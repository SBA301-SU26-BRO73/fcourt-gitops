# Bring-up runbook

Vietnamese notes, moved from the README.

## Bring-up (sau `terraform apply` của `fcourt-infra/envs/prod`)

Chạy từ repo này với `AWS_PROFILE=tpn12`, `kubectl` trỏ vào cluster (`aws eks update-kubeconfig --name fcourt-prod`), có `helm`, `terraform`, `jq`.

1. `bash scripts/apply-terraform-outputs.sh` đọc output `gitops_values`, ghi VPC id (ALB controller), SNS ARN (notification-service), bucket và public base URL S3, rồi push lên `main`.
2. `bash scripts/create-secrets.sh --generate` tạo namespace `data`, `fcourt-prod` và các Secret từ `~/.fcourt/secrets/<secret>.env` (xem `scripts/secrets.example/`). Giá trị ngẫu nhiên được tự sinh; PayOS và SMTP phải điền trước.
3. `bash scripts/bootstrap-argocd.sh`: cài Argo CD chart `10.13.1`, hạ StorageClass `gp2`, apply `argocd/root-app.yaml`, rồi chờ Load Balancer Controller lên và chép CA từ secret `aws-load-balancer-tls` vào webhook (`scripts/fix-lb-webhook-ca.sh`; thiếu bước này Ingress sync lỗi x509). Repo public nên không cần token; nếu repo chuyển private thì `export GITOPS_REPO_TOKEN=...` (PAT fine-grained, Contents read-only) trước khi chạy.
4. Theo dõi `kubectl -n argocd get applications`.
5. Khi Ingress `gateway-service` đã có địa chỉ ALB, chạy `sh ../fcourt-infra/scripts/update-origin-record.sh` để cập nhật CNAME `origin.fcourt.donan.site` (origin API của CloudFront) trỏ vào ALB mới. ALB đổi hostname sau mỗi lần up/down nên bước này bắt buộc để `https://fcourt.donan.site/api` hoạt động.

Còn phải chọn: `NOTIFICATION_SMTP_HOST`, `NOTIFICATION_RESET_PASSWORD_URL` (đang `<SET_...>`), `PAYOS_RETURN_URL`/`PAYOS_CANCEL_URL` đã trỏ `https://fcourt.donan.site/admin/subscriptions/payment-result` (không phải secret, nằm trong ConfigMap subscription-service); `SUBSCRIPTION_BASE_URL` và `DISCOVERY_BASE_URL` của facility-service đang rỗng.

