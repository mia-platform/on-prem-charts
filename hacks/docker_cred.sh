#!/usr/bin/env bash

set -euo pipefail

###############################################################################
# docker_cred.sh — Extracts credentials from docker host machine
#
# Environment:
#   OUTPUT_DIR          credentials output directory (default $ROOT/.kind)
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
OUTPUT_DIR="${OUTPUT_DIR:=${ROOT_DIR}/.kind}"

###############################################################################
# Preflight — check required binaries
###############################################################################

REQUIRED_BINS=(docker)
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
# Docker credentials
###############################################################################

docker_config_file="$HOME/.docker/config.json"
output_dir="${OUTPUT_DIR}/.local/docker"

mkdir -p "${output_dir}"

if [[ ! -f "${docker_config_file}" ]]; then
    log_warn "No Docker config found at" \
             "${docker_config_file}. Skipping."
return
fi

credsStore=$(jq -r '.credsStore // empty' "${docker_config_file}")

if [[ -z "${credsStore}" ]]; then
    log_info "Using plain credentials."
    cp "${docker_config_file}" "${output_dir}/config.json"
elif [[ "${credsStore}" == "secretservice" ]]; then
    log_info "Using secretservice credential store."
    cp "${docker_config_file}" "${output_dir}/config.json"
elif [[ "${credsStore}" == "pass" ]]; then
    log_info "Extracting credentials from pass..."

    decoded=$(echo -n 'nexus.mia-platform.eu' | docker-credential-pass get)
    username=$(echo "${decoded}" | jq -r '.Username')
    password=$(echo "${decoded}" | jq -r '.Secret')

    jq -n \
        --arg username "${username}" \
        --arg password "${password}" \
        '{ "auths": {
            "nexus.mia-platform.eu": {
                "auth": (
                    $username + ":" + $password
                    | @base64
                )
            }
        }}' > "${output_dir}/config.json"
elif [[ "${credsStore}" == "desktop" ]]; then
    log_info "Using desktop credential store."
else
    log_error "Unsupported credential store:" \
        "${credsStore}"
    exit 1
fi

log_ok "Docker credentials ready."
