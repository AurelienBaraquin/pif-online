#!/usr/bin/env bash
# Runs an engine test on Windows from WSL against a locally built server.
# usage: run.sh client|game|battle|codec|interaction|network <game-directory> <windows-staging-directory>
set -euo pipefail

mode=$1
game=$2
stage=$3
root=$(cd "$(dirname "$0")/../.." && pwd)
overlay="$root/client/998_Multiplayer"
timeout_ms=280000

mapfile -t overlay_core < <(find "$overlay/core" "$overlay/features" -name '*.rb' | sort)

stage_runtime() {
  mkdir -p "$stage/Data"
  cp "$game"/InfiniteFusion2.exe "$game"/x64-msvcrt-ruby310.dll "$game"/x64-msvcrt-ruby300.dll \
    "$game"/zlib1.dll "$game"/RGSS104E.dll "$game"/mkxp.json "$game"/Game.ini "$stage/"
}

stage_full_game() {
  mkdir -p "$stage"
  (cd "$game" && tar --exclude=.git --exclude=.claude-flow -cf - .) | (cd "$stage" && tar -xf -)
}

prepare_client() {
  stage_runtime
  python3 -I "$root/tools/engine-test/pack_scripts.py" "$stage/Data/Scripts.rxdata" \
    "${overlay_core[@]}" "$root/tools/engine-test/client_test.rb"
}

# usage: stage_game_with_test <test-file>...
stage_game_with_test() {
  [ -f "$stage/InfiniteFusion2.exe" ] && [ -d "$stage/Graphics" ] || stage_full_game
  rm -rf "$stage/Data/Scripts/998_Multiplayer" "$stage/Data/Scripts/998_MultiplayerTest"
  cp -r "$overlay" "$stage/Data/Scripts/"
  mkdir -p "$stage/Data/Scripts/998_MultiplayerTest"
  for test_file in "$@"; do
    cp "$root/tools/engine-test/$test_file" "$stage/Data/Scripts/998_MultiplayerTest/"
  done
  printf '{"host":"127.0.0.1","port":7777}\n' >"$stage/multiplayer.json"
}

prepare_game() {
  stage_game_with_test game_test.rb
}

prepare_battle() {
  stage_game_with_test battle_determinism_test.rb
}

# The codec test reuses the duel harness of the determinism test and replaces
# its entry point, so it must load second.
prepare_interaction() {
  stage_game_with_test battle_determinism_test.rb interaction_test.rb
}

prepare_network() {
  stage_game_with_test battle_determinism_test.rb network_duel_test.rb
}

prepare_codec() {
  stage_game_with_test battle_determinism_test.rb party_codec_test.rb
}

"prepare_$mode"
# The game executes every file under Data/Scripts, and tool hooks leave folders there.
find "$stage" -name .claude-flow -type d -prune -exec rm -r {} +
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
