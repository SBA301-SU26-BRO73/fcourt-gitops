# A11: counter gRPC requires TLS before it can be enabled

Status: proposal only. No A11 runtime settings or secrets were changed. The
requested plaintext fallback is unavailable in backend `origin/dev`, so enabling
the servers on `0.0.0.0` without certificates would prevent them from starting.
Task 1 preserves every existing environment value, including the current staff
plaintext setting; A11 remains unresolved until the TLS proposal is implemented.

## Backend evidence

All paths below are relative to the read-only `../fcourt-backend` repository,
revision `origin/dev`. Inspected with `git show` and `git grep`.

Server source paths:

- Hold: `slot-hold-engine/src/main/java/com/fcourt/hold/CounterSafetyServer.java`.
- Booking: `booking-service/src/main/java/com/fcourt/booking/CounterSafetyServer.java`.

| Property | Default / meaning | Hold source line | Booking source line |
| --- | --- | --- | --- |
| `counter.grpc.enabled` | Server bean exists only when `true`; use `COUNTER_GRPC_ENABLED=true` | 21 | 21 |
| `counter.grpc.host` | `127.0.0.1`; planned `COUNTER_GRPC_HOST=0.0.0.0` | 32 | 34 |
| `counter.grpc.port` | Hold `9087`, booking `9088`; `COUNTER_GRPC_PORT` | 33 | 35 |
| `counter.grpc.certificate` | Empty; filesystem path to PEM certificate chain, not inline PEM; `COUNTER_GRPC_CERTIFICATE` | 34 | 36 |
| `counter.grpc.private-key` | Empty; filesystem path to PEM private key | 35 | 37 |

For the hyphenated private-key property, the proposal uses the exact property
name in `SPRING_APPLICATION_JSON` rather than relying on an environment-variable
spelling. Example (only a file path, no secret value):
`{"counter":{"grpc":{"private-key":"/run/counter-tls/server-key.pem"}}}`.

Hold lines 40-44 and booking lines 43-47 implement the complete TLS decision:

```java
if (!certificate.isBlank() && !key.isBlank())
    builder.useTransportSecurity(new File(certificate), new File(key));
else if (!InetAddress.getByName(host).isLoopbackAddress())
    throw new IllegalArgumentException("Non-loopback gRPC requires TLS certificate and key");
```

There is no server `allow-plaintext` option and no separate TLS-enabled switch.
If either certificate path or key path is blank, a non-loopback bind is rejected.
`0.0.0.0` is non-loopback. Supplying both paths selects TLS; unreadable or invalid
material will also fail server construction.

Staff configuration:
`staff-operations-service/src/main/resources/application.yml`:

| Property | Exact environment variable | Default | Line |
| --- | --- | --- | --- |
| `staff.grpc.hold-target` | `HOLD_GRPC_TARGET` | `localhost:9087` | 38 |
| `staff.grpc.booking-target` | `BOOKING_GRPC_TARGET` | `localhost:9088` | 39 |
| `staff.grpc.plaintext` | `STAFF_GRPC_PLAINTEXT` | `false` | 40 |
| `staff.grpc.deadline-ms` | `STAFF_GRPC_DEADLINE_MS` | `2000` | 41 |

`staff-operations-service/src/main/java/com/fcourt/staff/integration/SlotSafetyGateway.java:29`
injects these properties (lines 29-32). Lines 73-77 call `usePlaintext()` when
plaintext is true, otherwise `useTransportSecurity()`. This is only a client
choice; it does not change either server's TLS guard. There is no custom CA,
trust-store, or client-certificate property in this channel builder. Line 57
produces the reported 503 message for dependency statuses mapped to unavailable.

The client forwards the caller's JWT in `authorization: Bearer ...` at
`SlotSafetyGateway.java:43`. Booking decodes it at
`booking-service/src/main/java/com/fcourt/booking/CounterSafetyServer.java:86`.
Hold checks it at `slot-hold-engine/src/main/java/com/fcourt/hold/CounterSafetyServer.java:83`
and decodes it at `slot-hold-engine/src/main/java/com/fcourt/hold/HoldStaffIdentity.java:48`.
No new shared gRPC bearer-token key is required.

## What the current GitOps checkout already contains

- `services/slot-hold-engine/kustomization.yaml`: ClusterIP gRPC Service port
  `9087`, TCP, numeric target port `9087`.
- `services/booking-service/kustomization.yaml`: ClusterIP gRPC Service port
  `9088`, TCP, numeric target port `9088`.
- Neither Deployment declares a gRPC container port. Numeric Service target
  ports do not require that declaration, but the proposal adds named ports.
- `services/staff-operations-service/config.env` already has
  `HOLD_GRPC_TARGET=slot-hold-engine:9087`,
  `BOOKING_GRPC_TARGET=booking-service:9088`,
  `STAFF_GRPC_PLAINTEXT=true`, and `STAFF_GRPC_DEADLINE_MS=2000`.
- Neither server has `COUNTER_GRPC_*` configuration.

Thus the missing server enablement/bind/TLS material blocks this link; the
existing client targets and Service ports alone cannot fix A11.

## Proposed TLS implementation

1. Issue a server certificate chain and matching PEM private key for each
   server. Hold's certificate must include DNS SAN `slot-hold-engine` and
   booking's must include `booking-service`, matching the existing targets.
   Include namespace-qualified names too if callers will use them. Use a
   private CA with a defined issuance and renewal process; random token strings
   are not TLS certificates or private keys.
2. Supply staff with a Java PKCS12 trust store containing that CA. The current
   channel builder has no per-channel trust configuration, so the manifest-only
   approach is to mount the store and append JVM system properties
   `javax.net.ssl.trustStore`, `javax.net.ssl.trustStoreType=PKCS12`, and
   `javax.net.ssl.trustStorePassword` to staff's existing `JAVA_TOOL_OPTIONS`.
   The password must come from a Secret reference. Preserve the existing JVM
   memory/startup options and verify trust with the deployed JVM/gRPC provider.
   Alternatively, backend work could add an explicit CA-file channel setting;
   that work is outside this checkout.
3. Keep all new sensitive material in the existing `fcourt-internal-tokens`
   Secret. Proposed **future** keys (none added or generated in this change):

   | Key | Contents |
   | --- | --- |
   | `COUNTER_HOLD_TLS_CERTIFICATE_B64` | Base64 of hold's PEM certificate chain |
   | `COUNTER_HOLD_TLS_PRIVATE_KEY_B64` | Base64 of hold's PEM private key |
   | `COUNTER_BOOKING_TLS_CERTIFICATE_B64` | Base64 of booking's PEM certificate chain |
   | `COUNTER_BOOKING_TLS_PRIVATE_KEY_B64` | Base64 of booking's PEM private key |
   | `COUNTER_STAFF_TLS_TRUSTSTORE_B64` | Base64 of staff's PKCS12 CA trust store |
   | `COUNTER_STAFF_TLS_TRUSTSTORE_PASSWORD` | Trust-store password |

   ASCII base64 keeps the existing shared `envFrom` safe for binary material.
   Init containers would decode only each workload's required keys into an
   `emptyDir`, with file permissions readable by UID/GID 10001; the application
   mounts the decoded files read-only. Fail startup if required keys are absent.
   Before implementation, add the selected keys to
   `scripts/secrets.example/fcourt-internal-tokens.env.example` and extend
   `scripts/create-secrets.sh --generate` to provision valid CA-signed server
   material and the trust store (or import externally issued material), retain
   existing values on reruns, and generate the trust-store password. Do not use
   the script's random-token generator for certificate/trust-store contents.
   The issuer/renewal choice and actual material are prerequisites, so secret
   generation and examples are deliberately deferred with the runtime changes.
4. Configure both servers with `COUNTER_GRPC_ENABLED=true`,
   `COUNTER_GRPC_HOST=0.0.0.0`, their respective `COUNTER_GRPC_PORT=9087`/`9088`,
   `COUNTER_GRPC_CERTIFICATE=/run/counter-tls/server-chain.pem`, and
   `counter.grpc.private-key=/run/counter-tls/server-key.pem` using the JSON
   property mapping above. Declare container port `grpc` on each Deployment;
   keep existing Service ports and optionally change `targetPort` to `grpc`.
5. Keep staff's existing `<svc>:<port>` targets; set
   `STAFF_GRPC_PLAINTEXT=false` only together with the trust store and servers.
   No public Ingress or ALB gRPC listener is needed.
6. Render all affected services, then verify a TLS handshake from the staff pod
   to each Service with hostname verification and test an authenticated walk-in.
   Check successful availability checks and expected busy-slot/auth failures.
   This checkout has only been rendered locally; no cluster smoke test was run.

No A11 manifest, `create-secrets.sh`, or secret-example change is applied in this
proposal. Implementing those changes without the TLS prerequisites would leave
the feature broken or crash the server workloads.
