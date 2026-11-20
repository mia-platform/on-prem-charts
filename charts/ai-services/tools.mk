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

##@ AI Services chart targets (NAMESPACE required)

AI_SERVICES_URL := https://ai-services.mia-platform.test/workflow-manager/

ai_services_open: ## Open the AI Services Temporal UI in the default browser
	@echo "Opening $(AI_SERVICES_URL) ..."
	@$(OPEN) "$(AI_SERVICES_URL)"
.PHONY: ai_services_open

ai_services_install ai_services_install_all_in_one ai_services_uninstall ai_services_render_secrets: RELEASE := ai-services
ai_services_install ai_services_install_all_in_one ai_services_uninstall ai_services_render_secrets: WORKING_DIR := $(CURDIR)/charts/ai-services

ai_services_render_secrets: # Render charts/ai-services/.local/secrets.yaml from key material in folder .local
	@$(WORKING_DIR)/render_values.sh
.PHONY: ai_services_render_secrets

ai_services_install: ai_services_render_secrets ## Install the ai-services chart (requires NAMESPACE=...)
	@helm dependency build $(WORKING_DIR)
	@helm upgrade --install $(RELEASE) \
		--namespace=$(NAMESPACE) --create-namespace \
		--wait --timeout=10m \
		-f $(WORKING_DIR)/values.yaml \
		-f $(WORKING_DIR)/.local/secrets.yaml \
		$(WORKING_DIR)
.PHONY: ai_services_install

ai_services_install_all_in_one: ai_services_render_secrets ## Install the ai-services chart with the all-in-one overlay (requires NAMESPACE=...)
	@helm dependency build $(WORKING_DIR)
	@helm upgrade --install $(RELEASE) \
		--namespace=$(NAMESPACE) --create-namespace \
		--wait --timeout=10m \
		-f $(WORKING_DIR)/values.yaml \
		-f $(WORKING_DIR)/values.all-in-one.yaml \
		-f $(WORKING_DIR)/.local/secrets.yaml \
		$(WORKING_DIR)
.PHONY: ai_services_install_all_in_one

ai_services_uninstall: ## Uninstall the ai-services chart (requires NAMESPACE=...)
	@helm uninstall $(RELEASE) --namespace=$(NAMESPACE)
.PHONY: ai_services_uninstall
