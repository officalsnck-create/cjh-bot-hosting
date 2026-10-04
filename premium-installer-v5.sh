#!/usr/bin/env bash
set -Eeuo pipefail
APP='CJH BOT HOSTING'; VERSION='5.0.0'; ROOT="${CJH_HOME:-$HOME/cjh-bots}"
SUDO=''; [[ $EUID -eq 0 ]] || SUDO='sudo'
C=$'\033[38;5;51m'; V=$'\033[38;5;141m'; P=$'\033[38;5;205m'; G=$'\033[38;5;82m'; Y=$'\033[38;5;220m'; R=$'\033[0m'; W=$'\033[1;97m'; D=$'\033[38;5;245m'
trap 'printf "%b" "$R"' EXIT INT TERM
clear_screen(){ printf '\033[2J\033[H'; }
box(){ printf '%b╭──────────────────────────────────────────────────────────────────────────────╮%b\n' "$V" "$R"; printf '%b│%b  %b%s%b  %b%s%b\n' "$V" "$R" "$W" "$1" "$R" "$D" "$2" "$R"; printf '%b╰──────────────────────────────────────────────────────────────────────────────╯%b\n' "$V" "$R"; }
need(){ command -v "$1" >/dev/null 2>&1 || { $SUDO apt-get update -y >/dev/null; $SUDO apt-get install -y "$2" >/dev/null; }; }
runtime(){ need curl curl; need ca-certificates ca-certificates; if ! command -v node >/dev/null 2>&1; then curl -fsSL https://deb.nodesource.com/setup_20.x | $SUDO -E bash - >/dev/null; $SUDO apt-get install -y nodejs >/dev/null; fi; command -v pm2 >/dev/null 2>&1 || $SUDO npm install -g pm2 >/dev/null; mkdir -p "$ROOT"; chmod 700 "$ROOT"; }
slug(){ printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9_-]+/-/g;s/^-+//;s/-+$//'; }
write_bot(){
 local d="$1" token="$2" client="$3"; mkdir -p "$d"; chmod 700 "$d"; umask 077
 printf 'BOT_TOKEN=%s\nCLIENT_ID=%s\n' "$token" "$client" > "$d/.env"; chmod 600 "$d/.env"
 cat > "$d/package.json" <<'JSON'
{"name":"cjh-server-bot","private":true,"version":"5.0.0","main":"bot.js","scripts":{"start":"node bot.js"},"dependencies":{"discord.js":"^14.27.0"}}
JSON
 cat > "$d/bot.js" <<'NODE'
const fs=require('fs');
const {Client,GatewayIntentBits,PermissionsBitField,SlashCommandBuilder,EmbedBuilder,REST,Routes}=require('discord.js');
const env={};for(const line of fs.readFileSync('.env','utf8').split(/\r?\n/)){const i=line.indexOf('=');if(i>0)env[line.slice(0,i)]=line.slice(i+1)}
if(!env.BOT_TOKEN||!env.CLIENT_ID){console.error('Missing BOT_TOKEN or CLIENT_ID');process.exit(1)}
const DATA='./data.json';let db={guilds:{}};try{db=JSON.parse(fs.readFileSync(DATA,'utf8'))}catch{};const save=()=>fs.writeFileSync(DATA,JSON.stringify(db,null,2),{mode:0o600});const cfg=id=>db.guilds[id]??={};
const client=new Client({intents:[GatewayIntentBits.Guilds,GatewayIntentBits.GuildMembers,GatewayIntentBits.GuildMessages,GatewayIntentBits.MessageContent]});
const P=PermissionsBitField.Flags;
const commands=[
 new SlashCommandBuilder().setName('help').setDescription('Show CJH commands'),
 new SlashCommandBuilder().setName('ping').setDescription('Show latency'),
 new SlashCommandBuilder().setName('security').setDescription('Show server security status'),
 new SlashCommandBuilder().setName('server').setDescription('Show server information'),
 new SlashCommandBuilder().setName('userinfo').setDescription('Show member information').addUserOption(o=>o.setName('user').setDescription('Member').setRequired(false)),
 new SlashCommandBuilder().setName('avatar').setDescription('Show a member avatar').addUserOption(o=>o.setName('user').setDescription('Member').setRequired(false)),
 new SlashCommandBuilder().setName('clear').setDescription('Delete recent messages').addIntegerOption(o=>o.setName('amount').setDescription('1-100').setMinValue(1).setMaxValue(100).setRequired(true)),
 new SlashCommandBuilder().setName('kick').setDescription('Kick a member').addUserOption(o=>o.setName('user').setDescription('Member').setRequired(true)).addStringOption(o=>o.setName('reason').setDescription('Reason')),
 new SlashCommandBuilder().setName('ban').setDescription('Ban a member').addUserOption(o=>o.setName('user').setDescription('Member').setRequired(true)).addStringOption(o=>o.setName('reason').setDescription('Reason')),
 new SlashCommandBuilder().setName('timeout').setDescription('Timeout a member').addUserOption(o=>o.setName('user').setDescription('Member').setRequired(true)).addIntegerOption(o=>o.setName('minutes').setDescription('1-40320').setMinValue(1).setMaxValue(40320).setRequired(true)),
 new SlashCommandBuilder().setName('warn').setDescription('Warn a member').addUserOption(o=>o.setName('user').setDescription('Member').setRequired(true)).addStringOption(o=>o.setName('reason').setDescription('Reason').setRequired(true)),
 new SlashCommandBuilder().setName('warnings').setDescription('View warnings').addUserOption(o=>o.setName('user').setDescription('Member').setRequired(true)),
 new SlashCommandBuilder().setName('lock').setDescription('Lock current channel'),
 new SlashCommandBuilder().setName('unlock').setDescription('Unlock current channel'),
 new SlashCommandBuilder().setName('slowmode').setDescription('Set channel slowmode').addIntegerOption(o=>o.setName('seconds').setDescription('0-21600').setMinValue(0).setMaxValue(21600).setRequired(true)),
 new SlashCommandBuilder().setName('announce').setDescription('Send a styled announcement').addStringOption(o=>o.setName('message').setDescription('Message').setRequired(true)),
 new SlashCommandBuilder().setName('poll').setDescription('Create a yes/no poll').addStringOption(o=>o.setName('question').setDescription('Question').setRequired(true)),
 new SlashCommandBuilder().setName('setlogs').setDescription('Set moderation log channel').addChannelOption(o=>o.setName('channel').setDescription('Text channel').setRequired(true)),
 new SlashCommandBuilder().setName('setwelcome').setDescription('Set welcome channel').addChannelOption(o=>o.setName('channel').setDescription('Text channel').setRequired(true))
].map(x=>x.toJSON());
(async()=>{try{await new REST({version:'10'}).setToken(env.BOT_TOKEN).put(Routes.applicationCommands(env.CLIENT_ID),{body:commands});console.log('[CJH] slash commands synced')}catch(e){console.error('[CJH] command sync:',e.message)}})();
const embed=(title,text,color=0x8b5cf6)=>new EmbedBuilder().setTitle(title).setDescription(text).setColor(color).setTimestamp();
const has=(i,p)=>i.member.permissions.has(p);
async function log(g,text){const id=cfg(g.id).logs;if(!id)return;const ch=g.channels.cache.get(id);if(ch)await ch.send({embeds:[embed('CJH Moderation Log',text,0xf59e0b)]}).catch(()=>{})}
client.once('ready',()=>console.log(`[CJH] ${client.user.tag} online | ${client.guilds.cache.size} server(s)`));
client.on('guildMemberAdd',async m=>{const id=cfg(m.guild.id).welcome;if(!id)return;const ch=m.guild.channels.cache.get(id);if(ch)await ch.send({embeds:[embed('Welcome ✨',`Welcome ${m} to **${m.guild.name}**!\nMember #${m.guild.memberCount}`,0x22d3ee)]}).catch(()=>{})});
client.on('interactionCreate',async i=>{if(!i.isChatInputCommand()||!i.guild)return;try{
 const u=i.options.getUser('user')||i.user; const member=i.options.getMember('user');
 if(i.commandName==='help')return i.reply({embeds:[embed('CJH Server Suite','**Utility** `/ping` `/security` `/server` `/userinfo` `/avatar`\n**Moderation** `/clear` `/kick` `/ban` `/timeout` `/warn` `/warnings`\n**Channel** `/lock` `/unlock` `/slowmode`\n**Community** `/announce` `/poll`\n**Setup** `/setlogs` `/setwelcome`')],ephemeral:true});
 if(i.commandName==='ping')return i.reply(`🏓 ${client.ws.ping}ms`);
 if(i.commandName==='security'){const g=i.guild;return i.reply({embeds:[embed('Security Status',`**Verification:** ${g.verificationLevel}\n**2FA moderation:** ${g.mfaLevel}\n**Members:** ${g.memberCount}\n**Bot permissions:** enforced per command\n**Logs:** ${cfg(g.id).logs?`<#${cfg(g.id).logs}>`:'not configured'}`,0x22d3ee)],ephemeral:true})}
 if(i.commandName==='server')return i.reply({embeds:[embed('Server Overview',`**${i.guild.name}**\nOwner: <@${i.guild.ownerId}>\nMembers: ${i.guild.memberCount}\nChannels: ${i.guild.channels.cache.size}\nRoles: ${i.guild.roles.cache.size}`)]});
 if(i.commandName==='userinfo')return i.reply({embeds:[embed('User Information',`User: ${u}\nID: ${u.id}\nCreated: <t:${Math.floor(u.createdTimestamp/1000)}:R>`)]});
 if(i.commandName==='avatar')return i.reply({embeds:[embed(`${u.username}'s Avatar`,`[Open full size](${u.displayAvatarURL({size:1024})})`).setImage(u.displayAvatarURL({size:1024}))]});
 if(i.commandName==='clear'){if(!has(i,P.ManageMessages))return i.reply({content:'Manage Messages permission required.',ephemeral:true});const n=i.options.getInteger('amount',true);const messages=await i.channel.bulkDelete(n,true);return i.reply({content:`🧹 Deleted ${messages.size} message(s).`,ephemeral:true})}
 if(i.commandName==='kick'){if(!has(i,P.KickMembers))return i.reply({content:'Kick Members permission required.',ephemeral:true});if(!member)return i.reply({content:'Member is not in this server.',ephemeral:true});const reason=i.options.getString('reason')||'No reason provided';if(!member.kickable)return i.reply({content:'I cannot kick this member. Check role hierarchy.',ephemeral:true});await member.kick(reason);await log(i.guild,`Kicked **${u.tag}** — ${reason}`);return i.reply(`👢 Kicked **${u.tag}**.`)}
 if(i.commandName==='ban'){if(!has(i,P.BanMembers))return i.reply({content:'Ban Members permission required.',ephemeral:true});if(!member)return i.reply({content:'Member is not in this server.',ephemeral:true});const reason=i.options.getString('reason')||'No reason provided';if(!member.bannable)return i.reply({content:'I cannot ban this member. Check role hierarchy.',ephemeral:true});await member.ban({reason});await log(i.guild,`Banned **${u.tag}** — ${reason}`);return i.reply(`🔨 Banned **${u.tag}**.`)}
 if(i.commandName==='timeout'){if(!has(i,P.ModerateMembers))return i.reply({content:'Moderate Members permission required.',ephemeral:true});if(!member)return i.reply({content:'Member is not in this server.',ephemeral:true});const minutes=i.options.getInteger('minutes',true);if(!member.moderatable)return i.reply({content:'I cannot timeout this member. Check role hierarchy.',ephemeral:true});await member.timeout(minutes*60000,'CJH moderation');await log(i.guild,`Timed out **${u.tag}** for ${minutes} minute(s)`);return i.reply(`⏳ Timed out **${u.tag}** for ${minutes} minute(s).`)}
 if(i.commandName==='warn'){if(!has(i,P.ModerateMembers))return i.reply({content:'Moderate Members permission required.',ephemeral:true});if(!member)return i.reply({content:'Member is not in this server.',ephemeral:true});const reason=i.options.getString('reason',true);const g=cfg(i.guild.id);g.warns??={};g.warns[u.id]??=[];g.warns[u.id].push({reason,by:i.user.id,at:Date.now()});save();await log(i.guild,`Warned **${u.tag}** — ${reason}`);return i.reply(`⚠️ Warned **${u.tag}**.`)}
 if(i.commandName==='warnings'){if(!has(i,P.ModerateMembers))return i.reply({content:'Moderate Members permission required.',ephemeral:true});const a=cfg(i.guild.id).warns?.[u.id]||[];return i.reply({embeds:[embed(`Warnings: ${u.tag}`,a.length?a.map((x,n)=>`**${n+1}.** ${x.reason} — <@${x.by}> <t:${Math.floor(x.at/1000)}:R>`).join('\n'):'No warnings.')],ephemeral:true})}
 if(i.commandName==='lock'||i.commandName==='unlock'){if(!has(i,P.ManageChannels))return i.reply({content:'Manage Channels permission required.',ephemeral:true});await i.channel.permissionOverwrites.edit(i.guild.roles.everyone,{SendMessages:i.commandName==='lock'?false:null});await log(i.guild,`${i.commandName==='lock'?'Locked':'Unlocked'} ${i.channel}`);return i.reply(`${i.commandName==='lock'?'🔒 Locked':'🔓 Unlocked'} ${i.channel}.`)}
 if(i.commandName==='slowmode'){if(!has(i,P.ManageChannels))return i.reply({content:'Manage Channels permission required.',ephemeral:true});const s=i.options.getInteger('seconds',true);await i.channel.setRateLimitPerUser(s);return i.reply(`🐢 Slowmode: **${s}s**.`)}
 if(i.commandName==='announce'){if(!has(i,P.ManageGuild))return i.reply({content:'Manage Server permission required.',ephemeral:true});await i.channel.send({embeds:[embed('📢 Announcement',i.options.getString('message',true),0xec4899)]});return i.reply({content:'Announcement sent.',ephemeral:true})}
 if(i.commandName==='poll'){const m=await i.reply({content:`📊 **Poll**\n${i.options.getString('question',true)}\n\n👍 Yes\n👎 No`,fetchReply:true});await m.react('👍');await m.react('👎');return}
 if(i.commandName==='setlogs'){if(!has(i,P.ManageGuild))return i.reply({content:'Manage Server permission required.',ephemeral:true});cfg(i.guild.id).logs=i.options.getChannel('channel',true).id;save();return i.reply('✅ Moderation logs configured.')}
 if(i.commandName==='setwelcome'){if(!has(i,P.ManageGuild))return i.reply({content:'Manage Server permission required.',ephemeral:true});cfg(i.guild.id).welcome=i.options.getChannel('channel',true).id;save();return i.reply('✅ Welcome channel configured.')}
}catch(e){console.error('[CJH]',e);if(!i.replied)await i.reply({content:'The command failed. Check bot permissions and role hierarchy.',ephemeral:true}).catch(()=>{})}});
client.login(env.BOT_TOKEN).catch(e=>{console.error('[CJH] login failed:',e.message);process.exit(1)});
NODE
}
create(){ clear_screen; box 'CJH v5  •  DEPLOY DISCORD SERVER BOT' 'REAL FEATURES • PM2 • PER-SERVER DATA'; runtime; printf '%bBot name%b: ' "$D" "$R";read -r raw; local n; n="$(slug "${raw:-cjh-bot}")";[[ -n "$n" ]]||n="cjh-bot";local d="$ROOT/$n";[[ ! -e "$d" ]]||{ printf '%bAlready exists.%b\n' "$Y" "$R";pause;return;};printf '%bBot token%b: ' "$D" "$R";read -r -s token;printf '\n%bClient ID%b: ' "$D" "$R";read -r client;[[ -n "$token"&&-n "$client" ]]||{ printf '%bToken and Client ID are required.%b\n' "$Y" "$R";pause;return;};write_bot "$d" "$token" "$client";printf '%bInstalling dependencies...%b\n' "$D" "$R";(cd "$d"&&npm install --omit=dev --no-audit --no-fund >/dev/null)||{rm -rf "$d";printf '%bInstall failed; cleaned up.%b\n' "$Y" "$R";pause;return;};pm2 start "$d/bot.js" --name "$n" --cwd "$d" --time >/dev/null;pm2 save >/dev/null 2>&1||true;printf '%b✓ Bot deployed and started.%b\n' "$G" "$R";printf '%bUse /help in Discord to see the real commands.%b\n' "$C" "$R";pause;}
manage(){ local action="$1";clear_screen;box "CJH  •  $action" 'PM2 PROCESS CONTROL';mapfile -t bots < <(find "$ROOT" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null|sort);((${#bots[@]}))||{printf '%bNo bots installed.%b\n' "$Y" "$R";pause;return;};local i=1;for b in "${bots[@]}";do printf '  %b%02d%b %-30s %s\n' "$C" "$i" "$R" "$b" "$(pm2 jlist 2>/dev/null|grep -o '"name":"'"$b"'"[^}]*"status":"[^"]*"'|sed -E 's/.*"status":"([^"]*)".*/\1/'|head -1)";((i++));done;printf '\nSelect: ';read -r q;[[ $q =~ ^[0-9]+$&&q -ge 1&&q -le ${#bots[@]} ]]||{pause;return;};local b="${bots[$((q-1))]}";case "$action" in START)pm2 start "$b";;STOP)pm2 stop "$b";;RESTART)pm2 restart "$b";;LOGS)pm2 logs "$b" --lines 100 --nostream;;esac;pm2 save >/dev/null 2>&1||true;pause;}
menu(){ clear_screen;box 'CJH BOT HOSTING' "Premium Aurora Control Center  •  v$VERSION";printf '%b  01%b  Deploy new Discord bot\n%b  02%b  Start bot\n%b  03%b  Stop bot\n%b  04%b  Restart bot\n%b  05%b  Live logs\n%b  06%b  System / PM2 status\n%b  Q %b Quit\n\n%b  Select › %b' "$C$W" "$R" "$G$W" "$R" "$Y$W" "$R" "$C$W" "$R" "$V$W" "$R" "$P$W" "$R" "$D" "$R" "$W" "$C";read -r x;case "$x" in 1|01)create;;2|02)manage START;;3|03)manage STOP;;4|04)manage RESTART;;5|05)manage LOGS;;6|06)runtime;pm2 list;pause;;q|Q)exit 0;;esac;}
runtime;while :;do menu;done
