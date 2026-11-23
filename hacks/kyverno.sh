#!/usr/bin/env bash

set -euo pipefail

###############################################################################
# kyverno.sh — Install Kyverno and make the cluster trust the local mkcert CA.
#
# Kubernetes has no cluster-wide trust store: every pod trusts only the CA
# bundle baked into its image. To let in-cluster clients validate the
# mkcert-signed https://*.mia-platform.test cert, two Kyverno CEL policies
# (policies.kyverno.io/v1 — Kyverno >= 1.20 rejects legacy kyverno.io/v1
# ClusterPolicy create/update):
#   1. GeneratingPolicy `mkcert-ca-distribute` clones a merged bundle
#      (system CAs + mkcert rootCA) ConfigMap into every non-system
#      namespace, existing ones included, and
#   2. MutatingPolicy `mkcert-ca-trust` mutates every new pod to
#      (a) mount it over both /etc/ssl/certs/ca-certificates.crt
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
#   KYVERNO_NAMESPACE      kyverno NS (default kyverno)
#   KYVERNO_CHART_VERSION  kyverno Helm chart version (default 3.10.0, i.e.
#                          Kyverno v1.20.0); pinned so a new upstream release
#                          cannot silently change policy APIs under us
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
: "${KYVERNO_CHART_VERSION:=3.10.0}"

###############################################################################
# Install Kyverno (single-replica controllers — this is a local dev cluster)
###############################################################################

log_info "Adding Kyverno Helm repo..."
helm repo add kyverno \
    https://kyverno.github.io/kyverno/ \
    --force-update >/dev/null 2>&1

log_info "Installing Kyverno chart ${KYVERNO_CHART_VERSION}..."
helm upgrade --install kyverno kyverno/kyverno \
    --version "${KYVERNO_CHART_VERSION}" \
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
# Policies — distribute the bundle + mount/wire it into every pod
###############################################################################

# `helm --wait` returns before Kyverno's policy webhook is actually serving,
# so applying a policy can hit "connection refused". Wait for the
# admission controller to be Available, then retry transient webhook errors.
log_info "Waiting for the Kyverno admission webhook to be ready..."
kubectl -n "${KYVERNO_NAMESPACE}" wait --for=condition=Available \
    deploy -l app.kubernetes.io/component=admission-controller \
    --timeout=120s >/dev/null

# Clusters set up before Kyverno 1.20 carry the legacy ClusterPolicy, which
# 1.20 no longer executes nor lets us update: drop it (delete is allowed).
kubectl delete clusterpolicies.kyverno.io mkcert-ca-trust \
    --ignore-not-found >/dev/null 2>&1 || true

log_info "Applying 'mkcert-ca-distribute' and 'mkcert-ca-trust' policies..."
POLICY_FILE="$(mktemp)"
trap 'rm -f "${BUNDLE_FILE}" "${POLICY_FILE}"' EXIT
cat > "${POLICY_FILE}" <<EOF
# 1) Clone the merged CA bundle into every non-system namespace so pods can
#    mount a ConfigMap from their own namespace. generateExisting backfills
#    namespaces that already exist; synchronize keeps the clones managed.
apiVersion: policies.kyverno.io/v1
kind: GeneratingPolicy
metadata:
  name: mkcert-ca-distribute
spec:
  evaluation:
    generateExisting:
      enabled: true
    synchronize:
      enabled: true
  matchConstraints:
    resourceRules:
      - apiGroups: [""]
        apiVersions: [v1]
        operations: [CREATE, UPDATE]
        resources: [namespaces]
  matchConditions:
    - name: not-system-namespace
      expression: >-
        !(object.metadata.name in ['kube-system', 'kube-public',
        'kube-node-lease', '${KYVERNO_NAMESPACE}', 'local-path-storage'])
  variables:
    - name: source
      expression: >-
        resource.Get("v1", "configmaps", "${KYVERNO_NAMESPACE}",
        "mkcert-ca-bundle")
  generate:
    # A clean object (not the fetched one) so no server-side metadata of the
    # source (uid, resourceVersion, namespace) leaks into the clone.
    - expression: >-
        generator.Apply(object.metadata.name, [{
          "apiVersion": "v1",
          "kind": "ConfigMap",
          "metadata": {"name": "mkcert-ca-bundle"},
          "data": variables.source.data
        }])
---
# 2) Mount the bundle over the system trust stores AND point TLS clients at
#    it. subPath keeps the other files in /etc/ssl/certs intact. Applies to
#    pods at CREATE only (running pods keep their spec until recreated).
#    Autogen is off: pods of Deployments/StatefulSets/Jobs are mutated when
#    created, their templates stay untouched.
apiVersion: policies.kyverno.io/v1
kind: MutatingPolicy
metadata:
  name: mkcert-ca-trust
spec:
  autogen:
    podControllers:
      controllers: []
  matchConstraints:
    resourceRules:
      - apiGroups: [""]
        apiVersions: [v1]
        operations: [CREATE]
        resources: [pods]
    namespaceSelector:
      matchExpressions:
        - key: kubernetes.io/metadata.name
          operator: NotIn
          values:
            - kube-system
            - kube-public
            - kube-node-lease
            - ${KYVERNO_NAMESPACE}
            - local-path-storage
  mutations:
    # Server-side-apply merge: volumes/env merge by name, volumeMounts by
    # mountPath, containers by name — existing entries are kept.
    #   /etc/ssl/certs/ca-certificates.crt  Debian/Ubuntu default (also what
    #                                       Envoy's cds.yaml reads).
    #   /etc/ssl/cert.pem                   Alpine/OpenSSL default — curl there
    #                                       is compiled with this hardcoded
    #                                       path and ignores SSL_CERT_FILE, so
    #                                       the connectivity-check hook
    #                                       (curlimages/curl) needs it too.
    #   NODE_EXTRA_CA_CERTS                 Node.js services.
    #   CURL_CA_BUNDLE                      curl honors this explicitly.
    #   SSL_CERT_FILE                       OpenSSL tooling AND Rust
    #                                       rustls-native-certs/openssl-probe
    #                                       (e.g. authtool-bff).
    - patchType: ApplyConfiguration
      applyConfiguration:
        expression: >-
          Object{
            spec: Object.spec{
              volumes: [Object.spec.volumes{
                name: "mkcert-ca-bundle",
                configMap: Object.spec.volumes.configMap{
                  name: "mkcert-ca-bundle"
                }
              }],
              containers: object.spec.containers.map(c,
                Object.spec.containers{
                  name: c.name,
                  volumeMounts: [
                    Object.spec.containers.volumeMounts{
                      name: "mkcert-ca-bundle",
                      mountPath: "/etc/ssl/certs/ca-certificates.crt",
                      subPath: "ca-certificates.crt",
                      readOnly: true
                    },
                    Object.spec.containers.volumeMounts{
                      name: "mkcert-ca-bundle",
                      mountPath: "/etc/ssl/cert.pem",
                      subPath: "ca-certificates.crt",
                      readOnly: true
                    }
                  ],
                  env: [
                    Object.spec.containers.env{
                      name: "NODE_EXTRA_CA_CERTS",
                      value: "/etc/ssl/certs/ca-certificates.crt"
                    },
                    Object.spec.containers.env{
                      name: "CURL_CA_BUNDLE",
                      value: "/etc/ssl/certs/ca-certificates.crt"
                    },
                    Object.spec.containers.env{
                      name: "SSL_CERT_FILE",
                      value: "/etc/ssl/certs/ca-certificates.crt"
                    }
                  ]
                })
            }
          }
EOF

# Retry only while the webhook is not reachable yet; any other error (e.g. a
# policy rejected by validation) is final and is shown immediately.
readonly TRANSIENT='connection refused|no endpoints available|failed calling webhook|context deadline exceeded|i/o timeout'
applied=false
for attempt in 1 2 3 4 5; do
    if output="$(kubectl apply -f "${POLICY_FILE}" 2>&1)"; then
        applied=true
        break
    fi
    if ! grep -qiE "${TRANSIENT}" <<<"${output}"; then
        log_error "Failed to apply the policies:"
        echo "${output}" >&2
        exit 1
    fi
    log_warn "Webhook not ready yet (attempt ${attempt}/5), retrying in 5s..."
    sleep 5
done

if [[ "${applied}" != true ]]; then
    log_error "Failed to apply the policies after retries:"
    echo "${output}" >&2
    exit 1
fi

# The policies only act once Kyverno has registered their webhooks: wait for
# that, so workloads created by the next steps (Traefik, ...) are mutated.
log_info "Waiting for the policies to be ready..."
for policy in generatingpolicy/mkcert-ca-distribute \
    mutatingpolicy/mkcert-ca-trust; do
    kubectl wait "${policy}" \
        --for=jsonpath='{.status.conditionStatus.ready}'=true \
        --timeout=120s >/dev/null
done

log_ok "Kyverno installed; cluster now trusts the mkcert CA."
