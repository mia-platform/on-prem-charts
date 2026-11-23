# Migration Guide

## Migrate from v15.1.0 to v15.2.0

This guide applies to installations already running v15.1.0 of this
repository's charts.

> **AI Services is mandatory from v15.2.0.** It is a new chart
> (`charts/ai-services`) with no v15.1.0 counterpart, so an upgrade has to
> **install** it, after Keycloak Realms and before Home. Home 15.2 sends the
> homepage agent's model calls through its AI gateway, converts chat
> attachments with its Docling and seeds its service accounts. Catalog 15.2
> uses the same AI gateway and Docling, and AI Foundry 15.2 also runs its
> workflows on its Temporal. Provision the
> [new prerequisites](#new-prerequisites) before you start. See
> [AI Services](#ai-services-new).

### Scope of the migration

v15.2.0 updates these charts:

- Keycloak (`charts/keycloak`)
- Keycloak Realms (`charts/keycloak-realms`)
- **AI Services (`charts/ai-services`), new and mandatory**
- Home (`charts/services`)
- Catalog (`charts/catalog`)
- AI Foundry (`charts/ai-foundry`)
- Console (`charts/console`)

### New prerequisites

v15.2.0 needs infrastructure that v15.1.0 didn't. Have it ready before
upgrading anything; details are in [Prerequisites](docs/20-prerequisites.md).

| Prerequisite | Needed by | Details |
|---|---|---|
| Hostname `ai-services.<your-domain>` | AI Services | DNS record and TLS certificate on your ingress, like the other products. Also `langfuse.<your-domain>` if you expose the Langfuse UI. |
| PostgreSQL databases `litellm`, `temporal`, `temporal_visibility`, `memory` | AI Services | One owner user each (`litellm_user`, `temporal_user` for both Temporal databases, `memory_user`). `memory` needs the `vector` extension ([pgvector](https://github.com/pgvector/pgvector)), created once by a superuser: `memory-service` does not create it. See [Prerequisites: PostgreSQL](docs/20-prerequisites.md#postgresql) and `hacks/postgres/*.sql`. |
| PostgreSQL database `workspace` | AI Foundry (`workspace-service`) | Owner user `workspace_user`, plain `postgresql://` URL. |
| OpenBao or HashiCorp Vault, with a KV v2 mount | AI Foundry (**required**), Catalog (optional) | Not bundled by any chart. AI Foundry's `secret-store-service` keeps API credentials and the tenants' AI gateway keys there; Catalog's keeps webhook signing keys. Each signs in with an AppRole or with its pod's ServiceAccount through a JWT auth mount. See [Prerequisites: OpenBao or Vault](docs/20-prerequisites.md#openbao-or-vault). |
| Langfuse `>= 4.24.0`, with a project and its API key pair | AI Services, AI Foundry (optional: observability) | Installed with its official Helm chart, which with its bundled ClickHouse needs **cert-manager** and the **ClickHouse operator** in the cluster. Without it, turn observability off as described in [Prerequisites: Langfuse](docs/20-prerequisites.md#langfuse-observability). |
| New Keycloak vault keys `mia-realm_scim-client-secret`, `mia-realm_ai-services-temporal-ui-client-secret` | Keycloak Realms | Added to `keycloak-vault-secrets` before the realms are re-imported. See [Keycloak](#keycloak). |
| IdP access token as a JWT with a groups claim | Keycloak (optional) | Only to federate your IdP with the new `mia-platform-oidc` provider, so its groups drive authorization in Home. See [Identity provider with group provisioning](docs/40-keycloak-realms.md#identity-provider-with-group-provisioning-mia-platform-oidc). |

### Order of operations

Upgrade in the same order as a fresh install: Keycloak, then Keycloak
Realms, then **install** AI Services, then Home, then Catalog, then AI
Foundry. Console
depends only on Keycloak and its realms, so it can be upgraded at any point
after them. For each Helm chart, run `helm dependency build charts/<chart>`
before `helm upgrade` so the new dependency version is pulled.

### Keycloak

| Change | Details |
|---|---|
| `keycloak-operator` dependency | `0.6.1` → `0.7.2` |
| Keycloak `26.6.4` → **`26.8.0`** | Image `0.3.9-26.8.0-postgres`, which includes upstream security fixes. Upgrading is recommended. |
| New `mia-platform-oidc` identity provider | Built into the image. An OIDC broker that provisions users and their IdP groups into Home's authorization service via SCIM. See [Identity provider with group provisioning](docs/40-keycloak-realms.md#identity-provider-with-group-provisioning-mia-platform-oidc). |
| New vault key `mia-realm_scim-client-secret` | Secret of the realm's `scim-client`, referenced as `${vault.scim-client-secret}`. Add it to `keycloak-vault-secrets` before re-importing the realms (see [Keycloak: Secrets](docs/30-keycloak.md#secrets)). |
| New vault key `mia-realm_ai-services-temporal-ui-client-secret` | Secret of the realm's `ai-services-temporal-ui` client, referenced as `${vault.ai-services-temporal-ui-client-secret}`. Add it before re-importing the realms. AI Services must get the same value as `secrets.temporalUiKeys.authClientSecret`. |
| Removed `keycloak-operator.…image.tag` override | The pinned `image.tag: "0.3.2-26.6.4-postgres"` is no longer set in `values.yaml`, so the image version shipped with the operator chart is used. If you copied this override into your own values, remove it. |

```sh
helm dependency build charts/keycloak
helm upgrade --install keycloak charts/keycloak \
  --namespace <keycloak-namespace> \
  -f charts/keycloak/values.yaml \
  --rollback-on-failure --timeout 5m
```

### Keycloak Realms

| Change | Details |
|---|---|
| `keycloak-realm-management` dependency | `0.1.35` → `0.1.54` |
| `scim-client` service account | Declared in the `products` realm when `products.authz: true`, with the `authz-api` provisioning roles for users and groups. Its secret comes from the vault key above. |
| New `aiServices` product (**required**) | `production/products.yaml` adds `products.aiServices: true` and `urls.aiServices: https://ai-services.<your-domain>`. The realm then creates the AI Services clients: `ai-services-api` (token-exchange audience), `ai-services-access-control`, `ai-services-temporal-ui` and `ai-services-mcp-gateway`. With `aiFoundry` enabled it also creates the `ai-foundry-provisioner` client. See [Keycloak Realms](docs/40-keycloak-realms.md). |

Add the `aiServices` entries to your `products.yaml`:

```yaml
keycloak-realm-management:
  urls:
    aiServices: https://ai-services.<your-domain>
  products:
    aiServices: true
```

No other realm value needs to change. To have your existing IdP push users
and groups into Home, switch it from `providerId: oidc` to
`providerId: mia-platform-oidc` and add the `miaScimClient*` keys. This is
optional; see
[Identity provider with group provisioning](docs/40-keycloak-realms.md#identity-provider-with-group-provisioning-mia-platform-oidc).
Render the realms again and re-apply
them with `keycloak-config-cli`, as described in
[Keycloak Realms](docs/40-keycloak-realms.md#install). In the local setup:

```sh
make keycloak_realms_master_as_admin_install
make keycloak_realms_production_install
```

### AI Services (new)

AI Services is a new, **mandatory** product: the shared AI infrastructure
(AI gateway on LiteLLM, Temporal, Docling, agent memory, OpenTelemetry
Collector and Prometheus) that Home and AI Foundry 15.2 run on. Nothing to
upgrade here: install it fresh, after Keycloak Realms and before Home.

Before installing it:

- Create its PostgreSQL databases: `litellm`, `temporal`,
  `temporal_visibility` and `memory` (`memory` needs the `vector`
  extension). See [New prerequisites](#new-prerequisites).
- Make sure the realms were re-imported with the `aiServices` product and
  the `ai-services-temporal-ui` vault key (see the two sections above).
- Choose the LiteLLM master key (`litellmProxyKeys.masterKey`). AI Foundry
  15.2 must get the same value as `aiFoundryBeKeys.litellmAdminKey`.
  Choose the `saltKey` once: it can't be rotated after models are
  registered.
- To keep observability on, prepare a Langfuse project and give its key
  pair to the collector (`otelCollectorKeys`); otherwise turn
  `otelCollector`, `prometheus` and `telemetry` off. See
  [Prerequisites: Langfuse](docs/20-prerequisites.md#langfuse-observability).

```sh
helm dependency build charts/ai-services
helm upgrade --install ai-services charts/ai-services \
  --namespace ai-services --create-namespace \
  -f charts/ai-services/values.yaml \
  -f <your-secrets-values-file> \
  --rollback-on-failure --timeout 10m
```

Its values and secrets are described in
[AI Services](docs/45-ai-services.md). Its token-gated routes (Docling,
memory) call Home's authorization service, so they answer only after Home is
upgraded too.

### Home (Services)

| Change | Details |
|---|---|
| `services` dependency | `0.3.16` → `0.5.1` (the `values.schema.json` `$ref` is updated to match) |
| Added `services.aiServicesClientId` | `ai-services-api`: audience of the token exchange towards AI Services. |
| Added `services.adkBeApp.config.catalogApiUrl` | Public URL of your Catalog instance (e.g. `https://catalog.<your-domain>`). |
| Added `services.adkBeApp.config.aiGatewayEnabled` | `true`: the homepage agent's model calls go through AI Services' AI gateway. |
| Added `services.adkBeApp.config.litellmProxyApiBase` | `https://ai-services.<your-domain>/ai-gateway/`. Required with the gateway on. |
| Added `services.adkBeApp.config.secretStoreBaseUrl` | `https://ai-services.<your-domain>`. The agent reads the tenant's AI gateway key there. Required with the gateway on. |
| Changed `services.telemetry` | `enabled: false` → `true`, exporting to AI Services' collector (`http://otel-collector.<ai-services-namespace>.svc.cluster.local:4317`, `otelExporterOtlpProtocol: grpc`), for every component of the chart. Keep `false` if you run AI Services without observability. |
| Added `services.adkBeApp.config.otelExporterOtlpEndpoint` / `otelExporterOtlpProtocol` | The agent runtime exports over OTLP/HTTP to the same collector (`:4318`, `http/protobuf`). |
| Added `services.apiGateway.docling.url` | `https://ai-services.<your-domain>/api/docling/`: chat attachments are converted by AI Services. Empty disables the route. |
| Added `services.hooks.seedAuthzResources` / `seedSystemRoles` / `seedBuiltinGroups` | New seed hooks for the authorization resources, system roles and built-in groups. Off in the chart, **enabled** in this repository's values. |
| Added `services.hooks.seedServiceAccounts` (`enabled`, `products.<product>.url`) | Registers the system service accounts in Keycloak and in the `authz` database, as the `authz-registrar` client. Set the public URL of each product you run (`ai-foundry`, `ai-services`, `authz`, `catalog`, `console`, `flow`). Existing clients are left untouched. Enabled in this repository's values. |
| Added `mcpServers` under `services.hooks.seedData.configurations.default.products.<product>` | MCP servers listed for each product: AI Foundry, memory and MCP gateway (AI Services), Catalog MCP, Services MCP. Optional. |
| Changed `services.hooks.postgresConnectivityCheck.enabled` / `issuerConnectivityCheck.enabled` | `false` → `true`: pre-flight checks that Postgres and the Keycloak issuer are reachable. |
| Removed `services.rbacManagement.config.frontendInvitationUrl` | No longer part of the chart's values; delete it from your values. |

See [Services](docs/50-services.md#valuesyaml-reference) for every field.

```yaml
services:
  aiServicesClientId: "ai-services-api"

  telemetry:
    enabled: true
    otelExporterOtlpEndpoint: "http://otel-collector.<ai-services-namespace>.svc.cluster.local:4317"
    otelExporterOtlpProtocol: "grpc"

  hooks:
    postgresConnectivityCheck:
      enabled: true
    issuerConnectivityCheck:
      enabled: true
    seedAuthzResources:
      enabled: true
    seedBuiltinGroups:
      enabled: true
    seedSystemRoles:
      enabled: true
    seedServiceAccounts:
      enabled: true
      products:
        ai-foundry:
          url: "https://ai-foundry.<your-domain>"
        ai-services:
          url: "https://ai-services.<your-domain>"
        authz:
          url: "https://home.<your-domain>"
        catalog:
          url: "https://catalog.<your-domain>"
        console:
          url: "https://console.<your-domain>"
        flow:
          url: "https://flow.<your-domain>"

  adkBeApp:
    config:
      aiGatewayEnabled: true
      catalogApiUrl: "https://catalog.<your-domain>"
      litellmProxyApiBase: "https://ai-services.<your-domain>/ai-gateway/"
      secretStoreBaseUrl: "https://ai-services.<your-domain>"
      otelExporterOtlpEndpoint: "http://otel-collector.<ai-services-namespace>.svc.cluster.local:4318"
      otelExporterOtlpProtocol: "http/protobuf"

  apiGateway:
    docling:
      url: "https://ai-services.<your-domain>/api/docling/"

  # remove:
  # rbacManagement:
  #   config:
  #     frontendInvitationUrl: "..."
```

```sh
helm dependency build charts/services
helm upgrade --install services charts/services \
  --namespace <services-namespace> \
  -f charts/services/values.yaml \
  -f <your-secrets-values-file> \
  --rollback-on-failure --timeout 5m
```

The homepage agent reads the tenant's AI gateway key minted by AI Foundry,
so it can call a model only after AI Foundry 15.2 is upgraded and a model is
registered.

### Catalog

| Change | Details |
|---|---|
| `catalog` dependency | `0.3.42-0` → `0.5.3-2` (the `values.schema.json` `$ref` is updated to match) |
| Added `catalog.aiServicesClientId` | `ai-services-api`: audience of the token exchange towards AI Services. |
| Added `catalog.adkBeApp.config.litellmProxyApiBase` | `https://ai-services.<your-domain>/ai-gateway/`: the Catalog agent's model calls go through AI Services' AI gateway. |
| Added `catalog.adkBeApp.config.secretStoreBaseUrl` | `https://ai-services.<your-domain>`. The agent reads the tenant's AI gateway key there. |
| Added `catalog.apiGateway.docling.url` | `https://ai-services.<your-domain>/api/docling/`: chat attachments are converted by AI Services. |
| Removed `catalog.doclingService` | Catalog no longer deploys its own Docling; delete it from your values. |
| Removed `catalog.adkBeApp.config.googleCloudProject` / `googleCloudLocation` / `googleGenaiUseVertexai` | Models and provider credentials are registered on the AI gateway from the AI Foundry UI. Leave `secrets.adkBeAppKeys.googleApplicationCredentials` empty. |
| Added `catalog.secretStoreService` | Optional, off in the chart. Keeps the signing keys of webhooks in an OpenBao/Vault KV v2 mount, signing in with the pod's ServiceAccount (`auth.method: jwt`, needs `auth.jwt.mount`/`role`) or an AppRole (`approle`, with `secrets.secretStoreServiceKeys`). Off, webhooks with a signing secret can't be created or rotated (`502`). Enabled in this repository's values. |

See [Catalog](docs/60-catalog.md#valuesyaml-reference) for every field.

```yaml
catalog:
  aiServicesClientId: "ai-services-api"

  apiGateway:
    docling:
      url: "https://ai-services.<your-domain>/api/docling/"

  adkBeApp:
    config:
      litellmProxyApiBase: "https://ai-services.<your-domain>/ai-gateway/"
      secretStoreBaseUrl: "https://ai-services.<your-domain>"
      # remove:
      # googleCloudProject: "..."
      # googleCloudLocation: "..."
      # googleGenaiUseVertexai: true

  # optional, for webhooks with a signing secret:
  secretStoreService:
    enabled: true
    config:
      storeAddr: "<your-openbao-or-vault-url>"
      storeKvMount: "<kv-v2-mount>"
      storeNamespace: ""            # X-Vault-Namespace, empty if unused
      auth:
        method: "jwt"
        jwt:
          mount: "<jwt-auth-mount>"
          role: "<role-bound-to-catalog-secret-store-service>"

  # remove:
  # doclingService:
  #   enabled: true
```

```sh
helm dependency build charts/catalog
helm upgrade --install catalog charts/catalog \
  --namespace <catalog-namespace> \
  -f charts/catalog/values.yaml \
  -f <your-secrets-values-file> \
  --rollback-on-failure --timeout 10m
```

Upgrade Catalog before AI Foundry: AI Foundry 15.2's provisioner writes into
Catalog as the `ai-foundry-provisioner` service account, which only Catalog
15.2's policies recognise. Like the homepage agent, the Catalog agent can
call a model only after AI Foundry has minted the tenant's AI gateway key.

### AI Foundry

| Change | Details |
|---|---|
| `ai-foundry` dependency | `0.4.83-0` → `0.5.0` |
| New components | `ai-foundry-be`, `ai-foundry-provisioner`, `ai-foundry-workflows`, `workspace-service`, `secret-store-service`, each with its own Secret. Docling moved to AI Services. |
| New prerequisites | AI Services, Catalog 15.2, an OpenBao/Vault KV v2 store, the `workspace` database. |

The full list of values to add, change and remove (AI gateway, Temporal,
OpenBao, telemetry, the removed Vertex AI settings) is in
[AI Foundry: Upgrading from 15.1](docs/70-ai-foundry.md#upgrading-from-151).

```sh
helm dependency build charts/ai-foundry
helm upgrade --install ai-foundry charts/ai-foundry \
  --namespace <ai-foundry-namespace> \
  -f charts/ai-foundry/values.yaml \
  -f <your-secrets-values-file> \
  --rollback-on-failure --timeout 10m
```

### Console

| Change | Details |
|---|---|
| `mia-console` dependency | `15.1.0` → `15.2.0-0` |
| Added `bootstrapSuperadmin.enabled` / `bootstrapSuperadmin.firstLoginEmail` (root level, not under `mia-console`) | Optional. When enabled, Helm hooks grant Console super-user and CMS permissions to the given user. Defaults to `false`. |

Existing installations already have administrators, so you can leave
`bootstrapSuperadmin.enabled: false`. To use the bootstrap anyway (for
example, to grant rights to a new admin), first make sure that user is in
the Keycloak group `products/console/guest` and has logged in to Console
at least once. Otherwise the hook fails and so does the upgrade. See
[Console: Bootstrap](docs/80-console.md#bootstrap).

```sh
helm dependency build charts/console
helm upgrade --install console charts/console \
  --namespace <existing-console-namespace> \
  -f charts/console/values.yaml \
  -f <your-secrets-values-file> \
  --rollback-on-failure --timeout 5m
```

On Helm v3, use `--atomic` instead of `--rollback-on-failure` in the
commands above.

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

Install Keycloak first (see [Keycloak](docs/30-keycloak.md)). Before
installing Keycloak Realms, configure identity provider federation in the
realm values as described below; this replaces the `authProviders`
configuration previously defined natively in Console. Install Keycloak
Realms only after this step (see
[Keycloak Realms](docs/40-keycloak-realms.md)). Before upgrading Console,
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

On customer IdP Application/Client you must exchange either:

- a client secret
- a set of public keys (jwks)

Then the custom IdP Application must register the following login `redirect_uri` parameter:

```url
https://<dns>/realms/<realm_name>/broker/<alias_idp>/endpoint
```

and logout `redirect_uri` parameter:

```url
https://<dns>/realms/<realm_name>/broker/<alias_idp>/endpoint/logout_response
```

Example identity provider configuration:

```yaml
keycloak-realm-management:
    identityProviders:
        - alias: customer-idp # <=== <alias_idp>
          config:
              # --- client authentication: shared secret (NOT asymmetric keys) ---
              clientAuthMethod: client_secret_post # or client_secret_basic
              clientId: my-registered-client-id
              clientSecret: "${vault.my-idp-client-secret}"

              # --- endpoints (from the IdP's .well-known/openid-configuration) ---
              authorizationUrl: https://idp.example.com/oauth2/authorize
              tokenUrl: https://idp.example.com/oauth2/token
              userInfoUrl: https://idp.example.com/oauth2/userinfo
              logoutUrl: https://idp.example.com/oauth2/logout
              issuer: https://idp.example.com

              # --- scopes / behavior ---
              defaultScope: "openid email profile"
              syncMode: FORCE
              pkceEnabled: "true"
              pkceMethod: S256

              # signature verification of the IdP's tokens (independent of client auth)
              validateSignature: "true"
              useJwksUrl: "true"
              jwksUrl: https://idp.example.com/oauth2/certs
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

`customer-idp-uid-mapper` should match the claim that is currently used by Authentication
Service on the customer provider:
Keycloak logic states that `oidc-user-attribute-idp-mapper` it reads from user profile from the following sources:

1. UserInfo endpoint (default). If the IdP's Disable User Info switch is off (the default)
   and a UserInfo URL + access token are available, Keycloak calls UserInfo (using the access token as a bearer)
   and stores the UserInfo response as the profile node. Your claims are mapped from there.
2. ID token (fallback). If User Info is disabled,
   or there's no UserInfo endpoint / no access token, Keycloak falls back to the ID token
   claims as the profile node.

- Okta -> `uid`
- Entra ID -> `oid`
- Auth0 -> either `sub` or `user_id`

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
db.userinfo.aggregate([
    { $match: { __STATE__: "PUBLIC" } },
    {
        $group: {
            _id: "$providerUserId",
            count: { $sum: 1 },
            ids: { $push: "$_id" },
        },
    },
    { $match: { count: { $gt: 1 } } },
    { $sort: { count: -1 } },
]);
```

If this query returns results, they must be resolved before proceeding
with the upgrade. Because `providerUserId` values originate from the
customer's own Identity Provider, resolving duplicates — including which
record to retain — is the customer's responsibility.

### Console `values.yaml` changes

The following compares a representative v14 `values.yaml` with the
current v15 `charts/console/values.yaml`.

#### Removed in v15

| v14 field                                                                                      | Reason                                                                                                                                                                   |
| ---------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `miaconsole.configurations.authProviders`                                                      | Replaced by Keycloak `identityProviders`/`identityProviderMappers` (see above).                                                                                          |
| `miaconsole.configurations.userAccountAuthProvider` (`tokenPassphrase`, `jwtTokenPrivateKey*`) | Replaced by Keycloak and `authtoolBff.keys`.                                                                                                                             |
| `miaconsole.authenticationService` (the whole component)                                       | Removed — Keycloak replaces Console's native auth service entirely.                                                                                                      |
| `miaconsole.configurations.enableUserSynchronizationWebhooks`                                  | Specific to syncing users from the native auth service; no longer applicable.                                                                                            |
| `miaconsole.configurations.additionalAuthenticationClients`                                    | No v15 equivalent in this repository's reference values. If in use (e.g. for a local MCP-server login flow), this requires manual review rather than a direct migration. |
| `miaconsole.configurations.serviceAccountAuthProvider.rsaPrivateKeyPass`                       | No longer part of the schema; the service-account private key is no longer passphrase-protected.                                                                         |

#### Added in v15

| v15 field                                                                                   | Purpose                                                                                                    |
| ------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| `miaconsole.configurations.keycloak.protocol` / `host` / `realm` / `extensibilityRealmName` | Points Console at the new Keycloak instance and realms. Required.                                          |
| `miaconsole.authtoolBff.keys` (`privateKey`, `cookieSecret`, `redisTokenEncKey`)            | New BFF component that bridges Keycloak-issued tokens — see [Console secrets](docs/80-console.md#secrets). |
| `miaconsole.extensibilityManagerService.keys.registrarPrivateKey`                           | New — used to register extensibility clients.                                                              |

#### Changed structure

| Field                                   | v14 shape                                       | v15 shape                                                                     |
| --------------------------------------- | ----------------------------------------------- | ----------------------------------------------------------------------------- |
| `miaconsole.configurations.redis.hosts` | List of plain host strings                      | List of `{ip, port}` objects                                                  |
| `miaconsole.configurations.audit`       | `configurations.audit.mongodbUrl` (plain value) | `configurations.audit.envs.mongodbUrl` (nested under `envs`, secret-injected) |

### Suggested upgrade command

Once the realm and `values.yaml` changes described above are in place,
the following command can be used as a starting point; adjust it to match
existing deployment conventions:

```sh
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

See [`docs/90-troubleshooting.md`](docs/90-troubleshooting.md), which
includes a section dedicated to issues that may arise during this
migration.
