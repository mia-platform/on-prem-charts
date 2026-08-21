# Console

Chart: `charts/console` · Depends on: Keycloak, MongoDB, Redis

Installs the Console product, via the `mia-console` dependency chart.

> **Migrating an existing installation?** If you're installing this into a
> cluster that already runs Console v14.x, don't follow this page as-is —
> the `values.yaml` fields, the `userInfo` duplicate check, and the
> `helm upgrade` invocation all differ from a fresh install. See the
> [Migration Guide](../MIGRATION_GUIDE.md). This only applies to existing
> installations; a fresh install can follow this page directly.

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

At root level, it is required a `imageCredentials` key with the following information:

| Field | Required | Description |
|---|---|---|
| `imagePullSecrets` | No if `imageCredentials` is present | Name of your image pull secret in the `console` namespace. |
| `imageCredentials` | No if `imagePullSecrets` is present | Definition of the Image Pull Secret to generate. Must include the `name` of the secret, an `username`, a `password`, a `mail` and the `registry` (which is the URL of the registry) |
| `mia-console` | Yes | Include all the configurations of the Console for the install |

The following configurations lives under the `mia-console` key.

| Field | Required | Description |
|---|---|---|
| `configurations.consoleUrl` / `cmsUrl` | Yes | Public URLs for Console and its CMS UI — the `IngressRoute` template derives its `Host()` rules from these, so changing them here is enough. |
| `configurations.keycloak.protocol` / `host` / `realm` / `extensibilityRealmName` | Yes | Where Console authenticates — must match your [Keycloak](03-keycloak.md)/[Keycloak Realms](04-keycloak-realms.md) setup. |
| `configurations.redis.hosts` / `username` / `tls` | Yes | Redis connection details (host/port list, auth username, whether to use TLS). |
| `configurations.mailSender.senderAddress` / `notifier` / `smtp.host` / `smtp.port` | Yes (if sending email) | SMTP configuration for notifications. |
| `configurations.audit` | No | Audit-log configuration; defaults are usually fine. |
| `configurations.enablePrometheusMetrics` | No | Enable if you scrape Prometheus metrics. |
| `configurations.crudEncryption` | No | ⚠️ Left commented out by default, meaning CRUD data is stored **unencrypted at rest** (see [Overview](01-overview.md#settings-not-suitable-for-production)). Not recommended for production — configure a real key provider (the chart supports GCP KMS; requires real GCP infrastructure: project, key ring, service account) before storing real data. |
| `configurations.assistant` | No | Console's built-in AI assistant. Disabled by default (`enabled: false`) — to enable it, provide your own LLM provider entries in `llms` and, if used, `embeddings` configuration. |

To have more details on the values you can update, please refer to the [JSON Schema of the Console chart](https://cdn.mia-platform.eu/runtime/platform/devops/console-helm-chart/15.0.15-3/values.schema.json).

## Secrets

### Mia-Platform Docker Container Registry

It is expected that the secret containing the information to authenticate to the Mia-Platform
Docker Container Registry is created separately from the Chart. However, if you prefer to
include it during the install of the Console, you can use the `imageCredentials` key in the
[`values.yaml`](../charts/console/values.yaml) (there's already a suggested structure in the file).

If you already have a secret containing the info to connect to the Registry, you can use the
`imagePullSecrets` key. This key expects one or more values, suggesting that you can refer to
multiple sources, and each value should include a secret to connect to a Docker Container Registry.

### Additional Secrets

Secrets required to run the Console services (e.g. private keys and API keys) are
generated in this repository via [`charts/console/render_values.sh`](charts/console/render_values.sh):

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
- **`authtoolBff.keys`** — `privateKey`, `cookieSecret`,
  `redisTokenEncKey`: token/cookie encryption key material.
- **`extensibilityManagerService.keys.registrarPrivateKey`** — key used by
  Console's extensibility manager to register extensibility clients.
- **`configurations.assistant.keys`** — `azureLlmApiKey`, `github`: API
  service-account tokens it issues to other products.
  keys for the assistant integration, only meaningful if
  `configurations.assistant.enabled` is `true`.

Every value shown in this repository's `render_values.sh` other than the
Redis/Mongo/SMTP connection info is placeholder/fake dev material — replace
all of it with your own generated secrets.

You can tweak the file to include your own API Keys and passwords for already existing instances,
if you already have them (which will be the case in some cases, e.g. the AI API keys)

## Verify

- `kubectl get pods -n console` — pods `Running`.
- Visit the Console URL and confirm you can sign in via Keycloak.
- Sign in with the username/password of the user you created in the
  `mia-realm` realm (or the realm name you chose) (see
  [Keycloak Realms: create a super-admin user](04-keycloak-realms.md#post-install-create-a-super-admin-user)).
  Alternatively, the **Register** button on the login page lets anyone
  create a new user on the spot — those self-registered users only get
  regular (non-admin) permissions.
- Visit the CMS Console URL (`cmsUrl`) and confirm it loads.
