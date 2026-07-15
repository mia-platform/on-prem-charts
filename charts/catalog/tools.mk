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
catalog_setup_keys catalog_install catalog_uninstall: WORKING_DIR := $(CURDIR)/charts/catalog

catalog_setup_keys: KEY_DIR := $(CURDIR)/charts/catalog/.local/authtool-bff
catalog_setup_keys: SECRETS_FILE := $(CURDIR)/charts/catalog/.local/secrets.yaml
catalog_setup_keys: RBAC_KEY := $(CURDIR)/charts/catalog/.local/rbac-management/rbac-private.pem
catalog_setup_keys: PG_HOST := postgres-postgresql.postgres.svc.cluster.local:5432
catalog_setup_keys: PG_CONN := postgresql://catalog_user:postgres@$(PG_HOST)/catalog
catalog_setup_keys: PG_CONN_ADK := postgresql+asyncpg://adk_user:postgres@$(PG_HOST)/adk
catalog_setup_keys:
	@if [ -f $(SECRETS_FILE) ]; then \
		echo "➡️  $(SECRETS_FILE) already exists, skipping key setup."; \
	else \
		mkdir -p $(WORKING_DIR)/.local/ $(dir $(RBAC_KEY)); \
		$(WORKING_DIR)/setup_bff_keys.sh -d $(KEY_DIR) --private-key; \
		test -f $(RBAC_KEY) || \
			openssl genpkey -algorithm RSA \
				-out $(RBAC_KEY) \
				-pkeyopt rsa_keygen_bits:2048 >/dev/null 2>&1; \
		$(WORKING_DIR)/render_secrets.sh --bff-dir $(KEY_DIR) \
			--rbac-key $(RBAC_KEY) --pg-conn "$(PG_CONN)" \
			--pg-conn-adk "$(PG_CONN_ADK)" --out $(SECRETS_FILE); \
	fi
.PHONY: catalog_setup_keys

catalog_install: catalog_setup_keys ## Install the catalog chart
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
