#!/usr/bin/env bash
set -Eeuo pipefail

APP='CJH BOT HOSTING'
VERSION='3.0.0'
BASE="${HOME}/cjh-bots"
SUDO=''
[[ $EUID -eq 0 ]] || SUDO='sudo'

ESC=$'\033'
RESET="${ESC}[0m"; BOLD="${ESC}[1m"; DIM="${ESC}[2m"
WHITE="${ESC}[38;2;248;250;255m"; MUTED="${ESC}[38;2;148;163;184m"
CYAN="${ESC}[38;2;56;211;255m"; BLUE="${ESC}[38;2;96;135;255m"
PURPLE="${ESC}[38;2;167;100;255m"; PINK="${ESC}[38;2;240;95;190m"
GREEN="${ESC}[38;2;54;224;140m"; GOLD="${ESC}[38;2;255;196;79m"; RED="${ESC}[38;2;255;91;116m"

command -v tput >/dev/null 2>&1 || true
cols(){ local n; n="$(tput cols 2>/dev/null || echo 100)"; ((n<78)) && n=78; echo "$n"; }
repeat(){ printf '%*s' "$2" '' | tr ' ' "$1"; }
clear_ui(){ printf '\033[2J\033[H'; }
box(){ local t="$1" w="$(cols)"; local fill=$((w-${#t}-6)); ((fill<1))&&fill=1; printf '%b╭─ %b%s%b %s╮%b\n' "$PURPLE" "$BOLD$WHITE" "$t" "$RESET" "$(repeat '─' "$fill")" "$RESET"; }
endbox(){ local w="$(cols)"; printf '%b╰%s╯%b\n' "$PURPLE" "$(repeat '─' $((w-2)))" "$RESET"; }
hr(){ printf '%b%s%b\n' "$PURPLE" "$(repeat '─' "$(cols)")" "$RESET"; }
msg(){ printf '%b%s%b\n' "$1" "$2" "$RESET"; }
pause(){ printf '\n%bPress Enter to continue...%b' "$MUTED" "$RESET"; read -r _; }

need(){
  if ! command -v "$1" >/dev/null 2>&1; then
    printf '%bInstalling %s...%b\n' "$CYAN" "$1" "$RESET"
    $SUDO apt-get update -y >/dev/null
    $SUDO apt-get install -y "$1" >/dev/null
  fi
}
setup_runtime(){
  need curl; need ca-certificates
  if ! command -v node >/dev/null 2>&1; then
    curl -fsSL https://deb.nodesource.com/setup_20.x | $SUDO -E bash -
    $SUDO apt-get install -y nodejs
  fi
  if ! command -v pm2 >/dev/null 2>&1; then $SUDO npm install -g pm2; fi
  mkdir -p "$BASE"; chmod 700 "$BASE"
}
safe(){ printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9._-]+/-/g;s/^-+//;s/-+$//'; }

status(){
  local name="$1" state='offline'
  if pm2 describe "$name" >/dev/null 2>&1; then
    state="$(pm2 jlist 2>/dev/null | node - "$name" <<'NODE'
let s=''; process.stdin.on('data',d=>s+=d).on('end',()=>{try{const n=process.argv[2],a=JSON.parse(s),p=a.find(x=>x.name===n);console.log(p?.pm2_env?.status||'unknown')}catch{console.log('unknown')}})
NODE
    )"
  fi
  case "$state" in online) printf '%b● ONLINE%b' "$GREEN" "$RESET";; stopped) printf '%b● STOPPED%b' "$GOLD" "$RESET";; errored) printf '%b● ERROR%b' "$RED" "$RESET";; *) printf '%b● OFFLINE%b' "$MUTED" "$RESET";; esac
}

list_bots(){
  mkdir -p "$BASE"; shopt -s nullglob
  local found=0 d n
  printf '%b%-28s %-16s %s%b\n' "$MUTED" 'BOT' 'PROCESS' 'STATUS' "$RESET"
  printf '%b%s%b\n' "$MUTED" "$(repeat '─' 68)" "$RESET"
  for d in "$BASE"/*; do
    [[ -d "$d" ]] || continue; found=1; n="$(basename "$d")"
    printf '%-28s %-16s ' "$n" "PM2"; status "$n"; printf '\n'
  done
  shopt -u nullglob
  ((found==0)) && msg "$MUTED" 'No bots installed.'
}

create_bot(){
 clear_ui; box 'CREATE DISCORD BOT';
 setup_runtime
 printf '%bBot name%b: ' "$MUTED" "$RESET"; read -r raw; local name; name="$(safe "${raw:-bot-$(date +%s)}")"; [[ -n "$name" ]] || name="bot-$(date +%s)"
 local dir="$BASE/$name"
 [[ ! -e "$dir" ]] || { msg "$RED" 'A bot with that name already exists.'; pause; return; }
 printf '%bBot token%b: ' "$MUTED" "$RESET"; read -r -s token; printf '\n'
 printf '%bApplication / Client ID%b: ' "$MUTED" "$RESET"; read -r client_id
 printf '%bAdmin Discord User ID (optional)%b: ' "$MUTED" "$RESET"; read -r admin_id
 [[ -n "$token" && -n "$client_id" ]] || { msg "$RED" 'Token and Client ID are required.'; pause; return; }
 mkdir -p "$dir"; chmod 700 "$dir"; umask 077
 cat > "$dir/package.json" <<'JSON'
{"name":"cjh-bot","version":"3.0.0","private":true,"main":"bot.js","scripts":{"start":"node bot.js"},"dependencies":{"discord.js":"^14.22.1","@discordjs/voice":"^0.19.0"}}
JSON
 cat > "$dir/.env" <<EOF
BOT_TOKEN=$token
CLIENT_ID=$client_id
ADMIN_ID=$admin_id
EOF
 chmod 600 "$dir/.env"
 cat > "$dir/bot.js" <<'NODE'
const fs=require('fs');const {Client,GatewayIntentBits,REST,Routes,SlashCommandBuilder,EmbedBuilder,ActivityType}=require('discord.js');const {joinVoiceChannel}=require('@discordjs/voice');
const env=Object.fromEntries(fs.readFileSync('.env','utf8').split(/\r?\n/).filter(Boolean).map(x=>{const i=x.indexOf('=');return[x.slice(0,i),x.slice(i+1)]}));
if(!env.BOT_TOKEN||!env.CLIENT_ID){console.error('Missing credentials');process.exit(1)}
const c=new Client({intents:[GatewayIntentBits.Guilds,GatewayIntentBits.GuildMessages,GatewayIntentBits.MessageContent,GatewayIntentBits.GuildMembers,GatewayIntentBits.GuildVoiceStates]});
const cmds=[new SlashCommandBuilder().setName('ping').setDescription('Show bot latency'),new SlashCommandBuilder().setName('security').setDescription('Show security status'),new SlashCommandBuilder().setName('joinvc').setDescription('Join your current voice channel')].map(x=>x.toJSON());
(async()=>{try{await new REST({version:'10'}).setToken(env.BOT_TOKEN).put(Routes.applicationCommands(env.CLIENT_ID),{body:cmds})}catch(e){console.error('Command registration:',e.message)}})();
c.once('ready',()=>{console.log(`[CJH] ${c.user.tag} online`);c.user.setActivity('CJH Bot Hosting',{type:ActivityType.Watching})});
c.on('messageCreate',async m=>{if(m.author.bot||!m.guild)return;if(m.content.toLowerCase().startsWith('!ping'))await m.reply(`Pong! ${c.ws.ping}ms`)});
c.on('interactionCreate',async i=>{if(!i.isChatInputCommand())return;try{if(i.commandName==='ping')await i.reply({content:`Pong! ${c.ws.ping}ms`,ephemeral:true});else if(i.commandName==='security')await i.reply({embeds:[new EmbedBuilder().setColor(0x8b5cf6).setTitle('CJH Security').setDescription('Bot security and moderation status is available.')],ephemeral:true});else if(i.commandName==='joinvc'){const ch=i.member?.voice?.channel;if(!ch)return i.reply({content:'Join a voice channel first.',ephemeral:true});joinVoiceChannel({channelId:ch.id,guildId:i.guild.id,adapterCreator:i.guild.voiceAdapterCreator});await i.reply({content:'Joined your voice channel.',ephemeral:true})}}catch(e){if(!i.replied)await i.reply({content:'Command failed.',ephemeral:true}).catch(()=>{})}});
c.login(env.BOT_TOKEN).catch(e=>{console.error('Login failed:',e.message);process.exit(1)});
NODE
 (cd "$dir" && npm install --omit=dev)
 pm2 delete "$name" >/dev/null 2>&1 || true; pm2 start "$dir/bot.js" --name "$name" --cwd "$dir" --time; pm2 save >/dev/null
 msg "$GREEN" "Bot $name created and started."; pause
}
select_bot(){ list_bots; printf '\n%bBot name%b: ' "$CYAN" "$RESET"; read -r SELECTED; SELECTED="$(safe "$SELECTED")"; [[ -d "$BASE/$SELECTED" ]]; }
start_bot(){ clear_ui;box 'START BOT';if select_bot;then pm2 start "$SELECTED" >/dev/null 2>&1||pm2 start "$BASE/$SELECTED/bot.js" --name "$SELECTED" --cwd "$BASE/$SELECTED" >/dev/null;pm2 save >/dev/null;msg "$GREEN" "$SELECTED started.";else msg "$RED" 'Bot not found.';fi;pause; }
stop_bot(){ clear_ui;box 'STOP BOT';if select_bot;then pm2 stop "$SELECTED" >/dev/null 2>&1||true;pm2 save >/dev/null;msg "$GOLD" "$SELECTED stopped.";else msg "$RED" 'Bot not found.';fi;pause; }
restart_bot(){ clear_ui;box 'RESTART BOT';if select_bot;then pm2 restart "$SELECTED" >/dev/null 2>&1||pm2 start "$BASE/$SELECTED/bot.js" --name "$SELECTED" --cwd "$BASE/$SELECTED" >/dev/null;pm2 save >/dev/null;msg "$GREEN" "$SELECTED restarted.";else msg "$RED" 'Bot not found.';fi;pause; }
logs_bot(){ clear_ui;box 'BOT LOGS';if select_bot;then pm2 logs "$SELECTED" --lines 80;else msg "$RED" 'Bot not found.';fi;pause; }
remove_bot(){ clear_ui;box 'REMOVE BOT';if select_bot;then printf '%bType DELETE to permanently remove %s%b: ' "$RED" "$SELECTED" "$RESET";read -r c;if [[ "$c"==DELETE ]];then pm2 delete "$SELECTED" >/dev/null 2>&1||true;rm -rf -- "$BASE/$SELECTED";pm2 save >/dev/null;msg "$GREEN" 'Bot removed.';else msg "$GOLD" 'Cancelled.';fi;else msg "$RED" 'Bot not found.';fi;pause; }
health(){ clear_ui;box 'SYSTEM HEALTH';printf '  %bHostname%b  %s\n' "$MUTED" "$RESET" "$(hostname)";printf '  %bNode%b      %s\n' "$MUTED" "$RESET" "$(node -v 2>/dev/null||echo unavailable)";printf '  %bPM2%b       %s\n' "$MUTED" "$RESET" "$(pm2 -v 2>/dev/null||echo unavailable)";printf '  %bMemory%b    %s\n' "$MUTED" "$RESET" "$(free -h|awk '/Mem:/ {print $3" / "$2}')";printf '  %bDisk%b      %s\n\n' "$MUTED" "$RESET" "$(df -h "$BASE"|awk 'NR==2 {print $3" / "$2" used; "$4" free"}')";list_bots;endbox;pause; }
update_runtime(){ clear_ui;box 'UPDATE RUNTIME';setup_runtime;pm2 save >/dev/null 2>&1||true;msg "$GREEN" 'Node.js and PM2 checks completed.';pause; }

menu(){
 clear_ui
 printf '%b╭%s╮%b\n' "$CYAN" "$(repeat '═' $(( $(cols)-2 )))" "$RESET"
 printf '%b%s%b%b%s%b\n' "$CYAN" "$BOLD" 'CJH' "$WHITE" ' BOT HOSTING' "$RESET"
 printf '%b%*s%b\n' "$MUTED" $(( ($(cols)-38)/2 )) '' 'Premium VPS Bot Manager • v'"$VERSION" "$RESET" 2>/dev/null || true
 printf '%b╰%s╯%b\n\n' "$PURPLE" "$(repeat '═' $(( $(cols)-2 )))" "$RESET"
 box 'MAIN MENU'
 printf '  %b[1]%b  %bCreate Bot%b       %bDeploy a new managed bot%b\n' "$CYAN" "$RESET" "$WHITE" "$RESET" "$MUTED" "$RESET"
 printf '  %b[2]%b  %bStart Bot%b        %bStart a stopped bot%b\n' "$GREEN" "$RESET" "$WHITE" "$RESET" "$MUTED" "$RESET"
 printf '  %b[3]%b  %bStop Bot%b         %bGracefully stop a bot%b\n' "$GOLD" "$RESET" "$WHITE" "$RESET" "$MUTED" "$RESET"
 printf '  %b[4]%b  %bRestart Bot%b      %bRestart and recover process%b\n' "$BLUE" "$RESET" "$WHITE" "$RESET" "$MUTED" "$RESET"
 printf '  %b[5]%b  %bBot Logs%b         %bLive PM2 output%b\n' "$PURPLE" "$RESET" "$WHITE" "$RESET" "$MUTED" "$RESET"
 printf '  %b[6]%b  %bRemove Bot%b       %bProtected permanent delete%b\n' "$RED" "$RESET" "$WHITE" "$RESET" "$MUTED" "$RESET"
 printf '  %b[7]%b  %bSystem Health%b     %bCPU/RAM/disk + bot status%b\n' "$CYAN" "$RESET" "$WHITE" "$RESET" "$MUTED" "$RESET"
 printf '  %b[8]%b  %bUpdate Runtime%b    %bNode.js + PM2 maintenance%b\n' "$PINK" "$RESET" "$WHITE" "$RESET" "$MUTED" "$RESET"
 printf '  %b[9]%b  %bExit%b              %bClose safely%b\n' "$MUTED" "$RESET" "$WHITE" "$RESET" "$MUTED" "$RESET"
 endbox
 printf '\n%bSelect %b› %b' "$WHITE" '1-9' "$CYAN"; read -r choice
 case "$choice" in 1)create_bot;;2)start_bot;;3)stop_bot;;4)restart_bot;;5)logs_bot;;6)remove_bot;;7)health;;8)update_runtime;;9|q|Q)exit 0;;*)msg "$RED" 'Invalid option.';sleep .7;;esac
}

setup_runtime
while :; do menu; done
