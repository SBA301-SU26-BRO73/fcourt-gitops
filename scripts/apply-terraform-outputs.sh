#!/usr/bin/env bash
# The only two values known after `terraform apply`: the VPC id (AWS Load Balancer Controller) and the SNS platform
# application ARN (notification-service). Reads fcourt-infra/envs/dev outputs, writes them into this repo, then
# commits and pushes to main because Argo CD syncs from main.
#
#   AWS_PROFILE=tpn12 bash scripts/apply-terraform-outputs.sh
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
infra=${FCOURT_INFRA_DIR:-$root_dir/../fcourt-infra}
tf() { terraform -chdir="$infra/envs/dev" output -raw "$1"; }

vpc_id=$(tf vpc_id)
sns_arn=$(tf push_platform_application_arn)

sed -i "s|^\(        vpcId: \).*|\1\"$vpc_id\"|" "$root_dir/platform/aws-load-balancer-controller/application.yaml"
sed -i "s|^\(  PUSH_SNS_PLATFORM_APPLICATION_ARN: \).*|\1'$sns_arn'|" "$root_dir/services/notification-service/base/configmap.yaml"

git -C "$root_dir" add platform/aws-load-balancer-controller/application.yaml services/notification-service/base/configmap.yaml
git -C "$root_dir" commit -m "chore(dev): set VPC id and SNS platform application ARN from terraform outputs"
git -C "$root_dir" push origin HEAD:main
