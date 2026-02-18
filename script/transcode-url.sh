#!/bin/bash
# Helper to generate a transcoded proxy URL for use in YTuner station configs.
# Usage: ./transcode-url.sh <stream_url> [bitrate]
# Example: ./transcode-url.sh "https://example.com/stream.aac" 192k

PROXY_HOST="${YTUNER_SERVER_IP:-$(hostname -I 2>/dev/null | awk '{print $1}')}"
PROXY_HOST="${PROXY_HOST:-127.0.0.1}"
PROXY_PORT="${TRANSCODE_PORT:-8888}"

if [ -z "$1" ]; then
    echo "Usage: $0 <stream_url> [bitrate]"
    echo "Example: $0 'https://example.com/stream.aac' 128k"
    exit 1
fi

ENCODED_URL=$(python3 -c "from urllib.parse import quote; print(quote('$1', safe=''))")

if [ -n "$2" ]; then
    echo "http://${PROXY_HOST}:${PROXY_PORT}/transcode?url=${ENCODED_URL}&bitrate=$2"
else
    echo "http://${PROXY_HOST}:${PROXY_PORT}/transcode?url=${ENCODED_URL}"
fi
