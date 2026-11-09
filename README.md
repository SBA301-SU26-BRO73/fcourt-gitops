# FCourt GitOps cho EKS

Repository này chứa cấu hình triển khai Kubernetes mà ArgoCD theo dõi cho 12 service FCourt và một số add-on nền tảng. Repo ứng dụng chứa mã nguồn và CI build image; repo này giữ manifest và tag image; repo `fcourt-infra` tạo EKS, mạng, IAM và EKS Pod Identity associations. Không lưu secret thật trong Git.

## Cấu trúc

```text
bootstrap/root-app.yaml       # Application gốc, apply thủ công một lần
argocd/projects/              # AppProject platform và services
argocd/appsets/               # ApplicationSet cho platform và services dev
platform/apps/                # Application cài add-on Helm đã pin phiên bản
services/<service>/base/      # Deployment, Service, ConfigMap, ServiceAccount
services/<service>/overlays/  # Cấu hình dev đang chạy; prod là khung chưa bật
docs/                         # ADR về ranh giới ba repository
scripts/validate.sh           # Dựng Kustomize và kiểm tra YAML qua kubectl
```

## Cấu trúc ArgoCD cha/con

```text
kubectl apply -n argocd -f bootstrap/root-app.yaml
                    |
                    v
              fcourt-root
                    |
          argocd/kustomization.yaml
             /              \
      AppProjects       ApplicationSets
                          /          \
                 platform/apps/*   services/*/overlays/dev
                     wave 0             wave 10
                       |                   |
                Helm add-ons         12 service apps
```

Platform được gắn sync-wave `0`, service `10` để thể hiện thứ tự phụ thuộc. ApplicationSet dev chỉ tìm `services/*/overlays/dev`; thư mục prod đã có nhưng chưa được generator theo dõi hoặc đồng bộ.

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
- Ingress gộp vào ALB `fcourt-public`: `/api/auth`, `/api/subscriptions`, `/api/facilities`, `/api/discovery`, `/api/vouchers`, `/api/bookings`, `/api/payments` và `/devices`. Ba nhóm auth/booking/payment có ví dụ trong system-test; các prefix còn lại suy ra từ API service. Sibling repo hiện không có gateway route config trong `docker/`, cần đối chiếu gateway thật trước khi mở ALB internet-facing.
- Health probe dùng `/actuator/health` theo cấu hình Spring Boot; xác nhận actuator có mặt trong image đã build.
- `pos-retail-service` và `notification-service` đều khai báo cổng mặc định `8091`. Manifest POS đặt `SERVER_PORT` và container/service port thành `8092` để tránh xung đột.
- Chart version được pin nhưng chưa kiểm chứng với phiên bản Kubernetes/IAM/VPC của EKS FCourt. Xem `platform/README.md`.

## Kiểm tra cục bộ

```sh
bash scripts/validate.sh
```

Kiểm tra chỉ render Kustomize và parse manifest bằng kubectl cục bộ; không cần hoặc truy cập cluster/AWS.
