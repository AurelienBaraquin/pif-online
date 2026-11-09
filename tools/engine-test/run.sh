#!/usr/bin/env bash
# Runs an engine test on Windows from WSL against a locally built server.
# usage: run.sh client|game|battle|codec|interaction|network|rules|robust|two|flip <game-directory> <windows-staging-directory>
set -euo pipefail

# Engine tests share the server port and the desktop: run one at a time.
exec 9>/tmp/pif-online-engine-test.lock
flock 9

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

prepare_rules() {
  stage_game_with_test battle_determinism_test.rb network_duel_test.rb rules_duel_test.rb
}

prepare_robust() {
  timeout_ms=570000
  stage_game_with_test battle_determinism_test.rb duel_robustness_test.rb
}

prepare_flip() {
  stage_game_with_test battle_determinism_test.rb display_flip_test.rb
}

prepare_two() {
  stage_game_with_test battle_determinism_test.rb network_duel_test.rb two_process_duel_test.rb
  timeout_ms=480000
}

"prepare_$mode"
# The game executes every file under Data/Scripts, and tool hooks leave folders there.
find "$stage" -name .claude-flow -type d -prune -exec rm -r {} +
rm -f "$stage"/test_result*.txt "$stage"/multiplayer*.log

server_binary=$(mktemp)
(cd "$root/server" && go build -o "$server_binary" ./cmd/pif-server)
# Restarts the server whenever a test creates the flag file.
serve() {
  local flag="$stage/restart_server" pid
  rm -f "$flag"
  trap 'kill "$pid" 2>/dev/null; exit 0' TERM EXIT
  while true; do
    "$server_binary" -addr 127.0.0.1:7777 &
    pid=$!
    until [ -e "$flag" ]; do sleep 0.2; done
    rm -f "$flag"
    kill "$pid"
    wait "$pid" 2>/dev/null || true
  done
}

serve &
server_pid=$!
trap 'kill "$server_pid" 2>/dev/null || true; rm -f "$server_binary"' EXIT
sleep 0.5

windows_stage=$(wslpath -w "$stage")

# usage: launch <role>... Starts one process per role, killing by PID on timeout.
# An empty role runs a single process with no role.
launch() {
  local roles
  roles=$(printf "'%s'," "$@")
  powershell.exe -NoProfile -Command "\$all=@(); foreach(\$r in @(${roles%,})){\$env:PIF_TEST_ROLE=\$r; \$all+=,@(\$r,(Start-Process -FilePath '$windows_stage\\InfiniteFusion2.exe' -WorkingDirectory '$windows_stage' -PassThru))}; \$deadline=(Get-Date).AddMilliseconds($timeout_ms); foreach(\$e in \$all){\$left=[Math]::Max(0,[int](\$deadline-(Get-Date)).TotalMilliseconds); if(\$e[1].WaitForExit(\$left)){\$e[0]+' exit='+\$e[1].ExitCode}else{Stop-Process -Id \$e[1].Id -Force; \$e[0]+' TIMEOUT'}}" | tr -d '\r'
}

# usage: show_results <suffix>
show_results() {
  tr -d '\r' <"$stage/test_result$1.txt"
  if [ -f "$stage/multiplayer$1.log" ]; then
    echo "--- multiplayer$1.log"
    tr -d '\r' <"$stage/multiplayer$1.log"
  fi
}

if [ "$mode" = two ]; then
  launch red blue
  status=0
  for role in red blue; do
    echo "=== $role"
    show_results "_$role" || status=1
    tail -n 1 "$stage/test_result_$role.txt" | grep -q '^PASS' || status=1
  done
  exit "$status"
fi

launch ''
show_results ''
tail -n 1 "$stage/test_result.txt" | grep -q '^PASS'
