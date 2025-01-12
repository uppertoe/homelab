#!/usr/bin/env bash
#
# samba_share_setup.sh
# A script to configure a Samba share on an already-mounted drive/subdirectory.

set -e  # Exit on error

#######################################
#          CONFIGURABLES
#######################################

# Windows-friendly name for your share as it appears in Finder or on the network
DEFAULT_SHARE_NAME="PiSSDShare"

# Samba config file
SMB_CONF="/etc/samba/smb.conf"

#######################################
#         HELPER FUNCTIONS
#######################################

require_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "Please run this script with sudo or as root."
    exit 1
  fi
}

print_header() {
  echo "=============================================="
  echo "        Setup a Samba Share on Raspberry Pi"
  echo "=============================================="
}

list_mounted_drives() {
  echo "Currently mounted volumes (excluding root/boot):"
  # -n = no headings, -o = columns, -r = raw
  # We only want lines with an actual mountpoint (column 2).
  # Exclude /boot, exclude /.
  lsblk -rn -o NAME,MOUNTPOINT \
    | grep -v " /boot" \
    | grep -v " /$" \
    | awk '$2 {print $2}' \
    | sort -u
}

prompt_for_mounted_drive() {
  mapfile -t MOUNTPOINTS < <(
    lsblk -rn -o NAME,MOUNTPOINT \
      | grep -v " /boot" \
      | grep -v " /$" \
      | awk '$2 {print $2}' \
      | sort -u
  )

  if [ ${#MOUNTPOINTS[@]} -eq 0 ]; then
    echo "No external drives or partitions appear to be mounted (other than system volumes)."
    echo "Please mount an external drive and re-run this script."
    exit 1
  fi

  echo ""
  echo "Select which mounted directory you want to share via Samba:"
  PS3="Enter your choice (number): "
  select MP_CHOICE in "${MOUNTPOINTS[@]}" "Quit"; do
    case "$REPLY" in
      [0-9]*)
        if [ "$REPLY" -le "${#MOUNTPOINTS[@]}" ]; then
          if [ "$MP_CHOICE" == "Quit" ]; then
            echo "Exiting..."
            exit 0
          fi
          BASE_MOUNTPOINT="$MP_CHOICE"
          break
        else
          echo "Invalid option."
        fi
        ;;
      "Quit")
        echo "Exiting..."
        exit 0
        ;;
      *)
        echo "Invalid option."
        ;;
    esac
  done

  echo "You selected: $BASE_MOUNTPOINT"
}

prompt_for_subdirectory() {
  echo ""
  echo "Enter the subdirectory (relative or absolute) to share from '$BASE_MOUNTPOINT'."
  echo "E.g., 'myshare' => $BASE_MOUNTPOINT/myshare, or an absolute path like /mnt/extern1/config."
  read -r SUBDIR_INPUT

  if [[ "$SUBDIR_INPUT" = /* ]]; then
    FULL_SUBDIR="$SUBDIR_INPUT"
  else
    FULL_SUBDIR="$BASE_MOUNTPOINT/$SUBDIR_INPUT"
  fi

  # Create directory if it doesn't exist
  if [ ! -d "$FULL_SUBDIR" ]; then
    echo "Directory '$FULL_SUBDIR' does not exist. Creating..."
    mkdir -p "$FULL_SUBDIR"
  fi
}

prompt_for_share_name() {
  echo ""
  read -p "Enter a Windows-friendly share name (press Enter to use '$DEFAULT_SHARE_NAME'): " CUSTOM_SHARE_NAME
  if [ -z "$CUSTOM_SHARE_NAME" ]; then
    SHARE_NAME="$DEFAULT_SHARE_NAME"
  else
    SHARE_NAME="$CUSTOM_SHARE_NAME"
  fi
}

install_samba() {
  if ! dpkg -l | grep -q samba; then
    echo "Installing Samba..."
    apt update
    apt install -y samba
  fi
}

configure_samba_share() {
  # We'll add a new share definition to smb.conf
  # If there's already a share with the same name, we skip or override.
  echo ""
  echo "Configuring Samba share for directory: $FULL_SUBDIR"
  echo "Share name: $SHARE_NAME"

  # Make a backup of the smb.conf if not already done
  if [ ! -f "$SMB_CONF.bak" ]; then
    cp "$SMB_CONF" "$SMB_CONF.bak"
  fi

  # Check if share name already exists in config
  if grep -q "^\[$SHARE_NAME\]" "$SMB_CONF"; then
    echo "A share named [$SHARE_NAME] already exists in $SMB_CONF. Overwriting its config..."
    # We can remove or comment out the old section. This is just a quick approach:
    sed -i "/^\[$SHARE_NAME\]/,/^\[.*\]/ {s/^/#/}" "$SMB_CONF"
  fi

  # Append new share definition
  cat <<EOT >> "$SMB_CONF"

[$SHARE_NAME]
  path = $FULL_SUBDIR
  browseable = yes
  writable = yes
  guest ok = no
  valid users = @sambashare
EOT

  # Ensure the directory is owned by a group that Samba users are in.
  # By default, let's use `sambashare` group.
  chown -R root:sambashare "$FULL_SUBDIR"
  chmod -R 2770 "$FULL_SUBDIR"  # Group can read/write; the setgid bit ensures files keep the group.
}

create_samba_user() {
  echo ""
  echo "Samba requires a user account to authenticate. You can either:"
  echo "  1) Use an existing Linux user, enabling Samba for them."
  echo "  2) Create a new Linux user exclusively for Samba."
  echo ""
  read -p "Enter the username you want to use for Samba (e.g., 'pi' or 'myuser'): " SMBUSER

  # Check if the user already exists in Linux
  if id "$SMBUSER" &>/dev/null; then
    echo "User '$SMBUSER' already exists on this system."
  else
    echo "Creating new Linux user '$SMBUSER'..."
    useradd -m -G sambashare -s /usr/sbin/nologin "$SMBUSER"
  fi

  # Ensure this user is in the `sambashare` group
  usermod -aG sambashare "$SMBUSER"

  # Now set a Samba password for this user
  echo "Setting a Samba password for user '$SMBUSER'..."
  smbpasswd -a "$SMBUSER"
}

restart_samba() {
  systemctl restart smbd
  systemctl enable smbd
  echo ""
  echo "Samba has been restarted and enabled on boot."
}

#######################################
#           SCRIPT EXECUTION
#######################################

require_root
print_header

echo "Currently mounted volumes (excluding root/boot):"
list_mounted_drives

prompt_for_mounted_drive
prompt_for_subdirectory
prompt_for_share_name

install_samba
configure_samba_share
create_samba_user
restart_samba

echo ""
echo "=========================================="
echo "          SAMBA SHARE SETUP COMPLETE"
echo "=========================================="
echo "Share Name:       [$SHARE_NAME]"
echo "Shared Directory: $FULL_SUBDIR"
echo ""
echo "Use the credentials of user '$SMBUSER' to connect."
echo ""
echo "On macOS, open Finder -> Go -> Connect to Server:"
echo "  smb://<RASPBERRY_PI_IP>/$SHARE_NAME"
echo "Enter the username '$SMBUSER' and the Samba password you set."
echo ""
echo "Enjoy your Samba share!"
