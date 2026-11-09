#!/usr/bin/env bash
# Runs an engine test on Windows from WSL against a locally built server.
# usage: run.sh client|game <game-directory> <windows-staging-directory>
set -euo pipefail

mode=$1
game=$2
stage=$3
root=$(cd "$(dirname "$0")/../.." && pwd)
overlay="$root/client/998_Multiplayer"
timeout_ms=120000

mapfile -t overlay_core < <(find "$overlay/core" "$overlay/features" -name '*.rb' | sort)

stage_runtime() {
  mkdir -p "$stage/Data"
  cp "$game"/InfiniteFusion2.exe "$game"/x64-msvcrt-ruby310.dll "$game"/x64-msvcrt-ruby300.dll \
    "$game"/zlib1.dll "$game"/RGSS104E.dll "$game"/mkxp.json "$game"/Game.ini "$stage/"
}

stage_full_game() {
  mkdir -p "$stage"
  (cd "$game" && tar --exclude=.git -cf - .) | (cd "$stage" && tar -xf -)
}

prepare_client() {
  stage_runtime
  python3 -I "$root/tools/engine-test/pack_scripts.py" "$stage/Data/Scripts.rxdata" \
    "${overlay_core[@]}" "$root/tools/engine-test/client_test.rb"
}

prepare_game() {
  [ -f "$stage/InfiniteFusion2.exe" ] && [ -d "$stage/Graphics" ] || stage_full_game
  rm -rf "$stage/Data/Scripts/998_Multiplayer" "$stage/Data/Scripts/998_MultiplayerTest"
  cp -r "$overlay" "$stage/Data/Scripts/"
  mkdir -p "$stage/Data/Scripts/998_MultiplayerTest"
  cp "$root/tools/engine-test/game_test.rb" "$stage/Data/Scripts/998_MultiplayerTest/"
  printf '{"host":"127.0.0.1","port":7777}\n' >"$stage/multiplayer.json"
}

"prepare_$mode"
rm -f "$stage/test_result.txt" "$stage/multiplayer.log"

server_binary=$(mktemp)
(cd "$root/server" && go build -o "$server_binary" ./cmd/pif-server)
"$server_binary" -addr 127.0.0.1:7777 &
server_pid=$!
trap 'kill "$server_pid" 2>/dev/null || true; rm -f "$server_binary"' EXIT
sleep 0.5

windows_stage=$(wslpath -w "$stage")
powershell.exe -NoProfile -Command "\$p=Start-Process -FilePath '$windows_stage\\InfiniteFusion2.exe' -WorkingDirectory '$windows_stage' -PassThru; if(-not \$p.WaitForExit($timeout_ms)){Stop-Process -Id \$p.Id -Force; 'TIMEOUT'}else{'exit='+\$p.ExitCode}" | tr -d '\r'

tr -d '\r' <"$stage/test_result.txt"
[ -f "$stage/multiplayer.log" ] && { echo '--- multiplayer.log'; tr -d '\r' <"$stage/multiplayer.log"; }
tail -n 1 "$stage/test_result.txt" | grep -q '^PASS'
