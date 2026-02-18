#!/usr/bin/env bash
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "Usage: $0 /path/to/ytuner-working-YYYYmmdd-HHMMSS.tar.gz"
  exit 1
fi

ARCHIVE="$1"
if [ ! -f "${ARCHIVE}" ]; then
  echo "Archive not found: ${ARCHIVE}"
  exit 1
fi

WORK_DIR="$(mktemp -d)"
echo "[*] Extracting ${ARCHIVE} to ${WORK_DIR}"
tar -C "${WORK_DIR}" -xzf "${ARCHIVE}"

echo "[*] Stopping ytuner (if running)"
sudo systemctl stop ytuner.service 2>/dev/null || true

echo "[*] Restoring /opt/ytuner"
if [ -f "${WORK_DIR}/opt-ytuner.tar" ]; then
  sudo rm -rf /opt/ytuner
  sudo tar -C / -xf "${WORK_DIR}/opt-ytuner.tar"
else
  echo "[!] opt-ytuner.tar not found inside archive (skipping /opt/ytuner restore)"
fi

echo "[*] Restoring systemd unit (if present)"
if [ -f "${WORK_DIR}/ytuner.service" ]; then
  sudo cp -a "${WORK_DIR}/ytuner.service" /etc/systemd/system/ytuner.service
  sudo systemctl daemon-reload
else
  echo "[!] ytuner.service file not found inside archive (skipping unit restore)"
fi

# Restore resolv.conf content (we avoid trying to recreate symlink exactly; content is enough for most cases)
if [ -f "${WORK_DIR}/resolv.conf" ]; then
  echo "[*] Restoring /etc/resolv.conf (content copy)"
  sudo cp -a "${WORK_DIR}/resolv.conf" /etc/resolv.conf || true
fi

# Re-enable/start ytuner depending on saved state (default: enable+start)
ENABLED="enabled"
ACTIVE="active"
if [ -f "${WORK_DIR}/ytuner.service.enabled" ]; then
  ENABLED="$(cat "${WORK_DIR}/ytuner.service.enabled" || true)"
fi
if [ -f "${WORK_DIR}/ytuner.service.active" ]; then
  ACTIVE="$(cat "${WORK_DIR}/ytuner.service.active" || true)"
fi

echo "[*] Applying saved service state: enabled=${ENABLED}, active=${ACTIVE}"
if [[ "${ENABLED}" == "enabled" ]]; then
  sudo systemctl enable ytuner.service || true
else
  sudo systemctl disable ytuner.service || true
fi

if [[ "${ACTIVE}" == "active" ]]; then
  sudo systemctl start ytuner.service || true
fi

echo "[*] Current status:"
sudo systemctl status ytuner.service --no-pager || true
echo
echo "[*] Listening sockets (DNS + HTTP):"
sudo ss -lnup | egrep ':53\b' || true
sudo ss -lntp  | egrep ':80\b|:443\b' || true

rm -rf "${WORK_DIR}"
echo "[✓] Restore complete."
