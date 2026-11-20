#!/usr/bin/env bash
set -euo pipefail

# Generates one shared pool of key material in .local/,
# ready to be used in charts secrets.

KEY_DIR=".local"
RSA_BITS=2048
COOKIE_KEY_SIZE=64      # bytes
REDIS_KEY_SIZE=64       # bytes
OVERWRITE=false

usage() {
    echo "Usage: $0 [--overwrite]"
    echo "      --overwrite     Regenerate existing key files"
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
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
    echo "➡️  client-private.pem already exists, skipping."
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
    echo "🔒 Creating OAuth2 client secret..."
    # hex output = only [0-9a-f], no +/=/newline that Keycloak chokes on
    openssl rand -hex 32 > "$KEY_DIR/client-secret"
    echo "✅ Created client-secret"
else
    echo "➡️  client-secret already exists, skipping."
fi

# --- RSA keypair of the AI Foundry provisioner service account ---
# Kept apart from client-private.pem on purpose: Keycloak accepts an assertion
# signed with any key of the provisioner client's JWKS, and that account is a
# platform superadmin.
if [[ ! -f "$KEY_DIR/provisioner-private.pem" || "$OVERWRITE" == true ]]; then
    echo "🗝 Creating AI Foundry provisioner RSA ${RSA_BITS}-bit keypair..."
    openssl genpkey -algorithm RSA -out "$KEY_DIR/provisioner-private.pem" \
        -pkeyopt rsa_keygen_bits:${RSA_BITS} >/dev/null 2>&1
    echo "✅ Created provisioner-private.pem"
else
    echo "➡️  provisioner-private.pem already exists, skipping."
fi

echo "🔧 Generating AI Services / AI Foundry key material in: $KEY_DIR"

# --- LiteLLM master key (AI Services AI gateway admin key, also used by ai-foundry-be) ---
if [[ ! -f "$KEY_DIR/litellm-master-key" || "$OVERWRITE" == true ]]; then
    echo "🔑 Creating LiteLLM master key..."
    echo "sk-$(openssl rand -hex 32)" > "$KEY_DIR/litellm-master-key"
    echo "✅ Created litellm-master-key"
else
    echo "➡️  litellm-master-key already exists, skipping."
fi

# --- LiteLLM salt key (encrypts provider credentials at rest: never rotate in place) ---
if [[ ! -f "$KEY_DIR/litellm-salt-key" || "$OVERWRITE" == true ]]; then
    echo "🧂 Creating LiteLLM salt key..."
    echo "sk-$(openssl rand -hex 32)" > "$KEY_DIR/litellm-salt-key"
    echo "✅ Created litellm-salt-key"
else
    echo "➡️  litellm-salt-key already exists, skipping."
fi

# --- ai-foundry-be MCP OAuth consent signing key ---
if [[ ! -f "$KEY_DIR/mcp-consent-key" || "$OVERWRITE" == true ]]; then
    echo "🔒 Creating MCP consent signing key..."
    openssl rand -hex 32 > "$KEY_DIR/mcp-consent-key"
    echo "✅ Created mcp-consent-key"
else
    echo "➡️  mcp-consent-key already exists, skipping."
fi

echo "🎉 All key material ready in: $KEY_DIR"
