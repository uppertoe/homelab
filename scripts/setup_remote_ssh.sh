#!/bin/bash

# Variables
REMOTE_USER="pi"           # Change this if using a different user
REMOTE_HOST="<IP of the RPi>"  # Replace with the IP or hostname of the Raspberry Pi
DEFAULT_SSH_PORT=22        # Default SSH port before hardening
HARDENED_SSH_PORT=2222     # New SSH port after hardening
KEY_NAME="id_rsa_pi"       # Name for the new SSH key
CONNECT_SCRIPT="connect.sh"

# Generate an SSH key pair
echo "Generating SSH key pair..."
ssh-keygen -t rsa -b 4096 -f ~/.ssh/$KEY_NAME -N "" -C "Remote SSH key for $REMOTE_HOST"

# Check if the Raspberry Pi is reachable on the default port
echo "Checking connection to $REMOTE_HOST on port $DEFAULT_SSH_PORT..."
if ! ssh -p $DEFAULT_SSH_PORT -o ConnectTimeout=5 $REMOTE_USER@$REMOTE_HOST "exit" &>/dev/null; then
    echo "Unable to connect to $REMOTE_HOST on port $DEFAULT_SSH_PORT. Check the IP, user, or port."
    echo "Ensure the Raspberry Pi is online and reachable."
    exit 1
fi

# Copy the public key to the Raspberry Pi
echo "Copying SSH public key to $REMOTE_USER@$REMOTE_HOST on port $DEFAULT_SSH_PORT..."
echo "You may be prompted for the password of $REMOTE_USER@$REMOTE_HOST."
ssh-copy-id -i ~/.ssh/$KEY_NAME.pub -p $DEFAULT_SSH_PORT $REMOTE_USER@$REMOTE_HOST

# Update local SSH configuration for the default port
echo "Updating SSH configuration for the default port..."
cat <<EOF >> ~/.ssh/config

Host $REMOTE_HOST-default
  HostName $REMOTE_HOST
  User $REMOTE_USER
  Port $DEFAULT_SSH_PORT
  IdentityFile ~/.ssh/$KEY_NAME
EOF

# Run the hardening script on the Raspberry Pi
echo "Running SSH hardening script on $REMOTE_HOST..."
ssh -p $DEFAULT_SSH_PORT $REMOTE_USER@$REMOTE_HOST <<EOF
#!/bin/bash
# Harden SSH Configuration
sudo sed -i 's/#Port 22/Port $HARDENED_SSH_PORT/' /etc/ssh/sshd_config
sudo sed -i 's/#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sudo sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config
sudo systemctl restart ssh
EOF

echo "SSH hardening script completed. SSH now listens on port $HARDENED_SSH_PORT."

# Update local SSH configuration for the hardened port
echo "Updating SSH configuration for the hardened port..."
cat <<EOF >> ~/.ssh/config

Host $REMOTE_HOST
  HostName $REMOTE_HOST
  User $REMOTE_USER
  Port $HARDENED_SSH_PORT
  IdentityFile ~/.ssh/$KEY_NAME
EOF

# Create a connect.sh script
echo "Creating $CONNECT_SCRIPT..."
cat <<EOF > $CONNECT_SCRIPT
#!/bin/bash
ssh $REMOTE_HOST
EOF

# Make the connect script executable
chmod +x $CONNECT_SCRIPT

# Test SSH login on the hardened port
echo "Testing SSH login on port $HARDENED_SSH_PORT..."
if ssh $REMOTE_HOST "exit"; then
    echo "SSH key successfully configured for $REMOTE_HOST."
    echo "Use './$CONNECT_SCRIPT' to connect to your Raspberry Pi."
else
    echo "SSH login test failed. Check your configuration."
    exit 1
fi
