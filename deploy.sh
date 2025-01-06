#!/bin/bash

# -----------------------------------------------------------------------------
# Script Name: deploy.sh
# Description: Automates the deployment process by setting up dependencies,
#              configuring scripts, initializing secrets, and scheduling cron jobs.
# -----------------------------------------------------------------------------

# Exit immediately if a command exits with a non-zero status
set -e

# Check if .env exists
if [ ! -f .env ]; then
    echo "Error: .env file not found!"
    exit 1
fi

# Variables
SCRIPT_DIR="./scripts"

# Function to display messages
log() {
    echo -e "\e[32m[INFO]\e[0m $1"
}

# Function to display error messages and exit
error_exit() {
    echo -e "\e[31m[ERROR]\e[0m $1"
    exit 1
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to install dependencies (if not installed)
install_dependencies() {
    if ! command_exists htpasswd; then
        log "htpasswd not found. Installing..."
        # Detect OS and install accordingly
        if [[ "$OSTYPE" == "linux-gnu"* ]]; then
            if command_exists apt-get; then
                sudo apt-get update
                sudo apt-get install -y apache2-utils
            elif command_exists yum; then
                sudo yum install -y httpd-tools
            else
                error_exit "Unsupported Linux package manager. Please install 'htpasswd' manually."
            fi
        elif [[ "$OSTYPE" == "darwin"* ]]; then
            if command_exists brew; then
                brew install httpd
            else
                error_exit "Homebrew not found. Please install it or install 'htpasswd' manually."
            fi
        else
            error_exit "Unsupported OS. Please install 'htpasswd' manually."
        fi
        log "htpasswd installed successfully."
    else
        log "htpasswd is already installed."
    fi

    if ! command_exists openssl; then
        log "openssl not found. Installing..."
        # Detect OS and install accordingly
        if [[ "$OSTYPE" == "linux-gnu"* ]]; then
            if command_exists apt-get; then
                sudo apt-get update
                sudo apt-get install -y openssl
            elif command_exists yum; then
                sudo yum install -y openssl
            else
                error_exit "Unsupported Linux package manager. Please install 'openssl' manually."
            fi
        elif [[ "$OSTYPE" == "darwin"* ]]; then
            if command_exists brew; then
                brew install openssl
            else
                error_exit "Homebrew not found. Please install it or install 'openssl' manually."
            fi
        else
            error_exit "Unsupported OS. Please install 'openssl' manually."
        fi
        log "openssl installed successfully."
    else
        log "openssl is already installed."
    fi
}

run_scripts() {
    # Set the secret cookie that Caddy uses for auth
    ./credentials/update_proxy_cookie_id.sh

    # Ensure rotation of the Caddy secret
    ./setup_cron_caddy.sh

    # Set up monitoring of the deploy trigger
    ./setup_webhook.sh

    # Set up permissions
    ./set_permissions.sh

    # Set avahi settings (for Homeassistant device discovery)
    sudo bash set_avahi_settings.sh

    # Requires user input for username and password
    ./credentials/update_proxy_credentials.sh
}

# Function to prompt the user
prompt_external_drive_setup() {
    while true; do
        read -rp "Do you want to set up an external drive for homelab? (y/n): " yn
        case $yn in
            [Yy]* )
                log "Setting up external drive..."
                # Check if the setup script exists
                if [ -f "./scripts/setup_external_drive.sh" ]; then
                    # Execute the setup script
                    ./scripts/setup_external_drive.sh
                    log "External drive setup completed successfully."
                else
                    log "ERROR: ./scripts/setup_external_drive.sh not found or not executable." >&2
                    exit 1
                fi
                break
                ;;
            [Nn]* )
                log "Skipping external drive setup."
                break
                ;;
            * )
                log "Please answer yes (y) or no (n)."
                ;;
        esac
    done
}

# Main Deployment Function
main() {
    log "Starting deployment process..."

    # Step 1: Check and install dependencies
    install_dependencies

    # Step 2: Run deployment scripts
    cd $SCRIPT_DIR
    run_scripts

    log "Deployment completed successfully."

    log ""
    log "Would you like to set up an external drive for your homelab?"
    # Call the function to prompt the user
    prompt_external_drive_setup
}

main