#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Path to the project directory (one level up from the script's directory)
PROJECT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

# Path to the .env file (located in the project directory)
ENV_FILE="$PROJECT_DIR/.env"

# Verify that the .env file exists
if [ ! -f "$ENV_FILE" ]; then
    echo "$(date) - ERROR: .env file not found at $ENV_FILE" >&2
    exit 1
fi

# Source the .env file to import environment variables
source "$ENV_FILE"

# Ensure that DOCKER_UID and DOCKER_GID are set
if [[ -z "$DOCKER_UID" || -z "$DOCKER_GID" ]]; then
    echo "$(date) - ERROR: DOCKER_UID and DOCKER_GID must be set in the .env file." >&2
    exit 1
fi

# Define paths for server and client certificates
SERVER_CERT_DIR="$PROJECT_DIR/certs/server"
CLIENT_CERT_DIR="$PROJECT_DIR/certs/client"

# Create certificate directories if they don't exist
echo "$(date) - Creating certificate directories..."
mkdir -p "$SERVER_CERT_DIR"
mkdir -p "$CLIENT_CERT_DIR"

# Function to secure a directory
secure_directory() {
    local DIR_PATH="$1"
    echo "$(date) - Securing directory: $DIR_PATH"

    # Assign ownership to DOCKER_UID:DOCKER_GID
    chown -R "$DOCKER_UID:$DOCKER_GID" "$DIR_PATH"

    # Set directory permissions to 700 (rwx------)
    chmod 700 "$DIR_PATH"

    # Iterate over files in the directory to set permissions
    for FILE in "$DIR_PATH"/*; do
        if [ -f "$FILE" ]; then
            # If the file is a private key, set permissions to 600
            if [[ "$FILE" == *.key ]]; then
                chmod 600 "$FILE"
                echo "$(date) - Set permissions 600 for private key: $(basename "$FILE")"
            # If the file is a certificate, set permissions to 644
            elif [[ "$FILE" == *.crt ]]; then
                chmod 644 "$FILE"
                echo "$(date) - Set permissions 644 for certificate: $(basename "$FILE")"
            else
                # For any other files, set permissions to 600 as a precaution
                chmod 600 "$FILE"
                echo "$(date) - Set permissions 600 for file: $(basename "$FILE")"
            fi
        fi
    done
}

# Secure the server certificates directory
secure_directory "$SERVER_CERT_DIR"

# Secure the client certificates directory
secure_directory "$CLIENT_CERT_DIR"

# Verification Step: List permissions for server certificates
echo "$(date) - Verifying server certificates permissions:"
ls -ld "$SERVER_CERT_DIR"
ls -l "$SERVER_CERT_DIR"

# Verification Step: List permissions for client certificates
echo "$(date) - Verifying client certificates permissions:"
ls -ld "$CLIENT_CERT_DIR"
ls -l "$CLIENT_CERT_DIR"

echo "$(date) - Certificate directories have been secured successfully."
