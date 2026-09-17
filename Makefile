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

##@ Install: namespace-per-product (default layout)

010_keycloak: ## install keycloak
	@$(MAKE) keycloak_install NAMESPACE=keycloak
.PHONY: 010_keycloak

010_keycloak_native: ## install keycloak without operator
	@$(MAKE) keycloak_install_native NAMESPACE=keycloak
.PHONY: 010_keycloak_native

020_keycloak_realms: ## configures keycloak master realm
	@$(MAKE) keycloak_realms_master_as_admin_install
	@$(MAKE) keycloak_realms_production_install
.PHONY: 020_keycloak_realms

030_home: ## installs home + RBAC access control systems
	@$(MAKE) services_install NAMESPACE=services
.PHONY: 030_home

040_catalog: ## installs Catalog
	@$(MAKE) catalog_install NAMESPACE=catalog
.PHONY: 040_catalog

050_ai_foundry: ## installs AI Foundry
	@$(MAKE) ai_foundry_install NAMESPACE=ai-foundry
.PHONY: 050_ai_foundry

060_console: ## installs Console
	@$(MAKE) console_install NAMESPACE=console
.PHONY: 060_console

##@ Install: all-in-one (everything in the `default` namespace)

010_keycloak_all_in_one: ## [ALL IN ONE] install keycloak
	@$(MAKE) keycloak_install NAMESPACE=default
.PHONY: 010_keycloak_all_in_one

010_keycloak_all_in_one_native: ## [ALL IN ONE] install keycloak without operator
	@$(MAKE) keycloak_install_native NAMESPACE=default
.PHONY: 010_keycloak_all_in_one_native

020_keycloak_realms_all_in_one: ## [ALL IN ONE] configures keycloak master realm
	@$(MAKE) keycloak_realms_master_as_admin_install
	@$(MAKE) keycloak_realms_production_install
.PHONY: 020_keycloak_realms_all_in_one

030_home_all_in_one: ## [ALL IN ONE] installs home + RBAC access control systems
	@$(MAKE) services_install_all_in_one NAMESPACE=default
.PHONY: 030_home_all_in_one

040_catalog_all_in_one: ## [ALL IN ONE] installs catalog
	@$(MAKE) catalog_install_all_in_one NAMESPACE=default
.PHONY: 040_catalog_all_in_one

050_ai_foundry_all_in_one: ## [ALL IN ONE] installs ai-foundry
	@$(MAKE) ai_foundry_install_all_in_one NAMESPACE=default
.PHONY: 050_ai_foundry_all_in_one

060_console_all_in_one: ## [ALL IN ONE] installs Console
	@$(MAKE) console_install NAMESPACE=default
.PHONY: 060_console_all_in_one
