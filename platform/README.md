# Nền tảng EKS

Các Application của ArgoCD trong `apps/` cài add-on bằng Helm chart với phiên bản đã pin. Các phiên bản chart đã được tra cứu trên Artifact Hub ngày 09/11/2026; chưa kiểm thử với phiên bản Kubernetes, cấu hình IAM hoặc VPC của cluster FCourt.

- AWS Load Balancer Controller: chart `3.6.2` từ `https://aws.github.io/eks-charts`; [Artifact Hub](https://artifacthub.io/packages/helm/aws/aws-load-balancer-controller/). Cần cluster name và Pod Identity association/permissions.
- External Secrets Operator: chart `0.19.2` từ `https://charts.external-secrets.io`; [Artifact Hub](https://artifacthub.io/packages/helm/external-secrets-operator/external-secrets/0.19.2). Cần cấu hình SecretStore/ClusterSecretStore và Pod Identity.
- metrics-server: chart `3.12.2` từ `https://kubernetes-sigs.github.io/metrics-server/`; [Artifact Hub](https://artifacthub.io/packages/helm/metrics-server/metrics-server/3.12.2).

Các giá trị cluster-specific hiện là placeholder. Xác minh tương thích chart, IAM policy, subnet discovery, và values của từng chart trước khi sync platform.
