const fs = require('fs');
const {
  Client,
  GatewayIntentBits,
  PermissionsBitField,
  SlashCommandBuilder,
  EmbedBuilder,
  REST,
  Routes,
  ChannelType
} = require('discord.js');

const loadEnv = () => {
  const out = {};
  for (const line of fs.readFileSync('.env', 'utf8').split(/\r?\n/)) {
    const i = line.indexOf('=');
    if (i > 0) out[line.slice(0, i)] = line.slice(i + 1);
  }
  return out;
};

const env = loadEnv();
if (!env.BOT_TOKEN || !env.CLIENT_ID) {
  console.error('[CJH] Missing BOT_TOKEN or CLIENT_ID');
  process.exit(1);
}

const DATA_FILE = 'data.json';
let db = { guilds: {} };
try {
  db = JSON.parse(fs.readFileSync(DATA_FILE, 'utf8'));
  if (!db.guilds || typeof db.guilds !== 'object') db.guilds = {};
} catch {
  db = { guilds: {} };
}
const save = () => fs.writeFileSync(DATA_FILE, JSON.stringify(db, null, 2), { mode: 0o600 });
const cfg = (guildId) => {
  db.guilds[guildId] ??= { warns: {} };
  db.guilds[guildId].warns ??= {};
  return db.guilds[guildId];
};
const P = PermissionsBitField.Flags;

const client = new Client({
  intents: [GatewayIntentBits.Guilds, GatewayIntentBits.GuildMembers]
});

const footer = { text: 'Made by root_dora • CJH Bot Hosting' };
const embed = (title, description, color = 0x8b5cf6) =>
  new EmbedBuilder().setTitle(title).setDescription(description).setColor(color).setFooter(footer).setTimestamp();
const ok = (title, description) => embed(`✅ ${title}`, description, 0x22c55e);
const errorEmbed = (description) => embed('❌ Action failed', description, 0xef4444);
const has = (interaction, permission) => interaction.member.permissions.has(permission);
const mention = (user) => `<@${user.id}>`;

const commands = [
  new SlashCommandBuilder().setName('help').setDescription('Show all CJH commands'),
  new SlashCommandBuilder().setName('ping').setDescription('Show bot latency'),
  new SlashCommandBuilder().setName('security').setDescription('Show server security status'),
  new SlashCommandBuilder().setName('server').setDescription('Show server information'),
  new SlashCommandBuilder().setName('userinfo').setDescription('Show member information').addUserOption(o => o.setName('user').setDescription('Member').setRequired(false)),
  new SlashCommandBuilder().setName('avatar').setDescription('Show a member avatar').addUserOption(o => o.setName('user').setDescription('Member').setRequired(false)),
  new SlashCommandBuilder().setName('membercount').setDescription('Show server member count'),
  new SlashCommandBuilder().setName('clear').setDescription('Delete recent messages').addIntegerOption(o => o.setName('amount').setDescription('1-100').setMinValue(1).setMaxValue(100).setRequired(true)),
  new SlashCommandBuilder().setName('kick').setDescription('Kick a member').addUserOption(o => o.setName('user').setDescription('Member').setRequired(true)).addStringOption(o => o.setName('reason').setDescription('Reason').setRequired(false)),
  new SlashCommandBuilder().setName('ban').setDescription('Ban a member').addUserOption(o => o.setName('user').setDescription('Member').setRequired(true)).addStringOption(o => o.setName('reason').setDescription('Reason').setRequired(false)),
  new SlashCommandBuilder().setName('unban').setDescription('Unban a user by ID').addStringOption(o => o.setName('user_id').setDescription('Discord user ID').setRequired(true)),
  new SlashCommandBuilder().setName('timeout').setDescription('Timeout a member').addUserOption(o => o.setName('user').setDescription('Member').setRequired(true)).addIntegerOption(o => o.setName('minutes').setDescription('1-40320').setMinValue(1).setMaxValue(40320).setRequired(true)).addStringOption(o => o.setName('reason').setDescription('Reason').setRequired(false)),
  new SlashCommandBuilder().setName('untimeout').setDescription('Remove a timeout').addUserOption(o => o.setName('user').setDescription('Member').setRequired(true)),
  new SlashCommandBuilder().setName('warn').setDescription('Warn a member').addUserOption(o => o.setName('user').setDescription('Member').setRequired(true)).addStringOption(o => o.setName('reason').setDescription('Reason').setRequired(true)),
  new SlashCommandBuilder().setName('warnings').setDescription('View warnings').addUserOption(o => o.setName('user').setDescription('Member').setRequired(true)),
  new SlashCommandBuilder().setName('clearwarnings').setDescription('Clear all warnings').addUserOption(o => o.setName('user').setDescription('Member').setRequired(true)),
  new SlashCommandBuilder().setName('lock').setDescription('Lock the current channel'),
  new SlashCommandBuilder().setName('unlock').setDescription('Unlock the current channel'),
  new SlashCommandBuilder().setName('slowmode').setDescription('Set channel slowmode').addIntegerOption(o => o.setName('seconds').setDescription('0-21600').setMinValue(0).setMaxValue(21600).setRequired(true)),
  new SlashCommandBuilder().setName('announce').setDescription('Send an embed announcement').addStringOption(o => o.setName('message').setDescription('Announcement').setRequired(true)),
  new SlashCommandBuilder().setName('say').setDescription('Send a bot message').addStringOption(o => o.setName('message').setDescription('Message').setRequired(true)),
  new SlashCommandBuilder().setName('poll').setDescription('Create a yes/no poll').addStringOption(o => o.setName('question').setDescription('Question').setRequired(true)),
  new SlashCommandBuilder().setName('nick').setDescription('Change a member nickname').addUserOption(o => o.setName('user').setDescription('Member').setRequired(true)).addStringOption(o => o.setName('nickname').setDescription('New nickname').setMaxLength(32).setRequired(true)),
  new SlashCommandBuilder().setName('setlogs').setDescription('Set moderation log channel').addChannelOption(o => o.setName('channel').setDescription('Text channel').addChannelTypes(ChannelType.GuildText).setRequired(true)),
  new SlashCommandBuilder().setName('setwelcome').setDescription('Set welcome channel').addChannelOption(o => o.setName('channel').setDescription('Text channel').addChannelTypes(ChannelType.GuildText).setRequired(true)),
  new SlashCommandBuilder().setName('setstatus').setDescription('Set bot activity').addStringOption(o => o.setName('text').setDescription('Activity text').setMaxLength(128).setRequired(true))
].map(c => c.toJSON());

async function log(guild, message) {
  const id = cfg(guild.id).logs;
  if (!id) return;
  const channel = guild.channels.cache.get(id);
  if (channel) await channel.send({ embeds: [embed('🛡️ Moderation Log', message, 0xf59e0b)] }).catch(() => {});
}

async function replyError(interaction, message) {
  const payload = { embeds: [errorEmbed(message)], ephemeral: true };
  if (interaction.replied || interaction.deferred) return interaction.followUp(payload).catch(() => {});
  return interaction.reply(payload).catch(() => {});
}

async function registerCommands() {
  const rest = new REST({ version: '10' }).setToken(env.BOT_TOKEN);
  await rest.put(Routes.applicationCommands(env.CLIENT_ID), { body: commands });
}

client.once('ready', () => {
  console.log(`[CJH] ${client.user.tag} online | ${client.guilds.cache.size} server(s)`);
  if (env.BOT_STATUS) client.user.setActivity(env.BOT_STATUS);
});

client.on('guildMemberAdd', async member => {
  const channelId = cfg(member.guild.id).welcome;
  if (!channelId) return;
  const channel = member.guild.channels.cache.get(channelId);
  if (channel) await channel.send({ embeds: [embed('👋 Welcome!', `Welcome ${mention(member.user)} to **${member.guild.name}**!\nYou are member **#${member.guild.memberCount}**.`, 0x22d3ee)] }).catch(() => {});
});

client.on('interactionCreate', async interaction => {
  if (!interaction.isChatInputCommand() || !interaction.guild) return;
  try {
    const n = interaction.commandName;
    const user = interaction.options.getUser('user') || interaction.user;
    const member = interaction.options.getMember('user');

    if (n === 'help') {
      return interaction.reply({ embeds: [embed('🤖 CJH Server Suite', '**Information**\n`/ping` `/security` `/server` `/userinfo` `/avatar` `/membercount`\n\n**Moderation**\n`/clear` `/kick` `/ban` `/unban` `/timeout` `/untimeout` `/warn` `/warnings` `/clearwarnings`\n\n**Channels**\n`/lock` `/unlock` `/slowmode`\n\n**Community**\n`/announce` `/say` `/poll` `/nick`\n\n**Setup**\n`/setlogs` `/setwelcome` `/setstatus`')] });
    }
    if (n === 'ping') return interaction.reply({ embeds: [ok('Pong', `WebSocket latency: **${client.ws.ping}ms**`)] });
    if (n === 'security') {
      const x = cfg(interaction.guild.id);
      return interaction.reply({ embeds: [embed('🛡️ Security Status', `**Verification:** ${interaction.guild.verificationLevel}\n**2FA requirement:** ${interaction.guild.mfaLevel}\n**Members:** ${interaction.guild.memberCount}\n**Roles:** ${interaction.guild.roles.cache.size}\n**Channels:** ${interaction.guild.channels.cache.size}\n**Logs:** ${x.logs ? `<#${x.logs}>` : 'Not configured'}\n**Welcome:** ${x.welcome ? `<#${x.welcome}>` : 'Not configured'}`, 0x22d3ee)] });
    }
    if (n === 'server') return interaction.reply({ embeds: [embed('🏠 Server Overview', `**${interaction.guild.name}**\nOwner: <@${interaction.guild.ownerId}>\nMembers: ${interaction.guild.memberCount}\nChannels: ${interaction.guild.channels.cache.size}\nRoles: ${interaction.guild.roles.cache.size}\nCreated: <t:${Math.floor(interaction.guild.createdTimestamp / 1000)}:R>`)] });
    if (n === 'userinfo') return interaction.reply({ embeds: [embed(`👤 ${user.username}`, `User: ${mention(user)}\nID: \`${user.id}\`\nCreated: <t:${Math.floor(user.createdTimestamp / 1000)}:R>`)] });
    if (n === 'avatar') return interaction.reply({ embeds: [embed(`🖼️ ${user.username}'s Avatar`, `[Open full size](${user.displayAvatarURL({ size: 1024 })})`).setImage(user.displayAvatarURL({ size: 1024 }))] });
    if (n === 'membercount') return interaction.reply({ embeds: [ok('Member Count', `This server currently has **${interaction.guild.memberCount}** member(s).`)] });

    if (n === 'clear') {
      if (!has(interaction, P.ManageMessages)) return replyError(interaction, 'Manage Messages permission is required.');
      const deleted = await interaction.channel.bulkDelete(interaction.options.getInteger('amount', true), true);
      await log(interaction.guild, `${interaction.user} deleted **${deleted.size}** message(s) in ${interaction.channel}.`);
      return interaction.reply({ embeds: [ok('Messages Cleared', `Deleted **${deleted.size}** message(s).`)], ephemeral: true });
    }

    if (['kick', 'ban'].includes(n)) {
      const permission = n === 'kick' ? P.KickMembers : P.BanMembers;
      if (!has(interaction, permission) || !member) return replyError(interaction, 'Missing permission or the user is not a member of this server.');
      const reason = interaction.options.getString('reason') || 'No reason provided';
      if (n === 'kick') {
        if (!member.kickable) return replyError(interaction, 'Role hierarchy prevents this member from being kicked.');
        await member.kick(reason);
      } else {
        if (!member.bannable) return replyError(interaction, 'Role hierarchy prevents this member from being banned.');
        await member.ban({ reason });
      }
      await log(interaction.guild, `${n === 'kick' ? 'Kicked' : 'Banned'} **${user.tag}** — ${reason}`);
      return interaction.reply({ embeds: [ok(n === 'kick' ? 'Member Kicked' : 'Member Banned', `${user.tag} was ${n === 'kick' ? 'kicked' : 'banned'}.\nReason: ${reason}`)] });
    }

    if (n === 'unban') {
      if (!has(interaction, P.BanMembers)) return replyError(interaction, 'Ban Members permission is required.');
      const id = interaction.options.getString('user_id', true).trim();
      if (!/^\d{17,20}$/.test(id)) return replyError(interaction, 'Enter a valid Discord user ID.');
      await interaction.guild.members.unban(id, 'CJH unban');
      await log(interaction.guild, `Unbanned user ID **${id}**.`);
      return interaction.reply({ embeds: [ok('Member Unbanned', `User ID **${id}** was unbanned.`)] });
    }

    if (n === 'timeout' || n === 'untimeout') {
      if (!has(interaction, P.ModerateMembers) || !member?.moderatable) return replyError(interaction, 'Missing Moderate Members permission or role hierarchy prevents this action.');
      const minutes = n === 'timeout' ? interaction.options.getInteger('minutes', true) : 0;
      const reason = n === 'timeout' ? (interaction.options.getString('reason') || 'CJH moderation') : 'CJH timeout removed';
      await member.timeout(minutes * 60000, reason);
      await log(interaction.guild, `${n === 'timeout' ? 'Timed out' : 'Removed timeout from'} **${user.tag}**${minutes ? ` for **${minutes} minute(s)**` : ''}.`);
      return interaction.reply({ embeds: [ok(n === 'timeout' ? 'Member Timed Out' : 'Timeout Removed', `${user.tag} ${n === 'timeout' ? `was timed out for **${minutes} minute(s)**.` : 'is no longer timed out.'}`)] });
    }

    if (n === 'warn') {
      if (!has(interaction, P.ModerateMembers) || !member) return replyError(interaction, 'Moderate Members permission is required.');
      const reason = interaction.options.getString('reason', true);
      const x = cfg(interaction.guild.id);
      x.warns[user.id] ??= [];
      x.warns[user.id].push({ reason, by: interaction.user.id, at: Date.now() });
      save();
      await log(interaction.guild, `Warned **${user.tag}** — ${reason}`);
      return interaction.reply({ embeds: [ok('Warning Added', `${user.tag} received a warning.\nReason: ${reason}`)] });
    }

    if (n === 'warnings' || n === 'clearwarnings') {
      if (!has(interaction, P.ModerateMembers)) return replyError(interaction, 'Moderate Members permission is required.');
      const x = cfg(interaction.guild.id);
      if (n === 'clearwarnings') {
        delete x.warns[user.id];
        save();
        await log(interaction.guild, `Cleared warnings for **${user.tag}**.`);
        return interaction.reply({ embeds: [ok('Warnings Cleared', `All warnings for ${user.tag} were cleared.`)], ephemeral: true });
      }
      const warnings = x.warns[user.id] || [];
      return interaction.reply({ ephemeral: true, embeds: [embed(`⚠️ Warnings: ${user.tag}`, warnings.length ? warnings.map((w, i) => `**${i + 1}.** ${w.reason}\nBy <@${w.by}> • <t:${Math.floor(w.at / 1000)}:R>`).join('\n\n') : 'No warnings recorded.')] });
    }

    if (n === 'lock' || n === 'unlock') {
      if (!has(interaction, P.ManageChannels)) return replyError(interaction, 'Manage Channels permission is required.');
      const locked = n === 'lock';
      await interaction.channel.permissionOverwrites.edit(interaction.guild.roles.everyone, { SendMessages: locked ? false : null });
      await log(interaction.guild, `${locked ? 'Locked' : 'Unlocked'} ${interaction.channel}.`);
      return interaction.reply({ embeds: [ok(locked ? 'Channel Locked' : 'Channel Unlocked', `${interaction.channel} is now **${locked ? 'locked' : 'unlocked'}**.`)] });
    }

    if (n === 'slowmode') {
      if (!has(interaction, P.ManageChannels)) return replyError(interaction, 'Manage Channels permission is required.');
      const seconds = interaction.options.getInteger('seconds', true);
      await interaction.channel.setRateLimitPerUser(seconds);
      return interaction.reply({ embeds: [ok('Slowmode Updated', `Slowmode is now **${seconds} second(s)**.`)] });
    }

    if (n === 'announce' || n === 'say') {
      if (!has(interaction, P.ManageGuild)) return replyError(interaction, 'Manage Server permission is required.');
      const message = interaction.options.getString('message', true);
      if (n === 'announce') await interaction.channel.send({ embeds: [embed('📢 Announcement', message, 0xec4899)] });
      else await interaction.channel.send({ embeds: [embed('💬 CJH Message', message, 0x8b5cf6)] });
      return interaction.reply({ embeds: [ok('Sent', 'Your message was sent successfully.')], ephemeral: true });
    }

    if (n === 'poll') {
      if (!has(interaction, P.SendMessages)) return replyError(interaction, 'Send Messages permission is required.');
      const question = interaction.options.getString('question', true);
      const message = await interaction.reply({ embeds: [embed('📊 Community Poll', `**${question}**\n\n👍 Yes\n👎 No`)], fetchReply: true });
      await message.react('👍');
      await message.react('👎');
      return;
    }

    if (n === 'nick') {
      if (!has(interaction, P.ManageNicknames) || !member?.manageable) return replyError(interaction, 'Manage Nicknames permission or role hierarchy prevents this action.');
      const nickname = interaction.options.getString('nickname', true);
      await member.setNickname(nickname, `CJH by ${interaction.user.tag}`);
      return interaction.reply({ embeds: [ok('Nickname Updated', `${user.tag}'s nickname is now **${nickname}**.`)] });
    }

    if (n === 'setlogs' || n === 'setwelcome') {
      if (!has(interaction, P.ManageGuild)) return replyError(interaction, 'Manage Server permission is required.');
      const channel = interaction.options.getChannel('channel', true);
      cfg(interaction.guild.id)[n === 'setlogs' ? 'logs' : 'welcome'] = channel.id;
      save();
      return interaction.reply({ embeds: [ok(n === 'setlogs' ? 'Logs Configured' : 'Welcome Configured', `${channel} is now the ${n === 'setlogs' ? 'moderation log' : 'welcome'} channel.`)] });
    }

    if (n === 'setstatus') {
      if (!has(interaction, P.ManageGuild)) return replyError(interaction, 'Manage Server permission is required.');
      const text = interaction.options.getString('text', true);
      client.user.setActivity(text);
      return interaction.reply({ embeds: [ok('Status Updated', `Bot activity is now **${text}**.`)], ephemeral: true });
    }
  } catch (error) {
    console.error('[CJH]', error);
    await replyError(interaction, 'The command failed. Check bot permissions, role hierarchy, channel permissions, and Discord intents.');
  }
});

(async () => {
  try {
    await registerCommands();
    await client.login(env.BOT_TOKEN);
  } catch (error) {
    console.error('[CJH] Startup failed:', error.message);
    process.exit(1);
  }
})();
