#!/usr/bin/env bash
set -euo pipefail

# === Default Configuration ===
KEY_DIR=".local"
RSA_BITS=2048
COOKIE_KEY_SIZE=64      # bytes
REDIS_KEY_SIZE=64       # bytes
GENERATE_PRIVATE_KEY=false
GENERATE_PUBLIC_KEY=false
OVERWRITE=false

# === Argument Parsing ===
usage() {
    echo "Usage: $0 [-d key_dir] [--private-key] [--public-key] [--overwrite]"
    echo "  -d, --dir           Output directory for keys (default .local)"
    echo "      --overwrite     Overwrite existing key files"
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--dir)
            KEY_DIR="$2"
            shift 2
            ;;
        --overwrite)
            OVERWRITE=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

if [[ -z "$KEY_DIR" ]]; then
    echo "Error: --dir is required"
    usage
fi

# === Helpers ===
mkdir -p "$KEY_DIR"

echo "🔧 Generating private key material in: $KEY_DIR"

# --- RSA keypair for AS client assertion ---
if [[ ! -f "$KEY_DIR/client-private.pem" || "$OVERWRITE" == true ]]; then
    echo "🗝 Creating RSA ${RSA_BITS}-bit keypair..."
    openssl genpkey -algorithm RSA -out "$KEY_DIR/client-private.pem" \
        -pkeyopt rsa_keygen_bits:${RSA_BITS} >/dev/null 2>&1
    echo "✅ Created client-private.pem"
else
    echo "➡️  RSA keypair already exists, skipping."
fi

echo "🔧 Generating BFF key material in: $KEY_DIR"

# --- Cookie signing key (HMAC secret) ---
if [[ ! -f "$KEY_DIR/cookie-secret.key" || "$OVERWRITE" == true ]]; then
    echo "🍪 Creating cookie signing secret..."
    openssl rand -base64 ${COOKIE_KEY_SIZE} > "$KEY_DIR/cookie-secret.key"
    echo "✅ Created cookie-secret.key"
else
    echo "➡️  cookie-secret.key already exists, skipping."
fi

# --- Redis token encryption key (AES-256-GCM) ---
if [[ ! -f "$KEY_DIR/redis-token-enc.key" || "$OVERWRITE" == true ]]; then
    echo "🔒 Creating Redis token encryption key..."
    openssl rand -base64 ${REDIS_KEY_SIZE} > "$KEY_DIR/redis-token-enc.key"
    echo "✅ Created redis-token-enc.key"
else
    echo "➡️  redis-token-enc.key already exists, skipping."
fi

# --- Generic client secret ---
if [[ ! -f "$KEY_DIR/client-secret" || "$OVERWRITE" == true ]]; then
    echo "🔒 Creating Oauth 2 client secret..."
    # hex output = only [0-9a-f], no +/=/newline that Keycloak chokes on
    openssl rand -hex 32 > "$KEY_DIR/client-secret"
    echo "✅ Created client-secret"
else
    echo "➡️  client-secret already exists, skipping."
fi

echo "🎉 Creating secrets.yaml file"

jq -n \
    --rawfile tokenEncKey   "$KEY_DIR/redis-token-enc.key" \
    --rawfile cookieSecret  "$KEY_DIR/cookie-secret.key" \
    --rawfile clientSecret  "$KEY_DIR/client-secret" \
    --rawfile privateKey    "$KEY_DIR/client-private.pem" \
    '{
        tokenEncKey:    ($tokenEncKey  | rtrimstr("\n")),
        cookieSecret:   ($cookieSecret | rtrimstr("\n")),
        clientSecret:   ($clientSecret | rtrimstr("\n")),
        privateKey:     $privateKey,
    }' | yq -P > "$KEY_DIR/secrets.yaml"

