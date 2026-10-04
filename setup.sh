#!/usr/bin/env bash
set -Eeuo pipefail
VERSION="8.0.7"
ROOT="${CJH_HOME:-$HOME/cjh-bots}"
BASE_URL="https://raw.githubusercontent.com/officalsnck-create/cjh-bot-hosting/main"
BOT_URL="$BASE_URL/bot.py"
REQ_URL="$BASE_URL/requirements.txt"
SUDO=""
[[ $(id -u) -eq 0 ]] || SUDO="sudo"

RESET=$'\033[0m'; CYAN=$'\033[38;5;51m'; PURPLE=$'\033[38;5;141m'; PINK=$'\033[38;5;205m'; GREEN=$'\033[38;5;82m'; YELLOW=$'\033[38;5;220m'; WHITE=$'\033[1;97m'; DIM=$'\033[38;5;245m'; RED=$'\033[38;5;203m'

log(){ printf '%b%s%b\n' "$CYAN" "$*" "$RESET"; }
ok(){ printf '%b[OK]%b %s\n' "$GREEN" "$RESET" "$*"; }
warn(){ printf '%b[WARN]%b %s\n' "$YELLOW" "$RESET" "$*"; }
fail(){ printf '%b[FAIL]%b %s\n' "$RED" "$RESET" "$*"; }

header(){
  printf '\033[2J\033[H'
  printf '%b+--------------------------------------------------------------------------+%b\n' "$PURPLE" "$RESET"
  printf '%b|%b  %bCJH BOT HOSTING%b  %bv%s  |  VPS CONTROL CENTER%b\n' "$PURPLE" "$RESET" "$WHITE" "$RESET" "$DIM" "$VERSION" "$RESET"
  printf '%b+--------------------------------------------------------------------------+%b\n\n' "$PURPLE" "$RESET"
}

pause_menu(){ printf '\n%bPress ENTER to continue...%b ' "$DIM" "$RESET"; read -r _ || true; }
command_ready(){ command -v "$1" >/dev/null 2>&1; }
package_ready(){ dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed'; }

repair_r2u_sources(){
  local changed=0 f
  for f in /etc/apt/sources.list /etc/apt/sources.list.d/*.list; do
    [[ -f "$f" ]] || continue
    if grep -qE '^\s*deb-src\s+https?://r2u\.stat\.illinois\.edu/ubuntu' "$f" 2>/dev/null; then
      $SUDO sed -i -E '/^\s*deb-src\s+https?:\/\/r2u\.stat\.illinois\.edu\/ubuntu/ s/^/# disabled-by-cjh: /' "$f"
      changed=1
    fi
  done
  for f in /etc/apt/sources.list.d/*.sources; do
    [[ -f "$f" ]] || continue
    if grep -q 'r2u.stat.illinois.edu/ubuntu' "$f" 2>/dev/null; then
      $SUDO sed -i -E '/^[[:space:]]*Types:[[:space:]]*/ { /deb-src/ s/(^|[[:space:]])deb-src([[:space:]]|$)/ /g; s/[[:space:]]+/ /g; }' "$f"
      changed=1
    fi
  done
  if (( changed )); then warn "Disabled only the unsupported r2u source-index entry. Binary r2u remains enabled."; fi
}

apt_update(){
  repair_r2u_sources
  log "Refreshing APT package lists..."
  if ! $SUDO apt-get update >/tmp/cjh-apt-update.log 2>&1; then
    tail -40 /tmp/cjh-apt-update.log || true
    return 1
  fi
}

apt_install(){
  local packages=("$@")
  apt_update || return 1
  log "Installing: ${packages[*]}"
  if ! env DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y "${packages[@]}" >/tmp/cjh-apt-install.log 2>&1; then
    fail "APT failed while installing: ${packages[*]}"
    tail -50 /tmp/cjh-apt-install.log || true
    return 1
  fi
  ok "Installed: ${packages[*]}"
}

ensure_command(){ local cmd="$1" pkg="$2"; command_ready "$cmd" && return 0; apt_install "$pkg" && command_ready "$cmd"; }
ensure_package(){ local pkg="$1"; package_ready "$pkg" && return 0; apt_install "$pkg" && package_ready "$pkg"; }

setup_runtime(){
  log "[1/4] Checking system runtime..."
  ensure_command curl curl || return 1
  ensure_package ca-certificates || return 1
  ensure_command python3 python3 || return 1
  log "[2/4] Checking Python runtime..."
  ensure_package python3-venv || return 1
  ensure_package python3-pip || return 1
  log "[3/4] Checking LXC..."
  ensure_command lxc lxc || return 1
  log "[4/4] Checking Node.js / PM2..."
  if ! command_ready node; then
    log "Installing Node.js 20..."
    curl -fsSL --retry 3 https://deb.nodesource.com/setup_20.x -o /tmp/cjh-node-setup.sh || return 1
    $SUDO bash /tmp/cjh-node-setup.sh >/tmp/cjh-node-setup.log 2>&1 || { tail -40 /tmp/cjh-node-setup.log; return 1; }
    apt_install nodejs || return 1
  fi
  ensure_command npm npm || return 1
  if ! command_ready pm2; then
    log "Installing PM2..."
    $SUDO npm install -g pm2 >/tmp/cjh-pm2.log 2>&1 || { tail -40 /tmp/cjh-pm2.log; return 1; }
  fi
  command_ready pm2 || return 1
  mkdir -p "$ROOT"; chmod 700 "$ROOT"; ok "Runtime ready."
}

create_python_env(){
  local dir="$1"; rm -rf "$dir/venv"
  if python3 -m venv --without-pip "$dir/venv" >/tmp/cjh-venv.log 2>&1; then
    curl -fsSL --retry 3 https://bootstrap.pypa.io/get-pip.py -o "$dir/get-pip.py" || return 1
    "$dir/venv/bin/python" "$dir/get-pip.py" --disable-pip-version-check >/tmp/cjh-pip.log 2>&1 || { tail -40 /tmp/cjh-pip.log; return 1; }
    rm -f "$dir/get-pip.py"; "$dir/venv/bin/python" -m pip --version >/dev/null 2>&1
  else
    cat /tmp/cjh-venv.log 2>/dev/null || true; return 1
  fi
}

detect_host(){
  local ip=""; ip="$(curl -4 -fsS --connect-timeout 5 https://api.ipify.org 2>/dev/null || true)"
  [[ "$ip" =~ ^[0-9.]+$ ]] || ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  printf '%s' "$ip"
}

list_bots(){ mapfile -t bots < <(find "$ROOT" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort); }
choose_bot(){
  list_bots; ((${#bots[@]})) || { warn "No bots installed."; return 1; }
  local i=1 bot; for bot in "${bots[@]}"; do printf '  %b[%02d]%b %s\n' "$CYAN" "$i" "$RESET" "$bot"; ((i++)); done
  printf '\n%bSelect bot:%b ' "$WHITE" "$RESET"; read -r n
  [[ "$n" =~ ^[0-9]+$ ]] && (( n >= 1 && n <= ${#bots[@]} )) || return 1
  SELECTED="${bots[$((n-1))]}"
}
slug(){ printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9_-]+/-/g;s/^-+//;s/-+$//'; }

create_bot(){
  header; printf '%bDEPLOY REAL VPS + DISCORD BOT%b\n\n' "$CYAN" "$RESET"
  setup_runtime || { fail "Runtime setup failed. See /tmp/cjh-apt-update.log or /tmp/cjh-apt-install.log"; pause_menu; return; }
  printf '%bBot name%b [cjh-vps]: ' "$DIM" "$RESET"; read -r input
  local name; name="$(slug "${input:-cjh-vps}")"; [[ -n "$name" ]] || name=cjh-vps; local dir="$ROOT/$name"
  [[ ! -e "$dir" ]] || { warn "Bot already exists: $name"; pause_menu; return; }
  printf '%bDiscord bot token%b: ' "$DIM" "$RESET"; read -r -s token; printf '\n'
  printf '%bMain admin Discord user ID%b: ' "$DIM" "$RESET"; read -r admin_id
  printf '%bSelf-deploy role ID%b [0=disabled]: ' "$DIM" "$RESET"; read -r deploy_role; deploy_role="${deploy_role:-0}"
  local host_ip; host_ip="$(detect_host)"; printf '%bPublic host IP/domain%b [%s]: ' "$DIM" "$RESET" "${host_ip:-not detected}"; read -r entered_host; host_ip="${entered_host:-$host_ip}"
  [[ -n "$token" && -n "$admin_id" && -n "$host_ip" ]] || { warn "Token, admin ID and public host are required."; pause_menu; return; }
  [[ "$admin_id" =~ ^[0-9]{17,20}$ ]] || { warn "Invalid Discord user ID."; pause_menu; return; }
  mkdir -p "$dir"; chmod 700 "$dir"; umask 077
  log "Downloading bot source..."
  curl -fL --retry 3 --retry-delay 1 "$BOT_URL" -o "$dir/bot.py" || { rm -rf "$dir"; fail "bot.py download failed."; pause_menu; return; }
  curl -fL --retry 3 --retry-delay 1 "$REQ_URL" -o "$dir/requirements.txt" || { rm -rf "$dir"; fail "requirements.txt download failed."; pause_menu; return; }
  python3 -m py_compile "$dir/bot.py" || { rm -rf "$dir"; fail "Bot Python syntax validation failed."; pause_menu; return; }
  cat > "$dir/.env" <<ENV
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
BOT_VERSION=$VERSION-PRO
BOT_DEVELOPER=root_dora
ENV
  chmod 600 "$dir/.env"
  log "Creating isolated Python environment..."
  create_python_env "$dir" || { rm -rf "$dir"; fail "Python environment creation failed."; pause_menu; return; }
  log "Installing bot dependencies..."
  "$dir/venv/bin/python" -m pip install --disable-pip-version-check -r "$dir/requirements.txt" || { rm -rf "$dir"; fail "Bot dependencies failed."; pause_menu; return; }
  pm2 delete "$name" >/dev/null 2>&1 || true; pm2 start "$dir/venv/bin/python" --name "$name" --cwd "$dir" --interpreter none -- "$dir/bot.py"; pm2 save >/dev/null 2>&1 || true
  ok "REAL bot installed and started."; printf '%bHost:%b %s\n%bDirectory:%b %s\n' "$DIM" "$RESET" "$host_ip" "$DIM" "$RESET" "$dir"; pause_menu
}

manage(){
  local action="$1"; header; printf '%b%s BOT%b\n\n' "$CYAN" "$action" "$RESET"; choose_bot || { pause_menu; return; }
  case "$action" in START) pm2 start "$SELECTED";; STOP) pm2 stop "$SELECTED";; RESTART) pm2 restart "$SELECTED";; LOGS) pm2 logs "$SELECTED" --lines 150 --nostream;; esac
  pm2 save >/dev/null 2>&1 || true; pause_menu
}

update_bot(){
  header; printf '%bUPDATE BOT%b\n\n' "$CYAN" "$RESET"; choose_bot || { pause_menu; return; }; local dir="$ROOT/$SELECTED" tmp="$ROOT/.${SELECTED}.bot.py.new"
  if curl -fL --retry 3 --retry-delay 1 "$BOT_URL" -o "$tmp" && python3 -m py_compile "$tmp"; then mv "$tmp" "$dir/bot.py"; pm2 restart "$SELECTED"; pm2 save >/dev/null 2>&1 || true; ok "Bot updated."; else rm -f "$tmp"; fail "Update validation failed; existing bot.py was kept."; fi
  pause_menu
}

remove_bot(){
  header; printf '%bREMOVE BOT%b\n\n' "$RED" "$RESET"; choose_bot || { pause_menu; return; }
  printf '%bType REMOVE to delete %s:%b ' "$YELLOW" "$SELECTED" "$RESET"; read -r confirm
  [[ "$confirm" == REMOVE ]] || { warn "Cancelled."; pause_menu; return; }
  pm2 delete "$SELECTED" >/dev/null 2>&1 || true; rm -rf -- "$ROOT/$SELECTED"; pm2 save >/dev/null 2>&1 || true; ok "Bot removed."; pause_menu
}

status(){
  header; printf '%bRUNTIME%b\nPython: %s\nLXC: %s\nNode: %s\nPM2: %s\nPublic IP: %s\n\n' "$CYAN" "$RESET" "$(python3 --version 2>/dev/null || echo unavailable)" "$(lxc version 2>/dev/null | head -1 || echo unavailable)" "$(node --version 2>/dev/null || echo unavailable)" "$(pm2 -v 2>/dev/null || echo unavailable)" "$(detect_host || echo unavailable)"; pm2 list || true; pause_menu
}

menu(){
  header
  printf '%b  01%b  Install / Create VPS Bot\n' "$CYAN" "$RESET"; printf '%b  02%b  Start Bot\n' "$GREEN" "$RESET"; printf '%b  03%b  Stop Bot\n' "$YELLOW" "$RESET"; printf '%b  04%b  Restart Bot\n' "$PURPLE" "$RESET"; printf '%b  05%b  Live Logs\n' "$PINK" "$RESET"; printf '%b  06%b  Update Bot\n' "$CYAN" "$RESET"; printf '%b  07%b  Remove Bot\n' "$RED" "$RESET"; printf '%b  08%b  System / LXC / PM2 Status\n' "$WHITE" "$RESET"; printf '%b  Q %b Quit\n\n' "$DIM" "$RESET"
  printf '%bSelect > %b' "$WHITE" "$CYAN"; read -r choice
  case "$choice" in 1|01) create_bot;; 2|02) manage START;; 3|03) manage STOP;; 4|04) manage RESTART;; 5|05) manage LOGS;; 6|06) update_bot;; 7|07) remove_bot;; 8|08) status;; q|Q) exit 0;; *) warn "Invalid option."; sleep 1;; esac
}

printf '%bCJH Bot Hosting v%s%b\n' "$PURPLE" "$VERSION" "$RESET"
printf '%bInitializing control center...%b\n' "$DIM" "$RESET"
setup_runtime || { fail "Runtime setup failed. See /tmp/cjh-apt-update.log and /tmp/cjh-apt-install.log"; exit 1; }
while :; do menu; done
