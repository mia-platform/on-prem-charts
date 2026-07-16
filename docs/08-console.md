# Console

Chart: `charts/console` · Depends on: Keycloak, MongoDB, Redis

Installs the Console product, via the `mia-console` dependency chart.

## Install

```
helm dependency build charts/console
helm upgrade --install console charts/console \
  --namespace console --create-namespace \
  -f charts/console/values.yaml \
  -f <your-secrets-values-file> \
  charts/console
```

## `values.yaml` reference

All configuration lives under the `mia-console` key.

| Field | Required | Description |
|---|---|---|
| `imagePullSecrets` | Yes | Name of your image pull secret in the `console` namespace. |
| `configurations.consoleUrl` / `cmsUrl` | Yes | Public URLs for Console and its CMS UI — the `IngressRoute` template derives its `Host()` rules from these, so changing them here is enough. |
| `configurations.keycloak.protocol` / `host` / `realm` / `extensibilityRealmName` | Yes | Where Console authenticates — must match your [Keycloak](03-keycloak.md)/[Keycloak Realms](04-keycloak-realms.md) setup. |
| `configurations.redis.hosts` / `username` / `tls` | Yes | Redis connection details (host/port list, auth username, whether to use TLS). |
| `configurations.mailSender.senderAddress` / `notifier` / `smtp.host` / `smtp.port` | Yes (if sending email) | SMTP configuration for notifications. |
| `configurations.audit` | No | Audit-log configuration; defaults are usually fine. |
| `configurations.enablePrometheusMetrics` | No | Enable if you scrape Prometheus metrics. |
| `configurations.crudEncryption` | No | ⚠️ Left commented out by default, meaning CRUD data is stored **unencrypted at rest** (see [Overview](01-overview.md#settings-not-suitable-for-production)). Not recommended for production — configure a real key provider (the chart supports GCP KMS; requires real GCP infrastructure: project, key ring, service account) before storing real data. |
| `configurations.assistant` | No | Console's built-in AI assistant. Disabled by default (`enabled: false`) — to enable it, provide your own LLM provider entries in `llms` and, if used, `embeddings` configuration. |

## Secrets

Generated in this repository via `charts/console/render_values.sh`:

- **`configurations.redis.password`** and **`configurations.redis.tlsCACert`**
  — Redis auth password and the CA certificate to validate Redis's TLS
  certificate against.
- **`configurations.mailSender.smtp.username`/`password`** — SMTP
  credentials.
- **`configurations.mongodbUrl`** — MongoDB connection string (must include
  `replicaSet=rs0` if your MongoDB runs as a replica set) — also reused for
  `configurations.audit.envs.mongodbUrl`.
- **`configurations.filesCredentials`** — base64-encoded JSON credentials
  for Console's file-storage integration (empty object `{}` disables it in
  this repository).
- **`configurations.serviceAccountAuthProvider`** — `rsaPrivateKeyBase64`,
  `rsaPrivateKeyId`, `clientIdSalt`: key material Console uses to sign
  service-account tokens it issues to other products.
- **`configurations.assistant.keys`** — `azureLlmApiKey`, `github`: API
  keys for the assistant integration, only meaningful if
  `configurations.assistant.enabled` is `true`.
- **`authtoolBff.keys`** — `privateKey`, `cookieSecret`,
  `redisTokenEncKey`: token/cookie encryption key material.
- **`extensibilityManagerService.keys.registrarPrivateKey`** — key used by
  Console's extensibility manager to register extensibility clients.

Every value shown in this repository's `render_values.sh` other than the
Redis/Mongo/SMTP connection info is placeholder/fake dev material — replace
all of it with your own generated secrets.

## Verify

- `kubectl get pods -n console` — pods `Running`.
- Visit the Console URL and confirm you can sign in via Keycloak.
- Sign in with the username/password of the user you created in the
  `mia-platform` realm (see
  [Keycloak Realms: create a super-admin user](04-keycloak-realms.md#post-install-create-a-super-admin-user)).
  Alternatively, the **Register** button on the login page lets anyone
  create a new user on the spot — those self-registered users only get
  regular (non-admin) permissions.
- Visit the CMS Console URL (`cmsUrl`) and confirm it loads.
