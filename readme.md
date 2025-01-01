# Raspbian
### Install Raspbian OS
Follow the instructions on the [Raspberry Pi website](https://www.raspberrypi.com/documentation/computers/getting-started.html#raspberry-pi-imager) to add the latest Raspbian OS to a micro SD card

### Set up SSH keys
Run the `scripts/setup_remote_ssh.sh` script on the remote computer
- Remember to set the RPi's IP and username in the script before running

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
sh scripts/setup_environment.sh
```

Note that SSH login with password authentication will no longer be possible

### Set environment variables
```
mv .env.example .env
nano .env
```

### Run the deploy script
Use this to set a password for the web interface of each proxied service

```
chmod +x deploy.sh
deploy.sh
```

Use ctrl + o to save and ctrl + x to exit nano

# Updating containers
This pulls the latest Pihole, Nginx and Home Assistant containers:

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