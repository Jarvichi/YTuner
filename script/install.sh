#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────
# YTuner Fork — Interactive Installer
# Installs YTuner + web UI + transcoding proxy + nginx reverse proxy
# on Debian / Raspberry Pi OS.
#
# Safe to re-run (idempotent).
# ─────────────────────────────────────────────────────────────────────
set -euo pipefail

YTUNER_VERSION="1.2.6"
YTUNER_RELEASE_BASE="https://github.com/coffeegreg/YTuner/releases/download/v${YTUNER_VERSION}"
INSTALL_DIR="/opt/ytuner"
LOG_FILE="/var/log/ytuner.log"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ── Colours ──────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()  { echo -e "${CYAN}[*]${NC} $*"; }
ok()    { echo -e "${GREEN}[+]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
die()   { err "$*"; exit 1; }

# ── 1. Pre-flight ────────────────────────────────────────────────────
info "YTuner fork installer v${YTUNER_VERSION}"
echo

if [[ $EUID -ne 0 ]]; then
    die "This script must be run as root (use: sudo $0)"
fi

ARCH="$(uname -m)"
case "${ARCH}" in
    aarch64)     YTUNER_ARCHIVE="ytuner-${YTUNER_VERSION}-linux-aarch64.tar.xz" ;;
    armv7l|armhf) YTUNER_ARCHIVE="ytuner-${YTUNER_VERSION}-linux-armhf.tar.xz"  ;;
    x86_64)      YTUNER_ARCHIVE="ytuner-${YTUNER_VERSION}-linux-amd64.tar.xz"   ;;
    *)           die "Unsupported architecture: ${ARCH}" ;;
esac
ok "Architecture: ${ARCH} -> ${YTUNER_ARCHIVE}"

# ── 2. Detect server IP ─────────────────────────────────────────────
DEFAULT_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
DEFAULT_IP="${DEFAULT_IP:-127.0.0.1}"

echo
echo -e "${BOLD}Server IP address${NC}"
echo "  Detected: ${DEFAULT_IP}"
read -rp "  Use this IP? [Y/n/enter custom IP]: " IP_INPUT
IP_INPUT="${IP_INPUT:-Y}"

if [[ "${IP_INPUT}" =~ ^[Yy]$ ]]; then
    SERVER_IP="${DEFAULT_IP}"
elif [[ "${IP_INPUT}" =~ ^[Nn]$ ]]; then
    read -rp "  Enter server IP: " SERVER_IP
else
    SERVER_IP="${IP_INPUT}"
fi
ok "Server IP: ${SERVER_IP}"

# ── 3. Detect service user ──────────────────────────────────────────
DEFAULT_USER="${SUDO_USER:-$(logname 2>/dev/null || echo pi)}"

echo
echo -e "${BOLD}Service user${NC} (runs the web UI)"
echo "  Detected: ${DEFAULT_USER}"
read -rp "  Use this user? [Y/n/enter custom]: " USER_INPUT
USER_INPUT="${USER_INPUT:-Y}"

if [[ "${USER_INPUT}" =~ ^[Yy]$ ]]; then
    SERVICE_USER="${DEFAULT_USER}"
elif [[ "${USER_INPUT}" =~ ^[Nn]$ ]]; then
    read -rp "  Enter username: " SERVICE_USER
else
    SERVICE_USER="${USER_INPUT}"
fi

id "${SERVICE_USER}" &>/dev/null || die "User '${SERVICE_USER}' does not exist"
ok "Service user: ${SERVICE_USER}"

# ── 4. Install APT packages ─────────────────────────────────────────
echo
info "Installing required packages..."
apt-get update -qq
apt-get install -y -qq nginx ffmpeg sqlite3 libsqlite3-0 python3 wget libarchive-tools 2>&1 | tail -1
ok "Packages installed"

# ── 5. Download & extract YTuner binary ──────────────────────────────
if [[ -f "${INSTALL_DIR}/ytuner" ]]; then
    warn "YTuner binary already exists at ${INSTALL_DIR}/ytuner — skipping download"
else
    info "Downloading YTuner ${YTUNER_VERSION}..."
    TMP_DIR="$(mktemp -d)"
    wget -q "${YTUNER_RELEASE_BASE}/${YTUNER_ARCHIVE}" -O "${TMP_DIR}/${YTUNER_ARCHIVE}"
    mkdir -p "${INSTALL_DIR}"
    bsdtar -xf "${TMP_DIR}/${YTUNER_ARCHIVE}" -C "${INSTALL_DIR}" --strip-components=1
    rm -rf "${TMP_DIR}"
    chmod +x "${INSTALL_DIR}/ytuner"
    ok "YTuner extracted to ${INSTALL_DIR}"
fi

# ── 6. Copy custom files from repo ──────────────────────────────────
info "Installing custom configuration and scripts..."

# Config files (don't overwrite stations.ini if it already exists)
mkdir -p "${INSTALL_DIR}/config"
cp -n "${REPO_DIR}/cfg/stations.ini" "${INSTALL_DIR}/config/stations.ini" 2>/dev/null || true
cp "${REPO_DIR}/cfg/avr.ini" "${INSTALL_DIR}/config/avr.ini"

# Transcoding proxy
cp "${REPO_DIR}/transcode/transcode-proxy.py" "${INSTALL_DIR}/transcode-proxy.py"

# Web UI
cp "${REPO_DIR}/webui/webui.py" "${INSTALL_DIR}/webui.py"

# Helper scripts
cp "${REPO_DIR}/script/transcode-url.sh" /usr/local/bin/transcode-url.sh
cp "${REPO_DIR}/script/ytuner-backup.sh" /usr/local/bin/ytuner-backup.sh
cp "${REPO_DIR}/script/ytuner-restore.sh" /usr/local/bin/ytuner-restore.sh
chmod +x /usr/local/bin/transcode-url.sh /usr/local/bin/ytuner-backup.sh /usr/local/bin/ytuner-restore.sh

ok "Custom files installed"

# ── 7. Configure ytuner.ini ──────────────────────────────────────────
info "Configuring ytuner.ini..."
INI="${INSTALL_DIR}/ytuner.ini"

# Patch key settings (idempotent sed replacements)
sed -i 's/^WebServerPort=.*/WebServerPort=18081/'           "${INI}"
sed -i 's/^CommonBookmark=.*/CommonBookmark=0/'             "${INI}"
sed -i 's/^Enable=1\s*$/Enable=0/'                         "${INI}"  # DNSServer.Enable — only first match in [DNSServer]
# More targeted: disable DNS server
sed -i '/^\[DNSServer\]/,/^\[/{s/^Enable=.*/Enable=0/}'    "${INI}"
sed -i 's/^WebServerIPAddress=.*/WebServerIPAddress=127.0.0.1/' "${INI}"

ok "ytuner.ini configured (port 18081, no DNS, bookmarks per-device)"

# ── 8. Patch webui.py — replace hardcoded IP ────────────────────────
info "Patching webui.py with server IP ${SERVER_IP}..."
sed -i "s/192\.168\.5\.180/${SERVER_IP}/g" "${INSTALL_DIR}/webui.py"
ok "webui.py patched"

# ── 9. Patch transcode-url.sh — replace hardcoded IP ────────────────
sed -i "s/192\.168\.5\.180/${SERVER_IP}/g" /usr/local/bin/transcode-url.sh
ok "transcode-url.sh patched"

# ── 10. Install nginx config ────────────────────────────────────────
info "Installing nginx config..."
cp "${REPO_DIR}/nginx/ytuner-proxy" /etc/nginx/sites-available/ytuner-proxy

# Enable site, disable default
ln -sf /etc/nginx/sites-available/ytuner-proxy /etc/nginx/sites-enabled/ytuner-proxy
rm -f /etc/nginx/sites-enabled/default

nginx -t 2>&1 || die "Nginx config test failed"
ok "Nginx configured"

# ── 11. Install systemd units ───────────────────────────────────────
info "Installing systemd service units..."

cp "${REPO_DIR}/systemd/ytuner.service" /etc/systemd/system/ytuner.service
cp "${REPO_DIR}/systemd/transcode-proxy.service" /etc/systemd/system/transcode-proxy.service

# Patch webui service with actual username
sed "s/User=andrew/User=${SERVICE_USER}/; s/Group=andrew/Group=${SERVICE_USER}/" \
    "${REPO_DIR}/systemd/ytuner-webui.service" > /etc/systemd/system/ytuner-webui.service

systemctl daemon-reload
ok "Systemd units installed"

# ── 12. Set permissions ─────────────────────────────────────────────
info "Setting permissions..."

chown -R root:"${SERVICE_USER}" "${INSTALL_DIR}"
chmod -R g+w "${INSTALL_DIR}"
# Ensure config dir is writable by service user (web UI writes XML files)
chmod -R g+w "${INSTALL_DIR}/config" 2>/dev/null || true

# Log file
touch "${LOG_FILE}"
chmod 644 "${LOG_FILE}"
chown root:"${SERVICE_USER}" "${LOG_FILE}"

ok "Permissions set (${INSTALL_DIR} owned root:${SERVICE_USER}, group-writable)"

# ── 13. Sudoers for web UI ──────────────────────────────────────────
info "Installing sudoers rule for web UI..."
SUDOERS_FILE="/etc/sudoers.d/ytuner-webui"
cat > "${SUDOERS_FILE}" <<EOF
# Allow the web UI user to restart YTuner services without a password
${SERVICE_USER} ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart ytuner
${SERVICE_USER} ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart transcode-proxy
${SERVICE_USER} ALL=(ALL) NOPASSWD: /usr/bin/systemctl status ytuner
${SERVICE_USER} ALL=(ALL) NOPASSWD: /usr/bin/systemctl status transcode-proxy
EOF
chmod 440 "${SUDOERS_FILE}"
visudo -cf "${SUDOERS_FILE}" || die "Sudoers file is invalid"
ok "Sudoers installed at ${SUDOERS_FILE}"

# ── 14. Optionally disable systemd-resolved ─────────────────────────
if systemctl is-active --quiet systemd-resolved 2>/dev/null; then
    echo
    warn "systemd-resolved is running (it binds port 53)."
    echo "  If you plan to use YTuner's built-in DNS server later,"
    echo "  you should disable systemd-resolved."
    read -rp "  Disable systemd-resolved now? [y/N]: " DISABLE_RESOLVED
    if [[ "${DISABLE_RESOLVED}" =~ ^[Yy]$ ]]; then
        systemctl stop systemd-resolved
        systemctl disable systemd-resolved
        # Point resolv.conf at a real DNS server
        if [[ -L /etc/resolv.conf ]]; then
            rm /etc/resolv.conf
            echo "nameserver 8.8.8.8" > /etc/resolv.conf
            echo "nameserver 1.1.1.1" >> /etc/resolv.conf
        fi
        ok "systemd-resolved disabled"
    else
        info "Leaving systemd-resolved as-is"
    fi
fi

# ── 15. Enable and start services ───────────────────────────────────
info "Enabling and starting services..."

systemctl enable --now ytuner.service
systemctl enable --now transcode-proxy.service
systemctl enable --now ytuner-webui.service
systemctl reload nginx

ok "All services started"

# ── 16. Verify ──────────────────────────────────────────────────────
echo
echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"
echo -e "${GREEN} Installation complete!${NC}"
echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"
echo
echo "  YTuner (AVR):    http://${SERVER_IP}/"
echo "  Web UI:          http://${SERVER_IP}:8080/"
echo "  Transcode proxy: http://${SERVER_IP}:8888/health"
echo

# Quick health checks
FAIL=0
for SVC in ytuner transcode-proxy ytuner-webui nginx; do
    if systemctl is-active --quiet "${SVC}" 2>/dev/null; then
        echo -e "  ${GREEN}●${NC} ${SVC} is running"
    else
        echo -e "  ${RED}●${NC} ${SVC} is NOT running"
        FAIL=1
    fi
done

echo
if [[ ${FAIL} -eq 0 ]]; then
    ok "All services are healthy."
else
    warn "Some services failed to start. Check: journalctl -u <service>"
fi

echo
info "Next steps:"
echo "  1. Point your AVR's DNS server to ${SERVER_IP}"
echo "  2. Open http://${SERVER_IP}:8080/ to manage stations and speakers"
echo "  3. See doc/INSTALL.md for detailed post-install instructions"
echo
