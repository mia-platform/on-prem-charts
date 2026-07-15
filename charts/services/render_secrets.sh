#!/usr/bin/env bash
set -euo pipefail

# Assemble the services secrets.yaml from generated key material.
# Builds JSON with jq (one named --rawfile per key file) and converts to YAML.

usage() {
    echo "Usage: $0 --bff-dir DIR --rbac-key FILE --pg-conn STRING --out FILE"
    echo "  --bff-dir    Directory holding the authtool-bff key material"
    echo "  --rbac-key   RSA private key (PEM) for rbac management"
    echo "  --pg-conn    Postgres connection string for rbac management"
    echo "  --out        Output secrets.yaml path"
    exit 1
}

BFF_DIR="" RBAC_KEY="" PG_CONN="" OUT=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --bff-dir)  BFF_DIR="$2";  shift 2 ;;
        --rbac-key) RBAC_KEY="$2"; shift 2 ;;
        --pg-conn)  PG_CONN="$2";  shift 2 ;;
        --out)      OUT="$2";      shift 2 ;;
        -h|--help)  usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

[[ -n "$BFF_DIR" && -n "$RBAC_KEY" && -n "$PG_CONN" && -n "$OUT" ]] || usage

jq -n \
    --rawfile tokenEncKey   "$BFF_DIR/redis-token-enc.key" \
    --rawfile cookieSecret  "$BFF_DIR/cookie-secret.key" \
    --rawfile bffPrivateKey "$BFF_DIR/client-private.pem" \
    --rawfile rbacPrivateKey "$RBAC_KEY" \
    --arg     pgConn        "$PG_CONN" \
    '{
        services: {
            secrets: {
                authtoolBffKeys: {
                    tokenEncKey:  ($tokenEncKey  | rtrimstr("\n")),
                    cookieSecret: ($cookieSecret | rtrimstr("\n")),
                    privateKey:   $bffPrivateKey
                },
                rbacManagementKeys: {
                    postgresConnectionString: $pgConn,
                    privateKey: $rbacPrivateKey
                }
            }
        }
    }' | yq -P > "$OUT"

echo "✅ Wrote BFF + RBAC secrets into $OUT"
