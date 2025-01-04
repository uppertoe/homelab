#!/bin/bash

# ==============================================
# Token Rotation Script for Caddy Authentication
# ==============================================

# Path to the token storage file
PARENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
TOKEN_FILE="$PARENT_DIRECTORY/config/caddy/secrets/.tokens"

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
CURRENT_TOKEN_LINE=$(grep "^PROXY_COOKIE_ID=" "$TOKEN_FILE")
CURRENT_TOKEN_VALUE=${CURRENT_TOKEN_LINE#PROXY_COOKIE_ID=}

# Function to update or add a key-value pair in the token file
update_token_file() {
    local key="$1"
    local value="$2"
    if grep -q "^${key}=" "$TOKEN_FILE"; then
        sed -i.bak "s/^${key}=.*/${key}=${value}/" "$TOKEN_FILE"
    else
        echo "${key}=${value}" >> "$TOKEN_FILE"
    fi
}

# Check if PROXY_COOKIE_ID is set and not empty
if [ -n "$CURRENT_TOKEN_VALUE" ]; then
    # PROXY_COOKIE_ID exists and is not empty
    # Update PROXY_COOKIE_ID_PREVIOUS with the current token
    update_token_file "PROXY_COOKIE_ID_PREVIOUS" "$CURRENT_TOKEN_VALUE"

    # Update PROXY_COOKIE_ID with the new token
    update_token_file "PROXY_COOKIE_ID" "$NEW_TOKEN"

    echo "PROXY_COOKIE_ID_PREVIOUS set to existing token."
    echo "PROXY_COOKIE_ID updated to new token."
else
    # PROXY_COOKIE_ID is empty or does not exist
    # Generate a new token for both PROXY_COOKIE_ID_PREVIOUS and PROXY_COOKIE_ID
    update_token_file "PROXY_COOKIE_ID_PREVIOUS" "$NEW_TOKEN"
    update_token_file "PROXY_COOKIE_ID" "$NEW_TOKEN"

    echo "PROXY_COOKIE_ID was empty or missing."
    echo "Both PROXY_COOKIE_ID_PREVIOUS and PROXY_COOKIE_ID set to new token."
fi

# Optional: Remove backup file created by sed (if not needed)
rm -f "${TOKEN_FILE}.bak"

# Output the new tokens (for verification; remove in production)
echo "Token rotation successful."
echo "PROXY_COOKIE_ID_PREVIOUS=$(grep "^PROXY_COOKIE_ID_PREVIOUS=" "$TOKEN_FILE" | cut -d'=' -f2-)"
echo "PROXY_COOKIE_ID=$(grep "^PROXY_COOKIE_ID=" "$TOKEN_FILE" | cut -d'=' -f2-)"
