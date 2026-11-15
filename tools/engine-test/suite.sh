#!/usr/bin/env bash
# Runs one category of tests and prints a summary. Categories, fastest first:
#   quick  server unit tests, client core, Multiplayer menu      (~1 min)
#   world  overworld presence: one game, then two real games     (~1 min)
#   duel   duel flow and screens: interaction, network, rules,
#          side-one display                                      (~6 min)
#   deep   long soak tests: determinism, party codec, robustness,
#          two-process duels                                     (~25 min)
#   all    every category
# usage: suite.sh <category> <game-directory> <windows-staging-directory>
# PIF_TEST_SAVES, when set, holds red.rxdata and blue.rxdata for the presence test.
set -euo pipefail

category=$1
game=$2
stage=$3
here=$(cd "$(dirname "$0")" && pwd)

case $category in
  quick) tests=(server client menu) ;;
  world) tests=(game presence) ;;
  duel) tests=(interaction network rules flip) ;;
  deep) tests=(battle codec robust two) ;;
  all) tests=(server client menu game presence interaction network rules flip battle codec robust two) ;;
  *)
    echo "unknown category: $category (quick, world, duel, deep, all)" >&2
    exit 2
    ;;
esac

run_test() {
  case $1 in
    server) (cd "$here/../../server" && go vet ./... && go test -race ./...) ;;
    # The client test packs its own minimal runtime: keep it out of the game stage.
    client) "$here/run.sh" client "$game" "$stage-client" ;;
    *) "$here/run.sh" "$1" "$game" "$stage" ;;
  esac
}

summary=()
failed=0
for test in "${tests[@]}"; do
  echo "=== $test"
  started=$SECONDS
  if run_test "$test" >"$stage.$test.log" 2>&1; then
    verdict=PASS
  else
    verdict=FAIL
    failed=1
    tail -n 25 "$stage.$test.log"
  fi
  summary+=("$(printf '%-12s %s %4ds' "$test" "$verdict" $((SECONDS - started)))")
done

echo "=== summary ($category), full logs in $stage.<test>.log"
printf '%s\n' "${summary[@]}"
exit "$failed"
