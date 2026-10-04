import os,re,sqlite3,secrets,string,subprocess,logging,asyncio
from datetime import datetime,timedelta
from pathlib import Path
import discord
from discord.ext import commands
from dotenv import load_dotenv
load_dotenv()
TOKEN=os.getenv('DISCORD_TOKEN',''); BOT_NAME=os.getenv('BOT_NAME','CJH VPS'); PREFIX=os.getenv('PREFIX','!')
HOST_IP=os.getenv('YOUR_SERVER_IP','127.0.0.1'); ADMIN_ID=int(os.getenv('MAIN_ADMIN_ID','0') or 0)
DEPLOY_ROLE_ID=int(os.getenv('DEPLOY_ROLE_ID','0') or 0); RAM_DEFAULT=int(os.getenv('DEPLOY_RAM','16') or 16)
CPU_DEFAULT=int(os.getenv('DEPLOY_CPU','3') or 3); DISK_DEFAULT=int(os.getenv('DEPLOY_DISK','80') or 80)
EXPIRY_DEFAULT=int(os.getenv('DEFAULT_VPS_EXPIRATION_DAYS','30') or 30); STORAGE=os.getenv('DEFAULT_STORAGE_POOL','default')
FOOTER='Made by root_dora'; DB=Path('cjh-vps.db')
logging.basicConfig(level=logging.INFO,format='%(asctime)s %(levelname)s %(message)s'); log=logging.getLogger('cjh')
OS={'ubuntu24':'ubuntu:24.04','ubuntu22':'ubuntu:22.04','debian13':'images:debian/13','debian12':'images:debian/12'}

def db():
 c=sqlite3.connect(DB); c.row_factory=sqlite3.Row; return c
def init_db():
 c=db(); c.execute('CREATE TABLE IF NOT EXISTS vps(id INTEGER PRIMARY KEY AUTOINCREMENT,owner TEXT,container TEXT UNIQUE,ram INTEGER,cpu INTEGER,disk INTEGER,os TEXT,status TEXT,password TEXT,ssh_port INTEGER,created TEXT,expires TEXT)'); c.commit(); c.close()
def run(*a,timeout=120,check=True):
 p=subprocess.run(list(a),capture_output=True,text=True,timeout=timeout)
 if check and p.returncode: raise RuntimeError((p.stderr or p.stdout).strip() or 'command failed')
 return p.stdout.strip()
def lxc(*a,**kw): return run('lxc',*a,**kw)
def embed(t,d='',c=0x8b5cf6):
 e=discord.Embed(title=t,description=d,color=c,timestamp=datetime.now()); e.set_footer(text=FOOTER); return e
def ok(t,d=''): return embed('✅ '+t,d,0x22c55e)
def err(t,d=''): return embed('❌ '+t,d,0xef4444)
def info(t,d=''): return embed('◆ '+t,d,0x8b5cf6)
def admin(uid): return uid==ADMIN_ID
def slug(s): return re.sub(r'[^a-z0-9-]+','-',s.lower()).strip('-')[:24] or 'user'
def pwd(): return ''.join(secrets.choice(string.ascii_letters+string.digits+'!@#$%') for _ in range(20))
def getv(x):
 c=db(); r=c.execute('SELECT * FROM vps WHERE id=? OR container=?',(x,x)).fetchone(); c.close(); return r
def mine(uid):
 c=db(); r=c.execute('SELECT * FROM vps WHERE owner=? ORDER BY id',(str(uid),)).fetchall(); c.close(); return r
def own(ctx,r): return admin(ctx.author.id) or str(r['owner'])==str(ctx.author.id)
def port():
 c=db(); used={x[0] for x in c.execute('SELECT ssh_port FROM vps WHERE ssh_port IS NOT NULL')}; c.close()
 for p in range(2200,65000):
  if p not in used:return p
 raise RuntimeError('No host ports available')
def configure(n,p):
 import base64
 cfg='Port 22\nAddressFamily any\nListenAddress 0.0.0.0\nPasswordAuthentication yes\nPubkeyAuthentication yes\nPermitRootLogin yes\nPermitEmptyPasswords no\nUsePAM yes\nSubsystem sftp /usr/lib/openssh/sftp-server\n'
 b=base64.b64encode(cfg.encode()).decode(); lxc('exec',n,'--','bash','-lc',f'echo {b} | base64 -d > /etc/ssh/sshd_config'); lxc('exec',n,'--','bash','-lc',f"echo 'root:{p}' | chpasswd"); lxc('exec',n,'--','bash','-lc','systemctl restart ssh 2>/dev/null || service ssh restart 2>/dev/null || true',check=False)
def deploy(owner,display,ram,cpu,disk,key):
 image=OS.get(key)
 if not image: raise RuntimeError('Invalid OS')
 c=db(); nid=c.execute('SELECT COALESCE(MAX(id),0)+1 FROM vps').fetchone()[0]; c.close(); name=f'{slug(display)}-vps-{nid}'; secret=pwd(); hp=port(); exp=datetime.now()+timedelta(days=EXPIRY_DEFAULT)
 lxc('init',image,name,'-s',STORAGE,'-c','security.privileged=true'); lxc('config','set',name,'limits.memory',f'{ram}GB'); lxc('config','set',name,'limits.cpu',str(cpu)); lxc('config','device','set',name,'root',f'size={disk}GB'); lxc('config','set',name,'security.nesting','true',check=False); lxc('start',name)
 lxc('exec',name,'--','bash','-lc','command -v sshd >/dev/null || (apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq openssh-server)',timeout=180,check=False); configure(name,secret)
 lxc('config','device','add',name,'sshproxy','proxy',f'listen=tcp:0.0.0.0:{hp}','connect=tcp:127.0.0.1:22',check=False)
 c=db(); c.execute('INSERT INTO vps(owner,container,ram,cpu,disk,os,status,password,ssh_port,created,expires) VALUES(?,?,?,?,?,?,?,?,?,?,?)',(str(owner),name,ram,cpu,disk,image,'running',secret,hp,datetime.now().isoformat(),exp.isoformat())); c.commit(); c.close(); return getv(name)
intents=discord.Intents.default(); intents.message_content=True; intents.members=True; bot=commands.Bot(command_prefix=PREFIX,intents=intents,help_command=None)
class OSView(discord.ui.View):
 def __init__(self,ctx,ram,cpu,disk):
  super().__init__(timeout=180); self.ctx=ctx; self.ram=ram; self.cpu=cpu; self.disk=disk
  for k,label in OS.items():
   b=discord.ui.Button(label=label,style=discord.ButtonStyle.primary); b.callback=self.cb(k); self.add_item(b)
 def cb(self,k):
  async def f(i):
   if i.user.id!=self.ctx.author.id and not admin(i.user.id): return await i.response.send_message(embed=err('Access denied'),ephemeral=True)
   await i.response.edit_message(embed=info('🚀 Creating VPS','Provisioning a real LXC VPS. Please wait...'),view=None)
   try:
    r=await asyncio.to_thread(deploy,i.user.id,self.ctx.author.display_name,self.ram,self.cpu,self.disk,k)
    e=ok('VPS created',f'VPS **#{r["id"]}** is running.'); e.add_field(name='SSH',value=f'`ssh root@{HOST_IP} -p {r["ssh_port"]}`',inline=False); e.add_field(name='Credentials',value=f'User: `root`\nPassword: `{r["password"]}`',inline=False); e.add_field(name='Resources',value=f'{r["ram"]}GB RAM • {r["cpu"]} CPU • {r["disk"]}GB disk'); await i.followup.send(embed=e,ephemeral=True)
    try: await i.user.send(embed=e)
    except discord.Forbidden: pass
   except Exception as ex: await i.followup.send(embed=err('VPS creation failed',str(ex)),ephemeral=True)
   self.stop()
  return f
@bot.event
async def on_ready(): init_db(); log.info('%s online as %s',BOT_NAME,bot.user); await bot.change_presence(activity=discord.Game(name=f'{PREFIX}help • VPS Hosting'))
@bot.command(name='help')
async def help_cmd(ctx): await ctx.send(embed=info('CJH VPS Control','**Create:** `!create <ram> <cpu> <disk>` or `!deploy`\n**VPS:** `!myvps` `!vps-info <id>` `!vps-password <id>` `!vps-stats <id>`\n**Power:** `!start-vps <id>` `!stop-vps <id>` `!restart-vps <id>`\n**Admin:** `!vps-list` `!delete-vps <id>` `!status`\n\nAll actions are real LXC operations.\n\n**Made by root_dora**'))
@bot.command()
async def ping(ctx): await ctx.send(embed=ok('Pong',f'{round(bot.latency*1000)}ms'))
@bot.command(name='create')
async def create(ctx,ram:int,cpu:int,disk:int):
 if not admin(ctx.author.id): return await ctx.send(embed=err('Access denied','Only the main administrator can create VPS for a user.'))
 if min(ram,cpu,disk)<=0 or ram>1024 or cpu>64 or disk>4096:return await ctx.send(embed=err('Invalid resources'))
 await ctx.send(embed=info('Choose OS',f'**{ram}GB RAM** • **{cpu} CPU** • **{disk}GB disk**'),view=OSView(ctx,ram,cpu,disk))
@bot.command(name='deploy')
async def deploy_cmd(ctx):
 role_ok=admin(ctx.author.id) or (DEPLOY_ROLE_ID and any(r.id==DEPLOY_ROLE_ID for r in getattr(ctx.author,'roles',[])))
 if not role_ok:return await ctx.send(embed=err('Access denied','You do not have the VPS deploy role.'))
 if len(mine(ctx.author.id))>=int(os.getenv('VPS_DEPLOY_LIMIT','2')):return await ctx.send(embed=err('VPS limit reached'))
 await ctx.send(embed=info('🚀 Self-service VPS',f'**{RAM_DEFAULT}GB RAM** • **{CPU_DEFAULT} CPU** • **{DISK_DEFAULT}GB disk**'),view=OSView(ctx,RAM_DEFAULT,CPU_DEFAULT,DISK_DEFAULT))
@bot.command(name='myvps')
async def myvps(ctx):
 r=mine(ctx.author.id); await ctx.send(embed=info('Your VPS','\n'.join(f'**#{x["id"]}** `{x["container"]}` • {x["status"]} • SSH `:{x["ssh_port"]}`' for x in r) if r else 'No VPS yet.'))
@bot.command(name='vps-list')
async def vpslist(ctx):
 if not admin(ctx.author.id):return await ctx.send(embed=err('Access denied'))
 c=db(); r=c.execute('SELECT * FROM vps ORDER BY id').fetchall(); c.close(); await ctx.send(embed=info('VPS inventory','\n'.join(f'**#{x["id"]}** `{x["container"]}` • <@{x["owner"]}> • {x["status"]}' for x in r) if r else 'No VPS.'))
@bot.command(name='vps-info')
async def vpsinfo(ctx,x:str):
 r=getv(x)
 if not r or not own(ctx,r):return await ctx.send(embed=err('Not found or access denied'))
 await ctx.send(embed=info(f'VPS #{r["id"]}',f'Container: `{r["container"]}`\nOS: `{r["os"]}`\nStatus: **{r["status"]}**\nResources: **{r["ram"]}GB / {r["cpu"]} CPU / {r["disk"]}GB**\nSSH: `ssh root@{HOST_IP} -p {r["ssh_port"]}`\nExpires: <t:{int(datetime.fromisoformat(r["expires"]).timestamp())}:R>'))
async def power(ctx,x,action):
 r=getv(x)
 if not r or not own(ctx,r):return await ctx.send(embed=err('Not found or access denied'))
 await asyncio.to_thread(lxc,action,r['container']); c=db(); c.execute('UPDATE vps SET status=? WHERE id=?',('running' if action!='stop' else 'stopped',r['id'])); c.commit(); c.close(); await ctx.send(embed=ok('VPS '+action,f'`{r["container"]}`'))
@bot.command(name='start-vps')
async def start(ctx,x): await power(ctx,x,'start')
@bot.command(name='stop-vps')
async def stop(ctx,x): await power(ctx,x,'stop')
@bot.command(name='restart-vps')
async def restart(ctx,x): await power(ctx,x,'restart')
@bot.command(name='delete-vps')
async def delete(ctx,x):
 r=getv(x)
 if not r or not admin(ctx.author.id):return await ctx.send(embed=err('Access denied'))
 await asyncio.to_thread(lxc,'stop',r['container'],check=False); await asyncio.to_thread(lxc,'delete',r['container'],check=False); c=db(); c.execute('DELETE FROM vps WHERE id=?',(r['id'],)); c.commit(); c.close(); await ctx.send(embed=ok('VPS deleted',f'`{r["container"]}`'))
@bot.command(name='vps-password')
async def vpspass(ctx,x):
 r=getv(x)
 if not r or not own(ctx,r):return await ctx.send(embed=err('Access denied'))
 await ctx.author.send(embed=info('🔐 VPS credentials',f'User: `root`\nPassword: `{r["password"]}`\nSSH: `ssh root@{HOST_IP} -p {r["ssh_port"]}`')); await ctx.send(embed=ok('Credentials sent','Check your DMs.'),delete_after=8)
@bot.command(name='vps-stats')
async def stats(ctx,x):
 r=getv(x)
 if not r or not own(ctx,r):return await ctx.send(embed=err('Access denied'))
 out=await asyncio.to_thread(lxc,'info',r['container'],check=False); await ctx.send(embed=info('VPS runtime',f'```text\n{out[-3500:]}\n```'))
@bot.command(name='status')
async def status(ctx):
 if not admin(ctx.author.id):return await ctx.send(embed=err('Access denied'))
 c=db(); n=c.execute('SELECT COUNT(*) FROM vps').fetchone()[0]; c.close(); await ctx.send(embed=info('CJH host',f'Bot: online\nLXC: available\nVPS records: **{n}**\nHost: `{HOST_IP}`\nStorage: `{STORAGE}`'))
@bot.event
async def on_command_error(ctx,e):
 if isinstance(e,commands.CommandNotFound):return
 log.error('command error: %s',e); await ctx.send(embed=err('Command failed',f'`{type(e).__name__}`: {str(e)[:700]}'))
if __name__=='__main__':
 if not TOKEN: raise SystemExit('DISCORD_TOKEN is missing')
 init_db(); bot.run(TOKEN)
