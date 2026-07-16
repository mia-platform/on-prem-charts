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
services_install services_uninstall: WORKING_DIR := $(CURDIR)/charts/services

services_install: ## Install the services chart
	@helm dependency build $(WORKING_DIR)
	@helm upgrade --install $(RELEASE) \
		--namespace=$(NAMESPACE) --create-namespace \
		--wait --timeout=10m \
		-f $(WORKING_DIR)/values.yaml \
		$(WORKING_DIR)
.PHONY: services_install

services_uninstall: ## Uninstall the services chart
	@helm uninstall $(RELEASE) --namespace=$(NAMESPACE)
.PHONY: services_uninstall
