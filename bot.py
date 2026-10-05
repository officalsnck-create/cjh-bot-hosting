import logging
import os
import re
import sqlite3
from datetime import datetime, timedelta, timezone
from pathlib import Path

import discord
from discord.ext import commands
from dotenv import load_dotenv
from pylxd import Client

BASE = Path(__file__).resolve().parent
load_dotenv(BASE / ".env")
TOKEN = os.getenv("DISCORD_TOKEN", "").strip()
BOT_NAME = os.getenv("BOT_NAME", "SNCK VPS")
PREFIX = os.getenv("PREFIX", "!")
ADMIN_ID = os.getenv("MAIN_ADMIN_ID", "0").strip()
DEPLOY_ROLE_ID = os.getenv("DEPLOY_ROLE_ID", "0").strip()
HOST_IP = os.getenv("YOUR_SERVER_IP", "127.0.0.1").strip()
RAM_GB = int(os.getenv("DEPLOY_RAM", "16"))
CPU = int(os.getenv("DEPLOY_CPU", "3"))
DISK_GB = int(os.getenv("DEPLOY_DISK", "80"))
VPS_LIMIT = int(os.getenv("VPS_DEPLOY_LIMIT", "2"))
VPS_SLOTS = int(os.getenv("DEPLOY_SLOT", "0"))
EXPIRY_DAYS = int(os.getenv("DEFAULT_VPS_EXPIRATION_DAYS", "30"))
VERSION = os.getenv("BOT_VERSION", "9.0.0")
DEVELOPER = os.getenv("BOT_DEVELOPER", "root_dora")
SSH_PUBLIC_KEY = os.getenv("DEPLOY_SSH_PUBLIC_KEY", "").strip()
LXD_ENDPOINT = os.getenv("LXD_ENDPOINT", "").strip()
DB = BASE / "vps.db"
LOG = BASE / "bot.log"

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s", handlers=[logging.FileHandler(LOG), logging.StreamHandler()])
logger = logging.getLogger("snck")
if not TOKEN:
    raise RuntimeError("DISCORD_TOKEN is missing from .env")
if not ADMIN_ID.isdigit():
    raise RuntimeError("MAIN_ADMIN_ID must be numeric")

intents = discord.Intents.default()
intents.message_content = True
intents.members = True
bot = commands.Bot(command_prefix=PREFIX, intents=intents, help_command=None)


def db():
    c = sqlite3.connect(DB, timeout=20)
    c.row_factory = sqlite3.Row
    c.execute("PRAGMA journal_mode=WAL")
    return c


def init_db():
    with db() as c:
        c.execute("""CREATE TABLE IF NOT EXISTS vps(
            id INTEGER PRIMARY KEY AUTOINCREMENT, owner TEXT NOT NULL, name TEXT UNIQUE NOT NULL,
            os TEXT NOT NULL, ram INTEGER NOT NULL, cpu INTEGER NOT NULL, disk INTEGER NOT NULL,
            status TEXT NOT NULL DEFAULT 'STOPPED', ssh_port INTEGER, expires TEXT NOT NULL, created TEXT NOT NULL)""")


def card(title, text, color=0x9B6DFF):
    e = discord.Embed(title=f"✦ {title}", description=text[:4096], color=color, timestamp=datetime.now(timezone.utc))
    e.set_footer(text=f"Made by {DEVELOPER} • SNCK VPS v{VERSION}")
    return e


def is_admin(uid):
    return str(uid) == ADMIN_ID


def can_deploy(member):
    return is_admin(member.id) or DEPLOY_ROLE_ID == "0" or any(str(r.id) == DEPLOY_ROLE_ID for r in member.roles)


def lxd_endpoint():
    if LXD_ENDPOINT:
        return LXD_ENDPOINT
    snap_socket = Path("/var/snap/lxd/common/lxd/unix.socket")
    if snap_socket.exists():
        return f"unix://{snap_socket}"
    return None


def lxd_client():
    endpoint = lxd_endpoint()
    return Client(endpoint=endpoint) if endpoint else Client()


def lxd_ready():
    try:
        lxd_client().host_info()
        return True
    except Exception as exc:
        logger.warning("LXD health check failed: %s", exc)
        return False


def safe_name(s):
    s = re.sub(r"[^a-z0-9-]+", "-", s.lower()).strip("-")
    return (s[:22] or "user")


def count_vps(owner=None):
    with db() as c:
        if owner is None:
            return c.execute("SELECT COUNT(*) FROM vps").fetchone()[0]
        return c.execute("SELECT COUNT(*) FROM vps WHERE owner=?", (str(owner),)).fetchone()[0]


def next_port():
    with db() as c:
        used = {r[0] for r in c.execute("SELECT ssh_port FROM vps WHERE ssh_port IS NOT NULL")}
    for port in range(20000, 50000):
        if port not in used:
            return port
    raise RuntimeError("No free SSH proxy ports remain")


def instance_for(name):
    client = lxd_client()
    try:
        return client.instances.get(name)
    except Exception:
        return None


def configure_instance(instance, port):
    config = dict(instance.config)
    config["limits.memory"] = f"{RAM_GB}GiB"
    config["limits.cpu"] = str(CPU)
    config["security.nesting"] = "true"
    config["security.privileged"] = "true"
    if SSH_PUBLIC_KEY:
        config["user.user-data"] = "\n".join([
            "#cloud-config",
            "users:",
            "  - name: root",
            "    lock_passwd: false",
            "    ssh_authorized_keys:",
            f"      - {SSH_PUBLIC_KEY}",
            "packages:",
            "  - openssh-server",
            "runcmd:",
            "  - systemctl enable --now ssh",
        ])
    devices = dict(instance.devices)
    root = dict(devices.get("root", {"type": "disk", "pool": "default", "path": "/"}))
    root["size"] = f"{DISK_GB}GiB"
    devices["root"] = root
    devices[f"ssh-{port}"] = {"type": "proxy", "listen": f"tcp:0.0.0.0:{port}", "connect": "tcp:127.0.0.1:22"}
    instance.config = config
    instance.devices = devices
    instance.save(wait=True)


def create_instance(owner):
    if not lxd_ready():
        raise RuntimeError("LXD is not reachable on this host. Run the installer self-check and use a VPS/VM that permits LXD.")
    if not SSH_PUBLIC_KEY:
        raise RuntimeError("DEPLOY_SSH_PUBLIC_KEY is not configured. Add an SSH public key in the bot .env before using !deploy.")
    if count_vps(owner.id) >= VPS_LIMIT:
        raise RuntimeError(f"Your VPS limit is {VPS_LIMIT}.")
    if VPS_SLOTS and count_vps() >= VPS_SLOTS:
        raise RuntimeError("Global VPS slot limit reached.")
    client = lxd_client()
    name = f"{safe_name(owner.display_name)}-vps-{count_vps()+1}"
    port = next_port()
    expires = (datetime.now(timezone.utc) + timedelta(days=EXPIRY_DAYS)).isoformat()
    try:
        instance = client.instances.create({
            "name": name,
            "source": {
                "type": "image",
                "alias": "24.04",
                "protocol": "simplestreams",
                "server": "https://cloud-images.ubuntu.com/releases",
            },
        }, wait=True)
        configure_instance(instance, port)
        instance.start(wait=True)
        with db() as c:
            c.execute("INSERT INTO vps(owner,name,os,ram,cpu,disk,status,ssh_port,expires,created) VALUES(?,?,?,?,?,?,?,?,?,?)", (str(owner.id), name, "Ubuntu 24.04", RAM_GB, CPU, DISK_GB, "RUNNING", port, expires, datetime.now(timezone.utc).isoformat()))
        return name, port, expires
    except Exception:
        existing = instance_for(name)
        if existing:
            try: existing.delete(wait=True, force=True)
            except Exception: pass
        raise


@bot.event
async def on_ready():
    init_db()
    logger.info("Connected as %s | LXD ready=%s", bot.user, lxd_ready())
    await bot.change_presence(activity=discord.Activity(type=discord.ActivityType.watching, name="SNCK VPS Hosting"))


@bot.command()
async def ping(ctx):
    await ctx.send(embed=card("Pong", f"Latency: `{round(bot.latency * 1000)}ms`\nLXD: **{'READY' if lxd_ready() else 'NOT READY'}**", 0x57F287))


@bot.command()
async def security(ctx):
    await ctx.send(embed=card("Security", "Keep the bot token and SSH private key private. Use least-privilege Discord permissions and keep the host updated.", 0x00C2FF))


@bot.command()
async def server(ctx):
    await ctx.send(embed=card("Server", f"Guild: **{ctx.guild.name if ctx.guild else 'DM'}**\nMembers: **{ctx.guild.member_count if ctx.guild else 'N/A'}**\nHost: `{HOST_IP}`"))


@bot.command()
async def vps(ctx):
    with db() as c: rows = c.execute("SELECT * FROM vps WHERE owner=? ORDER BY id", (str(ctx.author.id),)).fetchall()
    if not rows:
        await ctx.send(embed=card("Your VPS", "No VPS found.")); return
    text = "\n\n".join(f"**#{r['id']} `{r['name']}`**\n{r['status']} • {r['os']} • {r['ram']}GB RAM • {r['cpu']} CPU • {r['disk']}GB disk\nSSH: `ssh root@{HOST_IP} -p {r['ssh_port']}`\nExpires: `{r['expires'][:10]}`" for r in rows)
    await ctx.send(embed=card("Your VPS", text))


@bot.command()
async def deploy(ctx):
    if not isinstance(ctx.author, discord.Member) or not can_deploy(ctx.author):
        await ctx.send(embed=card("Access denied", "You do not have the VPS deployment role.", 0xED4245)); return
    m = await ctx.send(embed=card("Deploying", "Creating a real LXD VPS. Please wait...", 0xFEE75C))
    try:
        name, port, expires = create_instance(ctx.author)
        text = f"**Container:** `{name}`\n**OS:** `Ubuntu 24.04`\n**Resources:** `{RAM_GB}GB RAM / {CPU} CPU / {DISK_GB}GB disk`\n**SSH:** `ssh root@{HOST_IP} -p {port}`\n**Auth:** your configured SSH public key\n**Expires:** `{expires[:10]}`"
        await m.edit(embed=card("VPS deployed", text, 0x57F287))
    except Exception as e:
        logger.exception("deploy failed")
        await m.edit(embed=card("Deployment failed", str(e), 0xED4245))


async def owned(ctx, name):
    with db() as c: row = c.execute("SELECT * FROM vps WHERE name=?", (name,)).fetchone()
    return row if row and (str(row["owner"]) == str(ctx.author.id) or is_admin(ctx.author.id)) else None


@bot.command(name="vps-start")
async def vps_start(ctx, name):
    row = await owned(ctx, name)
    if not row: await ctx.send(embed=card("Not found", "VPS not found or not owned.", 0xED4245)); return
    try:
        i = instance_for(name)
        if not i: raise RuntimeError("LXD instance not found")
        i.start(wait=True)
        with db() as c: c.execute("UPDATE vps SET status='RUNNING' WHERE name=?", (name,))
        await ctx.send(embed=card("VPS started", f"`{name}` is running.", 0x57F287))
    except Exception as e: await ctx.send(embed=card("Start failed", str(e), 0xED4245))


@bot.command(name="vps-stop")
async def vps_stop(ctx, name):
    row = await owned(ctx, name)
    if not row: await ctx.send(embed=card("Not found", "VPS not found or not owned.", 0xED4245)); return
    try:
        i = instance_for(name)
        if not i: raise RuntimeError("LXD instance not found")
        i.stop(wait=True, force=True)
        with db() as c: c.execute("UPDATE vps SET status='STOPPED' WHERE name=?", (name,))
        await ctx.send(embed=card("VPS stopped", f"`{name}` is stopped.", 0xFEE75C))
    except Exception as e: await ctx.send(embed=card("Stop failed", str(e), 0xED4245))


@bot.command(name="vps-delete")
async def vps_delete(ctx, name):
    row = await owned(ctx, name)
    if not row or not is_admin(ctx.author.id):
        await ctx.send(embed=card("Access denied", "Only the main admin can permanently delete VPS instances.", 0xED4245)); return
    try:
        i = instance_for(name)
        if i: i.delete(wait=True, force=True)
        with db() as c: c.execute("DELETE FROM vps WHERE name=?", (name,))
        await ctx.send(embed=card("VPS deleted", f"`{name}` was deleted.", 0x57F287))
    except Exception as e: await ctx.send(embed=card("Delete failed", str(e), 0xED4245))


@bot.command()
@commands.has_permissions(manage_messages=True)
async def clear(ctx, amount: int = 10):
    amount = max(1, min(amount, 100)); deleted = await ctx.channel.purge(limit=amount + 1)
    await ctx.send(embed=card("Messages cleared", f"Deleted **{max(0, len(deleted)-1)}** messages.", 0x57F287), delete_after=4)


@bot.command()
@commands.has_permissions(kick_members=True)
async def kick(ctx, member: discord.Member, *, reason="No reason provided"):
    if member.top_role >= ctx.author.top_role or member == ctx.guild.owner:
        await ctx.send(embed=card("Kick blocked", "Discord role hierarchy prevents this action.", 0xED4245)); return
    await member.kick(reason=reason); await ctx.send(embed=card("Member kicked", f"{member.mention}\nReason: {reason}", 0x57F287))


@bot.command()
@commands.has_permissions(ban_members=True)
async def ban(ctx, member: discord.Member, *, reason="No reason provided"):
    if member.top_role >= ctx.author.top_role or member == ctx.guild.owner:
        await ctx.send(embed=card("Ban blocked", "Discord role hierarchy prevents this action.", 0xED4245)); return
    await member.ban(reason=reason); await ctx.send(embed=card("Member banned", f"{member.mention}\nReason: {reason}", 0xED4245))


@bot.command()
@commands.has_permissions(moderate_members=True)
async def timeout(ctx, member: discord.Member, minutes: int = 10, *, reason="No reason provided"):
    minutes = max(1, min(minutes, 40320))
    if member.top_role >= ctx.author.top_role or member == ctx.guild.owner:
        await ctx.send(embed=card("Timeout blocked", "Discord role hierarchy prevents this action.", 0xED4245)); return
    await member.timeout(timedelta(minutes=minutes), reason=reason)
    await ctx.send(embed=card("Member timed out", f"{member.mention}\nDuration: **{minutes} minutes**\nReason: {reason}", 0xFEE75C))


@bot.command(name="lock")
@commands.has_permissions(manage_channels=True)
async def lock_channel(ctx):
    await ctx.channel.set_permissions(ctx.guild.default_role, send_messages=False); await ctx.send(embed=card("Channel locked", ctx.channel.mention, 0xFEE75C))


@bot.command(name="unlock")
@commands.has_permissions(manage_channels=True)
async def unlock_channel(ctx):
    await ctx.channel.set_permissions(ctx.guild.default_role, send_messages=None); await ctx.send(embed=card("Channel unlocked", ctx.channel.mention, 0x57F287))


@bot.command()
async def help(ctx):
    await ctx.send(embed=card("SNCK Help", f"**VPS:** `{PREFIX}deploy`, `{PREFIX}vps`, `{PREFIX}vps-start <name>`, `{PREFIX}vps-stop <name>`, `{PREFIX}vps-delete <name>`\n**Moderation:** `{PREFIX}clear`, `{PREFIX}kick`, `{PREFIX}ban`, `{PREFIX}timeout`, `{PREFIX}lock`, `{PREFIX}unlock`\n**Info:** `{PREFIX}ping`, `{PREFIX}security`, `{PREFIX}server`"))


@bot.event
async def on_command_error(ctx, error):
    if isinstance(error, commands.CommandNotFound): return
    if isinstance(error, commands.MissingPermissions):
        await ctx.send(embed=card("Permission denied", "You do not have the required Discord permission.", 0xED4245)); return
    if isinstance(error, (commands.MissingRequiredArgument, commands.BadArgument)):
        await ctx.send(embed=card("Invalid command", f"Use `{PREFIX}help` for usage.", 0xFEE75C)); return
    logger.exception("command error", exc_info=error)
    await ctx.send(embed=card("Command error", str(error)[:1200], 0xED4245))


init_db()
bot.run(TOKEN)
