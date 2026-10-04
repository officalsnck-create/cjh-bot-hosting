#!/usr/bin/env bash
set -Eeuo pipefail

# CJH Bot Hosting - legacy entrypoint kept only as a compatibility wrapper.
# Always launches the current v5 installer so the old v4 menu cannot appear.

VERSION="5.0.0"
BASE_URL="https://raw.githubusercontent.com/officalsnck-create/cjh-bot-hosting/main"
INSTALLER="/tmp/cjh-bot-hosting-v${VERSION}.sh"

if ! command -v curl >/dev/null 2>&1; then
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    apt-get update -y >/dev/null
    apt-get install -y curl ca-certificates >/dev/null
  elif command -v sudo >/dev/null 2>&1; then
    sudo apt-get update -y >/dev/null
    sudo apt-get install -y curl ca-certificates >/dev/null
  else
    printf 'CJH requires curl. Install curl or run this installer as root.\n' >&2
    exit 1
  fi
fi

curl -fsSL "${BASE_URL}/premium-installer-v5.sh" -o "$INSTALLER"
chmod 700 "$INSTALLER"
exec bash "$INSTALLER" "$@"
