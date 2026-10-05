import logging
import os
from pathlib import Path

import discord
from discord.ext import commands
from dotenv import load_dotenv

BASE = Path(__file__).resolve().parent
load_dotenv(BASE / ".env")
TOKEN = os.getenv("DISCORD_TOKEN", "").strip()
PREFIX = os.getenv("PREFIX", "!")
BOT_NAME = os.getenv("BOT_NAME", "SNCK VPS")
VERSION = os.getenv("BOT_VERSION", "9.0.0")
DEVELOPER = os.getenv("BOT_DEVELOPER", "root_dora")

if not TOKEN:
    raise RuntimeError("DISCORD_TOKEN is missing from .env")

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
intents = discord.Intents.default()
intents.message_content = True
intents.members = True
bot = commands.Bot(command_prefix=PREFIX, intents=intents, help_command=None)


def card(title, text, color=0x9B6DFF):
    e = discord.Embed(title=f"✦ {title}", description=text[:4096], color=color)
    e.set_footer(text=f"Made by {DEVELOPER} • {BOT_NAME} v{VERSION}")
    return e


@bot.event
async def on_ready():
    logging.info("Connected as %s", bot.user)
    await bot.change_presence(activity=discord.Activity(type=discord.ActivityType.watching, name="SNCK VPS Hosting"))


@bot.command()
async def ping(ctx):
    await ctx.send(embed=card("Pong", f"Latency: `{round(bot.latency * 1000)}ms`", 0x57F287))


@bot.command()
async def server(ctx):
    guild = ctx.guild
    await ctx.send(embed=card("Server", f"Guild: **{guild.name if guild else 'DM'}**\nMembers: **{guild.member_count if guild else 'N/A'}**"))


@bot.command()
async def security(ctx):
    await ctx.send(embed=card("Security", "Keep the bot token private, use least-privilege Discord permissions, and keep the host updated.", 0x00C2FF))


@bot.command()
@commands.has_permissions(manage_messages=True)
async def clear(ctx, amount: int = 10):
    amount = max(1, min(amount, 100))
    deleted = await ctx.channel.purge(limit=amount + 1)
    await ctx.send(embed=card("Messages cleared", f"Deleted **{max(0, len(deleted) - 1)}** messages.", 0x57F287), delete_after=4)


@bot.command()
@commands.has_permissions(kick_members=True)
async def kick(ctx, member: discord.Member, *, reason="No reason provided"):
    if member.top_role >= ctx.author.top_role or member == ctx.guild.owner:
        await ctx.send(embed=card("Kick blocked", "Discord role hierarchy prevents this action.", 0xED4245)); return
    await member.kick(reason=reason)
    await ctx.send(embed=card("Member kicked", f"{member.mention}\nReason: {reason}", 0x57F287))


@bot.command()
@commands.has_permissions(ban_members=True)
async def ban(ctx, member: discord.Member, *, reason="No reason provided"):
    if member.top_role >= ctx.author.top_role or member == ctx.guild.owner:
        await ctx.send(embed=card("Ban blocked", "Discord role hierarchy prevents this action.", 0xED4245)); return
    await member.ban(reason=reason)
    await ctx.send(embed=card("Member banned", f"{member.mention}\nReason: {reason}", 0xED4245))


@bot.command()
@commands.has_permissions(moderate_members=True)
async def timeout(ctx, member: discord.Member, minutes: int = 10, *, reason="No reason provided"):
    from datetime import timedelta
    minutes = max(1, min(minutes, 40320))
    if member.top_role >= ctx.author.top_role or member == ctx.guild.owner:
        await ctx.send(embed=card("Timeout blocked", "Discord role hierarchy prevents this action.", 0xED4245)); return
    await member.timeout(timedelta(minutes=minutes), reason=reason)
    await ctx.send(embed=card("Member timed out", f"{member.mention}\nDuration: **{minutes} minutes**\nReason: {reason}", 0xFEE75C))


@bot.command()
@commands.has_permissions(manage_channels=True)
async def lock(ctx):
    await ctx.channel.set_permissions(ctx.guild.default_role, send_messages=False)
    await ctx.send(embed=card("Channel locked", ctx.channel.mention, 0xFEE75C))


@bot.command()
@commands.has_permissions(manage_channels=True)
async def unlock(ctx):
    await ctx.channel.set_permissions(ctx.guild.default_role, send_messages=None)
    await ctx.send(embed=card("Channel unlocked", ctx.channel.mention, 0x57F287))


@bot.command()
async def help(ctx):
    await ctx.send(embed=card("SNCK Help", f"**Info:** `{PREFIX}ping`, `{PREFIX}server`, `{PREFIX}security`\n**Moderation:** `{PREFIX}clear`, `{PREFIX}kick`, `{PREFIX}ban`, `{PREFIX}timeout`, `{PREFIX}lock`, `{PREFIX}unlock`"))


@bot.event
async def on_command_error(ctx, error):
    if isinstance(error, commands.CommandNotFound): return
    if isinstance(error, commands.MissingPermissions):
        await ctx.send(embed=card("Permission denied", "You do not have the required Discord permission.", 0xED4245)); return
    await ctx.send(embed=card("Command error", str(error)[:1200], 0xED4245))


bot.run(TOKEN)
