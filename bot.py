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
BOT_NAME = os.getenv("BOT_NAME", "SNCK VPS").strip()
PREFIX = os.getenv("PREFIX", "!").strip() or "!"
ADMIN_ID = os.getenv("MAIN_ADMIN_ID", "0").strip()
DEPLOY_ROLE_ID = os.getenv("DEPLOY_ROLE_ID", "0").strip()
HOST_IP = os.getenv("YOUR_SERVER_IP", "127.0.0.1").strip()

RAM_GB = int(os.getenv("DEPLOY_RAM", "2"))
CPU = int(os.getenv("DEPLOY_CPU", "2"))
DISK_GB = int(os.getenv("DEPLOY_DISK", "20"))
VPS_LIMIT = int(os.getenv("VPS_DEPLOY_LIMIT", "2"))
VPS_SLOTS = int(os.getenv("DEPLOY_SLOT", "0"))
EXPIRY_DAYS = int(os.getenv("DEFAULT_VPS_EXPIRATION_DAYS", "30"))
VERSION = os.getenv("BOT_VERSION", "9.1.0")
DEVELOPER = os.getenv("BOT_DEVELOPER", "root_dora")
SSH_PUBLIC_KEY = os.getenv("DEPLOY_SSH_PUBLIC_KEY", "").strip()

# Local LXD: leave LXD_ENDPOINT empty.
# Remote LXD: set endpoint=https://NODE:8443 and provide the client certificate/key.
LXD_ENDPOINT = os.getenv("LXD_ENDPOINT", "").strip()
LXD_CERT = os.getenv("LXD_CERT", "").strip()
LXD_KEY = os.getenv("LXD_KEY", "").strip()
LXD_VERIFY = os.getenv("LXD_VERIFY", "").strip()
LXD_PROJECT = os.getenv("LXD_PROJECT", "default").strip() or "default"

DB = BASE / "vps.db"
LOG = BASE / "bot.log"

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    handlers=[logging.FileHandler(LOG), logging.StreamHandler()],
)
logger = logging.getLogger("snck")

if not TOKEN:
    raise RuntimeError("DISCORD_TOKEN is missing from .env")
if not ADMIN_ID.isdigit():
    raise RuntimeError("MAIN_ADMIN_ID must be numeric")
if LXD_ENDPOINT and not (LXD_CERT and LXD_KEY):
    raise RuntimeError("Remote LXD requires LXD_CERT and LXD_KEY.")

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
        c.execute(
            """CREATE TABLE IF NOT EXISTS vps(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                owner TEXT NOT NULL,
                name TEXT UNIQUE NOT NULL,
                os TEXT NOT NULL,
                ram INTEGER NOT NULL,
                cpu INTEGER NOT NULL,
                disk INTEGER NOT NULL,
                status TEXT NOT NULL DEFAULT 'STOPPED',
                ssh_port INTEGER,
                expires TEXT NOT NULL,
                created TEXT NOT NULL
            )"""
        )


def card(title, text, color=0x9B6DFF):
    e = discord.Embed(
        title=f"✦ {title}",
        description=text[:4096],
        color=color,
        timestamp=datetime.now(timezone.utc),
    )
    e.set_footer(text=f"Made by {DEVELOPER} • SNCK VPS v{VERSION}")
    return e


def is_admin(uid):
    return str(uid) == ADMIN_ID


def can_deploy(member):
    return is_admin(member.id) or DEPLOY_ROLE_ID == "0" or any(
        str(r.id) == DEPLOY_ROLE_ID for r in member.roles
    )


def lxd_client():
    if not LXD_ENDPOINT:
        return Client(project=LXD_PROJECT)

    verify = LXD_VERIFY if LXD_VERIFY else False
    return Client(
        endpoint=LXD_ENDPOINT,
        cert=(LXD_CERT, LXD_KEY),
        verify=verify,
        timeout=30,
        project=LXD_PROJECT,
    )


def lxd_ready():
    try:
        client = lxd_client()
        client.host_info()
        client.storage_pools.all()
        client.networks.all()
        client.profiles.get("default")
        return True
    except Exception as exc:
        logger.warning("LXD health check failed: %s", exc)
        return False


def lxd_status_text():
    try:
        client = lxd_client()
        info = client.host_info()
        version = info.get("environment", {}).get("server_version", "unknown")
        return f"READY • LXD {version} • project {LXD_PROJECT}"
    except Exception as exc:
        return f"NOT READY • {type(exc).__name__}: {exc}"


def safe_name(s):
    s = re.sub(r"[^a-z0-9-]+", "-", s.lower()).strip("-")
    return s[:22] or "user"


def count_vps(owner=None):
    with db() as c:
        if owner is None:
            return c.execute("SELECT COUNT(*) FROM vps").fetchone()[0]
        return c.execute(
            "SELECT COUNT(*) FROM vps WHERE owner=?", (str(owner),)
        ).fetchone()[0]


def next_port():
    with db() as c:
        used = {
            r[0]
            for r in c.execute(
                "SELECT ssh_port FROM vps WHERE ssh_port IS NOT NULL"
            )
        }
    for port in range(20000, 50000):
        if port not in used:
            return port
    raise RuntimeError("No free SSH proxy ports remain.")


def instance_for(name):
    try:
        return lxd_client().instances.get(name)
    except Exception:
        return None


def get_instance_ipv4(instance):
    try:
        state = instance.state()
        networks = state.get("network", {})
        for data in networks.values():
            for address in data.get("addresses", []):
                if address.get("family") == "inet" and address.get("scope") == "global":
                    return address.get("address")
    except Exception:
        pass
    return None


def configure_instance(instance, port):
    config = dict(instance.config)
    config["limits.memory"] = f"{RAM_GB}GiB"
    config["limits.cpu"] = str(CPU)

    if SSH_PUBLIC_KEY:
        config["cloud-init.user-data"] = "\n".join(
            [
                "#cloud-config",
                "users:",
                "  - name: root",
                "    lock_passwd: false",
                "    ssh_authorized_keys:",
                f"      - {SSH_PUBLIC_KEY}",
                "packages:",
                "  - openssh-server",
                "runcmd:",
                "  - [systemctl, enable, --now, ssh]",
            ]
        )

    devices = dict(instance.devices)
    root = dict(
        devices.get("root", {"type": "disk", "pool": "default", "path": "/"})
    )
    root["size"] = f"{DISK_GB}GiB"
    devices["root"] = root

    # LXD proxy forwards a public host TCP port to SSH inside the container.
    devices[f"ssh-{port}"] = {
        "type": "proxy",
        "listen": f"tcp:0.0.0.0:{port}",
        "connect": "tcp:127.0.0.1:22",
    }

    instance.config = config
    instance.devices = devices
    instance.save(wait=True)


def wait_for_instance(instance, timeout=90):
    deadline = datetime.now(timezone.utc) + timedelta(seconds=timeout)
    while datetime.now(timezone.utc) < deadline:
        try:
            state = instance.state()
            if state.get("status") == "Running":
                return get_instance_ipv4(instance)
        except Exception:
            pass
        import time
        time.sleep(2)
    raise RuntimeError("VPS started but did not become ready before the timeout.")


def create_instance(owner):
    if not lxd_ready():
        target = LXD_ENDPOINT or "the local LXD socket"
        raise RuntimeError(
            f"LXD is not reachable at {target}. "
            "Run the installer self-check on a real LXD host or configure a remote LXD endpoint."
        )
    if not SSH_PUBLIC_KEY:
        raise RuntimeError(
            "DEPLOY_SSH_PUBLIC_KEY is not configured. "
            "Add an SSH public key to the bot .env before using !deploy."
        )
    if count_vps(owner.id) >= VPS_LIMIT:
        raise RuntimeError(f"Your VPS limit is {VPS_LIMIT}.")
    if VPS_SLOTS and count_vps() >= VPS_SLOTS:
        raise RuntimeError("Global VPS slot limit reached.")

    client = lxd_client()
    name = f"{safe_name(owner.display_name)}-vps-{count_vps() + 1}"
    port = next_port()
    expires = (
        datetime.now(timezone.utc) + timedelta(days=EXPIRY_DAYS)
    ).isoformat()

    try:
        # Validate the default profile before creating anything.
        profile = client.profiles.get("default")
        if not profile.devices.get("root"):
            raise RuntimeError(
                "LXD default profile has no root disk. Initialize LXD with 'lxd init' first."
            )

        instance = client.instances.create(
            {
                "name": name,
                "type": "container",
                "profiles": ["default"],
                "source": {
                    "type": "image",
                    "alias": "24.04",
                    "protocol": "simplestreams",
                    "server": "https://cloud-images.ubuntu.com/releases",
                },
            },
            wait=True,
        )

        configure_instance(instance, port)
        instance.start(wait=True)
        ipv4 = wait_for_instance(instance)

        with db() as c:
            c.execute(
                """INSERT INTO vps(
                    owner,name,os,ram,cpu,disk,status,ssh_port,expires,created
                ) VALUES(?,?,?,?,?,?,?,?,?,?)""",
                (
                    str(owner.id),
                    name,
                    "Ubuntu 24.04",
                    RAM_GB,
                    CPU,
                    DISK_GB,
                    "RUNNING",
                    port,
                    expires,
                    datetime.now(timezone.utc).isoformat(),
                ),
            )

        return name, port, expires, ipv4
    except Exception:
        existing = instance_for(name)
        if existing:
            try:
                existing.delete(wait=True, force=True)
            except Exception:
                pass
        raise


@bot.event
async def on_ready():
    init_db()
    logger.info("Connected as %s | %s", bot.user, lxd_status_text())
    await bot.change_presence(
        activity=discord.Activity(
            type=discord.ActivityType.watching, name="SNCK VPS Hosting"
        )
    )


@bot.command()
async def ping(ctx):
    await ctx.send(
        embed=card(
            "Pong",
            f"Latency: `{round(bot.latency * 1000)}ms`\nLXD: **{lxd_status_text()}**",
            0x57F287,
        )
    )


@bot.command()
async def security(ctx):
    await ctx.send(
        embed=card(
            "Security",
            "Keep the bot token, LXD client key and SSH private key private. "
            "Use a dedicated LXD trust identity and restrict the LXD API with a firewall.",
            0x00C2FF,
        )
    )


@bot.command()
async def server(ctx):
    await ctx.send(
        embed=card(
            "Server",
            f"Guild: **{ctx.guild.name if ctx.guild else 'DM'}**\n"
            f"Members: **{ctx.guild.member_count if ctx.guild else 'N/A'}**\n"
            f"Host: `{HOST_IP}`\nLXD: **{lxd_status_text()}**",
        )
    )


@bot.command()
async def vps(ctx):
    with db() as c:
        rows = c.execute(
            "SELECT * FROM vps WHERE owner=? ORDER BY id", (str(ctx.author.id),)
        ).fetchall()

    if not rows:
        await ctx.send(embed=card("Your VPS", "No VPS found."))
        return

    lines = []
    for r in rows:
        instance = instance_for(r["name"])
        actual = "MISSING"
        ipv4 = None
        if instance:
            try:
                state = instance.state()
                actual = state.get("status", "UNKNOWN").upper()
                ipv4 = get_instance_ipv4(instance)
            except Exception:
                pass
        if actual != r["status"]:
            with db() as c:
                c.execute("UPDATE vps SET status=? WHERE name=?", (actual, r["name"]))

        ssh = f"ssh root@{HOST_IP} -p {r['ssh_port']}"
        lines.append(
            f"**#{r['id']} `{r['name']}`**\n"
            f"Status: **{actual}** • {r['os']} • {r['ram']}GB RAM • {r['cpu']} CPU • {r['disk']}GB disk\n"
            f"IPv4: `{ipv4 or 'pending'}`\n"
            f"SSH: `{ssh}`\n"
            f"Expires: `{r['expires'][:10]}`"
        )

    await ctx.send(embed=card("Your VPS", "\n\n".join(lines)))


@bot.command()
async def deploy(ctx):
    if not isinstance(ctx.author, discord.Member) or not can_deploy(ctx.author):
        await ctx.send(
            embed=card(
                "Access denied",
                "You do not have the VPS deployment role.",
                0xED4245,
            )
        )
        return

    message = await ctx.send(
        embed=card("Deploying", "Creating a real Ubuntu 24.04 LXD VPS...", 0xFEE75C)
    )
    try:
        name, port, expires, ipv4 = create_instance(ctx.author)
        text = (
            f"**Container:** `{name}`\n"
            f"**OS:** `Ubuntu 24.04`\n"
            f"**Resources:** `{RAM_GB}GB RAM / {CPU} CPU / {DISK_GB}GB disk`\n"
            f"**VPS IPv4:** `{ipv4 or 'not assigned yet'}`\n"
            f"**SSH:** `ssh root@{HOST_IP} -p {port}`\n"
            f"**Auth:** configured SSH public key\n"
            f"**Expires:** `{expires[:10]}`"
        )
        await message.edit(embed=card("VPS deployed", text, 0x57F287))
    except Exception as exc:
        logger.exception("deploy failed")
        await message.edit(
            embed=card("Deployment failed", str(exc)[:3500], 0xED4245)
        )


async def owned(ctx, name):
    with db() as c:
        row = c.execute("SELECT * FROM vps WHERE name=?", (name,)).fetchone()
    return row if row and (
        str(row["owner"]) == str(ctx.author.id) or is_admin(ctx.author.id)
    ) else None


@bot.command(name="vps-start")
async def vps_start(ctx, name):
    row = await owned(ctx, name)
    if not row:
        await ctx.send(embed=card("Not found", "VPS not found or not owned.", 0xED4245))
        return
    try:
        instance = instance_for(name)
        if not instance:
            raise RuntimeError("LXD instance not found.")
        instance.start(wait=True)
        with db() as c:
            c.execute("UPDATE vps SET status='RUNNING' WHERE name=?", (name,))
        await ctx.send(embed=card("VPS started", f"`{name}` is running.", 0x57F287))
    except Exception as exc:
        await ctx.send(embed=card("Start failed", str(exc), 0xED4245))


@bot.command(name="vps-stop")
async def vps_stop(ctx, name):
    row = await owned(ctx, name)
    if not row:
        await ctx.send(embed=card("Not found", "VPS not found or not owned.", 0xED4245))
        return
    try:
        instance = instance_for(name)
        if not instance:
            raise RuntimeError("LXD instance not found.")
        instance.stop(wait=True, force=True)
        with db() as c:
            c.execute("UPDATE vps SET status='STOPPED' WHERE name=?", (name,))
        await ctx.send(embed=card("VPS stopped", f"`{name}` is stopped.", 0xFEE75C))
    except Exception as exc:
        await ctx.send(embed=card("Stop failed", str(exc), 0xED4245))


@bot.command(name="vps-restart")
async def vps_restart(ctx, name):
    row = await owned(ctx, name)
    if not row:
        await ctx.send(embed=card("Not found", "VPS not found or not owned.", 0xED4245))
        return
    try:
        instance = instance_for(name)
        if not instance:
            raise RuntimeError("LXD instance not found.")
        instance.restart(wait=True)
        with db() as c:
            c.execute("UPDATE vps SET status='RUNNING' WHERE name=?", (name,))
        await ctx.send(embed=card("VPS restarted", f"`{name}` restarted.", 0x57F287))
    except Exception as exc:
        await ctx.send(embed=card("Restart failed", str(exc), 0xED4245))


@bot.command(name="vps-ip")
async def vps_ip(ctx, name):
    row = await owned(ctx, name)
    if not row:
        await ctx.send(embed=card("Not found", "VPS not found or not owned.", 0xED4245))
        return
    instance = instance_for(name)
    if not instance:
        await ctx.send(embed=card("Not found", "LXD instance is missing.", 0xED4245))
        return
    ip = get_instance_ipv4(instance)
    await ctx.send(
        embed=card(
            "VPS Network",
            f"Container: `{name}`\nIPv4: `{ip or 'not assigned'}`\n"
            f"SSH: `ssh root@{HOST_IP} -p {row['ssh_port']}`",
        )
    )


@bot.command(name="vps-delete")
async def vps_delete(ctx, name):
    row = await owned(ctx, name)
    if not row or not is_admin(ctx.author.id):
        await ctx.send(
            embed=card(
                "Access denied",
                "Only the main admin can permanently delete VPS instances.",
                0xED4245,
            )
        )
        return

    try:
        instance = instance_for(name)
        if instance:
            instance.delete(wait=True, force=True)
        with db() as c:
            c.execute("DELETE FROM vps WHERE name=?", (name,))
        await ctx.send(embed=card("VPS deleted", f"`{name}` was deleted.", 0x57F287))
    except Exception as exc:
        await ctx.send(embed=card("Delete failed", str(exc), 0xED4245))


@bot.command()
@commands.has_permissions(manage_messages=True)
async def clear(ctx, amount: int = 10):
    amount = max(1, min(amount, 100))
    deleted = await ctx.channel.purge(limit=amount + 1)
    await ctx.send(
        embed=card(
            "Messages cleared",
            f"Deleted **{max(0, len(deleted) - 1)}** messages.",
            0x57F287,
        ),
        delete_after=4,
    )


@bot.command()
@commands.has_permissions(kick_members=True)
async def kick(ctx, member: discord.Member, *, reason="No reason provided"):
    if member.top_role >= ctx.author.top_role or member == ctx.guild.owner:
        await ctx.send(embed=card("Kick blocked", "Discord role hierarchy prevents this action.", 0xED4245))
        return
    await member.kick(reason=reason)
    await ctx.send(embed=card("Member kicked", f"{member.mention}\nReason: {reason}", 0x57F287))


@bot.command()
@commands.has_permissions(ban_members=True)
async def ban(ctx, member: discord.Member, *, reason="No reason provided"):
    if member.top_role >= ctx.author.top_role or member == ctx.guild.owner:
        await ctx.send(embed=card("Ban blocked", "Discord role hierarchy prevents this action.", 0xED4245))
        return
    await member.ban(reason=reason)
    await ctx.send(embed=card("Member banned", f"{member.mention}\nReason: {reason}", 0xED4245))


@bot.command()
@commands.has_permissions(moderate_members=True)
async def timeout(ctx, member: discord.Member, minutes: int = 10, *, reason="No reason provided"):
    minutes = max(1, min(minutes, 40320))
    if member.top_role >= ctx.author.top_role or member == ctx.guild.owner:
        await ctx.send(embed=card("Timeout blocked", "Discord role hierarchy prevents this action.", 0xED4245))
        return
    await member.timeout(timedelta(minutes=minutes), reason=reason)
    await ctx.send(embed=card("Member timed out", f"{member.mention}\nDuration: **{minutes} minutes**\nReason: {reason}", 0xFEE75C))


@bot.command(name="lock")
@commands.has_permissions(manage_channels=True)
async def lock_channel(ctx):
    await ctx.channel.set_permissions(ctx.guild.default_role, send_messages=False)
    await ctx.send(embed=card("Channel locked", ctx.channel.mention, 0xFEE75C))


@bot.command(name="unlock")
@commands.has_permissions(manage_channels=True)
async def unlock_channel(ctx):
    await ctx.channel.set_permissions(ctx.guild.default_role, send_messages=None)
    await ctx.send(embed=card("Channel unlocked", ctx.channel.mention, 0x57F287))


@bot.command()
async def help(ctx):
    await ctx.send(
        embed=card(
            "SNCK Help",
            f"**VPS**\n"
            f"`{PREFIX}deploy` — create VPS\n"
            f"`{PREFIX}vps` — list your VPS\n"
            f"`{PREFIX}vps-ip <name>` — show network\n"
            f"`{PREFIX}vps-start <name>`\n"
            f"`{PREFIX}vps-stop <name>`\n"
            f"`{PREFIX}vps-restart <name>`\n"
            f"`{PREFIX}vps-delete <name>` — admin only\n\n"
            f"**Moderation**\n"
            f"`{PREFIX}clear` `{PREFIX}kick` `{PREFIX}ban` `{PREFIX}timeout`\n"
            f"`{PREFIX}lock` `{PREFIX}unlock`\n\n"
            f"**Info**\n"
            f"`{PREFIX}ping` `{PREFIX}security` `{PREFIX}server`",
        )
    )


@bot.event
async def on_command_error(ctx, error):
    if isinstance(error, commands.CommandNotFound):
        return
    if isinstance(error, commands.MissingPermissions):
        await ctx.send(embed=card("Permission denied", "You do not have the required Discord permission.", 0xED4245))
        return
    if isinstance(error, (commands.MissingRequiredArgument, commands.BadArgument)):
        await ctx.send(embed=card("Invalid command", f"Use `{PREFIX}help` for usage.", 0xFEE75C))
        return
    logger.exception("command error", exc_info=error)
    await ctx.send(embed=card("Command error", str(error)[:1200], 0xED4245))


init_db()
bot.run(TOKEN)
