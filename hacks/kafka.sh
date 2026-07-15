#!/usr/bin/env bash

set -euo pipefail

###############################################################################
# kafka.sh — Install a Kafka cluster on K8S via strimzi operator
#
# Environment:
#   KAFKA_NAMESPACE     kafka cluster namespace (default: kafka)
#   CATALOG_NAMESPACE   nodepool for catalog (default: catalog)
#   KUBECONFIG          location of kubectl config file
###############################################################################

###############################################################################
# Helpers
###############################################################################

readonly GREEN='\033[32m'
readonly YELLOW='\033[33m'
readonly BLUE='\033[34m'
readonly RED='\033[31m'
readonly RESET='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${RESET}  $1"
}

log_ok() {
    echo -e "${GREEN}[OK]${RESET}    $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${RESET}  $*"
}

log_error() {
    echo -e "${RED}[ERROR]${RESET} $*"
}

KAFKA_NAMESPACE=${KAFKA_NAMESPACE:=kafka}
CATALOG_NAMESPACE=${CATALOG_NAMESPACE:=catalog}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${SCRIPT_DIR}/.."

###############################################################################
# Preflight — check required binaries
###############################################################################

REQUIRED_BINS=(helm)
missing=()

for bin in "${REQUIRED_BINS[@]}"; do
    if ! command -v "${bin}" &> /dev/null; then
        missing+=("${bin}")
    fi
done

if [[ ${#missing[@]} -gt 0 ]]; then
    log_error "Missing required" \
        "binaries: ${missing[*]}"
    exit 1
fi

###############################################################################
# Install Strimzi Kafka Operator
###############################################################################

log_info "Adding Strimzi Helm repo..."
helm repo add strimzi \
    https://strimzi.io/charts/ \
    --force-update >/dev/null 2>&1
helm repo update strimzi >/dev/null 2>&1

log_info "Adding Strimzi CRDs..."
kubectl apply --server-side --force-conflicts \
    -f https://github.com/strimzi/strimzi-kafka-operator/releases/download/0.50.0/strimzi-crds-0.50.0.yaml

log_info "Waiting for Strimzi CRDs to be established..."
kubectl wait --for=condition=established --timeout=60s \
    crd/kafkas.kafka.strimzi.io \
    crd/kafkanodepools.kafka.strimzi.io \
    crd/kafkatopics.kafka.strimzi.io

log_info "Installing Strimzi Kafka Operator..."
helm upgrade --install kafka strimzi/strimzi-kafka-operator \
    --namespace ${KAFKA_NAMESPACE} --create-namespace \
    --skip-crds \
    --set=watchAnyNamespace=true \
    --wait

log_info "Waiting for Kafka Strimzi Operator..."
kubectl wait --namespace ${KAFKA_NAMESPACE} \
    --for=condition=ready pod \
    --selector=strimzi.io/kind=cluster-operator \
    --timeout=120s

log_info "Ensuring '${CATALOG_NAMESPACE}' namespace exists..."
kubectl create namespace "${CATALOG_NAMESPACE}" \
    --dry-run=client -o yaml | kubectl apply -f -

log_info "Install Kafka templates"
kubectl apply --namespace=${CATALOG_NAMESPACE} \
    -f "${SCRIPT_DIR}/kafka/"

log_info "Waiting for Kafka cluster to be ready..."
kubectl wait --namespace=${CATALOG_NAMESPACE} \
    --for=condition=Ready kafka/catalog-kafka \
    --timeout=300s

log_info "Waiting for Kafka topics to be ready..."
kubectl wait --namespace=${CATALOG_NAMESPACE} \
    --for=condition=Ready kafkatopic --all \
    --timeout=120s

log_ok "Kafka Strimzi Operator is ready."
