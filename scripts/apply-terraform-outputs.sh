#!/usr/bin/env bash
# The values known only after `terraform apply`: the VPC id (AWS Load Balancer Controller), the SNS platform
# application ARN (notification-service), and the media bucket name and public base URL (auth, facility, discovery,
# payment, booking). Reads fcourt-infra/envs/dev outputs, writes them into this repo, then
# commits and pushes to main because Argo CD syncs from main.
#
#   AWS_PROFILE=tpn12 bash scripts/apply-terraform-outputs.sh
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
infra=${FCOURT_INFRA_DIR:-$root_dir/../fcourt-infra}
tf() { terraform -chdir="$infra/envs/dev" output -raw "$1"; }

vpc_id=$(tf vpc_id)
sns_arn=$(tf push_platform_application_arn)
media_bucket=$(tf media_bucket_name)
media_url=$(tf media_public_base_url)

sed -i "s|^\(        vpcId: \).*|\1\"$vpc_id\"|" "$root_dir/platform/aws-load-balancer-controller/application.yaml"
sed -i "s|^\(  PUSH_SNS_PLATFORM_APPLICATION_ARN: \).*|\1'$sns_arn'|" "$root_dir/services/notification-service/base/configmap.yaml"

media_files=()
for svc in auth facility discovery payment booking; do
  cm="services/$svc-service/base/configmap.yaml"
  sed -i -e "s|^\(  STORAGE_S3_BUCKET: \).*|\1'$media_bucket'|" -e "s|^\(  STORAGE_PUBLIC_BASE_URL: \).*|\1'$media_url'|" "$root_dir/$cm"
  media_files+=("$cm")
done

git -C "$root_dir" add platform/aws-load-balancer-controller/application.yaml services/notification-service/base/configmap.yaml "${media_files[@]}"
git -C "$root_dir" commit -m "chore(dev): set VPC id, SNS ARN and media bucket from terraform outputs"
git -C "$root_dir" push origin HEAD:main
