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

services_install services_uninstall services_render_secrets: NAMESPACE := services
services_install services_uninstall services_render_secrets: RELEASE := services
services_install services_uninstall services_render_secrets: WORKING_DIR := $(CURDIR)/charts/services

services_render_secrets: ## Render charts/services/.local/secrets.yaml from key material in folder .local
	@$(WORKING_DIR)/render_values.sh
.PHONY: services_render_secrets

services_install: services_render_secrets ## Install the services chart
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
