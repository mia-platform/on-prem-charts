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

KEYCLOAK_URL := https://auth.mia-platform.test

keycloak_open: ## Open the Keycloak admin console in the default browser
	@echo "Opening $(KEYCLOAK_URL) ..."
	@$(OPEN) "$(KEYCLOAK_URL)"
.PHONY: keycloak_open

REALM_TARGETS := keycloak_realms_master_as_admin_install keycloak_realms_production_install

$(REALM_TARGETS): NAMESPACE := keycloak-realms # just for templating
$(REALM_TARGETS): RELEASE := keycloak-realms # just for templating
$(REALM_TARGETS): WORKING_DIR := $(CURDIR)/charts/keycloak-realms

# Production realms imported via the keycloak-config-cli service account
# (client_credentials). Add new realms here — the recipe loops over them.
PRODUCTION_REALMS := products extensibility

keycloak_realms_master_as_admin_install:
	@helm dependency build $(WORKING_DIR)
	@cd $(WORKING_DIR) && ./template.sh -r master -e prod
	@docker run \
		--rm \
		--network host \
		--add-host auth.mia-platform.test:127.0.0.1 \
		-v $(WORKING_DIR)/rendered/prod/master/master:/configs \
		-e KEYCLOAK_URL="$(KEYCLOAK_URL)" \
		-e KEYCLOAK_SSLVERIFY="false" \
		-e KEYCLOAK_USER="admin" \
		-e KEYCLOAK_PASSWORD="change_me" \
		-e KEYCLOAK_LOGIN_REALM="master" \
		-e KEYCLOAK_SKIPSERVERINFO="true" \
		-e IMPORT_REMOTESTATE_ENABLED="true" \
		-e IMPORT_VARSUBSTITUTION_ENABLED="false" \
		-e IMPORT_MANAGED_AUTHENTICATIONFLOWS=no-delete \
		-e IMPORT_MANAGED_CLIENT=no-delete \
		-e IMPORT_MANAGED_USER=no-delete \
		-e IMPORT_MANAGED_IDENTITYPROVIDER=no-delete \
		-e IMPORT_USERS_MERGEROLES="true" \
		-e IMPORT_USERS_MERGEGROUPS="true" \
		-e IMPORT_MANAGED_ROLE=no-delete \
		-e IMPORT_MANAGED_GROUP=no-delete \
		-e IMPORT_MANAGED_SUBGROUP=no-delete \
		-e IMPORT_MANAGED_ORGANIZATION=no-delete \
		-e KEYCLOAK_AVAILABILITYCHECK_ENABLED="true" \
		-e KEYCLOAK_AVAILABILITYCHECK_TIMEOUT="30s" \
		-e IMPORT_FILES_LOCATIONS="/configs/*.yaml" \
		docker.io/adorsys/keycloak-config-cli:latest-26.5.4
.PHONY: keycloak_realms_master_as_admin_install

keycloak_realms_production_install:
	@helm dependency build $(WORKING_DIR)
	@for realm in $(PRODUCTION_REALMS); do \
		cd $(WORKING_DIR) && ./template.sh -r $$realm -e prod -t production; \
		docker run \
			--rm \
			--network host \
			--add-host auth.mia-platform.test:127.0.0.1 \
			-v $(WORKING_DIR)/rendered/prod/production/$$realm:/configs \
			-e KEYCLOAK_URL="$(KEYCLOAK_URL)" \
			-e KEYCLOAK_CLIENT_ID=keycloak-config-cli \
			-e KEYCLOAK_CLIENT_SECRET=change_me \
			-e KEYCLOAK_GRANT_TYPE=client_credentials \
			-e KEYCLOAK_SSLVERIFY="false" \
			-e KEYCLOAK_LOGIN_REALM="master" \
			-e KEYCLOAK_SKIPSERVERINFO="true" \
			-e IMPORT_REMOTESTATE_ENABLED="true" \
			-e IMPORT_VARSUBSTITUTION_ENABLED="false" \
			-e IMPORT_MANAGED_AUTHENTICATIONFLOWS=no-delete \
			-e IMPORT_MANAGED_CLIENT=no-delete \
			-e IMPORT_MANAGED_USER=no-delete \
			-e IMPORT_MANAGED_IDENTITYPROVIDER=no-delete \
			-e IMPORT_USERS_MERGEROLES="true" \
			-e IMPORT_USERS_MERGEGROUPS="true" \
			-e IMPORT_MANAGED_ROLE=no-delete \
			-e IMPORT_MANAGED_GROUP=no-delete \
			-e IMPORT_MANAGED_SUBGROUP=no-delete \
			-e IMPORT_MANAGED_ORGANIZATION=no-delete \
			-e KEYCLOAK_AVAILABILITYCHECK_ENABLED="true" \
			-e KEYCLOAK_AVAILABILITYCHECK_TIMEOUT="30s" \
			-e IMPORT_FILES_LOCATIONS="/configs/*.yaml" \
			docker.io/adorsys/keycloak-config-cli:latest-26.5.4; \
	done
.PHONY: keycloak_realms_production_install
