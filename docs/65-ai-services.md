# AI Services

Chart: `charts/ai-services` · Depends on: Keycloak Realms (`aiServices`
product), Services, PostgreSQL (`litellm`, `temporal`,
`temporal_visibility`, `memory`)

Installs AI Services, the shared AI infrastructure AI Foundry runs on:

| Component | What it does | Who calls it |
|---|---|---|
| `api-gateway` (Envoy) + `access-control` | The product's edge, published at `url`. Verifies the caller's token (issuer + `ai-services-api` audience) before the gated routes. | AI Foundry, MCP clients |
| `litellm-proxy` | The **AI gateway**, at `/ai-gateway`. Every model call of AI Foundry goes through it; models, provider credentials, teams and virtual keys live in its own database. | `adk-be-app`, `ai-foundry-be` (admin API, with the master key) |
| `temporal-*` | The Temporal cluster that runs AI Foundry's **Agentic Workflows**, plus its Web UI at `/workflow-manager`. | `ai-foundry-workflows` (in-cluster, port `7233`) |
| `docling-service` | Document conversion for chat attachments, at `/api/docling/`. | AI Foundry's edge |
| `memory-service` | Agent memory, at `/api/memories` and the MCP endpoint `/memory/mcp`. | `adk-be-app`, `ai-foundry-bff`, MCP clients |

Install it **before AI Foundry**: AI Foundry's workflows worker connects to
Temporal at startup, and its agents cannot reach a model without the AI
gateway.

## Install

```
helm dependency build charts/ai-services
helm upgrade --install ai-services charts/ai-services \
  --namespace ai-services --create-namespace \
  -f charts/ai-services/values.yaml \
  -f <your-secrets-values-file> \
  charts/ai-services
```

> **The namespace matters.** AI Foundry reaches Temporal in-cluster at
> `temporal-frontend.<namespace>.svc.cluster.local:7233`
> (`ai-foundry.aiFoundryWorkflows.config.temporalAddress`). If you install AI
> Services into a namespace other than `ai-services`, update that value too.

> **All-in-one layout:** AI Services shares component names (`api-gateway`,
> `access-control`) with the other products, so in a shared namespace apply
> the `values.all-in-one.yaml` overlay, which sets
> `ai-services.namespacePrefix: ais` and renames every resource to `ais-*`:
>
> ```
> helm upgrade --install ai-services charts/ai-services \
>   --namespace default --create-namespace \
>   -f charts/ai-services/values.yaml \
>   -f charts/ai-services/values.all-in-one.yaml \
>   -f <your-secrets-values-file> \
>   charts/ai-services
> ```
>
> AI Foundry's own all-in-one overlay then points its Temporal address at
> `ais-temporal-frontend.default.svc.cluster.local:7233`. In the local `kind`
> setup that's `make 045_ai_services_all_in_one`; see
> [Installation layouts](10-overview.md#installation-layouts).

## `values.yaml` reference

All configuration lives under the `ai-services` key.

| Field | Required | Description |
|---|---|---|
| `url` | Yes | Public URL of AI Services. AI Foundry points at it (`/ai-gateway/`, `/api/docling/`, memory). |
| `authorizationServer.issuer` | Yes | Keycloak realm issuer URL. |
| `authzUrl` | Yes | Services (homepage) URL: `access-control` resolves the caller's tenant context against it. |
| `apiGateway.authorizationServer.audiences` | Yes | Keep `["ai-services-api"]`. Empty would let *any* token of the realm through, bypassing the permission checks made by AI Foundry's own gateway. |
| `ingressRoute.enabled` | Yes (if using Traefik) | Disable and configure your own ingress otherwise. |
| `secrets.*.enabled` | Yes | Same convention as the other products — see [Secrets](#secrets). |
| `litellmProxy.extraEnv.MCP_TRUSTED_REDIRECT_ORIGINS` | Yes | AI Foundry's hostname, so the gateway accepts it as the redirect origin of MCP OAuth flows. |
| `temporal.persistence.*` | Yes | Database names of Temporal's default and visibility stores. `sql.createDatabase: false` expects both to exist already (see [Prerequisites](20-prerequisites.md#postgresql)). |
| `temporal.namespaces` | Yes | The Temporal namespace(s) to create. Must contain AI Foundry's `aiFoundryWorkflows.config.temporalNamespace` (`ai-services` by default). |
| `temporalUi.auth.enabled` / `clientId` | Recommended | The Temporal UI shows the inputs and payloads of every workflow run: with `auth.enabled` it signs users in through the realm's `ai-services-temporal-ui` client. Left off, the UI is open to anyone who can reach `url`. |
| `memoryService.enabled` | No | On by default here. Without `memoryService.config.embeddingModel`, memory search uses keyword ranking; to use semantic search, register an embedding model on the AI gateway and set `config.embeddingModel` + `config.aiGateway.enabled` (see the chart README). |
| `otelCollector.enabled` / `config.langfuse.tracesEndpoint` | No | On here. The OpenTelemetry Collector every AI Services and AI Foundry service exports to: traces go to Langfuse's OTLP endpoint (`…/api/public/otel/v1/traces`), with `secrets.otelCollectorKeys.langfuseOtlpBasic` = `base64(publicKey:secretKey)` of the Langfuse project; metrics go to `prometheus`. See [Prerequisites](20-prerequisites.md#langfuse-observability). |
| `prometheus.enabled` | No | On here. Receives the collector's metrics over OTLP (nothing scrapes the services) and is read by AI Foundry's AI Metrics; in-cluster only, no route on the edge. Keeps `prometheus.config.retentionTime` (15 days) on a `persistence.size` volume. |
| `telemetry.enabled` / `otelExporterOtlpEndpoint` | No | On here, pointing at the collector above (`ais-otel-collector.default` in the all-in-one layout). LiteLLM finds the in-release collector by itself. |

> **What is public on this edge.** LiteLLM (all of `/ai-gateway`, including
> its admin API and UI) and the Temporal UI route opt out of the token check
> by design. The LiteLLM **master key** is therefore an internet-facing
> password: keep it secret and do not give out the AI Services hostname
> freely.

For every other value, see the AI Services chart README (bundled in the
`ai-services` chart under `charts/ai-services/charts/` after
`helm dependency build`). The chart does not publish a JSON Schema yet.

## Secrets

Generated in this repository via `charts/ai-services/render_values.sh`:

- **`accessControlKeys.privateKey`** — the `ai-services-access-control`
  service account signs its client assertion with it; Keycloak verifies it
  against `<url>/.well-known/jwks.json`.
- **`litellmProxyKeys`** — `postgresConnectionString` (`postgresql://…`, a
  database of LiteLLM's own), `masterKey` (admin key; **must be the same
  value** as AI Foundry's `aiFoundryBeKeys.litellmAdminKey`) and `saltKey`
  (encrypts the provider credentials stored in the database: **never rotate
  it** once models are registered, or they become unreadable).
- **`temporalKeys`** — `postgresHost`, `postgresPort`, `postgresUser`,
  `postgresPassword` of the server holding both Temporal databases.
- **`temporalUiKeys.authClientSecret`** — secret of the
  `ai-services-temporal-ui` client. It must match the realm's
  `${vault.ai-services-temporal-ui-client-secret}`, which this repository
  renders into Keycloak's `keycloak-vault-secrets` from the same key
  material (see [Keycloak: secrets](30-keycloak.md#secrets)).
- **`memoryServiceKeys.postgresConnectionString`** —
  `postgresql+asyncpg://…`, a database of its own with the `vector`
  extension.

Setting `secrets.<name>.enabled: false` makes the chart read an existing
Secret named `<component>-keys` instead (`ais-<component>-keys` in the
all-in-one layout), exactly as described for AI Foundry in
[Bringing your own Secret](70-ai-foundry.md#bringing-your-own-secret).

## Verify

- `kubectl get pods -n ai-services` — every pod `Running`, and the
  `temporal-schema-setup` / `temporal-namespace-setup` Jobs `Completed`.
- `kubectl logs -n ai-services deploy/litellm-proxy` shows the database
  migrations completed and the proxy listening (it runs them at every boot,
  so the first start takes up to a couple of minutes).
- Open `https://ai-services.mia-platform.test/workflow-manager/`
  (`make ai_services_open`): with `temporalUi.auth.enabled` you are sent to
  the Keycloak login, and after it the `ai-services` namespace is listed.
