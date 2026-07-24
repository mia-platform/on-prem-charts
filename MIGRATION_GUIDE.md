# Migration Guide

## Migrate Mia-Platform Console from v14.x to v15.0.0

This guide is for existing on-prem customers who already run **Console
v14.x** in a cluster and are upgrading it to **v15.0.0** as part of
installing the wider Mia Platform product suite in that same cluster/
namespace. If you're installing from scratch with no prior version, you
don't need this guide — follow [`docs/`](docs/README.md) directly.

### What's actually changing

- **Home (Services), Catalog, and AI Foundry are brand new** for you — they
  don't replace anything, and can be installed by following
  [`docs/`](docs/README.md) with no migration concerns.
- **Keycloak is also brand new.** It replaces Console's previous native
  authentication implementation (the `authenticationService` component
  and its own built-in identity-provider handling). Once migrated, Console
  no longer authenticates users itself — it delegates entirely to
  Keycloak.
- **Console is the one component actually being upgraded in place**, from
  v14.x to v15.0.0, inside the same cluster/namespace it already runs in.

### Order of operations

Install Keycloak first (see [Keycloak](docs/03-keycloak.md)). Before
installing Keycloak Realms, configure your identity provider federation in
the realm values as described below — this replaces the `authProviders`
your v14 Console configured natively — and only then install Keycloak
Realms (see [Keycloak Realms](docs/04-keycloak-realms.md)). Before
touching Console itself, check for duplicate users in its `userInfo`
collection as described below; this has to happen before the upgrade, not
after. With that done, update Console's `values.yaml` for v15 and run
`helm upgrade` against the existing Console release/namespace. Home,
Catalog, and AI Foundry can be installed whenever convenient, in any
order, by following [`docs/`](docs/README.md).

### Configure your Identity Provider before installing realms

In v14, your external IdP (Okta, your own Keycloak, etc.) was configured
directly inside Console via `miaconsole.configurations.authProviders`. In
v15, that federation moves entirely into the **`products`** realm
(`mia-platform`), configured via `identityProviders` and
`identityProviderMappers` in
[`charts/keycloak-realms/values/prod/production/products.yaml`](charts/keycloak-realms/values/prod/production/products.yaml)
— currently empty placeholders (`identityProviders: []`,
`identityProviderMappers: []`) waiting for your IdP's details.

On-prem installations have exactly **one** external IdP (unlike Mia
Platform's own multi-organization setup, which is why the example below
has only one entry instead of several).

```yaml
keycloak-realm-management:
  identityProviders:
    - alias: customer-idp
      config:
        authorizationUrl: https://<your-idp>/oauth2/v1/authorize
        clientAuthMethod: private_key_jwt   # or client_secret, if that's what your IdP issues
        clientId: <your-oidc-client-id>
        defaultScope: openid email profile offline_access
        disableUserInfo: "true"
        isAccessTokenJWT: "true"
        issuer: https://<your-idp>
        logoutUrl: https://<your-idp>/oauth2/v1/logout
        pkceEnabled: "true"
        pkceMethod: S256
        sendIdTokenOnLogout: "true"
        syncMode: IMPORT
        tokenIntrospectionUrl: https://<your-idp>/oauth2/v1/introspect
        tokenUrl: https://<your-idp>/oauth2/v1/token
        jwksUrl: https://<your-idp>/oauth2/v1/keys
        useJwksUrl: "true"
        userInfoUrl: https://<your-idp>/oauth2/v1/userinfo
      displayName: <Your IdP display name>
      enabled: true
      providerId: oidc
      trustEmail: true

  identityProviderMappers:
    - name: customer-idp-uid-mapper
      config:
        claim: <the claim your IdP uses as a stable user identifier, e.g. sub or uid>
        syncMode: IMPORT
        user.attribute: provider_sub
      identityProviderAlias: customer-idp
      identityProviderMapper: oidc-user-attribute-idp-mapper
    - name: customer-idp-console-guest-mapper
      config:
        syncMode: FORCE
        group: /products/console/guest
      identityProviderMapper: oidc-hardcoded-group-idp-mapper
      identityProviderAlias: customer-idp
```

#### Why `provider_sub` matters

Console's `userInfo` MongoDB collection identifies existing users by a
`providerUserId` field, tied to whatever your old v14 setup used as a
stable user identifier. The `oidc-user-attribute-idp-mapper` above copies
your IdP's own stable identifier claim into a Keycloak user attribute
named **`provider_sub`** — this is what lets an existing v14 user log in
through the new Keycloak-brokered flow and still resolve to their
*existing* `userInfo` document, instead of Console creating a duplicate
new user for them. Get this claim mapping wrong and existing users will
appear to lose their history/permissions on first login post-migration.

### Check for duplicate `providerUserId` values before upgrading

Console's v15 `userInfo` collection enforces a **unique partial index** on
`providerUserId` (scoped to documents where `__STATE__` is `"PUBLIC"`,
i.e. non-removed users — `__STATE__` is the CRUD Service's standard
soft-delete marker). If your existing v14 data has duplicate
`providerUserId` values among active users, index creation — and the
upgrade — will fail.

Run this aggregation against the `userInfo` collection **before**
upgrading Console, to find duplicates:

```js
db.userInfo.aggregate([
  { $match: { __STATE__: "PUBLIC" } },
  {
    $group: {
      _id: "$providerUserId",
      count: { $sum: 1 },
      ids: { $push: "$_id" }
    }
  },
  { $match: { count: { $gt: 1 } } },
  { $sort: { count: -1 } }
])
```

If this returns any results, resolve them before upgrading. Since
`providerUserId` values come from your own Identity Provider, deciding
which duplicate to keep (or how to merge/remove the others) is entirely
in your hands as the IdP owner — there is nothing Mia Platform can do on
the Console/Keycloak side to resolve a collision it didn't create.

### Console `values.yaml` changes

Comparing a representative v14 `values.yaml` to the current v15
`charts/console/values.yaml`, here's what changes.

#### Removed in v15 (delete these from your values)

| v14 field | Why it's gone |
|---|---|
| `miaconsole.configurations.authProviders` | Replaced by Keycloak `identityProviders`/`identityProviderMappers` (see above). |
| `miaconsole.configurations.userAccountAuthProvider` (`tokenPassphrase`, `jwtTokenPrivateKey*`) | Replaced by Keycloak + `authtoolBff.keys`. |
| `miaconsole.authenticationService` (the whole component) | Removed — Keycloak replaces Console's native auth service entirely. |
| `miaconsole.configurations.enableUserSynchronizationWebhooks` | Was specific to syncing users from the native auth service; no longer applicable. |
| `miaconsole.configurations.additionalAuthenticationClients` | No v15 equivalent found in this repository's reference values. If you use this (e.g. for a local MCP-server login flow), treat it as needing manual review rather than a direct migration. |
| `imageCredentials.username` / `imageCredentials.password` (root and `miaconsole` level) | Replaced by a proper Kubernetes image pull secret — see `imagePullSecrets`/`imageCredentials.name` in [Console](docs/08-console.md). |
| `miaconsole.configurations.serviceAccountAuthProvider.rsaPrivateKeyPass` | No longer part of the schema — the service-account private key is no longer passphrase-protected. |

#### New in v15 (add these)

| v15 field | Purpose |
|---|---|
| `miaconsole.configurations.keycloak.protocol` / `host` / `realm` / `extensibilityRealmName` | Points Console at your new Keycloak instance and realms. Required. |
| `miaconsole.authtoolBff.keys` (`privateKey`, `cookieSecret`, `redisTokenEncKey`) | New BFF component that bridges Keycloak-issued tokens — see [Console secrets](docs/08-console.md#secrets). |
| `miaconsole.extensibilityManagerService.keys.registrarPrivateKey` | New — used to register extensibility clients. |
| top-level `dns` | New field alongside `consoleDNS`/`consoleCMSDNS` in production-style overlays. |

#### Changed shape (same concept, different structure)

| Field | v14 shape | v15 shape |
|---|---|---|
| `miaconsole.configurations.redis.hosts` | List of plain host strings | List of `{ip, port}` objects |
| `miaconsole.configurations.audit` | `configurations.audit.mongodbUrl` (plain value) | `configurations.audit.envs.mongodbUrl` (nested under `envs`, secret-injected) |

### Suggested upgrade command

Once the realm and `values.yaml` changes above are in place, here's a
suggested way to run the upgrade — adapt it to whatever conventions your
own deployment tooling already follows:

```
helm upgrade --install console charts/console \
  --namespace <existing-console-namespace> \
  -f charts/console/values.yaml \
  -f <your-secrets-values-file> \
  --rollback-on-failure --timeout 5m \
  charts/console
```

`--rollback-on-failure` (combined with `--timeout`) makes Helm
automatically roll back to the previous release if the upgrade isn't
stable within the given timeout — adjust the timeout to whatever window
makes sense for your environment. If you're on Helm v3, use `--atomic`
instead — `--rollback-on-failure` is the same flag under its new Helm v4
name, and v3 doesn't recognize it.

## Troubleshooting

See [`docs/09-troubleshooting.md`](docs/09-troubleshooting.md), which
includes a section specifically for issues that come up during any
migration.
