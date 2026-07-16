#!/usr/bin/env bash

set -euo pipefail

###############################################################################
# tls.sh — Generate local TLS certs and load them into the traefik namespace
#          so Traefik can terminate TLS. Must run BEFORE traefik is installed.
#
# Environment:
#   KUBECONFIG          location of kubectl config file
#   OUTPUT_DIR          certificates output directory (default $ROOT/.kind/tls)
#   TRAEFIK_NAMESPACE   traefik NS (default traefik)
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${SCRIPT_DIR}/.."
OUTPUT_DIR="${OUTPUT_DIR:=${ROOT_DIR}/.kind/tls}"

###############################################################################
# Preflight — check required binaries
###############################################################################

REQUIRED_BINS=(mkcert kubectl)
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
# Preflight — check /etc/hosts for the *.mia-platform.test hostnames
#
# Note: glibc's resolver does NOT expand wildcards in /etc/hosts, so every
# real subdomain must be listed explicitly (the "*.mia-platform.test" entry
# is cosmetic — it only documents intent). Add new ingress hosts here as they
# are introduced, or switch to a wildcard resolver (dnsmasq) instead.
###############################################################################

HOSTS=(
    'mia-platform.test'
    'auth.mia-platform.test'
    'home.mia-platform.test'
    'catalog.mia-platform.test'
    'ai-foundry.mia-platform.test'
    'console.mia-platform.test'
    'cms-console.mia-platform.test'
    '*.mia-platform.test'  # cosmetic: documents intent, not resolved by glibc
)

for host in "${HOSTS[@]}"; do
    escaped="${host//./\\.}"
    escaped="${escaped//\*/\\*}"
    if ! grep -qE \
        "^\s*127\.0\.0\.1\s+([^[:space:]]+\s+)*${escaped}(\s|$)" \
        /etc/hosts; then
        log_warn "/etc/hosts is missing:" \
            "127.0.0.1 ${host}"
        log_info "Adding it now (sudo required)..."
        echo "127.0.0.1 ${host}" \
            | sudo tee -a /etc/hosts > /dev/null
        log_ok "Entry added to /etc/hosts."
    fi
done

###############################################################################
# TLS - certificates
###############################################################################

: "${TRAEFIK_NAMESPACE:=traefik}"

TLS_DIR=".kind/.local/tls"
CERT_FILE="${TLS_DIR}/tls.crt"
KEY_FILE="${TLS_DIR}/tls.key"

mkdir -p "${TLS_DIR}"

# Idempotent: only (re)generate the certificate if it is missing.
if [[ -f "${CERT_FILE}" && -f "${KEY_FILE}" ]]; then
    log_info "TLS certificate already present at" \
        "${CERT_FILE}, skipping mkcert."
else
    log_info "Generating TLS certificate with mkcert..."
    mkcert \
        -cert-file "${CERT_FILE}" \
        -key-file "${KEY_FILE}" \
        *.mia-platform.test mia-platform.test localhost 127.0.0.1 ::1
fi

# Traefik terminates TLS, so its namespace must exist and hold the cert
# secret BEFORE the chart is installed.
log_info "Ensuring '${TRAEFIK_NAMESPACE}' namespace exists..."
kubectl create namespace "${TRAEFIK_NAMESPACE}" \
    --dry-run=client -o yaml | kubectl apply -f -

log_info "Creating 'traefik-tls' secret in '${TRAEFIK_NAMESPACE}' namespace..."
kubectl create secret tls traefik-tls \
    --cert="${CERT_FILE}" \
    --key="${KEY_FILE}" \
    --namespace="${TRAEFIK_NAMESPACE}" \
    --dry-run=client -o yaml | kubectl apply -f -

log_ok "TLS secret 'traefik-tls' ready."
