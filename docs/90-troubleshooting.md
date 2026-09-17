# Troubleshooting

General checks that apply across products, plus a few issues specific to
this suite's shared components.

## General checks

- `kubectl get pods -n <namespace>` — anything not `Running`/`Ready`?
  `kubectl describe pod <pod>` for events, `kubectl logs <pod>` for
  application errors.
- `kubectl get ingressroute -n <namespace>` (or your ingress controller's
  equivalent) — does the route exist and match the hostname you're testing?
- TLS: confirm the certificate presented for each hostname is trusted by
  your client (browser, `curl --cacert`, etc.) — don't reuse this
  repository's locally-trusted `mkcert` CA outside local dev.

## `make` target fails or targets the wrong namespace

The per-chart `make` targets (`catalog_install`, `catalog_uninstall`,
`console_uninstall`, `services_render_secrets`, …) have no default
namespace — `NAMESPACE` must be passed on the command line:

```
make catalog_uninstall NAMESPACE=catalog        # namespace-per-product
make catalog_uninstall NAMESPACE=default        # all-in-one
```

Omit it and `helm` receives an empty `--namespace`, which falls back to
whatever your current kubeconfig context points at rather than failing —
so an `*_uninstall` can hit a namespace you didn't mean, which on an
all-in-one cluster is `default`, where the live releases actually are. If a
release "disappeared" or a command reported success against the wrong
place, check the `NAMESPACE` you passed.

The numbered targets (`010_keycloak` … `060_console` and their
`*_all_in_one` counterparts) set it for you — prefer those for normal
installs.

## All-in-one layout

These only apply if you installed the suite into a single namespace — see
[Installation layouts](10-overview.md#installation-layouts).

- **`helm upgrade` fails with "existing resource conflict" / another
  release owns a resource.** You installed Services, Catalog, or AI Foundry
  into the shared namespace *without* its `values.all-in-one.yaml` overlay.
  All three produce identically named `api-gateway`, `authtool-bff`,
  `adk-be-app`, `access-control`, `cache`, `swagger-aggregator`, and
  `docling-service` resources, and the overlay is what renames them to
  `svc-*`/`cat-*`/`aif-*`. Re-run the install with both values files, in
  order: `-f values.yaml -f values.all-in-one.yaml`.
- **Mixed layouts.** Installing some products namespace-per-product and
  others all-in-one isn't supported. Pick one and reinstall the odd ones out.
- **A product's request lands in the wrong product's component.** In a
  shared namespace, a bare Service name like `authtool-bff` resolves to
  whichever release owns that unprefixed name (Console). If a product is
  configured with an in-cluster URL of its own, it must carry that product's
  prefix — AI Foundry's `authtoolBffUrl` is the one such value in this
  repository, and the overlay sets it to `http://aif-authtool-bff`. Symptoms
  look like token-exchange or authorization failures rather than connection
  errors, since the wrong service does answer.
- **Telling pods apart.** `kubectl get pods -n default` mixes every product.
  Filter by release: `kubectl get pods -n default -l app.kubernetes.io/instance=catalog`
  (or `services`, `ai-foundry`, `console`), or by the `svc-`/`cat-`/`aif-`
  name prefix.
- **Datastores did not move.** PostgreSQL, MongoDB, Redis, and Kafka stay in
  their own namespaces in both layouts, and every connection string is
  fully-qualified — so a datastore connection failure in the all-in-one
  layout is a real connectivity/credentials problem, not a namespace
  mismatch. Note that `hacks/kafka.sh` creates Catalog's topics in the
  `catalog` namespace even when Catalog runs in `default`.

## Shared secrets must match across products

Several products share the *same* key material and must be configured
identically or they will fail to interoperate:

- `authtoolBffKeys` (`tokenEncKey`, `cookieSecret`, `privateKey`) — shared
  by [Services](50-services.md), [Catalog](60-catalog.md), and
  [AI Foundry](70-ai-foundry.md).
- The `adk` Postgres connection string — shared by the same three products.
- The Keycloak realm issuer URL (`authorizationServer.issuer`) — must be
  identical across every product's configuration.

If sign-in works on one product but a downstream call fails with an
authorization/token error, check whether the `authtoolBffKeys` material
actually matches between the two products involved.

## Keycloak native mode (no operator)

These apply if you installed Keycloak with
`charts/keycloak/values.native.yaml` (`mode: manual`) — see
[Run modes](30-keycloak.md#run-modes-operator-or-native).

- **No operator pod in the namespace.** Expected. Native mode deploys a
  Keycloak StatefulSet and Service only — no operator `Deployment`, no
  `Keycloak` custom resource, no cluster-scoped RBAC. `kubectl get
  statefulset` is the thing to check, not `kubectl get keycloak`.
- **Template fails mentioning cluster discovery / `instances`.** Native mode
  supports a single instance; the chart refuses to render with
  `keycloak.instances` greater than `1`. Either set it back to `1` or switch
  to operator mode, which handles clustering.
- **`no matches for kind "ServiceMonitor"`.** The `ServiceMonitor` template
  renders only in native mode and the subchart defaults it to `true`, so a
  cluster without the Prometheus Operator CRDs fails on it. Set
  `keycloak.serviceMonitor.enabled: false` — this repository's
  `values.native.yaml` already does.
- **Switching modes on an existing release.** The two modes own different
  resources (a `Keycloak` CR versus a chart-managed StatefulSet), so
  `helm upgrade` between them is not a clean in-place swap. Uninstall the
  release first (`make keycloak_uninstall NAMESPACE=...`) and reinstall in
  the other mode. Keycloak's state lives in PostgreSQL, so the realms and
  users survive as long as the database does.

## Keycloak realm import

- If realm import "succeeds" but sign-in fails with an invalid client
  secret, check whether the realm's client secret is a literal
  `${vault....}` string instead of a real value — see the known issue in
  [Keycloak Realms](40-keycloak-realms.md).
- If the `products`/`extensibility` realm import step itself fails to
  authenticate, confirm the `keycloak-config-cli` client's secret in the
  `master` realm matches the secret you're using for the
  `client_credentials` grant.

## Kafka

- If Catalog can't connect, confirm `catalogKafkaContext.connectionConfig`
  (bootstrap servers, security protocol, SASL settings) matches your Kafka
  cluster's actual configuration — a common mismatch is leaving
  `securityProtocol: PLAINTEXT` when your cluster requires TLS/SASL.

## MongoDB / Redis

- Console's `configurations.mongodbUrl` must include `replicaSet=rs0` (or
  your replica set's name) if MongoDB is running as a replica set —
  otherwise the driver will fail to find a primary.
- Console's `configurations.redis.tlsCACert` must be the CA that actually
  signed your Redis instance's certificate — a mismatch here causes TLS
  handshake failures that can look like a generic connection timeout.

## `helm upgrade` fails on an existing Console install because of leftover Jobs

If you're running `helm upgrade` against a namespace that already has a
previous installation of Console, the upgrade can fail because Kubernetes
`Job` resources from that previous install are still present — `Job`
specs are immutable, so Helm can't update them in place, and the upgrade
errors out instead of replacing them.

This is safe to resolve manually: the leftover `Job`s from the previous
install can simply be deleted from the namespace, after which `helm
upgrade` can be run again and will succeed.

```
kubectl get jobs -n <console-namespace>
kubectl delete job <job-name> -n <console-namespace>
```

Deleting these completed Jobs does not affect your data — it only clears
the old, immutable Job records so Helm can recreate them as part of the
upgrade.

## Migrating Console from v14.x

These only come up if you're following the
[Migration Guide](../MIGRATION_GUIDE.md) to upgrade an existing v14.x
Console install to v15.0.0 — they don't apply to a fresh install.

- **A migrated user loses access/history on first login** — check the
  `provider_sub` mapper configuration in your realm's
  `identityProviderMappers`; the claim it copies must match the identifier
  your IdP has always used for that user. See the Migration Guide's
  identity-provider section for the mapper example.
- **Upgrade fails on a unique index error for `userInfo`** — you have
  duplicate `providerUserId` values among active (`__STATE__: "PUBLIC"`)
  users. Re-run the duplicate-check aggregation from the Migration Guide
  and resolve them before retrying.
