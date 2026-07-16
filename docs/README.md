# On-Prem Deployment Documentation

This folder documents how to install the Mia Platform product suite on your
own Kubernetes infrastructure, using the Helm charts in this repository as
the configuration reference.

## Contents

1. [Overview](01-overview.md) — components, dependency order, architecture
2. [Prerequisites](02-prerequisites.md) — cluster, ingress, DNS, datastores
3. [Keycloak](03-keycloak.md)
4. [Keycloak Realms](04-keycloak-realms.md)
5. [Services (Home + Authorization)](05-services.md)
6. [Catalog](06-catalog.md)
7. [AI Foundry](07-ai-foundry.md)
8. [Console](08-console.md)
9. [Troubleshooting](09-troubleshooting.md)

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
