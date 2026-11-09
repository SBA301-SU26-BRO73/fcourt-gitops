# Platform

Argo CD Applications for cluster add-ons. Helm chart versions are pinned. They were looked up on Artifact Hub on 2026-11-09 and have not been tested against the FCourt Kubernetes version, IAM setup or VPC.

## Shared add-ons (dev and prod)

Listed in both `clusters/dev` and `clusters/prod`.

| Component | Chart | Notes |
|---|---|---|
| `aws-load-balancer-controller` | `3.6.2` from `https://aws.github.io/eks-charts` | Needs cluster name, region and VPC ID in the Application values, plus a Pod Identity association from `fcourt-infra`. |
| `external-secrets` | `0.19.2` from `https://charts.external-secrets.io` | Operator only. SecretStore / ClusterSecretStore and Pod Identity are not configured yet. |
| `metrics-server` | `3.12.2` from `https://kubernetes-sigs.github.io/metrics-server/` | |

## dev-data: DEV ONLY

In-cluster data for the dev cluster, listed only in `clusters/dev`. Prod uses RDS, MSK and ElastiCache created by `fcourt-infra`. Each component folder holds the Application files and a subfolder of plain manifests that the instance Application syncs.

| Component | Applications | Synced manifests |
|---|---|---|
| `cloudnative-pg` | operator chart `0.23.2` from `https://cloudnative-pg.github.io/charts`; instance Application | `cluster/`: `Cluster fcourt-postgres` (1 instance, 10Gi gp3, PostgreSQL 16.4) and the Job that creates the service databases |
| `strimzi` | operator chart `0.45.0` from `https://strimzi.io/charts/`; instance Application | `kafka/`: Kafka 3.9.0 KRaft, one combined node, 10Gi gp3, and the `KafkaTopic` resources |
| `redis` | instance Application | `manifests/`: `redis:7.4-alpine`, one replica, memory-limited, `emptyDir` |

The chart registries and versions for CloudNativePG and Strimzi, and the Redis image tag, have not been verified in this environment.

All Applications are in sync wave `0`. The instance Applications for CloudNativePG and Strimzi use `SkipDryRunOnMissingResource=true`, so their custom resources are not rejected before the operator CRDs exist. The CloudNativePG Job that creates the databases is in wave `1` inside its own Application. CloudNativePG generates the `postgres` credential in Secret `fcourt-postgres-superuser`, key `password`, which the services reference.

The shared `platform` AppProject does not allow these chart repos and namespaces. `clusters/dev/platform-project-dev.patch.yaml` adds them for dev only.
