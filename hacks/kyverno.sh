#!/usr/bin/env bash

set -euo pipefail

###############################################################################
# kyverno.sh — Install Kyverno and make the cluster trust the local mkcert CA.
#
# Kubernetes has no cluster-wide trust store: every pod trusts only the CA
# bundle baked into its image. To let in-cluster clients validate the
# mkcert-signed https://*.mia-platform.test cert, a Kyverno ClusterPolicy:
#   1. clones a merged bundle (system CAs + mkcert rootCA) ConfigMap into
#      every non-system namespace, and
#   2. mutates every pod to (a) mount it over both /etc/ssl/certs/ca-certificates.crt
#      (Debian/Ubuntu; Envoy) and /etc/ssl/cert.pem (Alpine; the hook's curl)
#      via subPath, and (b) set SSL_CERT_FILE / CURL_CA_BUNDLE / NODE_EXTRA_CA_CERTS.
#      Between them these cover curl, Envoy, Node.js, and Rust rustls-native-certs
#      (e.g. authtool-bff, which reads the system store honoring SSL_CERT_FILE).
#
# JVM note: Java ignores this OS bundle (it uses its own truststore), so JVM
# clients are handled elsewhere:
#   - Keycloak fetches the services' merged client JWKS over mkcert TLS to
#     verify private_key_jwt assertions -> Keycloak CR `truststores` points at
#     the mkcert-ca-bundle ConfigMap this policy clones (charts/keycloak).
#   - keycloak-config-cli runs on the host via docker -> KEYCLOAK_SSLVERIFY=false.
#
# Runs BEFORE Traefik so every workload created afterwards is mutated.
# Idempotent.
#
# Environment:
#   KUBECONFIG          location of kubectl config file
#   KYVERNO_NAMESPACE   kyverno NS (default kyverno)
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

###############################################################################
# Preflight — check required binaries
###############################################################################

REQUIRED_BINS=(helm kubectl mkcert)
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

: "${KYVERNO_NAMESPACE:=kyverno}"

###############################################################################
# Install Kyverno (single-replica controllers — this is a local dev cluster)
###############################################################################

log_info "Adding Kyverno Helm repo..."
helm repo add kyverno \
    https://kyverno.github.io/kyverno/ \
    --force-update >/dev/null 2>&1
helm repo update kyverno >/dev/null 2>&1

log_info "Installing Kyverno..."
helm upgrade --install kyverno kyverno/kyverno \
    --namespace "${KYVERNO_NAMESPACE}" --create-namespace \
    --set admissionController.replicas=1 \
    --set backgroundController.replicas=1 \
    --set cleanupController.replicas=1 \
    --set reportsController.replicas=1 \
    --wait

###############################################################################
# Build the merged CA bundle (host system CAs + mkcert rootCA)
###############################################################################

CAROOT="$(mkcert -CAROOT)"
MKCERT_CA="${CAROOT}/rootCA.pem"

if [[ ! -f "${MKCERT_CA}" ]]; then
    log_error "mkcert rootCA.pem not found at ${MKCERT_CA}." \
        "Run 'mkcert -install' first."
    exit 1
fi

# Locate the host's system CA bundle so pods keep trusting public CAs too.
SYS_BUNDLE=""
for candidate in \
    /etc/ssl/certs/ca-certificates.crt \
    /etc/pki/tls/certs/ca-bundle.crt; do
    if [[ -f "${candidate}" ]]; then
        SYS_BUNDLE="${candidate}"
        break
    fi
done

BUNDLE_FILE="$(mktemp)"
trap 'rm -f "${BUNDLE_FILE}"' EXIT

if [[ -n "${SYS_BUNDLE}" ]]; then
    log_info "Merging mkcert CA into system bundle (${SYS_BUNDLE})..."
    cat "${SYS_BUNDLE}" "${MKCERT_CA}" > "${BUNDLE_FILE}"
else
    log_warn "No host CA bundle found; pods will trust ONLY the mkcert CA."
    cat "${MKCERT_CA}" > "${BUNDLE_FILE}"
fi

###############################################################################
# Source ConfigMap (cloned into every namespace by the policy below)
###############################################################################

log_info "Creating source ConfigMap 'mkcert-ca-bundle' in '${KYVERNO_NAMESPACE}'..."
kubectl -n "${KYVERNO_NAMESPACE}" create configmap mkcert-ca-bundle \
    --from-file=ca-certificates.crt="${BUNDLE_FILE}" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null

###############################################################################
# RBAC — let Kyverno's background controller clone ConfigMaps everywhere
###############################################################################

log_info "Granting Kyverno permission to manage ConfigMaps..."
kubectl apply -f - >/dev/null <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: kyverno:manage-ca-configmaps
  labels:
    rbac.kyverno.io/aggregate-to-background-controller: "true"
rules:
  - apiGroups: [""]
    resources: ["configmaps"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
EOF

###############################################################################
# ClusterPolicy — distribute the bundle + mount/wire it into every pod
###############################################################################

# `helm --wait` returns before Kyverno's policy webhook is actually serving,
# so applying a ClusterPolicy can hit "connection refused". Wait for the
# admission controller to be Available, then retry the apply with backoff.
log_info "Waiting for the Kyverno admission webhook to be ready..."
kubectl -n "${KYVERNO_NAMESPACE}" wait --for=condition=Available \
    deploy -l app.kubernetes.io/component=admission-controller \
    --timeout=120s >/dev/null

log_info "Applying 'mkcert-ca-trust' ClusterPolicy..."
POLICY_FILE="$(mktemp)"
trap 'rm -f "${BUNDLE_FILE}" "${POLICY_FILE}"' EXIT
cat > "${POLICY_FILE}" <<EOF
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: mkcert-ca-trust
spec:
  # Backfill namespaces (and re-mount running pods) that already exist.
  generateExisting: true
  rules:
    # 1) Clone the merged CA bundle into every non-system namespace so pods
    #    can mount a ConfigMap from their own namespace.
    - name: distribute-ca-bundle
      match:
        any:
          - resources:
              kinds: [Namespace]
      exclude:
        any:
          - resources:
              namespaces:
                - kube-system
                - kube-public
                - kube-node-lease
                - ${KYVERNO_NAMESPACE}
                - local-path-storage
      generate:
        apiVersion: v1
        kind: ConfigMap
        name: mkcert-ca-bundle
        namespace: "{{request.object.metadata.name}}"
        synchronize: true
        clone:
          namespace: ${KYVERNO_NAMESPACE}
          name: mkcert-ca-bundle
    # 2) Mount the bundle over the system trust store AND point Node.js at it.
    #    subPath keeps the other files in /etc/ssl/certs intact.
    - name: trust-ca-bundle
      match:
        any:
          - resources:
              kinds: [Pod]
      exclude:
        any:
          - resources:
              namespaces:
                - kube-system
                - kube-public
                - kube-node-lease
                - ${KYVERNO_NAMESPACE}
                - local-path-storage
      mutate:
        patchStrategicMerge:
          spec:
            volumes:
              - name: mkcert-ca-bundle
                configMap:
                  name: mkcert-ca-bundle
            containers:
              - (name): "?*"
                volumeMounts:
                  # Debian/Ubuntu default (also what Envoy's cds.yaml reads).
                  - name: mkcert-ca-bundle
                    mountPath: /etc/ssl/certs/ca-certificates.crt
                    subPath: ca-certificates.crt
                    readOnly: true
                  # Alpine/OpenSSL default — curl there is compiled with this
                  # hardcoded bundle path and ignores SSL_CERT_FILE, so the
                  # connectivity-check hook (curlimages/curl) needs it here too.
                  - name: mkcert-ca-bundle
                    mountPath: /etc/ssl/cert.pem
                    subPath: ca-certificates.crt
                    readOnly: true
                env:
                  # Node.js services.
                  - name: NODE_EXTRA_CA_CERTS
                    value: /etc/ssl/certs/ca-certificates.crt
                  # curl honors this explicitly, unlike SSL_CERT_FILE.
                  - name: CURL_CA_BUNDLE
                    value: /etc/ssl/certs/ca-certificates.crt
                  # OpenSSL tooling AND Rust rustls-native-certs/openssl-probe
                  # (e.g. authtool-bff, which reads the system store via this).
                  - name: SSL_CERT_FILE
                    value: /etc/ssl/certs/ca-certificates.crt
EOF

applied=false
for attempt in 1 2 3 4 5; do
    if kubectl apply -f "${POLICY_FILE}" >/dev/null 2>&1; then
        applied=true
        break
    fi
    log_warn "Webhook not ready yet (attempt ${attempt}/5), retrying in 5s..."
    sleep 5
done

if [[ "${applied}" != true ]]; then
    log_error "Failed to apply the ClusterPolicy after retries."
    kubectl apply -f "${POLICY_FILE}"  # surface the real error
    exit 1
fi

log_ok "Kyverno installed; cluster now trusts the mkcert CA."
