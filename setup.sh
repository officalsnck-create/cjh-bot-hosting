#!/bin/bash

# ==========================================
#              CJH BOT PANEL
# ==========================================

show_menu() {
    clear
    echo "=========================================="
    echo "               CJH BOT                    "
    echo "=========================================="
    echo "1. CREATE Bot (Setup & Run)"
    echo "2. UNINSTALL Bot (Stop & Delete)"
    echo "3. UPDATE Bot (Pull latest from GitHub)"
    echo "4. START Bot (Select from list)"
    echo "5. STOP Bot (Select from list)"
    echo "6. VPS Deploy Bot (Coming Soon)"
    echo "7. Exit"
    echo "=========================================="
    read -p "Apna option chunein (1-7): " choice
}

create_bot() {
    echo "[+] Bot Setup shuru ho raha hai..."
    
    if ! command -v node &> /dev/null; then
        echo "[+] Node.js install kiya ja raha hai..."
        curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
        sudo apt-get install -y nodejs
    fi

    read -p "Apna Discord Bot Token daalein: " BOT_TOKEN
    read -p "Apni Discord Client ID (Application ID) daalein: " CLIENT_ID
    read -p "Apni Discord Admin User ID daalein: " ADMIN_ID
    read -p "Bot ka naam (folder name, jaise my-sec-bot): " BOT_NAME
    
    if [ -z "$BOT_NAME" ]; then
        BOT_NAME="discord-sec-bot-$(date +%s)"
    fi

    mkdir -p $BOT_NAME
    cd $BOT_NAME

    cat << 'EOF' > package.json
{
  "name": "discord-security-bot",
  "version": "9.0.0",
  "description": "Fixed Discord Security & Moderation Bot",
  "main": "bot.js",
  "scripts": {
    "start": "node bot.js"
  },
  "dependencies": {
    "discord.js": "^14.14.1",
    "@discordjs/voice": "^0.16.1"
  }
}
EOF

    cat << EOF > config.json
{
  "prefix": "!",
  "timeoutDuration": 600000,
  "badWords": ["gaali1", "gaali2", "bsdk", "mc", "bc", "madarchod", "behanchod", "gali"]
}
EOF

    cat << EOF > bot.js
const { Client, GatewayIntentBits, EmbedBuilder, PermissionsBitField, REST, Routes, SlashCommandBuilder, ActivityType } = require('discord.js');
const fs = require('fs');

const client = new Client({
    intents: [
        GatewayIntentBits.Guilds,
        GatewayIntentBits.GuildMessages,
        GatewayIntentBits.MessageContent,
        GatewayIntentBits.GuildMembers,
        GatewayIntentBits.GuildVoiceStates,
    ]
});

let config = { prefix: "!", timeoutDuration: 600000, badWords: ["gaali1", "gaali2", "bsdk", "mc", "bc", "madarchod", "behanchod", "gali"] };
if (fs.existsSync('./config.json')) {
    try {
        config = JSON.parse(fs.readFileSync('./config.json', 'utf8'));
    } catch (e) {
        console.log("Config load karne mein error aayi.");
    }
}

const TOKEN = "$BOT_TOKEN";
const CLIENT_ID = "$CLIENT_ID";
const ADMIN_ID = "$ADMIN_ID";

const commands = [
    new SlashCommandBuilder().setName('ping').setDescription('Bot ki latency check karein'),
    new SlashCommandBuilder().setName('security').setDescription('Server security status dekhein'),
    new SlashCommandBuilder().setName('joinvc').setDescription('Bot ko aapke voice channel mein bulayein')
].map(command => command.toJSON());

const rest = new REST({ version: '10' }).setToken(TOKEN);

(async () => {
    try {
        console.log('[+] Slash commands register ki ja rahi hain...');
        await rest.put(Routes.applicationCommands(CLIENT_ID), { body: commands });
        console.log('[+] Slash commands successfully register ho gayi hain!');
    } catch (error) {
        console.error("Slash commands register karne mein error:", error);
    }
})();

client.once('ready', () => {
    console.log(\`[ONLINE] CJH Bot \${client.user.tag} successfully online ho chuka hai!\`);
    client.user.setActivity('CJH Bot | /security', { type: ActivityType.Watching });
});

client.on('messageCreate', async message => {
    if (message.author.bot || !message.guild) return;

    const contentLower = message.content.toLowerCase();
    const hasBadWord = config.badWords.some(word => contentLower.includes(word));

    if (hasBadWord) {
        try {
            await message.delete().catch(() => {});

            const member = message.guild.members.cache.get(message.author.id);
            if (member && member.moderatable) {
                await member.timeout(config.timeoutDuration, 'Using prohibited abusive language (Auto-Security)');
                
                const warnMsg = await message.channel.send(\`⚠️ <@\${message.author.id}>, galat bhasha ka prayog karne ke liye aapko **10 minutes** ka timeout de diya gaya hai!\`);
                setTimeout(() => warnMsg.delete().catch(() => {}), 5000);
            }
        } catch (e) {
            console.error("Timeout dene mein error aayi:", e);
        }
        return;
    }

    if (!message.content.startsWith(config.prefix)) return;
    const args = message.content.slice(config.prefix.length).trim().split(/ +/);
    const cmd = args.shift().toLowerCase();

    if (cmd === 'ping') {
        message.reply(\`Pong! Latency: \${client.ws.ping}ms\`);
    }
});

client.on('interactionCreate', async interaction => {
    if (!interaction.isChatInputCommand()) return;

    try {
        if (interaction.commandName === 'ping') {
            await interaction.reply({ content: \`🏓 Pong! \${client.ws.ping}ms\`, ephemeral: true });
        } else if (interaction.commandName === 'security') {
            const embed = new EmbedBuilder()
                .setColor(0x00FF00)
                .setTitle('🛡️ CJH Bot Server Security Status')
                .setDescription('Anti-Abuse & Auto-Timeout system fully active hai.')
                .setTimestamp();
            await interaction.reply({ embeds: [embed], ephemeral: true });
        } else if (interaction.commandName === 'joinvc') {
            const memberChannel = interaction.member.voice.channel;
            if (!memberChannel) {
                return interaction.reply({ content: '❌ Pehle aapko kisi Voice Channel mein judna hoga!', ephemeral: true });
            }
            const { joinVoiceChannel } = require('@discordjs/voice');
            joinVoiceChannel({
                channelId: memberChannel.id,
                guildId: interaction.guild.id,
                adapterCreator: interaction.guild.voiceAdapterCreator,
            });
            await interaction.reply({ content: \`🔊 Successfully voice channel mein join ho gaya hoon!\`, ephemeral: true });
        }
    } catch (err) {
        console.error("Interaction error:", err);
    }
});

client.login(TOKEN).catch(err => {
    console.error("❌ Bot login fail ho gaya! Token check karein:", err);
});
EOF

    echo "[+] Dependencies install ki ja rahi hain..."
    npm install
    
    if ! command -v pm2 &> /dev/null; then
        sudo npm install -g pm2
    fi

    pm2 delete "$BOT_NAME" 2>/dev/null
    pm2 start bot.js --name "$BOT_NAME"
    pm2 save
    cd ..
    echo "=========================================="
    echo " ✅ CJH BOT SUCCESSFUL CREATE & START!"
    echo "=========================================="
    read -p "Menu par wapas jaane ke liye Enter dabayein..."
}

uninstall_bot() {
    echo "--- Active Bots List ---"
    pm2 list
    read -p "Jis bot ko delete/uninstall karna hai uska Name daalein: " TARGET_BOT
    if [ ! -z "$TARGET_BOT" ]; then
        pm2 delete "$TARGET_BOT" 2>/dev/null
        rm -rf "$TARGET_BOT"
        echo "✅ Bot successfully uninstall kar diya gaya hai."
    fi
    read -p "Menu par wapas jaane ke liye Enter dabayein..."
}

update_bot() {
    echo "[+] Bot update kiya ja raha hai..."
    if [ -d ".git" ]; then
        git pull origin main 2>/dev/null || echo "Local repo updated."
        echo "✅ Update process poori ho gayi!"
    else
        echo "⚠️ Git repository nahi mili."
    fi
    read -p "Menu par wapas jaane ke liye Enter dabayein..."
}

start_bot() {
    echo "=========================================="
    echo "      CHALANE KE LIYE BOTS LIST           "
    echo "=========================================="
    pm2 list
    echo ""
    read -p "Jiss bot ko start karna hai uska naam daalein: " START_NAME
    if [ ! -z "$START_NAME" ]; then
        pm2 start "$START_NAME" 2>/dev/null || pm2 resurrect
        echo "✅ Bot '$START_NAME' start kar diya gaya hai!"
    fi
    read -p "Menu par wapas jaane ke liye Enter dabayein..."
}

stop_bot() {
    echo "=========================================="
    echo "        ROKNE KE LIYE BOTS LIST           "
    echo "=========================================="
    pm2 list
    echo ""
    read -p "Jiss bot ko stop karna hai uska naam daalein: " STOP_NAME
    if [ ! -z "$STOP_NAME" ]; then
        pm2 stop "$STOP_NAME" 2>/dev/null
        echo "✅ Bot '$STOP_NAME' ko stop kar diya gaya hai!"
    fi
    read -p "Menu par wapas jaane ke liye Enter dabayein..."
}

vps_deploy_bot() {
    clear
    echo "=========================================="
    echo "         CJH VPS DEPLOY BOT               "
    echo "=========================================="
    echo ""
    echo "       🚀 COMING SOON! 🚀                "
    echo "  Yeh feature jald hi update kiya jayega. "
    echo ""
    echo "=========================================="
    read -p "Menu par wapas jaane ke liye Enter dabayein..."
}

while true; do
    show_menu
    case $choice in
        1) create_bot ;;
        2) uninstall_bot ;;
        3) update_bot ;;
        4) start_bot ;;
        5) stop_bot ;;
        6) vps_deploy_bot ;;
        7) exit 0 ;;
        *) echo "Galat option! Dobara koshish karein." ; sleep 2 ;;
    esac
done
EOF
