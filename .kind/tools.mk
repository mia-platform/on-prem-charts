export KIND_CLUSTER_NAME := mia-on-prem
export KUBECONFIG := $(CURDIR)/.kind/config

00_init_docker: ## Load docker registry credentials for the cluster
	@./hacks/docker_cred.sh
.PHONY: 01_init_docker

01_create_cluster: ## Create the kind cluster (skips if it already exists)
	@if kind get clusters 2>/dev/null | grep -qx '$(KIND_CLUSTER_NAME)'; then \
		echo "Kind cluster '$(KIND_CLUSTER_NAME)' already exists, skipping."; \
	else \
		kind create cluster --name=$(KIND_CLUSTER_NAME) --config $(CURDIR)/.kind/config.yaml; \
	fi
.PHONY: create_cluster

02_init_kyverno: ## Install Kyverno and make the cluster trust the mkcert CA
	@./hacks/kyverno.sh
.PHONY: 02_init_kyverno

03_init_tls: ## Generate TLS certs and load them into the traefik namespace
	@./hacks/tls.sh
.PHONY: 03_init_tls

04_init_traefik: ## Install Traefik as the cluster TLS-terminating ingress
	@TRAEFIK_VALUES=$(CURDIR)/.kind/traefik.yaml ./hacks/traefik.sh
.PHONY: 04_init_traefik

05_init_coredns: ## Rewrite *.mia-platform.test to Traefik so pods can reach ingress hosts
	@./hacks/coredns.sh
.PHONY: 05_init_coredns

06_init_postgres: ## Install PostgreSQL into the cluster
	@./hacks/postgres.sh
.PHONY: 06_init_postgres

07_init_kafka: ## Install Kafka into the cluster
	@./hacks/kafka.sh
.PHONY: 07_init_kafka

08_init_secrets: ## Produce some secrets
	@./hacks/setup_keys.sh
.PHONY: 08_init_secrets

09_init_mongo: ## Initialize a MongoDb instance into the cluster
	@./hacks/mongo.sh
.PHONY: 09_init_mongo

10_init_redis: ## Initialize a Redis instance into the cluster
	@./hacks/redis.sh
.PHONY: 10_init_redis

up: 00_init_docker 01_create_cluster 02_init_kyverno 03_init_tls 04_init_traefik 05_init_coredns 06_init_postgres 07_init_kafka 08_init_secrets 09_init_mongo 10_init_redis ## Bring up the full local cluster (cluster + creds + kyverno/ca-trust + tls + traefik + coredns + postgres)
.PHONY: up

down:
	@kind delete cluster --name=$(KIND_CLUSTER_NAME);
.PHONY: down
