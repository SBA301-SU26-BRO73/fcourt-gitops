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

echo "== Bootstrap (one root Application per cluster) =="
for dir in bootstrap/*/; do render "${dir%/}"; done

echo "== Cluster entry points =="
for dir in clusters/*/; do render "${dir%/}"; done

echo "== Platform add-ons and dev-only data (Application wrappers) =="
for dir in platform/*/ platform/dev-data/*/; do
  [ -f "$dir/kustomization.yaml" ] && render "${dir%/}"
done

echo "== Dev-only data manifests synced by child Applications =="
for dir in platform/dev-data/*/*/; do
  [ -f "$dir/kustomization.yaml" ] && render "${dir%/}"
done

echo "== Services (every overlay) =="
for dir in services/*/overlays/*/; do render "${dir%/}"; done

echo "Validation passed: $count Kustomize targets rendered."
