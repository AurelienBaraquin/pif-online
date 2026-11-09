#!/usr/bin/env bash
# Builds every file of a release into the given directory.
# usage: build.sh <output-directory>
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
mkdir -p "$1"
output=$(cd "$1" && pwd)

build_server() {
  (cd "$root/server" && CGO_ENABLED=0 GOOS=$1 GOARCH=$2 \
    go build -trimpath -ldflags "-s -w" -o "$output/$3" ./cmd/pif-server)
}

build_server windows amd64 pif-server-windows-amd64.exe
build_server linux amd64 pif-server-linux-amd64
build_server linux arm64 pif-server-linux-arm64

# Tracked files only: tools leave untracked folders here, and the game executes
# everything found under Data/Scripts.
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/Data/Scripts"
git -C "$root" archive HEAD client/998_Multiplayer | tar -xf - -C "$stage"
mv "$stage/client/998_Multiplayer" "$stage/Data/Scripts/"
rm -r "$stage/client"
rm -f "$output/PIF-Online-Client.zip"
(cd "$stage" && zip -qr "$output/PIF-Online-Client.zip" Data)
