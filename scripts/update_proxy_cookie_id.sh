#!/bin/bash

# ==============================================
# Token Rotation Script for Caddy Authentication
# ==============================================

# Path to the token storage file
TOKEN_FILE="../config/caddy/secrets/.tokens"

# Ensure the token file exists; create if it doesn't
if [ ! -f "$TOKEN_FILE" ]; then
    touch "$TOKEN_FILE"
fi

# Function to generate a new secure token
generate_new_token() {
    # Generates a 32-byte (256-bit) hex string
    openssl rand -hex 32
}

# Generate a new token
NEW_TOKEN=$(generate_new_token)

# Extract the current PROXY_COOKIE_ID, if it exists
CURRENT_TOKEN=$(grep "^PROXY_COOKIE_ID=" "$TOKEN_FILE" | cut -d'=' -f2-)

# Update PROXY_COOKIE_ID_PREVIOUS with the current token
if [ -n "$CURRENT_TOKEN" ]; then
    # If PROXY_COOKIE_ID exists, set it as PROXY_COOKIE_ID_PREVIOUS
    sed -i.bak "/^PROXY_COOKIE_ID_PREVIOUS=/d" "$TOKEN_FILE"  # Remove existing PROXY_COOKIE_ID_PREVIOUS
    sed -i.bak "/^PROXY_COOKIE_ID=/s/^/PROXY_COOKIE_ID_PREVIOUS=$CURRENT_TOKEN\n/" "$TOKEN_FILE"
else
    # If PROXY_COOKIE_ID doesn't exist, ensure PROXY_COOKIE_ID_PREVIOUS is empty
    sed -i.bak "/^PROXY_COOKIE_ID_PREVIOUS=/d" "$TOKEN_FILE"  # Remove existing PROXY_COOKIE_ID_PREVIOUS
    echo "PROXY_COOKIE_ID_PREVIOUS=" >> "$TOKEN_FILE"
fi

# Update PROXY_COOKIE_ID with the new token
if grep -q "^PROXY_COOKIE_ID=" "$TOKEN_FILE"; then
    # If PROXY_COOKIE_ID exists, replace it with the new token
    sed -i.bak "s/^PROXY_COOKIE_ID=.*/PROXY_COOKIE_ID=$NEW_TOKEN/" "$TOKEN_FILE"
else
    # If PROXY_COOKIE_ID doesn't exist, add it
    echo "PROXY_COOKIE_ID=$NEW_TOKEN" >> "$TOKEN_FILE"
fi

# Optional: Remove backup file created by sed (if not needed)
rm -f "${TOKEN_FILE}.bak"

# Output the new tokens (for verification; remove in production)
echo "Token rotation successful."
echo "PROXY_COOKIE_ID_PREVIOUS=$CURRENT_TOKEN"
echo "PROXY_COOKIE_ID=$NEW_TOKEN"
