#!/usr/bin/env bash
set -euo pipefail

TS="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${HOME}/ytuner-backups"
WORK_DIR="$(mktemp -d)"
ARCHIVE="${BACKUP_DIR}/ytuner-working-${TS}.tar.gz"

mkdir -p "${BACKUP_DIR}"

echo "[*] Creating working snapshot in ${WORK_DIR}"

# 1) YTuner install directory
if [ -d /opt/ytuner ]; then
  sudo tar -C / -cf "${WORK_DIR}/opt-ytuner.tar" opt/ytuner
else
  echo "[!] /opt/ytuner not found (skipping)"
fi

# 2) systemd unit (and enabled symlink state)
if [ -f /etc/systemd/system/ytuner.service ]; then
  sudo cp -a /etc/systemd/system/ytuner.service "${WORK_DIR}/ytuner.service"
else
  echo "[!] /etc/systemd/system/ytuner.service not found (skipping)"
fi

# Record whether it's enabled
sudo systemctl is-enabled ytuner.service > "${WORK_DIR}/ytuner.service.enabled" 2>/dev/null || true
sudo systemctl is-active ytuner.service  > "${WORK_DIR}/ytuner.service.active"  2>/dev/null || true

# 3) DNS / resolver state snapshots
# resolv.conf might be symlink; capture both link + content
ls -l /etc/resolv.conf > "${WORK_DIR}/etc-resolv.conf.ls" 2>/dev/null || true
sudo cp -a /etc/resolv.conf "${WORK_DIR}/resolv.conf" 2>/dev/null || true

sudo systemctl is-enabled systemd-resolved > "${WORK_DIR}/systemd-resolved.enabled" 2>/dev/null || true
sudo systemctl is-active  systemd-resolved > "${WORK_DIR}/systemd-resolved.active"  2>/dev/null || true

# What is listening on DNS ports right now?
sudo ss -lnup > "${WORK_DIR}/ss-lnup.txt" 2>/dev/null || true
sudo ss -lntp > "${WORK_DIR}/ss-lntp.txt" 2>/dev/null || true

# 4) YTuner log (useful when restoring)
if [ -f /var/log/ytuner.log ]; then
  sudo tail -n 2000 /var/log/ytuner.log > "${WORK_DIR}/ytuner.log.tail" 2>/dev/null || true
fi

# 5) Package snapshot (helpful for rebuilds)
dpkg -l > "${WORK_DIR}/dpkg-list.txt" 2>/dev/null || true
apt-mark showmanual > "${WORK_DIR}/apt-manual.txt" 2>/dev/null || true

# 6) Quick version stamps
uname -a > "${WORK_DIR}/uname.txt" 2>/dev/null || true
date > "${WORK_DIR}/date.txt" 2>/dev/null || true

echo "[*] Creating archive ${ARCHIVE}"
tar -C "${WORK_DIR}" -czf "${ARCHIVE}" .

rm -rf "${WORK_DIR}"

echo "[✓] Backup created: ${ARCHIVE}"
echo "[i] Tip: copy it off the Pi for extra safety (scp, etc.)."
