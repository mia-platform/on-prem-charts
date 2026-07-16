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

CONSOLE_URL := https://console.mia-platform.test
CMS_CONSOLE_URL := https://cms-console.mia-platform.test

console_open: ## Open the console website in the default browser
	@echo "Opening $(CONSOLE_URL) ..."
	@$(OPEN) "$(CONSOLE_URL)"
.PHONY: console_open

cms_console_open: ## Open the console CMS website in the default browser
	@echo "Opening $(CMS_CONSOLE_URL) ..."
	@$(OPEN) "$(CMS_CONSOLE_URL)"
.PHONY: cms_console_open

console_install console_uninstall console_render_secrets: NAMESPACE := console
console_install console_uninstall console_render_secrets: RELEASE := console
console_install console_uninstall console_render_secrets: WORKING_DIR := $(CURDIR)/charts/console

console_render_secrets: # Render charts/console/.local/secrets.yaml from key material in folder .local
	@$(WORKING_DIR)/render_values.sh
.PHONY: console_render_secrets

console_install: console_render_secrets ## Install the console chart
	@helm dependency build $(WORKING_DIR)
	@helm upgrade --install $(RELEASE) \
		--namespace=$(NAMESPACE) --create-namespace \
		--wait --timeout=10m \
		-f $(WORKING_DIR)/values.yaml \
		-f $(WORKING_DIR)/.local/secrets.yaml \
		$(WORKING_DIR)
.PHONY: console_install

console_uninstall: ## Uninstall the console chart
	@helm uninstall $(RELEASE) --namespace=$(NAMESPACE)
.PHONY: console_uninstall
