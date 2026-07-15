#!/usr/bin/env bash

set -euo pipefail

###############################################################################
# traefik.sh — Install traefik on cluster
#
# Environment:
#   TRAEFIK_VALUES      location of traefik chart values
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

if [[ -z "${TRAEFIK_VALUES:-}" ]]; then
    log_error "Missing 'TRAEFIK_VALUES' env var"
    exit 1
fi

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
# Install Traefik
###############################################################################

log_info "Adding Traefik Helm repo..."
helm repo add traefik \
    https://traefik.github.io/charts/ \
    --force-update >/dev/null 2>&1
helm repo update traefik >/dev/null 2>&1

log_info "Installing Traefik..."
helm upgrade --install traefik traefik/traefik \
    --namespace traefik --create-namespace \
    -f "${TRAEFIK_VALUES}" \
    --wait

log_info "Waiting for Traefik controller..."
kubectl wait --namespace traefik \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/name=traefik \
    --timeout=120s

log_ok "Traefik is ready."
