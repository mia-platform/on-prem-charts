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

## Shared secrets must match across products

Several products share the *same* key material and must be configured
identically or they will fail to interoperate:

- `authtoolBffKeys` (`tokenEncKey`, `cookieSecret`, `privateKey`) — shared
  by [Services](05-services.md), [Catalog](06-catalog.md), and
  [AI Foundry](07-ai-foundry.md).
- The `adk` Postgres connection string — shared by the same three products.
- The Keycloak realm issuer URL (`authorizationServer.issuer`) — must be
  identical across every product's configuration.

If sign-in works on one product but a downstream call fails with an
authorization/token error, check whether the `authtoolBffKeys` material
actually matches between the two products involved.

## Keycloak realm import

- If realm import "succeeds" but sign-in fails with an invalid client
  secret, check whether the realm's client secret is a literal
  `${vault....}` string instead of a real value — see the known issue in
  [Keycloak Realms](04-keycloak-realms.md).
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
