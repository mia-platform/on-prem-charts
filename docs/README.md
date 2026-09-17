# On-Prem Deployment Documentation

This folder documents how to install the Mia Platform product suite on your
own Kubernetes infrastructure, using the Helm charts in this repository as
the configuration reference.

## Contents

1. [Overview](10-overview.md) — components, dependency order, architecture
2. [Prerequisites](20-prerequisites.md) — cluster, ingress, DNS, datastores
3. [Keycloak](30-keycloak.md)
4. [Keycloak Realms](40-keycloak-realms.md)
5. [Services (Home + Authorization)](50-services.md)
6. [Catalog](60-catalog.md)
7. [AI Foundry](70-ai-foundry.md)
8. [Console](80-console.md)
9. [Troubleshooting](90-troubleshooting.md)

## How to read this

Install the products in the order listed above — later products depend on
the ones before them (Keycloak Realms needs a running Keycloak, Console
needs Services for authorization, and so on). Each product page documents:

- What the product is and what it depends on
- The Helm chart location and how to install/upgrade it
- The `values.yaml` fields you need to configure, split into required and
  optional
- The secrets it expects, and where that sensitive material should come from
  in your own infrastructure
- How to verify the product is healthy before moving to the next one

Each page's `helm upgrade --install` example installs the product into a
namespace of its own, which is what you'll normally want in your own
infrastructure. This repository's local `kind` setup also supports an
**all-in-one** layout that puts the whole suite in a single namespace — see
[Installation layouts](10-overview.md#installation-layouts) for what that
changes and when it's worth using.

Separately, Keycloak can run either through the Keycloak Operator (default)
or as a plain StatefulSet with no operator. That choice is independent of
the namespace layout and applies to Keycloak alone — see
[Run modes](30-keycloak.md#run-modes-operator-or-native).
