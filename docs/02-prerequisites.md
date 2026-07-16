# Prerequisites

These are the pieces of infrastructure the product suite expects to already
exist. The `hacks/` scripts in this repository provision throwaway versions
of all of them inside a local `kind` cluster for development — use them only
as a reference for *what* is needed, not as your installation method.

## Kubernetes cluster

- A cluster you control, with `kubectl`/`helm` access.
- An ingress controller that terminates TLS and can route by `Host` header.
  This repository's local setup uses [Traefik](https://traefik.io/) with
  `IngressRoute` resources (see each chart's `ingressRoute.enabled` value) —
  if you use a different ingress controller, you will need to translate
  those routes to your controller's CRDs/annotations.
- DNS (or `/etc/hosts` entries) resolving each product's hostname to your
  ingress. The default hostnames used throughout the charts are:

  | Product | Default hostname |
  |---|---|
  | Keycloak | `auth.mia-platform.test` |
  | Services (Home) | `home.mia-platform.test` |
  | Catalog | `catalog.mia-platform.test` |
  | AI Foundry | `ai-foundry.mia-platform.test` |
  | Console | `console.mia-platform.test`, `cms-console.mia-platform.test` |

  All of these are overridable via `values.yaml` — see each product's page.

## ⚠️ External Identity Provider

The `extensibility` realm (see [Keycloak Realms](04-keycloak-realms.md)) is
configured to broker authentication through an **external OIDC-compliant
identity provider** — your organization's own IdP, or an existing Keycloak
you already run. This is not optional infrastructure you can skip: without
it, the `extensibility` realm's identity-provider federation will not work.

You will need, from that external IdP:

- An OIDC client registered for this federation (`client_id`, plus either a
  `client_secret` or `private_key_jwt` authentication).
- Its standard OIDC endpoints: `issuer`, `authorization`, `token`,
  `userinfo`, `jwks`, and `logout` — normally discoverable from its
  `/.well-known/openid-configuration`.

This repository's default configuration
(`charts/keycloak-realms/values/prod/production/extensibility.yaml`, alias
`mia-platform`) points these at a realm on the same local Keycloak instance,
purely so the federation flow can be tested end-to-end without a second
IdP. **Before using this as a reference for production, replace every one
of those URLs and the `clientId`/`clientSecret` with your actual external
IdP's details** — see the client-secret note in
[Keycloak Realms](04-keycloak-realms.md) for where that secret is
threaded through.

## PostgreSQL

A PostgreSQL instance reachable from the cluster, with one database and
owner-user per product that needs one:

| Database | Owner user | Used by |
|---|---|---|
| `keycloak` | `keycloak_user` | Keycloak |
| `authz` | `authz_user` (needs the `pg_trgm` extension) | Services (authorization) |
| `catalog` | `catalog_user` | Catalog |
| `adk` | `adk_user` | Services, Catalog, AI Foundry (shared "ADK" component) |

The exact `CREATE USER`/`CREATE DATABASE` statements this repository uses
locally are in `hacks/postgres/*.sql`, if useful as a reference for the
grants/extensions each database needs.

## MongoDB

A MongoDB instance (replica-set mode, since the driver connection string
requires `replicaSet=rs0`) for Console, with a `console` database.

## Redis

A Redis instance is required for Console (session/token cache), reachable
over TLS with a CA certificate Console can validate against
(`configurations.redis.tlsCACert`). Catalog, Services, and AI Foundry also
take token-encryption key material (`authtoolBffKeys.tokenEncKey`) but do
not expose a Redis host field directly in their `values.yaml` — if their
underlying components need their own Redis/cache instance, that is
configured at the subchart level and is not part of this documentation's
scope.

## Kafka

A Kafka cluster for Catalog's event topics. This repository provisions a
[Strimzi](https://strimzi.io/)-managed cluster locally
(`hacks/kafka/cluster.yaml`) with two topics, `catalog-events.input` and
`catalog-events.output` (see `hacks/kafka/topics.yaml` for partition/
retention settings as a reference). `catalog.catalogKafkaContext` in
`charts/catalog/values.yaml` controls how Catalog connects (bootstrap
servers, SASL, security protocol).

## Docker registry access

All product images are pulled from Mia Platform's registry
(`nexus.mia-platform.eu`) or your own mirror of it. You will need pull
credentials configured as a Kubernetes image pull secret in each namespace
(see `imagePullSecrets/imageCredentials` fields in the relevant
`values.yaml` files).

For the local `kind` setup, [`hacks/docker_cred.sh`](../hacks/docker_cred.sh)
loads those credentials into the cluster, but it does not obtain them for
you: it only reads whatever is already stored in your local Docker
credential store (`~/.docker/config.json`, or the `pass`/`secretservice`/
`desktop` credential helper backing it). You must already have a valid
access token for the `nexus.mia-platform.eu` registry — e.g. by running
`docker login nexus.mia-platform.eu` with credentials provided by
Mia Platform — before running this script, otherwise it has nothing to
extract.

## TLS certificates

Each product's ingress route needs a valid TLS certificate for its
hostname. Locally this repository uses [mkcert](https://github.com/FiloSottile/mkcert)
for a locally-trusted CA (`hacks/tls.sh`); in your own infrastructure, use
your organization's CA or a public one (e.g. via cert-manager).
