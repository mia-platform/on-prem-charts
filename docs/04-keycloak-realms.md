# Keycloak Realms

Chart: `charts/keycloak-realms` · Depends on: a running Keycloak instance

This one is different from the other charts: it doesn't deploy a workload.
It renders realm-configuration YAML from Helm templates and applies it to
the already-running Keycloak instance using
[`keycloak-config-cli`](https://github.com/adorsys/keycloak-config-cli),
a tool that idempotently imports/updates realm configuration through the
Keycloak Admin REST API. Use it as the reference for what realm
configuration this suite expects — you can apply the same configuration
with any tool that talks to that API (this `keycloak-config-cli`-based
flow, the Keycloak Admin CLI, Terraform's Keycloak provider, etc.).

Two realm types are configured:

- **`master`** — realm-level settings on the built-in `master` realm,
  applied via the Keycloak admin user (bootstrapped by the Keycloak chart).
- **`products`** and **`extensibility`** — the two realms product traffic
  actually authenticates against, applied via a dedicated
  `keycloak-config-cli` service account using the `client_credentials`
  grant.

## Configuration source

The realm configuration lives in `charts/keycloak-realms/values/prod/`:

| File | Realm | Contents |
|---|---|---|
| `master.yaml` | `master` | e.g. the `keycloak-config-cli` service-account client used to authenticate subsequent realm imports. |
| `production/products.yaml` | `products` | Clients, roles, groups, identity providers, etc. for the `products` realm. |
| `production/extensibility.yaml` | `extensibility` | Same, for the `extensibility` realm. |

`template.sh` renders these into `keycloak-config-cli`-consumable YAML
under `rendered/<env>/<tier>/<realm-type>/`.

## Import order and credentials

1. **Master realm**, authenticated as the Keycloak admin user
   (`adminBootstrap.password` from the [Keycloak chart](03-keycloak.md)).
   This is where the `keycloak-config-cli` client itself gets created,
   with a client secret placeholder.
2. **Products** and **extensibility** realms, authenticated as that
   `keycloak-config-cli` client via `client_credentials` — its client
   secret must match what was configured for it during step 1.

> **Known issue:** this repository currently disables
> `keycloak-config-cli`'s variable-substitution feature
> (`IMPORT_VARSUBSTITUTION_ENABLED=false`) while the realm values files still
> contain `${vault....}`-style placeholders (e.g.
> `${vault.mia-platform-identity-provider-client-secret}`,
> `${vault.keycloak-config-cli-client-secret}`). With substitution disabled,
> those placeholders are imported into Keycloak literally instead of being
> resolved to real secret values, which breaks the client secrets they're
> meant to hold. If you're using this repository as a reference, plan to
> either enable variable substitution with the matching environment
> variables, or replace the placeholders with your own real secret values
> before import.
>
> Note specifically that `${vault.mia-platform-identity-provider-client-secret}`
> is not an arbitrary internal secret — it's the client secret for the
> **external Identity Provider** federation described in
> [Prerequisites](02-prerequisites.md#-external-identity-provider). It must
> be the actual `client_secret` (or equivalent) issued by that external
> IdP for the OIDC client you registered there, not a value you invent.

## Verify

- In the Keycloak admin console, confirm the `products` and `extensibility`
  realms exist with the expected clients/roles/groups.
- Confirm the `keycloak-config-cli` client in the `master` realm has a
  client secret that matches what you used to authenticate the
  products/extensibility import.

## Post-install: create a super-admin user

The `products` realm is imported under the realm name **`mia-platform`**
(not literally "products" — see `products/010-realm-settings.yaml`). In
that realm, create a new user with a username and password of your choice,
then add it to the **`products/authz/superadmin`** group. That group maps
the `authz-api` client role `urn:mia-platform-internal:role:authz:superadmin`,
which is what grants full administrative access across the products (Home,
Catalog, AI Foundry, Console) once you start using them — use this account
rather than the Keycloak admin account for day-to-day platform
administration.
