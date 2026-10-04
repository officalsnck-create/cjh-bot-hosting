#!/usr/bin/env bash
set -Eeuo pipefail

VERSION="6.0.0"
ROOT="${CJH_HOME:-$HOME/cjh-bots}"
BASE_URL="https://raw.githubusercontent.com/officalsnck-create/cjh-bot-hosting/main"
SELF_URL="${BASE_URL}/setup.sh"
BOT_URL="${BASE_URL}/bot-template.js"
SUDO=""
if [ "$(id -u)" -ne 0 ]; then SUDO="sudo"; fi

RESET=$'\033[0m'
CYAN=$'\033[38;5;51m'
PURPLE=$'\033[38;5;141m'
PINK=$'\033[38;5;205m'
GREEN=$'\033[38;5;82m'
YELLOW=$'\033[38;5;220m'
WHITE=$'\033[1;97m'
DIM=$'\033[38;5;245m'
RED=$'\033[38;5;203m'

pause_menu() {
  printf '\n%bPress ENTER to continue%b ' "$DIM" "$RESET"
  read -r _
}

header() {
  printf '\033[2J\033[H'
  printf '%b╭──────────────────────────────────────────────────────────────────────────────╮%b\n' "$PURPLE" "$RESET"
  printf '%b│%b  %bCJH BOT HOSTING%b  %bAurora Control Center • v%s%b\n' "$PURPLE" "$RESET" "$WHITE" "$RESET" "$DIM" "$VERSION" "$RESET"
  printf '%b╰──────────────────────────────────────────────────────────────────────────────╯%b\n\n' "$PURPLE" "$RESET"
}

need() {
  if command -v "$1" >/dev/null 2>&1; then return 0; fi
  $SUDO apt-get update -y >/dev/null
  $SUDO apt-get install -y "$2" >/dev/null
}

setup_runtime() {
  need curl curl
  need ca-certificates ca-certificates
  if ! command -v node >/dev/null 2>&1; then
    curl -fsSL https://deb.nodesource.com/setup_20.x | $SUDO -E bash - >/dev/null
    $SUDO apt-get install -y nodejs >/dev/null
  fi
  if ! command -v npm >/dev/null 2>&1; then
    printf '%bNode.js/npm installation failed.%b\n' "$RED" "$RESET"
    return 1
  fi
  if ! command -v pm2 >/dev/null 2>&1; then
    $SUDO npm install -g pm2 >/dev/null
  fi
  mkdir -p "$ROOT"
  chmod 700 "$ROOT"
}

slug() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9_-]+/-/g;s/^-+//;s/-+$//'
}

create_bot() {
  header
  printf '%bDEPLOY REAL DISCORD BOT%b\n\n' "$CYAN" "$RESET"
  printf '%bBot name%b: ' "$DIM" "$RESET"
  read -r input
  local bot_name
  bot_name="$(slug "${input:-cjh-bot}")"
  [ -n "$bot_name" ] || bot_name="cjh-bot"
  local dir="$ROOT/$bot_name"
  if [ -e "$dir" ]; then
    printf '%bBot already exists.%b\n' "$YELLOW" "$RESET"
    pause_menu
    return
  fi
  printf '%bDiscord bot token%b: ' "$DIM" "$RESET"
  read -r -s token
  printf '\n%bDiscord application Client ID%b: ' "$DIM" "$RESET"
  read -r client_id
  printf '\n'
  if [ -z "$token" ] || [ -z "$client_id" ]; then
    printf '%bToken and Client ID are required.%b\n' "$YELLOW" "$RESET"
    pause_menu
    return
  fi

  mkdir -p "$dir"
  chmod 700 "$dir"
  umask 077
  printf 'BOT_TOKEN=%s\nCLIENT_ID=%s\n' "$token" "$client_id" > "$dir/.env"
  chmod 600 "$dir/.env"

  printf '%bDownloading verified bot source...%b\n' "$DIM" "$RESET"
  if ! curl -fL --retry 3 --retry-delay 1 "$BOT_URL" -o "$dir/bot.js"; then
    rm -rf "$dir"
    printf '%bCould not download bot source; nothing was left installed.%b\n' "$RED" "$RESET"
    pause_menu
    return
  fi

  cat > "$dir/package.json" <<'JSON'
{
  "name": "cjh-discord-bot",
  "version": "6.0.0",
  "private": true,
  "main": "bot.js",
  "scripts": {"start": "node bot.js"},
  "dependencies": {"discord.js": "^14.27.0"}
}
JSON

  if ! node --check "$dir/bot.js"; then
    rm -rf "$dir"
    printf '%bDownloaded bot source failed Node syntax validation; installation stopped.%b\n' "$RED" "$RESET"
    pause_menu
    return
  fi

  printf '%bInstalling Discord.js...%b\n' "$DIM" "$RESET"
  if ! (cd "$dir" && npm install --omit=dev --no-audit --no-fund); then
    rm -rf "$dir"
    printf '%bDependency installation failed; incomplete bot removed.%b\n' "$RED" "$RESET"
    pause_menu
    return
  fi

  if pm2 start "$dir/bot.js" --name "$bot_name" --cwd "$dir" --time; then
    pm2 save >/dev/null 2>&1 || true
    printf '%b✓ REAL Discord bot started: %s%b\n' "$GREEN" "$bot_name" "$RESET"
    printf '%bCommands are registered through Discord API at startup.%b\n' "$CYAN" "$RESET"
  else
    printf '%bBot failed to start. Choose Live Logs to inspect the real error.%b\n' "$RED" "$RESET"
  fi
  pause_menu
}

list_bots() {
  mapfile -t bots < <(find "$ROOT" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort)
}

choose_bot() {
  list_bots
  if [ "${#bots[@]}" -eq 0 ]; then
    printf '%bNo bots installed.%b\n' "$YELLOW" "$RESET"
    return 1
  fi
  local i=1 bot
  for bot in "${bots[@]}"; do
    printf '  %b[%02d]%b %-28s\n' "$CYAN" "$i" "$RESET" "$bot"
    i=$((i + 1))
  done
  printf '\n%bSelect bot:%b ' "$WHITE" "$RESET"
  read -r n
  [[ "$n" =~ ^[0-9]+$ ]] || return 1
  [ "$n" -ge 1 ] && [ "$n" -le "${#bots[@]}" ] || return 1
  SELECTED="${bots[$((n - 1))]}"
}

manage() {
  local action="$1"
  header
  printf '%b%s BOT%b\n\n' "$CYAN" "$action" "$RESET"
  if ! choose_bot; then pause_menu; return; fi
  case "$action" in
    START) pm2 start "$SELECTED" ;;
    STOP) pm2 stop "$SELECTED" ;;
    RESTART) pm2 restart "$SELECTED" ;;
    LOGS) pm2 logs "$SELECTED" --lines 100 --nostream ;;
  esac
  pm2 save >/dev/null 2>&1 || true
  pause_menu
}

status() {
  header
  printf '%bNode%b   %s\n' "$CYAN" "$RESET" "$(node -v 2>/dev/null || echo unavailable)"
  printf '%bPM2%b    %s\n\n' "$CYAN" "$RESET" "$(pm2 -v 2>/dev/null || echo unavailable)"
  pm2 list
  pause_menu
}

menu() {
  header
  printf '%b  01%b  Deploy real Discord bot\n' "$CYAN" "$RESET"
  printf '%b  02%b  Start bot\n' "$GREEN" "$RESET"
  printf '%b  03%b  Stop bot\n' "$YELLOW" "$RESET"
  printf '%b  04%b  Restart bot\n' "$PURPLE" "$RESET"
  printf '%b  05%b  Live logs\n' "$PINK" "$RESET"
  printf '%b  06%b  System / PM2 status\n' "$CYAN" "$RESET"
  printf '%b  Q %b Quit\n\n' "$DIM" "$RESET"
  printf '%bSelect › %b' "$WHITE" "$CYAN"
  read -r choice
  case "$choice" in
    1|01) create_bot ;;
    2|02) manage START ;;
    3|03) manage STOP ;;
    4|04) manage RESTART ;;
    5|05) manage LOGS ;;
    6|06) status ;;
    q|Q) exit 0 ;;
    *) printf '%bInvalid option.%b\n' "$YELLOW" "$RESET"; sleep 1 ;;
  esac
}

setup_runtime || exit 1
while :; do menu; done
