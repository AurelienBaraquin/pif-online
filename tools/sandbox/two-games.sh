#!/usr/bin/env bash
# Two playable copies of the game on one Windows PC, connected to a local
# server, to try PIF Online by hand without a second computer. Each copy keeps
# its saves in its own folder (%APPDATA%\pif-online-a or -b), never in the
# player's real ones.
# usage:
#   two-games.sh setup <game-directory> <windows-directory> [save-file-a] [save-file-b]
#   two-games.sh update <windows-directory>   copies the current overlay into both
#   two-games.sh start <windows-directory>    starts the server and both games
#   two-games.sh stop <windows-directory>     stops what start started
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
copies=(a b)

install_overlay() {
  local copy=$1
  rm -rf "$copy/Data/Scripts/998_Multiplayer"
  cp -r "$root/client/998_Multiplayer" "$copy/Data/Scripts/"
  # The game runs every file under Data/Scripts; tools leave folders here.
  find "$copy/Data/Scripts/998_Multiplayer" -name .claude-flow -type d -prune -exec rm -r {} +
}

setup() {
  local game=$1 dir=$2 saves=("${@:3}")
  for index in "${!copies[@]}"; do
    local name=${copies[$index]} copy="$dir/${copies[$index]}"
    echo "copying the game to $copy"
    mkdir -p "$copy"
    (cd "$game" && tar --exclude=./.git --exclude=.claude-flow -cf - .) | tar -xf - -C "$copy"
    install_overlay "$copy"
    sed -i "s|^\( *\)// \"dataPathApp\": \"mygame\",|\1\"dataPathApp\": \"pif-online-$name\",|" "$copy/mkxp.json"
    grep -q "\"dataPathApp\": \"pif-online-$name\"" "$copy/mkxp.json" || { echo "cannot isolate saves in $copy" >&2; exit 1; }
    printf '{"servers":[{"host":"127.0.0.1","port":7777}],"active":{"host":"127.0.0.1","port":7777}}\n' >"$copy/multiplayer.json"
    local save=${saves[$index]:-}
    if [ -n "$save" ]; then
      local data
      data="$(wslpath "$(powershell.exe -NoProfile -Command '$env:APPDATA' | tr -d '\r')")/pif-online-$name"
      mkdir -p "$data"
      cp "$save" "$data/File A.rxdata"
    fi
  done
  (cd "$root/server" && GOOS=windows GOARCH=amd64 go build -o "$dir/pif-server.exe" ./cmd/pif-server)
  echo "ready: two-games.sh start $dir"
}

start() {
  local dir=$1 windows
  windows=$(wslpath -w "$dir")
  powershell.exe -NoProfile -Command "
    \$ids = @((Start-Process -FilePath '$windows\\pif-server.exe' -ArgumentList '-addr','127.0.0.1:7777' -PassThru).Id)
    foreach (\$copy in 'a','b') {
      \$ids += (Start-Process -FilePath \"$windows\\\$copy\\InfiniteFusion2.exe\" -WorkingDirectory \"$windows\\\$copy\" -PassThru).Id
    }
    \$ids -join ' '" | tr -d '\r' >"$dir/pids"
  echo "started (process ids $(cat "$dir/pids")); logs: $dir/{a,b}/multiplayer.log"
}

# Stops only the processes start launched, never other copies of the game.
stop() {
  local dir=$1 windows
  [ -f "$dir/pids" ] || { echo "nothing started from $dir"; return; }
  windows=$(wslpath -w "$dir")
  for id in $(cat "$dir/pids"); do
    powershell.exe -NoProfile -Command "
      \$p = Get-Process -Id $id -ErrorAction SilentlyContinue
      if (\$p -and \$p.Path -like '$windows\\*') { Stop-Process -Id $id -Force }" | tr -d '\r'
  done
  rm -f "$dir/pids"
  echo "stopped"
}

case ${1:-} in
  setup) setup "${@:2}" ;;
  update) for copy in "${copies[@]}"; do install_overlay "$2/$copy"; done; echo "overlay updated" ;;
  start) start "$2" ;;
  stop) stop "$2" ;;
  *)
    sed -n '2,12p' "$0"
    exit 2
    ;;
esac
