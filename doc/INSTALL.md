# Installation Guide

This guide covers installing the YTuner fork on a Raspberry Pi or Debian-based system.

## Prerequisites

- Raspberry Pi (any model) or Debian/Ubuntu server
- Raspberry Pi OS or Debian 11+ (Bullseye or newer)
- Network connection (wired recommended)
- Static IP address assigned to the server

## Quick Install

```bash
git clone https://github.com/Jarvichi/YTuner.git
cd YTuner
git checkout custom
sudo bash script/install.sh
```

The installer will prompt you to confirm the server IP and service user, then handle everything else automatically.

## What the Installer Does

1. **Detects architecture** — aarch64, armhf, or x86_64
2. **Installs packages** — nginx, ffmpeg, sqlite3, python3, and utilities
3. **Downloads YTuner v1.2.6** — official binary from upstream releases
4. **Copies fork files** — web UI, transcoding proxy, helper scripts, configs
5. **Configures ytuner.ini** — sets port 18081, disables built-in DNS, enables per-device bookmarks
6. **Patches IP addresses** — replaces hardcoded IPs in webui.py and scripts with your server IP
7. **Sets up nginx** — reverse proxy on port 80 that forwards `Host: $remote_addr` to YTuner
8. **Installs systemd units** — ytuner, transcode-proxy, ytuner-webui
9. **Sets permissions** — `/opt/ytuner/` group-writable by your user
10. **Creates sudoers rule** — allows web UI to restart services without password
11. **Starts all services** — enables and starts everything

The script is idempotent — safe to re-run if something goes wrong.

## Manual Installation

If you prefer to install manually, follow these steps.

### 1. Install packages

```bash
sudo apt update
sudo apt install nginx ffmpeg sqlite3 libsqlite3-0 python3 wget libarchive-tools
```

### 2. Download and extract YTuner

```bash
# For aarch64 (Pi 4/5 with 64-bit OS):
wget https://github.com/coffeegreg/YTuner/releases/download/v1.2.6/ytuner-1.2.6-linux-aarch64.tar.xz
sudo mkdir -p /opt/ytuner
sudo bsdtar -xf ytuner-1.2.6-linux-aarch64.tar.xz -C /opt/ytuner --strip-components=1
sudo chmod +x /opt/ytuner/ytuner
```

### 3. Copy fork files

From the cloned repo:

```bash
sudo cp cfg/stations.ini /opt/ytuner/config/stations.ini
sudo cp cfg/avr.ini /opt/ytuner/config/avr.ini
sudo cp transcode/transcode-proxy.py /opt/ytuner/transcode-proxy.py
sudo cp webui/webui.py /opt/ytuner/webui.py
sudo cp script/transcode-url.sh /usr/local/bin/
sudo cp script/ytuner-backup.sh /usr/local/bin/
sudo cp script/ytuner-restore.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/transcode-url.sh /usr/local/bin/ytuner-backup.sh /usr/local/bin/ytuner-restore.sh
```

### 4. Configure ytuner.ini

Edit `/opt/ytuner/ytuner.ini`:

```ini
[WebServer]
WebServerIPAddress=127.0.0.1
WebServerPort=18081

[Bookmark]
CommonBookmark=0

[DNSServer]
Enable=0
```

### 5. Set server IP (optional)

The web UI and helper scripts auto-detect the server's LAN IP address. To override, set the `YTUNER_SERVER_IP` environment variable (e.g. in the ytuner-webui systemd unit or your shell profile).

### 6. Set up nginx

```bash
sudo cp nginx/ytuner-proxy /etc/nginx/sites-available/ytuner-proxy
sudo ln -sf /etc/nginx/sites-available/ytuner-proxy /etc/nginx/sites-enabled/ytuner-proxy
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl reload nginx
```

### 7. Install systemd units

```bash
sudo cp systemd/ytuner.service /etc/systemd/system/
sudo cp systemd/transcode-proxy.service /etc/systemd/system/
# Edit ytuner-webui.service: replace "andrew" with your username
sudo cp systemd/ytuner-webui.service /etc/systemd/system/
sudo systemctl daemon-reload
```

### 8. Set permissions

```bash
sudo chown -R root:YOUR_USER /opt/ytuner
sudo chmod -R g+w /opt/ytuner
sudo touch /var/log/ytuner.log
sudo chmod 644 /var/log/ytuner.log
```

### 9. Create sudoers rule

```bash
sudo tee /etc/sudoers.d/ytuner-webui <<EOF
YOUR_USER ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart ytuner
YOUR_USER ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart transcode-proxy
YOUR_USER ALL=(ALL) NOPASSWD: /usr/bin/systemctl status ytuner
YOUR_USER ALL=(ALL) NOPASSWD: /usr/bin/systemctl status transcode-proxy
EOF
sudo chmod 440 /etc/sudoers.d/ytuner-webui
```

### 10. Start services

```bash
sudo systemctl enable --now ytuner transcode-proxy ytuner-webui
sudo systemctl reload nginx
```

## Post-Install

### Configure your AVR receiver

Set the DNS server on your AVR to your YTuner server's IP address. This makes the receiver's vTuner requests go to YTuner instead of the defunct vTuner service.

### Add Libratone speakers

Open the web UI at `http://YOUR_IP:8080/` and use the "Add New Speaker" button. The guided wizard walks you through discovering preset IDs. See [LIBRATONE_SETUP.md](LIBRATONE_SETUP.md) for details.

### Web UI

The web UI at port 8080 lets you:
- Manage Libratone speaker presets
- Edit the station library (stations.ini)
- Search Radio Browser for new stations
- Monitor and restart services
- Manage server links

### Transcode proxy

The transcode proxy at port 8888 converts HTTPS and non-MP3 streams to HTTP MP3 for devices that only support MP3. Use it in station URLs:

```
http://YOUR_IP:8888/transcode?url=https%3A%2F%2Fexample.com%2Fstream.aac
```

Or use the helper script:

```bash
transcode-url.sh "https://example.com/stream.aac" 192k
```

## Updating

To update to a newer version of the fork:

```bash
cd YTuner
git pull
sudo bash script/install.sh
```

The installer will skip downloading the YTuner binary if it already exists and will not overwrite your `stations.ini`.

## Uninstalling

```bash
sudo systemctl disable --now ytuner transcode-proxy ytuner-webui
sudo rm /etc/systemd/system/ytuner.service
sudo rm /etc/systemd/system/transcode-proxy.service
sudo rm /etc/systemd/system/ytuner-webui.service
sudo rm /etc/nginx/sites-enabled/ytuner-proxy
sudo rm /etc/nginx/sites-available/ytuner-proxy
sudo rm /etc/sudoers.d/ytuner-webui
sudo rm -rf /opt/ytuner
sudo rm /usr/local/bin/transcode-url.sh /usr/local/bin/ytuner-backup.sh /usr/local/bin/ytuner-restore.sh
sudo systemctl daemon-reload
sudo systemctl reload nginx
```

## Ports

| Port | Service | Description |
|------|---------|-------------|
| 80 | nginx | Reverse proxy — AVR devices connect here |
| 8080 | ytuner-webui | Web management UI |
| 8888 | transcode-proxy | Audio transcoding proxy |
| 18081 | ytuner | YTuner HTTP server (behind nginx) |

## Troubleshooting

**Service won't start:**
```bash
journalctl -u ytuner -n 50
journalctl -u transcode-proxy -n 50
journalctl -u ytuner-webui -n 50
```

**Port 80 already in use:**
Check if another web server is running: `sudo ss -lntp | grep :80`

**AVR can't find stations:**
Verify DNS is pointing to the YTuner server. The AVR must resolve `*.vtuner.com` to your server's IP.

**Streams don't play:**
Check if the stream needs transcoding. HTTPS streams and non-MP3 codecs must go through the transcode proxy.
