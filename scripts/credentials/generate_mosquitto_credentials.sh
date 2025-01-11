#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Path to the project directory (one level up from the script's directory)
PROJECT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../.." && pwd )"

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
CLIENTS_CERT_BASE_DIR="$PROJECT_DIR/certs/clients"

# Define clients
CLIENTS=("zigbee2mqtt" "homeassistant" "pai")

# Create certificate directories if they don't exist
echo "$(date) - Creating certificate directories..."
mkdir -p "$SERVER_CERT_DIR"
for CLIENT in "${CLIENTS[@]}"; do
    mkdir -p "$CLIENTS_CERT_BASE_DIR/$CLIENT"
done

# ==============================
# Certificate Generation Section
# ==============================

# Define server hostname
SERVER_HOSTNAME="mosquitto"

# Define subject information
INFO_CA="/C=AU/ST=Victoria/L=Melbourne/O=homelab/OU=CA/CN=homelab_CA"
INFO_SERVER="/C=AU/ST=Victoria/L=Melbourne/O=homelab/OU=Server/CN=$SERVER_HOSTNAME"

# Function to generate Certificate Authority (CA)
gen_CA () {
    echo "$(date) - Generating CA certificate and key..."
    openssl req -x509 -nodes -sha256 -newkey rsa:2048 \
        -subj "$INFO_CA" \
        -days 3650 \
        -keyout "$SERVER_CERT_DIR/ca.key" \
        -out "$SERVER_CERT_DIR/ca.crt"
    echo "$(date) - CA certificate and key generated successfully."
}

# Function to generate Server Certificate and Key
gen_server () {
    echo "$(date) - Generating server certificate and key for $SERVER_HOSTNAME..."
    openssl req -nodes -sha256 -new \
        -subj "$INFO_SERVER" \
        -keyout "$SERVER_CERT_DIR/server.key" \
        -out "$SERVER_CERT_DIR/server.csr"

    openssl x509 -req -sha256 -in "$SERVER_CERT_DIR/server.csr" \
        -CA "$SERVER_CERT_DIR/ca.crt" -CAkey "$SERVER_CERT_DIR/ca.key" \
        -CAcreateserial -out "$SERVER_CERT_DIR/server.crt" -days 3650

    # Optionally, remove the CSR after signing
    rm "$SERVER_CERT_DIR/server.csr"
    echo "$(date) - Server certificate and key generated successfully."
}

# Function to generate Client Certificate and Key
gen_client () {
    local CLIENT_NAME="$1"
    local CLIENT_DIR="$CLIENTS_CERT_BASE_DIR/$CLIENT_NAME"
    local INFO_CLIENT="/C=AU/ST=SomeState/L=Melbourne/O=homelab/OU=Client/CN=$CLIENT_NAME"

    echo "$(date) - Generating client certificate and key for $CLIENT_NAME..."
    openssl req -new -nodes -sha256 \
        -subj "$INFO_CLIENT" \
        -out "$CLIENT_DIR/client.csr" \
        -keyout "$CLIENT_DIR/client.key"

    openssl x509 -req -sha256 -in "$CLIENT_DIR/client.csr" \
        -CA "$SERVER_CERT_DIR/ca.crt" -CAkey "$SERVER_CERT_DIR/ca.key" \
        -CAcreateserial -out "$CLIENT_DIR/client.crt" -days 3650

    # Optionally, remove the CSR after signing
    rm "$CLIENT_DIR/client.csr"
    echo "$(date) - Client certificate and key for $CLIENT_NAME generated successfully."

    # Copy CA certificate to client directory for verification
    cp "$SERVER_CERT_DIR/ca.crt" "$CLIENT_DIR/"
    echo "$(date) - CA certificate copied to $CLIENT_NAME client directory."
}

# Generate CA, Server, and Client Certificates
gen_CA
gen_server
for CLIENT in "${CLIENTS[@]}"; do
    gen_client "$CLIENT"
done

# ==============================
# Directory Security Section
# ==============================

# Function to secure a directory
secure_directory () {
    local DIR_PATH="$1"
    local PERMS="$2"
    echo "$(date) - Securing directory: $DIR_PATH"

    # Assign ownership to Mosquitto container
    echo "$(date) - Setting permissions for user $PERMS"
    chown -R $PERMS "$DIR_PATH"

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
secure_directory "$SERVER_CERT_DIR" "1883:1883"

# Secure each client certificates directory
for CLIENT in "${CLIENTS[@]}"; do
    secure_directory "$CLIENTS_CERT_BASE_DIR/$CLIENT" "1000:1000"
done

# Verification Step: List permissions for server certificates
echo "$(date) - Verifying server certificates permissions:"
ls -ld "$SERVER_CERT_DIR"
ls -l "$SERVER_CERT_DIR"

# Verification Step: List permissions for client certificates
for CLIENT in "${CLIENTS[@]}"; do
    echo "$(date) - Verifying certificates permissions for $CLIENT:"
    ls -ld "$CLIENTS_CERT_BASE_DIR/$CLIENT"
    ls -l "$CLIENTS_CERT_BASE_DIR/$CLIENT"
done

echo "$(date) - Certificate directories have been secured successfully."
