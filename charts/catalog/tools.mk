export KUBECONFIG := $(CURDIR)/.kind/config

# OS-independent "open a URL in the default browser" command.
# Linux: xdg-open, macOS: open, Windows (Git Bash/MSYS/Cygwin): start
ifeq ($(OS),Windows_NT)
	OPEN := start
else ifeq ($(shell uname -s),Darwin)
	OPEN := open
else
	OPEN := xdg-open
endif

##@ Catalog chart targets (NAMESPACE required)

CATALOG_URL := https://catalog.mia-platform.test

catalog_open: ## Open the catalog website in the default browser
	@echo "Opening $(CATALOG_URL) ..."
	@$(OPEN) "$(CATALOG_URL)"
.PHONY: catalog_open

catalog_install catalog_install_all_in_one catalog_uninstall catalog_render_secrets: RELEASE := catalog
catalog_install catalog_install_all_in_one catalog_uninstall catalog_render_secrets: WORKING_DIR := $(CURDIR)/charts/catalog

catalog_render_secrets: # Render charts/catalog/.local/secrets.yaml from key material in folder .local
	@$(WORKING_DIR)/render_values.sh
.PHONY: catalog_render_secrets

catalog_install: catalog_render_secrets ## Install the catalog chart (requires NAMESPACE=...)
	@helm dependency build $(WORKING_DIR)
	@helm upgrade --install $(RELEASE) \
		--namespace=$(NAMESPACE) --create-namespace \
		--wait --timeout=10m \
		-f $(WORKING_DIR)/values.yaml \
		-f $(WORKING_DIR)/.local/secrets.yaml \
		$(WORKING_DIR)
.PHONY: catalog_install

catalog_install_all_in_one: catalog_render_secrets ## Install the catalog chart with the all-in-one overlay (requires NAMESPACE=...)
	@helm dependency build $(WORKING_DIR)
	@helm upgrade --install $(RELEASE) \
		--namespace=$(NAMESPACE) --create-namespace \
		--wait --timeout=10m \
		-f $(WORKING_DIR)/values.yaml \
		-f $(WORKING_DIR)/values.all-in-one.yaml \
		-f $(WORKING_DIR)/.local/secrets.yaml \
		$(WORKING_DIR)
.PHONY: catalog_install_all_in_one

catalog_uninstall: ## Uninstall the catalog chart (requires NAMESPACE=...)
	@helm uninstall $(RELEASE) --namespace=$(NAMESPACE)
.PHONY: catalog_uninstall
