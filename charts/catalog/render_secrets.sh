#!/usr/bin/env bash
set -euo pipefail

# Assemble the catalog secrets.yaml from generated key material.
# Builds JSON with jq (one named --rawfile per key file) and converts to YAML.
#
# Remaining config values (GCP credentials, SMTP username/password) are emitted
# as empty placeholders to be filled in manually — see temp.secret.yaml for the
# expected shape.

usage() {
    echo "Usage: $0 --bff-dir DIR --rbac-key FILE --pg-conn STRING --pg-conn-adk STRING --out FILE"
    echo "  --bff-dir      Directory holding the authtool-bff key material"
    echo "  --rbac-key     RSA private key (PEM) for access control"
    echo "  --pg-conn      Postgres connection string for the catalog engine"
    echo "  --pg-conn-adk  Postgres connection string for the ADK backend app"
    echo "  --out          Output secrets.yaml path"
    exit 1
}

BFF_DIR="" RBAC_KEY="" PG_CONN="" PG_CONN_ADK="" OUT=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --bff-dir)     BFF_DIR="$2";      shift 2 ;;
        --rbac-key)    RBAC_KEY="$2";     shift 2 ;;
        --pg-conn)     PG_CONN="$2";      shift 2 ;;
        --pg-conn-adk) PG_CONN_ADK="$2";  shift 2 ;;
        --out)         OUT="$2";          shift 2 ;;
        -h|--help)     usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

[[ -n "$BFF_DIR" && -n "$RBAC_KEY" && -n "$PG_CONN" && -n "$PG_CONN_ADK" && -n "$OUT" ]] || usage

jq -n \
    --rawfile tokenEncKey   "$BFF_DIR/redis-token-enc.key" \
    --rawfile cookieSecret  "$BFF_DIR/cookie-secret.key" \
    --rawfile bffPrivateKey "$BFF_DIR/client-private.pem" \
    --rawfile accessCtrlKey "$RBAC_KEY" \
    --arg     pgConn        "$PG_CONN" \
    --arg     pgConnAdk     "$PG_CONN_ADK" \
    '{
        catalog: {
            secrets: {
                accessControlKeys: {
                    privateKey: $accessCtrlKey
                },
                authtoolBffKeys: {
                    tokenEncKey:  ($tokenEncKey  | rtrimstr("\n")),
                    cookieSecret: ($cookieSecret | rtrimstr("\n")),
                    website:  { privateKey: $bffPrivateKey },
                    exchange: { privateKey: $bffPrivateKey }
                },
                adkBeAppKeys: {
                    googleApplicationCredentials: "",
                    postgresConnectionString: $pgConnAdk
                },
                catalogEngineKeys: {
                    postgresConnectionString: $pgConn
                },
                itemsCompressorKeys: {
                    postgresConnectionString: $pgConn
                },
                kafkaKeys: {
                    bootstrapServers: "catalog-kafka-kafka-bootstrap.catalog.svc:9092"
                },
                mailServiceKeys: {
                    smtpUsername: "",
                    smtpPassword: ""
                }
            }
        }
    }' | yq -P > "$OUT"

echo "✅ Wrote catalog secrets into $OUT"
