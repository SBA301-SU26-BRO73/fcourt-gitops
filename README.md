# FCourt GitOps

Kubernetes configuration that Argo CD syncs to the FCourt EKS clusters (dev and prod): 12 Spring Boot services plus the platform add-ons they need. Kustomize everywhere; Helm charts are installed by Argo CD Applications with pinned versions.

Repository split (see `docs/adr/0001-three-repositories.md`): the backend repo holds source code and image CI, `fcourt-infra` (Terraform) creates EKS, networking, IAM, Pod Identity associations and the prod managed data services, and this repo holds manifests and the image tag in each overlay. No real secrets are stored in Git.

## Layout

```text
bootstrap/
  dev/root-app.yaml            # root Application for the dev cluster  -> clusters/dev
  prod/root-app.yaml           # root Application for the prod cluster -> clusters/prod
clusters/                      # per-cluster entry points: what each cluster runs
  dev/
    kustomization.yaml         #   projects + shared add-ons + dev-only data + services
    services-appset.yaml       #   ApplicationSet: one App per services/*/overlays/dev
    platform-project-dev.patch.yaml  # dev-only additions to the platform AppProject
  prod/
    kustomization.yaml         #   projects + shared add-ons + services (no in-cluster data)
    services-appset.yaml       #   ApplicationSet: one App per services/*/overlays/prod
projects/                      # AppProjects platform and services (shared by both clusters)
platform/
  aws-load-balancer-controller/  # shared add-ons, one Application (Helm chart) each
  external-secrets/
  metrics-server/
  dev-data/                    # DEV ONLY: in-cluster data; prod uses RDS / MSK / ElastiCache
    cloudnative-pg/            #   operator-application.yaml, cluster-application.yaml, cluster/
    strimzi/                   #   operator-application.yaml, kafka-application.yaml, kafka/
    redis/                     #   redis-application.yaml, manifests/
components/
  spring-service/              # shared Deployment, Service, ServiceAccount, probes, resources, security context
  alb-ingress/                 # shared public ALB Ingress (group fcourt-public)
services/<service>/
  base/                        # configmap.yaml, kustomization.yaml, optional deployment-env.yaml
  overlays/dev/                # namespace fcourt-dev, image tag, replicas
  overlays/prod/               # namespace fcourt-prod, image tag, replicas
docs/adr/                      # architecture decision records
scripts/validate.sh            # renders every Kustomize entry point
```

## How bootstrap works

Each cluster gets exactly one root Application, applied once by hand after Argo CD is installed:

```sh
kubectl create namespace argocd                            # if Argo CD is not installed yet
kubectl apply -n argocd -f bootstrap/dev/root-app.yaml     # dev cluster
kubectl apply -n argocd -f bootstrap/prod/root-app.yaml    # prod cluster
```

The root Application syncs `clusters/<env>`, which contains everything Argo CD needs for that cluster, ordered by sync wave:

```text
fcourt-root (path clusters/<env>)
  |- wave -1  AppProjects (platform, services)
  |- wave  0  platform Applications (add-ons; in dev also operators and in-cluster data)
  '- wave  1  services ApplicationSet -> one Application per services/*/overlays/<env>
```

Argo CD waits for the wave 0 Applications to be healthy before it creates the ApplicationSet. The ApplicationSet does not wait for the Applications it generates, so service Apps reconcile concurrently. Retry with bounded backoff is set on the root and all child Applications. In dev, the CloudNativePG and Strimzi instance Applications use `SkipDryRunOnMissingResource=true` so their custom resources are accepted before the operator CRDs exist.

Before the first sync, replace the placeholders: the Git URL (if it changes), `<ECR_REGISTRY>`, `<IMAGE_TAG>`, the `<SET_...>` ConfigMap values, and in `platform/aws-load-balancer-controller/application.yaml` the cluster name, region and VPC ID. Pod Identity associations come from `fcourt-infra`.

## Dev vs prod

| | dev | prod |
|---|---|---|
| Entry point | `clusters/dev` | `clusters/prod` |
| Services namespace | `fcourt-dev` (1 replica each) | `fcourt-prod` (2 replicas each) |
| PostgreSQL | CloudNativePG in namespace `data` | RDS (Terraform) |
| Kafka | Strimzi in namespace `data` | MSK (Terraform) |
| Redis | Deployment in namespace `data` | ElastiCache (Terraform) |
| Shared add-ons | ALB controller, External Secrets, metrics-server | same |

Prod is a skeleton: its overlays render, but service ConfigMaps still carry the dev in-cluster endpoints (`*.data.svc.cluster.local`) and the `fcourt-postgres-superuser` secret reference, because those values live in `services/<service>/base/`. Before enabling prod, move them into `overlays/prod` (or a patch) and point them at RDS, MSK and ElastiCache.

### Dev in-cluster data

```text
fcourt-dev services -- PostgreSQL  fcourt-postgres-rw.data.svc.cluster.local:5432
                    |- Redis       redis.data.svc.cluster.local:6379
                    '- Kafka       fcourt-kafka-kafka-bootstrap.data.svc.cluster.local:9092
```

- PostgreSQL creates 11 databases (`auth_db`, `booking_db`, `discovery_db`, `facility_db`, `notification_db`, `payment_db`, `pos_retail_db`, `reporting_db`, `staff_db`, `subscription_db`, `voucher_db`). Services connect as `postgres` with the password from Secret `fcourt-postgres-superuser`, key `password`. This is one shared high-privilege account, acceptable for dev only.
- Redis uses `emptyDir`, has no password and loses its data on restart.
- Kafka is plain internal, auto-create is off, and topics (events and DLT) are declared as `KafkaTopic` resources in `platform/dev-data/strimzi/kafka/topics.yaml`.
- PostgreSQL and Kafka use single-AZ gp3 PVCs, with no HA and no backups. Do not reuse this setup in prod.

Debug access:

```sh
kubectl -n data port-forward svc/fcourt-postgres-rw 5432:5432
kubectl -n data port-forward svc/redis 6379:6379
kubectl -n data port-forward svc/fcourt-kafka-kafka-bootstrap 9092:9092
```

## How a service is built

`components/spring-service` holds the Deployment, Service and ServiceAccount shared by all services: non-root user, read-only root filesystem, `/tmp` emptyDir, `/actuator/health` probes, resource requests and limits. It uses placeholder names and fills them in from the service's own ConfigMap with Kustomize replacements: the `app.kubernetes.io/name` label gives every resource name and selector, `metadata.name` gives the `envFrom` reference, and `SERVER_PORT` gives the container and Service port. `components/alb-ingress` does the same for the public Ingress.

A service base therefore contains only what is specific to it:

- `configmap.yaml`: `<service>-config`, labelled `app.kubernetes.io/name: <service>`, with `SERVER_PORT` and the Spring environment variables.
- `deployment-env.yaml` (optional): `env` entries that reference Secrets.
- `kustomization.yaml`: the components, the image name, and for public services the Ingress path.

## Add a service

1. Create `services/<service>/base/configmap.yaml`, named `<service>-config`, with label `app.kubernetes.io/name: <service>`, `SERVER_PORT` and the variables from the service's `application.yml`. Pick a port no other service uses.
2. If the service needs secrets, add `services/<service>/base/deployment-env.yaml` (copy one from an existing service). Secrets are Kubernetes Secrets named `<service>-secrets`.
3. Create `services/<service>/base/kustomization.yaml` (copy an existing one). Change the image `newName` to `<ECR_REGISTRY>/fcourt/<service>`. Keep `components/alb-ingress` and the Ingress path patch only if the API is public.
4. Create `services/<service>/overlays/dev/kustomization.yaml` and `overlays/prod/kustomization.yaml` (copy an existing pair and replace the service name).
5. Run `bash scripts/validate.sh`.

No other registration is needed: the ApplicationSets discover `services/*/overlays/<env>`.

## Image updates

Images are `<ECR_REGISTRY>/fcourt/<service>:<tag>`. CI builds with an immutable tag (commit SHA preferred) and sets `images[].newTag` in `services/<service>/overlays/<env>/kustomization.yaml` with `kustomize edit set image`; Argo CD syncs from the new commit. Never use `latest`.

## Public routes and assumptions

Every service that has public REST endpoints has its own Ingress in the shared ALB group `fcourt-public`, so web and mobile clients use one host. Paths come from the controller mappings in `fcourt-backend` (branch `dev`) plus `/devices` from the open `work-push-device-registry` branch. Never routed: `/api/internal/**` (service-to-service), `/actuator/**` (the ALB only health-checks `/actuator/health` on the pod), `/.well-known/jwks.json` (consumed by services inside the cluster), and the slot-hold-engine gRPC server (not in the Service or any Ingress).

| Path | Service | Port |
|---|---|---|
| `/api/auth` (also `/api/auth/me`, `/profile`, `/password`) | auth-service | 8081 |
| `/api/super-admin/court-admins`, `/api/super-admin/users`, `/api/super-admin/stats/accounts`, `/api/super-admin/stats/owner-names` | auth-service | 8081 |
| `/api/subscriptions`, `/api/subscription-plans`, `/api/court-types`, `/api/super-admin/stats/saas-revenue` | subscription-service | 8082 |
| `/api/public/branches/*` (branch detail, `/images`, `/courts`), `/api/admin/branches`, `/api/admin/courts`, `/api/admin/time-slot-templates`, `/api/staff/branches`, `/api/staff/courts` | facility-service | 8083 |
| `/api/admin/dashboard`, `/api/super-admin/dashboard` | reporting-service | 8084 |
| `/api/public/branches` (exact, list), `/api/public/branches/*/reviews`, `/api/public/courts`, `/api/reviews`, `/api/admin/reviews` | discovery-service | 8085 |
| `/api/vouchers`, `/api/admin/vouchers` | voucher-service | 8086 |
| `/api/bookings/hold-slots` (REST only; gRPC stays private) | slot-hold-engine | 8087 |
| `/api/bookings`, `/api/admin/bookings`, `/ws-fcourt` (WebSocket/STOMP) | booking-service | 8088 |
| `/api/payments`, `/api/refunds`, `/api/admin/payments`, `/api/admin/refunds` | payment-service | 8089 |
| `/api/staff/schedule`, `/api/staff/check-in`, `/api/staff/offline`, `/api/staff/me`, `/api/staff/walk-in`, `/api/staff/bookings`, `/api/admin/staff` | staff-operations-service | 8090 |
| `/devices` | notification-service | 8091 |
| `/api/staff/pos`, `/api/admin/pos` | pos-retail-service | 8092 |

### Path precedence

The ALB picks the first matching rule by priority, not the longest prefix. The AWS Load Balancer Controller orders rules in a group by `alb.ingress.kubernetes.io/group.order` (lower first), then by Ingress namespace/name, then by path order inside the Ingress. Two overlaps exist and are resolved with that order:

- `/api/bookings` (booking-service, order 20) contains `/api/bookings/hold-slots` (slot-hold-engine, order 10). The hold-engine Ingress is evaluated first.
- `/api/public/branches/*` (facility-service, order 20) contains `/api/public/branches/{id}/reviews` (discovery-service, order 10), and discovery also owns the exact list path `/api/public/branches`. Discovery is evaluated first; the facility wildcard does not match the bare list path.

Everything else is disjoint on purpose: `/api/admin/*`, `/api/staff/*` and `/api/super-admin/*` are split by the second segment (for example `/api/admin/branches` vs `/api/admin/dashboard`), so no broad `/api/admin` or `/api/staff` prefix is used. Keep new paths specific and give any path that sits inside another service's prefix a lower `group.order`.

The ALB default limit is 100 rules; the 12 Ingresses currently use about 45.

### WebSocket (`/ws-fcourt`)

booking-service serves STOMP over plain WebSocket (no SockJS fallback, so sticky sessions are not needed; slot updates fan out through Redis pub/sub). ALB upgrades WebSocket connections on its HTTP listeners without extra annotations. The component sets `load-balancer-attributes: idle_timeout.timeout_seconds=3600` (default is 60 s, and the server sends no heartbeats), and the booking Ingress sets `target-group-attributes: deregistration_delay.timeout_seconds=60` to let sockets drain on rollouts. Clients should still reconnect on close.

### Assumptions

- `pos-retail-service` and `notification-service` both default to `8091` in code. The POS manifest sets `SERVER_PORT` to `8092` to avoid the clash.
- Secrets are referenced by name only. External Secrets is installed as an operator, but no SecretStore or ExternalSecret exists yet.
- Confirm that the Actuator health endpoint is present in the built images.
- Chart versions are pinned but not tested against the clusters. See `platform/README.md`.

## Local validation

```sh
bash scripts/validate.sh
```

Renders every Kustomize entry point (bootstrap, clusters, platform, every service overlay) with `kustomize` or `kubectl kustomize`. No cluster or AWS access is needed.
