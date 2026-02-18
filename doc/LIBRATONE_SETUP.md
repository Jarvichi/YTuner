# YTuner Setup for Libratone Speakers

## Overview
This document explains how YTuner has been configured to work with Libratone speakers, which have hardcoded preset IDs that cannot be changed.

## The Problem
Libratone speakers have firmware-embedded preset IDs (like 3158, 13417, 80195, etc.) that are sent to the vTuner service when you press preset buttons. YTuner v1.2.6 has basic Libratone support but requires proper configuration.

## The Solution

### 1. Key Configuration Changes

**File: `/opt/ytuner/ytuner.ini`**
- Changed `CommonBookmark=0` (was 1)
  - This allows device-specific bookmark files instead of a single shared file
  - Each speaker gets its own XML file based on its IP address

**File: `/etc/nginx/sites-available/ytuner-proxy`**
- Changed `proxy_set_header Host $remote_addr;` (was `192.168.5.180`)
  - Uses each speaker's IP address as its unique device ID
  - Allows YTuner to serve different presets to different speakers

### 2. Device-Specific Configuration Files

Each Libratone speaker has its own XML file in `/opt/ytuner/config/`.
Different speakers have different firmware preset IDs, so each file maps the correct IDs to stations.

### 3. How It Works

When a Libratone speaker preset button is pressed:
1. Speaker sends request: `Search.asp?sSearchtype=3&search=3158`
2. Nginx forwards request with `Host: 192.168.5.31` (speaker's IP)
3. YTuner checks if `/opt/ytuner/config/192.168.5.31.xml` exists
4. If exists, prepends "UNB" to search ID → looks for `UNB3158` in that XML file
5. Returns the matching station URL to the speaker

### 4. Transcoding Proxy

Libratone speakers only support MP3 playback. A transcoding proxy (`transcode-proxy.py`) runs on port 8888 and converts non-MP3 streams (AAC, HLS, etc.) to MP3 on the fly via FFmpeg.

To use a non-MP3 stream, wrap the URL through the proxy:
```
http://192.168.5.180:8888/transcode?url=<URL-encoded stream URL>
```

Or use the helper script:
```bash
~/transcode-url.sh "https://example.com/stream.aac"
~/transcode-url.sh "https://example.com/stream.aac" 192k   # custom bitrate
```

The proxy runs as a systemd service (`transcode-proxy.service`). Configuration via environment variables:
- `TRANSCODE_PORT` (default 8888)
- `TRANSCODE_BITRATE` (default 128k)
- `TRANSCODE_MAX_CONCURRENT` (default 4)

### 5. Web Management UI

A web UI (`webui.py`) runs on port 8080 and provides a browser-based interface for:
- Viewing and editing speaker preset assignments
- Managing stream URLs and station names
- Adding new speakers

Access it at `http://192.168.5.180:8080`. It runs as a systemd service (`ytuner-webui.service`).

This is the easiest way to manage speakers — no need to edit XML files by hand.

## Adding a New Libratone Speaker

### Step 1: Identify the Speaker's IP and Preset IDs

1. Connect the new speaker to YTuner (configure its DNS to point to this server)
2. Press each preset button on the speaker
3. Check the logs to find the preset IDs:
```bash
tail -100 /var/log/nginx/access.log | grep "sSearchtype=3"
```
Look for lines like: `192.168.5.XX - - ... "search=XXXXX"`

### Step 2: Create Device Configuration File

Use the web UI at `http://192.168.5.180:8080` to add the new speaker and assign stations to its presets.

Alternatively, create `/opt/ytuner/config/192.168.5.XX.xml` manually (replace XX with speaker's last octet):

```xml
<?xml version="1.0" encoding="utf-8"?>
<ListOfItems>
  <ItemCount>5</ItemCount>
  <Item>
    <ItemType>Station</ItemType>
    <StationId>UNB[PRESET_ID_1]</StationId>
    <StationName>Station Name</StationName>
    <StationUrl>http://stream-url-here</StationUrl>
    <StationDesc>Preset 1</StationDesc>
    <Logo></Logo>
    <StationFormat>Genre</StationFormat>
    <StationLocation></StationLocation>
    <StationBandWidth></StationBandWidth>
    <StationMime></StationMime>
    <Relia>3</Relia>
    <Bookmark></Bookmark>
  </Item>
  <!-- Repeat for each preset with UNB[PRESET_ID_2], etc. -->
</ListOfItems>
```

**Important Notes:**
- StationId MUST be `UNB` + the preset ID (e.g., `UNB3158`)
- Use HTTP URLs, not HTTPS (Libratone doesn't support HTTPS)
- Streams must reach the speaker as MP3 — use the transcoding proxy for non-MP3 sources

### Step 3: Restart YTuner
```bash
sudo systemctl restart ytuner
```

## Customizing Stations

### Using the Web UI (recommended)

Open `http://192.168.5.180:8080` in a browser to view and edit preset assignments for each speaker.

### Manual Editing

1. Edit the device's XML file:
```bash
sudo nano /opt/ytuner/config/192.168.5.31.xml
```

2. Find the preset you want to change (by StationId)

3. Update the `StationName` and `StationUrl`
   - Keep the `StationId` unchanged (must remain `UNB[ID]`)
   - Use HTTP URLs only
   - For non-MP3 streams, wrap through the transcoding proxy

4. Restart YTuner:
```bash
sudo systemctl restart ytuner
```

### Finding Station URLs

Search for stations on Radio Browser:
```bash
curl -s "http://all.api.radio-browser.info/json/stations/search?name=STATION_NAME&countrycode=GB&codec=MP3&hidebroken=true" | python3 -c "import sys, json; stations = json.load(sys.stdin); [print(f\"{s['name']}: {s['url']}\") for s in stations[:5]]"
```

Replace `STATION_NAME` with the station you're looking for. Filter by `codec=MP3` to find streams that work directly, or use any codec and wrap through the transcoding proxy.

## Stream Compatibility

**Direct playback (no proxy needed):**
- HTTP URLs with MP3 codec

**Via transcoding proxy:**
- AAC, HLS (.m3u8), and other non-MP3 formats — the proxy converts them to MP3
- HTTPS sources — the proxy handles TLS and forwards as HTTP MP3

**Not supported:**
- HTTPS URLs direct to speaker (speaker firmware doesn't support TLS)
- DRM-protected streams

## Troubleshooting

### Speaker plays the same station for all presets

1. Check that `CommonBookmark=0` in `/opt/ytuner/ytuner.ini`
2. Check that device XML file exists: `ls /opt/ytuner/config/192.168.5.XX.xml`
3. Check nginx config uses `$remote_addr`:
```bash
grep "proxy_set_header Host" /etc/nginx/sites-available/ytuner-proxy
```
Should show: `proxy_set_header Host $remote_addr;`

### Speaker doesn't play anything

1. Check if the stream URL works:
```bash
timeout 3 curl -s http://stream-url-here | head -c 100
```

2. Make sure the URL is HTTP, not HTTPS

3. For transcoded streams, check the proxy is running:
```bash
sudo systemctl status transcode-proxy
```

4. Check YTuner logs:
```bash
tail -50 /var/log/ytuner.log
```

### Find which presets are being used

Check nginx access log:
```bash
tail -50 /var/log/nginx/access.log | grep "192.168.5.XX"
```

### Restart services after changes

```bash
# After changing station XML files:
sudo systemctl restart ytuner

# After changing nginx config:
sudo nginx -t && sudo systemctl reload nginx

# After changing transcode proxy config:
sudo systemctl restart transcode-proxy

# After changing webui:
sudo systemctl restart ytuner-webui
```

## File Locations

- **YTuner config:** `/opt/ytuner/ytuner.ini`
- **YTuner binary:** `/opt/ytuner/ytuner`
- **Station lists:** `/opt/ytuner/config/stations.ini`
- **Device configs:** `/opt/ytuner/config/192.168.5.XX.xml`
- **YTuner logs:** `/var/log/ytuner.log`
- **Nginx config:** `/etc/nginx/sites-available/ytuner-proxy`
- **Nginx logs:** `/var/log/nginx/access.log`
- **Transcoding proxy:** `/opt/ytuner/transcode-proxy.py`
- **Web UI:** `/opt/ytuner/webui.py` (port 8080)

## Additional Resources

- YTuner upstream: https://github.com/coffeegreg/YTuner
- Libratone Discussion: https://github.com/coffeegreg/YTuner/discussions/68
- Libratone Issue: https://github.com/coffeegreg/YTuner/issues/58
- Radio Browser API: http://all.api.radio-browser.info/

## Notes

- The solution works around Libratone's hardcoded preset IDs by using device-specific XML bookmark files
- Each speaker can have different stations assigned to its presets
- The configuration survives YTuner updates (XML files are in config directory)
- Non-MP3 streams work via the transcoding proxy (FFmpeg)
