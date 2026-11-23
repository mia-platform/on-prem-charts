#!/usr/bin/env bash

set -euo pipefail

###############################################################################
# Install OpenBao in dev mode on kind and provision the KV v2 and ServiceAccount
# JWT settings from the AI Foundry, AI Services and Catalog values.
#
# Environment:
#   OPENBAO_NAMESPACE   openbao namespace (default: openbao)
#   OPENBAO_ROOT_TOKEN  dev-mode root token (default: root)
#   KIND_CLUSTER_NAME   kind cluster name (default: mia-on-prem)
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
KIND_CLUSTER_NAME=${KIND_CLUSTER_NAME:-mia-on-prem}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHARTS_DIR="${SCRIPT_DIR}/../charts"

###############################################################################
# Preflight — check required binaries
###############################################################################

REQUIRED_BINS=(helm kubectl docker jq yq)
missing=()

for bin in "${REQUIRED_BINS[@]}"; do
    if ! command -v "${bin}" &> /dev/null; then
        missing+=("${bin}")
    fi
done

if [[ ${#missing[@]} -gt 0 ]]; then
    log_error "Missing required binaries: ${missing[*]}"
    exit 1
fi

if [[ "$(kubectl config current-context)" != "kind-${KIND_CLUSTER_NAME}" ]]; then
    log_error "Select Kubernetes context kind-${KIND_CLUSTER_NAME} before running this script."
    exit 1
fi

# Read kind's public signing key so OpenBao can verify projected tokens
# without calling Kubernetes' authenticated discovery endpoints.
SIGNING_KEY=$(docker exec "${KIND_CLUSTER_NAME}-control-plane" cat /etc/kubernetes/pki/sa.pub)
TOKEN_ISSUER=$(kubectl get --raw /.well-known/openid-configuration | jq -er '.issuer')

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
    --set-string server.dev.devRootToken="${OPENBAO_ROOT_TOKEN}" \
    --set injector.enabled=false \
    --wait

log_info "Waiting for OpenBao..."
kubectl wait --namespace "${OPENBAO_NAMESPACE}" \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/instance=${RELEASE_NAME},app.kubernetes.io/name=openbao \
    --timeout=120s

log_ok "OpenBao is ready."

###############################################################################
# Configure namespaces, KV mounts and JWT roles
###############################################################################

OPENBAO_POD=$(kubectl get pod --namespace "${OPENBAO_NAMESPACE}" \
    --selector=app.kubernetes.io/instance=${RELEASE_NAME},app.kubernetes.io/name=openbao \
    -o jsonpath='{.items[0].metadata.name}')

bao_in() {
    local store_namespace=$1
    shift
    kubectl exec -i --namespace "${OPENBAO_NAMESPACE}" "${OPENBAO_POD}" -- \
        env BAO_ADDR=http://127.0.0.1:8200 BAO_TOKEN="${OPENBAO_ROOT_TOKEN}" \
        BAO_NAMESPACE="$store_namespace" bao "$@"
}

ensure_namespace() {
    local parent="" part
    local -a parts
    IFS=/ read -r -a parts <<< "$1"
    for part in "${parts[@]}"; do
        if ! bao_in "$parent" read "sys/namespaces/$part" >/dev/null 2>&1; then
            bao_in "$parent" namespace create "$part" >/dev/null
        fi
        parent="${parent:+$parent/}$part"
    done
}

for product in ai-foundry ai-services catalog; do
    chart_config=$(PRODUCT="$product" yq -o=json -e \
        '.[strenv(PRODUCT)].secretStoreService.config' "$CHARTS_DIR/$product/values.yaml")
    store_namespace=$(jq -er '.storeNamespace' <<< "$chart_config")
    kv_mount=$(jq -er '.storeKvMount' <<< "$chart_config")
    jwt_mount=$(jq -er '.auth.jwt.mount' <<< "$chart_config")
    jwt_role=$(jq -er '.auth.jwt.role' <<< "$chart_config")
    jwt_audience=$(jq -er '.auth.jwt.audience // "openbao"' <<< "$chart_config")
    name_prefix=$(PRODUCT="$product" yq -e \
        '.[strenv(PRODUCT)].namespacePrefix' "$CHARTS_DIR/$product/values.all-in-one.yaml")

    log_info "Configuring JWT and KV v2 for $product in '$store_namespace'..."
    ensure_namespace "$store_namespace"

    if ! bao_in "$store_namespace" secrets list -format=json |
        jq -e --arg mount "$kv_mount/" '.[$mount].options.version == "2"' >/dev/null; then
        bao_in "$store_namespace" secrets enable -path="$kv_mount" kv-v2 >/dev/null
    fi
    if ! bao_in "$store_namespace" auth list -format=json |
        jq -e --arg mount "$jwt_mount/" '.[$mount].type == "jwt"' >/dev/null; then
        bao_in "$store_namespace" auth enable -path="$jwt_mount" jwt >/dev/null
    fi
    jq -n --arg issuer "$TOKEN_ISSUER" --arg key "$SIGNING_KEY" \
        '{bound_issuer: $issuer, jwt_validation_pubkeys: [$key]}' |
        bao_in "$store_namespace" write "auth/$jwt_mount/config" - >/dev/null

    bao_in "$store_namespace" policy write "$jwt_role" - >/dev/null <<EOF
path "$kv_mount/data/*" {
  capabilities = ["create", "read", "update", "patch", "delete"]
}
path "$kv_mount/metadata/*" {
  capabilities = ["read", "list", "delete"]
}
path "$kv_mount/delete/*" {
  capabilities = ["update"]
}
path "$kv_mount/undelete/*" {
  capabilities = ["update"]
}
path "$kv_mount/destroy/*" {
  capabilities = ["update"]
}
EOF

    jq -n --arg audience "$jwt_audience" --arg policy "$jwt_role" \
        --arg product_account "system:serviceaccount:$product:secret-store-service" \
        --arg all_in_one_account "system:serviceaccount:default:$name_prefix-secret-store-service" \
        '{
            role_type: "jwt",
            user_claim: "sub",
            bound_audiences: [$audience],
            bound_claims: {sub: [$product_account, $all_in_one_account]},
            token_policies: [$policy],
            token_ttl: "15m"
        }' | bao_in "$store_namespace" write "auth/$jwt_mount/role/$jwt_role" - >/dev/null
done

###############################################################################
# Connection details
###############################################################################

log_ok "Address: http://${RELEASE_NAME}.${OPENBAO_NAMESPACE}.svc.cluster.local:8200"
log_warn "Dev mode: data and JWT configuration are lost on pod restart. Re-run this script to restore the configuration."
