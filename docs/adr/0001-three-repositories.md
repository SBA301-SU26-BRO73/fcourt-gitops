# ADR 0001: Tách mã ứng dụng, hạ tầng và cấu hình GitOps

## Trạng thái

Đề xuất cho triển khai EKS FCourt.

## Quyết định

Chia trách nhiệm thành ba repository: repository backend giữ mã nguồn và pipeline build/test image; `fcourt-infra` quản lý EKS, mạng, IAM và EKS Pod Identity associations; `fcourt-gitops` giữ Kubernetes manifests, cấu hình ArgoCD và image tag đang triển khai.

## Lý do

- Quyền và vòng đời hạ tầng khác với quyền phát hành ứng dụng.
- ArgoCD cần một nguồn khai báo riêng để đối chiếu trạng thái cluster với Git và cho phép rollback bằng lịch sử Git.
- CI có thể cập nhật tag trong GitOps repo mà không cần quyền thay đổi hạ tầng hay truy cập trực tiếp cluster.
- Secret không đi vào repo; workload dùng tên Kubernetes Secret, còn External Secrets và Pod Identity được cấu hình với IAM từ `fcourt-infra`.

## Hệ quả

Ba repo cần quy ước chung cho tên service, tag image, biến môi trường, tên Secret và quy trình review. Cần cấu hình quyền Git đọc repo cho ArgoCD và quyền cập nhật overlay cho CI.
