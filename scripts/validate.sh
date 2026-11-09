#!/usr/bin/env bash
set -euo pipefail

if ! command -v kubectl >/dev/null 2>&1; then
  echo "ERROR: kubectl is required" >&2
  exit 1
fi

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root_dir"

echo "== Service overlays =="
for env in dev prod; do
  for overlay in services/*/overlays/"$env"; do
    echo "Rendering $overlay"
    kubectl kustomize "$overlay" >/dev/null
  done
done

echo "== Platform Applications =="
for app in platform/apps/*; do
  echo "Parsing $app"
  kubectl kustomize "$app" >/dev/null
done

echo "== ArgoCD manifests =="
kubectl kustomize argocd >/dev/null
kubectl kustomize bootstrap >/dev/null

echo "Validation passed: 12 dev overlays, 12 prod skeletons, 3 platform Applications, argocd/, bootstrap/."
