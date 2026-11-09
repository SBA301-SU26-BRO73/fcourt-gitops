# FCourt GitOps cho EKS

Repository này chứa cấu hình triển khai Kubernetes mà ArgoCD theo dõi cho 12 service FCourt và một số add-on nền tảng. Repo ứng dụng chứa mã nguồn và CI build image; repo này giữ manifest và tag image; repo `fcourt-infra` tạo EKS, mạng, IAM và EKS Pod Identity associations. Không lưu secret thật trong Git.

## Cấu trúc

```text
bootstrap/root-app.yaml       # Application gốc, apply thủ công một lần
argocd/projects/              # AppProject platform và services
argocd/appsets/               # ApplicationSet cho services dev; platform Apps trực tiếp
platform/apps/                # Application cài add-on Helm đã pin phiên bản
services/<service>/base/      # Deployment, Service, ConfigMap, ServiceAccount
services/<service>/overlays/  # Cấu hình dev đang chạy; prod là khung chưa bật
docs/                         # ADR về ranh giới ba repository
scripts/validate.sh           # Dựng Kustomize và kiểm tra YAML qua kubectl
```

## Cấu trúc ArgoCD cha/con

```text
fcourt-root (path argocd)
  ├─ AppProjects                         wave -1
  ├─ platform add-on Applications       wave 0 (wait for app health)
  └─ services ApplicationSet            wave 1
```

Root app orders resources it directly manages: AppProjects at `-1`, direct platform Application resources at `0`, then the services ApplicationSet at `1`. Argo CD waits for health of the wave 0 Applications before advancing. Retry is configured for root and child Apps. Limitation: the ApplicationSet resource does not wait for health of the Applications it generates, so service Apps are not serialized by readiness. Progressive syncs (RollingSync) may be considered later; they are not enabled. The dev generator discovers `services/*/overlays/dev`, so adding a service remains a folder-only change; prod is not currently generated.
## Khởi tạo ArgoCD

1. Cài ArgoCD vào cluster EKS bằng quy trình phát hành đã được đội xác nhận.
2. Thay `https://github.com/SBA301-SU26-BRO73/fcourt-gitops.git` trong `bootstrap/root-app.yaml`, `argocd/projects/` và `argocd/appsets/` bằng URL Git thật. Xác nhận branch `main` tồn tại và ArgoCD có quyền đọc repo.
3. Apply Application gốc một lần:

   ```sh
   kubectl create namespace argocd
   kubectl apply -n argocd -f bootstrap/root-app.yaml
   ```

4. Điền cluster name, AWS region, VPC ID và xác nhận IAM/Helm values ở `platform/apps/` trước khi bật sync add-on. EKS Pod Identity associations được tạo bởi repo `fcourt-infra`.

## Thêm service

Tạo `services/<service>/base/` với Deployment, Service, ConfigMap, ServiceAccount và `kustomization.yaml`; thêm `overlays/dev/` và `overlays/prod/` với Kustomization theo cấu trúc hiện có. ApplicationSet dev tự phát hiện thư mục `overlays/dev`, vì vậy không cần đăng ký service ở nơi khác. Đọc `application.yml` của service để khai báo đầy đủ biến môi trường, health path và port. Chỉ thêm Ingress cho API cần truy cập từ bên ngoài; các service còn lại dùng ClusterIP.

## Luồng cập nhật image

Image có dạng `<ECR_REGISTRY>/fcourt/<service>:<tag>`. CI build và đẩy image với tag bất biến, tốt nhất là commit SHA. Sau khi image sẵn sàng, CI cập nhật `images.newTag` trong `services/<service>/overlays/<env>/kustomization.yaml` bằng `kustomize edit set image`; ArgoCD tự sync từ commit Git. Không dùng `latest`.

## Cấu hình hiện tại và giả định cần xử lý

- Thay các giá trị `<...>` trước khi triển khai: URL repo, ECR registry/tag, endpoint database/Kafka/Redis, domain/TLS, cluster name, region và VPC ID.
- Secret chỉ tham chiếu tới Kubernetes Secret `<service>-secrets` và key tương ứng. External Secrets hiện mới cài operator; chưa có SecretStore/ExternalSecret hay tên secret/key đã xác nhận.
- Ingress prefixes are supported by backend controller mappings. The table below records route evidence; services without an Ingress have unverified external exposure intent. No gateway route config was found under `docker/`, `tools/` or `docs/`.

| Service | Public prefixes | Evidence file |
|---|---|---|
| auth-service | `/api/auth` | `auth-service/src/main/java/com/fcourt/auth/account/AuthController.java` |
| booking-service | `/api/bookings` | `booking-service/src/main/java/com/fcourt/booking/BookingController.java`, `OnlineBooking.java` |
| discovery-service | — (no ingress; exposure intent unverified) | `discovery-service/src/main/java/com/fcourt/discovery/controller/BranchController.java` |
| facility-service | — (no ingress; exposure intent unverified) | `facility-service/src/main/java/com/fcourt/facility/api/BranchController.java` |
| notification-service | `/devices` | `notification-service/src/main/java/com/fcourt/notification/device/DeviceController.java` |
| payment-service | `/api/payments` | `payment-service/src/main/java/com/fcourt/payment/CustomerPaymentsController.java`, `CheckoutController.java` |
| subscription-service | `/api/subscriptions` | `subscription-service/src/main/java/com/fcourt/subscription/billing/BillingController.java` |
| voucher-service | `/api/vouchers` | `voucher-service/src/main/java/com/fcourt/voucher/VoucherApplyController.java` |
| pos-retail-service | — (no ingress; exposure intent unverified) | `pos-retail-service/src/main/java/com/fcourt/pos/api/PosController.java` |
| reporting-service | — (no ingress; exposure intent unverified) | `reporting-service/src/main/java/com/fcourt/reporting/api/DashboardController.java` |
| staff-operations-service | — (no ingress; exposure intent unverified) | `staff-operations-service/src/main/java/com/fcourt/staff/api/StaffController.java` |
| slot-hold-engine | — (no ingress; exposure intent unverified) | `slot-hold-engine/src/main/java/com/fcourt/hold/HoldController.java` |
- Health probe dùng `/actuator/health` theo cấu hình Spring Boot; xác nhận actuator có mặt trong image đã build.
- `pos-retail-service` và `notification-service` đều khai báo cổng mặc định `8091`. Manifest POS đặt `SERVER_PORT` và container/service port thành `8092` để tránh xung đột.
- Chart version được pin nhưng chưa kiểm chứng với phiên bản Kubernetes/IAM/VPC của EKS FCourt. Xem `platform/README.md`.

## Kiểm tra cục bộ

```sh
bash scripts/validate.sh
```

Kiểm tra chỉ render Kustomize và parse manifest bằng kubectl cục bộ; không cần hoặc truy cập cluster/AWS.
