# AI Foundry

Chart: `charts/ai-foundry` · Depends on: Services, Catalog, AI Services,
PostgreSQL (`adk`, `workspace`), an OpenBao/Vault KV store

Installs the AI Foundry product. Since 15.2 the chart deploys, next to the
website, BFF, edge and agent runtime (`adk-be-app`):

| Component | What it does |
|---|---|
| `ai-foundry-be` | Observability read APIs and the admin side of the AI gateway (models, teams, virtual keys) — it calls AI Services' LiteLLM with the master key. |
| `ai-foundry-provisioner` | Seeds the Item Type Definitions and the default items (agents, tools, MCP servers, playbooks) into every Catalog tenant: a Job at each install/upgrade plus a small Deployment that keeps new tenants seeded and publishes the key of its service account. |
| `ai-foundry-workflows` | Agentic Workflows: an API and a worker running on AI Services' Temporal. |
| `workspace-service` | Ephemeral workspaces (a Git checkout in a runner pod) for workflow steps. It creates runner pods through the Kubernetes API, with a namespaced `Role`. |
| `secret-store-service` | Stores the credentials AI Foundry manages (API credentials, the tenants' gateway keys) in an OpenBao/Vault KV v2 mount. |
| `ai-foundry-mcp` | The AI Foundry MCP server. |

The Docling service is no longer part of this chart: chat attachments are
converted by AI Services (`apiGateway.docling.url`).

## Install

Install [AI Services](45-ai-services.md) first.

```
helm dependency build charts/ai-foundry
helm upgrade --install ai-foundry charts/ai-foundry \
  --namespace ai-foundry --create-namespace \
  -f charts/ai-foundry/values.yaml \
  -f <your-secrets-values-file> \
  charts/ai-foundry
```

The chart checks its configuration at render time
(`templates/validate-values.yaml` of the `ai-foundry` chart): an incomplete
combination fails `helm upgrade` with a message that names the setting,
rather than surfacing later as a `503`.

> **All-in-one layout:** this chart shares component names (`api-gateway`,
> `authtool-bff`, `adk-be-app`, `access-control`, …) with Services and
> Catalog, so installing it into a shared namespace requires the
> `values.all-in-one.yaml` overlay, which sets `ai-foundry.namespacePrefix:
> aif` and renames every resource to `aif-*`:
>
> ```
> helm upgrade --install ai-foundry charts/ai-foundry \
>   --namespace default --create-namespace \
>   -f charts/ai-foundry/values.yaml \
>   -f charts/ai-foundry/values.all-in-one.yaml \
>   -f <your-secrets-values-file> \
>   charts/ai-foundry
> ```
>
> The overlay also overrides two values that aren't derived from the prefix
> automatically: `authtoolBffUrl` (`http://aif-authtool-bff`, without which AI
> Foundry would resolve `authtool-bff` to another product's service in the
> shared namespace) and `aiFoundryWorkflows.config.temporalAddress`
> (`ais-temporal-frontend.default.svc.cluster.local:7233`, AI Services'
> prefixed Temporal frontend). In the local `kind` setup that's
> `make 050_ai_foundry_all_in_one`; see
> [Installation layouts](10-overview.md#installation-layouts).

## `values.yaml` reference

All configuration lives under the `ai-foundry` key.

| Field | Required | Description |
|---|---|---|
| `url` | Yes | Public URL for AI Foundry. |
| `authzUrl` | Yes | Services (homepage) URL, for the authorization check. |
| `catalogUrl` | Yes | Catalog URL, for catalog integration. |
| `authtoolBffUrl` | Yes | This chart's own `authtool-bff` Service, which exchanges the caller's token for the other products' audiences. ⚠️ If you set `namespacePrefix` (as the all-in-one overlay does), update this to match, e.g. `http://aif-authtool-bff`. |
| `catalogClientId` / `authzClientId` | Yes | Client IDs registered in Keycloak for calling Catalog/Authorization. |
| `aiServicesClientId` | Yes | Audience of the token exchange towards AI Services (`ai-services-api`). Without it, docling, memory and the AI gateway would receive an AI Foundry token and refuse it. |
| `authorizationServer.issuer` | Yes | Keycloak realm issuer URL. |
| `ingressRoute.enabled` | Yes (if using Traefik) | Disable and configure your own ingress otherwise. |
| `secrets.*.enabled` | Yes | Toggles gating each secrets block below. Set to `true` to have the chart render the Secret from these `values.yaml` fields, or `false` to reuse a Secret you manage outside the chart — see [Bringing your own Secret](#bringing-your-own-secret). |
| `adkBeApp.config.litellmProxyApiBase` | Yes | The AI gateway: `<ai-services url>/ai-gateway/`. Every model call goes through it; models and provider credentials (Vertex AI, OpenAI, Anthropic, …) are registered from the AI Foundry UI, not in `values.yaml`. |
| `adkBeApp.config.agentMemoryBaseUrl` / `aiFoundryBff.config.memoryBaseUrl` | No | AI Services URL, for agent memory. |
| `aiFoundryBe.config.litellmBaseUrl` | Yes | Same AI gateway URL, for its admin API. Requires `secrets.aiFoundryBeKeys.litellmAdminKey`. |
| `aiFoundryProvisioner.clientId` / `serve.enabled` | Yes | The `ai-foundry-provisioner` service account created by the realm, and the workload that publishes its public key at `<url>/.well-known/ai-foundry-provisioner/jwks.json` (Keycloak verifies the account's assertions against it). |
| `aiFoundryProvisioner.mcpServers.*` | Yes | URLs of the Catalog, Services and AI Services memory MCP servers registered as default items. |
| `aiFoundryWorkflows.config.temporalAddress` | Yes | AI Services' Temporal frontend, in-cluster: `temporal-frontend.<ai-services namespace>.svc.cluster.local:7233`. |
| `aiFoundryWorkflows.config.temporalNamespace` | Yes | A *Temporal* namespace (not a Kubernetes one) listed in AI Services' `temporal.namespaces`. |
| `secretStoreService.config.storeAddr` / `storeKvMount` / `auth` | Yes | Address of your OpenBao/Vault, the KV v2 mount AI Foundry writes under, and the JWT mount and role for the pod's ServiceAccount. See [Prerequisites](20-prerequisites.md#openbao-or-vault). |
| `apiGateway.docling.url` | Yes | AI Services' Docling route: `<ai-services url>/api/docling/`. |
| `workspaceService.config.*` | No | Runner images, flavours, node selector. `allowArbitraryCommands` (off) lets workflow steps run code from the cloned repository, and requires a dedicated node pool or a sandboxed runtime class. |
| `aiFoundryWebsite.config.links` | No | Cross-links shown in the AI Foundry UI (Console, Catalog, homepage, and various documentation URLs) — point these at your own products' URLs. |
| `telemetry.enabled` / `otelExporterOtlpEndpoint` | No | On here: OpenTelemetry export to AI Services' collector (`otel-collector.ai-services`, gRPC 4317). `adkBeApp.config.otelExporterOtlpEndpoint` sends the runtime over OTLP/HTTP (4318) to the same collector. |
| `aiFoundryBe.config.langfuseBaseUrl` / `adkBeApp.config.langfuseBaseUrl` | No | Langfuse base URL, read by AI Traces, Insights and the agents' observability tools, with `secrets.aiFoundryBeKeys.langfuseAuthHeader` / `adkBeAppKeys.langfuseAuthHeader` = `Basic base64(publicKey:secretKey)` of the project the collector writes to. See [Prerequisites](20-prerequisites.md#langfuse-observability). |
| `aiFoundryBe.config.prometheusBaseUrl` / `adkBeApp.config.prometheusBaseUrl` | No | AI Services' Prometheus (`http://prometheus.ai-services.svc.cluster.local`), read by AI Metrics. No credential: it is in-cluster only. |

To have more details on the values you can update, please refer to the [JSON Schema of the AI Foundry chart](https://cdn.mia-platform.eu/runtime/platform/ai-foundry/ai-foundry-helm-chart/0.5.0/values.schema.json).

## Secrets

Generated in this repository via `charts/ai-foundry/render_values.sh`:

- **`accessControlKeys.privateKey`** — shared with the other products'
  `authtoolBffKeys`/`accessControlKeys` key material.
- **`authtoolBffKeys`** — `tokenEncKey`, `cookieSecret`, plus per-client
  `privateKey`s (`website`, `exchangeAuthz`, `exchangeCatalog`,
  `exchangeAiServices`) — must match Services'/Catalog's `authtoolBffKeys`
  key material.
- **`adkBeAppKeys.postgresConnectionString`** — connection string to the
  shared `adk` Postgres database, `postgresql+asyncpg://…`.
- **`aiFoundryBeKeys`** — `postgresConnectionString` to the **same** `adk`
  database, as a plain `postgresql://…` URL; `litellmAdminKey`, which **must
  be** AI Services' `litellmProxyKeys.masterKey`; `mcpConsentKeySecret`, a
  random value that signs MCP OAuth consents.
- **`aiFoundryWorkflowsKeys.postgresConnectionString`** — the **same** `adk`
  database again (workflow definitions are written there by `adk-be-app` and
  `ai-foundry-be`).
- **`aiFoundryProvisionerKeys.privateKey`** — the provisioner service
  account's own RSA key. Keep it distinct from the shared client key: that
  account is a platform superadmin, and Keycloak accepts an assertion signed
  with any key it publishes.
- **`workspaceServiceKeys.postgresConnectionString`** — a database of its
  own (`workspace`), `postgresql://…`.

`adkBeAppKeys.googleApplicationCredentials` no longer exists: provider
credentials are registered on the AI gateway.

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
in the all-in-one layout, e.g. `aif-adk-be-app-keys`) and contain these keys:

- **`access-control-keys`** (`secrets.accessControlKeys.enabled`): only
  rendered/expected if
  `accessControl.config.externalContext.enabled` and
  `.authorization.enabled` are both `true`; then `key.pem` if
  `.authorization.tokenAuthMethod` is `private_key_jwt`, otherwise
  `client-secret`.
- **`adk-be-app-keys`** (`secrets.adkBeAppKeys.enabled`):
  `postgresConnectionString`
- **`authtool-bff-keys`** (`secrets.authtoolBffKeys.enabled`):
  `redis-token-enc.key`, `cookie-secret.key`, plus one
  `<client>-key.pem`/`<client>-client-secret` per entry configured under
  `authtoolBff.config.clients` (by default `website-key.pem`,
  `exchangeCatalog-key.pem`, `exchangeAuthz-key.pem`,
  `exchangeAiServices-key.pem`).

For the Secrets of the components added in 15.2 (`ai-foundry-be-keys`,
`ai-foundry-workflows-keys`, `ai-foundry-provisioner-keys`,
`secret-store-service-keys`, `workspace-service-keys`), render the chart once
with `enabled: true` and placeholder values (`helm template …`) to see the
exact key names it expects.

## Upgrading from 15.1

- Install [AI Services](45-ai-services.md) and an OpenBao/Vault store before
  upgrading, and create the new databases (`workspace`, plus AI Services'
  ones) — see [Prerequisites](20-prerequisites.md).
- Upgrade [Keycloak Realms](40-keycloak-realms.md) first: the realm must have
  the `aiServices` product enabled and the `ai-foundry-provisioner` client.
- Remove `adkBeApp.config.googleCloudProject`, `googleCloudLocation`,
  `googleGenaiUseVertexai` and `adkBeAppKeys.googleApplicationCredentials`
  from your values: models are now reached through the AI gateway. After the
  upgrade, register your models and provider credentials from the AI Foundry
  UI.
- AI Foundry 15.2 expects **Catalog and Services 15.2** as well: the
  provisioner writes into Catalog as the `ai-foundry-provisioner` service
  account, which Catalog's policies have to recognise, and it registers the
  Catalog and Services MCP servers (`/mcp`) as default items.

## Verify

- `kubectl get pods -n ai-foundry` — pods `Running`, and the
  `ai-foundry-provisioner` Job `Completed`. (All-in-one layout:
  `kubectl get pods -n default -l app.kubernetes.io/instance=ai-foundry`, or
  look for the `aif-` prefixed pods.)
- Visit the AI Foundry URL and confirm you can sign in and that the
  cross-links to Console/Catalog/homepage resolve correctly.
- Sign in with the username/password of the user you created in the
  `mia-realm` realm (or the realm name you chose) (see
  [Keycloak Realms: bootstrap the first super-admin](40-keycloak-realms.md#post-install-bootstrap-the-first-super-admin)).
  Alternatively, the **Register** button on the login page lets anyone
  create a new user on the spot — those self-registered users only get
  regular (non-admin) permissions.
- Register a model in the AI Foundry UI and chat with an agent: the call
  goes through AI Services' AI gateway.
