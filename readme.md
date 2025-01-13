# Raspbian
### Install Raspbian OS
Follow the instructions on the [Raspberry Pi website](https://www.raspberrypi.com/documentation/computers/getting-started.html#raspberry-pi-imager) to add the latest Raspbian OS to a micro SD card

### Set up SSH keys
Run the `scripts/setup_remote_ssh.sh` script on the remote computer
- Use ctrl + o to save and ctrl + x to exit nano

```
# Get the file from this repository
curl -o setup_remote_ssh.sh https://raw.githubusercontent.com/uppertoe/homelab/refs/heads/main/scripts/setup_remote_ssh.sh

# Set the RPi's IP and username as variables in the script
nano scripts/setup_remote_ssh.sh

# Run the script to create connection credentials
bash scripts/setup_remote_ssh.sh
```

Use the resulting connect.sh to SSH in to the RPi

### Clone this repository
```
git clone https://github.com/uppertoe/homelab.git
```

### Change to the Homelab directory
```
cd homelab
```

### Harden the RPi's security settings and install Docker
Run 
```
bash scripts/setup_environment.sh
```

Note that SSH login with password authentication will no longer be possible

### Set environment variables
```
mv .env.example .env
nano .env
```
- Use ctrl + o to save and ctrl + x to exit nano

### Run the deploy script
Use this to set a password for the web interface of each proxied service

```
bash deploy.sh
```

# Updating containers
This pulls the latest container images for each compose file:

```
docker compose pull
```

# Setting up DNS
### Get a static IP from your ISP
If this is not possible, consider using [Duck DNS](https://www.duckdns.org/)

### Create an A record pointing to the IP
Simply send the wildcard apex domain * to the static IP; the reverse proxy will handle the subdomains.

### Forward ports on your router
| Service | External Port | Internal IP | Internal Port | Protocol |
|---------|---------------|-------------|---------------|----------|
| HTTP | 80 | 192.168.4.48 | 80 | TCP |
| HTTPS | 443 | 192.168.4.48 | 443 | TCP |
| Wireguard VPN | 51820 | 192.168.4.48 | 51820 | UDP |

# Specific services

### Wireguard-Easy
The client VPN can be configured to forward only DNS requests:
- Set *Allowed IPs* to the Pihole static IP (eg 10.2.1.200/32)

### Homeassistant
To enable device discoverability while retaining Docker's 'bridge' neworking mode:
- Set 'advanced mode' in profile -> user settings
- Set the network adapters to use in settings -> system -> network

### Mosquitto
The current configuration is stored in config/mosquitto.conf.

To set up the self-signed certificates for TLS:
1. Generate the certificates
    ```
    scripts/credentials/generate_mosquitto_credentials.sh
    ```
2. Go to the Homeassistant web interface
3. Ensure that advanced mode is enabled in Homeassistant
4. Add the MQTT integration with the following information:

    | **Input**                          | **Value**    |
    |------------------------------------|--------------|
    | Broker                             | localhost    |
    | Port                               | 8883         |
    | Use a client certificate           | Yes          |
    | Upload Client Certificate File     | `client.crt` |
    | Upload Private Key File            | `client.key` |
    | Broker Certificate Validation      | Custom       |
    | Upload Custom CA Certificate File  | `ca.crt`     |

The certificates can be found at ~/homelab/certs

Note: Homeassistant running in bridge networking mode will need to connect to <server_ip>:8883 rather than mosquitto:8883
- Choose ignore broker's certificate validation as the hostname will not match

5. Create a password (for clients which cannot use a client certificate)
- Get an interactive shell in the mosquitto container:
    ```
    docker compose exec -it mosquitto sh
    ```
- Use the [mosquitto_passwd](https://mosquitto.org/documentation/authentication-methods/) utility to create a password:
    ```
    mosquitto_passwd -c /etc/mosquitto/auth/password_file <username>
    ```

### Backrest

Using [Backblaze](https://www.backblaze.com) cloud storage:
- Use the following schema for the bucket URL: s3:https://<BUCKET_URL>/<BUCKET_NAME>

## Network backups
Use [Syncthing](https://syncthing.net/) to clone a folder to to server.

Suggest using a mounted drive at eg /mnt/homelab with a subdirectory for the share.

This can be added as a volume to the Syncthing container.

The /mnt/share folder can then be backed up using Restic (i.e. using [Backrest](https://github.com/garethgeorge/backrest))

Notes:
- Syncthing may perform better if clients can specify the server IP address, rather than relying on discovery