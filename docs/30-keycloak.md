# Keycloak

Chart: `charts/keycloak` · Depends on: PostgreSQL, TLS certificate

Keycloak is the identity provider for the whole suite. This chart installs
the Keycloak instance itself (via the `keycloak-operator` dependency) and
includes the `master` realm. Product realms (`products`, `extensibility`)
are configured separately — see [Keycloak Realms](40-keycloak-realms.md).

The chart can run Keycloak either through the Keycloak Operator (the
default) or as a plain StatefulSet with no operator at all — see
[Run modes](#run-modes-operator-or-native).

## Install

```
helm dependency build charts/keycloak
helm upgrade --install keycloak charts/keycloak \
  --namespace keycloak --create-namespace \
  -f charts/keycloak/values.yaml \
  charts/keycloak
```

> **All-in-one layout:** install into the shared namespace instead
> (`--namespace default`). Keycloak needs no values overlay — its resource
> names don't collide with the rest of the suite. In the local `kind` setup
> that's `make 010_keycloak_all_in_one`; see
> [Installation layouts](10-overview.md#installation-layouts).

## Run modes: operator or native

Keycloak can be run in two ways, selected by the `keycloak-operator.mode`
value. This is **independent of the namespace layout** — either mode works
with namespace-per-product and with all-in-one, and it applies to Keycloak
only; no other product in the suite has an equivalent choice.

| | `mode: operator` (default) | `mode: manual` ("native") |
|---|---|---|
| How Keycloak runs | The chart creates a `Keycloak` custom resource; the [Keycloak Operator](https://www.keycloak.org/operator/installation) reconciles it into a StatefulSet. | The chart renders the StatefulSet and Service **directly**. No operator involved. |
| Operator workload | Operator `Deployment`, `Service`, `ServiceAccount` | none |
| RBAC | 3 `ClusterRole`s, 1 `Role`, 4 `RoleBinding`s for the operator | none |
| Custom resources | `Keycloak` CR (and `KeycloakRealmImport` support) | none — no Keycloak CRDs are used |
| Replicas | `keycloak.instances` (operator handles clustering) | **single instance only** |
| Rendered resources | 18 | 8 |

Both modes produce the same `IngressRoute`, the same three Secrets, and the
same Grafana dashboard ConfigMaps — so **Keycloak is reachable at the same
public URL either way**, and the rest of the suite is configured identically.
The chart points the ingress at whichever Service the active mode creates
(`keycloak-service` under the operator, `keycloak-keycloak-operator-service`
in native mode), and nothing else in this repository addresses Keycloak by
its in-cluster name.

### When to use native mode

Native mode exists for clusters where running the operator isn't possible or
isn't worth it:

- You can't install the Keycloak CRDs or the cluster-scoped RBAC the
  operator needs (restricted/shared clusters).
- You want fewer moving parts for a local, demo, or evaluation install —
  one StatefulSet instead of an operator reconciling a CR.

Use the default operator mode for anything that needs more than one Keycloak
replica, or where you want the operator's ongoing reconciliation.

### Installing in native mode

Native mode is the `values.native.yaml` overlay, applied on top of the normal
`values.yaml`:

```
helm dependency build charts/keycloak
helm upgrade --install keycloak charts/keycloak \
  --namespace keycloak --create-namespace \
  -f charts/keycloak/values.yaml \
  -f charts/keycloak/values.native.yaml \
  charts/keycloak
```

In the local `kind` setup, the overlay is wrapped by its own targets — one
per namespace layout, since the two choices are orthogonal:

| | Operator mode (default) | Native mode |
|---|---|---|
| Namespace-per-product | `make 010_keycloak` | `make 010_keycloak_native` |
| All-in-one | `make 010_keycloak_all_in_one` | `make 010_keycloak_all_in_one_native` |

Whichever you pick, the remaining steps (`020_keycloak_realms` onward) are
unchanged.

### What the overlay sets

```yaml
keycloak-operator:
  mode: manual
  operator:
    enabled: false
  keycloak:
    serviceMonitor:
      enabled: false
```

- **`mode: manual`** is the switch. Everything else follows from it.
- **`operator.enabled: false`** is belt-and-braces: `mode: manual` already
  forces the operator off, so the operator is not deployed even without this
  line. It's here to make the intent obvious when reading the file.
- **`serviceMonitor.enabled: false`** is *not* optional in a cluster without
  Prometheus. The subchart defaults it to `true`, and the `ServiceMonitor`
  template only renders in manual mode — so leaving it on in a cluster that
  has no Prometheus Operator (the local `kind` setup included) means
  rendering a `ServiceMonitor` whose CRD doesn't exist. Turn it back on only
  if you actually run the Prometheus Operator.

### Constraints

- **Single instance only.** `keycloak.instances` must stay `1`; the chart
  fails the template outright with a message about cluster discovery if you
  set more. If you need HA, use operator mode.
- **The operator's `realms[]` import is unavailable.** This does not affect
  this suite: realms here are imported with `keycloak-config-cli` over the
  Admin REST API, not through the operator's `KeycloakRealmImport` CR — see
  [Keycloak Realms](40-keycloak-realms.md). Step `020` behaves identically in
  both modes.

## `values.yaml` reference

All configuration lives under the `keycloak-operator` key.

| Field | Required | Description |
|---|---|---|
| `mode` | No | `operator` (default) or `manual` — see [Run modes](#run-modes-operator-or-native). `manual` renders the StatefulSet/Service directly instead of a `Keycloak` CR. |
| `operator.enabled` | No | Whether to deploy the Keycloak Operator. Forced off when `mode: manual`. |
| `adminBootstrap.enabled` | Yes | Must be `true` so an initial admin user is created. |
| `adminBootstrap.password` | Yes | Initial admin password. Change this from the `change_me` default before going to production. |
| `keycloak.instances` | Yes | Number of Keycloak replicas. ⚠️ Must be `1` when `mode: manual` — the template fails otherwise. |
| `keycloak.serviceMonitor.enabled` | No | Only rendered when `mode: manual`, and defaults to `true` — set `false` unless you run the Prometheus Operator. |
| `keycloak.hostname.hostname` | Yes | The public URL Keycloak will advertise and validate tokens against — must match your ingress hostname. |
| `keycloak.ingressRoute.enabled` | Yes (if using Traefik) | Set `false` and configure your own ingress resource if not using Traefik. |
| `keycloak.db.vendor` | Yes | Database vendor, `postgres` in this repo. |
| `keycloak.db.url` | Yes | JDBC connection URL to your PostgreSQL instance/database. |
| `keycloak.db.usernameSecret` / `passwordSecret` | Yes | Name/key of a Kubernetes Secret holding the DB credentials (see below). |
| `keycloak.image.tag` | Yes | Keycloak image tag to deploy. |
| `keycloak.truststores` | No | Only needed if Keycloak must trust a custom CA (e.g. to validate other products' client JWKS over TLS with an internal/self-signed certificate). ⚠️ In this repository's default `values.yaml`, this points at a CA bundle built around the local dev `mkcert` CA (see [Overview](10-overview.md#settings-not-suitable-for-production)) — replace it with your organization's real CA before production. |
| `keycloak.tracing` / `keycloak.telemetry` | No | OpenTelemetry endpoints, disable if you don't run a collector. |
| `vault.enabled` | Yes | Enables the templated `keycloak-vault-secrets` Secret (see below). |
| `grafana.enabled` | No | Enables a bundled Grafana dashboard for the operator, optional. |

To have more details on the values you can update, please refer to the [JSON Schema of the Keycloak chart](https://cdn.mia-platform.eu/runtime/platform/auth/keycloak-chart/0.5.4/values.schema.json).

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
  (see [Keycloak Realms](40-keycloak-realms.md)). This repository generates
  it from `charts/keycloak/render_values.sh`, which reads a `clientSecret`
  value into `charts/keycloak/.local/secrets.yaml` and feeds it to
  `templates/vault.secret.yaml`. In your environment, this should be the
  client secret you intend to use for the `mia-realm` (or the realm name
  you chose)/`mia-realm-extensibility` identity-provider clients configured
  during realm import — generate it yourself and adapt the render step (or the
  Secret) to your own secret-management approach rather than reusing the
  `.local/` dev key material.

  Each key in `templates/vault.secret.yaml` follows the format
  `<realm>_<key>`, e.g. `mia-realm_mia-identity-provider-client-secret`.
  The part before the first underscore (`mia-realm`) is the realm the
  secret applies to; the part after it
  (`mia-identity-provider-client-secret`) is the key referenced in
  realm YAML as `${vault.<key>}` (see
  [Keycloak Realms](40-keycloak-realms.md)) — the realm prefix itself is not
  part of that reference. This is why the same key name can appear under
  different realm prefixes (`mia-realm` vs. `mia-realm-extensibility_`):
  each realm gets its own copy of the secret value under its own Secret key,
  even though the `${vault....}` placeholder they resolve looks identical.

## Verify

- `kubectl get pods -n keycloak` — the Keycloak instance and operator pods
  should be `Running`. (All-in-one layout: `-n default`.) In **native mode**
  there is no operator pod — only the Keycloak StatefulSet's pod — and that
  is expected, not a failed install.
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
