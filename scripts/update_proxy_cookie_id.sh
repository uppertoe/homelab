#!/bin/bash

# -----------------------------------------------------------------------------
# Script Name: update_proxy_cookie_id.sh
# Description: Generates a secure 256-bit PROXY_COOKIE_ID, updates the .tokens
#              environment file, manages backups older than 4 weeks.
# -----------------------------------------------------------------------------

# Function to generate a secure 256-bit (32-byte) secret in Base64
generate_secret() {
    openssl rand -base64 32
}

# Path to the .tokens file
TOKENS_FILE="$HOME/homelab/config/caddy/secrets/.tokens"

# Backup extension for existing .tokens file
BACKUP_EXT=".bak"

# Function to update the .tokens file with the new PROXY_COOKIE_ID
update_tokens_file() {
    local new_secret="$1"

    # Ensure the directory exists
    mkdir -p "$(dirname "$TOKENS_FILE")"

    if [ -f "$TOKENS_FILE" ]; then
        # Create a timestamped backup
        local timestamp
        timestamp=$(date +%F_%T)
        cp "$TOKENS_FILE" "${TOKENS_FILE}${BACKUP_EXT}_${timestamp}"
        echo "Backup created at ${TOKENS_FILE}${BACKUP_EXT}_${timestamp}"

        # Update or add PROXY_COOKIE_ID
        if grep -q "^PROXY_COOKIE_ID=" "$TOKENS_FILE"; then
            sed -i "s/^PROXY_COOKIE_ID=.*/PROXY_COOKIE_ID=\"$new_secret\"/" "$TOKENS_FILE"
            echo "Updated PROXY_COOKIE_ID in $TOKENS_FILE."
        else
            echo "PROXY_COOKIE_ID=\"$new_secret\"" >> "$TOKENS_FILE"
            echo "Added PROXY_COOKIE_ID to $TOKENS_FILE."
        fi
    else
        # Create the .tokens file with PROXY_COOKIE_ID
        echo "PROXY_COOKIE_ID=\"$new_secret\"" > "$TOKENS_FILE"
        echo "Created $TOKENS_FILE with PROXY_COOKIE_ID."
    fi
}

# Function to remove .tokens.bak files older than 4 weeks (28 days)
cleanup_old_backups() {
    local backup_dir
    backup_dir="$(dirname "$TOKENS_FILE")"

    # Find and delete .tokens.bak_* files older than 28 days
    find "$backup_dir" -type f -name ".tokens.bak_*" -mtime +28 -exec rm -f {} +
    
    # Optionally, log the cleanup action
    echo "Cleaned up backups older than 4 weeks in $backup_dir."
}

# Function to set secure file permissions
set_file_permissions() {
    chmod 600 "$TOKENS_FILE"
    echo "Set file permissions for $TOKENS_FILE to 600."
}

# Main Execution

# Generate a new secret
NEW_PROXY_COOKIE_ID=$(generate_secret)
echo "Generated new PROXY_COOKIE_ID."

# Update the .tokens file with the new secret
update_tokens_file "$NEW_PROXY_COOKIE_ID"

# Remove backups older than 4 weeks
cleanup_old_backups

# Set secure permissions on the .tokens file
set_file_permissions

echo "PROXY_COOKIE_ID has been updated successfully."
