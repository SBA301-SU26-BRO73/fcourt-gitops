# ConfigMap rollout verification

Verified locally with `kubectl kustomize` (embedded Kustomize v5.5.0). All 13
service entry points built before and after conversion. No cluster access was
used. Baselines were captured before editing the manifests.

For every service, the complete rendered YAML was compared byte-for-byte after
replacing the generated name with its original logical name. The assertion
passed for all 13 services. Each hashed name occurred exactly twice:
`ConfigMap.metadata.name` and the Deployment container's
`envFrom.configMapRef.name`. Thus all ConfigMap data, explicit Deployment env,
Secret references, labels, ports, images, and other resources are identical.

**Result: 231/231 ConfigMap key/value pairs preserved; zero environment-value
changes; exactly two name-field changes per service (26 fields total).**

| Service | Unchanged keys | Before: ConfigMap and envFrom name | After: ConfigMap and envFrom name |
| --- | ---: | --- | --- |
| auth-service | 23 | `auth-service-config` | `auth-service-config-8tt577994t` |
| booking-service | 22 | `booking-service-config` | `booking-service-config-4mmdhkt69b` |
| discovery-service | 23 | `discovery-service-config` | `discovery-service-config-tg8td6k86t` |
| facility-service | 25 | `facility-service-config` | `facility-service-config-d52k2gtf4m` |
| gateway-service | 19 | `gateway-service-config` | `gateway-service-config-879h44ctbm` |
| notification-service | 21 | `notification-service-config` | `notification-service-config-98cb4d2tc4` |
| payment-service | 16 | `payment-service-config` | `payment-service-config-k5h6gthm7b` |
| pos-retail-service | 13 | `pos-retail-service-config` | `pos-retail-service-config-52gfm6549g` |
| reporting-service | 16 | `reporting-service-config` | `reporting-service-config-9g7mb74d5k` |
| slot-hold-engine | 5 | `slot-hold-engine-config` | `slot-hold-engine-config-hh9979fkct` |
| staff-operations-service | 22 | `staff-operations-service-config` | `staff-operations-service-config-5fcf67b4b8` |
| subscription-service | 13 | `subscription-service-config` | `subscription-service-config-mc24cf7t6c` |
| voucher-service | 13 | `voucher-service-config` | `voucher-service-config-85kg76m28f` |

## Rendered diff

These are the only changed fields in each complete render:

```diff
# auth-service: ConfigMap.metadata.name
-  name: auth-service-config
+  name: auth-service-config-8tt577994t
# auth-service: Deployment.spec.template.spec.containers[0].envFrom[0].configMapRef.name
-            name: auth-service-config
+            name: auth-service-config-8tt577994t
# booking-service: ConfigMap.metadata.name
-  name: booking-service-config
+  name: booking-service-config-4mmdhkt69b
# booking-service: Deployment.spec.template.spec.containers[0].envFrom[0].configMapRef.name
-            name: booking-service-config
+            name: booking-service-config-4mmdhkt69b
# discovery-service: ConfigMap.metadata.name
-  name: discovery-service-config
+  name: discovery-service-config-tg8td6k86t
# discovery-service: Deployment.spec.template.spec.containers[0].envFrom[0].configMapRef.name
-            name: discovery-service-config
+            name: discovery-service-config-tg8td6k86t
# facility-service: ConfigMap.metadata.name
-  name: facility-service-config
+  name: facility-service-config-d52k2gtf4m
# facility-service: Deployment.spec.template.spec.containers[0].envFrom[0].configMapRef.name
-            name: facility-service-config
+            name: facility-service-config-d52k2gtf4m
# gateway-service: ConfigMap.metadata.name
-  name: gateway-service-config
+  name: gateway-service-config-879h44ctbm
# gateway-service: Deployment.spec.template.spec.containers[0].envFrom[0].configMapRef.name
-            name: gateway-service-config
+            name: gateway-service-config-879h44ctbm
# notification-service: ConfigMap.metadata.name
-  name: notification-service-config
+  name: notification-service-config-98cb4d2tc4
# notification-service: Deployment.spec.template.spec.containers[0].envFrom[0].configMapRef.name
-            name: notification-service-config
+            name: notification-service-config-98cb4d2tc4
# payment-service: ConfigMap.metadata.name
-  name: payment-service-config
+  name: payment-service-config-k5h6gthm7b
# payment-service: Deployment.spec.template.spec.containers[0].envFrom[0].configMapRef.name
-            name: payment-service-config
+            name: payment-service-config-k5h6gthm7b
# pos-retail-service: ConfigMap.metadata.name
-  name: pos-retail-service-config
+  name: pos-retail-service-config-52gfm6549g
# pos-retail-service: Deployment.spec.template.spec.containers[0].envFrom[0].configMapRef.name
-            name: pos-retail-service-config
+            name: pos-retail-service-config-52gfm6549g
# reporting-service: ConfigMap.metadata.name
-  name: reporting-service-config
+  name: reporting-service-config-9g7mb74d5k
# reporting-service: Deployment.spec.template.spec.containers[0].envFrom[0].configMapRef.name
-            name: reporting-service-config
+            name: reporting-service-config-9g7mb74d5k
# slot-hold-engine: ConfigMap.metadata.name
-  name: slot-hold-engine-config
+  name: slot-hold-engine-config-hh9979fkct
# slot-hold-engine: Deployment.spec.template.spec.containers[0].envFrom[0].configMapRef.name
-            name: slot-hold-engine-config
+            name: slot-hold-engine-config-hh9979fkct
# staff-operations-service: ConfigMap.metadata.name
-  name: staff-operations-service-config
+  name: staff-operations-service-config-5fcf67b4b8
# staff-operations-service: Deployment.spec.template.spec.containers[0].envFrom[0].configMapRef.name
-            name: staff-operations-service-config
+            name: staff-operations-service-config-5fcf67b4b8
# subscription-service: ConfigMap.metadata.name
-  name: subscription-service-config
+  name: subscription-service-config-mc24cf7t6c
# subscription-service: Deployment.spec.template.spec.containers[0].envFrom[0].configMapRef.name
-            name: subscription-service-config
+            name: subscription-service-config-mc24cf7t6c
# voucher-service: ConfigMap.metadata.name
-  name: voucher-service-config
+  name: voucher-service-config-85kg76m28f
# voucher-service: Deployment.spec.template.spec.containers[0].envFrom[0].configMapRef.name
-            name: voucher-service-config
+            name: voucher-service-config-85kg76m28f
```

## Content-change check

For each of the 13 services, temporarily appended
`CONFIGMAP_ROLLOUT_VERIFICATION=probe` to `config.env` and rebuilt. Every
ConfigMap name changed again, and every Deployment reference matched its new
name. Restored each file in a `finally` block. This verifies that a data edit
changes the pod template through the shared component. The probe key is not
present in the final configuration.

Existing comments were moved into `config.env`, with inline comments moved
onto their own lines so Kustomize does not include them in environment values.
Generators retain the logical `<service>-config` name, `behavior: create`, and
the `app.kubernetes.io/name` label. No `disableNameSuffixHash` is set.

Additional checks passed: `bash scripts/validate.sh` rendered all 22 repository
targets and 13 Deployments; Bash syntax checks passed for the changed Terraform
script, secret-generation script, and validation script. The Terraform script's
actual update statements were exercised against an isolated fixture: all 12
expected VPC/SNS/media values changed, with no Terraform or Git commands
executed. Final renders matched the verified outputs after probe restoration.
`git diff --check` passed.
