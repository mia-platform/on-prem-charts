#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_NAME=$(basename "$0")
readonly DEFAULT_MODE="chart"

DEBUG=""
CHART_NAME=${CHART_NAME:="keycloak-realm-management"}
ENVIRONMENT_TO_DEPLOY=${ENVIRONMENT_TO_DEPLOY:=noprod}
REALM_TYPE=${REALM_TYPE:-}
RELEASE_TIER=${RELEASE_TIER:=development}

usage() {
  cat >&2 <<USAGE

  ${SCRIPT_NAME} - Renders Keycloak realm templates via using Helm TPL engine

USAGE:
  ${SCRIPT_NAME} [OPTIONS]

REQUIRED OPTIONS:
  -r, --realm-type <type>       Realm to render:
                                (values: [master, products, extensibility], env: REALM_TYPE)
OPTIONAL:
  -e, --env <env>               Target environment
                                (values: [noprod, prod], default: ${ENVIRONMENT_TO_DEPLOY}, env: ENVIRONMENT_TO_DEPLOY)
  -t, --tier <tier>             Tier to release, unused when realm type is master
                                (values: [development, experimental, preproduction, lts, preview, demo, production], default: ${RELEASE_TIER}, env: RELEASE_TIER)
  -d,--debug                    Pass debug flag to helm
  -h, --help                    Show this help message

ENVIRONMENT:
  CHART_NAME                    Overrides the local chart name (default: ${CHART_NAME})

OUTPUT:
  keycloak-config-cli yaml values to configure
  a realm are saved into:

    > rendered/<env>/<tier>/<realm-type>/

  with coalescing master == tier == realm-type

EXAMPLES:
  ${SCRIPT_NAME} -e noprod -r master
  ${SCRIPT_NAME} -e noprod -r products -t development
  ${SCRIPT_NAME} -e prod -r products -t development

USAGE
  exit "${1:-1}"
}

## Helpers

readonly BLUE='\033[34m'
readonly GREEN='\033[32m'
readonly YELLOW='\033[33m'
readonly RED='\033[31m'
readonly RESET='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${RESET}  $1"
}

log_ok() {
    echo -e "${GREEN}[OK]${RESET}    $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${RESET}  $1"
}

log_error() {
    echo -e "${RED}[ERROR]${RESET}    $1"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -e|--env)               ENVIRONMENT_TO_DEPLOY="$2"; shift 2 ;;
    -r|--realm-type)        REALM_TYPE="$2"; shift 2 ;;
    -t|--tier)              RELEASE_TIER="$2"; shift 2 ;;
    -d|--debug)             DEBUG="--debug"; shift 1 ;;
    -h|--help)              usage 0 ;;
    -*)                     log_error "unknown option '$1'" >&2; echo "" >&2; usage ;;
    *)                      log_error "unexpected argument '$1'" >&2; echo "" >&2; usage ;;
  esac
done

errors=()
[[ -z "${REALM_TYPE}" ]] && errors+=("-r,--realm-type or REALM_TYPE env var is required")

case "${REALM_TYPE}" in
  master|products|extensibility) ;;
  *) errors+=("-r,--realm-type must be one of: master, products, extensibility (got '${REALM_TYPE}')") ;;
esac

if [[ "${REALM_TYPE}" != "master" ]]; then
  case "${RELEASE_TIER}" in
    development|experimental|preproduction|lts|preview|demo|production) ;;
    *) errors+=("-t,--tier must be one of: development, experimental, preproduction, lts, preview, demo, production (got '${RELEASE_TIER}')") ;;
  esac
else
  log_warn "overriding RELEASE_TIER to 'master'"
  RELEASE_TIER="master"
fi

if [[ -n "${ENVIRONMENT_TO_DEPLOY}" ]]; then
  case "${ENVIRONMENT_TO_DEPLOY}" in
    noprod|prod) ;;
    *) errors+=("-e,--env must be one of: noprod, prod (got '${ENVIRONMENT_TO_DEPLOY}')") ;;
  esac
fi

if [[ ${#errors[@]} -gt 0 ]]; then
  echo "" >&2
  for err in "${errors[@]}"; do log_error "${err}" >&2; done
  echo "" >&2
  usage
fi

values_file="values/${ENVIRONMENT_TO_DEPLOY}"
case "${REALM_TYPE}" in
  master)             values_file="${values_file}/master.yaml" ;;
  products)           values_file="${values_file}/${RELEASE_TIER}/products.yaml" ;;
  extensibility)      values_file="${values_file}/${RELEASE_TIER}/extensibility.yaml" ;;
  *)                  log_error "unreachable"; exit 1 ;;
esac

# --- Resolve templates ---

if [[ ! -d "charts" ]]; then
  log_error "charts/ directory not found: RUN 'helm dependency build'" >&2
  exit 1
fi

chart_tgz=$(find charts/ -maxdepth 1 -name "${CHART_NAME}-*.tgz" 2>/dev/null | head -1)
if [[ -z "${chart_tgz}" ]]; then
  log_error "no tarball for '${CHART_NAME}' found in charts/. Run 'helm dependency build' first." >&2
  exit 1
fi

template_names=()
while IFS= read -r entry; do
  name=$(basename "${entry}" .yaml)
  template_names+=("${name}")
done < <(tar -tf "${chart_tgz}" | grep "^${CHART_NAME}/templates/${REALM_TYPE}/.*\.yaml$")

if [[ ${#template_names[@]} -eq 0 ]]; then
  log_error "no templates found for realm type '${REALM_TYPE}' in ${chart_tgz}" >&2
  exit 1
fi

# --- Output directory ---
show_only_prefix="charts/${CHART_NAME}/templates/${REALM_TYPE}"
outdir="rendered/${ENVIRONMENT_TO_DEPLOY}/${RELEASE_TIER}/${REALM_TYPE}"
rm -rf "${outdir}"
mkdir -p "${outdir}"

# --- Render ---
for name in "${template_names[@]}"; do
  helm template keycloak-realms . ${DEBUG} \
    --show-only="${show_only_prefix}/${name}.yaml" \
    --values="./${values_file}" > "${outdir}/${name}.yaml"
  log_info "  ✓ ${name}.yaml" >&2
done

log_info "" >&2
log_info "========================================" >&2
log_info "  ✅ Output: ${outdir}" >&2
log_info "========================================" >&2
