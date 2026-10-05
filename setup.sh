#!/usr/bin/env bash
set -Eeuo pipefail
VERSION="9.0.0"
BRAND="SNCK"
ROOT="${CJH_HOME:-$HOME/cjh-bots}"
BASE_URL="https://raw.githubusercontent.com/officalsnck-create/cjh-bot-hosting/main"
BOT_URL="$BASE_URL/bot.py"
REQ_URL="$BASE_URL/requirements.txt"
SUDO=""
[[ "$(id -u)" -eq 0 ]] || SUDO="sudo"
RESET=$'\033[0m'; CYAN=$'\033[38;5;51m'; PURPLE=$'\033[38;5;141m'; PINK=$'\033[38;5;205m'; GREEN=$'\033[38;5;82m'; YELLOW=$'\033[38;5;220m'; WHITE=$'\033[1;97m'; DIM=$'\033[38;5;245m'; RED=$'\033[38;5;203m'
log(){ printf '%b%s%b\n' "$CYAN" "$*" "$RESET"; }; ok(){ printf '%b[OK]%b %s\n' "$GREEN" "$RESET" "$*"; }; warn(){ printf '%b[WARN]%b %s\n' "$YELLOW" "$RESET" "$*"; }; fail(){ printf '%b[FAIL]%b %s\n' "$RED" "$RESET" "$*"; }
header(){ printf '\033[2J\033[H'; printf '%b╭──────────────────────────────────────────────────────────────────────────╮%b\n' "$PURPLE" "$RESET"; printf '%b│%b  %b%s BOT HOSTING%b  %bv%s%b  •  VPS CONTROL CENTER  %b│%b\n' "$PURPLE" "$RESET" "$WHITE" "$BRAND" "$RESET" "$DIM" "$VERSION" "$RESET" "$PURPLE" "$RESET"; printf '%b╰──────────────────────────────────────────────────────────────────────────╯%b\n\n' "$PURPLE" "$RESET"; }
pause_menu(){ printf '\n%bPress ENTER to continue...%b ' "$DIM" "$RESET"; read -r _ || true; }; command_ready(){ command -v "$1" >/dev/null 2>&1; }; package_ready(){ dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed'; }; systemd_available(){ [[ -d /run/systemd/system ]] && command_ready systemctl; }; hosted_dev_env(){ [[ -n "${CODESPACES:-}" || -n "${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN:-}" || -n "${COLAB_RELEASE_TAG:-}" || -n "${KAGGLE_KERNEL_RUN_TYPE:-}" || -f /.dockerenv ]]; }
repair_r2u_sources(){ local changed=0 f; shopt -s nullglob; for f in /etc/apt/sources.list /etc/apt/sources.list.d/*.list; do [[ -f "$f" ]] || continue; if grep -qE '^[[:space:]]*deb-src[[:space:]]+https?://r2u\.stat\.illinois\.edu/ubuntu' "$f" 2>/dev/null; then $SUDO sed -i -E '/^[[:space:]]*deb-src[[:space:]]+https?:\/\/r2u\.stat\.illinois\.edu\/ubuntu/ s/^/# disabled-by-snck: /' "$f"; changed=1; fi; done; shopt -u nullglob; (( changed )) && warn "Disabled unsupported r2u source-index entries; binary r2u remains enabled."; }
apt_update(){ repair_r2u_sources; log "Refreshing APT package lists..."; $SUDO apt-get update >/tmp/cjh-apt-update.log 2>&1 || { tail -60 /tmp/cjh-apt-update.log || true; return 1; }; }
apt_install(){ local p=("$@"); apt_update || return 1; log "Installing: ${p[*]}"; env DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y --no-install-recommends "${p[@]}" >/tmp/cjh-apt-install.log 2>&1 || { fail "APT failed while installing: ${p[*]}"; tail -80 /tmp/cjh-apt-install.log || true; return 1; }; ok "Installed: ${p[*]}"; }
ensure_command(){ local c="$1" p="$2"; command_ready "$c" && return 0; apt_install "$p" && command_ready "$c"; }; ensure_package(){ local p="$1"; package_ready "$p" && return 0; apt_install "$p" && package_ready "$p"; }
setup_lxd(){
  log "[3/4] Checking LXD runtime..."
  if command_ready lxc && lxc version >/tmp/cjh-lxc-version.log 2>&1 && lxc info >/tmp/cjh-lxc-info.log 2>&1; then ok "Existing LXD client and daemon are usable."; return 0; fi
  if hosted_dev_env; then warn "Hosted/containerized development runtime detected; host-level LXD may be unavailable."; return 2; fi
  warn "Installing the official LXD snap..."; apt_install snapd || return 1
  if systemd_available; then $SUDO systemctl enable --now snapd.socket >/tmp/cjh-snapd.log 2>&1 || true; fi
  command_ready snap || { fail "snap is unavailable after installing snapd."; return 1; }
  if snap list lxd >/dev/null 2>&1; then $SUDO snap refresh lxd >/tmp/cjh-lxd-snap.log 2>&1 || true; else $SUDO snap install lxd --channel=5.21/stable >/tmp/cjh-lxd-snap.log 2>&1 || { tail -80 /tmp/cjh-lxd-snap.log || true; return 1; }; fi
  [[ -x /snap/bin/lxc ]] && $SUDO ln -sf /snap/bin/lxc /usr/local/bin/lxc; [[ -x /snap/bin/lxd ]] && $SUDO ln -sf /snap/bin/lxd /usr/local/bin/lxd; hash -r 2>/dev/null || true
  command_ready lxc || { fail "LXD client command is unavailable."; return 1; }
  if ! lxc info >/tmp/cjh-lxc-info.log 2>&1; then command_ready lxd || { fail "LXD daemon command is unavailable."; return 1; }; $SUDO lxd waitready --timeout=60 >/tmp/cjh-lxd-wait.log 2>&1 || true; $SUDO lxd init --minimal >/tmp/cjh-lxd-init.log 2>&1 || { tail -80 /tmp/cjh-lxd-init.log || true; return 1; }; fi
  lxc info >/tmp/cjh-lxc-info.log 2>&1 || { tail -80 /tmp/cjh-lxc-info.log || true; return 1; }; lxc storage list >/tmp/cjh-lxc-storage.log 2>&1 || { tail -80 /tmp/cjh-lxc-storage.log || true; return 1; }; lxc network list >/tmp/cjh-lxc-network.log 2>&1 || { tail -80 /tmp/cjh-lxc-network.log || true; return 1; }; ok "LXD is installed, initialized, and responding."; return 0
}
setup_runtime(){
  log "[1/4] Checking system runtime..."; ensure_command curl curl || return 1; ensure_package ca-certificates || return 1; ensure_command python3 python3 || return 1
  log "[2/4] Checking Python runtime..."; ensure_package python3-venv || return 1; ensure_package python3-pip || return 1
  if setup_lxd; then LXD_AVAILABLE=1; else local rc=$?; if [[ "$rc" -eq 2 ]]; then LXD_AVAILABLE=0; warn "Continuing in bot-only mode; VPS creation needs a real LXD host."; else return 1; fi; fi
  log "[4/4] Checking service runtime..."; if systemd_available; then ok "systemd service manager available."; elif command_ready node; then ok "PM2 fallback available."; else apt_install nodejs npm || return 1; $SUDO npm install -g pm2 >/tmp/cjh-pm2.log 2>&1 || { tail -60 /tmp/cjh-pm2.log || true; return 1; }; fi
  mkdir -p "$ROOT"; chmod 700 "$ROOT"; ok "Runtime ready."
}
create_python_env(){ local dir="$1"; rm -rf "$dir/venv"; python3 -m venv --without-pip "$dir/venv" >/tmp/cjh-venv.log 2>&1 || { cat /tmp/cjh-venv.log || true; return 1; }; curl -fsSL --retry 3 https://bootstrap.pypa.io/get-pip.py -o "$dir/get-pip.py" || return 1; "$dir/venv/bin/python" "$dir/get-pip.py" --disable-pip-version-check >/tmp/cjh-pip.log 2>&1 || { tail -60 /tmp/cjh-pip.log || true; return 1; }; rm -f "$dir/get-pip.py"; "$dir/venv/bin/python" -m pip --version >/dev/null 2>&1; }
detect_host(){ local ip; ip="$(curl -4 -fsS --connect-timeout 5 https://api.ipify.org 2>/dev/null || true)"; [[ "$ip" =~ ^[0-9.]+$ ]] || ip="$(hostname -I 2>/dev/null | awk '{print $1}')"; printf '%s' "$ip"; }
list_bots(){ mapfile -t bots < <(find "$ROOT" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort); }; choose_bot(){ list_bots; ((${#bots[@]})) || { warn "No bots installed."; return 1; }; local i=1 bot n; for bot in "${bots[@]}"; do printf '  %b[%02d]%b %s\n' "$CYAN" "$i" "$RESET" "$bot"; ((i++)); done; printf '\n%bSelect bot:%b ' "$WHITE" "$RESET"; read -r n; [[ "$n" =~ ^[0-9]+$ ]] && ((n>=1&&n<=${#bots[@]})) || return 1; SELECTED="${bots[$((n-1))]}"; }; slug(){ printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9_-]+/-/g;s/^-+//;s/-+$//'; }; service_name(){ printf 'cjh-%s' "$1"; }
service_start(){ local name="$1" dir="$2" unit; unit="$(service_name "$name")"; if systemd_available; then cat >"/tmp/${unit}.service" <<EOF
[Unit]
Description=SNCK Discord Bot - ${name}
After=network-online.target
Wants=network-online.target
[Service]
Type=simple
User=root
WorkingDirectory=${dir}
Environment=PYTHONUNBUFFERED=1
ExecStart=${dir}/venv/bin/python ${dir}/bot.py
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF
$SUDO install -m 0644 "/tmp/${unit}.service" "/etc/systemd/system/${unit}.service"; $SUDO systemctl daemon-reload; $SUDO systemctl enable --now "$unit.service"; elif command_ready pm2; then pm2 delete "$name" >/dev/null 2>&1 || true; pm2 start "$dir/venv/bin/python" --name "$name" --cwd "$dir" --interpreter none -- "$dir/bot.py"; pm2 save >/dev/null 2>&1 || true; else nohup "$dir/venv/bin/python" "$dir/bot.py" >"$dir/bot.log" 2>&1 </dev/null & echo $! >"$dir/bot.pid"; fi; }
service_action(){ local action="$1" name="$2" unit; unit="$(service_name "$name")"; if systemd_available && [[ -f "/etc/systemd/system/$unit.service" ]]; then $SUDO systemctl "$action" "$unit.service"; elif command_ready pm2; then pm2 "$action" "$name"; else case "$action" in start) nohup "$ROOT/$name/venv/bin/python" "$ROOT/$name/bot.py" >"$ROOT/$name/bot.log" 2>&1 </dev/null & echo $! >"$ROOT/$name/bot.pid";; stop) [[ -f "$ROOT/$name/bot.pid" ]] && kill "$(cat "$ROOT/$name/bot.pid")" 2>/dev/null || true;; restart) service_action stop "$name" || true; service_action start "$name";; esac; fi; }
create_bot(){
  header; printf '%bDEPLOY REAL DISCORD BOT + LXD VPS NODE%b\n\n' "$CYAN" "$RESET"; setup_runtime || { fail "Runtime setup failed."; pause_menu; return; }
  printf '%bBot name%b [cjh-vps]: ' "$DIM" "$RESET"; read -r input; local name; name="$(slug "${input:-cjh-vps}")"; [[ -n "$name" ]] || name=cjh-vps; local dir="$ROOT/$name"; [[ ! -e "$dir" ]] || { warn "Bot already exists: $name"; pause_menu; return; }
  printf '%bDiscord bot token%b: ' "$DIM" "$RESET"; read -r -s token; printf '\n'; printf '%bMain admin Discord user ID%b: ' "$DIM" "$RESET"; read -r admin_id; printf '%bDeploy role ID%b [0=disabled]: ' "$DIM" "$RESET"; read -r deploy_role; deploy_role="${deploy_role:-0}"; local host_ip; host_ip="$(detect_host)"; printf '%bPublic host IP/domain%b [%s]: ' "$DIM" "$RESET" "${host_ip:-not detected}"; read -r entered_host; host_ip="${entered_host:-$host_ip}"; printf '%bSSH public key%b [optional on bot-only hosts]: ' "$DIM" "$RESET"; read -r ssh_key
  [[ -n "$token" && "$admin_id" =~ ^[0-9]{17,20}$ && -n "$host_ip" ]] || { warn "Token, valid admin ID and public host are required."; pause_menu; return; }
  mkdir -p "$dir"; chmod 700 "$dir"; umask 077; curl -fL --retry 3 --retry-delay 1 "${BOT_URL}?$(date +%s)" -o "$dir/bot.py" || { rm -rf "$dir"; fail "bot.py download failed."; pause_menu; return; }; curl -fL --retry 3 --retry-delay 1 "${REQ_URL}?$(date +%s)" -o "$dir/requirements.txt" || { rm -rf "$dir"; fail "requirements.txt download failed."; pause_menu; return; }; python3 -m py_compile "$dir/bot.py" || { rm -rf "$dir"; fail "Bot Python syntax validation failed."; pause_menu; return; }
  cat >"$dir/.env" <<ENV
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
DEPLOY_SLOT=0
VPS_DEPLOY_LIMIT=2
BOT_VERSION=$VERSION
BOT_DEVELOPER=root_dora
DEPLOY_SSH_PUBLIC_KEY=$ssh_key
ENV
  chmod 600 "$dir/.env"; create_python_env "$dir" || { rm -rf "$dir"; fail "Python environment creation failed."; pause_menu; return; }; "$dir/venv/bin/python" -m pip install --disable-pip-version-check -r "$dir/requirements.txt" || { rm -rf "$dir"; fail "Bot dependencies failed."; pause_menu; return; }; service_start "$name" "$dir" || { fail "Bot service failed to start."; pause_menu; return; }; ok "REAL bot installed and started."; printf '%bDirectory:%b %s\n%bService:%b %s\n' "$DIM" "$RESET" "$dir" "$DIM" "$RESET" "$(service_name "$name")"; pause_menu; }
manage(){ local action="$1"; header; printf '%b%s BOT%b\n\n' "$CYAN" "$action" "$RESET"; choose_bot || { pause_menu; return; }; case "$action" in START) service_action start "$SELECTED";; STOP) service_action stop "$SELECTED";; RESTART) service_action restart "$SELECTED";; LOGS) if systemd_available && [[ -f "/etc/systemd/system/$(service_name "$SELECTED").service" ]]; then $SUDO journalctl -u "$(service_name "$SELECTED").service" -n 150 --no-pager; elif command_ready pm2; then pm2 logs "$SELECTED" --lines 150 --nostream; else tail -150 "$ROOT/$SELECTED/bot.log" 2>/dev/null || true; fi;; esac; pause_menu; }
update_bot(){ header; printf '%bUPDATE BOT%b\n\n' "$CYAN" "$RESET"; choose_bot || { pause_menu; return; }; local dir="$ROOT/$SELECTED" tmp="$ROOT/.${SELECTED}.bot.py.new"; if curl -fL --retry 3 --retry-delay 1 "${BOT_URL}?$(date +%s)" -o "$tmp" && python3 -m py_compile "$tmp"; then mv "$tmp" "$dir/bot.py"; "$dir/venv/bin/python" -m pip install --disable-pip-version-check -r "$dir/requirements.txt" >/tmp/cjh-bot-update.log 2>&1 || true; service_action restart "$SELECTED"; ok "Bot updated and restarted."; else rm -f "$tmp"; fail "Update validation failed; existing bot.py was kept."; fi; pause_menu; }
remove_bot(){ header; printf '%bREMOVE BOT%b\n\n' "$RED" "$RESET"; choose_bot || { pause_menu; return; }; printf '%bType REMOVE to delete %s:%b ' "$YELLOW" "$SELECTED" "$RESET"; read -r confirm; [[ "$confirm" == REMOVE ]] || { warn "Cancelled."; pause_menu; return; }; service_action stop "$SELECTED" >/dev/null 2>&1 || true; if systemd_available; then $SUDO systemctl disable "$(service_name "$SELECTED").service" >/dev/null 2>&1 || true; $SUDO rm -f "/etc/systemd/system/$(service_name "$SELECTED").service"; $SUDO systemctl daemon-reload; fi; command_ready pm2 && pm2 delete "$SELECTED" >/dev/null 2>&1 || true; rm -rf -- "$ROOT/$SELECTED"; ok "Bot removed."; pause_menu; }
status(){ header; printf '%bHOST RUNTIME%b\n' "$CYAN" "$RESET"; printf 'Python: %s\n' "$(python3 --version 2>/dev/null || echo unavailable)"; printf 'LXD API: %s\n' "$(python3 -c 'from pylxd import Client; Client().host_info(); print("READY")' 2>/dev/null || echo unavailable)"; printf 'systemd: %s\n' "$(systemd_available && echo yes || echo no)"; printf 'Public IP: %s\n\n' "$(detect_host || echo unavailable)"; pause_menu; }
self_check(){ header; printf '%bSNCK SELF CHECK%b\n\n' "$CYAN" "$RESET"; local failures=0; command_ready curl || { fail "curl missing"; failures=$((failures+1)); }; command_ready python3 || { fail "python3 missing"; failures=$((failures+1)); }; python3 -m venv --help >/dev/null 2>&1 || { fail "python3-venv unavailable"; failures=$((failures+1)); }; if python3 -c 'from pylxd import Client; Client().host_info()' >/dev/null 2>&1; then ok "Python LXD API is usable"; else warn "LXD unavailable here; bot-only mode is supported."; fi; [[ "$failures" -eq 0 ]] && ok "Base prerequisites passed." || warn "$failures base prerequisite(s) failed."; pause_menu; }
menu(){ header; printf '%b  01%b  Install / Create Bot + LXD VPS Node\n' "$CYAN" "$RESET"; printf '%b  02%b  Start Bot\n' "$GREEN" "$RESET"; printf '%b  03%b  Stop Bot\n' "$YELLOW" "$RESET"; printf '%b  04%b  Restart Bot\n' "$PURPLE" "$RESET"; printf '%b  05%b  Live Logs\n' "$PINK" "$RESET"; printf '%b  06%b  Update Bot\n' "$CYAN" "$RESET"; printf '%b  07%b  Remove Bot\n' "$RED" "$RESET"; printf '%b  08%b  System / LXD / Service Status\n' "$WHITE" "$RESET"; printf '%b  09%b  Full Self Check\n' "$GREEN" "$RESET"; printf '%b  Q %b Quit\n\n' "$DIM" "$RESET"; printf '%bSelect > %b' "$WHITE" "$CYAN"; read -r choice; case "$choice" in 1|01) create_bot;; 2|02) manage START;; 3|03) manage STOP;; 4|04) manage RESTART;; 5|05) manage LOGS;; 6|06) update_bot;; 7|07) remove_bot;; 8|08) status;; 9|09) self_check;; q|Q) exit 0;; *) warn "Invalid option."; sleep 1;; esac; }
trap 'rc=$?; ((rc!=0)) && fail "Installer stopped with exit code $rc"' ERR
printf '%b%s Bot Hosting v%s%b\n' "$PURPLE" "$BRAND" "$VERSION" "$RESET"; printf '%bInitializing control center...%b\n' "$DIM" "$RESET"; setup_runtime || { fail "Runtime setup failed."; printf '%bSee:%b /tmp/cjh-apt-update.log /tmp/cjh-apt-install.log /tmp/cjh-lxc-*.log\n' "$DIM" "$RESET"; exit 1; }; while :; do menu; done
