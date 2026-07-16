# Services (Home + Authorization)

Chart: `charts/services` · Depends on: Keycloak Realms, PostgreSQL (`authz`, `adk`)

This chart installs the platform homepage and the authorization (RBAC)
service that other products (Catalog, AI Foundry, Console) call to check
permissions.

## Install

```
helm dependency build charts/services
helm upgrade --install services charts/services \
  --namespace services --create-namespace \
  -f charts/services/values.yaml \
  -f <your-secrets-values-file> \
  charts/services
```

## `values.yaml` reference

All configuration lives under the `services` key.

| Field | Required | Description |
|---|---|---|
| `url` | Yes | Public URL for the homepage. |
| `authorizationServer.issuer` | Yes | The Keycloak realm issuer URL products authenticate against (`https://<keycloak-host>/realms/<realm>`). |
| `ingressRoute.enabled` | Yes (if using Traefik) | Disable and configure your own ingress otherwise. |
| `hooks.seedData.configurations.default.products` | Yes | The product tiles/URLs shown on the homepage — one entry per product you're installing, with its public URL. |
| `hooks.postgresConnectivityCheck.enabled` / `issuerConnectivityCheck.enabled` | No | Pre-flight checks; enable once your Postgres/Keycloak are reachable. |
| `secrets.adkBeAppKeys.enabled` / `authtoolBffKeys.enabled` / `rbacManagementKeys.enabled` | Yes | Toggles that gate the Secrets below — must be `true`. |
| `telemetry.enabled` / `otelExporterOtlpEndpoint` | No | OpenTelemetry export, disable if you don't run a collector. |
| `apiGateway.extraVirtualHosts` | Yes | Hostnames the internal API gateway should route for — must include your homepage hostname. |

## Secrets

This chart expects a Secret (this repository generates it via
`charts/services/render_values.sh` into `.local/secrets.yaml`) providing:

- **`adkBeAppKeys`** — `postgresConnectionString` for the shared `adk`
  Postgres database.
- **`authtoolBffKeys`** — `tokenEncKey`, `cookieSecret`, `privateKey`: key
  material for token/cookie encryption between products (shared across
  Catalog, Services, and AI Foundry — must be the same value in all three).
- **`rbacManagementKeys`** — `postgresConnectionString` for the `authz`
  Postgres database, and `privateKey`.

Generate your own values for these in your own secret-management approach
rather than reusing this repository's `.local/` dev key material — but keep
`authtoolBffKeys`'s key material identical across the Services, Catalog, and
AI Foundry installs, since they need to interoperate.

## Verify

- `kubectl get pods -n services` — pods `Running`.
- Visit the homepage URL and confirm you can sign in via Keycloak and see
  the product tiles configured in `hooks.seedData`.
- Sign in with the username/password of the user you created in the
  `mia-platform` realm (see
  [Keycloak Realms: create a super-admin user](04-keycloak-realms.md#post-install-create-a-super-admin-user)).
  Alternatively, the **Register** button on the login page lets anyone
  create a new user on the spot — those self-registered users only get
  regular (non-admin) permissions.
