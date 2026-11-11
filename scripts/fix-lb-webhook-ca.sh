#!/usr/bin/env bash
# The AWS Load Balancer Controller chart generates its webhook CA at render time. Argo CD can render the
# TLS secret and the webhook configurations in different passes, so caBundle may not match the secret and
# every Ingress/Service admission call fails (x509). Copy the CA from the secret into both webhook
# configurations; the Application ignores caBundle, so Argo CD keeps the patched value.
# Usage: bash scripts/fix-lb-webhook-ca.sh   (safe to re-run)
set -euo pipefail

NS=kube-system
SECRET=aws-load-balancer-tls
WEBHOOK=aws-load-balancer-webhook
TIMEOUT=${TIMEOUT:-900}

waited=0
until kubectl -n "$NS" get secret "$SECRET" >/dev/null 2>&1 \
  && kubectl get mutatingwebhookconfiguration "$WEBHOOK" >/dev/null 2>&1 \
  && kubectl get validatingwebhookconfiguration "$WEBHOOK" >/dev/null 2>&1; do
  if [ "$waited" -ge "$TIMEOUT" ]; then
    echo "Timed out waiting for $SECRET and $WEBHOOK; run this script again later." >&2
    exit 1
  fi
  sleep 10
  waited=$((waited + 10))
done

ca=$(kubectl -n "$NS" get secret "$SECRET" -o jsonpath='{.data.ca\.crt}')
if [ -z "$ca" ]; then
  echo "$SECRET has no ca.crt" >&2
  exit 1
fi

changed=0
for kind in mutatingwebhookconfiguration validatingwebhookconfiguration; do
  current=$(kubectl get "$kind" "$WEBHOOK" -o jsonpath='{range .webhooks[*]}{.clientConfig.caBundle}{"\n"}{end}')
  count=$(printf '%s\n' "$current" | grep -c . || true)
  for i in $(seq 0 $((count - 1))); do
    if [ "$(printf '%s\n' "$current" | sed -n "$((i + 1))p")" != "$ca" ]; then
      kubectl patch "$kind" "$WEBHOOK" --type=json \
        -p "[{\"op\":\"replace\",\"path\":\"/webhooks/$i/clientConfig/caBundle\",\"value\":\"$ca\"}]" >/dev/null
      changed=1
    fi
  done
done

if [ "$changed" -eq 1 ]; then
  kubectl -n "$NS" rollout restart deployment/aws-load-balancer-controller
  echo "Webhook caBundle patched from $SECRET; controller restarted."
else
  echo "Webhook caBundle already matches $SECRET."
fi
