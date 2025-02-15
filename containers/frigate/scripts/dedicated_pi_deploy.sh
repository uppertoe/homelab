#!/usr/bin/env bash
set -e

##
# full_deploy.sh
#
# Usage:
#   ./full_deploy.sh <PI_HOST_OR_IP> <PI_PASSWORD> <NEW_SSH_PORT> <NEW_HOSTNAME> <REMOTE_USER>
#
# Example:
#   ./full_deploy.sh raspberrypi.local raspberry 2222 my-hass-pi pi
#
# Steps:
#   1. Generate SSH key locally (if it doesn't exist).
#   2. Copy that key to the Pi (via sshpass using the Pi's old password).
#   3. SSH in (via default port 22 + key), configure SSH (change port, disable password auth, etc.).
#   4. SSH in again (new port), configure firewall, Docker, swap, fail2ban, etc.
#   5. Enable cgroup parameters in /boot/cmdline.txt for proper Docker CPU/memory reporting.
#   6. Reboot the Pi to apply new cgroup parameters.
##

# Check arguments
if [ "$#" -ne 5 ]; then
  echo "Usage: $0 <PI_HOST_OR_IP> <PI_PASSWORD> <NEW_SSH_PORT> <NEW_HOSTNAME> <REMOTE_USER>"
  echo "Example: $0 raspberrypi.local raspberry 2222 my-hass-pi pi"
  exit 1
fi

PI_HOST="$1"
PI_PASSWORD="$2"
NEW_SSH_PORT="$3"
NEW_HOSTNAME="$4"
REMOTE_USER="$5"

# Path to your local SSH key
SSH_KEY_PATH="$HOME/.ssh/my_rpi_key"

echo "====================================================="
echo "  Raspberry Pi Full Deployment Script"
echo "====================================================="
echo "PI Host/IP:      $PI_HOST"
echo "Pi Password:     (hidden)"
echo "New SSH Port:    $NEW_SSH_PORT"
echo "New Hostname:    $NEW_HOSTNAME"
echo "Remote Username: $REMOTE_USER"
echo "SSH Key Path:    $SSH_KEY_PATH"
echo "====================================================="
echo

# Make sure we have sshpass installed locally
if ! command -v sshpass &> /dev/null; then
  echo "ERROR: sshpass is not installed on your local machine."
  echo "       Please install it (e.g., sudo apt-get install sshpass) and re-run."
  exit 1
fi

# ------------------------------------------------------------------------------
# 1. Generate an SSH key if not already present
# ------------------------------------------------------------------------------
if [ ! -f "$SSH_KEY_PATH" ]; then
  echo "[1/6] Generating a new SSH key ($SSH_KEY_PATH) ..."
  ssh-keygen -t ed25519 -f "$SSH_KEY_PATH" -N "" -C "my_rpi_key"
  echo "SSH key generated."
else
  echo "[1/6] SSH key already exists at $SSH_KEY_PATH. Skipping key generation."
fi

# ------------------------------------------------------------------------------
# 2. Copy the public key to the Pi using sshpass
# ------------------------------------------------------------------------------
echo "[2/6] Copying SSH key to the Pi using sshpass..."
sshpass -p "$PI_PASSWORD" ssh-copy-id -i "$SSH_KEY_PATH.pub" -p 22 "$REMOTE_USER@$PI_HOST"
echo "Key copied successfully."

# ------------------------------------------------------------------------------
# 3. First SSH connection (port 22) to configure SSH on the Pi
#    (change port, disable password auth, etc.)
# ------------------------------------------------------------------------------
echo "[3/6] Running first config script on the Pi (still using port 22)..."
ssh -i "$SSH_KEY_PATH" -p 22 "$REMOTE_USER@$PI_HOST" bash <<EOF
  set -e

  # 1. Set the new hostname
  echo "Setting new hostname to: $NEW_HOSTNAME"
  sudo raspi-config nonint do_hostname "$NEW_HOSTNAME"

  # 2. Update & upgrade packages
  echo "Updating packages..."
  sudo apt-get update
  sudo apt-get upgrade -y

  # 3. Install essential packages (ufw, fail2ban, unattended-upgrades)
  echo "Installing ufw, fail2ban, and unattended-upgrades..."
  sudo apt-get install -y ufw fail2ban unattended-upgrades
  sudo systemctl enable unattended-upgrades

  # 4. Reconfigure SSH daemon
  echo "Configuring SSH to use port $NEW_SSH_PORT, disable password auth..."
  sudo sed -i "s/#Port 22/Port $NEW_SSH_PORT/g" /etc/ssh/sshd_config
  sudo sed -i "s/^.*PasswordAuthentication yes/PasswordAuthentication no/g" /etc/ssh/sshd_config
  sudo sed -i "s/^.*PermitRootLogin .*/PermitRootLogin no/g" /etc/ssh/sshd_config
  # If there's a commented line for PasswordAuthentication, ensure it's no:
  sudo sed -i "s/#PasswordAuthentication yes/PasswordAuthentication no/g" /etc/ssh/sshd_config

  sudo systemctl restart ssh
EOF

echo "[3.1] SSH daemon reconfigured. We'll now connect on port $NEW_SSH_PORT."

# ------------------------------------------------------------------------------
# 4. Second SSH connection (new port) to do the rest (firewall, Docker, swap, etc.)
# ------------------------------------------------------------------------------
echo "[4/6] Running second config script on the Pi (port $NEW_SSH_PORT)..."

ssh -i "$SSH_KEY_PATH" -p "$NEW_SSH_PORT" "$REMOTE_USER@$PI_HOST" bash <<EOF
  set -e

  # 1. Configure firewall (ufw)
  echo "Configuring firewall..."
  sudo ufw --force reset
  sudo ufw default deny incoming
  sudo ufw default allow outgoing

  # Allow new SSH port
  sudo ufw allow "$NEW_SSH_PORT"/tcp

  # Allow Home Assistant typical port
  sudo ufw allow 8123/tcp

  # Allow Frigate typical ports
  sudo ufw allow 5000/tcp
  sudo ufw allow 1935/tcp
  sudo ufw allow 8554/tcp
  sudo ufw allow 8555/tcp

  sudo ufw --force enable

  # 2. Install Docker
  echo "Installing Docker..."
  curl -fsSL https://get.docker.com -o get-docker.sh
  sh get-docker.sh
  sudo usermod -aG docker $REMOTE_USER

  # 3. Increase swap to 2GB
  echo "Increasing swap space to 2GB..."
  sudo dphys-swapfile swapoff || true
  sudo sed -i "s/^CONF_SWAPSIZE=.*/CONF_SWAPSIZE=2048/" /etc/dphys-swapfile
  sudo dphys-swapfile setup
  sudo dphys-swapfile swapon

  # 4. Configure fail2ban for SSH
  echo "Configuring fail2ban for SSH..."
  sudo bash -c 'cat > /etc/fail2ban/jail.d/ssh.conf' <<EOT
[sshd]
enabled = true
port = $NEW_SSH_PORT
logpath = /var/log/auth.log
maxretry = 3
bantime = 1h
EOT
  sudo systemctl restart fail2ban

  echo "Second config script completed."
EOF

echo "[4/6] Configuration done (firewall, Docker, swap, fail2ban)."

# ------------------------------------------------------------------------------
# 5. Enable cgroups for accurate Docker resource reporting
#    (cgroup_enable=cpuset cgroup_enable=memory cgroup_memory=1)
# ------------------------------------------------------------------------------
echo "[5/6] Ensuring cgroups are enabled in /boot/cmdline.txt for Docker..."

# We'll do this with a single SSH command that checks if the string is present; if not, we append it.
SSH_APPEND_CMD="if ! grep -q 'cgroup_enable=cpuset' /boot/cmdline.txt; then \
  sudo sed -i 's|\$| cgroup_enable=cpuset cgroup_enable=memory cgroup_memory=1|' /boot/cmdline.txt; \
  echo \"Appended cgroup parameters to /boot/cmdline.txt\"; \
else \
  echo \"cgroup parameters already in /boot/cmdline.txt\"; \
fi"

ssh -i "$SSH_KEY_PATH" -p "$NEW_SSH_PORT" "$REMOTE_USER@$PI_HOST" "$SSH_APPEND_CMD"

echo "[5/6] cgroup parameters are now set (or already existed)."

# ------------------------------------------------------------------------------
# 6. Reboot so the new cgroup settings take effect
#    (Docker CPU usage won't be accurate until after reboot)
# ------------------------------------------------------------------------------
echo "[6/6] Rebooting the Pi to apply new kernel cgroup parameters..."
ssh -i "$SSH_KEY_PATH" -p "$NEW_SSH_PORT" "$REMOTE_USER@$PI_HOST" sudo reboot

# Once we reboot, the script can’t continue to run commands on the Pi, so we’re done.
echo "==========================================================="
echo " Deployment complete! The Pi is now rebooting."
echo " After reboot, reconnect using your new settings:"
echo "   ssh -i $SSH_KEY_PATH -p $NEW_SSH_PORT $REMOTE_USER@$NEW_HOSTNAME.local"
echo " or by IP (if DNS is not set up for '.local'):"
echo "   ssh -i $SSH_KEY_PATH -p $NEW_SSH_PORT $REMOTE_USER@${PI_HOST}"
echo "==========================================================="
