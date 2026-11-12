# Service layout, adding a service, updating images

Vietnamese notes, moved from the README.

## Một service được dựng thế nào

`services/_components/spring-service` chứa Deployment, Service, ServiceAccount dùng chung (non-root, root filesystem read-only, probe `/actuator/health`, resource, startupProbe 5 phút). Tên resource, `envFrom` và port được điền bằng Kustomize replacements từ ConfigMap của service (label `app.kubernetes.io/name`, `metadata.name`, `SERVER_PORT`). `services/<svc>/` chỉ chứa:

- `config.env`: các dòng `KEY=VALUE` (không thêm dấu nháy), gồm `SERVER_PORT` và biến môi trường Spring; chú thích nằm trên dòng riêng.
- `deployment-env.yaml` (tuỳ chọn): các `env` tham chiếu Secret `<svc>-secrets`.
- `kustomization.yaml`: namespace `fcourt-prod`, components, `configMapGenerator` tên logic `<svc>-config` (`behavior: create`, `envs: [config.env]`, label `app.kubernetes.io/name: <svc>`), mục `images:` cho `870853685410.dkr.ecr.ap-southeast-1.amazonaws.com/fcourt/<svc>` và một patch gắn image đó vào container để `kustomize edit set image` hoạt động.

Kustomize thêm content hash vào tên ConfigMap và tự cập nhật `envFrom.configMapRef.name` qua component. Khi giá trị trong `config.env` thay đổi, pod template đổi nên Deployment tự rollout khi Argo CD sync. Không tắt name suffix hash. Kết quả so sánh cả 13 service: [configmap-rollout-verification.md](../validation/configmap-rollout-verification.md). Đề xuất TLS cho lỗi staff walk-in A11: [a11-counter-grpc-tls-proposal.md](../proposals/a11-counter-grpc-tls-proposal.md).

## Thêm một service

1. Tạo `services/<svc>/config.env` (port chưa dùng) và `kustomization.yaml` (copy từ service có sẵn, đổi tên generator, label và image).
2. Cần secret thì thêm `deployment-env.yaml` và key vào `scripts/secrets.example/`.
3. Thêm route và URL instance của service trong `gateway-service` ở fcourt-backend. Không thêm Ingress.
4. `bash scripts/validate.sh`. ApplicationSet tự phát hiện `services/*`.

## Cập nhật image

CI của fcourt-backend (`build-push-images.yml`) push `:<short-sha>` và `:latest`, rồi chạy `kustomize edit set image <repo>=<repo>:<short-sha>` trong `services/<svc>` và commit vào `main`; Argo CD sync commit mới. Gitops luôn ghim tag SHA; `latest` chỉ là giá trị khởi tạo trước lần build đầu tiên.

