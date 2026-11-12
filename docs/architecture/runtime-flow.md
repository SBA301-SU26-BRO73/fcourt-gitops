# Runtime flow

Vietnamese notes, moved from the README.

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

