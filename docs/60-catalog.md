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

> **All-in-one layout:** this chart shares component names (`api-gateway`,
> `authtool-bff`, `adk-be-app`, `access-control`, …) with Services and AI
> Foundry, so installing it into a shared namespace requires the
> `values.all-in-one.yaml` overlay, which sets `catalog.namespacePrefix:
> cat` and renames every resource to `cat-*`:
>
> ```
> helm upgrade --install catalog charts/catalog \
>   --namespace default --create-namespace \
>   -f charts/catalog/values.yaml \
>   -f charts/catalog/values.all-in-one.yaml \
>   -f <your-secrets-values-file> \
>   charts/catalog
> ```
>
> Kafka is unaffected: `kafkaKeys.bootstrapServers` is a fully-qualified
> in-cluster address, so Catalog reaches the same broker from either
> namespace — and this repository's `hacks/kafka.sh` still creates the
> topics in the `catalog` namespace even when Catalog itself runs in
> `default`. In the local `kind` setup that's `make 040_catalog_all_in_one`;
> see [Installation layouts](10-overview.md#installation-layouts).

## `values.yaml` reference

All configuration lives under the `catalog` key.

| Field | Required | Description |
|---|---|---|
| `url` | Yes | Public URL for Catalog. |
| `authzUrl` | Yes | The Services (homepage) URL, used for the authorization check. |
| `rbacAuthzServiceUrl` | Yes | In-cluster gRPC address of the authorization service from the Services chart. |
| `authorizationServer.issuer` | Yes | Keycloak realm issuer URL. |
| `catalogKafkaContext.connectionConfig` | Yes | Kafka bootstrap-servers/SASL/security-protocol settings — must match your Kafka cluster. |
| `catalogKafkaContext.topics.input` / `.output` | Yes | Kafka topic names Catalog produces/consumes on — must match the actual topic names on your Kafka cluster, not necessarily this repository's `catalog-events.input`/`catalog-events.output` defaults. |
| `ingressRoute.enabled` | Yes (if using Traefik) | Disable and configure your own ingress otherwise. |
| `secrets.*.enabled` | Yes | Toggles gating each secrets block below. Set to `true` to have the chart render the Secret from these `values.yaml` fields, or `false` to reuse a Secret you manage outside the chart — see [Bringing your own Secret](#bringing-your-own-secret). |
| `adkBeApp.config.googleCloudProject` / `googleCloudLocation` / `googleGenaiUseVertexai` | Only if using the ADK's Vertex AI integration | GCP project/region for the AI features; omit or adjust if you don't use GCP/Vertex. |
| `doclingService.enabled` | No | Document-processing companion service, enable if you need it. |
| `itemsCompressor.config` / `itemsConsumer.config` | Yes | Kafka consumer-group IDs and Postgres cache table/schema names for Catalog's internal processing pipeline. |
| `mailService.config.host` | Yes (if sending email) | SMTP host for notifications. |
| `environment` | Yes | Environment label used internally by Catalog (e.g. `local`, `production`). |

To have more details on the values you can update, please refer to the [JSON Schema of the Catalog chart](https://cdn.mia-platform.eu/runtime/platform/catalog/catalog-helm-chart/0.3.28/values.schema.json).

## Secrets

Generated in this repository via `charts/catalog/render_values.sh`:

- **`accessControlKeys.privateKey`** — same key material as
  `authtoolBffKeys.privateKey` below (shared across products).
- **`authtoolBffKeys`** — `tokenEncKey`, `cookieSecret`, plus per-client
  `privateKey`s (`website`, `exchange`) — must match Services'/AI Foundry's
  `authtoolBffKeys` key material.
- **`adkBeAppKeys.postgresConnectionString`** — connection string to the
  shared `adk` Postgres database. (`googleApplicationCredentials` is left
  empty by default — set it if your Vertex AI integration needs a service
  account key.)
- **`catalogEngineKeys.postgresConnectionString`** and
  **`itemsCompressorKeys.postgresConnectionString`** — connection string to
  the `catalog` Postgres database.
- **`kafkaKeys.bootstrapServers`** — Kafka bootstrap servers address.
- **`mailServiceKeys.smtpUsername`/`smtpPassword`** — SMTP credentials, if
  `mailService` is used.

### Bringing your own Secret

Setting a `secrets.*.enabled` flag to `false` stops the chart from rendering
that Secret at all — instead, the pods read from a Secret of the same name
that must already exist in the release namespace, so you can manage it
through your own GitOps flow rather than through `values.yaml`. The
deployment's restart-on-change annotation adapts accordingly: with
`enabled: true` it hashes the rendered Secret, with `enabled: false` it
`lookup`s the existing one in-cluster and hashes that instead, so pods still
roll on a rotation.

The Secret must be named `<component>-keys` (`<namespacePrefix>-<component>-keys`
in the all-in-one layout, e.g. `cat-adk-be-app-keys`) and contain these keys:

- **`access-control-keys`** (`secrets.accessControlKeys.enabled`): `key.pem`
  if `accessControl.config.externalContext.authorization.tokenAuthMethod` is
  `private_key_jwt`, otherwise `client-secret`.
- **`adk-be-app-keys`** (`secrets.adkBeAppKeys.enabled`):
  `postgresConnectionString` and `google-application-credentials.json`
- **`authtool-bff-keys`** (`secrets.authtoolBffKeys.enabled`):
  `redis-token-enc.key`, `cookie-secret.key`, plus one
  `<client>-key.pem`/`<client>-client-secret` per entry configured under
  `authtoolBff.config.clients` (by default just `website-key.pem`).
- **`catalog-engine-keys`** (`secrets.catalogEngineKeys.enabled`):
  `postgres-connection-string`, plus `key.pem` or `client-secret` (same
  `tokenAuthMethod` rule as above) if
  `catalogEngine.config.authzServiceAuthorization.enabled` is `true`.
- **`items-compressor-keys`** (`secrets.itemsCompressorKeys.enabled`):
  `postgres-connection-string`.
- **`mail-service-keys`** (`secrets.mailServiceKeys.enabled`):
  `smtp-username`, `smtp-password`.

`kafkaKeys` follows the same `enabled`/`lookup` mechanics but with a fixed,
unprefixed Secret name, **`kafka-keys`**, holding `bootstrap.servers`,
`sasl.username`, `sasl.password` — unless `catalogKafkaContext.embedded.enabled`
is also `true`, in which case the chart always renders its own `kafka-keys`
from the embedded cluster's coordinates and the two flags are mutually
exclusive (the chart fails validation otherwise).

## Verify

- `kubectl get pods -n catalog` — pods `Running`. (All-in-one layout:
  `kubectl get pods -n default -l app.kubernetes.io/instance=catalog`, or
  look for the `cat-` prefixed pods.)
- Visit the Catalog URL and confirm you can sign in and browse items.
- Sign in with the username/password of the user you created in the
  `mia-realm` realm (or the realm name you chose) (see
  [Keycloak Realms: create a super-admin user](40-keycloak-realms.md#post-install-create-a-super-admin-user)).
  Alternatively, the **Register** button on the login page lets anyone
  create a new user on the spot — those self-registered users only get
  regular (non-admin) permissions.
- Confirm the topics named in `catalogKafkaContext.topics.input`/`.output`
  exist on your Kafka cluster and are being consumed. This repository's
  local setup names them `catalog-events.input`/`catalog-events.output`
  (see `hacks/kafka/topics.yaml` for the partition/retention settings used
  there as a reference) — your own installation's topic names may differ.
