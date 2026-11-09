#!/usr/bin/env bash
# Installs or updates the PIF Online server on a Linux machine using systemd.
# usage: sudo PIF_PORT=7777 bash install-vps.sh
set -euo pipefail

port=${PIF_PORT:-7777}
repository=AurelienBaraquin/pif-online
binary=/usr/local/bin/pif-server
service=/etc/systemd/system/pif-server.service

if [ "$(id -u)" -ne 0 ]; then
  echo "Run this script with sudo." >&2
  exit 1
fi
if ! [[ $port =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
  echo "PIF_PORT must be a number between 1 and 65535." >&2
  exit 1
fi

case $(uname -m) in
  x86_64) architecture=amd64 ;;
  aarch64 | arm64) architecture=arm64 ;;
  *)
    echo "Unsupported architecture: $(uname -m)" >&2
    exit 1
    ;;
esac

download=$(mktemp)
trap 'rm -f "$download"' EXIT
curl -fsSL -o "$download" \
  "https://github.com/$repository/releases/latest/download/pif-server-linux-$architecture"
install -m 0755 "$download" "$binary"

cat >"$service" <<UNIT
[Unit]
Description=PIF Online server
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=$binary -addr :$port
DynamicUser=yes
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
Restart=on-failure
RestartSec=2

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable pif-server >/dev/null
systemctl restart pif-server

if command -v ufw >/dev/null && ufw status | grep -q "Status: active"; then
  ufw allow "$port/tcp" >/dev/null
fi

echo "PIF Online server running on port $port."
echo "Players add this machine's public address in the game: Pause > Multiplayer > Add a server."
echo "If your provider has its own firewall, open TCP port $port there too."
