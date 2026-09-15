#!/usr/bin/env python3
"""Controlled finite module audit; restores the production shell in finally.
No screenshots, Quickshell IPC, dependency installation, or source modifications.
Only the snapshot's shell.qml is replaced. Run in the user's Wayland session.
"""
import ctypes as C
import datetime, hashlib, json, os, re, signal, statistics, subprocess, sys, time
from pathlib import Path
import proc_reader as proc
BASE=Path(__file__).resolve().parent
SRC=Path('/home/pedro/Downloads/ii-vynx/dots/.config/quickshell/ii')
HOME_PATH=Path('/home/pedro')
RUNTIME=Path(os.environ.get('XDG_RUNTIME_DIR','/run/user/1000'))
RESULTS=BASE/'results';RESULTS.mkdir(exist_ok=True)
class ProcInfo(C.Structure):
 _fields_=[('pid',C.c_uint),('usedGpuMemory',C.c_ulonglong),('gpuInstanceId',C.c_uint),('computeInstanceId',C.c_uint)]
class Util(C.Structure):
 _fields_=[('pid',C.c_uint),('timeStamp',C.c_ulonglong),('smUtil',C.c_uint),('memUtil',C.c_uint),('encUtil',C.c_uint),('decUtil',C.c_uint)]
class Rates(C.Structure):_fields_=[('gpu',C.c_uint),('memory',C.c_uint)]
class Nvml:
 def __init__(self):
  self.lib=C.CDLL('libnvidia-ml.so.1');assert self.lib.nvmlInit_v2()==0
  self.dev=C.c_void_p();assert self.lib.nvmlDeviceGetHandleByIndex_v2(0,C.byref(self.dev))==0
  self.timestamp=0
 def read(self,pids):
  a=(ProcInfo*256)();n=C.c_uint(256)
  r=self.lib.nvmlDeviceGetGraphicsRunningProcesses_v3(self.dev,C.byref(n),a)
  mem={str(p.pid):p.usedGpuMemory/1048576 for p in a[:n.value] if p.pid in pids and p.usedGpuMemory<2**63} if r==0 else {}
  u=(Util*1024)();count=C.c_uint(1024)
  ur=self.lib.nvmlDeviceGetProcessUtilization(self.dev,u,C.byref(count),C.c_ulonglong(self.timestamp))
  raw=[]
  if ur==0:
   for v in u[:count.value]:
    self.timestamp=max(self.timestamp,v.timeStamp)
    if v.pid in pids:raw.append({k:getattr(v,k) for k,_ in Util._fields_})
  rates=Rates();gr=self.lib.nvmlDeviceGetUtilizationRates(self.dev,C.byref(rates))
  return {'memoryMiB':mem,'memoryStatus':r,'utilStatus':ur,'utilSamples':raw,'globalGpuPercent':rates.gpu if gr==0 else None}
CASES=[
 {'id':'dashboard_keep','path':'modules/ii/sidebarDashboard/SidebarDashboard.qml','kind':'dashboard','keep':True},
 {'id':'dashboard_unload','path':'modules/ii/sidebarDashboard/SidebarDashboard.qml','kind':'dashboard','keep':False},
 {'id':'policies_ai_keep','path':'modules/ii/sidebarPolicies/SidebarPolicies.qml','kind':'policies','keep':True,'tab':0},
 {'id':'policies_ai_unload','path':'modules/ii/sidebarPolicies/SidebarPolicies.qml','kind':'policies','keep':False,'tab':0},
 {'id':'policies_phone','path':'modules/ii/sidebarPolicies/SidebarPolicies.qml','kind':'policies','keep':False,'tab':2},
 {'id':'cheatsheet_keybinds_keep','path':'modules/ii/cheatsheet/Cheatsheet.qml','kind':'cheatsheet','keep':True,'tab':'keybinds'},
 {'id':'cheatsheet_keybinds_unload','path':'modules/ii/cheatsheet/Cheatsheet.qml','kind':'cheatsheet','keep':False,'tab':'keybinds'},
 {'id':'cheatsheet_timetable','path':'modules/ii/cheatsheet/Cheatsheet.qml','kind':'cheatsheet','keep':False,'tab':'timetable'},
 {'id':'cheatsheet_commands','path':'modules/ii/cheatsheet/Cheatsheet.qml','kind':'cheatsheet','keep':False,'tab':'commands'},
 {'id':'overview','path':'modules/ii/overview/Overview.qml','kind':'overview'},
 {'id':'settings_colors','path':'SettingsWindow.qml','kind':'settings','tab':'colors'},
 {'id':'settings_bar','path':'SettingsWindow.qml','kind':'settings','tab':'bar'},
 {'id':'usage','path':'modules/ii/usage/Usage.qml','kind':'usage'},
 {'id':'notes','path':'modules/ii/notes/NotesApp.qml','kind':'notes'},
 {'id':'wallpaper_selector','path':'modules/ii/wallpaperSelector/WallpaperSelector.qml','kind':'wallpaper'},
 {'id':'background','path':'modules/ii/background/Background.qml','kind':'resident'},
 {'id':'vertical_bar','path':'modules/ii/verticalBar/VerticalBar.qml','kind':'bar'},
 {'id':'dock','path':'modules/ii/dock/Dock.qml','kind':'resident'},
 {'id':'media_mode','path':'modules/ii/background/Background.qml','kind':'media'},
]
DRIVER=r'''//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000
//@ pragma Env QSG_NO_DEPTH_BUFFER=1
import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
__IMPORT__
ShellRoot {
 id: root
 property var test: __CASE__
 property var stages: __STAGES__
 property int index: -1
 property bool booted: false
 property string phase: "boot"
 Loader { id: target; asynchronous: false }
 function mark(extra) {
  console.warn("IIAUDIT " + JSON.stringify({time:Date.now(),phase:phase,status:target.status,
   item:!!target.item,active:target.item && target.item.activeState !== undefined ? target.item.activeState : null,
   contentWanted:target.item && target.item.contentWanted !== undefined ? target.item.contentWanted : null,
   tab:target.item && target.item.tabIndex !== undefined ? target.item.tabIndex : null,
   currentPage:target.item && target.item.currentPage !== undefined ? target.item.currentPage : null,
   left:GlobalStates.sidebarLeftOpen,right:GlobalStates.sidebarRightOpen,
   cheatsheet:GlobalStates.cheatsheetOpen,settings:GlobalStates.settingsOpen,
   overview:GlobalStates.overviewOpen,notes:GlobalStates.notesAppOpen,
   wallpaper:GlobalStates.wallpaperSelectorOpen,usage:GlobalStates.usageOpen,
   media:GlobalStates.mediaModeActive,extra:extra || ""}));
 }
 function load() { target.source = Qt.resolvedUrl(test.path); }
 function open() {
  if (!target.item) load();
  if (test.kind === "dashboard") GlobalStates.openRightSidebar("eDP-1");
  else if (test.kind === "policies") GlobalStates.openLeftSidebar("eDP-1");
  else if (test.kind === "cheatsheet") GlobalStates.openCheatsheet(test.tab);
  else if (test.kind === "settings") GlobalStates.openSettingsPage(test.tab, "", "");
  else if (test.kind === "overview") GlobalStates.overviewOpen=true;
  else if (test.kind === "usage") GlobalStates.usageOpen=true;
  else if (test.kind === "notes") GlobalStates.openNotes();
  else if (test.kind === "wallpaper") GlobalStates.wallpaperSelectorOpen=true;
  else if (test.kind === "bar") GlobalStates.barOpen=true;
  else if (test.kind === "media") GlobalStates.requestMediaMode("open");
 }
 function close() {
  if (test.kind === "dashboard") GlobalStates.sidebarRightOpen=false;
  else if (test.kind === "policies") GlobalStates.sidebarLeftOpen=false;
  else if (test.kind === "cheatsheet") GlobalStates.closeCheatsheet();
  else if (test.kind === "settings") { GlobalStates.settingsOpen=false; settingsUnload.restart(); }
  else if (test.kind === "overview") GlobalStates.overviewOpen=false;
  else if (test.kind === "usage") GlobalStates.usageOpen=false;
  else if (test.kind === "notes") GlobalStates.notesAppOpen=false;
  else if (test.kind === "wallpaper") GlobalStates.wallpaperSelectorOpen=false;
  else if (test.kind === "bar") GlobalStates.barOpen=false;
  else if (test.kind === "media") GlobalStates.requestMediaMode("close");
  else target.source="";
 }
 function next() {
  index++;
  if (index >= stages.length) {phase="done";mark();return;}
  phase=stages[index].phase;
  if (phase === "controller") {
   if (test.kind !== "settings" && test.kind !== "resident") load();
  } else if (phase === "open" || phase === "reopen") open();
  else if (phase === "closed" || phase === "closed_again") close();
  else if (phase === "unloaded") target.source="";
  mark("transition"); settle.restart();
  step.interval=stages[index].seconds*1000; step.restart();
 }
 Timer {id:step;onTriggered:root.next()}
 Timer {id:settle;interval:3000;onTriggered:root.mark("settled")}
 Timer {id:heartbeat;interval:5000;running:root.booted;repeat:true;onTriggered:root.mark("heartbeat")}
 Timer {id:settingsUnload;interval:5000;onTriggered:{SearchRegistry.clearIndex();ThemePreviewCache.release();WallpaperPreviewCache.release();target.source="";}}
 Timer {
  interval:200;running:!root.booted;repeat:true
  onTriggered:{
   if (!Config.ready || !Persistent.ready) return;
   Config.options.sidebar.keepLeftSidebarLoaded=!!root.test.keep && root.test.kind === "policies";
   Config.options.sidebar.keepRightSidebarLoaded=!!root.test.keep && root.test.kind === "dashboard";
   Config.options.cheatsheet.keepLastTabLoaded=!!root.test.keep;
   GlobalStates.policiesPinned=false; GlobalStates.policiesDetached=false;
   GlobalStates.barOpen=root.test.kind !== "bar";
   if(root.test.kind === "policies") Persistent.states.sidebar.policies.tab=root.test.tab;
   root.booted=true;root.next();
  }
 }
 Component.onCompleted:{
  Qt.application.applicationName="quickshell";
  Qt.application.organizationName="Unknown Organization";
  Qt.application.organizationDomain="unknown.organization";
  MaterialThemeLoader.reapplyTheme();
 }
}
'''
def cpseed():
 import shutil
 for part in ('config','state','cache'):
  dest=BASE/('run-'+part)
  if dest.exists():shutil.rmtree(dest)
  subprocess.run(['cp','-a','--reflink=auto',str(BASE/('seed-'+part)),str(dest)],check=True)
def box():
 args=['bwrap','--ro-bind','/','/','--dev-bind','/dev','/dev','--proc','/proc','--unshare-pid','--unshare-net','--die-with-parent','--tmpfs','/tmp']
 for a,b in [(BASE,BASE),(HOME_PATH/'.config',BASE/'host-config'),(BASE/'config-root',HOME_PATH/'.config'),(BASE/'source',SRC),(BASE/'run-config',HOME_PATH/'.config/illogical-impulse'),(BASE/'run-state',HOME_PATH/'.local/state/quickshell'),(BASE/'run-cache',HOME_PATH/'.cache/quickshell'),(RUNTIME,RUNTIME)]:
  args+=['--ro-bind' if b==BASE/'host-config' else '--bind',str(a),str(b)]
 args+=['--chdir',str(SRC),'--','qs','-c','ii','--no-duplicate','--no-color','--log-times']
 return args
def stop_group(p):
 if p and p.poll() is None:
  os.killpg(p.pid,signal.SIGTERM)
  try:p.wait(timeout=4)
  except subprocess.TimeoutExpired:
   os.killpg(p.pid,signal.SIGKILL);p.wait(timeout=4)
def snapshots():
 out={}
 for name,cmd in [('layers',['hyprctl','-j','layers']),('windows',['hyprctl','-j','clients'])]:
  try:
   obj=json.loads(subprocess.check_output(cmd,text=True,timeout=3))
   if name=='layers':
    out[name]=[{k:v for k,v in x.items() if k in ('namespace','x','y','w','h','pid')} for mon in obj.values() for layer in mon.get('levels',{}).values() for x in layer if 'quickshell' in x.get('namespace','')]
   else:out[name]=[{k:v for k,v in x.items() if k in ('pid','class','mapped','hidden','size')} for x in obj if 'quickshell' in x.get('class','').lower()]
  except Exception as e:out[name]={'error':type(e).__name__}
 return out
def summarize(result):
 rows=[];pid=str(result['pid'])
 for phase in dict.fromkeys(s['phase'] for s in result['samples']):
  phaseall=[s for s in result['samples'] if s['phase']==phase]
  start=phaseall[0]['elapsed'];samples=[s for s in phaseall if s['elapsed']-start>=5 and pid in s['processes']]
  if len(samples)<2:continue
  def med(f):return round(statistics.median(f(s) for s in samples),3)
  a,b=samples[0],samples[-1];dt=b['elapsed']-a['elapsed']
  def totalcpu(s):return sum(p['cpuSeconds']+p['waitedChildCpuSeconds'] for p in s['processes'].values())
  gpu=[u['smUtil'] for s in samples for u in s['gpu']['utilSamples'] if str(u['pid'])==pid]
  statuses=sorted(set(s['gpu']['utilStatus'] for s in samples))
  # NVML reports only processes having nonzero activity. No report in a successful
  # interval is treated as inactive, while raw statuses/samples are retained.
  gpuMean=statistics.mean(sum(u['smUtil'] for u in s['gpu']['utilSamples'] if str(u['pid'])==pid) for s in samples) if all(x in (0,6) for x in statuses) else None
  rows.append({'phase':phase,'seconds':round(dt,2),'samples':len(samples),
   'rssMiB':med(lambda s:s['processes'][pid]['memoryMiB']['Rss']),
   'pssMiB':med(lambda s:s['processes'][pid]['memoryMiB']['Pss']),
   'privateMiB':med(lambda s:s['processes'][pid]['memoryMiB']['Private']),
   'treePssMiB':med(lambda s:sum(x['memoryMiB']['Pss'] for x in s['processes'].values())),
   'cpuPercent':round(100*(b['processes'][pid]['cpuSeconds']-a['processes'][pid]['cpuSeconds'])/dt,3),
   'treeCpuPercent':round(100*(totalcpu(b)-totalcpu(a))/dt,3),
   'vramMiB':med(lambda s:s['gpu']['memoryMiB'].get(pid,0)) if all(s['gpu']['memoryStatus']==0 for s in samples) else None,
   'gpuSmMeanApprox':round(gpuMean,3) if gpuMean is not None else None,'gpuSmPeak':max(gpu,default=0) if gpuMean is not None else None,
   'nvmlUtilStatuses':statuses,'globalGpuMean':round(statistics.mean(s['gpu']['globalGpuPercent'] for s in samples if s['gpu']['globalGpuPercent'] is not None),2)})
 return rows
def run_case(case,stages):
 cpseed()
 (BASE/'source/shell.qml').write_text(DRIVER.replace('__CASE__',json.dumps(case)).replace('__STAGES__',json.dumps(stages)).replace('__IMPORT__', 'import qs.' + str(Path(case['path']).parent).replace('/', '.') if '/' in case['path'] else ''))
 env=os.environ.copy();env.pop('II_CHEATSHEET_CACHE_PROBE',None)
 path=RESULTS/case['id'];path.mkdir(exist_ok=True)
 nv=Nvml(); nv.read(set())
 result={'case':case,'stages':stages,'startedUtc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'samples':[],'markers':[],'maps':{},'surfaces':{}}
 with (path/'private.log').open('w') as log:
  p=subprocess.Popen(box(),stdout=log,stderr=subprocess.STDOUT,env=env,start_new_session=True)
  global ACTIVE;ACTIVE=p
  lastMarker=0;begin=time.monotonic();pid=None;phase='boot';offset=0;foundat=None;checkphases=set()
  while time.monotonic()-begin < sum(x['seconds'] for x in stages)+90:
   if p.poll() is not None:raise RuntimeError(f'{case["id"]}: sandbox exited {p.returncode}; inspect private log')
   elapsed=time.monotonic()-begin
   with (path/'private.log').open() as read:
    read.seek(offset)
    for line in read:
     if 'IIAUDIT ' in line:
      try:
       marker=json.loads(line.split('IIAUDIT ',1)[1]);result['markers'].append(marker);lastMarker=elapsed
       if marker['phase']=='open' and marker['extra']=='settled' and marker['status'] != 1:raise RuntimeError('target did not load')
       if marker['phase']!=phase:phase=marker['phase'];foundat=elapsed; print(json.dumps({'case':case['id'],'phase':phase,'elapsed':round(elapsed,1)}),flush=True)
      except json.JSONDecodeError:pass
    offset=read.tell()
   if phase=='done':break
   if phase!='boot' and elapsed-lastMarker>35:raise RuntimeError(f'{case["id"]}: heartbeat stalled at {phase}')
   if pid is None:
    desc=proc.tree(p.pid); candidates=[int(k) for k,v in desc.items() if v['name']=='qs']
    if candidates:pid=candidates[0];result['pid']=pid
   if pid:
    ps=proc.tree(pid)
    if str(pid) not in ps:raise RuntimeError(f'{case["id"]}: qs disappeared')
    result['samples'].append({'elapsed':elapsed,'time':time.time(),'phase':phase,'processes':ps,'gpu':nv.read({int(x) for x in ps})})
    if foundat is not None and elapsed-foundat>=10 and phase not in checkphases:
     result['maps'][phase]=proc.memory_maps(pid)['groupsMiB']; result['surfaces'][phase]=snapshots();checkphases.add(phase)
   time.sleep(1)
  else:raise RuntimeError(f'{case["id"]}: timed out at {phase}')
  stop_group(p);ACTIVE=None
 result['summary']=summarize(result)
 (path/'measurements.json').write_text(json.dumps(result,indent=2)+'\n')
 (path/'summary.json').write_text(json.dumps(result['summary'],indent=2)+'\n')
 print(json.dumps({'case':case['id'],'complete':True,'summary':result['summary']}),flush=True)
 return result
ACTIVE=None
STOPPED=False
PROD_PID=int(subprocess.check_output(['pgrep','-x','qs'],text=True).strip())
WORKSPACE=None
ORIGINAL_HASH=None
def signal_handler(signum,frame):raise KeyboardInterrupt()
def main():
 global STOPPED,WORKSPACE,ORIGINAL_HASH
 signal.signal(signal.SIGTERM,signal_handler);signal.signal(signal.SIGINT,signal_handler)
 selection=sys.argv[1:]
 cases=[x for x in CASES if not selection or x['id'] in selection]
 if not cases:raise SystemExit('no cases selected')
 conf=HOME_PATH/'.config/illogical-impulse/config.json';ORIGINAL_HASH=hashlib.sha256(conf.read_bytes()).hexdigest()
 baseline=proc.tree(PROD_PID)
 if str(PROD_PID) not in baseline or baseline[str(PROD_PID)]['name']!='qs':raise RuntimeError('production PID changed; inspect before running')
 meta={'originalPid':PROD_PID,'originalConfigHash':ORIGINAL_HASH,'sourceHead':subprocess.check_output(['git','rev-parse','HEAD'],cwd=SRC,text=True).strip(),'originalProcesses':baseline}
 (BASE/'recovery.json').write_text(json.dumps(meta,indent=2)+'\n')
 subprocess.run(['qs','list','--all','--no-color'],check=True)
 try:
  STOPPED=True
  os.kill(PROD_PID,signal.SIGTERM)
  time.sleep(2)
  # Recorded exact identities only. Reparented helper processes are included.
  for pid,old in reversed(list(baseline.items())):
   try:
    if proc.stat(Path('/proc')/pid)['startTicks']==old['startTicks']:os.kill(int(pid),signal.SIGKILL)
   except (FileNotFoundError,ProcessLookupError):pass
  time.sleep(1)
  if any(v['name']=='qs' for v in proc.tree(os.getpid()).values()):raise RuntimeError('unexpected qs child')
  ws=json.loads(subprocess.check_output(['hyprctl','-j','activeworkspace'],text=True));WORKSPACE=ws['id']
  allws=json.loads(subprocess.check_output(['hyprctl','-j','workspaces'],text=True));target=9009
  while any(x['id']==target for x in allws):target+=1
  subprocess.run(['hyprctl','dispatch',f'hl.dsp.focus({{ workspace = {target} }})'],stdout=subprocess.DEVNULL,check=True)
  stages=[{'phase':'core','seconds':15},{'phase':'controller','seconds':15},{'phase':'open','seconds':25},{'phase':'closed','seconds':25},{'phase':'unloaded','seconds':20}]
  for case in cases:
   try: run_case(case,stages)
   except Exception as exc:
    stop_group(ACTIVE)
    (RESULTS/case['id']/'failed.json').write_text(json.dumps({'error':str(exc)}))
    print(json.dumps({'case':case['id'],'failed':str(exc)}),flush=True)
 finally:
  stop_group(ACTIVE)
  if WORKSPACE is not None:subprocess.run(['hyprctl','dispatch',f'hl.dsp.focus({{ workspace = {WORKSPACE} }})'],stdout=subprocess.DEVNULL)
  if STOPPED:
   subprocess.run(['qs','list','--all','--no-color'])
   subprocess.Popen(['qs','-c','ii','--no-duplicate'],stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,start_new_session=True)
   time.sleep(4)
   subprocess.run(['qs','list','--all','--no-color'])
   print(json.dumps({'restored':True,'originalConfigUnchanged':hashlib.sha256(conf.read_bytes()).hexdigest()==ORIGINAL_HASH}),flush=True)
if __name__=='__main__':main()
