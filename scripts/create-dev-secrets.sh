#!/usr/bin/env bash
# Creates the Kubernetes Secrets the dev services reference. Values never live in Git.
#
# Source directory (default ~/.fcourt/dev-secrets, override with FCOURT_SECRETS_DIR) holds one KEY=VALUE file per
# Secret, named <secret>.env (for example auth-service-secrets.env). scripts/dev-secrets.example/ lists the keys.
# With --generate, keys that can be random (JWT/gRPC keys, internal tokens, Postgres password) are generated when
# missing; third-party keys (Cloudinary, PayOS, SMTP) must always come from you.
#
#   bash scripts/create-dev-secrets.sh --generate
#
# Idempotent (kubectl apply). Run after the cluster exists, before Argo CD syncs the services.
set -euo pipefail

dir=${FCOURT_SECRETS_DIR:-$HOME/.fcourt/dev-secrets}
generate=false
[ "${1:-}" = "--generate" ] && generate=true
mkdir -p "$dir"
chmod 700 "$dir" 2>/dev/null || true

rand() { openssl rand -hex 24; }
# PEM keys are stored on one line with literal \n so --from-env-file keeps them intact.
pem() { openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 2>/dev/null | awk '{printf "%s\\n",$0}'; }
getval() { grep "^$2=" "$dir/$1.env" 2>/dev/null | head -n1 | cut -d= -f2- || true; }
# Append KEY=VALUE to <secret>.env when KEY is missing (generate mode only). Value is a command evaluated lazily.
ensure() {
  local file="$dir/$1.env" key=$2
  touch "$file"
  chmod 600 "$file" 2>/dev/null || true
  if ! grep -q "^$key=" "$file"; then
    printf '%s=%s\n' "$key" "$("${@:3}")" >> "$file"
  fi
}

if $generate; then
  ensure fcourt-postgres-superuser password rand
  pg=$(getval fcourt-postgres-superuser password)
  ensure discovery-service-secrets DISCOVERY_INTERNAL_SLOT_TOKEN rand
  ensure discovery-service-secrets DISCOVERY_DB_PASSWORD echo "$pg"
  ensure facility-service-secrets DISCOVERY_INTERNAL_SLOT_TOKEN echo "$(getval discovery-service-secrets DISCOVERY_INTERNAL_SLOT_TOKEN)"
  ensure facility-service-secrets FACILITY_DB_PASSWORD echo "$pg"
  ensure facility-service-secrets FACILITY_RESERVATION_TOKEN rand
  ensure pos-retail-service-secrets POS_BOOKING_SERVICE_TOKEN rand
  ensure pos-retail-service-secrets POS_SETTLEMENT_SERVICE_TOKEN rand
  ensure voucher-service-secrets VOUCHER_GRPC_TOKEN rand
  ensure auth-service-secrets AUTH_JWT_PRIVATE_KEY pem
  ensure voucher-service-secrets VOUCHER_GRPC_PRIVATE_KEY pem
fi

for ns in data fcourt-dev; do kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -; done

shopt -s nullglob
count=0
for file in "$dir"/*.env; do
  name=$(basename "$file" .env)
  [ -s "$file" ] || { echo "skip $name (empty file)"; continue; }
  if [ "$name" = "fcourt-postgres-superuser" ]; then
    # CloudNativePG reads it in namespace data (needs username too); services read the same name in fcourt-dev.
    pw=$(getval "$name" password)
    kubectl -n data create secret generic "$name" --type=kubernetes.io/basic-auth \
      --from-literal=username=postgres --from-literal=password="$pw" --dry-run=client -o yaml | kubectl apply -f -
    kubectl -n fcourt-dev create secret generic "$name" \
      --from-literal=password="$pw" --dry-run=client -o yaml | kubectl apply -f -
  else
    kubectl -n fcourt-dev create secret generic "$name" --from-env-file="$file" --dry-run=client -o yaml | kubectl apply -f -
  fi
  count=$((count + 1))
done
echo "Applied $count Secret(s). Missing third-party keys? Compare with scripts/dev-secrets.example/."
