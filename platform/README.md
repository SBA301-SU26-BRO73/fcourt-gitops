# Nền tảng EKS

Các Application của ArgoCD trong `apps/` cài add-on bằng Helm chart với phiên bản đã pin. Các phiên bản chart đã được tra cứu trên Artifact Hub ngày 09/11/2026; chưa kiểm thử với phiên bản Kubernetes, cấu hình IAM hoặc VPC của cluster FCourt.

- AWS Load Balancer Controller: chart `3.6.2` từ `https://aws.github.io/eks-charts`; [Artifact Hub](https://artifacthub.io/packages/helm/aws/aws-load-balancer-controller/). Cần cluster name và Pod Identity association/permissions.
- External Secrets Operator: chart `0.19.2` từ `https://charts.external-secrets.io`; [Artifact Hub](https://artifacthub.io/packages/helm/external-secrets-operator/external-secrets/0.19.2). Cần cấu hình SecretStore/ClusterSecretStore và Pod Identity.
- metrics-server: chart `3.12.2` từ `https://kubernetes-sigs.github.io/metrics-server/`; [Artifact Hub](https://artifacthub.io/packages/helm/metrics-server/metrics-server/3.12.2).
- CloudNativePG operator: chart `0.23.2` từ `https://cloudnative-pg.github.io/charts`; **chưa xác minh registry chart/version trong môi trường hiện tại**. Cluster `fcourt-postgres` là CR riêng; 1 instance, 10Gi gp3, database init job.
- Strimzi Kafka operator: chart `0.45.0` từ `https://strimzi.io/charts/`; **chưa xác minh chart/version và tương thích Kubernetes**. Kafka 3.9.0 KRaft, một node broker/controller, 10Gi gp3; bootstrap `fcourt-kafka-kafka-bootstrap.data.svc.cluster.local:9092`.
- Redis: image `redis:7.4-alpine` (tag pin, **chưa xác minh registry/tag còn được cunguh cấp**), một replica, memory-limited, `emptyDir`.

Operator Applications và instance Applications đều ở platform wave `0`, trước ApplicationSet services wave `1`. PostgreSQL/Kafka instance Apps dùng `SkipDryRunOnMissingResource=true` để CRDs cài trước khi Argo kiểm tra custom resources. PostgreSQL shared `postgres` credential do CNPG sinh; apps tham chiếu Secret `fcourt-postgres-superuser`, key `password`. Databases được init bằng Job sau khi Cluster sẵn sàng.

Các giá trị cluster-specific hiện là placeholder. Xác minh tương thích chart, IAM policy, subnet discovery, và values của từng chart trước khi sync platform.
