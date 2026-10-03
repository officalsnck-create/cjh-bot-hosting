# 🤖 CJH Bot Hosting

A lightweight **Discord Bot Hosting & Management Toolkit** for Ubuntu/Debian VPS servers. CJH provides a simple interactive terminal menu for creating, starting, stopping, updating, and removing Discord bot instances with PM2.

> **Project:** `officalsnck-create/cjh-bot-hosting`  
> **Main installer:** `setup.sh`

---

## ✨ Features

- 🚀 One-command installation
- 🧭 Interactive terminal management menu
- 🤖 Create and configure a Discord bot
- 🟢 Start / 🔴 stop bot processes
- 🗑️ Remove bot installations
- 🔄 Update the local project when used from a Git repository
- ⚡ PM2 process management
- 📦 Automatic Node.js installation when Node.js is missing
- 🔊 Discord voice-channel join support
- 🛡️ Basic message moderation / timeout protection
- 📡 Discord slash commands
- 💾 PM2 process persistence across reboots
- 🐧 Designed for Ubuntu/Debian VPS environments

---

## ⚡ One-Command Installer

Run this on your Ubuntu/Debian VPS:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/officalsnck-create/cjh-bot-hosting/main/setup.sh)
```

The installer launches the CJH menu automatically.

### Safer alternative

If you prefer to inspect the installer before executing it:

```bash
curl -fsSL https://raw.githubusercontent.com/officalsnck-create/cjh-bot-hosting/main/setup.sh -o setup.sh
less setup.sh
chmod +x setup.sh
./setup.sh
```

---

## 🧭 Management Menu

After starting `setup.sh`, you will get an interactive menu similar to:

```text
==========================================
               CJH BOT
==========================================
1. CREATE Bot (Setup & Run)
2. UNINSTALL Bot (Stop & Delete)
3. UPDATE Bot (Pull latest from GitHub)
4. START Bot (Select from list)
5. STOP Bot (Select from list)
6. VPS Deploy Bot (Coming Soon)
7. Exit
==========================================
```

Choose an option by entering its number.

---

## 🚀 Create a Bot

Select:

```text
1. CREATE Bot
```

CJH will:

1. Check for Node.js.
2. Install Node.js if required.
3. Ask for the Discord bot token.
4. Ask for the Discord Application / Client ID.
5. Ask for the administrator Discord user ID.
6. Ask for a bot folder/process name.
7. Create the bot files.
8. Install npm dependencies.
9. Install PM2 if necessary.
10. Start the bot with PM2.
11. Save the PM2 process list.

The bot can then continue running after you disconnect from SSH.

---

## 🛠️ Requirements

Recommended environment:

- Ubuntu 22.04 / 24.04 or compatible Debian-based Linux
- `curl`
- `sudo` access
- Internet connection
- A Discord application/bot created through Discord's official developer tools

Node.js and PM2 are installed automatically by the current installer when they are not already available.

---

## 🤖 Included Bot Commands

The generated bot currently includes:

| Command | Purpose |
|---|---|
| `/ping` | Check bot latency |
| `/security` | Show the basic security/moderation status |
| `/joinvc` | Join the invoking user's current voice channel |
| `!ping` | Prefix-based latency check |

The generated bot also includes basic prohibited-word detection and automatic timeout handling.

---

## 🔐 Discord Configuration

When creating the Discord application, make sure the bot has the permissions and gateway intents required by the features you enable.

For the current generated bot, message-based moderation uses message content and guild/member-related events. Voice functionality also requires the appropriate voice permissions in the target server/channel.

**Never publish your bot token.** Treat it like a password. If a token is accidentally exposed, rotate it immediately through Discord's developer tools.

---

## 📁 Project Structure

```text
cjh-bot-hosting/
├── README.md
└── setup.sh
```

`setup.sh` is the interactive installer and management entry point. It generates the bot runtime files inside the selected bot directory.

---

## 🔄 Updating

If you are running the project from a cloned Git repository, choose:

```text
3. UPDATE Bot
```

The updater attempts to pull the latest `main` branch changes.

If you originally executed the remote one-command installer without cloning the repository, download the latest `setup.sh` again when you want to refresh the installer.

---

## 🟢 Process Management

CJH uses **PM2** to keep bot processes running.

Useful commands:

```bash
pm2 list
pm2 logs
pm2 save
pm2 resurrect
```

You can also manage bots directly from the CJH menu.

---

## 🧹 Uninstall a Bot

Choose:

```text
2. UNINSTALL Bot
```

CJH displays the active PM2 processes and lets you select the bot process to remove.

> Review the bot name carefully before confirming removal because the bot directory is deleted by the current uninstall routine.

---

## 🔒 Security Notes

CJH is intended for legitimate bot hosting and server administration.

- Do not commit Discord tokens or other secrets to Git.
- Use least-privilege Discord permissions where possible.
- Keep Ubuntu/Debian and Node.js packages updated.
- Use a non-root account for routine administration when practical.
- Restrict SSH access and use key-based authentication where possible.
- Review `setup.sh` before running it on a production server.

---

## 🧪 Troubleshooting

### Check whether Node.js is installed

```bash
node --version
npm --version
```

### Check PM2

```bash
pm2 --version
pm2 list
```

### View bot logs

```bash
pm2 logs
```

### Restart a bot

```bash
pm2 restart <bot-name>
```

### Check whether the bot process is online

```bash
pm2 status
```

---

## 🐧 VPS Quick Start

For a fresh Ubuntu/Debian VPS:

```bash
sudo apt update && sudo apt install -y curl
bash <(curl -fsSL https://raw.githubusercontent.com/officalsnck-create/cjh-bot-hosting/main/setup.sh)
```

Then select **CREATE Bot** from the menu and follow the prompts.

---

## 🗺️ Roadmap

Planned improvements can include:

- 🌐 Web-based management panel
- 🖥️ Multi-VPS/node management
- 📊 CPU/RAM/storage monitoring
- 🗂️ Browser-based bot file manager
- 🔐 Encrypted secret storage
- 🔁 Automated backup and restore
- 🧩 Runtime templates for Node.js, Python, Java and more
- ☁️ Remote deployment workflow
- 🟢 Better health checks and automatic recovery
- 📦 Release-based installer versions

---

## 🤝 Contributing

Contributions are welcome.

1. Fork the repository.
2. Create a feature branch.
3. Make and test your changes.
4. Open a pull request with a clear description of the change.

Please avoid committing secrets, tokens, private keys, or generated credentials.

---

## 📜 License

See the repository for the project's license information.

---

## ⭐ Support the Project

If CJH Bot Hosting is useful to you, consider starring the repository and sharing improvements through pull requests.

**CJH Bot Hosting — simple bot management from your VPS terminal.**
