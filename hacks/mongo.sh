#!/usr/bin/env bash

set -euo pipefail

###############################################################################
# mongo.sh — Install a MongoDB replicaset on cluster
#
# Environment:
#   MONGO_NAMESPACE       mongo namespace (default: mongo)
#   MONGO_ROOT_PASSWORD   mongo root password (default: mongo)
#   MONGO_REPLICA_COUNT   number of replicaset members (default: 3)
#   KUBECONFIG            location of kubectl config file
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

MONGO_NAMESPACE=${MONGO_NAMESPACE:=mongo}
MONGO_ROOT_PASSWORD=${MONGO_ROOT_PASSWORD:=mongo}
MONGO_REPLICA_COUNT=${MONGO_REPLICA_COUNT:=3}

RELEASE_NAME=mongo
FULLNAME="${RELEASE_NAME}-mongodb"

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
# Install MongoDB
###############################################################################

log_info "Adding Bitnami Helm repo..."
helm repo add bitnami \
    https://charts.bitnami.com/bitnami/ \
    --force-update >/dev/null 2>&1
helm repo update bitnami >/dev/null 2>&1

log_info "Installing MongoDB replicaset (${MONGO_REPLICA_COUNT} members)..."
helm upgrade --install ${RELEASE_NAME} bitnami/mongodb \
    --namespace ${MONGO_NAMESPACE} --create-namespace \
    --set architecture=replicaset \
    --set replicaCount=${MONGO_REPLICA_COUNT} \
    --set auth.rootPassword=${MONGO_ROOT_PASSWORD} \
    --set persistence.enabled=false \
    --wait

log_info "Waiting for MongoDB..."
kubectl wait --namespace ${MONGO_NAMESPACE} \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/instance=${RELEASE_NAME},app.kubernetes.io/name=mongodb \
    --timeout=180s

log_ok "MongoDB replicaset is ready."

###############################################################################
# Connection string
###############################################################################

HOSTS=""
for ((i = 0; i < MONGO_REPLICA_COUNT; i++)); do
    HOST="${FULLNAME}-${i}.${FULLNAME}-headless.${MONGO_NAMESPACE}.svc.cluster.local:27017"
    if [[ -z "${HOSTS}" ]]; then
        HOSTS="${HOST}"
    else
        HOSTS="${HOSTS},${HOST}"
    fi
done

CONNECTION_STRING="mongodb://root:${MONGO_ROOT_PASSWORD}@${HOSTS}/?replicaSet=rs0&authSource=admin"

log_ok "Connection string: ${CONNECTION_STRING}"
