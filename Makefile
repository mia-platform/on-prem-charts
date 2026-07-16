.DEFAULT_GOAL := help

# Additional tools to create a local cluster with kind
include .kind/tools.mk
include charts/catalog/tools.mk
include charts/keycloak/tools.mk
include charts/keycloak-realms/tools.mk
include charts/services/tools.mk
include charts/ai-foundry/tools.mk
include charts/console/tools.mk

export KUBECONFIG := $(CURDIR)/.kind/config

help: ## Show this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage: make \033[36m<target>\033[0m\n\nTargets:\n"} \
		/^[a-zA-Z0-9_-]+:.*?##/ { printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2 } \
		/^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) }' \
		$(MAKEFILE_LIST)
.PHONY: help

010_keycloak: ## install keycloak
	@$(MAKE) keycloak_install
.PHONY: 010_keycloak

020_keycloak_realms: ## configures keycloak master realm
	@$(MAKE) keycloak_realms_master_as_admin_install
	@$(MAKE) keycloak_realms_production_install
.PHONY: 020_keycloak_realms

030_home: ## installs home + RBAC access control systems
	@$(MAKE) services_install
.PHONY: 030_home

040_catalog: ## installs Catalog
	@$(MAKE) catalog_install
.PHONY: 040_catalog

050_ai_foundry: ## installs AI Foundry
	@$(MAKE) ai_foundry_install
.PHONY: 050_ai_foundry

060_console: ## installs Console
	@$(MAKE) console_install
.PHONY: 060_console