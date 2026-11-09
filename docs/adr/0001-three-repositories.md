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

## Root sync ordering

The root Application at `bootstrap/root-app.yaml` manages `argocd/`. That Kustomize root includes AppProjects at sync-wave `-1`, the platform add-on Application manifests directly at wave `0`, and the services ApplicationSet at wave `1`. Since Argo CD processes sync waves and waits for wave resources to become healthy before advancing, platform Application health gates creation/sync of the services ApplicationSet. The platform Application CRs are in namespace `argocd`; their chart destinations are their workload namespaces such as `kube-system` and `external-secrets`. Root and child Applications use bounded retry backoff.

This orders the resources the root directly manages. An ApplicationSet does not wait for the health of generated Applications; service Applications may reconcile concurrently after generation. Progressive syncs with RollingSync are a possible later option but are not enabled.

## Root sync ordering

The root Application at `bootstrap/root-app.yaml` manages `argocd/`. That Kustomize root includes AppProjects at sync-wave `-1`, the platform add-on Application manifests directly at wave `0`, and the services ApplicationSet at wave `1`. Argo CD waits for the health of wave 0 Application resources before advancing. The platform Application CRs live in namespace `argocd`; their chart destinations are workload namespaces such as `kube-system` and `external-secrets`. Root and child Applications use bounded retry backoff.

This orders resources the root directly manages. An ApplicationSet does not wait for the health of generated Applications; service Applications may reconcile concurrently. Progressive syncs with RollingSync are a possible later option but are not enabled.
