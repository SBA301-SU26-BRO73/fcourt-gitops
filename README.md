# fcourt-gitops

Kubernetes configuration that Argo CD syncs into the `fcourt-prod` EKS cluster (a single environment). It holds the manifests of the FCourt backend services and the in-cluster platform add-ons. Application code lives in `fcourt-backend`; AWS resources live in `fcourt-infra`. This repo is the source of truth for what runs in the cluster, including the image tag of each service. No real secrets are stored here.

## Role in the FCourt system

| Repo | Responsibility |
|---|---|
| `fcourt-backend` | Spring Boot microservices and the CI that builds and pushes images, then commits new image tags here |
| **fcourt-gitops** (this repo) | Argo CD apps, platform add-ons, per-service Kustomize config |
| `fcourt-infra` | Terraform: VPC, EKS, ECR, S3, CloudFront, Route 53, ACM, SNS, IAM Pod Identity, budget |
| `fcourt-web` | Web frontend on S3 + CloudFront (https://fcourt.donan.site) |
| `fcourt-flutter` | Android app |

Why three repos: [docs/architecture/adr/0001-three-repositories.md](docs/architecture/adr/0001-three-repositories.md).

## Tech stack

Argo CD (Helm chart pinned in `scripts/bootstrap-argocd.sh`), Kustomize, ApplicationSet. Platform add-ons: AWS Load Balancer Controller, gp3 StorageClass, PostgreSQL (CloudNativePG), Kafka (Strimzi), Redis. Services: 12 Spring Boot services plus `gateway-service`, which is the only public entry point (ALB Ingress). Services call each other through Kubernetes Service DNS.

## Project structure

```text
argocd/
  root-app.yaml            # single root Application (path: argocd), applied by hand once
  kustomization.yaml       # root app content: projects, platform, services ApplicationSet
  projects.yaml            # AppProjects: platform, services
  services-appset.yaml     # ApplicationSet: one Application per services/*
  values.yaml              # Helm values for Argo CD
platform/
  aws-load-balancer-controller/  storage/  postgres/  kafka/  redis/
services/
  _components/spring-service/    # shared Deployment, Service, ServiceAccount
  _components/alb-ingress/       # public ALB Ingress (gateway only)
  <service>/                     # kustomization.yaml, config.env, deployment-env.yaml (if secrets)
scripts/                         # bootstrap, secrets, Terraform outputs, validate, secrets.example/
docs/                            # see docs/README.md
```

## How it works

```text
scripts/bootstrap-argocd.sh --> argocd/root-app.yaml (Application fcourt-root, path argocd)
  wave -1  AppProjects, StorageClass gp3
  wave  0  aws-load-balancer-controller, cloudnative-pg-operator, strimzi-operator, redis
  wave  1  cloudnative-pg (Cluster), strimzi (Kafka)
  wave  2  ApplicationSet fcourt-services --> Application fcourt-<svc> per services/*
           (namespace fcourt-prod, automated prune and selfHeal)
```

Runtime: `client -> ALB -> gateway-service:8080 -> http://<svc>:<port>`. Services use PostgreSQL, Kafka and Redis in namespace `data`, and reach S3 and SNS through EKS Pod Identity (ServiceAccount name = service name; the associations are created by `fcourt-infra`). More detail: [docs/architecture](docs/architecture/) and [docs/operations](docs/operations/).

## Prerequisites

`kubectl` pointed at the cluster, `helm`, `terraform`, `jq`, and AWS credentials with access to the cluster. For local rendering only `kustomize` or `kubectl` is needed (no cluster, no AWS).

## Common tasks

| Task | Command or place |
|---|---|
| Validate all manifests locally | `bash scripts/validate.sh` (renders every Kustomize entry point, expects 13 Deployments) |
| Bring up a fresh cluster | after `terraform apply` of `fcourt-infra/envs/prod`: `scripts/apply-terraform-outputs.sh`, `scripts/create-secrets.sh --generate`, `scripts/bootstrap-argocd.sh`; full runbook in [docs/operations/bring-up.md](docs/operations/bring-up.md) |
| Watch sync | `kubectl -n argocd get applications` |
| Open Argo CD UI | `kubectl -n argocd port-forward svc/argocd-server 8080:80` |
| Add a service | [docs/operations/service-layout.md](docs/operations/service-layout.md) |
| Gateway paths per service | [docs/architecture/gateway-routes.md](docs/architecture/gateway-routes.md) |

## Configuration

- Per-service environment lives in `services/<svc>/config.env` (`KEY=VALUE`, no quotes). Kustomize hashes the ConfigMap name, so a changed value rolls the Deployment on the next sync.
- Secrets are never committed. `scripts/create-secrets.sh` creates Kubernetes Secrets from local env files (templates in `scripts/secrets.example/`, real files under `~/.fcourt/secrets/`). Service Deployments reference Secret `<svc>-secrets` through `deployment-env.yaml`.
- Values derived from Terraform (VPC id, SNS ARN, S3 bucket and public base URL) are written by `scripts/apply-terraform-outputs.sh`.

## CI/CD and deployment

- There is no CI workflow in this repo. Argo CD syncs `main` automatically.
- Image updates: the `fcourt-backend` workflow `build-push-images.yml` pushes `:<short-sha>`, runs `kustomize edit set image` in `services/<svc>` and commits to `main`. Tags are always pinned to the SHA.
- After a fresh bring-up, update the `origin` DNS record of the API (script `update-origin-record.sh` in `fcourt-infra`), because the ALB hostname changes on every up/down. See the runbook.
- Run `bash scripts/validate.sh` before opening a PR.

## Testing

Manifests are validated by rendering: `bash scripts/validate.sh`. Verification notes for past changes: [docs/validation](docs/validation/).

## Contributing

- Branch from `main` with a prefix such as `feat/`, `fix/`, `docs/`, `chore/`; open a PR into `main`.
- Commit messages and PR titles are in English (`type(scope): message`, for example `chore(images): bump notification-service to <sha>`). Bodies may be Vietnamese.
- Do not commit secrets, tokens or filled-in `.env` files. Do not disable the ConfigMap name suffix hash.
