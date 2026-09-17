# On-Prem Deployment

Helm charts for installing the Mia Platform product suite — Keycloak,
Keycloak Realms, Services (Home + Authorization), Catalog, AI Foundry, and
Console — on your own Kubernetes infrastructure.

**Start here: [`docs/`](docs/README.md)** for installation instructions,
prerequisites, and a per-product configuration reference.

## What this repository is

This repository bundles the Helm charts for the full product suite, plus a
local development environment used to build and test them end-to-end. The
charts in `charts/` are the part that matters for installing the suite
elsewhere — everything else exists to support developing and testing them.

## Structure

| Path | Contents |
|---|---|
| `docs/` | Installation documentation for deploying the suite on your own infrastructure — see [`docs/README.md`](docs/README.md). |
| `charts/` | One Helm chart per product (`keycloak`, `keycloak-realms`, `services`, `catalog`, `ai-foundry`, `console`), each with its own `Chart.yaml`, `values.yaml`, and `tools.mk`. |
| `hacks/` | Bash scripts that provision a local development environment: TLS, ingress, DNS, and the datastores (PostgreSQL, MongoDB, Redis, Kafka) the charts depend on. Local-dev only — not part of the product suite. |
| `.kind/` | Configuration for the local `kind` Kubernetes cluster used in development. |
| `.local/` | Generated key material for local development (gitignored). |
| `Makefile` | Entry point for the local development workflow — includes each chart's `tools.mk` and the cluster-provisioning targets in `.kind/tools.mk`. |

## Local development

`make up` provisions a local `kind` cluster with everything the charts need
(see `hacks/` above), after which each product can be installed with its
own `make` target — run `make help` for the full list. This is intended for
developing and testing the charts in this repository, not as an
installation method for your own infrastructure; see
[`docs/`](docs/README.md) for that.

There are two ways to lay the products out in the local cluster:

| Layout | Targets | Where products land |
|---|---|---|
| **Namespace-per-product** (default) | `make 010_keycloak` … `make 060_console` | One namespace per product (`keycloak`, `services`, `catalog`, `ai-foundry`, `console`). |
| **All-in-one** | `make 010_keycloak_all_in_one` … `make 060_console_all_in_one` | Everything in the `default` namespace, using each chart's `values.all-in-one.yaml` overlay. |

Pick one and use it for the whole suite — the two are alternatives, not
steps to combine. See [Installation layouts](docs/10-overview.md#installation-layouts)
for what the all-in-one overlay changes and why.

Orthogonally to the layout, **Keycloak** can be installed with or without
the Keycloak Operator. Appending `_native` to either Keycloak target
(`make 010_keycloak_native`, `make 010_keycloak_all_in_one_native`) applies
`charts/keycloak/values.native.yaml`, which runs Keycloak as a plain
StatefulSet — no operator, no CRDs, no cluster-scoped RBAC, single instance.
Keycloak serves the same URL either way and the rest of the install is
unchanged; see [Run modes](docs/30-keycloak.md#run-modes-operator-or-native).

> **`NAMESPACE` is mandatory on the bare targets.** The numbered targets
> above pass it for you, but the underlying per-chart targets
> (`catalog_install`, `catalog_uninstall`, `console_uninstall`, …) no longer
> default to a namespace — invoke them as
> `make catalog_uninstall NAMESPACE=catalog`.
