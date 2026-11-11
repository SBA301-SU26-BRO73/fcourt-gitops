#!/usr/bin/env bash
# Renders every Kustomize entry point in the repository. Needs kubectl (or a
# standalone kustomize binary); no cluster or AWS access is used.
set -euo pipefail

if command -v kustomize >/dev/null 2>&1; then
  build=(kustomize build)
elif command -v kubectl >/dev/null 2>&1; then
  build=(kubectl kustomize)
else
  echo "ERROR: kustomize or kubectl is required" >&2
  exit 1
fi

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root_dir"

count=0
render() {
  echo "Rendering $1"
  "${build[@]}" "$1" >/dev/null
  count=$((count + 1))
}

echo "== Argo CD content (root Application path) =="
render argocd

echo "== Platform (Application wrappers and manifests synced by child Applications) =="
for dir in platform/*/ platform/*/manifests/; do
  [ -f "$dir/kustomization.yaml" ] && render "${dir%/}"
done

echo "== Services =="
deployments=0
for dir in services/*/; do
  case "$dir" in services/_components/) continue;; esac
  render "${dir%/}"
  deployments=$((deployments + $("${build[@]}" "${dir%/}" | grep -c '^kind: Deployment')))
done
echo "Deployments rendered: $deployments"

echo "Validation passed: $count Kustomize targets rendered."
