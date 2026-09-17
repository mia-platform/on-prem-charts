export KUBECONFIG := $(CURDIR)/.kind/config

##@ Keycloak chart targets (NAMESPACE required)

keycloak_install keycloak_install_native keycloak_uninstall keycloak_render_secrets: RELEASE := keycloak
keycloak_install keycloak_install_native keycloak_uninstall keycloak_render_secrets: WORKING_DIR := $(CURDIR)/charts/keycloak

keycloak_render_secrets: # Render charts/keycloak/.local/secrets.yaml from key material in folder .local
	@$(WORKING_DIR)/render_values.sh
.PHONY: keycloak_render_secrets

keycloak_install: keycloak_render_secrets ## Install the Keycloak chart (requires NAMESPACE=...)
	@helm dependency build $(WORKING_DIR)
	@helm upgrade --install $(RELEASE) \
		--namespace=$(NAMESPACE) --create-namespace \
		--wait --timeout=10m \
		-f $(WORKING_DIR)/values.yaml \
		$(WORKING_DIR)
.PHONY: keycloak_install

keycloak_install_native: keycloak_render_secrets ## Install the Keycloak chart without the operator (requires NAMESPACE=...)
	@helm dependency build $(WORKING_DIR)
	@helm upgrade --install $(RELEASE) \
		--namespace=$(NAMESPACE) --create-namespace \
		--wait --timeout=10m \
		-f $(WORKING_DIR)/values.yaml \
		-f $(WORKING_DIR)/values.native.yaml \
		$(WORKING_DIR)
.PHONY: keycloak_install_native

keycloak_uninstall: ## Uninstall the Keycloak chart (requires NAMESPACE=...)
	@helm uninstall $(RELEASE) --namespace=$(NAMESPACE)
.PHONY: keycloak_uninstall
