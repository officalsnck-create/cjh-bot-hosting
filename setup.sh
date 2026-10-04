#!/usr/bin/env bash
set -Eeuo pipefail

VERSION="7.0.0"
ROOT="${CJH_HOME:-$HOME/cjh-bots}"
BASE_URL="https://raw.githubusercontent.com/officalsnck-create/cjh-bot-hosting/main"
BOT_URL="${BASE_URL}/bot-template.js"
SUDO=""
if [ "$(id -u)" -ne 0 ]; then SUDO="sudo"; fi

RESET=$'\033[0m'; CYAN=$'\033[38;5;51m'; PURPLE=$'\033[38;5;141m'; PINK=$'\033[38;5;205m'; GREEN=$'\033[38;5;82m'; YELLOW=$'\033[38;5;220m'; WHITE=$'\033[1;97m'; DIM=$'\033[38;5;245m'; RED=$'\033[38;5;203m'
pause_menu(){ printf '\n%bPress ENTER to continue%b ' "$DIM" "$RESET"; read -r _; }
header(){ printf '\033[2J\033[H'; printf '%b╭──────────────────────────────────────────────────────────────────────────────╮%b\n' "$PURPLE" "$RESET"; printf '%b│%b  %bCJH BOT HOSTING%b  %bv%s • REAL DISCORD CONTROL%b\n' "$PURPLE" "$RESET" "$WHITE" "$RESET" "$DIM" "$VERSION" "$RESET"; printf '%b╰──────────────────────────────────────────────────────────────────────────────╯%b\n\n' "$PURPLE" "$RESET"; }
need(){ command -v "$1" >/dev/null 2>&1 && return 0; if ! $SUDO apt-get update -y >/dev/null || ! $SUDO apt-get install -y "$2" >/dev/null; then printf '%bFailed to install %s.%b\n' "$RED" "$2" "$RESET"; return 1; fi; }
setup_runtime(){ need curl curl || return 1; need ca-certificates ca-certificates || return 1; if ! command -v node >/dev/null 2>&1; then curl -fsSL https://deb.nodesource.com/setup_20.x | $SUDO -E bash - >/dev/null; $SUDO apt-get install -y nodejs >/dev/null; fi; command -v node >/dev/null 2>&1 || { printf '%bNode.js installation failed.%b\n' "$RED" "$RESET"; return 1; }; command -v npm >/dev/null 2>&1 || { printf '%bnpm installation failed.%b\n' "$RED" "$RESET"; return 1; }; if ! command -v pm2 >/dev/null 2>&1; then $SUDO npm install -g pm2 >/dev/null; fi; command -v pm2 >/dev/null 2>&1 || { printf '%bPM2 installation failed.%b\n' "$RED" "$RESET"; return 1; }; mkdir -p "$ROOT"; chmod 700 "$ROOT"; }
slug(){ printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9_-]+/-/g;s/^-+//;s/-+$//'; }
list_bots(){ mapfile -t bots < <(find "$ROOT" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort); }
choose_bot(){ list_bots; [ "${#bots[@]}" -gt 0 ] || { printf '%bNo bots installed.%b\n' "$YELLOW" "$RESET"; return 1; }; local i=1 bot; for bot in "${bots[@]}"; do printf '  %b[%02d]%b %s\n' "$CYAN" "$i" "$RESET" "$bot"; i=$((i+1)); done; printf '\n%bSelect bot:%b ' "$WHITE" "$RESET"; read -r n; [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le "${#bots[@]}" ] || return 1; SELECTED="${bots[$((n-1))]}"; }
validate_bot(){ node --check "$1"; }
install_dependencies(){ (cd "$1" && npm install --omit=dev --no-audit --no-fund >/dev/null); }
create_bot(){ header; printf '%bDEPLOY REAL DISCORD BOT%b\n\n' "$CYAN" "$RESET"; printf '%bBot name%b: ' "$DIM" "$RESET"; read -r input; local bot_name dir token client_id; bot_name="$(slug "${input:-cjh-bot}")"; [ -n "$bot_name" ] || bot_name="cjh-bot"; dir="$ROOT/$bot_name"; [ ! -e "$dir" ] || { printf '%bBot already exists.%b\n' "$YELLOW" "$RESET"; pause_menu; return; }; printf '%bDiscord bot token%b: ' "$DIM" "$RESET"; read -r -s token; printf '\n'; printf '%bDiscord application Client ID%b: ' "$DIM" "$RESET"; read -r client_id; printf '\n'; [ -n "$token" ] && [ -n "$client_id" ] || { printf '%bToken and Client ID are required.%b\n' "$YELLOW" "$RESET"; pause_menu; return; }; mkdir -p "$dir"; chmod 700 "$dir"; umask 077; printf 'BOT_TOKEN=%s\nCLIENT_ID=%s\n' "$token" "$client_id" > "$dir/.env"; chmod 600 "$dir/.env"; printf '%bDownloading verified bot source...%b\n' "$DIM" "$RESET"; if ! curl -fL --retry 3 --retry-delay 1 "$BOT_URL" -o "$dir/bot.js"; then rm -rf "$dir"; printf '%bSource download failed; installation rolled back.%b\n' "$RED" "$RESET"; pause_menu; return; fi; cat > "$dir/package.json" <<'JSON'
{
  "name": "cjh-discord-bot",
  "version": "7.0.0",
  "private": true,
  "main": "bot.js",
  "scripts": {"start": "node bot.js"},
  "dependencies": {"discord.js": "^14.27.0"}
}
JSON
if ! validate_bot "$dir/bot.js"; then rm -rf "$dir"; printf '%bBot source failed Node syntax validation; rolled back.%b\n' "$RED" "$RESET"; pause_menu; return; fi; printf '%bInstalling Discord.js...%b\n' "$DIM" "$RESET"; if ! install_dependencies "$dir"; then rm -rf "$dir"; printf '%bDependency installation failed; rolled back.%b\n' "$RED" "$RESET"; pause_menu; return; fi; if pm2 start "$dir/bot.js" --name "$bot_name" --cwd "$dir" --time; then pm2 save >/dev/null 2>&1 || true; printf '%b✓ REAL Discord bot started: %s%b\n' "$GREEN" "$bot_name" "$RESET"; else printf '%bBot did not start. Use Live Logs.%b\n' "$RED" "$RESET"; fi; pause_menu; }
manage(){ local action="$1"; header; printf '%b%s BOT%b\n\n' "$CYAN" "$action" "$RESET"; choose_bot || { pause_menu; return; }; case "$action" in START) pm2 start "$SELECTED" ;; STOP) pm2 stop "$SELECTED" ;; RESTART) pm2 restart "$SELECTED" ;; LOGS) pm2 logs "$SELECTED" --lines 150 --nostream ;; esac; pm2 save >/dev/null 2>&1 || true; pause_menu; }
update_bot(){ header; printf '%bUPDATE BOT%b\n\n' "$CYAN" "$RESET"; choose_bot || { pause_menu; return; }; local dir="$ROOT/$SELECTED" was_online=0; pm2 describe "$SELECTED" >/dev/null 2>&1 && was_online=1; pm2 stop "$SELECTED" >/dev/null 2>&1 || true; if curl -fL --retry 3 --retry-delay 1 "$BOT_URL" -o "$dir/bot.js" && validate_bot "$dir/bot.js" && install_dependencies "$dir"; then if [ "$was_online" -eq 1 ]; then pm2 restart "$SELECTED"; else pm2 start "$dir/bot.js" --name "$SELECTED" --cwd "$dir" --time; fi; pm2 save >/dev/null 2>&1 || true; printf '%b✓ Bot updated successfully.%b\n' "$GREEN" "$RESET"; else printf '%bUpdate failed. The downloaded source did not pass validation.%b\n' "$RED" "$RESET"; fi; pause_menu; }
remove_bot(){ header; printf '%bREMOVE BOT%b\n\n' "$RED" "$RESET"; choose_bot || { pause_menu; return; }; printf '%bType REMOVE to permanently delete %s:%b ' "$YELLOW" "$SELECTED" "$RESET"; read -r confirm; [ "$confirm" = "REMOVE" ] || { printf '%bCancelled.%b\n' "$DIM" "$RESET"; pause_menu; return; }; pm2 delete "$SELECTED" >/dev/null 2>&1 || true; rm -rf -- "$ROOT/$SELECTED"; pm2 save >/dev/null 2>&1 || true; printf '%b✓ Bot removed.%b\n' "$GREEN" "$RESET"; pause_menu; }
status(){ header; printf '%bRUNTIME%b\nNode: %s\nNPM:  %s\nPM2:  %s\n\n' "$CYAN" "$RESET" "$(node -v 2>/dev/null || echo unavailable)" "$(npm -v 2>/dev/null || echo unavailable)" "$(pm2 -v 2>/dev/null || echo unavailable)"; pm2 list; pause_menu; }
menu(){ header; printf '%b  01%b  Deploy new bot\n' "$CYAN" "$RESET"; printf '%b  02%b  Start bot\n' "$GREEN" "$RESET"; printf '%b  03%b  Stop bot\n' "$YELLOW" "$RESET"; printf '%b  04%b  Restart bot\n' "$PURPLE" "$RESET"; printf '%b  05%b  Live logs\n' "$PINK" "$RESET"; printf '%b  06%b  Update bot\n' "$CYAN" "$RESET"; printf '%b  07%b  Remove bot\n' "$RED" "$RESET"; printf '%b  08%b  System / PM2 status\n' "$WHITE" "$RESET"; printf '%b  Q %b Quit\n\n' "$DIM" "$RESET"; printf '%bSelect › %b' "$WHITE" "$CYAN"; read -r choice; case "$choice" in 1|01) create_bot ;; 2|02) manage START ;; 3|03) manage STOP ;; 4|04) manage RESTART ;; 5|05) manage LOGS ;; 6|06) update_bot ;; 7|07) remove_bot ;; 8|08) status ;; q|Q) exit 0 ;; *) printf '%bInvalid option.%b\n' "$YELLOW" "$RESET"; sleep 1 ;; esac; }
setup_runtime || exit 1
while :; do menu; done
