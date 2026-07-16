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

CATALOG_URL := https://catalog.mia-platform.test

catalog_open: ## Open the catalog website in the default browser
	@echo "Opening $(CATALOG_URL) ..."
	@$(OPEN) "$(CATALOG_URL)"
.PHONY: catalog_open

catalog_install catalog_uninstall: NAMESPACE := catalog
catalog_install catalog_uninstall: RELEASE := catalog
catalog_install catalog_uninstall: WORKING_DIR := $(CURDIR)/charts/catalog

catalog_install: ## Install the catalog chart
	@helm dependency build $(WORKING_DIR)
	@helm upgrade --install $(RELEASE) \
		--namespace=$(NAMESPACE) --create-namespace \
		--wait --timeout=10m \
		-f $(WORKING_DIR)/values.yaml \
		-f $(WORKING_DIR)/.local/secrets.yaml \
		$(WORKING_DIR)
.PHONY: catalog_install

catalog_uninstall: ## Uninstall the catalog chart
	@helm uninstall $(RELEASE) --namespace=$(NAMESPACE)
.PHONY: catalog_uninstall
