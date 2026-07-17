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

## Post-install: rename the default tenant

The seed data provisions a default tenant with a generic name and
description. If you'd rather not keep that default, you can rename it
through the api-portal exposed by the homepage, using the authorization
(RBAC) APIs:

1. **Open the api-portal.** From your homepage URL, go to
   `/documentations/api-portal` (e.g.
   `https://<your-homepage-url>/documentations/api-portal`).
2. **List the tenants.** Call `GET /api/authz/admin/tenants` and, in the
   response, find the default system tenant.
3. **Note its `id` and `version`.** Both values are needed to perform the
   update in the next step — the `version` acts as an optimistic-concurrency
   check, so it must match the tenant's current value or the patch will be
   rejected.
4. **Patch the tenant.** Call
   `PATCH /api/authz/admin/tenants/{tenantId}`, passing the `id` and
   `version` you just retrieved together with the `name` and `description`
   you want to assign to the tenant.

Once the patch succeeds, the new name and description are reflected
wherever the tenant is shown (e.g. in Catalog).
