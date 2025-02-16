#!/bin/bash

# -------------------------------
# VARIABLES
# -------------------------------
REMOTE_USER="pi"                    # Change this if using a different user
REMOTE_HOST="<IP of the RPi>"       # Replace with the IP or hostname of the Raspberry Pi
DEFAULT_SSH_PORT=22                 # Default SSH port before hardening
HARDENED_SSH_PORT=2222              # New SSH port after hardening
KEY_NAME="id_rsa_pi"                # Name for the new SSH key
CONNECT_SCRIPT="connect.sh"

# -------------------------------
# 1. GENERATE SSH KEY
# -------------------------------
echo "Generating SSH key pair..."
ssh-keygen -t rsa -b 4096 -f ~/.ssh/$KEY_NAME -N "" -C "Remote SSH key for $REMOTE_HOST"

# -------------------------------
# 2. CHECK PI REACHABILITY ON DEFAULT PORT
# -------------------------------
echo "Checking connection to $REMOTE_HOST on port $DEFAULT_SSH_PORT..."
if ! ssh -p "$DEFAULT_SSH_PORT" -o ConnectTimeout=5 "$REMOTE_USER@$REMOTE_HOST" "exit" &>/dev/null; then
    echo "ERROR: Unable to connect to $REMOTE_HOST on port $DEFAULT_SSH_PORT."
    echo "Check the IP, user, or port. Ensure the Raspberry Pi is online."
    exit 1
fi

# -------------------------------
# 3. COPY PUBLIC KEY TO THE PI
# -------------------------------
echo "Copying SSH public key to $REMOTE_USER@$REMOTE_HOST on port $DEFAULT_SSH_PORT..."
echo "You may be prompted for the password of $REMOTE_USER@$REMOTE_HOST."
ssh-copy-id -i ~/.ssh/$KEY_NAME.pub -p "$DEFAULT_SSH_PORT" "$REMOTE_USER@$REMOTE_HOST"

# -------------------------------
# 4. ADD A 'DEFAULT' HOST BLOCK TO ~/.ssh/config
# -------------------------------
echo "Updating SSH configuration for the default port..."
cat <<EOF >> ~/.ssh/config

Host $REMOTE_HOST-default
  HostName $REMOTE_HOST
  User $REMOTE_USER
  Port $DEFAULT_SSH_PORT
  IdentityFile ~/.ssh/$KEY_NAME
EOF

# -------------------------------
# 5. RUN REMOTE HARDENING SCRIPT
# -------------------------------
echo "Running SSH hardening script on $REMOTE_HOST..."
ssh -p "$DEFAULT_SSH_PORT" "$REMOTE_USER@$REMOTE_HOST" <<EOF
#!/bin/bash

# Using robust sed patterns to handle lines whether commented or not:
sudo sed -i -E "s/^(#?Port).*/Port $HARDENED_SSH_PORT/" /etc/ssh/sshd_config

# Disable root login entirely:
sudo sed -i -E "s/^(#?PermitRootLogin).*/PermitRootLogin no/" /etc/ssh/sshd_config

# Disable password login (only if sure your key works):
sudo sed -i -E "s/^(#?PasswordAuthentication).*/PasswordAuthentication no/" /etc/ssh/sshd_config

# Ensure public key authentication is enabled:
sudo sed -i -E "s/^(#?PubkeyAuthentication).*/PubkeyAuthentication yes/" /etc/ssh/sshd_config

sudo systemctl restart ssh
EOF

echo "SSH hardening script completed. SSH now listens on port $HARDENED_SSH_PORT (assuming the edits succeeded)."

# -------------------------------
# 6. ADD THE 'HARDENED' HOST BLOCK TO ~/.ssh/config
# -------------------------------
echo "Updating SSH configuration for the hardened port..."
cat <<EOF >> ~/.ssh/config

Host $REMOTE_HOST
  HostName $REMOTE_HOST
  User $REMOTE_USER
  Port $HARDENED_SSH_PORT
  IdentityFile ~/.ssh/$KEY_NAME
EOF

# -------------------------------
# 7. CREATE A connect.sh SCRIPT
# -------------------------------
echo "Creating $CONNECT_SCRIPT..."
cat <<EOF > "$CONNECT_SCRIPT"
#!/bin/bash
ssh $REMOTE_HOST
EOF
chmod +x "$CONNECT_SCRIPT"

# -------------------------------
# 8. TEST SSH LOGIN ON NEW PORT
# -------------------------------
echo "Testing SSH login on port $HARDENED_SSH_PORT..."
if ssh -o ConnectTimeout=5 "$REMOTE_HOST" "exit"; then
    echo "SUCCESS: SSH key works for $REMOTE_HOST on port $HARDENED_SSH_PORT."
    echo "Use './$CONNECT_SCRIPT' to connect to your Raspberry Pi."
else
    echo "ERROR: SSH login test failed on port $HARDENED_SSH_PORT. Check your configuration."
    exit 1
fi
