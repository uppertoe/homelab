#!/bin/bash

# -----------------------------------------------------------------------------
# Script Name: update_proxy_credentials.sh
# Description: Generates a bcrypt-hashed password and updates the .hashes
#              environment file with PROXY_USERNAME and PROXY_PASSWORD_HASHED.
# -----------------------------------------------------------------------------

# Function to generate a bcrypt-hashed password
generate_hash() {
    # Usage: generate_hash username password
    htpasswd -nbBC 12 "$1" "$2" | cut -d':' -f2 | sed 's/\$/$$/g'
}

# Path to the .hashes file
PROJECT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
HASHES_FILE="$PROJECT_DIR/config/caddy/secrets/.hashes"

# Backup the existing .hashes file if it exists
backup_hashes_file() {
    if [ -f "$HASHES_FILE" ]; then
        cp "$HASHES_FILE" "${HASHES_FILE}.bak_$(date +%F_%T)"
        echo "Backup created at ${HASHES_FILE}.bak_$(date +%F_%T)"
    fi
}

# Update the .hashes file with new credentials
update_hashes_file() {
    local username="$1"
    local hashed_password="$2"

    # Check if PROXY_USERNAME exists and update or add it
    if grep -q "^PROXY_USERNAME=" "$HASHES_FILE" 2>/dev/null; then
        sed -i.bak "s/^PROXY_USERNAME=.*/PROXY_USERNAME=\"$username\"/" "$HASHES_FILE"
        echo "Updated PROXY_USERNAME in $HASHES_FILE."
    else
        echo "PROXY_USERNAME=\"$username\"" >> "$HASHES_FILE"
        echo "Added PROXY_USERNAME to $HASHES_FILE."
    fi

    # Check if PROXY_PASSWORD_HASHED exists and update or add it
    if grep -q "^PROXY_PASSWORD_HASHED=" "$HASHES_FILE" 2>/dev/null; then
        sed -i.bak "s/^PROXY_PASSWORD_HASHED=.*/PROXY_PASSWORD_HASHED=\"$hashed_password\"/" "$HASHES_FILE"
        echo "Updated PROXY_PASSWORD_HASHED in $HASHES_FILE."
    else
        echo "PROXY_PASSWORD_HASHED=\"$hashed_password\"" >> "$HASHES_FILE"
        echo "Added PROXY_PASSWORD_HASHED to $HASHES_FILE."
    fi
}

# Set secure permissions on the .hashes file
set_file_permissions() {
    chmod 600 "$HASHES_FILE"
    echo "Set file permissions for $HASHES_FILE to 600."
}

# Main script execution starts here

# Prompt for Username
read -p "Enter PROXY_USERNAME: " USERNAME

# Prompt for Password securely
while true; do
    read -s -p "Enter PROXY_PASSWORD: " PASSWORD
    echo
    read -s -p "Confirm PROXY_PASSWORD: " PASSWORD_CONFIRM
    echo

    if [ "$PASSWORD" != "$PASSWORD_CONFIRM" ]; then
        echo "Passwords do not match. Please try again."
    elif [ -z "$PASSWORD" ]; then
        echo "Password cannot be empty. Please try again."
    else
        break
    fi
done

# Generate hashed password
HASHED_PASSWORD=$(generate_hash "$USERNAME" "$PASSWORD")

# Inform the user about the hash generation
echo "Generated hashed password."

# Backup existing .hashes file
backup_hashes_file

# Create the directory if it doesn't exist
mkdir -p "$(dirname "$HASHES_FILE")"

# Update the .hashes file with new credentials
update_hashes_file "$USERNAME" "$HASHED_PASSWORD"

# Set secure permissions on the .hashes file
set_file_permissions

echo "PROXY_USERNAME and PROXY_PASSWORD_HASHED have been successfully updated in $HASHES_FILE."

echo "Restart the Caddy container for the change to take effect"