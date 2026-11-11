#!/usr/bin/env bash
# Installs Argo CD (pinned Helm chart, dex and notifications off), registers the private gitops repo with a
# credential read from the environment, then applies the root Application. Run once per new cluster.
#
#   export GITOPS_REPO_USERNAME=<github user>   # any non-empty value works for a fine-grained token
#   export GITOPS_REPO_TOKEN=<fine-grained PAT, Contents read-only, repo fcourt-gitops only>
#   bash scripts/bootstrap-argocd.sh
#
# Never commit the token. It only lives in the argocd/repo-fcourt-gitops Secret in the cluster.
set -euo pipefail

CHART_VERSION=${ARGOCD_CHART_VERSION:-10.13.1} # appVersion v3.6.1
REPO_URL=https://github.com/SBA301-SU26-BRO73/fcourt-gitops.git
root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

: "${GITOPS_REPO_USERNAME:?set GITOPS_REPO_USERNAME}"
: "${GITOPS_REPO_TOKEN:?set GITOPS_REPO_TOKEN}"
command -v helm >/dev/null || { echo "helm is required" >&2; exit 1; }

helm repo add argo https://argoproj.github.io/argo-helm >/dev/null
helm repo update argo >/dev/null
helm upgrade --install argocd argo/argo-cd --version "$CHART_VERSION" \
  --namespace argocd --create-namespace \
  -f "$root_dir/argocd/values.yaml" --wait --timeout 10m

kubectl -n argocd create secret generic repo-fcourt-gitops \
  --from-literal=type=git --from-literal=url="$REPO_URL" \
  --from-literal=username="$GITOPS_REPO_USERNAME" --from-literal=password="$GITOPS_REPO_TOKEN" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n argocd label secret repo-fcourt-gitops argocd.argoproj.io/secret-type=repository --overwrite

# EKS ships gp2 as the default StorageClass; gp3 (from this repo) must be the only default.
if kubectl get sc gp2 >/dev/null 2>&1; then
  kubectl patch sc gp2 -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
fi

kubectl apply -n argocd -f "$root_dir/argocd/root-app.yaml"
echo "Argo CD installed. UI: kubectl -n argocd port-forward svc/argocd-server 8080:80"
echo "Admin password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath={.data.password} | base64 -d"
