# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

YTuner is a lightweight vTuner internet radio replacement service for AVR devices (Yamaha, Denon, Pioneer, Marantz, etc.). It runs on a Raspberry Pi at 192.168.5.180, serving internet radio to vintage network-connected audio receivers and Libratone speakers.

The project consists of:
- **YTuner** (Free Pascal) — the main vTuner-compatible server installed at `/opt/ytuner/`
- **Transcoding proxy** (Python 3) — converts non-MP3 streams to MP3 via FFmpeg for devices that only support MP3
- **Helper scripts** (Bash) — backup, restore, installation, and URL generation utilities
- **Station configurations** (INI/YAML/XML) — custom radio station definitions

## Architecture

### YTuner Server (upstream project at `ytuner-source/`)
Written in Free Pascal, built with Lazarus IDE and FPC. Source in `ytuner-source/src/`. Key modules:
- `httpserver.pas` — multi-threaded HTTP server (port 80), handles all AVR requests
- `radiobrowser.pas` — Radio-browser.info API client with caching
- `radiobrowserdb.pas` — SQLite-backed local cache of radio-browser data
- `dnsserver.pas` — DNS proxy (port 53) to intercept vtuner.com queries
- `my_stations.pas` — parses custom station files (INI/YAML)
- `vtuner.pas` — vTuner XML protocol format
- `avr.pas` — per-device configuration and filtering
- `bookmark.pas` — station bookmarks (per-device or shared)

Build requires Lazarus IDE + Free Pascal Compiler + Indy library. No automated test suite exists.

### Transcoding Proxy (`transcode-proxy.py`)
Python 3 HTTP server on port 8888. Spawns FFmpeg to transcode streams to MP3 on-the-fly. Configured via environment variables: `TRANSCODE_PORT` (default 8888), `TRANSCODE_BITRATE` (default 128k), `TRANSCODE_MAX_CONCURRENT` (default 4). Runs as systemd service (`transcode-proxy.service`).

### Nginx Reverse Proxy
Sits in front of YTuner. Config at `/etc/nginx/sites-available/ytuner-proxy`. Sets `Host` header to `$remote_addr` so YTuner can identify individual devices (critical for Libratone per-device presets).

## Key File Locations

| What | Path |
|------|------|
| YTuner binary + config | `/opt/ytuner/` |
| YTuner main config | `/opt/ytuner/ytuner.ini` |
| AVR device config | `/opt/ytuner/config/avr.ini` |
| Custom stations | `/opt/ytuner/config/stations.ini` |
| Device-specific XMLs | `/opt/ytuner/config/192.168.5.XX.xml` |
| YTuner source code | `~/ytuner-source/src/` |
| Transcode proxy | `~/transcode-proxy.py` |
| Transcode service | `~/transcode-proxy.service` |
| Backup/restore scripts | `~/ytuner-backup.sh`, `~/ytuner-restore.sh` |
| Libratone setup docs | `~/YTUNER_LIBRATONE_SETUP.md` |
| YTuner logs | `/var/log/ytuner.log` |
| Nginx config | `/etc/nginx/sites-available/ytuner-proxy` |
| Nginx logs | `/var/log/nginx/access.log` |

## Common Commands

```bash
# Service management
sudo systemctl restart ytuner
sudo systemctl status ytuner
sudo systemctl restart transcode-proxy

# View logs
tail -f /var/log/ytuner.log
tail -f /var/log/nginx/access.log

# Backup current working state
~/ytuner-backup.sh

# Restore from backup
~/ytuner-restore.sh ~/ytuner-backups/ytuner-working-YYYYMMDD-HHMMSS.tar.gz

# Generate a transcoded proxy URL for a non-MP3 stream
~/transcode-url.sh "https://example.com/stream.aac" 192k

# Test a stream URL
timeout 3 curl -s http://stream-url | head -c 100

# Search Radio Browser API for stations
curl -s "http://all.api.radio-browser.info/json/stations/search?name=STATION&countrycode=GB&codec=MP3&hidebroken=true" | python3 -m json.tool

# Check what's listening on key ports
sudo ss -lntp | grep -E ':80\b|:53\b|:8888\b'

# Nginx config test and reload
sudo nginx -t && sudo systemctl reload nginx
```

## Libratone Speaker Configuration

Libratone speakers have firmware-hardcoded preset IDs. Each speaker needs a device-specific XML file at `/opt/ytuner/config/<IP>.xml` mapping `UNB<preset_id>` to station URLs. Key constraints:
- `CommonBookmark=0` must be set in `ytuner.ini`
- Nginx must forward `Host: $remote_addr` (not a static IP)
- Streams must be HTTP (not HTTPS) and MP3 codec
- Use the transcode proxy for non-MP3 streams

See `~/YTUNER_LIBRATONE_SETUP.md` for full details. Currently configured speakers: 192.168.5.31, 192.168.5.11.

## Station File Formats

**INI format** (`stations.ini`):
```
[Category Name]
Station Name=http://stream-url|http://logo-url
```

**YAML format** (`stations.yaml`):
```
Category Name:
  Station Name: http://stream-url|http://logo-url
```

**Device XML** (for Libratone presets): StationId must be `UNB` + preset ID. See existing XML files for template.
