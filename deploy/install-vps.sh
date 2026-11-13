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

release=https://github.com/$repository/releases/latest/download
name=pif-server-linux-$architecture
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
curl -fsSL -o "$work/$name" "$release/$name"
curl -fsSL -o "$work/SHA256SUMS" "$release/SHA256SUMS"
if ! (cd "$work" && grep " $name\$" SHA256SUMS | sha256sum -c --quiet -); then
  echo "The downloaded server is corrupted (checksum mismatch). Run the script again." >&2
  exit 1
fi
install -m 0755 "$work/$name" "$binary"

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
