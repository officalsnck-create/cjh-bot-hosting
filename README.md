# 🤖 SNCK / CJH Bot Hosting

A real Discord bot + LXD VPS management toolkit for Ubuntu/Debian hosts.

> **Made by root_dora**

## What changed in v9

- Real **LXD** runtime validation instead of treating the legacy `lxc` package as LXD.
- Automatic LXD installation/initialization on supported Ubuntu/Debian VPS hosts.
- APT handling for the known unsupported `r2u` `deb-src` entry.
- Isolated Python virtual environment for every bot.
- `systemd` service support on normal VPS hosts, with a fallback for containerized development environments.
- Python LXD API client for actual VPS provisioning.
- Real Discord moderation commands: clear, kick, ban, timeout, lock and unlock.
- Real VPS commands: deploy, list, IP lookup, start, stop, restart and admin delete.
- Working Discord application commands: `/about`, `/ping`, and `/deploy` with automatic command sync.
- LXD health checks use PyLXD's actual `host_info` property and validate storage, network, and the default profile.
- SQLite persistence and automatic bot restart.
- Discord embeds use the footer **Made by root_dora**.

## ⚡ One-command installer

On a supported Ubuntu/Debian VPS:

```bash
bash <(curl -fsSL "https://raw.githubusercontent.com/officalsnck-create/cjh-bot-hosting/main/setup.sh?$(date +%s)")
```

The cache-busting query helps avoid an older raw GitHub response.

## 🖥️ Menu

```text
╭──────────────────────────────────────────────────────────────────────────╮
│  SNCK BOT HOSTING  v9.1.2  •  VPS CONTROL CENTER                        │
╰──────────────────────────────────────────────────────────────────────────╯

  01  Install / Create Bot + LXD VPS Node
  02  Start Bot
  03  Stop Bot
  04  Restart Bot
  05  Live Logs
  06  Update Bot
  07  Remove Bot
  08  System / LXD / Service Status
  09  Full Self Check
  Q   Quit
```

These are real service/filesystem operations. There are no placeholder demo buttons.

## 🧱 Architecture

```text
Discord
   │
   ▼
SNCK Python Bot
   │
   ▼
Python LXD API
   │
   ▼
LXD daemon
   ├── VPS 01
   ├── VPS 02
   └── VPS ...
```

The bot uses the LXD API rather than scraping terminal output. This avoids the earlier problem where the Ubuntu `lxc` package was installed but the LXD daemon was not actually usable.

## 🔐 SSH access for deployed VPS

For secure access, configure an SSH public key on the host before using `!deploy`.

Add this to the bot's `.env`:

```env
DEPLOY_SSH_PUBLIC_KEY=ssh-ed25519 AAAA...your-public-key...
```

The bot injects that public key through cloud-init and exposes SSH through an LXD proxy port. **Never put a private SSH key in `.env` or Discord.**

After editing `.env`, restart the bot from the installer menu.

## 🤖 Discord commands

### VPS

```text
!deploy
!vps
!vps-start <container-name>
!vps-stop <container-name>
!vps-restart <container-name>
!vps-ip <container-name>
!vps-delete <container-name>   # main admin only
```

The deployment role is controlled by `DEPLOY_ROLE_ID`. The main admin is controlled by `MAIN_ADMIN_ID`.

Default VPS resources are controlled by:

```env
DEPLOY_RAM=2
DEPLOY_CPU=2
DEPLOY_DISK=20
VPS_DEPLOY_LIMIT=2
DEPLOY_SLOT=0
DEFAULT_VPS_EXPIRATION_DAYS=30
```

### Moderation

```text
!clear [amount]
!kick <member> [reason]
!ban <member> [reason]
!timeout <member> [minutes] [reason]
!lock
!unlock
```

Discord permission checks and role hierarchy checks are applied by the bot.

### Information

```text
!ping
!server
!security
!help
```

## 🛠️ Host requirements

For **actual VPS creation**, use a normal Ubuntu/Debian VM or VPS where LXD can run as the host container manager.

GitHub Codespaces and Google Colab are useful for development/testing, but they are not reliable LXD host environments. The installer therefore verifies the LXD daemon instead of pretending that package installation alone means VPS creation works.

The host must pass:

```bash
lxc version
lxc info
lxc storage list
lxc network list
```

## 🔧 Diagnostics

If installation stops:

```bash
cat /tmp/cjh-apt-update.log
cat /tmp/cjh-apt-install.log
cat /tmp/cjh-lxc-version.log
cat /tmp/cjh-lxc-info.log
cat /tmp/cjh-lxc-storage.log
cat /tmp/cjh-lxc-network.log
```

Or select **09 — Full Self Check** in the installer.

## 📁 Runtime layout

```text
~/cjh-bots/
└── <bot-name>/
    ├── .env
    ├── bot.py
    ├── requirements.txt
    ├── venv/
    ├── bot.log
    └── vps.db
```

On systemd-capable hosts:

```text
/etc/systemd/system/cjh-<bot-name>.service
```

## 🔒 Security

- Never publish the Discord bot token.
- Never publish a private SSH key.
- Use a dedicated deployment role.
- Give the Discord bot only the permissions it needs.
- Keep Ubuntu/Debian and LXD updated.
- Do not expose the LXD API socket to the public internet.

## 📦 Project files

```text
cjh-bot-hosting/
├── README.md
├── setup.sh
├── bot.py
├── requirements.txt
└── bot-template.js
```

`setup.sh` is the single installer/manager entrypoint. `bot.py` is the real Python Discord + LXD implementation.

---

**SNCK / CJH Bot Hosting — real Discord automation, real LXD VPS provisioning, and no fake management actions.**

## v9.1.2 reliability fixes

- Reconciles real LXD instances that survived a bot/database reinstall, so a stale `user-vps-1` no longer causes a duplicate-name deployment failure.
- Counts existing LXD instances when enforcing VPS limits and allocates SSH proxy ports from both SQLite and LXD state.
- Serializes deployment requests to prevent two simultaneous deploys from selecting the same name or port.
- Waits for SSH readiness and uses the actual PyLXD `execute()` tuple return format.
- Uninstall now stops/disables the systemd unit, removes PM2 entries, terminates stale bot processes, removes the bot directory, and verifies whether the old process is gone.
