export KUBECONFIG := $(CURDIR)/.kind/config

keycloak_install keycloak_uninstall: NAMESPACE := keycloak
keycloak_install keycloak_uninstall: RELEASE := keycloak
keycloak_install keycloak_uninstall: WORKING_DIR := $(CURDIR)/charts/keycloak

keycloak_install: ## Install the Keycloak chart
	@helm dependency build $(WORKING_DIR)
	@helm upgrade --install $(RELEASE) \
		--namespace=$(NAMESPACE) --create-namespace \
		--wait --timeout=10m \
		-f $(WORKING_DIR)/values.yaml \
		-f $(WORKING_DIR)/secrets/admin-bootstrap.yaml \
		-f $(WORKING_DIR)/secrets/postgres-credentials.yaml \
		-f $(WORKING_DIR)/secrets/vault.yaml \
		$(WORKING_DIR)
.PHONY: keycloak_install

keycloak_uninstall: ## Uninstall the Keycloak chart
	@helm uninstall $(RELEASE) --namespace=$(NAMESPACE)
.PHONY: keycloak_uninstall
