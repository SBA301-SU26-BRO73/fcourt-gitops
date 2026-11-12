# fcourt-gitops

Cấu hình Kubernetes mà Argo CD đồng bộ vào cluster EKS `fcourt-prod` (một môi trường duy nhất). Repo chứa manifest của các backend service FCourt và các add-on nền tảng chạy trong cluster. Mã ứng dụng nằm ở `fcourt-backend`; tài nguyên AWS nằm ở `fcourt-infra`. Repo này là nguồn sự thật cho những gì đang chạy trong cluster, gồm cả image tag của từng service. Không lưu secret thật ở đây.

## Vai trò trong hệ thống FCourt

| Repo | Trách nhiệm |
|---|---|
| `fcourt-backend` | Các microservice Spring Boot, và CI build, push image rồi commit image tag mới vào repo này |
| **fcourt-gitops** (repo này) | Argo CD app, add-on nền tảng, cấu hình Kustomize theo từng service |
| `fcourt-infra` | Terraform: VPC, EKS, ECR, S3, CloudFront, Route 53, ACM, SNS, IAM Pod Identity, budget |
| `fcourt-web` | Web frontend trên S3 + CloudFront (https://fcourt.donan.site) |
| `fcourt-flutter` | Ứng dụng Android |

Lý do dùng ba repo: [docs/architecture/adr/0001-three-repositories.md](docs/architecture/adr/0001-three-repositories.md).

## Công nghệ

Argo CD (Helm chart được pin trong `scripts/bootstrap-argocd.sh`), Kustomize, ApplicationSet. Add-on nền tảng: AWS Load Balancer Controller, gp3 StorageClass, PostgreSQL (CloudNativePG), Kafka (Strimzi), Redis. Service: 12 service Spring Boot cùng `gateway-service`, là điểm vào public duy nhất (ALB Ingress). Các service gọi nhau qua Kubernetes Service DNS.

## Cấu trúc dự án

```text
argocd/
  root-app.yaml            # Application gốc duy nhất (path: argocd), apply thủ công một lần
  kustomization.yaml       # nội dung root app: projects, platform, services ApplicationSet
  projects.yaml            # AppProject: platform, services
  services-appset.yaml     # ApplicationSet: mỗi services/* một Application
  values.yaml              # Helm values cho Argo CD
platform/
  aws-load-balancer-controller/  storage/  postgres/  kafka/  redis/
services/
  _components/spring-service/    # Deployment, Service, ServiceAccount dùng chung
  _components/alb-ingress/       # ALB Ingress public (chỉ gateway)
  <service>/                     # kustomization.yaml, config.env, deployment-env.yaml (nếu có secret)
scripts/                         # bootstrap, secret, output Terraform, validate, secrets.example/
docs/                            # xem docs/README.md
```

## Cách hoạt động

```text
scripts/bootstrap-argocd.sh --> argocd/root-app.yaml (Application fcourt-root, path argocd)
  wave -1  AppProjects, StorageClass gp3
  wave  0  aws-load-balancer-controller, cloudnative-pg-operator, strimzi-operator, redis
  wave  1  cloudnative-pg (Cluster), strimzi (Kafka)
  wave  2  ApplicationSet fcourt-services --> Application fcourt-<svc> cho mỗi services/*
           (namespace fcourt-prod, tự động prune và selfHeal)
```

Luồng runtime: `client -> ALB -> gateway-service:8080 -> http://<svc>:<port>`. Các service dùng PostgreSQL, Kafka và Redis trong namespace `data`, và truy cập S3, SNS qua EKS Pod Identity (tên ServiceAccount = tên service; các association do `fcourt-infra` tạo). Chi tiết hơn: [docs/architecture](docs/architecture/) và [docs/operations](docs/operations/).

## Yêu cầu

`kubectl` trỏ tới cluster, `helm`, `terraform`, `jq`, và AWS credentials có quyền truy cập cluster. Để render cục bộ chỉ cần `kustomize` hoặc `kubectl` (không cần cluster, không cần AWS).

## Tác vụ thường gặp

| Tác vụ | Lệnh hoặc vị trí |
|---|---|
| Validate toàn bộ manifest ở local | `bash scripts/validate.sh` (render mọi entry point Kustomize, kỳ vọng 13 Deployment) |
| Dựng cluster mới | sau khi `terraform apply` `fcourt-infra/envs/prod`: `scripts/apply-terraform-outputs.sh`, `scripts/create-secrets.sh --generate`, `scripts/bootstrap-argocd.sh`; runbook đầy đủ trong [docs/operations/bring-up.md](docs/operations/bring-up.md) |
| Theo dõi sync | `kubectl -n argocd get applications` |
| Mở giao diện Argo CD | `kubectl -n argocd port-forward svc/argocd-server 8080:80` |
| Thêm một service | [docs/operations/service-layout.md](docs/operations/service-layout.md) |
| Đường dẫn gateway theo từng service | [docs/architecture/gateway-routes.md](docs/architecture/gateway-routes.md) |

## Cấu hình

- Biến môi trường của từng service nằm trong `services/<svc>/config.env` (`KEY=VALUE`, không dùng dấu nháy). Kustomize băm tên ConfigMap, nên khi giá trị đổi thì Deployment được roll ở lần sync kế tiếp.
- Secret không bao giờ được commit. `scripts/create-secrets.sh` tạo Kubernetes Secret từ các file env cục bộ (template trong `scripts/secrets.example/`, file thật nằm dưới `~/.fcourt/secrets/`). Deployment của service tham chiếu Secret `<svc>-secrets` qua `deployment-env.yaml`.
- Các giá trị lấy từ Terraform (VPC id, SNS ARN, S3 bucket và public base URL) được ghi bởi `scripts/apply-terraform-outputs.sh`.

## CI/CD và triển khai

- Repo này không có CI workflow. Argo CD tự động sync nhánh `main`.
- Cập nhật image: workflow `build-push-images.yml` của `fcourt-backend` push `:<short-sha>`, chạy `kustomize edit set image` trong `services/<svc>` rồi commit lên `main`. Tag luôn được pin theo SHA.
- Sau khi dựng cluster mới, cập nhật bản ghi DNS `origin` của API (script `update-origin-record.sh` trong `fcourt-infra`), vì hostname của ALB đổi mỗi lần up/down. Xem runbook.
- Chạy `bash scripts/validate.sh` trước khi mở PR.

## Kiểm thử

Manifest được kiểm tra bằng cách render: `bash scripts/validate.sh`. Ghi chú xác minh cho các thay đổi trước đây: [docs/validation](docs/validation/).

## Đóng góp

- Tạo branch từ `main` với prefix như `feat/`, `fix/`, `docs/`, `chore/`; mở PR vào `main`.
- Commit message và tiêu đề PR viết bằng tiếng Anh (`type(scope): message`, ví dụ `chore(images): bump notification-service to <sha>`). Phần body có thể viết bằng tiếng Việt.
- Không commit secret, token hay file `.env` đã điền giá trị. Không tắt hậu tố hash trong tên ConfigMap.
