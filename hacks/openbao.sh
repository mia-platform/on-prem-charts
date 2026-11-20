#!/usr/bin/env bash

set -euo pipefail

###############################################################################
# openbao.sh — Install OpenBao on cluster, for AI Foundry's secret-store-service
#
# Runs OpenBao in *dev mode*: in-memory storage, auto-unsealed, fixed root
# token. Everything it holds — the KV mount, the AppRole, the secrets AI
# Foundry stored — is lost when the pod restarts; re-run this script and then
# `make ai_foundry_install` to get a working AppRole again. Not a production
# setup: install OpenBao (or point at your Vault) with real storage there.
#
# Configures:
#   - a KV v2 mount at `kv` (ai-foundry `secretStoreService.config.storeKvMount`)
#   - the AppRole auth method, with role `ai-foundry-secret-store` allowed to
#     read and write under that mount
# and writes the role's credentials to .local/openbao-role-id and
# .local/openbao-secret-id, which charts/ai-foundry/render_values.sh reads.
#
# Environment:
#   OPENBAO_NAMESPACE   openbao namespace (default: openbao)
#   OPENBAO_ROOT_TOKEN  dev-mode root token (default: root)
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

OPENBAO_NAMESPACE=${OPENBAO_NAMESPACE:=openbao}
OPENBAO_ROOT_TOKEN=${OPENBAO_ROOT_TOKEN:=root}

RELEASE_NAME=openbao
KV_MOUNT=kv
ROLE_NAME=ai-foundry-secret-store
POLICY_NAME=ai-foundry-secret-store

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_LOCAL="${SCRIPT_DIR}/../.local"

###############################################################################
# Preflight — check required binaries
###############################################################################

REQUIRED_BINS=(helm kubectl)
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
# Install OpenBao
###############################################################################

log_info "Adding OpenBao Helm repo..."
helm repo add openbao \
    https://openbao.github.io/openbao-helm \
    --force-update >/dev/null 2>&1
helm repo update openbao >/dev/null 2>&1

log_info "Installing OpenBao (dev mode)..."
helm upgrade --install ${RELEASE_NAME} openbao/openbao \
    --namespace "${OPENBAO_NAMESPACE}" --create-namespace \
    --set server.dev.enabled=true \
    --set server.dev.devRootToken="${OPENBAO_ROOT_TOKEN}" \
    --set injector.enabled=false \
    --wait

log_info "Waiting for OpenBao..."
kubectl wait --namespace "${OPENBAO_NAMESPACE}" \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/instance=${RELEASE_NAME},app.kubernetes.io/name=openbao \
    --timeout=120s

log_ok "OpenBao is ready."

###############################################################################
# Configure KV mount, policy and AppRole
###############################################################################

OPENBAO_POD=$(kubectl get pod --namespace "${OPENBAO_NAMESPACE}" \
    --selector=app.kubernetes.io/instance=${RELEASE_NAME},app.kubernetes.io/name=openbao \
    -o jsonpath='{.items[0].metadata.name}')

bao() {
    kubectl exec -i --namespace "${OPENBAO_NAMESPACE}" "${OPENBAO_POD}" -- \
        env BAO_ADDR=http://127.0.0.1:8200 BAO_TOKEN="${OPENBAO_ROOT_TOKEN}" bao "$@"
}

if bao secrets list -format=json | grep -q "\"${KV_MOUNT}/\""; then
    log_info "KV mount '${KV_MOUNT}' already enabled."
else
    log_info "Enabling KV v2 mount '${KV_MOUNT}'..."
    bao secrets enable -path="${KV_MOUNT}" kv-v2 >/dev/null
fi

if bao auth list -format=json | grep -q '"approle/"'; then
    log_info "AppRole auth method already enabled."
else
    log_info "Enabling AppRole auth method..."
    bao auth enable approle >/dev/null
fi

log_info "Writing policy '${POLICY_NAME}'..."
bao policy write "${POLICY_NAME}" - >/dev/null <<EOF
path "${KV_MOUNT}/data/*" {
  capabilities = ["create", "read", "update", "patch", "delete"]
}
path "${KV_MOUNT}/metadata/*" {
  capabilities = ["read", "list", "delete"]
}
path "${KV_MOUNT}/delete/*" {
  capabilities = ["update"]
}
path "${KV_MOUNT}/undelete/*" {
  capabilities = ["update"]
}
path "${KV_MOUNT}/destroy/*" {
  capabilities = ["update"]
}
EOF

log_info "Writing AppRole '${ROLE_NAME}'..."
bao write "auth/approle/role/${ROLE_NAME}" \
    token_policies="${POLICY_NAME}" \
    token_ttl=1h token_max_ttl=4h \
    secret_id_ttl=0 >/dev/null

mkdir -p "${ROOT_LOCAL}"

bao read -field=role_id "auth/approle/role/${ROLE_NAME}/role-id" \
    > "${ROOT_LOCAL}/openbao-role-id"
bao write -f -field=secret_id "auth/approle/role/${ROLE_NAME}/secret-id" \
    > "${ROOT_LOCAL}/openbao-secret-id"

log_ok "AppRole credentials written to ${ROOT_LOCAL}/openbao-role-id and openbao-secret-id."

###############################################################################
# Connection details
###############################################################################

log_ok "Address: http://${RELEASE_NAME}.${OPENBAO_NAMESPACE}.svc.cluster.local:8200"
log_ok "KV v2 mount: ${KV_MOUNT}"
log_warn "Dev mode: data and AppRole are lost on pod restart — re-run this script and reinstall AI Foundry."
