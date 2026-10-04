#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME='CJH BOT HOSTING'
APP_VERSION='4.0.0'
BASE_DIR="${CJH_HOME:-$HOME/cjh-bots}"
SUDO=''
[[ $EUID -eq 0 ]] || SUDO='sudo'

# Premium terminal palette: obsidian + aurora cyan/indigo/violet/pink.
E=$'\033'
RESET="${E}[0m"; BOLD="${E}[1m"; DIM="${E}[2m"
WHITE="${E}[38;2;245;247;255m"; SLATE="${E}[38;2;148;163;184m"
CYAN="${E}[38;2;45;226;230m"; SKY="${E}[38;2;56;189;248m"
INDIGO="${E}[38;2;99;102;241m"; VIOLET="${E}[38;2;139;92;246m"
PINK="${E}[38;2;236;72;153m"; GREEN="${E}[38;2;74;222;128m"
AMBER="${E}[38;2;251;191;36m"; RED="${E}[38;2;248;113;113m"

cleanup(){ printf '%b' "$RESET"; }
trap cleanup EXIT INT TERM

cols(){ local n; n="$(tput cols 2>/dev/null || printf '100')"; (( n < 82 )) && n=82; printf '%s' "$n"; }
repeat(){ printf '%*s' "$2" '' | tr ' ' "$1"; }
clear_ui(){ printf '\033[2J\033[H'; }

# Terminal "glass" is represented with translucent-style borders, spacing, muted layers and aurora accents.
frame_top(){
  local w="$(cols)" title="$1"; local inner=$((w-4)); local left=$(( (inner-${#title}-4)/2 )); ((left<1))&&left=1
  local right=$((inner-left-${#title}-4)); ((right<1))&&right=1
  printf '%b╭─%s╮%b\n' "$VIOLET" "$(repeat '─' "$((w-2))")" "$RESET"
  printf '%b│%b%*s %b%s%b %*s%b│%b\n' "$VIOLET" "$RESET" "$left" '' "$BOLD$WHITE" "$title" "$RESET" "$right" '' "$VIOLET" "$RESET"
  printf '%b├%s┤%b\n' "$VIOLET" "$(repeat '─' "$((w-2))")" "$RESET"
}
frame_bottom(){ local w="$(cols)"; printf '%b╰%s╯%b\n' "$VIOLET" "$(repeat '─' "$((w-2))")" "$RESET"; }
section(){ printf '%b╭─ %b%s%b %s╮%b\n' "$INDIGO" "$BOLD$WHITE" "$1" "$RESET" "$(repeat '─' "$(( $(cols)-${#1}-7 ))")" "$RESET"; }

info(){ printf '%b%s%b\n' "$SLATE" "$1" "$RESET"; }
ok(){ printf '%b✓ %s%b\n' "$GREEN" "$1" "$RESET"; }
warn(){ printf '%b! %s%b\n' "$AMBER" "$1" "$RESET"; }
err(){ printf '%b✕ %s%b\n' "$RED" "$1" "$RESET"; }
pause(){ printf '\n%bPress Enter to return...%b' "$SLATE" "$RESET"; read -r _; }

need_cmd(){
  local cmd="$1" pkg="${2:-$1}"
  command -v "$cmd" >/dev/null 2>&1 && return 0
  info "Installing $pkg..."
  $SUDO apt-get update -y >/dev/null
  $SUDO apt-get install -y "$pkg" >/dev/null
}

setup_runtime(){
  need_cmd curl curl
  need_cmd ca-certificates ca-certificates
  if ! command -v node >/dev/null 2>&1; then
    info 'Installing Node.js 20 LTS...'
    curl -fsSL https://deb.nodesource.com/setup_20.x | $SUDO -E bash - >/dev/null
    $SUDO apt-get install -y nodejs >/dev/null
  fi
  if ! command -v npm >/dev/null 2>&1; then
    err 'npm was not installed with Node.js.'; return 1
  fi
  if ! command -v pm2 >/dev/null 2>&1; then
    info 'Installing PM2...'
    $SUDO npm install -g pm2 >/dev/null
  fi
  mkdir -p "$BASE_DIR"
  chmod 700 "$BASE_DIR"
}

safe_name(){ printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9._-]+/-/g;s/^-+//;s/-+$//'; }

pm2_state(){
  local name="$1"
  pm2 jlist 2>/dev/null | node - "$name" <<'NODE'
let s='';process.stdin.on('data',d=>s+=d).on('end',()=>{try{const n=process.argv[2],a=JSON.parse(s),p=a.find(x=>x.name===n);process.stdout.write(p?.pm2_env?.status||'offline')}catch{process.stdout.write('offline')}})
NODE
}

state_label(){
  case "$1" in
    online) printf '%b● ONLINE%b' "$GREEN" "$RESET";;
    stopped) printf '%b● STOPPED%b' "$AMBER" "$RESET";;
    errored|error) printf '%b● ERROR%b' "$RED" "$RESET";;
    *) printf '%b● OFFLINE%b' "$SLATE" "$RESET";;
  esac
}

bot_dirs(){
  find "$BASE_DIR" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null | sort
}

bot_count(){ bot_dirs | wc -l | tr -d ' '; }

choose_bot(){
  local dirs=() d i=1 pick
  mapfile -t dirs < <(bot_dirs)
  if ((${#dirs[@]}==0)); then err 'No bots are installed.'; return 1; fi
  section 'BOT SELECTOR'
  for d in "${dirs[@]}"; do
    local n="$(basename "$d")" st; st="$(pm2_state "$n")"
    printf '  %b[%02d]%b %-28s ' "$CYAN" "$i" "$RESET" "$n"; state_label "$st"; printf '\n'
    ((i++))
  done
  printf '\n%bChoose a number%b: ' "$WHITE" "$RESET"; read -r pick
  [[ "$pick" =~ ^[0-9]+$ ]] || { err 'Enter a valid number.'; return 1; }
  ((pick>=1 && pick<=${#dirs[@]})) || { err 'Selection is outside the list.'; return 1; }
  SELECTED_BOT="$(basename "${dirs[$((pick-1))]}")"
  SELECTED_DIR="$BASE_DIR/$SELECTED_BOT"
}

write_bot(){
  local dir="$1" token="$2" client_id="$3" admin_id="$4"
  mkdir -p "$dir"; chmod 700 "$dir"
  cat > "$dir/package.json" <<'JSON'
{
  "name": "cjh-discord-bot",
  "version": "4.0.0",
  "private": true,
  "main": "bot.js",
  "scripts": { "start": "node bot.js" },
  "dependencies": { "discord.js": "^14.22.1", "@discordjs/voice": "^0.19.0" }
}
JSON
  umask 077
  cat > "$dir/.env" <<EOF
BOT_TOKEN=$token
CLIENT_ID=$client_id
ADMIN_ID=$admin_id
EOF
  chmod 600 "$dir/.env"
  cat > "$dir/bot.js" <<'NODE'
const fs=require('fs');
const {Client,GatewayIntentBits,REST,Routes,SlashCommandBuilder,EmbedBuilder,ActivityType}=require('discord.js');
const {joinVoiceChannel}=require('@discordjs/voice');
const env={};
for(const line of fs.readFileSync('.env','utf8').split(/\r?\n/)){if(!line||!line.includes('='))continue;const i=line.indexOf('=');env[line.slice(0,i)]=line.slice(i+1)}
if(!env.BOT_TOKEN||!env.CLIENT_ID){console.error('[CJH] Missing credentials');process.exit(1)}
const client=new Client({intents:[GatewayIntentBits.Guilds,GatewayIntentBits.GuildMessages,GatewayIntentBits.MessageContent,GatewayIntentBits.GuildMembers,GatewayIntentBits.GuildVoiceStates]});
const commands=[new SlashCommandBuilder().setName('ping').setDescription('Show bot latency'),new SlashCommandBuilder().setName('security').setDescription('Show security status'),new SlashCommandBuilder().setName('joinvc').setDescription('Join your current voice channel')].map(x=>x.toJSON());
(async()=>{try{await new REST({version:'10'}).setToken(env.BOT_TOKEN).put(Routes.applicationCommands(env.CLIENT_ID),{body:commands});console.log('[CJH] Slash commands synchronized')}catch(e){console.error('[CJH] Slash registration:',e.message)}})();
client.once('ready',()=>{console.log(`[CJH] ${client.user.tag} online`);client.user.setActivity('CJH Bot Hosting',{type:ActivityType.Watching})});
client.on('messageCreate',async m=>{if(m.author.bot||!m.guild)return;if(m.content.trim().toLowerCase()==='!ping')await m.reply(`Pong! ${client.ws.ping}ms`)});
client.on('interactionCreate',async i=>{if(!i.isChatInputCommand())return;try{if(i.commandName==='ping')return i.reply({content:`Pong! ${client.ws.ping}ms`,ephemeral:true});if(i.commandName==='security')return i.reply({embeds:[new EmbedBuilder().setColor(0x8b5cf6).setTitle('CJH Security').setDescription('Security status: active.').setTimestamp()],ephemeral:true});if(i.commandName==='joinvc'){const ch=i.member?.voice?.channel;if(!ch)return i.reply({content:'Join a voice channel first.',ephemeral:true});joinVoiceChannel({channelId:ch.id,guildId:i.guild.id,adapterCreator:i.guild.voiceAdapterCreator});return i.reply({content:'Joined your voice channel.',ephemeral:true})}}catch(e){console.error('[CJH] Interaction:',e.message);if(!i.replied)await i.reply({content:'Command failed.',ephemeral:true}).catch(()=>{})}});
client.login(env.BOT_TOKEN).catch(e=>{console.error('[CJH] Login failed:',e.message);process.exit(1)});
NODE
}

install_pm2_startup(){
  if command -v pm2 >/dev/null 2>&1; then
    local startup
    startup="$(pm2 startup 2>/dev/null | tail -n 1 || true)"
    if [[ "$startup" == sudo\ * ]]; then eval "$startup" >/dev/null 2>&1 || true; fi
    pm2 save >/dev/null 2>&1 || true
  fi
}

create_bot(){
  clear_ui; frame_top 'CREATE BOT  /  SECURE DEPLOYMENT'
  setup_runtime || { pause; return; }
  section 'BOT IDENTITY'
  printf '%bName%b: ' "$SLATE" "$RESET"; read -r raw_name
  local name; name="$(safe_name "${raw_name:-bot-$(date +%s)}")"; [[ -n "$name" ]] || name="bot-$(date +%s)"
  local dir="$BASE_DIR/$name"
  [[ ! -e "$dir" ]] || { err 'That bot name already exists.'; pause; return; }
  section 'DISCORD CREDENTIALS'
  printf '%bBot token%b: ' "$SLATE" "$RESET"; read -r -s token; printf '\n'
  printf '%bApplication / Client ID%b: ' "$SLATE" "$RESET"; read -r client_id
  printf '%bAdmin Discord User ID (optional)%b: ' "$SLATE" "$RESET"; read -r admin_id
  [[ -n "$token" && -n "$client_id" ]] || { err 'Bot token and Client ID are required.'; pause; return; }
  write_bot "$dir" "$token" "$client_id" "$admin_id"
  info 'Installing bot dependencies...'
  if ! (cd "$dir" && npm install --omit=dev --no-audit --no-fund >/dev/null); then
    rm -rf -- "$dir"; err 'Dependency installation failed; incomplete bot was removed.'; pause; return
  fi
  pm2 delete "$name" >/dev/null 2>&1 || true
  if ! pm2 start "$dir/bot.js" --name "$name" --cwd "$dir" --time >/dev/null; then
    err 'PM2 could not start the bot. Check the generated logs.'; pause; return
  fi
  install_pm2_startup
  ok "Bot '$name' created and started."
  printf '%bPath%b: %s\n' "$SLATE" "$RESET" "$dir"
  printf '%bStatus%b: ' "$SLATE" "$RESET"; state_label online; printf '\n'
  frame_bottom; pause
}

start_bot(){ clear_ui; frame_top 'START BOT'; choose_bot || { frame_bottom; pause; return; }; if pm2 start "$SELECTED_BOT" >/dev/null 2>&1 || pm2 start "$SELECTED_DIR/bot.js" --name "$SELECTED_BOT" --cwd "$SELECTED_DIR" >/dev/null 2>&1; then pm2 save >/dev/null 2>&1 || true; ok "$SELECTED_BOT is online."; else err 'Unable to start the selected bot.'; fi; frame_bottom; pause; }
stop_bot(){ clear_ui; frame_top 'STOP BOT'; choose_bot || { frame_bottom; pause; return; }; if pm2 stop "$SELECTED_BOT" >/dev/null 2>&1; then pm2 save >/dev/null 2>&1 || true; ok "$SELECTED_BOT stopped."; else err 'Unable to stop the selected bot.'; fi; frame_bottom; pause; }
restart_bot(){ clear_ui; frame_top 'RESTART BOT'; choose_bot || { frame_bottom; pause; return; }; if pm2 restart "$SELECTED_BOT" >/dev/null 2>&1 || pm2 start "$SELECTED_DIR/bot.js" --name "$SELECTED_BOT" --cwd "$SELECTED_DIR" >/dev/null 2>&1; then pm2 save >/dev/null 2>&1 || true; ok "$SELECTED_BOT restarted."; else err 'Unable to restart the selected bot.'; fi; frame_bottom; pause; }
logs_bot(){ clear_ui; frame_top 'LIVE BOT LOGS'; choose_bot || { frame_bottom; pause; return; }; info "Showing the latest 100 lines. Press Ctrl+C to return."; set +e; pm2 logs "$SELECTED_BOT" --lines 100 --nostream; set -e; frame_bottom; pause; }
remove_bot(){ clear_ui; frame_top 'REMOVE BOT  /  PROTECTED ACTION'; choose_bot || { frame_bottom; pause; return; }; printf '%bType REMOVE %s to confirm:%b ' "$RED" "$SELECTED_BOT" "$RESET"; read -r confirm; if [[ "$confirm" == "REMOVE $SELECTED_BOT" ]]; then pm2 delete "$SELECTED_BOT" >/dev/null 2>&1 || true; rm -rf -- "$SELECTED_DIR"; pm2 save >/dev/null 2>&1 || true; ok 'Bot and its local files were removed.'; else warn 'Removal cancelled.'; fi; frame_bottom; pause; }

health(){
  clear_ui; frame_top 'LIVE SYSTEM HEALTH'
  local host nodev pmv mem disk uptimev count online=0
  host="$(hostname 2>/dev/null || echo unknown)"; nodev="$(node -v 2>/dev/null || echo unavailable)"; pmv="$(pm2 -v 2>/dev/null || echo unavailable)"; mem="$(free -h 2>/dev/null | awk '/^Mem:/ {print $3" / "$2}' || echo unavailable)"; disk="$(df -h "$BASE_DIR" 2>/dev/null | awk 'NR==2 {print $3" / "$2" used, "$4" free}' || echo unavailable)"; uptimev="$(uptime -p 2>/dev/null || uptime 2>/dev/null || echo unavailable)"; count="$(bot_count)"
  section 'SERVER'
  printf '  %bHost%b      %s\n  %bNode.js%b   %s\n  %bPM2%b       %s\n  %bMemory%b    %s\n  %bDisk%b      %s\n  %bUptime%b    %s\n' "$SLATE" "$RESET" "$host" "$SLATE" "$RESET" "$nodev" "$SLATE" "$RESET" "$pmv" "$SLATE" "$RESET" "$mem" "$SLATE" "$RESET" "$disk" "$SLATE" "$RESET" "$uptimev"
  section "BOTS  /  $count INSTALLED"
  local d n st
  while IFS= read -r d; do n="$(basename "$d")"; st="$(pm2_state "$n")"; [[ "$st" == online ]] && ((online+=1)); printf '  %-30s ' "$n"; state_label "$st"; printf '\n'; done < <(bot_dirs)
  printf '\n%bOnline%b: %b%s%b / %s\n' "$SLATE" "$RESET" "$GREEN" "$online" "$RESET" "$count"
  frame_bottom; pause
}

update_runtime(){ clear_ui; frame_top 'RUNTIME MAINTENANCE'; setup_runtime; if command -v pm2 >/dev/null 2>&1; then pm2 update >/dev/null 2>&1 || true; fi; install_pm2_startup; ok 'Runtime checks completed.'; printf '%bNode%b %s   %bPM2%b %s\n' "$SLATE" "$RESET" "$(node -v)" "$SLATE" "$RESET" "$(pm2 -v)"; frame_bottom; pause; }

show_about(){ clear_ui; frame_top 'CJH  /  ABOUT'; printf '%bCJH Bot Hosting%b\n\n' "$BOLD$WHITE" "$RESET"; info 'Premium terminal control plane for Discord bot hosting.'; info 'Glass-inspired aurora UI • PM2 process management • secure local credentials'; info "Version $APP_VERSION"; info "Bot directory: $BASE_DIR"; frame_bottom; pause; }

menu(){
  clear_ui
  local w="$(cols)"
  printf '%b╭%s╮%b\n' "$CYAN" "$(repeat '═' "$((w-2))")" "$RESET"
  printf '%b│%b%*s%bCJH%b %s%b%*s%b│%b\n' "$CYAN" "$RESET" "$(( (w-30)/2 ))" '' "$BOLD$WHITE" "$CYAN" 'BOT HOSTING' "$RESET" "$(( (w-30)/2 ))" '' "$CYAN" "$RESET"
  printf '%b│%b%*s%bAurora Glass Terminal  •  v%s%b%*s%b│%b\n' "$CYAN" "$RESET" "$(( (w-46)/2 ))" '' "$SLATE" "$APP_VERSION" "$RESET" "$(( (w-46)/2 ))" '' "$CYAN" "$RESET"
  printf '%b╰%s╯%b\n\n' "$VIOLET" "$(repeat '═' "$((w-2))")" "$RESET"

  section 'CONTROL CENTER'
  local count="$(bot_count)" online=0 d n st
  while IFS= read -r d; do n="$(basename "$d")"; st="$(pm2_state "$n")"; [[ "$st" == online ]] && ((online+=1)); done < <(bot_dirs)
  printf '  %bBOTS%b  %s installed   %b● %s online%b     %bSTORE%b %s\n\n' "$SLATE" "$RESET" "$count" "$GREEN" "$online" "$RESET" "$SLATE" "$RESET" "$BASE_DIR"

  printf '  %b╭─%b %b01%b  CREATE BOT        %bDeploy a new Discord bot%b\n' "$INDIGO" "$RESET" "$CYAN$BOLD" "$RESET" "$SLATE" "$RESET"
  printf '  %b│  %b02%b  START BOT         %bBring a bot online%b\n' "$INDIGO" "$RESET" "$GREEN$BOLD" "$RESET" "$SLATE" "$RESET"
  printf '  %b│  %b03%b  STOP BOT          %bGraceful process stop%b\n' "$INDIGO" "$RESET" "$AMBER$BOLD" "$RESET" "$SLATE" "$RESET"
  printf '  %b│  %b04%b  RESTART BOT       %bRecover/reload a bot%b\n' "$INDIGO" "$RESET" "$SKY$BOLD" "$RESET" "$SLATE" "$RESET"
  printf '  %b│  %b05%b  LIVE LOGS         %bInspect runtime output%b\n' "$INDIGO" "$RESET" "$VIOLET$BOLD" "$RESET" "$SLATE" "$RESET"
  printf '  %b│  %b06%b  REMOVE BOT        %bProtected deletion%b\n' "$INDIGO" "$RESET" "$RED$BOLD" "$RESET" "$SLATE" "$RESET"
  printf '  %b│  %b07%b  SYSTEM HEALTH     %bServer + bot telemetry%b\n' "$INDIGO" "$RESET" "$CYAN$BOLD" "$RESET" "$SLATE" "$RESET"
  printf '  %b│  %b08%b  RUNTIME UPDATE     %bRepair/update PM2 runtime%b\n' "$INDIGO" "$RESET" "$PINK$BOLD" "$RESET" "$SLATE" "$RESET"
  printf '  %b╰─ %b09%b  ABOUT             %bVersion and storage info%b\n' "$INDIGO" "$RESET" "$WHITE$BOLD" "$RESET" "$SLATE" "$RESET"
  printf '\n  %bQ%b  Quit\n' "$SLATE$BOLD" "$RESET"
  printf '\n%bSelect%b %b›%b ' "$WHITE$BOLD" "$RESET" "$CYAN$BOLD" "$RESET"
  read -r choice
  case "$choice" in
    1|01) create_bot;; 2|02) start_bot;; 3|03) stop_bot;; 4|04) restart_bot;; 5|05) logs_bot;; 6|06) remove_bot;; 7|07) health;; 8|08) update_runtime;; 9|09) show_about;; q|Q|quit|exit) exit 0;; *) err 'Unknown menu option.'; sleep .8;;
  esac
}

setup_runtime
install_pm2_startup
while :; do menu; done
