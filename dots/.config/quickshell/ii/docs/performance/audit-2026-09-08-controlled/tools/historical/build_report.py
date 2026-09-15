from pathlib import Path
import json,hashlib,statistics,shutil,datetime
BASE=Path(__file__).resolve().parent
DEST=BASE/'report';DEST.mkdir(exist_ok=True)
LABELS={
'dashboard_keep':'Dashboard — cache ligado','dashboard_unload':'Dashboard — cache desligado',
'policies_ai_keep':'Sidebar IA — cache ligado','policies_ai_unload':'Sidebar IA — cache desligado',
'policies_phone':'Sidebar solicitando Phone (aba não validada; excluído da atribuição)',
'cheatsheet_keybinds_keep':'Calendário pré-carregado → Atalhos','cheatsheet_keybinds_unload':'Atalhos — cache desligado',
'cheatsheet_timetable':'Calendário mensal','cheatsheet_commands':'Comandos','overview':'Overview',
'settings_colors':'Settings — Cores','settings_bar':'Settings — Barra','usage':'Uso de aplicativos','notes':'Notas',
'wallpaper_selector':'Seletor de wallpapers','background':'Background + widgets desktop','vertical_bar':'Barra vertical',
'dock':'Dock','media_mode':'Modo de mídia (inclui Background)',
'repeat_keybinds_keep':'Atalhos — cache ligado, mesma aba','repeat_keybinds_unload':'Atalhos — cache desligado, mesma aba',
'phone_only':'Phone — única política habilitada','repeat_timetable':'Calendário mensal — repetição + GC',
'bar_no_privacy':'Barra vertical — Privacy desativado','bar_reference':'Barra vertical — referência A/B','bar_active_layout':'Barra vertical — apenas layout ativo','media_reference':'Modo de mídia — referência A/B','media_static':'Modo de mídia — fundo estático / visualizador desligado','family_fork_no_prewarm':'Família II — fork sem pré-carregar sidebars/cheatsheet','family_fork':'Família II — fork','family_upstream':'Família II — end-4',
}
data={p.parent.name:json.loads(p.read_text()) for p in (BASE/'results').glob('*/measurements.json')}
manifest={'createdUtc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'cases':{},'units':'MiB; CPU 100%=one logical CPU; GPU SM percent NVML', 'snapshot':'842411d065ada2b95a714dbeacc1387ada258aac'}
records=[]
for name,d in data.items():
 path=DEST/'data'/name;path.mkdir(parents=True,exist_ok=True)
 source=BASE/'results'/name/'measurements.json';shutil.copy2(source,path/'measurements.json')
 valid=[x for x in d['markers'] if x['phase']=='open' and x['extra']=='settled' and x['status']==1]
 manifest['cases'][name]={'label':LABELS.get(name,name),'samples':len(d['samples']),'openedWithReadyLoader':bool(valid),'sha256':hashlib.sha256(source.read_bytes()).hexdigest()}
 for r in d['summary']:records.append({'case':name,'label':LABELS.get(name,name),**r})
(DEST/'manifest.json').write_text(json.dumps(manifest,indent=2,ensure_ascii=False)+'\n')
(DEST/'summary.json').write_text(json.dumps(records,indent=2,ensure_ascii=False)+'\n')
f=lambda n:f'{n:.1f}' if n is not None else 'N/D'
lines=['# Medições controladas por módulo','', 'Valores absolutos do processo Quickshell isolado. RAM em MiB de PSS. A árvore soma os auxiliares observados. Não somar os módulos: eles compartilham serviços e bibliotecas no shell completo.','',
'| Cenário | Núcleo | Antes de abrir | Aberto | Fechado | Descarregado | CPU aberto (%) | CPU fechado (%) | Árvore CPU aberto (%) | VRAM aberta | VRAM fechada | GPU SM média aprox. (%) | GPU SM pico (%) |',
'|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|']
for name,d in data.items():
 if name=='policies_phone':continue
 p={x['phase']:x for x in d['summary']}
 if not all(x in p for x in ['core','controller','open','closed','unloaded']):continue
 vals=[p[x]['pssMiB'] for x in ['core','controller','open','closed','unloaded']]+[p['open']['cpuPercent'],p['closed']['cpuPercent'],p['open']['treeCpuPercent'],p['open']['vramMiB'],p['closed']['vramMiB'],p['open']['gpuSmMeanApprox'],p['open']['gpuSmPeak']]
 lines.append('| '+LABELS.get(name,name)+' | '+' | '.join(f(v) for v in vals)+' |')
lines+=['','## Segunda abertura e coleta explícita','', '| Cenário | Aberto 1 | Fechado 1 | Aberto 2 | Fechado 2 | Descarregado | Após gc() | Redução adicional por GC |','|---|---:|---:|---:|---:|---:|---:|---:|']
for name,d in data.items():
 p={x['phase']:x for x in d['summary']}
 if 'gc' not in p:continue
 vals=[p[x]['pssMiB'] if x in p else None for x in ['open','closed','reopen','closed_again','unloaded','gc']]+[p['unloaded']['pssMiB']-p['gc']['pssMiB']]
 lines.append('| '+LABELS.get(name,name)+' | '+' | '.join(f(v) for v in vals)+' |')
lines+=['','## RAM RSS e processos auxiliares','', '| Cenário | RSS aberto | PSS aberto | PSS da árvore aberto | Auxiliares (diferença) |','|---|---:|---:|---:|---:|']
for name,d in data.items():
 if name=='policies_phone':continue
 p=next((x for x in d['summary'] if x['phase']=='open'),None)
 if p:lines.append('| '+LABELS.get(name,name)+' | '+' | '.join(f(x) for x in [p['rssMiB'],p['pssMiB'],p['treePssMiB'],p['treePssMiB']-p['pssMiB']])+' |')
(DEST/'medicoes.md').write_text('\n'.join(lines)+'\n')
# Sanitized source inventory: no configuration values, user data, or raw logs.
(DEST/'validacao.json').write_text(json.dumps({name:{'surfaces':d['surfaces'],'openMarkers':[x for x in d['markers'] if x['phase']=='open' and x['extra']=='settled']} for name,d in data.items()},indent=2)+'\n')
print(json.dumps({'cases':len(data),'report':str(DEST)}))
