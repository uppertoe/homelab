#!/bin/bash

# Exit if any command fails
set -e

# Variables
SSH_PORT=2222  # Ensure this matches your existing SSH configuration

echo "Securing and updating the system..."

# Update and install necessary packages
echo "Updating system and installing required packages..."
sudo apt update && sudo apt full-upgrade -y
sudo apt install ufw fail2ban unattended-upgrades -y

# Enable and configure unattended upgrades
echo "Configuring unattended updates..."
sudo dpkg-reconfigure --priority=low unattended-upgrades

echo "Enabling and configuring unattended upgrades..."
sudo tee /etc/apt/apt.conf.d/50unattended-upgrades > /dev/null <<EOF
Unattended-Upgrade::Allowed-Origins {
    "\${distro_id}:\${distro_codename}-security";
    "\${distro_id}:\${distro_codename}-updates";
};
Unattended-Upgrade::Automatic-Reboot "true";
EOF

sudo tee /etc/apt/apt.conf.d/20auto-upgrades > /dev/null <<EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF

# Verify unattended-upgrades
echo "Verifying unattended-upgrades configuration..."
sudo systemctl status unattended-upgrades | grep "active (running)" || echo "Unattended-upgrades did not start correctly!"

# Set up UFW firewall
echo "Configuring UFW..."

# Set the default policies: deny incoming, allow outgoing
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow SSH (ensure your SSH_PORT variable is correctly set, default: 22)
sudo ufw allow "$SSH_PORT"/tcp

# Allow HTTP and HTTPS for web traffic
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# Allow WireGuard VPN traffic
sudo ufw allow 51820/udp  # WireGuard VPN

# Allow mDNS for local device discovery
sudo ufw allow from 192.168.4.0/24 to any port 5353 proto udp

# Allow MQTT
sudo ufw allow 1883/tcp

# Modify /etc/ufw/before.rules to allow IGMP and multicast traffic
# This is necessary because UFW does not handle some protocols like IGMP by default.

# Check if IGMP and multicast rules are already present to avoid duplication
if ! sudo grep -q "# Allow IGMP and Multicast traffic" /etc/ufw/before.rules; then
    sudo bash -c 'cat <<EOF >> /etc/ufw/before.rules

# Allow IGMP and Multicast traffic
# Allow IGMP
-A ufw-before-input -p igmp -j ACCEPT
-A ufw-before-output -p igmp -j ACCEPT

# Allow multicast traffic (224.0.0.0/4)
-A ufw-before-input -d 224.0.0.0/4 -j ACCEPT
-A ufw-before-output -d 224.0.0.0/4 -j ACCEPT
EOF'
    echo "Added IGMP and multicast rules to /etc/ufw/before.rules"
else
    echo "IGMP and multicast rules already exist in /etc/ufw/before.rules"
fi

# Ensure Docker can function with UFW by setting DEFAULT_FORWARD_POLICY to ACCEPT
# This allows forwarding of traffic, which is necessary for Docker containers.
# Only set if not already set.

if ! sudo grep -q "^DEFAULT_FORWARD_POLICY=\"ACCEPT\"" /etc/default/ufw; then
    sudo sed -i 's/^DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw
    echo "Set DEFAULT_FORWARD_POLICY to ACCEPT in /etc/default/ufw"
else
    echo "DEFAULT_FORWARD_POLICY is already set to ACCEPT in /etc/default/ufw"
fi

# Enable UFW with the new rules
sudo ufw enable

echo "UFW firewall has been configured successfully."

# Install and configure Fail2Ban
echo "Configuring Fail2Ban..."
sudo apt install fail2ban -y

# Create custom Fail2Ban jail configuration
cat <<EOF | sudo tee /etc/fail2ban/jail.local
[DEFAULT]
bantime = 10m
findtime = 10m
maxretry = 5

[sshd]
enabled = true
port = $SSH_PORT
EOF

# Restart Fail2Ban service
sudo systemctl restart fail2ban

# Verify Fail2Ban status
echo "Verifying Fail2Ban service..."
sudo systemctl status fail2ban | grep "active (running)" || echo "Fail2Ban did not start correctly!"

echo "System updates applied successfully!"
echo "Firewall and Fail2Ban protections are in place!"
echo "Unattended updates have been configured and enabled!"

# Install Docker
echo "Installing Docker and Docker Compose"
curl -sSL https://get.docker.com | sh

echo "Setting the Docker user"
sudo usermod -aG docker $USER

# Set up VM overcommit memory for Redis
echo "vm.overcommit_memory = 1" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# Install Log2Ram
echo "Installing Log2Ram"
echo "deb [signed-by=/usr/share/keyrings/azlux-archive-keyring.gpg] http://packages.azlux.fr/debian/ bookworm main" | sudo tee /etc/apt/sources.list.d/azlux.list
sudo wget -O /usr/share/keyrings/azlux-archive-keyring.gpg  https://azlux.fr/repo.gpg
sudo apt update
sudo apt install log2ram

# Set the system logs to less than the RAM volume
JOURNAL_CONF="/etc/systemd/journald.conf"
SETTING="SystemMaxUse=20M"

# Use sed to uncomment and set the SystemMaxUse parameter if it exists,
# or append it if it doesn't.
if grep -qE "^\s*#?\s*SystemMaxUse=" "$JOURNAL_CONF"; then
    sudo sed -i -E "s/^\s*#?\s*SystemMaxUse=.*/$SETTING/" "$JOURNAL_CONF"
    echo "Updated existing SystemMaxUse setting to $SETTING"
else
    echo "$SETTING" | sudo tee -a "$JOURNAL_CONF" > /dev/null
    echo "Appended SystemMaxUse setting: $SETTING"
fi

# Install inotify-tools for webhooks
sudo apt install inotify-tools -y

# Restart the systemd-journald service to apply changes
sudo systemctl restart systemd-journald
echo "systemd-journald service restarted to apply changes."

# Enable memory reporting from Docker
sudo sed -i 's/$/ cgroup_enable=cpuset cgroup_enable=memory cgroup_memory=1/' /boot/firmware/cmdline.txt

echo "Rebooting now!"
sudo reboot
