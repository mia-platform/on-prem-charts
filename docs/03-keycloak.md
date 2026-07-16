# Keycloak

Chart: `charts/keycloak` · Depends on: PostgreSQL, TLS certificate

Keycloak is the identity provider for the whole suite. This chart installs
the Keycloak instance itself (via the `keycloak-operator` dependency) and
includes the `master` realm. Product realms (`products`, `extensibility`)
are configured separately — see [Keycloak Realms](04-keycloak-realms.md).

## Install

```
helm dependency build charts/keycloak
helm upgrade --install keycloak charts/keycloak \
  --namespace keycloak --create-namespace \
  -f charts/keycloak/values.yaml \
  charts/keycloak
```

## `values.yaml` reference

All configuration lives under the `keycloak-operator` key.

| Field | Required | Description |
|---|---|---|
| `adminBootstrap.enabled` | Yes | Must be `true` so an initial admin user is created. |
| `adminBootstrap.password` | Yes | Initial admin password. Change this from the `change_me` default before going to production. |
| `keycloak.instances` | Yes | Number of Keycloak replicas. |
| `keycloak.hostname.hostname` | Yes | The public URL Keycloak will advertise and validate tokens against — must match your ingress hostname. |
| `keycloak.ingressRoute.enabled` | Yes (if using Traefik) | Set `false` and configure your own ingress resource if not using Traefik. |
| `keycloak.db.vendor` | Yes | Database vendor, `postgres` in this repo. |
| `keycloak.db.url` | Yes | JDBC connection URL to your PostgreSQL instance/database. |
| `keycloak.db.usernameSecret` / `passwordSecret` | Yes | Name/key of a Kubernetes Secret holding the DB credentials (see below). |
| `keycloak.image.tag` | Yes | Keycloak image tag to deploy. |
| `keycloak.truststores` | No | Only needed if Keycloak must trust a custom CA (e.g. to validate other products' client JWKS over TLS with an internal/self-signed certificate). ⚠️ In this repository's default `values.yaml`, this points at a CA bundle built around the local dev `mkcert` CA (see [Overview](01-overview.md#settings-not-suitable-for-production)) — replace it with your organization's real CA before production. |
| `keycloak.tracing` / `keycloak.telemetry` | No | OpenTelemetry endpoints, disable if you don't run a collector. |
| `vault.enabled` | Yes | Enables the templated `keycloak-vault-secrets` Secret (see below). |
| `grafana.enabled` | No | Enables a bundled Grafana dashboard for the operator, optional. |

## Secrets

This chart expects two Kubernetes Secrets to exist (or be created by a
values-driven render step) before install:

- **`keycloak-postgres-credentials`** — referenced by `keycloak.db.usernameSecret`/`passwordSecret`. In this repository's template
  (`templates/postgres-credentials.secret.yaml`) the username/password are
  fixed to the values used in the local dev database
  (`hacks/postgres/keycloak.sql`); for your own PostgreSQL instance, update
  this template (or replace it with your own Secret) to match your actual
  DB credentials.
- **`keycloak-vault-secrets`** — client secrets consumed by realm imports
  (see [Keycloak Realms](04-keycloak-realms.md)). This repository generates
  it from `charts/keycloak/render_values.sh`, which reads a `clientSecret`
  value into `charts/keycloak/.local/secrets.yaml` and feeds it to
  `templates/vault.secret.yaml`. In your environment, this should be the
  client secret you intend to use for the `mia-platform`/
  `mia-platform-extensibility` identity-provider clients configured during
  realm import — generate it yourself and adapt the render step (or the
  Secret) to your own secret-management approach rather than reusing the
  `.local/` dev key material.

## Verify

- `kubectl get pods -n keycloak` — the Keycloak instance and operator pods
  should be `Running`.
- Visit `https://<your-keycloak-hostname>` and confirm the login page loads
  and you can sign in with the admin bootstrap credentials.

## Post-install: create an admin user

Log in to the Keycloak admin console at `https://<your-keycloak-hostname>`
using the bootstrap admin account (username `admin`, password from
`adminBootstrap.password` — `change_me` in this repository's default
`values.yaml`, change it before production). In the **`master`** realm,
create a new user and assign it the **`admin`** role. Use this account for
day-to-day Keycloak administration going forward, rather than relying on
the bootstrap admin indefinitely.
