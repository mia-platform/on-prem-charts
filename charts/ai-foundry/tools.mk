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

AI_FOUNDRY_URL := https://ai-foundry.mia-platform.test

ai_foundry_open: ## Open the ai-foundry website in the default browser
	@echo "Opening $(AI_FOUNDRY_URL) ..."
	@$(OPEN) "$(AI_FOUNDRY_URL)"
.PHONY: ai_foundry_open

ai_foundry_install ai_foundry_uninstall ai_foundry_render_secrets: NAMESPACE := ai-foundry
ai_foundry_install ai_foundry_uninstall ai_foundry_render_secrets: RELEASE := ai-foundry
ai_foundry_install ai_foundry_uninstall ai_foundry_render_secrets: WORKING_DIR := $(CURDIR)/charts/ai-foundry

ai_foundry_render_secrets: ## Render charts/ai-foundry/.local/secrets.yaml from key material in folder .local
	@$(WORKING_DIR)/render_values.sh
.PHONY: ai_foundry_render_secrets

ai_foundry_install: ai_foundry_render_secrets ## Install the ai-foundry chart
	@helm dependency build $(WORKING_DIR)
	@helm upgrade --install $(RELEASE) \
		--namespace=$(NAMESPACE) --create-namespace \
		--wait --timeout=10m \
		-f $(WORKING_DIR)/values.yaml \
		-f $(WORKING_DIR)/.local/secrets.yaml \
		$(WORKING_DIR)
.PHONY: ai_foundry_install

ai_foundry_uninstall: ## Uninstall the ai-foundry chart
	@helm uninstall $(RELEASE) --namespace=$(NAMESPACE)
.PHONY: ai_foundry_uninstall
