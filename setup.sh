#!/usr/bin/env bash
set -Eeuo pipefail

BASE_URL="https://raw.githubusercontent.com/officalsnck-create/cjh-bot-hosting/main"
TARGET="/tmp/cjh-bot-hosting-installer.sh"

if ! command -v curl >/dev/null 2>&1; then
  if [ "$(id -u)" -eq 0 ]; then
    apt-get update -y >/dev/null
    apt-get install -y curl ca-certificates >/dev/null
  elif command -v sudo >/dev/null 2>&1; then
    sudo apt-get update -y >/dev/null
    sudo apt-get install -y curl ca-certificates >/dev/null
  else
    printf '%s\n' 'CJH requires curl. Install curl and run this command again.' >&2
    exit 1
  fi
fi

curl -fL --retry 3 --retry-delay 1 "${BASE_URL}/premium-installer-v5.sh" -o "$TARGET"
chmod 700 "$TARGET"

if ! bash -n "$TARGET"; then
  printf '%s\n' 'CJH installer validation failed. The remote installer was not executed.' >&2
  rm -f "$TARGET"
  exit 1
fi

exec bash "$TARGET" "$@"
