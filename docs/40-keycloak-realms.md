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

> **Migrating an existing installation?** If you're installing this into a
> cluster that already runs Console v14.x, configuring `identityProviders`/
> `identityProviderMappers` here is a required migration step, not just a
> generic option — see the [Migration Guide](../MIGRATION_GUIDE.md). This
> only applies to existing installations; skip it for a fresh install.

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

Of each file, you can find more details on the values you can update in the [JSON Schema of the Keycloak Realms chart](https://cdn.mia-platform.eu/runtime/platform/auth/keycloak-realm-management/0.1.54/values.schema.json).

`template.sh` renders these into `keycloak-config-cli`-consumable YAML
under `rendered/<env>/<tier>/<realm-type>/`.

## Install

There's no `helm install` here — this chart only renders configuration.
Applying it means running `template.sh` to render a realm, then running
`keycloak-config-cli` against the rendered output. In this repository's
local dev setup, that's wrapped in two `make` targets that do both steps
for each realm type:

```
make keycloak_realms_master_as_admin_install
make keycloak_realms_production_install
```

> **Layout- and mode-independent.** These two targets are the same in both
> the namespace-per-product and the
> [all-in-one](10-overview.md#installation-layouts) layouts — and they're
> the only step that takes no `NAMESPACE`. `keycloak-config-cli` reaches
> Keycloak over the Admin REST API at its public URL (`KEYCLOAK_URL`), not
> through the cluster, so where Keycloak was installed makes no difference.
> `make 020_keycloak_realms` and `make 020_keycloak_realms_all_in_one` both
> just run the two targets above.
>
> The same goes for Keycloak's
> [run mode](30-keycloak.md#run-modes-operator-or-native): because realms
> here are imported over the Admin REST API rather than through the
> operator's `KeycloakRealmImport` custom resource, this step works
> unchanged when Keycloak is installed in native mode with no operator
> running.

The first renders and imports the `master` realm, authenticated as the
Keycloak admin user; the second loops over `products` and `extensibility`,
authenticated as the `keycloak-config-cli` client created during the
`master` import (see [Import order and credentials](#import-order-and-credentials)
below). See `charts/keycloak-realms/tools.mk` for the exact
`keycloak-config-cli` invocation and environment variables — in
production, replace it with however you run `keycloak-config-cli` against
your own cluster (e.g. a Kubernetes `Job`), pointed at your own
`KEYCLOAK_URL`, admin/client credentials, and TLS configuration, rather
than this repository's local, `--network host`-based `docker run`.

## Import order and credentials

1. **Master realm**, authenticated as the Keycloak admin user
   (`adminBootstrap.password` from the [Keycloak chart](30-keycloak.md)).
   This is where the `keycloak-config-cli` client itself gets created,
   with a client secret placeholder.
2. **Products** and **extensibility** realms, authenticated as that
   `keycloak-config-cli` client via `client_credentials` — its client
   secret must match what was configured for it during step 1.

> **Known issue:** this repository currently disables
> `keycloak-config-cli`'s variable-substitution feature
> (`IMPORT_VARSUBSTITUTION_ENABLED=false`) while the realm values files still
> contain `${vault....}`-style placeholders (e.g.
> `${vault.mia-identity-provider-client-secret}`,
> `${vault.keycloak-config-cli-client-secret}`). With substitution disabled,
> those placeholders are imported into Keycloak literally instead of being
> resolved to real secret values, which breaks the client secrets they're
> meant to hold. If you're using this repository as a reference, plan to
> either enable variable substitution with the matching environment
> variables, or replace the placeholders with your own real secret values
> before import.
>
> Note that a `${vault.<key>}` placeholder never includes the realm prefix
> used in `templates/vault.secret.yaml`'s `<realm>_<key>` Secret keys (see
> [Keycloak](30-keycloak.md)) — only the `<key>` part. This is why the
> `products.yaml` and `extensibility.yaml` realm files can both reference
> `${vault.mia-identity-provider-client-secret}` and still resolve
> to different values: `keycloak-config-cli` reads it against the
> `mia-realm_mia-identity-provider-client-secret` Secret key
> when importing the `products` realm, and against
> `mia-realm-extensibility_mia-identity-provider-client-secret`
> when importing `extensibility`.
>
> Note specifically that `${vault.mia-identity-provider-client-secret}`
> is not an arbitrary internal secret — it's the client secret for the
> **external Identity Provider** federation described in
> [Prerequisites](20-prerequisites.md#-external-identity-provider). It must
> be the actual `client_secret` (or equivalent) issued by that external
> IdP for the OIDC client you registered there, not a value you invent.

## Identity provider with group provisioning (mia-platform-oidc)

From v15.2.0 the Keycloak image ships the **`mia-platform-oidc`** identity
provider ([mia-platform-idp](https://git.tools.mia-platform.eu/platform/auth/mia-platform-idp)).
It brokers logins exactly like the built-in `oidc` provider. In addition,
after each login it pushes the user and the user's IdP groups into Home's
authorization service through its SCIM API. Authorization then follows
what your IdP asserts, as with proxy-header authorization: anyone in group
`X` at the IdP is in group `X` in Home, so nobody has to maintain those
memberships by hand.

### How it works

After every login that goes through the upstream IdP (not a silent SSO
re-authentication against an existing Keycloak session), the provider:

1. Gets an access token for the realm's **`scim-client`** service account
   (`client_credentials`, cached until shortly before it expires).
2. Makes sure the user exists in Home (`<endpoint>/Users`). It first looks
   for `externalId` = the Keycloak user id, then for the email address,
   and creates the user only if neither lookup finds them.
3. Reads the groups claim (default `groups`) from the **upstream access
   token** and aligns the user's Home groups (`<endpoint>/Groups`) with it:
   - The user is added to every listed group. Groups that don't exist yet
     are created, with the listed name as `displayName` and `externalId`.
   - The user is removed from every group that isn't listed.
   - The claim is authoritative: if it's absent or null, the user is
     removed from all managed groups.

Provisioning is part of the login. If the SCIM call fails, **the login
fails**, so a user never gets in without their permissions.

### Prerequisites

- **`scim-client`** in the `products` realm. Keycloak Realms declares it
  when `products.authz: true` (the default in
  [`products.yaml`](../charts/keycloak-realms/values/prod/production/products.yaml)).
  Its service account holds the `authz-api` roles
  `urn:mia-platform-internal:role:authz:provisioning:users` and
  `urn:mia-platform-internal:role:authz:provisioning:groups`.
- **Its secret** in the Keycloak vault, under key
  `mia-realm_scim-client-secret` (see
  [Keycloak: Secrets](30-keycloak.md#secrets)). The client and the
  identity provider both reference it as `${vault.scim-client-secret}`.
- **[Home](50-services.md)** installed and reachable from Keycloak, plus
  the id of the tenant users are provisioned into (`default` in this
  repository's seed data).
- An **upstream access token that is a JWT** carrying the groups claim.
  With Okta, use a custom authorization server: the org authorization
  server issues opaque access tokens, which can't be read. The provider
  never calls UserInfo for groups.

### Configuration

Set `providerId: mia-platform-oidc` on the identity provider in
`identityProviders` (in
[`products.yaml`](../charts/keycloak-realms/values/prod/production/products.yaml)).
Keep all the usual OIDC settings, and add the `miaScimClient*` keys:

```yaml
keycloak-realm-management:
  identityProviders:
    - alias: customer-idp
      displayName: <Your IdP display name>
      enabled: true
      providerId: mia-platform-oidc    # instead of oidc
      trustEmail: true
      config:
        # --- standard OIDC broker settings, as for providerId: oidc ---
        issuer: https://idp.example.com/oauth2/<custom-auth-server>
        authorizationUrl: https://idp.example.com/oauth2/<custom-auth-server>/v1/authorize
        tokenUrl: https://idp.example.com/oauth2/<custom-auth-server>/v1/token
        jwksUrl: https://idp.example.com/oauth2/<custom-auth-server>/v1/keys
        useJwksUrl: "true"
        logoutUrl: https://idp.example.com/oauth2/<custom-auth-server>/v1/logout
        clientId: <registered-client-id>
        clientAuthMethod: private_key_jwt
        defaultScope: openid email profile groups
        isAccessTokenJWT: "true"
        pkceEnabled: "true"
        pkceMethod: S256
        syncMode: IMPORT

        # --- SCIM provisioning through the realm's scim-client ---
        miaScimClientEndpoint: https://home.<your-domain>/api/scim/v2/tenants/<tenant>
        miaScimClientIssuerUrl: https://auth.<your-domain>/realms/mia-realm
        miaScimClientClientId: scim-client
        miaScimClientClientSecret: "${vault.scim-client-secret}"
        miaScimClientAuthMethod: client_secret_basic
        # miaScimClientGroupsClaim: groups                 # default
        # miaScimClientManagedGroups: "developers##admins"  # optional
```

| Key | Default | Description |
|---|---|---|
| `miaScimClientEndpoint` | — | Home's SCIM base URL for the tenant: `https://<home-host>/api/scim/v2/tenants/<tenant>`. If empty, provisioning is off and the provider behaves like `oidc`. |
| `miaScimClientIssuerUrl` | — | Issuer of the realm that issues the `scim-client` token, `https://<keycloak-host>/realms/<realm>`, or a full metadata URL. If empty, provisioning is off. |
| `miaScimClientClientId` | — | `scim-client`. |
| `miaScimClientClientSecret` | — | `"${vault.scim-client-secret}"`. Only used with the `client_secret_*` methods. |
| `miaScimClientAuthMethod` | `client_secret_basic` | `client_secret_basic`, `client_secret_post` or `private_key_jwt`. `private_key_jwt` signs with the realm's active key. |
| `miaScimClientGrantType` | `client_credentials` | Only grants that need no parameters beyond `scope` are supported. |
| `miaScimClientScope` | — | Space-separated scopes to request; leave empty to omit the parameter. |
| `miaScimClientGroupsClaim` | `groups` | Upstream access-token claim listing the user's group names (a string or an array of strings). Set it to an empty string to leave group memberships alone. |
| `miaScimClientManagedGroups` | — | Group names the claim is authoritative for, separated by `##` (Keycloak's multivalued format). If set, only these groups are added or removed, and other names in the claim are ignored. If empty, every group of the tenant is managed. |
| `miaScimClientAssertionAudience` | token endpoint | `private_key_jwt` only: audience of the client assertion. |
| `miaScimClientAssertionSigningAlg` | `RS256` | `private_key_jwt` only: the realm must have an active key for it. |
| `miaScimClientAssertionLifetimeSeconds` | `60` | `private_key_jwt` only. |
| `miaScimClientExpiryMarginSeconds` | `30` | How long before expiry a cached `scim-client` token stops being reused. |

> ⚠️ Because the claim is authoritative, groups you assign by hand in Home
> to a user brokered through this provider are removed on their next
> login. The exception is groups left out of `miaScimClientManagedGroups`,
> when that key is set. Use `miaScimClientManagedGroups` to scope the sync
> if Home also has groups managed manually.

You can combine this with the `identityProviderMappers` from the
[Migration Guide](../MIGRATION_GUIDE.md#configure-the-identity-provider-before-installing-realms)
(e.g. the `provider_sub` mapper and the hardcoded `products/console/guest`
group mapper). They work the same with `mia-platform-oidc`.

## Verify

- In the Keycloak admin console, confirm the `products` and `extensibility`
  realms exist with the expected clients/roles/groups.
- Confirm the `keycloak-config-cli` client in the `master` realm has a
  client secret that matches what you used to authenticate the
  products/extensibility import.

## Post-install: create a super-admin user

The `products` realm is imported under the realm name **`mia-realm`**
(not literally "products" — see `products/010-realm-settings.yaml`). This
name is a prototype value in this repository's example configuration — set
it to whatever realm name your installation actually uses, not a fixed
identifier. In that realm, create a new user with a username and password of your choice,
then add it to the **`products/authz/superadmin`** group. That group maps
the `authz-api` client role `urn:mia-platform-internal:role:authz:superadmin`,
which is what grants full administrative access across the products (Home,
Catalog, AI Foundry, Console) once you start using them — use this account
rather than the Keycloak admin account for day-to-day platform
administration.
