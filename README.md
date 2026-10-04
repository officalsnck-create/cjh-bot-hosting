# 🤖 CJH Bot Hosting

A production-focused Discord bot hosting and management toolkit for Ubuntu/Debian VPS servers.

CJH uses a **single installer**, PM2 for process supervision, and a real Discord.js runtime. The installer validates the bot source before starting it and provides a complete bot lifecycle menu.

## ✨ What is included

### VPS / hosting manager

- 🚀 One-command installer
- 🎨 Premium terminal UI with purple/cyan/pink ANSI glass-style presentation
- 🤖 Deploy a real Discord bot
- 🟢 Start
- 🔴 Stop
- 🔄 Restart
- 📜 Live logs
- ⬆️ Update an installed bot from the current repository bot source
- 🗑️ Safe remove with explicit confirmation
- 📊 Node.js / npm / PM2 status
- 💾 PM2 persistence
- 🧹 Failed installs roll back instead of leaving a half-created bot
- 🔐 `.env` is created with restrictive permissions
- ✅ Node.js syntax validation before a bot is started

## ⚡ One-command installer

On Ubuntu/Debian:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/officalsnck-create/cjh-bot-hosting/main/setup.sh)
```

The installer is intentionally consolidated: **`setup.sh` is the only installer entrypoint.**

## 🧭 Management menu

```text
╭──────────────────────────────────────────────────────────────────────────────╮
│  CJH BOT HOSTING  v7.0.0 • REAL DISCORD CONTROL                              │
╰──────────────────────────────────────────────────────────────────────────────╯

  01  Deploy new bot
  02  Start bot
  03  Stop bot
  04  Restart bot
  05  Live logs
  06  Update bot
  07  Remove bot
  08  System / PM2 status
  Q   Quit
```

There are no fake/demo management actions in the menu: each lifecycle action maps to the local PM2 process and filesystem.

## 🤖 Real Discord features

The generated bot uses the Discord API and Discord.js v14.

### Information

- `/help`
- `/ping`
- `/security`
- `/server`
- `/userinfo`
- `/avatar`
- `/membercount`

### Moderation

- `/clear`
- `/kick`
- `/ban`
- `/unban`
- `/timeout`
- `/untimeout`
- `/warn`
- `/warnings`
- `/clearwarnings`

Moderation actions check Discord permissions and role hierarchy before performing the action.

### Channel management

- `/lock`
- `/unlock`
- `/slowmode`

### Community / utility

- `/announce`
- `/say`
- `/poll`
- `/nick`

### Server configuration

- `/setlogs` — persistent moderation logging
- `/setwelcome` — persistent welcome channel
- `/setstatus` — change bot activity

### Automatic behavior

- 👋 Real welcome messages
- 🛡️ Moderation log embeds
- 💾 Persistent warning storage in `data.json`
- 📊 Yes/no reaction polls
- 🧩 Slash-command registration through Discord's API

## 💎 Bot message design

CJH responses use Discord embeds instead of plain, unfinished-looking messages. Successful actions use a clean confirmation card, failures use a separate error card, and moderation logs use their own embed style.

Every CJH embed carries the footer:

> **Made by root_dora • CJH Bot Hosting**

## 🔐 Discord setup

Create a bot application in Discord's official developer tools and keep the token private.

The bot requires the Discord permissions appropriate to the commands you enable, such as:

- Manage Messages for `/clear`
- Kick Members for `/kick`
- Ban Members for `/ban` and `/unban`
- Moderate Members for `/timeout`, `/untimeout`, `/warn`, and warning management
- Manage Channels for `/lock`, `/unlock`, and `/slowmode`
- Manage Server for configuration and announcements
- Manage Nicknames for `/nick`

The welcome system uses the Guild Members gateway intent. Enable the corresponding privileged intent in the Discord Developer Portal if your application requires it.

**Never publish your bot token.** If it is exposed, rotate it immediately.

## 📁 Runtime layout

```text
~/cjh-bots/
└── my-bot/
    ├── .env
    ├── bot.js
    ├── package.json
    ├── package-lock.json
    └── data.json
```

The `.env` contains the bot credentials and is created with restrictive permissions. `data.json` stores per-server configuration and warnings.

## 🛠️ Requirements

- Ubuntu/Debian VPS
- Internet connection
- `sudo` access when Node.js/PM2 must be installed
- A Discord application and bot token

The installer installs Node.js 20, npm, PM2, curl, and CA certificates when required.

## 🧪 Validation and recovery

Before the bot is started, CJH runs:

```bash
node --check bot.js
```

The installer also installs dependencies before launching PM2. If source download, syntax validation, or dependency installation fails during a new deployment, the incomplete bot directory is removed.

For an installed bot, use **Update bot** to download the current repository bot source, validate it, install dependencies, and restart the bot.

## 📜 PM2 commands

```bash
pm2 list
pm2 logs
pm2 save
pm2 resurrect
```

CJH saves the process list after lifecycle operations so bots can be restored after a reboot when PM2 startup has been configured on the VPS.

## 🔒 Security notes

- Never commit tokens or `.env` files.
- Use least-privilege Discord permissions.
- Keep the VPS and Node.js packages updated.
- Do not run untrusted bot code.
- Review the installer before running it on a production server if your environment has strict change-control requirements.

## 🧩 Project files

```text
cjh-bot-hosting/
├── README.md
├── setup.sh
└── bot-template.js
```

`setup.sh` is the single installer/manager. `bot-template.js` is the real Discord bot template downloaded during deployment.

## 📜 License

See the repository license information for the applicable terms.

---

**CJH Bot Hosting — real Discord automation, clean VPS management, and a better terminal experience.**
