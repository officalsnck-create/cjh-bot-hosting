#!/usr/bin/env bash
set -Eeuo pipefail

# CJH Bot Hosting - interactive VPS installer and manager
# Terminal UI: glass-inspired panels, ANSI truecolor gradients, live status.

APP_NAME="CJH BOT HOSTING"
APP_VERSION="2.0.0"
INSTALL_DIR="${HOME}/cjh-bots"

# Truecolor palette: deep navy + cyan/blue/purple/magenta accents.
RESET='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'
WHITE='\033[38;2;245;248;255m'
MUTED='\033[38;2;145;158;180m'
CYAN='\033[38;2;73;225;255m'
BLUE='\033[38;2;89;140;255m'
PURPLE='\033[38;2;173;111;255m'
MAGENTA='\033[38;2;236;104;255m'
GREEN='\033[38;2;72;230;151m'
YELLOW='\033[38;2;255;202;79m'
RED='\033[38;2;255;91;119m'

supports_color() {
    [[ -t 1 ]] && [[ "${TERM:-}" != "dumb" ]]
}

if ! supports_color; then
    RESET=''; BOLD=''; DIM=''; WHITE=''; MUTED=''; CYAN=''; BLUE=''; PURPLE=''; MAGENTA=''; GREEN=''; YELLOW=''; RED=''
fi

trap 'printf "${RESET}"' EXIT

clear_screen() { printf '\033[2J\033[H'; }

term_width() {
    local width
    width="$(tput cols 2>/dev/null || printf '100')"
    (( width < 72 )) && width=72
    printf '%s' "$width"
}

repeat_char() {
    local char="$1" count="$2"
    printf '%*s' "$count" '' | tr ' ' "$char"
}

line() {
    local width="$(term_width)"
    printf '%b%s%b\n' "${PURPLE}" "$(repeat_char '─' "$width")" "${RESET}"
}

center_text() {
    local text="$1" width="$(term_width)" visible_length
    visible_length="${#text}"
    local left=$(( (width - visible_length) / 2 ))
    (( left < 0 )) && left=0
    printf '%*s%b\n' "$left" '' "$text"
}

panel_title() {
    local title="$1"
    printf '%b╭─%b %b%s%b %b' "${PURPLE}" "${RESET}" "${BOLD}${WHITE}" "$title" "${RESET}" "${PURPLE}"
    local used=$(( ${#title} + 5 ))
    local width="$(term_width)"
    local fill=$(( width - used ))
    (( fill < 1 )) && fill=1
    printf '%s╮%b\n' "$(repeat_char '─' "$fill")" "${RESET}"
}

panel_bottom() {
    local width="$(term_width)"
    printf '%b╰%s╯%b\n' "${PURPLE}" "$(repeat_char '─' $(( width - 2 )))" "${RESET}"
}

status_dot() {
    local state="$1"
    case "$state" in
        online) printf '%b● ONLINE%b' "${GREEN}" "${RESET}" ;;
        stopped) printf '%b● STOPPED%b' "${RED}" "${RESET}" ;;
        installed) printf '%b● READY%b' "${CYAN}" "${RESET}" ;;
        warning) printf '%b● CHECK%b' "${YELLOW}" "${RESET}" ;;
        *) printf '%b● UNKNOWN%b' "${MUTED}" "${RESET}" ;;
    esac
}

pause_menu() {
    printf '\n%bPress Enter to return to the menu...%b' "${MUTED}" "${RESET}"
    read -r _
}

require_sudo() {
    if [[ "${EUID}" -eq 0 ]]; then
        SUDO=""
    elif command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        printf '%bThis installer needs root privileges or sudo.%b\n' "${RED}" "${RESET}"
        exit 1
    fi
}

install_base_dependencies() {
    printf '%b[1/3]%b Checking system dependencies...\n' "${CYAN}" "${RESET}"
    if ! command -v curl >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1; then
        $SUDO apt-get update -y
        $SUDO apt-get install -y curl git ca-certificates
    fi

    if ! command -v node >/dev/null 2>&1; then
        printf '%b[2/3]%b Installing Node.js 20 LTS...\n' "${BLUE}" "${RESET}"
        curl -fsSL https://deb.nodesource.com/setup_20.x | $SUDO -E bash -
        $SUDO apt-get install -y nodejs
    else
        printf '%b[2/3]%b Node.js %s already installed.\n' "${BLUE}" "${RESET}" "$(node --version)"
    fi

    if ! command -v pm2 >/dev/null 2>&1; then
        printf '%b[3/3]%b Installing PM2...\n' "${PURPLE}" "${RESET}"
        $SUDO npm install -g pm2
    else
        printf '%b[3/3]%b PM2 %s already installed.\n' "${PURPLE}" "${RESET}" "$(pm2 --version 2>/dev/null || printf '?')"
    fi
}

safe_name() {
    local raw="$1"
    raw="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9._-]+/-/g; s/^-+//; s/-+$//')"
    printf '%s' "$raw"
}

create_bot() {
    clear_screen
    panel_title "CREATE BOT"
    printf '%bCreate a managed Discord bot instance%b\n\n' "${CYAN}${BOLD}" "${RESET}"

    install_base_dependencies
    mkdir -p "$INSTALL_DIR"

    printf '\n%bDiscord configuration%b\n' "${BOLD}${WHITE}" "${RESET}"
    printf '%bBot token:%b ' "${MUTED}" "${RESET}"
    read -r -s BOT_TOKEN
    printf '\n%bApplication / Client ID:%b ' "${MUTED}" "${RESET}"
    read -r CLIENT_ID
    printf '%bAdmin Discord User ID:%b ' "${MUTED}" "${RESET}"
    read -r ADMIN_ID
    printf '%bBot name:%b ' "${MUTED}" "${RESET}"
    read -r BOT_NAME

    BOT_NAME="$(safe_name "${BOT_NAME:-discord-bot-$(date +%s)}")"
    [[ -z "$BOT_NAME" ]] && BOT_NAME="discord-bot-$(date +%s)"
    BOT_DIR="$INSTALL_DIR/$BOT_NAME"

    if [[ -e "$BOT_DIR" ]]; then
        printf '%bA bot named %s already exists.%b\n' "${RED}" "$BOT_NAME" "${RESET}"
        pause_menu
        return
    fi

    mkdir -p "$BOT_DIR"
    umask 077

    cat > "$BOT_DIR/package.json" <<'JSON'
{
  "name": "cjh-discord-bot",
  "version": "2.0.0",
  "private": true,
  "description": "Discord bot managed by CJH Bot Hosting",
  "main": "bot.js",
  "scripts": { "start": "node bot.js" },
  "dependencies": {
    "discord.js": "^14.22.1",
    "@discordjs/voice": "^0.19.0"
  }
}
JSON

    cat > "$BOT_DIR/config.json" <<'JSON'
{
  "prefix": "!",
  "timeoutDuration": 600000,
  "badWords": ["gaali1", "gaali2", "bsdk", "mc", "bc", "madarchod", "behanchod", "gali"]
}
JSON

    cat > "$BOT_DIR/.env" <<EOF
BOT_TOKEN=$(printf '%s' "$BOT_TOKEN" | sed 's/[\\&/]/\\&/g')
CLIENT_ID=$(printf '%s' "$CLIENT_ID" | sed 's/[\\&/]/\\&/g')
ADMIN_ID=$(printf '%s' "$ADMIN_ID" | sed 's/[\\&/]/\\&/g')
EOF
    chmod 600 "$BOT_DIR/.env"

    cat > "$BOT_DIR/bot.js" <<'NODE'
const fs = require('fs');
const {
  Client,
  GatewayIntentBits,
  EmbedBuilder,
  REST,
  Routes,
  SlashCommandBuilder,
  ActivityType
} = require('discord.js');
const { joinVoiceChannel } = require('@discordjs/voice');

function loadEnv(path) {
  if (!fs.existsSync(path)) return {};
  return Object.fromEntries(fs.readFileSync(path, 'utf8').split(/\r?\n/).filter(Boolean).map(line => {
    const index = line.indexOf('=');
    return index < 0 ? [line, ''] : [line.slice(0, index), line.slice(index + 1)];
  }));
}

const env = loadEnv('./.env');
const TOKEN = env.BOT_TOKEN;
const CLIENT_ID = env.CLIENT_ID;
const ADMIN_ID = env.ADMIN_ID;
const config = JSON.parse(fs.readFileSync('./config.json', 'utf8'));

if (!TOKEN || !CLIENT_ID) {
  console.error('[CJH] Missing BOT_TOKEN or CLIENT_ID in .env');
  process.exit(1);
}

const client = new Client({
  intents: [
    GatewayIntentBits.Guilds,
    GatewayIntentBits.GuildMessages,
    GatewayIntentBits.MessageContent,
    GatewayIntentBits.GuildMembers,
    GatewayIntentBits.GuildVoiceStates
  ]
});

const commands = [
  new SlashCommandBuilder().setName('ping').setDescription('Check bot latency'),
  new SlashCommandBuilder().setName('security').setDescription('Show server security status'),
  new SlashCommandBuilder().setName('joinvc').setDescription('Join your current voice channel')
].map(command => command.toJSON());

(async () => {
  try {
    const rest = new REST({ version: '10' }).setToken(TOKEN);
    await rest.put(Routes.applicationCommands(CLIENT_ID), { body: commands });
    console.log('[CJH] Slash commands registered.');
  } catch (error) {
    console.error('[CJH] Slash command registration failed:', error.message);
  }
})();

client.once('ready', () => {
  console.log(`[CJH] ${client.user.tag} is online.`);
  client.user.setActivity('CJH Bot Hosting', { type: ActivityType.Watching });
});

client.on('messageCreate', async message => {
  if (message.author.bot || !message.guild) return;
  const content = message.content.toLowerCase();
  if (config.badWords.some(word => content.includes(word))) {
    try {
      await message.delete().catch(() => {});
      const member = await message.guild.members.fetch(message.author.id).catch(() => null);
      if (member?.moderatable) {
        await member.timeout(config.timeoutDuration, 'CJH automatic moderation');
      }
    } catch (error) {
      console.error('[CJH] Moderation error:', error.message);
    }
    return;
  }
  if (!message.content.startsWith(config.prefix)) return;
  const command = message.content.slice(config.prefix.length).trim().split(/\s+/)[0]?.toLowerCase();
  if (command === 'ping') await message.reply(`Pong! ${client.ws.ping}ms`);
});

client.on('interactionCreate', async interaction => {
  if (!interaction.isChatInputCommand()) return;
  try {
    if (interaction.commandName === 'ping') {
      await interaction.reply({ content: `Pong! ${client.ws.ping}ms`, ephemeral: true });
    } else if (interaction.commandName === 'security') {
      const embed = new EmbedBuilder()
        .setColor(0x8b5cf6)
        .setTitle('CJH Security')
        .setDescription('Automatic prohibited-language detection and timeout protection are active.')
        .setTimestamp();
      await interaction.reply({ embeds: [embed], ephemeral: true });
    } else if (interaction.commandName === 'joinvc') {
      const channel = interaction.member?.voice?.channel;
      if (!channel) return interaction.reply({ content: 'Join a voice channel first.', ephemeral: true });
      joinVoiceChannel({ channelId: channel.id, guildId: interaction.guild.id, adapterCreator: interaction.guild.voiceAdapterCreator });
      await interaction.reply({ content: 'Joined your voice channel.', ephemeral: true });
    }
  } catch (error) {
    console.error('[CJH] Interaction error:', error.message);
    if (!interaction.replied && !interaction.deferred) {
      await interaction.reply({ content: 'The command could not be completed.', ephemeral: true }).catch(() => {});
    }
  }
});

client.login(TOKEN).catch(error => {
  console.error('[CJH] Login failed:', error.message);
  process.exitCode = 1;
});
NODE

    printf '\n%bInstalling bot dependencies...%b\n' "${CYAN}" "${RESET}"
    (cd "$BOT_DIR" && npm install --omit=dev)

    pm2 delete "$BOT_NAME" >/dev/null 2>&1 || true
    pm2 start "$BOT_DIR/bot.js" --name "$BOT_NAME" --cwd "$BOT_DIR" --time
    pm2 save >/dev/null

    clear_screen
    panel_title "BOT CREATED"
    printf '\n%b%s%b  ' "${GREEN}${BOLD}" "$BOT_NAME" "${RESET}"
    status_dot online
    printf '\n\n%bPath%b    %s\n%bPM2%b     %s\n%bVersion%b %s\n' "${MUTED}" "${RESET}" "$BOT_DIR" "${MUTED}" "${RESET}" "$APP_VERSION" "${MUTED}" "${RESET}" "$APP_VERSION"
    panel_bottom
    pause_menu
}

list_bots() {
    mkdir -p "$INSTALL_DIR"
    printf '%b%-24s %-12s %-12s%b\n' "${MUTED}" "BOT" "PM2" "STATUS" "${RESET}"
    printf '%b%s%b\n' "${MUTED}" "$(repeat_char '─' 52)" "${RESET}"
    local found=0 dir name state
    shopt -s nullglob
    for dir in "$INSTALL_DIR"/*; do
        [[ -d "$dir" ]] || continue
        found=1
        name="$(basename "$dir")"
        if pm2 describe "$name" >/dev/null 2>&1; then
            state="$(pm2 jlist 2>/dev/null | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{let a=JSON.parse(s),n=process.argv[1],x=a.find(p=>p.name===n);console.log(x?.pm2_env?.status||"unknown")}catch{console.log("unknown")}})' "$name" 2>/dev/null || printf 'unknown')"
        else
            state="not-managed"
        fi
        case "$state" in
            online) printf '%-24s %-12s %bONLINE%b\n' "$name" "PM2" "${GREEN}" "${RESET}" ;;
            stopped) printf '%-24s %-12s %bSTOPPED%b\n' "$name" "PM2" "${RED}" "${RESET}" ;;
            *) printf '%-24s %-12s %b%s%b\n' "$name" "PM2" "${YELLOW}" "$state" "${RESET}" ;;
        esac
    done
    shopt -u nullglob
    (( found == 0 )) && printf '%bNo CJH bots installed yet.%b\n' "${MUTED}" "${RESET}"
}

choose_bot() {
    local prompt="$1" name
    list_bots
    printf '\n%b%s:%b ' "${CYAN}" "$prompt" "${RESET}"
    read -r name
    name="$(safe_name "$name")"
    if [[ -z "$name" || ! -d "$INSTALL_DIR/$name" ]]; then
        printf '%bBot not found: %s%b\n' "${RED}" "${name:-<empty>}" "${RESET}"
        return 1
    fi
    SELECTED_BOT="$name"
}

start_bot() {
    clear_screen; panel_title "START BOT"
    if choose_bot "Bot name"; then
        pm2 start "$SELECTED_BOT" >/dev/null 2>&1 || pm2 start "$INSTALL_DIR/$SELECTED_BOT/bot.js" --name "$SELECTED_BOT" --cwd "$INSTALL_DIR/$SELECTED_BOT" >/dev/null
        pm2 save >/dev/null
        printf '\n%b%s is now online.%b\n' "${GREEN}${BOLD}" "$SELECTED_BOT" "${RESET}"
    fi
    pause_menu
}

stop_bot() {
    clear_screen; panel_title "STOP BOT"
    if choose_bot "Bot name"; then
        pm2 stop "$SELECTED_BOT" >/dev/null 2>&1 || true
        pm2 save >/dev/null
        printf '\n%b%s stopped.%b\n' "${YELLOW}${BOLD}" "$SELECTED_BOT" "${RESET}"
    fi
    pause_menu
}

uninstall_bot() {
    clear_screen; panel_title "UNINSTALL BOT"
    if choose_bot "Bot name"; then
        printf '%bDelete %s permanently? [y/N]:%b ' "${RED}" "$SELECTED_BOT" "${RESET}"
        read -r confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            pm2 delete "$SELECTED_BOT" >/dev/null 2>&1 || true
            rm -rf -- "$INSTALL_DIR/$SELECTED_BOT"
            pm2 save >/dev/null
            printf '%bBot removed successfully.%b\n' "${GREEN}" "${RESET}"
        else
            printf '%bCancelled.%b\n' "${MUTED}" "${RESET}"
        fi
    fi
    pause_menu
}

update_panel() {
    clear_screen; panel_title "UPDATE"
    printf '%bRefreshing installer dependencies and PM2...%b\n\n' "${CYAN}" "${RESET}"
    install_base_dependencies
    printf '\n%bUpdate check completed.%b\n' "${GREEN}" "${RESET}"
    pause_menu
}

show_status() {
    clear_screen; panel_title "LIVE STATUS"
    printf '%bSystem%b\n' "${BOLD}${WHITE}" "${RESET}"
    printf '  OS       : %s\n' "$(. /etc/os-release 2>/dev/null && printf '%s %s' "${NAME:-Linux}" "${VERSION_ID:-}" || printf 'Linux')"
    printf '  Node.js  : %s\n' "$(node --version 2>/dev/null || printf 'not installed')"
    printf '  npm      : %s\n' "$(npm --version 2>/dev/null || printf 'not installed')"
    printf '  PM2      : %s\n' "$(pm2 --version 2>/dev/null || printf 'not installed')"
    printf '  Storage  : %s\n' "$(df -h "$INSTALL_DIR" 2>/dev/null | awk 'NR==2 {print $4 " free / " $2}')"
    printf '\n%bBots%b\n' "${BOLD}${WHITE}" "${RESET}"
    list_bots
    panel_bottom
    pause_menu
}

show_header() {
    local width="$(term_width)"
    clear_screen
    printf '%b╭%s╮%b\n' "${CYAN}" "$(repeat_char '═' $(( width - 2 )))" "${RESET}"
    center_text "${BOLD}${CYAN}CJH${RESET} ${BOLD}${WHITE}BOT HOSTING${RESET}"
    center_text "${DIM}${MUTED}Glass Terminal • VPS Bot Management • v${APP_VERSION}${RESET}"
    printf '%b╰%s╯%b\n' "${PURPLE}" "$(repeat_char '═' $(( width - 2 )))" "${RESET}"

    printf '\n'
    panel_title "SYSTEM OVERVIEW"
    printf '  %bHOST%b       %s\n' "${MUTED}" "${RESET}" "$(hostname 2>/dev/null || printf 'unknown')"
    printf '  %bNODE%b       %s\n' "${MUTED}" "${RESET}" "$(node --version 2>/dev/null || printf 'not installed')"
    printf '  %bPM2%b        %s\n' "${MUTED}" "${RESET}" "$(pm2 --version 2>/dev/null || printf 'not installed')"
    printf '  %bBOT STORE%b  %s\n' "${MUTED}" "${RESET}" "$INSTALL_DIR"
    panel_bottom

    printf '\n'
    panel_title "MANAGEMENT"
    printf '  %b[1]%b  %bCREATE BOT%b       %bDeploy a new Discord bot%b\n' "${CYAN}" "${RESET}" "${WHITE}${BOLD}" "${RESET}" "${MUTED}" "${RESET}"
    printf '  %b[2]%b  %bUNINSTALL%b        %bRemove a bot safely%b\n' "${RED}" "${RESET}" "${WHITE}${BOLD}" "${RESET}" "${MUTED}" "${RESET}"
    printf '  %b[3]%b  %bUPDATE%b           %bRefresh dependencies%b\n' "${BLUE}" "${RESET}" "${WHITE}${BOLD}" "${RESET}" "${MUTED}" "${RESET}"
    printf '  %b[4]%b  %bSTART BOT%b         %bBring a bot online%b\n' "${GREEN}" "${RESET}" "${WHITE}${BOLD}" "${RESET}" "${MUTED}" "${RESET}"
    printf '  %b[5]%b  %bSTOP BOT%b          %bStop a running bot%b\n' "${YELLOW}" "${RESET}" "${WHITE}${BOLD}" "${RESET}" "${MUTED}" "${RESET}"
    printf '  %b[6]%b  %bLIVE STATUS%b       %bSystem + bot health%b\n' "${PURPLE}" "${RESET}" "${WHITE}${BOLD}" "${RESET}" "${MUTED}" "${RESET}"
    printf '  %b[7]%b  %bEXIT%b              %bClose menu%b\n' "${MAGENTA}" "${RESET}" "${WHITE}${BOLD}" "${RESET}" "${MUTED}" "${RESET}"
    panel_bottom
}

require_sudo
mkdir -p "$INSTALL_DIR"

while true; do
    show_header
    printf '\n%bSelect an option%b %b›%b ' "${BOLD}${WHITE}" "${RESET}" "${CYAN}" "${RESET}"
    read -r choice
    case "$choice" in
        1) create_bot ;;
        2) uninstall_bot ;;
        3) update_panel ;;
        4) start_bot ;;
        5) stop_bot ;;
        6) show_status ;;
        7|q|Q|exit) clear_screen; printf '%bCJH Bot Hosting closed.%b\n' "${CYAN}" "${RESET}"; exit 0 ;;
        *) printf '\n%bInvalid option. Choose 1-7.%b\n' "${RED}" "${RESET}"; sleep 1 ;;
    esac
done
