#!/usr/bin/env bash
set -Eeuo pipefail
VERSION="8.0.5"
ROOT="${CJH_HOME:-$HOME/cjh-bots}"
BASE_URL="https://raw.githubusercontent.com/officalsnck-create/cjh-bot-hosting/main"
BOT_URL="${BASE_URL}/bot.py"
REQ_URL="${BASE_URL}/requirements.txt"
SUDO=""; [ "$(id -u)" -eq 0 ] || SUDO="sudo"
RESET=$'\033[0m'; CYAN=$'\033[38;5;51m'; PURPLE=$'\033[38;5;141m'; PINK=$'\033[38;5;205m'; GREEN=$'\033[38;5;82m'; YELLOW=$'\033[38;5;220m'; WHITE=$'\033[1;97m'; DIM=$'\033[38;5;245m'; RED=$'\033[38;5;203m'
pause_menu(){ printf '\n%bPress ENTER to continue%b ' "$DIM" "$RESET"; read -r _; }
header(){ printf '\033[2J\033[H'; printf '%b╭──────────────────────────────────────────────────────────────────────────────╮%b\n' "$PURPLE" "$RESET"; printf '%b│%b  %bCJH BOT HOSTING%b  %bv%s • VPS CONTROL CENTER%b\n' "$PURPLE" "$RESET" "$WHITE" "$RESET" "$DIM" "$VERSION" "$RESET"; printf '%b╰──────────────────────────────────────────────────────────────────────────────╯%b\n\n' "$PURPLE" "$RESET"; }
apt_install(){
  local packages=("$@"); printf '%b• Installing missing package(s):%b %s\n' "$CYAN" "$RESET" "${packages[*]}"
  if ! $SUDO apt-get update >/tmp/cjh-apt-update.log 2>&1; then printf '%b• APT update reported warnings; trying package installation anyway.%b\n' "$YELLOW" "$RESET"; fi
  if ! $SUDO apt-get install -y "${packages[@]}" >/tmp/cjh-apt-install.log 2>&1; then
    printf '%b✗ APT could not install:%b %s\n' "$RED" "$RESET" "${packages[*]}"; tail -30 /tmp/cjh-apt-install.log 2>/dev/null || true; return 1
  fi
  printf '%b✓ Installed:%b %s\n' "$GREEN" "$RESET" "${packages[*]}"
}
command_ready(){ command -v "$1" >/dev/null 2>&1; }
package_ready(){ dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed'; }
ensure_command(){ local cmd="$1" pkg="$2"; command_ready "$cmd" && return 0; apt_install "$pkg"; command_ready "$cmd"; }
ensure_package(){ local pkg="$1"; package_ready "$pkg" && return 0; apt_install "$pkg"; package_ready "$pkg"; }
setup_runtime(){
  printf '%b[1/4]%b Checking system runtime...\n' "$CYAN" "$RESET"
  ensure_command curl curl || return 1
  # ca-certificates is a package, not a command. The old installer incorrectly used command -v ca-certificates.
  ensure_package ca-certificates || return 1
  ensure_command python3 python3 || return 1
  printf '%b[2/4]%b Checking Python packages...\n' "$CYAN" "$RESET"
  ensure_package python3-venv || return 1
  ensure_package python3-pip || return 1
  ensure_package python3-full || true
  printf '%b[3/4]%b Checking LXC...\n' "$CYAN" "$RESET"
  ensure_command lxc lxc || return 1
  printf '%b[4/4]%b Checking Node.js / PM2...\n' "$CYAN" "$RESET"
  if ! command_ready node; then curl -fsSL https://deb.nodesource.com/setup_20.x | $SUDO -E bash - >/tmp/cjh-node-setup.log 2>&1 || { tail -30 /tmp/cjh-node-setup.log; return 1; }; apt_install nodejs || return 1; fi
  if ! command_ready npm; then ensure_command npm npm || return 1; fi
  if ! command_ready pm2; then printf '%b• Installing PM2...%b\n' "$CYAN" "$RESET"; $SUDO npm install -g pm2 || return 1; fi
  command_ready pm2 || return 1
  mkdir -p "$ROOT"; chmod 700 "$ROOT"; printf '%b✓ Runtime ready.%b\n\n' "$GREEN" "$RESET"
}
create_python_env(){
  local dir="$1"; rm -rf "$dir/venv"; mkdir -p "$dir"
  if ! python3 -m venv --without-pip "$dir/venv" >/tmp/cjh-venv.log 2>&1; then printf '%bPython venv creation failed:%b\n' "$RED" "$RESET"; cat /tmp/cjh-venv.log 2>/dev/null || true; return 1; fi
  printf '%b• Installing isolated pip...%b\n' "$CYAN" "$RESET"
  curl -fsSL --retry 3 --retry-delay 1 https://bootstrap.pypa.io/get-pip.py -o "$dir/get-pip.py" || return 1
  if ! "$dir/venv/bin/python" "$dir/get-pip.py" --disable-pip-version-check >/tmp/cjh-pip.log 2>&1; then printf '%bPip bootstrap failed:%b\n' "$RED" "$RESET"; tail -30 /tmp/cjh-pip.log 2>/dev/null || true; return 1; fi
  rm -f "$dir/get-pip.py"; "$dir/venv/bin/python" -m pip --version >/dev/null 2>&1
}
detect_host(){ local detected=""; detected="$(curl -4 -fsS --connect-timeout 5 https://api.ipify.org 2>/dev/null || true)"; if [[ ! "$detected" =~ ^[0-9.]+$ ]]; then detected="$(curl -4 -fsS --connect-timeout 5 https://ifconfig.me 2>/dev/null || true)"; fi; if [[ ! "$detected" =~ ^[0-9.]+$ ]]; then detected="$(hostname -I 2>/dev/null | awk '{print $1}')"; fi; printf '%s' "$detected"; }
list_bots(){ mapfile -t bots < <(find "$ROOT" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort); }
choose_bot(){ list_bots; [ "${#bots[@]}" -gt 0 ] || { printf '%bNo bots installed.%b\n' "$YELLOW" "$RESET"; return 1; }; local i=1 bot; for bot in "${bots[@]}"; do printf '  %b[%02d]%b %s\n' "$CYAN" "$i" "$RESET" "$bot"; i=$((i+1)); done; printf '\n%bSelect bot:%b ' "$WHITE" "$RESET"; read -r n; [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le "${#bots[@]}" ] || return 1; SELECTED="${bots[$((n-1))]}"; }
slug(){ printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9_-]+/-/g;s/^-+//;s/-+$//'; }
create_bot(){
 header; printf '%bDEPLOY REAL VPS + DISCORD BOT%b\n\n' "$CYAN" "$RESET"; setup_runtime || { printf '%bRuntime setup failed. Check /tmp/cjh-apt-install.log.%b\n' "$RED" "$RESET"; pause_menu; return; }
 printf '%bBot name%b [cjh-vps]: ' "$DIM" "$RESET"; read -r input; local name; name="$(slug "${input:-cjh-vps}")"; [ -n "$name" ] || name=cjh-vps; local dir="$ROOT/$name"; [ ! -e "$dir" ] || { printf '%bBot already exists.%b\n' "$YELLOW" "$RESET"; pause_menu; return; }
 printf '%bDiscord bot token%b: ' "$DIM" "$RESET"; read -r -s token; printf '\n'; printf '%bMain admin Discord user ID%b: ' "$DIM" "$RESET"; read -r admin_id; printf '%bSelf-deploy role ID%b [0=disabled]: ' "$DIM" "$RESET"; read -r deploy_role; deploy_role="${deploy_role:-0}"
 local detected_host; detected_host="$(detect_host)"; printf '%bPublic host IP/domain%b [%s]: ' "$DIM" "$RESET" "${detected_host:-not detected}"; read -r host_ip; host_ip="${host_ip:-$detected_host}"
 if [ -z "$host_ip" ]; then printf '%bCould not detect a public IP. Enter the VPS public IP/domain manually.%b\n' "$YELLOW" "$RESET"; pause_menu; return; fi
 if [ -z "$token" ] || [ -z "$admin_id" ]; then printf '%bToken and admin ID are required.%b\n' "$YELLOW" "$RESET"; pause_menu; return; fi
 if ! [[ "$admin_id" =~ ^[0-9]{17,20}$ ]]; then printf '%bInvalid Discord admin ID.%b\n' "$YELLOW" "$RESET"; pause_menu; return; fi
 mkdir -p "$dir"; chmod 700 "$dir"; umask 077
 printf '%b• Downloading bot source...%b\n' "$CYAN" "$RESET"; if ! curl -fL --retry 3 --retry-delay 1 "$BOT_URL" -o "$dir/bot.py"; then rm -rf "$dir"; printf '%bBot source download failed; rolled back.%b\n' "$RED" "$RESET"; pause_menu; return; fi
 printf '%b• Downloading dependencies...%b\n' "$CYAN" "$RESET"; if ! curl -fL --retry 3 --retry-delay 1 "$REQ_URL" -o "$dir/requirements.txt"; then rm -rf "$dir"; printf '%bDependency file download failed; rolled back.%b\n' "$RED" "$RESET"; pause_menu; return; fi
 python3 -m py_compile "$dir/bot.py" || { rm -rf "$dir"; printf '%bPython syntax validation failed; rolled back.%b\n' "$RED" "$RESET"; pause_menu; return; }
 cat > "$dir/.env" <<EOF
DISCORD_TOKEN=$token
BOT_NAME=$name
PREFIX=!
YOUR_SERVER_IP=$host_ip
MAIN_ADMIN_ID=$admin_id
VPS_USER_ROLE_ID=0
DEFAULT_STORAGE_POOL=default
DEFAULT_VPS_EXPIRATION_DAYS=30
DEPLOY_RAM=16
DEPLOY_CPU=3
DEPLOY_DISK=80
DEPLOY_ROLE_ID=$deploy_role
VPS_DEPLOY_LIMIT=2
BOT_VERSION=8.0.5-PRO
BOT_DEVELOPER=root_dora
EOF
 chmod 600 "$dir/.env"
 if ! create_python_env "$dir"; then rm -rf "$dir"; printf '%bPython virtual environment could not be created.%b\n' "$RED" "$RESET"; pause_menu; return; fi
 printf '%b• Installing bot dependencies...%b\n' "$CYAN" "$RESET"; if ! "$dir/venv/bin/python" -m pip install --disable-pip-version-check -r "$dir/requirements.txt"; then rm -rf "$dir"; printf '%bPython dependencies failed; rolled back.%b\n' "$RED" "$RESET"; pause_menu; return; fi
 pm2 delete "$name" >/dev/null 2>&1 || true; pm2 start "$dir/venv/bin/python" --name "$name" --cwd "$dir" --interpreter none -- "$dir/bot.py"; pm2 save >/dev/null 2>&1 || true
 printf '%b✓ REAL VPS bot installed and started.%b\n' "$GREEN" "$RESET"; printf '%bPublic host:%b %s\n' "$DIM" "$RESET" "$host_ip"; printf '%bBot directory:%b %s\n' "$DIM" "$RESET" "$dir"; pause_menu
}
manage(){ local action="$1"; header; printf '%b%s BOT%b\n\n' "$CYAN" "$action" "$RESET"; choose_bot || { pause_menu; return; }; case "$action" in START) pm2 start "$SELECTED";; STOP) pm2 stop "$SELECTED";; RESTART) pm2 restart "$SELECTED";; LOGS) pm2 logs "$SELECTED" --lines 150 --nostream;; esac; pm2 save >/dev/null 2>&1 || true; pause_menu; }
update_bot(){ header; printf '%bUPDATE BOT%b\n\n' "$CYAN" "$RESET"; choose_bot || { pause_menu; return; }; local dir="$ROOT/$SELECTED"; pm2 stop "$SELECTED" >/dev/null 2>&1 || true; if curl -fL --retry 3 --retry-delay 1 "$BOT_URL" -o "$dir/bot.py" && python3 -m py_compile "$dir/bot.py" && "$dir/venv/bin/python" -m pip install -r "$dir/requirements.txt" >/dev/null 2>&1; then pm2 restart "$SELECTED"; pm2 save >/dev/null 2>&1 || true; printf '%b✓ Bot updated.%b\n' "$GREEN" "$RESET"; else printf '%bUpdate validation failed. Existing files were not deleted.%b\n' "$RED" "$RESET"; fi; pause_menu; }
remove_bot(){ header; printf '%bREMOVE BOT%b\n\n' "$RED" "$RESET"; choose_bot || { pause_menu; return; }; printf '%bType REMOVE to permanently delete %s:%b ' "$YELLOW" "$SELECTED" "$RESET"; read -r confirm; [ "$confirm" = REMOVE ] || { printf '%bCancelled.%b\n' "$DIM" "$RESET"; pause_menu; return; }; pm2 delete "$SELECTED" >/dev/null 2>&1 || true; rm -rf -- "$ROOT/$SELECTED"; pm2 save >/dev/null 2>&1 || true; printf '%b✓ Bot removed.%b\n' "$GREEN" "$RESET"; pause_menu; }
status(){ header; printf '%bRUNTIME%b\nPython: %s\nLXC: %s\nPM2: %s\nPublic IP: %s\n\n' "$CYAN" "$RESET" "$(python3 --version 2>/dev/null || echo unavailable)" "$(lxc version 2>/dev/null | head -1 || echo unavailable)" "$(pm2 -v 2>/dev/null || echo unavailable)" "$(detect_host || echo unavailable)"; pm2 list; pause_menu; }
menu(){ header; printf '%b  01%b  Install / create VPS bot\n' "$CYAN" "$RESET"; printf '%b  02%b  Start bot\n' "$GREEN" "$RESET"; printf '%b  03%b  Stop bot\n' "$YELLOW" "$RESET"; printf '%b  04%b  Restart bot\n' "$PURPLE" "$RESET"; printf '%b  05%b  Live logs\n' "$PINK" "$RESET"; printf '%b  06%b  Update bot\n' "$CYAN" "$RESET"; printf '%b  07%b  Remove bot\n' "$RED" "$RESET"; printf '%b  08%b  System / LXC / PM2 status\n' "$WHITE" "$RESET"; printf '%b  Q %b Quit\n\n' "$DIM" "$RESET"; printf '%bSelect › %b' "$WHITE" "$CYAN"; read -r choice; case "$choice" in 1|01) create_bot;;2|02) manage START;;3|03) manage STOP;;4|04) manage RESTART;;5|05) manage LOGS;;6|06) update_bot;;7|07) remove_bot;;8|08) status;;q|Q) exit 0;;*) printf '%bInvalid option.%b\n' "$YELLOW" "$RESET"; sleep 1;;esac; }
printf '%bCJH Bot Hosting v%s%b\n' "$PURPLE" "$VERSION" "$RESET"
printf '%bInitializing control center...%b\n' "$DIM" "$RESET"
setup_runtime || { printf '%bRuntime setup failed. Check /tmp/cjh-apt-install.log and /tmp/cjh-apt-update.log.%b\n' "$RED" "$RESET"; exit 1; }
while :; do menu; done
