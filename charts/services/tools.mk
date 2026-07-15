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

HOME_URL := https://home.mia-platform.test

services_open: ## Open the Services website in the default browser
	@echo "Opening $(HOME_URL) ..."
	@$(OPEN) "$(HOME_URL)"
.PHONY: services_open

services_install services_uninstall: NAMESPACE := services
services_install services_uninstall: RELEASE := services
services_setup_keys services_install services_uninstall: WORKING_DIR := $(CURDIR)/charts/services

services_setup_keys: KEY_DIR := $(CURDIR)/charts/services/.local/authtool-bff
services_setup_keys: SECRETS_FILE := $(CURDIR)/charts/services/.local/secrets.yaml
services_setup_keys: RBAC_KEY := $(CURDIR)/charts/services/.local/rbac-management/rbac-private.pem
services_setup_keys: PG_HOST := postgres-postgresql.postgres.svc.cluster.local:5432
services_setup_keys: PG_CONN := postgresql://authz_user:postgres@$(PG_HOST)/authz
services_setup_keys:
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
			--rbac-key $(RBAC_KEY) --pg-conn "$(PG_CONN)" --out $(SECRETS_FILE); \
	fi
.PHONY: services_setup_keys

services_install: services_setup_keys ## Install the services chart
	@helm dependency build $(WORKING_DIR)
	@helm upgrade --install $(RELEASE) \
		--namespace=$(NAMESPACE) --create-namespace \
		--wait --timeout=10m \
		-f $(WORKING_DIR)/values.yaml \
		-f $(WORKING_DIR)/.local/secrets.yaml \
		$(WORKING_DIR)
.PHONY: services_install

services_uninstall: ## Uninstall the services chart
	@helm uninstall $(RELEASE) --namespace=$(NAMESPACE)
.PHONY: services_uninstall
