# Catalog

Chart: `charts/catalog` · Depends on: Services, PostgreSQL (`catalog`, `adk`), Kafka

Installs the Catalog product.

## Install

```
helm dependency build charts/catalog
helm upgrade --install catalog charts/catalog \
  --namespace catalog --create-namespace \
  -f charts/catalog/values.yaml \
  -f <your-secrets-values-file> \
  charts/catalog
```

## `values.yaml` reference

All configuration lives under the `catalog` key.

| Field | Required | Description |
|---|---|---|
| `url` | Yes | Public URL for Catalog. |
| `authzUrl` | Yes | The Services (homepage) URL, used for the authorization check. |
| `rbacAuthzServiceUrl` | Yes | In-cluster gRPC address of the authorization service from the Services chart. |
| `authorizationServer.issuer` | Yes | Keycloak realm issuer URL. |
| `catalogKafkaContext.connectionConfig` | Yes | Kafka bootstrap-servers/SASL/security-protocol settings — must match your Kafka cluster. |
| `ingressRoute.enabled` | Yes (if using Traefik) | Disable and configure your own ingress otherwise. |
| `secrets.*.enabled` | Yes | Toggles gating each secrets block below — must all be `true`. |
| `adkBeApp.config.googleCloudProject` / `googleCloudLocation` / `googleGenaiUseVertexai` | Only if using the ADK's Vertex AI integration | GCP project/region for the AI features; omit or adjust if you don't use GCP/Vertex. |
| `doclingService.enabled` | No | Document-processing companion service, enable if you need it. |
| `itemsCompressor.config` / `itemsConsumer.config` | Yes | Kafka consumer-group IDs and Postgres cache table/schema names for Catalog's internal processing pipeline. |
| `mailService.config.host` | Yes (if sending email) | SMTP host for notifications. |
| `environment` | Yes | Environment label used internally by Catalog (e.g. `local`, `production`). |

## Secrets

Generated in this repository via `charts/catalog/render_values.sh`:

- **`accessControlKeys.privateKey`** — same key material as
  `authtoolBffKeys.privateKey` below (shared across products).
- **`authtoolBffKeys`** — `tokenEncKey`, `cookieSecret`, plus per-client
  `privateKey`s (`website`, `exchange`) — must match Services'/AI Foundry's
  `authtoolBffKeys` key material.
- **`adkBeAppKeys.postgresConnectionString`** — connection string to the
  shared `adk` Postgres database.
- **`catalogEngineKeys.postgresConnectionString`** and
  **`itemsCompressorKeys.postgresConnectionString`** — connection string to
  the `catalog` Postgres database.
- **`kafkaKeys.bootstrapServers`** — Kafka bootstrap servers address.
- **`mailServiceKeys.smtpUsername`/`smtpPassword`** — SMTP credentials, if
  `mailService` is used.

## Verify

- `kubectl get pods -n catalog` — pods `Running`.
- Visit the Catalog URL and confirm you can sign in and browse items.
- Sign in with the username/password of the user you created in the
  `mia-platform` realm (see
  [Keycloak Realms: create a super-admin user](04-keycloak-realms.md#post-install-create-a-super-admin-user)).
  Alternatively, the **Register** button on the login page lets anyone
  create a new user on the spot — those self-registered users only get
  regular (non-admin) permissions.
- Confirm Kafka topics for `catalog-events.input`/`catalog-events.output`
  (or your equivalent) exist and are being consumed (see
  `hacks/kafka/topics.yaml` for the partition/retention settings this
  repository uses as a reference).
