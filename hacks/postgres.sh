#!/usr/bin/env bash

set -euo pipefail

###############################################################################
# postgres.sh — Install postgres DB on cluster
#
# Environment:
#   POSTGRES_NAMESPACE  postgres namespace (default: postgres)
#   POSTGRES_PASSWORD   postgres password (default: postgres)
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

POSTGRES_NAMESPACE=${POSTGRES_NAMESPACE:=postgres}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD:=postgres}

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
# Install Postgres
###############################################################################

log_info "Adding Bitnami Helm repo..."
helm repo add bitnami \
    https://charts.bitnami.com/bitnami/ \
    --force-update >/dev/null 2>&1
helm repo update bitnami >/dev/null 2>&1

log_info "Installing PostgreSQL..."
helm upgrade --install postgres bitnami/postgresql \
    --namespace "${POSTGRES_NAMESPACE}" --create-namespace \
    --set auth.postgresPassword="${POSTGRES_PASSWORD}" \
    --set primary.persistence.enabled=false \
    --wait

log_info "Waiting for PostgreSQL..."
kubectl wait --namespace "${POSTGRES_NAMESPACE}" \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/instance=postgres,app.kubernetes.io/name=postgresql \
    --timeout=120s

log_ok "PostgreSQL is ready."

###############################################################################
# Run init scripts
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_DIR="${SCRIPT_DIR}/postgres"

POSTGRES_POD=$(kubectl get pod --namespace "${POSTGRES_NAMESPACE}" \
    --selector=app.kubernetes.io/instance=postgres,app.kubernetes.io/name=postgresql \
    -o jsonpath='{.items[0].metadata.name}')

for sql_file in "${SQL_DIR}"/*.sql; do
    log_info "Running $(basename "${sql_file}")..."
    kubectl exec -i --namespace "${POSTGRES_NAMESPACE}" "${POSTGRES_POD}" -- \
        env PGPASSWORD="${POSTGRES_PASSWORD}" psql -U postgres -f - < "${sql_file}"
done

log_ok "Postgres init scripts applied."
