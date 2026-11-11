# FCourt GitOps

Cấu hình Kubernetes mà Argo CD đồng bộ vào cluster EKS `fcourt-prod` (một môi trường duy nhất). Gồm 12 Spring Boot service và `gateway-service` (điểm vào công khai duy nhất), cùng các add-on nền tảng: AWS Load Balancer Controller, StorageClass gp3, PostgreSQL (CloudNativePG), Kafka (Strimzi), Redis. Dùng Kustomize; Helm chart được cài bởi Argo CD Application với version cố định. Không có Eureka: service gọi nhau qua Kubernetes Service DNS.

Phân chia repo (xem `docs/adr/0001-three-repositories.md`): repo backend giữ code và CI image; `fcourt-infra` (Terraform, root `envs/prod`) tạo EKS, VPC, IAM, Pod Identity, S3 và SNS; repo này giữ manifest và image tag của từng service. Không lưu secret thật trong Git.

## Cấu trúc

```text
argocd/
  values.yaml              # Helm values cho Argo CD
  root-app.yaml            # Application gốc duy nhất (path: argocd), apply tay một lần
  kustomization.yaml       # nội dung root app: projects, platform, services ApplicationSet
  projects.yaml            # AppProject platform + services
  services-appset.yaml     # ApplicationSet: một App cho mỗi services/*
platform/
  aws-load-balancer-controller/   # Helm chart qua Application
  storage/                        # StorageClass gp3 (mặc định)
  postgres/                       # operator + cluster CloudNativePG (manifests/)
  kafka/                          # operator + Kafka + topics Strimzi (manifests/)
  redis/                          # Redis (manifests/)
services/
  _components/spring-service/     # Deployment, Service, ServiceAccount dùng chung
  _components/alb-ingress/        # Ingress ALB công khai (chỉ gateway dùng)
  <service>/                      # kustomization.yaml, configmap.yaml, deployment-env.yaml (nếu có secret)
scripts/                          # bootstrap-argocd.sh, create-secrets.sh, apply-terraform-outputs.sh, validate.sh, secrets.example/
docs/adr/                         # quyết định kiến trúc
```

## Luồng Argo CD

```text
scripts/bootstrap-argocd.sh  -->  argocd/root-app.yaml  (Application fcourt-root, path argocd)
                                       |
                                       |- wave -1  AppProjects (platform, services), StorageClass gp3
                                       |- wave  0  Applications nền tảng:
                                       |           aws-load-balancer-controller, cloudnative-pg (+operator),
                                       |           strimzi (+operator), redis
                                       '- wave  1  ApplicationSet fcourt-services
                                                   --> Application fcourt-<svc> cho mỗi services/* (trừ _components)
                                                       namespace fcourt-prod, automated prune + selfHeal
```

ApplicationSet chỉ được tạo sau khi các Application wave 0 healthy. Các App con sau đó reconcile song song; service tự retry kết nối DB/Kafka. Root và mọi App con đều có retry backoff giới hạn. Instance CloudNativePG/Strimzi dùng `SkipDryRunOnMissingResource=true` để CR được chấp nhận trước khi CRD của operator tồn tại.

## Luồng runtime

```text
client --> ALB (group fcourt-public, HTTP 80) --> gateway-service:8080 --http://<svc>:<port>--> các service (ClusterIP)

service --> PostgreSQL  fcourt-postgres-rw.data.svc.cluster.local:5432            (CloudNativePG, ns data)
        |-> Kafka       fcourt-kafka-kafka-bootstrap.data.svc.cluster.local:9092  (Strimzi, ns data)
        |-> Redis       redis.data.svc.cluster.local:6379
        '-> S3 (media bucket) và SNS (push) qua EKS Pod Identity, ServiceAccount = tên service
```

- Gateway kiểm tra JWT (JWKS từ `auth-service`) rồi route theo path tới `http://<svc>:<port>` (instance tĩnh cấu hình trong backend). Mọi service khác chỉ là ClusterIP.
- Pod Identity association do `fcourt-infra` tạo; ServiceAccount có cùng tên với service (từ `_components/spring-service`).
- S3: `auth`, `discovery`, `facility`, `booking`, `payment` có `STORAGE_S3_BUCKET`, `STORAGE_S3_REGION`, `STORAGE_PUBLIC_BASE_URL` (bucket `fcourt-prod-media-870853685410`).
- PostgreSQL tạo 11 database; service kết nối bằng user `postgres`, mật khẩu từ Secret `fcourt-postgres-superuser` (key `password`). Redis dùng `emptyDir`, không mật khẩu. Kafka plain nội bộ, topic khai báo bằng `KafkaTopic` trong `platform/kafka/manifests/topics.yaml`. Không HA, không backup.

Debug:

```sh
kubectl -n data port-forward svc/fcourt-postgres-rw 5432:5432
kubectl -n data port-forward svc/redis 6379:6379
kubectl -n data port-forward svc/fcourt-kafka-kafka-bootstrap 9092:9092
```

## Một service được dựng thế nào

`services/_components/spring-service` chứa Deployment, Service, ServiceAccount dùng chung (non-root, root filesystem read-only, probe `/actuator/health`, resource, startupProbe 5 phút). Tên resource, `envFrom` và port được điền bằng Kustomize replacements từ ConfigMap của service (label `app.kubernetes.io/name`, `metadata.name`, `SERVER_PORT`). `services/<svc>/` chỉ chứa:

- `configmap.yaml`: `<svc>-config` với label `app.kubernetes.io/name: <svc>`, `SERVER_PORT` và biến môi trường Spring.
- `deployment-env.yaml` (tuỳ chọn): các `env` tham chiếu Secret `<svc>-secrets`.
- `kustomization.yaml`: namespace `fcourt-prod`, components, mục `images:` cho `870853685410.dkr.ecr.ap-southeast-1.amazonaws.com/fcourt/<svc>` và một patch gắn image đó vào container để `kustomize edit set image` hoạt động.

## Thêm một service

1. Tạo `services/<svc>/configmap.yaml` (port chưa dùng) và `kustomization.yaml` (copy từ service có sẵn, đổi tên và image).
2. Cần secret thì thêm `deployment-env.yaml` và key vào `scripts/secrets.example/`.
3. Thêm route và URL instance của service trong `gateway-service` ở fcourt-backend. Không thêm Ingress.
4. `bash scripts/validate.sh`. ApplicationSet tự phát hiện `services/*`.

## Cập nhật image

CI của fcourt-backend (`build-push-images.yml`) push `:<short-sha>` và `:dev`, rồi chạy `kustomize edit set image <repo>=<repo>:<short-sha>` trong `services/<svc>` và commit vào `main`; Argo CD sync commit mới. Không dùng `latest`.

## Bring-up (sau `terraform apply` của `fcourt-infra/envs/prod`)

Chạy từ repo này với `AWS_PROFILE=tpn12`, `kubectl` trỏ vào cluster (`aws eks update-kubeconfig --name fcourt-prod`), có `helm`, `terraform`, `jq`.

1. `bash scripts/apply-terraform-outputs.sh` đọc output `gitops_values`, ghi VPC id (ALB controller), SNS ARN (notification-service), bucket và public base URL S3, rồi push lên `main`.
2. `bash scripts/create-secrets.sh --generate` tạo namespace `data`, `fcourt-prod` và các Secret từ `~/.fcourt/secrets/<secret>.env` (xem `scripts/secrets.example/`). Giá trị ngẫu nhiên được tự sinh; PayOS và SMTP phải điền trước.
3. `export GITOPS_REPO_USERNAME=... GITOPS_REPO_TOKEN=...` (PAT fine-grained, Contents read-only) rồi `bash scripts/bootstrap-argocd.sh`: cài Argo CD chart `10.13.1`, lưu credential repo, hạ StorageClass `gp2` và apply `argocd/root-app.yaml`.
4. Theo dõi `kubectl -n argocd get applications`.

Còn phải chọn: `NOTIFICATION_SMTP_HOST`, `NOTIFICATION_RESET_PASSWORD_URL` (đang `<SET_...>`), `PAYOS_RETURN_URL`, `PAYOS_CANCEL_URL` (đang rỗng); `SUBSCRIPTION_BASE_URL` và `DISCOVERY_BASE_URL` của facility-service đang rỗng.

## Kiểm tra cục bộ

```sh
bash scripts/validate.sh
```

Render mọi entry point Kustomize (argocd, platform, từng service) bằng `kustomize` hoặc `kubectl kustomize`, và đếm Deployment (kỳ vọng 13). Không cần cluster hay AWS.

## Gateway routes

Gateway sở hữu Ingress duy nhất (path `/`). Tham chiếu route (từ controller trong `fcourt-backend`, cộng `/devices`); không route `/api/internal/**`, `/actuator/**` của service khác, `/.well-known/jwks.json`, gRPC của slot-hold-engine.

| Path | Service | Port |
|---|---|---|
| `/api/auth`, `/api/super-admin/court-admins`, `/api/super-admin/users`, `/api/super-admin/stats/accounts`, `/api/super-admin/stats/owner-names` | auth-service | 8081 |
| `/api/subscriptions`, `/api/subscription-plans`, `/api/court-types`, `/api/super-admin/stats/saas-revenue` | subscription-service | 8082 |
| `/api/public/branches/*` (chi tiết, `/images`, `/courts`), `/api/admin/branches`, `/api/admin/courts`, `/api/admin/time-slot-templates`, `/api/staff/branches`, `/api/staff/courts` | facility-service | 8083 |
| `/api/admin/dashboard`, `/api/super-admin/dashboard` | reporting-service | 8084 |
| `/api/public/branches` (list), `/api/public/branches/*/reviews`, `/api/public/courts`, `/api/reviews`, `/api/admin/reviews` | discovery-service | 8085 |
| `/api/vouchers`, `/api/admin/vouchers` | voucher-service | 8086 |
| `/api/bookings/hold-slots` | slot-hold-engine | 8087 |
| `/api/bookings`, `/api/admin/bookings`, `/ws-fcourt` (WebSocket/STOMP) | booking-service | 8088 |
| `/api/payments`, `/api/refunds`, `/api/admin/payments`, `/api/admin/refunds` | payment-service | 8089 |
| `/api/staff/schedule`, `/check-in`, `/offline`, `/me`, `/walk-in`, `/bookings`, `/api/admin/staff` | staff-operations-service | 8090 |
| `/devices` | notification-service | 8091 |
| `/api/staff/pos`, `/api/admin/pos` | pos-retail-service | 8092 |

Thứ tự ưu tiên: Spring Cloud Gateway lấy route khớp đầu tiên, nên `/api/bookings/hold-slots` phải đứng trước `/api/bookings`, và các route reviews/list của discovery phải đứng trước wildcard `/api/public/branches/*` của facility. `/ws-fcourt` cần WebSocket upgrade tới booking-service; Ingress đặt `idle_timeout.timeout_seconds=3600` và `deregistration_delay.timeout_seconds=60`. `pos-retail-service` dùng 8092 để tránh trùng 8091 của notification-service.
