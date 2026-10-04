#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="${CJH_HOME:-$HOME/cjh-bots}"
if [ "$(id -u)" -eq 0 ]; then SUDO=""; else SUDO="sudo"; fi
RESET=$'\033[0m'; CYAN=$'\033[38;5;51m'; PURPLE=$'\033[38;5;141m'; PINK=$'\033[38;5;205m'; GREEN=$'\033[38;5;82m'; YELLOW=$'\033[38;5;220m'; WHITE=$'\033[1;97m'; DIM=$'\033[38;5;245m'

pause_menu(){ printf '\n%bPress ENTER to continue%b ' "$DIM" "$RESET"; read -r _; }
header(){ printf '\033[2J\033[H'; printf '%b╭──────────────────────────────────────────────────────────────────────────────╮%b\n' "$PURPLE" "$RESET"; printf '%b│%b  %bCJH BOT HOSTING%b  %bAurora Control Center • v5.1.0%b\n' "$PURPLE" "$RESET" "$WHITE" "$RESET" "$DIM" "$RESET"; printf '%b╰──────────────────────────────────────────────────────────────────────────────╯%b\n\n' "$PURPLE" "$RESET"; }
need(){ command -v "$1" >/dev/null 2>&1 && return 0; $SUDO apt-get update -y >/dev/null; $SUDO apt-get install -y "$2" >/dev/null; }
setup_runtime(){ need curl curl; need ca-certificates ca-certificates; if ! command -v node >/dev/null 2>&1; then curl -fsSL https://deb.nodesource.com/setup_20.x | $SUDO -E bash - >/dev/null; $SUDO apt-get install -y nodejs >/dev/null; fi; command -v pm2 >/dev/null 2>&1 || $SUDO npm install -g pm2 >/dev/null; mkdir -p "$ROOT"; chmod 700 "$ROOT"; }
slug(){ printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9_-]+/-/g;s/^-+//;s/-+$//'; }

write_bot(){
  local dir="$1" token="$2" client_id="$3"
  mkdir -p "$dir"; chmod 700 "$dir"; umask 077
  printf 'BOT_TOKEN=%s\nCLIENT_ID=%s\n' "$token" "$client_id" > "$dir/.env"; chmod 600 "$dir/.env"
  cat > "$dir/package.json" <<'JSON'
{"name":"cjh-discord-bot","version":"5.1.0","private":true,"main":"bot.js","scripts":{"start":"node bot.js"},"dependencies":{"discord.js":"^14.27.0"}}
JSON
  cat > "$dir/bot.js" <<'NODE'
const fs=require('fs');
const {Client,GatewayIntentBits,PermissionsBitField,SlashCommandBuilder,EmbedBuilder,REST,Routes}=require('discord.js');
const env={};
for(const line of fs.readFileSync('.env','utf8').split(/\r?\n/)){const i=line.indexOf('=');if(i>0)env[line.slice(0,i)]=line.slice(i+1);}
if(!env.BOT_TOKEN||!env.CLIENT_ID){console.error('[CJH] Missing BOT_TOKEN or CLIENT_ID');process.exit(1);}
const DATA='./data.json';let db={guilds:{}};try{db=JSON.parse(fs.readFileSync(DATA,'utf8'));}catch{}
const save=()=>fs.writeFileSync(DATA,JSON.stringify(db,null,2),{mode:0o600});
const cfg=id=>db.guilds[id]??={};
const P=PermissionsBitField.Flags;
const client=new Client({intents:[GatewayIntentBits.Guilds,GatewayIntentBits.GuildMembers,GatewayIntentBits.GuildMessages,GatewayIntentBits.MessageContent]});
const cmd=(n,d)=>new SlashCommandBuilder().setName(n).setDescription(d);
const commands=[cmd('help','Show CJH commands'),cmd('ping','Show bot latency'),cmd('security','Show server security status'),cmd('server','Show server information'),cmd('clear','Delete recent messages'),cmd('kick','Kick a member'),cmd('ban','Ban a member'),cmd('timeout','Timeout a member'),cmd('warn','Warn a member'),cmd('warnings','View warnings'),cmd('lock','Lock current channel'),cmd('unlock','Unlock current channel'),cmd('slowmode','Set channel slowmode'),cmd('announce','Send an announcement'),cmd('poll','Create a yes/no poll'),cmd('setlogs','Configure moderation logs'),cmd('setwelcome','Configure welcome messages')];
commands.find(x=>x.name==='clear').addIntegerOption(o=>o.setName('amount').setDescription('1-100').setMinValue(1).setMaxValue(100).setRequired(true));
for(const n of ['kick','ban'])commands.find(x=>x.name===n).addUserOption(o=>o.setName('user').setDescription('Member').setRequired(true)).addStringOption(o=>o.setName('reason').setDescription('Reason'));
commands.find(x=>x.name==='timeout').addUserOption(o=>o.setName('user').setDescription('Member').setRequired(true)).addIntegerOption(o=>o.setName('minutes').setDescription('1-40320').setMinValue(1).setMaxValue(40320).setRequired(true));
commands.find(x=>x.name==='warn').addUserOption(o=>o.setName('user').setDescription('Member').setRequired(true)).addStringOption(o=>o.setName('reason').setDescription('Reason').setRequired(true));
commands.find(x=>x.name==='warnings').addUserOption(o=>o.setName('user').setDescription('Member').setRequired(true));
commands.find(x=>x.name==='slowmode').addIntegerOption(o=>o.setName('seconds').setDescription('0-21600').setMinValue(0).setMaxValue(21600).setRequired(true));
commands.find(x=>x.name==='announce').addStringOption(o=>o.setName('message').setDescription('Message').setRequired(true));
commands.find(x=>x.name==='poll').addStringOption(o=>o.setName('question').setDescription('Question').setRequired(true));
for(const n of ['setlogs','setwelcome'])commands.find(x=>x.name===n).addChannelOption(o=>o.setName('channel').setDescription('Channel').setRequired(true));
const embed=(t,d,c=0x8b5cf6)=>new EmbedBuilder().setTitle(t).setDescription(d).setColor(c).setTimestamp();
const allowed=(i,p)=>i.member.permissions.has(p);
async function log(g,text){const id=cfg(g.id).logs;if(!id)return;const ch=g.channels.cache.get(id);if(ch)await ch.send({embeds:[embed('CJH Moderation Log',text,0xf59e0b)]}).catch(()=>{});}
client.once('ready',()=>console.log(`[CJH] ${client.user.tag} online | ${client.guilds.cache.size} server(s)`));
client.on('guildMemberAdd',async m=>{const id=cfg(m.guild.id).welcome;if(!id)return;const ch=m.guild.channels.cache.get(id);if(ch)await ch.send({embeds:[embed('Welcome ✨',`Welcome ${m} to **${m.guild.name}**!\nMember #${m.guild.memberCount}`,0x22d3ee)]}).catch(()=>{});});
client.on('interactionCreate',async i=>{if(!i.isChatInputCommand()||!i.guild)return;try{const user=i.options.getUser('user')||i.user;const member=i.options.getMember('user');
if(i.commandName==='help')return i.reply({ephemeral:true,embeds:[embed('CJH Server Suite','**Utility** `/ping` `/security` `/server`\n**Moderation** `/clear` `/kick` `/ban` `/timeout` `/warn` `/warnings`\n**Channel** `/lock` `/unlock` `/slowmode`\n**Community** `/announce` `/poll`\n**Setup** `/setlogs` `/setwelcome`')]});
if(i.commandName==='ping')return i.reply(`🏓 ${client.ws.ping}ms`);
if(i.commandName==='security'){const g=i.guild,c=cfg(g.id);return i.reply({ephemeral:true,embeds:[embed('Security Status',`**Verification:** ${g.verificationLevel}\n**2FA moderation:** ${g.mfaLevel}\n**Members:** ${g.memberCount}\n**Logs:** ${c.logs?`<#${c.logs}>`:'not configured'}\n**Welcome:** ${c.welcome?`<#${c.welcome}>`:'not configured'}`,0x22d3ee)]});}
if(i.commandName==='server')return i.reply({embeds:[embed('Server Overview',`**${i.guild.name}**\nOwner: <@${i.guild.ownerId}>\nMembers: ${i.guild.memberCount}\nChannels: ${i.guild.channels.cache.size}\nRoles: ${i.guild.roles.cache.size}`)]});
if(i.commandName==='clear'){if(!allowed(i,P.ManageMessages))return i.reply({content:'Manage Messages permission required.',ephemeral:true});const n=i.options.getInteger('amount',true);const d=await i.channel.bulkDelete(n,true);return i.reply({content:`🧹 Deleted ${d.size} message(s).`,ephemeral:true});}
if(i.commandName==='kick'||i.commandName==='ban'){const p=i.commandName==='kick'?P.KickMembers:P.BanMembers;if(!allowed(i,p))return i.reply({content:'Required moderation permission is missing.',ephemeral:true});if(!member)return i.reply({content:'Member is not in this server.',ephemeral:true});const reason=i.options.getString('reason')||'No reason provided';if(i.commandName==='kick'){if(!member.kickable)return i.reply({content:'I cannot kick that member because of role hierarchy.',ephemeral:true});await member.kick(reason);}else{if(!member.bannable)return i.reply({content:'I cannot ban that member because of role hierarchy.',ephemeral:true});await member.ban({reason});}await log(i.guild,`${i.commandName==='kick'?'Kicked':'Banned'} **${user.tag}** — ${reason}`);return i.reply(`${i.commandName==='kick'?'👢 Kicked':'🔨 Banned'} **${user.tag}**.`);}
if(i.commandName==='timeout'){if(!allowed(i,P.ModerateMembers))return i.reply({content:'Moderate Members permission required.',ephemeral:true});if(!member||!member.moderatable)return i.reply({content:'I cannot timeout that member because of role hierarchy.',ephemeral:true});const min=i.options.getInteger('minutes',true);await member.timeout(min*60000,'CJH moderation');await log(i.guild,`Timed out **${user.tag}** for ${min} minute(s)`);return i.reply(`⏳ Timed out **${user.tag}** for ${min} minute(s).`);}
if(i.commandName==='warn'){if(!allowed(i,P.ModerateMembers))return i.reply({content:'Moderate Members permission required.',ephemeral:true});if(!member)return i.reply({content:'Member is not in this server.',ephemeral:true});const c=cfg(i.guild.id);c.warns??={};c.warns[user.id]??=[];c.warns[user.id].push({reason:i.options.getString('reason',true),by:i.user.id,at:Date.now()});save();await log(i.guild,`Warned **${user.tag}**`);return i.reply(`⚠️ Warned **${user.tag}**.`);}
if(i.commandName==='warnings'){if(!allowed(i,P.ModerateMembers))return i.reply({content:'Moderate Members permission required.',ephemeral:true});const a=cfg(i.guild.id).warns?.[user.id]||[];return i.reply({ephemeral:true,embeds:[embed(`Warnings: ${user.tag}`,a.length?a.map((x,n)=>`**${n+1}.** ${x.reason} — <@${x.by}> <t:${Math.floor(x.at/1000)}:R>`).join('\n'):'No warnings.')]});}
if(i.commandName==='lock'||i.commandName==='unlock'){if(!allowed(i,P.ManageChannels))return i.reply({content:'Manage Channels permission required.',ephemeral:true});const lock=i.commandName==='lock';await i.channel.permissionOverwrites.edit(i.guild.roles.everyone,{SendMessages:lock?false:null});await log(i.guild,`${lock?'Locked':'Unlocked'} ${i.channel}`);return i.reply(`${lock?'🔒 Locked':'🔓 Unlocked'} ${i.channel}.`);}
if(i.commandName==='slowmode'){if(!allowed(i,P.ManageChannels))return i.reply({content:'Manage Channels permission required.',ephemeral:true});const s=i.options.getInteger('seconds',true);await i.channel.setRateLimitPerUser(s);return i.reply(`🐢 Slowmode set to **${s}s**.`);}
if(i.commandName==='announce'){if(!allowed(i,P.ManageGuild))return i.reply({content:'Manage Server permission required.',ephemeral:true});await i.channel.send({embeds:[embed('📢 Announcement',i.options.getString('message',true),0xec4899)]});return i.reply({content:'Announcement sent.',ephemeral:true});}
if(i.commandName==='poll'){const m=await i.reply({content:`📊 **Poll**\n${i.options.getString('question',true)}\n\n👍 Yes\n👎 No`,fetchReply:true});await m.react('👍');await m.react('👎');return;}
if(i.commandName==='setlogs'){if(!allowed(i,P.ManageGuild))return i.reply({content:'Manage Server permission required.',ephemeral:true});cfg(i.guild.id).logs=i.options.getChannel('channel',true).id;save();return i.reply('✅ Moderation logs configured.');}
if(i.commandName==='setwelcome'){if(!allowed(i,P.ManageGuild))return i.reply({content:'Manage Server permission required.',ephemeral:true});cfg(i.guild.id).welcome=i.options.getChannel('channel',true).id;save();return i.reply('✅ Welcome channel configured.');}
}catch(e){console.error('[CJH]',e);if(!i.replied&&!i.deferred)await i.reply({content:'Command failed. Check bot permissions and role hierarchy.',ephemeral:true}).catch(()=>{});}});
(async()=>{try{await new REST({version:'10'}).setToken(env.BOT_TOKEN).put(Routes.applicationCommands(env.CLIENT_ID),{body:commands.map(x=>x.toJSON())});await client.login(env.BOT_TOKEN);}catch(e){console.error('[CJH] Startup failed:',e.message);process.exit(1);}})();
NODE
}

create_bot(){
 header "Deploy real Discord bot"; setup_runtime
 printf '%bBot name%b: ' "$DIM" "$RESET"; read -r input; bot_name="$(slug "${input:-cjh-bot}")"; [ -n "$bot_name" ] || bot_name="cjh-bot"; dir="$ROOT/$bot_name"
 if [ -e "$dir" ]; then printf '%bBot already exists.%b\n' "$YELLOW" "$RESET"; pause_menu; return; fi
 printf '%bDiscord bot token%b: ' "$DIM" "$RESET"; read -r -s token; printf '\n%bDiscord application Client ID%b: ' "$DIM" "$RESET"; read -r client_id; printf '\n'
 if [ -z "$token" ] || [ -z "$client_id" ]; then printf '%bToken and Client ID are required.%b\n' "$YELLOW" "$RESET"; pause_menu; return; fi
 write_bot "$dir" "$token" "$client_id"
 printf '%bInstalling Discord.js...%b\n' "$DIM" "$RESET"
 if ! (cd "$dir" && npm install --omit=dev --no-audit --no-fund); then rm -rf "$dir"; printf '%bDependency installation failed; incomplete bot removed.%b\n' "$YELLOW" "$RESET"; pause_menu; return; fi
 if pm2 start "$dir/bot.js" --name "$bot_name" --cwd "$dir" --time; then pm2 save >/dev/null 2>&1 || true; printf '%b✓ Real bot started: %s%b\n' "$GREEN" "$bot_name" "$RESET"; else printf '%bBot failed to start. Use Logs.%b\n' "$YELLOW" "$RESET"; fi
 pause_menu
}
choose_bot(){
 mapfile -t bots < <(find "$ROOT" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort)
 [ "${#bots[@]}" -gt 0 ] || { printf '%bNo bots installed.%b\n' "$YELLOW" "$RESET"; return 1; }
 local i=1; for bot in "${bots[@]}"; do if pm2 describe "$bot" >/dev/null 2>&1; then status="managed"; else status="offline"; fi; printf '  %b[%02d]%b %-28s %b%s%b\n' "$CYAN" "$i" "$RESET" "$bot" "$GREEN" "$status" "$RESET"; i=$((i+1)); done
 printf '\n%bSelect bot:%b ' "$WHITE" "$RESET"; read -r n; [[ "$n" =~ ^[0-9]+$ ]] || return 1; [ "$n" -ge 1 ] && [ "$n" -le "${#bots[@]}" ] || return 1; SELECTED="${bots[$((n-1))]}"
}
manage(){ local action="$1"; header "$action bot"; if ! choose_bot; then pause_menu; return; fi; case "$action" in START) pm2 start "$SELECTED";;STOP) pm2 stop "$SELECTED";;RESTART) pm2 restart "$SELECTED";;LOGS) pm2 logs "$SELECTED" --lines 100 --nostream;;esac; pm2 save >/dev/null 2>&1 || true; pause_menu; }
status(){ header "System status"; printf '%bNode%b %s\n%bPM2%b %s\n\n' "$CYAN" "$RESET" "$(node -v)" "$CYAN" "$RESET" "$(pm2 -v)"; pm2 list; pause_menu; }
menu(){ header "Premium Discord bot control plane"; printf '%b  01%b  Deploy Discord bot\n%b  02%b  Start bot\n%b  03%b  Stop bot\n%b  04%b  Restart bot\n%b  05%b  Live logs\n%b  06%b  System / PM2 status\n%b  Q %b Quit\n\n%bSelect › %b' "$CYAN" "$RESET" "$GREEN" "$RESET" "$YELLOW" "$RESET" "$PURPLE" "$RESET" "$PINK" "$RESET" "$CYAN" "$RESET" "$DIM" "$RESET" "$WHITE" "$CYAN"; read -r choice; case "$choice" in 1|01)create_bot;;2|02)manage START;;3|03)manage STOP;;4|04)manage RESTART;;5|05)manage LOGS;;6|06)status;;q|Q)exit 0;;*)printf '%bInvalid option.%b\n' "$YELLOW" "$RESET";sleep 1;;esac; }

setup_runtime
while true; do menu; done
