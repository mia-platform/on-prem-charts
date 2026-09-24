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
> The overlay also overrides `authtoolBffUrl` to `http://aif-authtool-bff`
> (see the table below) — that one isn't derived from the prefix
> automatically, and without it AI Foundry would resolve `authtool-bff` to
> another product's service in the shared namespace. In the local `kind`
> setup that's `make 050_ai_foundry_all_in_one`; see
> [Installation layouts](10-overview.md#installation-layouts).

## `values.yaml` reference

All configuration lives under the `ai-foundry` key.

| Field | Required | Description |
|---|---|---|
| `url` | Yes | Public URL for AI Foundry. |
| `authzUrl` | Yes | Services (homepage) URL, for the authorization check. |
| `catalogUrl` | Yes | Catalog URL, for catalog integration. |
| `authtoolBffUrl` | No | Cross-cluster token-exchange endpoint. Leave empty to forward the caller's JWT verbatim (same-cluster pass-through mode). ⚠️ Must point at *this* chart's own `authtool-bff` Service — if you set `namespacePrefix` (as the all-in-one overlay does), update this to match, e.g. `http://aif-authtool-bff`. |
| `catalogClientId` / `authzClientId` | Yes | Client IDs registered in Keycloak for calling Catalog/Authorization. |
| `authorizationServer.issuer` | Yes | Keycloak realm issuer URL. |
| `ingressRoute.enabled` | Yes (if using Traefik) | Disable and configure your own ingress otherwise. |
| `secrets.*.enabled` | Yes | Toggles gating each secrets block below. Set to `true` to have the chart render the Secret from these `values.yaml` fields, or `false` to reuse a Secret you manage outside the chart — see [Bringing your own Secret](#bringing-your-own-secret). |
| `adkBeApp.config.googleCloudProject` / `googleCloudLocation` / `googleGenaiUseVertexai` | Only if using Vertex AI | GCP project/region; adjust or remove if not using GCP. |
| `aiFoundryWebsite.config.links` | No | Cross-links shown in the AI Foundry UI (Console, Catalog, homepage, and various documentation URLs) — point these at your own products' URLs. |
| `telemetry.enabled` / `otelExporterOtlpEndpoint` | No | OpenTelemetry export, disable if you don't run a collector. |

To have more details on the values you can update, please refer to the [JSON Schema of the AI Foundry chart](https://cdn.mia-platform.eu/runtime/platform/ai-foundry/ai-foundry-helm-chart/0.4.82/values.schema.json).

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
  `postgresConnectionString` and `google-application-credentials.json`
- **`authtool-bff-keys`** (`secrets.authtoolBffKeys.enabled`):
  `redis-token-enc.key`, `cookie-secret.key`, plus one
  `<client>-key.pem`/`<client>-client-secret` per entry configured under
  `authtoolBff.config.clients` (by default `website-key.pem`,
  `exchangeCatalog-key.pem`, `exchangeAuthz-key.pem`,
  `exchangeAiServices-key.pem`).

## Verify

- `kubectl get pods -n ai-foundry` — pods `Running`. (All-in-one layout:
  `kubectl get pods -n default -l app.kubernetes.io/instance=ai-foundry`, or
  look for the `aif-` prefixed pods.)
- Visit the AI Foundry URL and confirm you can sign in and that the
  cross-links to Console/Catalog/homepage resolve correctly.
- Sign in with the username/password of the user you created in the
  `mia-realm` realm (or the realm name you chose) (see
  [Keycloak Realms: create a super-admin user](40-keycloak-realms.md#post-install-create-a-super-admin-user)).
  Alternatively, the **Register** button on the login page lets anyone
  create a new user on the spot — those self-registered users only get
  regular (non-admin) permissions.
