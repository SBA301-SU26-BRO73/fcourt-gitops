#!/usr/bin/env bash
# The values known only after `terraform apply`: the VPC id (AWS Load Balancer Controller), the SNS platform
# application ARN (notification-service), and the media bucket name and public base URL (auth, facility, discovery,
# payment, booking). Reads the `gitops_values` output of fcourt-infra/envs/prod, writes the values into this repo,
# then commits and pushes to main because Argo CD syncs from main.
#
#   AWS_PROFILE=tpn12 bash scripts/apply-terraform-outputs.sh
set -euo pipefail

command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }
root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
infra=${FCOURT_INFRA_DIR:-$root_dir/../fcourt-infra}
values=$(terraform -chdir="$infra/envs/prod" output -json gitops_values)
val() { jq -er ".$1" <<<"$values"; }

vpc_id=$(val vpc_id)
sns_arn=$(val push_platform_application_arn)
media_bucket=$(val media_bucket_name)
media_url=$(val media_public_base_url)

alb=platform/aws-load-balancer-controller/application.yaml
notif=services/notification-service/config.env
sed -i "s|^\(        vpcId: \).*|\1\"$vpc_id\"|" "$root_dir/$alb"
sed -i "s|^PUSH_SNS_PLATFORM_APPLICATION_ARN=.*|PUSH_SNS_PLATFORM_APPLICATION_ARN=$sns_arn|" "$root_dir/$notif"

media_files=()
for svc in auth facility discovery payment booking; do
  cm="services/$svc-service/config.env"
  sed -i -e "s|^STORAGE_S3_BUCKET=.*|STORAGE_S3_BUCKET=$media_bucket|" -e "s|^STORAGE_PUBLIC_BASE_URL=.*|STORAGE_PUBLIC_BASE_URL=$media_url|" "$root_dir/$cm"
  media_files+=("$cm")
done

git -C "$root_dir" add "$alb" "$notif" "${media_files[@]}"
git -C "$root_dir" commit -m "chore(prod): set VPC id, SNS ARN and media bucket from terraform outputs"
git -C "$root_dir" push origin HEAD:main
