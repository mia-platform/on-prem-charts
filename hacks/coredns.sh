#!/usr/bin/env bash

set -euo pipefail

###############################################################################
# coredns.sh — Teach CoreDNS to resolve *.<DOMAIN> to the Traefik service so
#              in-cluster clients (pods, Helm hooks) can reach ingress hosts
#              like https://auth.mia-platform.test by looping back through
#              Traefik, which routes by Host header. Idempotent.
#
# Why: glibc /etc/hosts wildcards don't work and, more importantly, pods
# resolve via CoreDNS — not the host. Without this rewrite, in-cluster
# lookups of *.<DOMAIN> return NXDOMAIN.
#
# Environment:
#   KUBECONFIG          location of kubectl config file
#   DOMAIN              base domain to rewrite (default mia-platform.test)
#   TRAEFIK_NAMESPACE   traefik NS (default traefik)
#   TRAEFIK_SERVICE     traefik service name (default traefik)
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

REQUIRED_BINS=(kubectl)
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
# Config
###############################################################################

: "${DOMAIN:=mia-platform.test}"
: "${TRAEFIK_NAMESPACE:=traefik}"
: "${TRAEFIK_SERVICE:=traefik}"

TARGET="${TRAEFIK_SERVICE}.${TRAEFIK_NAMESPACE}.svc.cluster.local"

# Escape dots so DOMAIN is a literal in the CoreDNS regex. The trailing
# "\.?$" tolerates the FQDN trailing dot in the query name (auth.<DOMAIN>.),
# which is why an un-escaped "...test$" anchor never matches.
DOMAIN_RE="${DOMAIN//./\\.}"
REWRITE="rewrite stop name regex (.*)\\.${DOMAIN_RE}\\.?\$ ${TARGET} answer auto"

# Sentinel comment used to detect an already-patched Corefile. We can't grep
# for the domain directly: it is stored regex-escaped (mia-platform\.test),
# so a fixed-string match would miss it and re-inject on every run.
SENTINEL="# managed by hacks/coredns.sh: rewrite *.${DOMAIN} -> Traefik"

###############################################################################
# Patch the CoreDNS Corefile (idempotent)
###############################################################################

log_info "Reading current CoreDNS Corefile..."
COREFILE="$(kubectl -n kube-system get configmap coredns \
    -o jsonpath='{.data.Corefile}')"

if grep -qF "${SENTINEL}" <<< "${COREFILE}"; then
    log_ok "CoreDNS already rewrites '*.${DOMAIN}', nothing to do."
    exit 0
fi

log_info "Injecting rewrite: *.${DOMAIN} -> ${TARGET}"

# Insert the rewrite right after the 'ready' line inside the .:53 block.
# rewrite rules must precede the plugins that answer (e.g. kubernetes).
# Pass the rule via ENVIRON (not -v): awk runs C-style escape processing on
# -v values, which would strip the backslashes from the regex.
PATCHED="$(rule="    ${SENTINEL}"$'\n'"    ${REWRITE}" awk '
    { print }
    /^[[:space:]]*ready[[:space:]]*$/ && !done { print ENVIRON["rule"]; done=1 }
' <<< "${COREFILE}")"

if ! grep -qF "${SENTINEL}" <<< "${PATCHED}"; then
    log_error "Failed to inject rewrite (no 'ready' line found in Corefile)."
    exit 1
fi

kubectl -n kube-system create configmap coredns \
    --from-literal=Corefile="${PATCHED}" \
    --dry-run=client -o yaml | kubectl -n kube-system apply -f - >/dev/null

log_info "Restarting CoreDNS to pick up the new Corefile..."
kubectl -n kube-system rollout restart deploy/coredns >/dev/null
kubectl -n kube-system rollout status deploy/coredns --timeout=90s

log_ok "CoreDNS now resolves '*.${DOMAIN}' to Traefik."
