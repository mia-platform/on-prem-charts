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
own `make` target (e.g. `make 010_keycloak`, `make 040_catalog`) — run
`make help` for the full list. This is intended for developing and testing
the charts in this repository, not as an installation method for your own
infrastructure; see [`docs/`](docs/README.md) for that.
