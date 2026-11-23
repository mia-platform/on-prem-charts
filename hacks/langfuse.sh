#!/usr/bin/env bash

set -euo pipefail

###############################################################################
# langfuse.sh — Install Langfuse on cluster, the trace store of AI Services'
# OpenTelemetry Collector and of AI Foundry's observability screens
#
# Installs, with their official charts:
#   - cert-manager            (prerequisite of the ClickHouse operator)
#   - clickhouse-operator     (renders the ClickHouse/Keeper clusters Langfuse
#                              stores traces in)
#   - langfuse                (web + worker, with its bundled PostgreSQL,
#                              Valkey, SeaweedFS and ClickHouse)
# sized for a local kind cluster: one ClickHouse replica, one Keeper replica,
# small volumes. Not a production setup: size and back up the stores there,
# or point Langfuse at managed ones (see docs/20-prerequisites.md).
#
# Headless initialisation (LANGFUSE_INIT_*) creates an organization, a project
# with a known API key pair and an admin user on first start. The key pair is
# generated once and kept in .local/ so a re-run keeps the same project keys:
#   .local/langfuse-public-key, .local/langfuse-secret-key
#   .local/langfuse-admin-password
# charts/ai-services/render_values.sh and charts/ai-foundry/render_values.sh
# read the key pair.
#
# Environment:
#   LANGFUSE_NAMESPACE      langfuse namespace (default: langfuse)
#   LANGFUSE_HOST           public hostname (default: langfuse.mia-platform.test)
#   LANGFUSE_ADMIN_EMAIL    admin user (default: admin@mia-platform.test)
#   KUBECONFIG              location of kubectl config file
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

LANGFUSE_NAMESPACE=${LANGFUSE_NAMESPACE:=langfuse}
LANGFUSE_HOST=${LANGFUSE_HOST:=langfuse.mia-platform.test}
LANGFUSE_ADMIN_EMAIL=${LANGFUSE_ADMIN_EMAIL:=admin@mia-platform.test}

# Pinned together: Langfuse chart 2.1.0 ships Langfuse 4.24.0, the version
# AI Services' and AI Foundry's observability is tested against
# (ai-services-local-dev). The cert-manager and operator versions are the ones
# that chart's README names as its prerequisites.
readonly CERT_MANAGER_VERSION=v1.20.2
readonly CLICKHOUSE_OPERATOR_VERSION=0.0.5
readonly LANGFUSE_CHART_VERSION=2.1.0

readonly RELEASE_NAME=langfuse
readonly LANGFUSE_ORG_ID=mia-platform
readonly LANGFUSE_PROJECT_ID=mia-platform-ai

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_LOCAL="${SCRIPT_DIR}/../.local"

###############################################################################
# Preflight — check required binaries
###############################################################################

REQUIRED_BINS=(helm kubectl openssl)
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
# Project key pair and admin password (generated once, then reused)
###############################################################################

mkdir -p "${ROOT_LOCAL}"

ensure_secret_file() {
    local file="$1" value="$2"
    if [[ ! -s "${ROOT_LOCAL}/${file}" ]]; then
        printf '%s' "${value}" > "${ROOT_LOCAL}/${file}"
        log_info "Generated ${ROOT_LOCAL}/${file}."
    fi
}

ensure_secret_file langfuse-public-key "pk-lf-$(openssl rand -hex 16)"
ensure_secret_file langfuse-secret-key "sk-lf-$(openssl rand -hex 16)"
ensure_secret_file langfuse-admin-password "$(openssl rand -hex 12)"

PUBLIC_KEY=$(cat "${ROOT_LOCAL}/langfuse-public-key")
SECRET_KEY=$(cat "${ROOT_LOCAL}/langfuse-secret-key")
ADMIN_PASSWORD=$(cat "${ROOT_LOCAL}/langfuse-admin-password")

###############################################################################
# cert-manager
###############################################################################

if kubectl get crd certificates.cert-manager.io &> /dev/null; then
    log_info "cert-manager CRDs already present, skipping install."
else
    log_info "Installing cert-manager ${CERT_MANAGER_VERSION}..."
    helm upgrade --install cert-manager oci://quay.io/jetstack/charts/cert-manager \
        --version "${CERT_MANAGER_VERSION}" \
        --namespace cert-manager --create-namespace \
        --set crds.enabled=true \
        --wait
fi

kubectl wait --for=condition=Established \
    crd/certificates.cert-manager.io crd/issuers.cert-manager.io \
    --timeout=120s

log_ok "cert-manager is ready."

###############################################################################
# ClickHouse operator
###############################################################################

log_info "Installing clickhouse-operator ${CLICKHOUSE_OPERATOR_VERSION}..."
helm upgrade --install clickhouse-operator oci://ghcr.io/clickhouse/clickhouse-operator-helm \
    --version "${CLICKHOUSE_OPERATOR_VERSION}" \
    --namespace clickhouse-operator --create-namespace \
    --wait

kubectl wait --for=condition=Established \
    crd/clickhouseclusters.clickhouse.com crd/keeperclusters.clickhouse.com \
    --timeout=120s

log_ok "clickhouse-operator is ready."

###############################################################################
# Langfuse
###############################################################################

log_info "Adding Langfuse Helm repo..."
helm repo add langfuse \
    https://langfuse.github.io/langfuse-k8s \
    --force-update >/dev/null 2>&1
helm repo update langfuse >/dev/null 2>&1

# Values go through a file, not --set: the LANGFUSE_INIT_* list and the
# ingress hosts are lists of maps, which --set spells badly.
VALUES_FILE=$(mktemp)
trap 'rm -f "${VALUES_FILE}"' EXIT

cat > "${VALUES_FILE}" <<EOF
langfuse:
  nextauth:
    url: "https://${LANGFUSE_HOST}"
  # Only the headless-init organization exists: nobody signs up to create
  # another one next to it.
  # No usage statistics leave an on-prem installation.
  features:
    signUpDisabled: true
    telemetryEnabled: false
  additionalEnv:
    - name: LANGFUSE_INIT_ORG_ID
      value: "${LANGFUSE_ORG_ID}"
    - name: LANGFUSE_INIT_ORG_NAME
      value: "Mia-Platform"
    - name: LANGFUSE_INIT_PROJECT_ID
      value: "${LANGFUSE_PROJECT_ID}"
    - name: LANGFUSE_INIT_PROJECT_NAME
      value: "Mia-Platform AI"
    - name: LANGFUSE_INIT_PROJECT_PUBLIC_KEY
      value: "${PUBLIC_KEY}"
    - name: LANGFUSE_INIT_PROJECT_SECRET_KEY
      value: "${SECRET_KEY}"
    - name: LANGFUSE_INIT_USER_EMAIL
      value: "${LANGFUSE_ADMIN_EMAIL}"
    - name: LANGFUSE_INIT_USER_NAME
      value: "Admin"
    - name: LANGFUSE_INIT_USER_PASSWORD
      value: "${ADMIN_PASSWORD}"
  # The chart has no startupProbe and starts liveness after 20s: on a busy
  # node (a kind cluster coming back up, everything starting at once) web and
  # worker need longer than that to boot and are killed in a loop. Measured on
  # kind: >50s after a Docker restart.
  web:
    livenessProbe:
      initialDelaySeconds: 180
  worker:
    livenessProbe:
      initialDelaySeconds: 180
  ingress:
    enabled: true
    className: traefik
    annotations:
      traefik.ingress.kubernetes.io/router.entrypoints: websecure
    hosts:
      - host: "${LANGFUSE_HOST}"
        paths:
          - path: /
            pathType: Prefix

postgresql:
  storage:
    requestedSize: 2Gi

clickhouse:
  cluster:
    replicas: 1
    storage:
      size: 5Gi
    resources:
      requests:
        cpu: 250m
        memory: 1Gi
      limits:
        memory: 2Gi
  keeper:
    replicas: 1
    storage:
      size: 1Gi
    resources:
      requests:
        cpu: 50m
        memory: 128Mi
      limits:
        memory: 512Mi
EOF

log_info "Installing Langfuse (chart ${LANGFUSE_CHART_VERSION})..."
helm upgrade --install ${RELEASE_NAME} langfuse/langfuse \
    --version "${LANGFUSE_CHART_VERSION}" \
    --namespace "${LANGFUSE_NAMESPACE}" --create-namespace \
    -f "${VALUES_FILE}" \
    --wait --timeout=15m

log_info "Waiting for Langfuse web..."
kubectl wait --namespace "${LANGFUSE_NAMESPACE}" \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/instance=${RELEASE_NAME},app=web \
    --timeout=300s

log_ok "Langfuse is ready."

###############################################################################
# Connection details
###############################################################################

log_ok "UI: https://${LANGFUSE_HOST} (user ${LANGFUSE_ADMIN_EMAIL}, password in ${ROOT_LOCAL}/langfuse-admin-password)"
log_ok "In-cluster: http://${RELEASE_NAME}-web.${LANGFUSE_NAMESPACE}.svc.cluster.local:3000"
log_ok "OTLP traces: http://${RELEASE_NAME}-web.${LANGFUSE_NAMESPACE}.svc.cluster.local:3000/api/public/otel/v1/traces"
log_ok "Project keys: ${ROOT_LOCAL}/langfuse-public-key, ${ROOT_LOCAL}/langfuse-secret-key"
log_warn "Re-running keeps the same keys; deleting .local/langfuse-* after the first install leaves a project whose keys no longer match."
