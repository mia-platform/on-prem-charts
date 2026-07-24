# Migration Guide

## Migrate Mia-Platform Console from v14.x to v15.0.0

This guide applies to on-prem customers who already run Console v14.x and
are upgrading it to v15.0.0 as part of installing the broader Mia Platform
product suite in the same cluster. For a first-time installation with no
prior version, use [`docs/`](docs/README.md) directly; this guide is not
required in that case.

### Scope of the migration

- Home (Services), Catalog, and AI Foundry are new products for this
  installation. They do not replace any existing component and can be
  installed by following [`docs/`](docs/README.md).
- Keycloak is also new. It replaces Console's previous native
  authentication implementation (the `authenticationService` component and
  its built-in identity-provider handling). After migration, Console no
  longer authenticates users directly; authentication is delegated to
  Keycloak.
- Console is the only component upgraded in place, from v14.x to v15.0.0,
  within the same cluster and namespace where it currently runs.

### Order of operations

Install Keycloak first (see [Keycloak](docs/03-keycloak.md)). Before
installing Keycloak Realms, configure identity provider federation in the
realm values as described below; this replaces the `authProviders`
configuration previously defined natively in Console. Install Keycloak
Realms only after this step (see
[Keycloak Realms](docs/04-keycloak-realms.md)). Before upgrading Console,
check the `userInfo` collection for duplicate users as described below —
this step must be completed before the upgrade, not after. Once these
steps are complete, update Console's `values.yaml` for v15 and run `helm
upgrade` against the existing Console release and namespace. Home,
Catalog, and AI Foundry can be installed at any point afterward, in any
order, by following [`docs/`](docs/README.md).

### Configure the Identity Provider before installing realms

In v14, the external IdP (Okta, an existing Keycloak instance, etc.) was
configured directly in Console via
`miaconsole.configurations.authProviders`. In v15, this federation is
configured entirely in the `products` realm (`mia-platform`), via
`identityProviders` and `identityProviderMappers` in
[`charts/keycloak-realms/values/prod/production/products.yaml`](charts/keycloak-realms/values/prod/production/products.yaml)
— currently empty placeholders (`identityProviders: []`,
`identityProviderMappers: []`) to be populated with the customer's IdP
configuration.

Example identity provider configuration:

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

#### Purpose of the `provider_sub` mapping

Console's `userInfo` MongoDB collection identifies existing users by a
`providerUserId` field, derived from whichever identifier the v14 setup
used. The `oidc-user-attribute-idp-mapper` shown above copies the IdP's
stable identifier claim into a Keycloak user attribute named
`provider_sub`. This mapping allows an existing v14 user to authenticate
through the new Keycloak-brokered flow while resolving to their existing
`userInfo` document, rather than having Console create a new one. If this
claim mapping is incorrect, affected users may lose access to their
existing history and permissions on their first login after migration.

### Check for duplicate `providerUserId` values before upgrading

Console's v15 `userInfo` collection enforces a unique partial index on
`providerUserId`, scoped to documents where `__STATE__` is `"PUBLIC"`
(i.e., active, non-removed users — `__STATE__` is the CRUD Service's
standard soft-delete marker). If the existing v14 data contains duplicate
`providerUserId` values among active users, index creation, and
consequently the upgrade, will fail. This is not expected to occur
frequently, but should be verified before upgrading.

Run the following aggregation against the `userInfo` collection before
upgrading Console, to identify duplicates:

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

If this query returns results, they must be resolved before proceeding
with the upgrade. Because `providerUserId` values originate from the
customer's own Identity Provider, resolving duplicates — including which
record to retain — is the customer's responsibility.

### Console `values.yaml` changes

The following compares a representative v14 `values.yaml` with the
current v15 `charts/console/values.yaml`.

#### Removed in v15

| v14 field | Reason |
|---|---|
| `miaconsole.configurations.authProviders` | Replaced by Keycloak `identityProviders`/`identityProviderMappers` (see above). |
| `miaconsole.configurations.userAccountAuthProvider` (`tokenPassphrase`, `jwtTokenPrivateKey*`) | Replaced by Keycloak and `authtoolBff.keys`. |
| `miaconsole.authenticationService` (the whole component) | Removed — Keycloak replaces Console's native auth service entirely. |
| `miaconsole.configurations.enableUserSynchronizationWebhooks` | Specific to syncing users from the native auth service; no longer applicable. |
| `miaconsole.configurations.additionalAuthenticationClients` | No v15 equivalent in this repository's reference values. If in use (e.g. for a local MCP-server login flow), this requires manual review rather than a direct migration. |
| `imageCredentials.username` / `imageCredentials.password` (root and `miaconsole` level) | Replaced by a Kubernetes image pull secret — see `imagePullSecrets`/`imageCredentials.name` in [Console](docs/08-console.md). |
| `miaconsole.configurations.serviceAccountAuthProvider.rsaPrivateKeyPass` | No longer part of the schema; the service-account private key is no longer passphrase-protected. |

#### Added in v15

| v15 field | Purpose |
|---|---|
| `miaconsole.configurations.keycloak.protocol` / `host` / `realm` / `extensibilityRealmName` | Points Console at the new Keycloak instance and realms. Required. |
| `miaconsole.authtoolBff.keys` (`privateKey`, `cookieSecret`, `redisTokenEncKey`) | New BFF component that bridges Keycloak-issued tokens — see [Console secrets](docs/08-console.md#secrets). |
| `miaconsole.extensibilityManagerService.keys.registrarPrivateKey` | New — used to register extensibility clients. |
| top-level `dns` | New field alongside `consoleDNS`/`consoleCMSDNS` in production-style overlays. |

#### Changed structure

| Field | v14 shape | v15 shape |
|---|---|---|
| `miaconsole.configurations.redis.hosts` | List of plain host strings | List of `{ip, port}` objects |
| `miaconsole.configurations.audit` | `configurations.audit.mongodbUrl` (plain value) | `configurations.audit.envs.mongodbUrl` (nested under `envs`, secret-injected) |

### Suggested upgrade command

Once the realm and `values.yaml` changes described above are in place,
the following command can be used as a starting point; adjust it to match
existing deployment conventions:

```
helm upgrade --install console charts/console \
  --namespace <existing-console-namespace> \
  -f charts/console/values.yaml \
  -f <your-secrets-values-file> \
  --rollback-on-failure --timeout 5m \
  charts/console
```

`--rollback-on-failure`, combined with `--timeout`, instructs Helm to
automatically roll back to the previous release if the upgrade does not
stabilize within the specified time. Adjust the timeout according to the
environment's requirements. On Helm v3, use `--atomic` instead: it is the
same flag under its pre-v4 name, and v3 does not recognize
`--rollback-on-failure`.

## Troubleshooting

See [`docs/09-troubleshooting.md`](docs/09-troubleshooting.md), which
includes a section dedicated to issues that may arise during this
migration.
