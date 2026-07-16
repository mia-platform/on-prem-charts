# AI Foundry

Chart: `charts/ai-foundry` · Depends on: Services, Catalog, PostgreSQL (`adk`)

Installs the AI Foundry product.

## Install

```
helm dependency build charts/ai-foundry
helm upgrade --install ai-foundry charts/ai-foundry \
  --namespace ai-foundry --create-namespace \
  -f charts/ai-foundry/values.yaml \
  -f <your-secrets-values-file> \
  charts/ai-foundry
```

## `values.yaml` reference

All configuration lives under the `ai-foundry` key.

| Field | Required | Description |
|---|---|---|
| `url` | Yes | Public URL for AI Foundry. |
| `authzUrl` | Yes | Services (homepage) URL, for the authorization check. |
| `catalogUrl` | Yes | Catalog URL, for catalog integration. |
| `authtoolBffUrl` | No | Cross-cluster token-exchange endpoint. Leave empty to forward the caller's JWT verbatim (same-cluster pass-through mode). |
| `catalogClientId` / `authzClientId` | Yes | Client IDs registered in Keycloak for calling Catalog/Authorization. |
| `authorizationServer.issuer` | Yes | Keycloak realm issuer URL. |
| `ingressRoute.enabled` | Yes (if using Traefik) | Disable and configure your own ingress otherwise. |
| `secrets.*.enabled` | Yes | Toggles gating each secrets block below — must all be `true`. |
| `adkBeApp.config.googleCloudProject` / `googleCloudLocation` / `googleGenaiUseVertexai` | Only if using Vertex AI | GCP project/region; adjust or remove if not using GCP. |
| `aiFoundryWebsite.config.links` | No | Cross-links shown in the AI Foundry UI (Console, Catalog, homepage, and various documentation URLs) — point these at your own products' URLs. |
| `telemetry.enabled` / `otelExporterOtlpEndpoint` | No | OpenTelemetry export, disable if you don't run a collector. |

## Secrets

Generated in this repository via `charts/ai-foundry/render_values.sh`:

- **`accessControlKeys.privateKey`** — shared with the other products'
  `authtoolBffKeys`/`accessControlKeys` key material.
- **`authtoolBffKeys`** — `tokenEncKey`, `cookieSecret`, plus per-client
  `privateKey`s (`website`, `exchangeAuthz`, `exchangeCatalog`) — must match
  Services'/Catalog's `authtoolBffKeys` key material.
- **`adkBeAppKeys.postgresConnectionString`** — connection string to the
  shared `adk` Postgres database. (`googleApplicationCredentials` is left
  empty by default — set it if your Vertex AI integration needs a service
  account key.)

## Verify

- `kubectl get pods -n ai-foundry` — pods `Running`.
- Visit the AI Foundry URL and confirm you can sign in and that the
  cross-links to Console/Catalog/homepage resolve correctly.
- Sign in with the username/password of the user you created in the
  `mia-platform` realm (see
  [Keycloak Realms: create a super-admin user](04-keycloak-realms.md#post-install-create-a-super-admin-user)).
  Alternatively, the **Register** button on the login page lets anyone
  create a new user on the spot — those self-registered users only get
  regular (non-admin) permissions.
