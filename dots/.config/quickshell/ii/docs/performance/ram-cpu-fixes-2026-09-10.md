# Correções de RAM/CPU — 10 de setembro de 2026

Continuação direta da [auditoria consolidada](audit-2026-09-08-controlled/REANALISE-INVESTIGACOES.md)
e da [auditoria de GPU](gpu-audit-2026-09-09.md). Meta declarada pelo usuário:
**~700 MiB de RAM em idle**. Esta rodada foi interrompida a pedido do usuário
no meio da investigação do visualizer; o que está abaixo é o estado real da
árvore de código neste momento — o que foi corrigido e medido, e o que falta.

## 1. Estado medido (limpeza de sessões + restarts limpos)

| Momento | RSS | PSS | Nota |
|---|---:|---:|---|
| Auditoria 2026-09-08 (confirmação 60 s) | 1050,95 MiB | 854,04 MiB | referência histórica |
| Sessão de hoje, antes das correções (após 30 min de hot-reloads meus) | 1016 MiB | 815 MiB | janela suja por reload churn |
| **Depois das correções, início limpo, idle 60 s** | **798,7 MiB** | **621,0 MiB** | mediana de 30 amostras |

PSS de 621 MiB já está abaixo da meta; RSS de 799 MiB está perto dela.
**Limites**: início limpo ≠ uso diário (o número real cresce com hot-reloads e
sessões longas, como na auditoria); as medições não isolam arenas do jemalloc
que não retornam ao SO. A comparação exata antes/depois na mesma sessão limpa
não foi completada — interrompida pelo pedido de parada.

CPU da árvore no idle medido após as correções: **41,75% de um núcleo**
(`qs` 39,6% + cava 1,8% + auxiliares ~0,3%). O dominante é o `qs` **com mídia
tocando** — ver §3, item adiado: o usuário confirmou que trocar o estilo do
widget de media da bar (retirando o visualizer) derruba o uso drasticamente.

## 2. Corrigido nesta rodada

### 2.1 `screensharestate.sh`: produtor único, fim dos órfãos
**Evidência:** 8 loops `pw-dump|jq` simultâneos vivos durante a medição
(4 órfãos com PPID=1, sobreviventes de `killall -9 qs`, + 1 por instância do
widget `ScreenShareIndicator`). A auditoria de 09-08 já havia provado 2.

**Correção em `scripts/screenShare/screensharestate.sh`:**
1. `flock` no LOCK_FILE, nunca escrito;
2. heartbeat `pid+tempo` em BEAT_FILE separado (escrita atômica tmp+rename) —
   um candidato cuja lock está tomada sai em milissegundos se o holder está
   vivo, e assume (`flock -w 5`) se ele morreu;
3. guarda de órfão: se o ppid mudou (shell dono morreu → reparenteado ao
   init), o loop sai sozinho no próximo tick.

**Armadilha descoberta no caminho (testado, corrigido):** na primeira versão,
beat e lock dividiam o mesmo inode e o `exec 9>` de cada candidato **truncava
o heartbeat do holder antes da leitura** — os 5 losing processes entravam em
`flock -w 5` em vez de sair cedo ("6 vivos" no teste de corrida). Com os
inodes separados: teste de 5 partidas simultâneas converge para **1**; teste
de takeover (matar o holder → novo assume o beat) funciona; 1 produtor vivo
no shell atual via IPC `ipc call`. O widget `ScreenShareIndicator.qml` mantém
seu `Process` por instância — o flock é o que torna as cópias baratas (saída
em ms); remover o Process do widget foi tentado via singleton
`ScreenShareState.qml` e **revertido**: singletons novos referenciados durante
hot-reload produziram cascata `Type ScreenShareState unavailable` (mesmo
padrão do SIGSEGV de singleton novo do AGENTS.md), e o estado do widget
(um `FileView` + uma binding) já vem do arquivo de estado de qualquer jeito.

**Ganho:** ~4,6–4,9% de um núcleo por duplicata eliminada; órfãos que nunca
morriam → zero; 1 MiB/min de lockfile que crescia por append → truncado.

### 2.2 `VpnService`: poll leve + bug real de `"active"`
**Evidência:** o `pollTimer` de 10 s chamava `refresh()`, que roda a cadeia
completa de descoberta: `which nmcli` + `which nordvpn` + `which protonvpn` +
`nmcli profiles` + `nmcli active` + `nordvpn status` + `protonvpn status`
(CLI Python; a auditoria pegou `protonvpn` com pico de **103 MiB PSS**) — a
cada 10 s, para sempre, mesmo com backend `networkmanager`.

**Correção em `services/VpnService.qml`:**
- novo `pollStatus()`: 10 s fazem apenas `nmcli` ativo + status do provedor
  CLI **somente enquanto ele é o `activeProvider`**; `refresh()` completo fica
  para boot, `Config.ready`, toggle, diálogo aberto, import/conect/desconect;
- `onTriggered: pollStatus()` no Timer;
- **bug real consertado:** `enqueue("active", ...)` existia mas **não havia
  handler `kind === "active"`** — o `nmcli` rodava a cada ciclo e a saída era
  descartada; `parseActive()` era código morto. Agora conectado (linha
  `else if (kind === "active") { root.parseActive(out) }`).

**Verificado:** 12 s de observação sem spawns de `which`/`protonvpn` com
poll ativo; `protonvpn status` → "Disconnected" (não-VPN no NM, o ramo CLI só
roda se for o provedor ativo); testes `test_google_tasks_api` OK.

### 2.3 Sidebar Policies: cache de abas limitado
**Evidência:** §2 da auditoria de RAM ("prioridade alta de teste") —
`visitedTabs` só crescia; com `keepLeftSidebarLoaded: true`, passar por
AI + Translator + Phone deixava as três árvores pesadas residentes para
sempre na sessão.

**Correção em `modules/ii/sidebarPolicies/SidebarPoliciesContent.qml`:**
em `onCurrentIndexChanged`, o cache morno passou a ser **aba atual + aba de
origem** (o par vai-e-volta comum), não o acúmulo histórico. Sem mudança de
preferência do usuário, sem tocar em drafts/estado de serviço (só a UI
decaiu).

### 2.4 Timeouts de rede nos helpers de e-mail/Google
**Evidência:** §3 da auditoria — quatro helpers residentes 60 s com quase
zero CPU (≈49 MiB PSS somados) porque `urlopen` sem timeout pode travar para
sempre.

**Correção:** `timeout=30` em todas as chamadas `urlopen` de produção de
`scripts/email/` (10 sítios: fetch_emails, fetch_labels, fetch_thread,
fetch_all_accounts, fetch_email_body, delete_email, download_email_attachment,
send_email, oauth_server ×2) e em `scripts/google/google_config.py`,
`scripts/google/oauth.py` (×2), `scripts/google_tasks/api.py`,
`scripts/google_calendar/api.py`. `py_compile` OK em todos; lista restante
sem timeout: **zero** (só `list_ics_attachments.py` já tinha 20 s).

### 2.5 Logs órfãos do Quickshell em tmpfs
**Evidência:** §7 da auditoria — 156 MiB de logs sem instância ativa em
`/run/user/1000` (tmpfs = RAM do sistema).

**Ação:** 3 diretórios órfãos arquivados (copiados, depois removidos) para
`~/.local/share/quickshell/orphaned-logs.20260910_153751/` em **disco**
(`/tmp` não serve — também é tmpfs aqui). tmpfs: 105 → 38 MiB ocupados.
Nada da instância ativa foi tocado.

### 2.6 BudsLink — verificado, **não alterado**
Pedida pelo usuário. Investigação: o serviço D-Bus `io.github.maniacx.BudsLink`
está realmente rodando (`busctl --user list`), e o `gjs bridge.js` é o
HoldService que o mantém vivo — comportamento **legítimo** com um candidato de
áudio (Soundcore Life Q30 conectado). O idle-stop já existe (8 s de graça
quando o gate cai). Uma park-flag por "serviço ausente" foi considerada e
**rejeitada**: o serviço não está ausente. CPU do `gjs` mensurável abaixo da
resolução. **Ganho zero; código intacto.**

## 3. O que FALTA (próxima sessão, por ordem de evidência)

### 3.1 Visualizer da bar — RESOLVIDO 2026-09-11 (commit `efac0a813`)
**A causa era arquitetural, como suspeitado abaixo.** Cada amostra do Cava (30 Hz)
mudava a altura de uma barra que vivia **dentro** do mesmo `Item` que carrega
`layer.enabled` + `OpacityMask` (cantos arredondados do card de arte). Isso
forçava o re-render + recomposição do FBO mascarado inteiro (arte borrada,
gradientes, vinheta, dimming, texto) 30×/s. Diagnóstico A/B: desligar o `layer`
da raiz do `NeuralMedia` levou `qs` de ~28% → ~15,7% de um núcleo com mídia
tocando; confirma que o custo é o re-render do FBO disparado pelas barras.

**Correção:** o card de arte foi para um `Item` interno com o `layer`/máscara;
a linha de conteúdo (texto + visualizer) passou a ser irmã por cima, **fora** do
layer. Uma mudança de barra agora repinta só as barrinhas; o FBO da arte fica em
cache até track/arte/estado-de-reprodução mudar. Cantos arredondados idênticos
(verificado por screenshot). Medido: `qs` com mídia tocando **~28% → ~14%** de um
núcleo (idle inalterado ~4%). Aplicado nas três superfícies:
- `NeuralMedia.qml` (estilo ativo aqui) — medido acima.
- `FloatingNotchMedia.qml` (mídia contraída do notch) — mesma correção; a linha
  de conteúdo espelha `opacity`/`scale` de `contractedLayout`, então a animação
  expand/contract fica inalterada e em repouso renderiza idêntico.
- `VerticalNeuralMedia.qml` (barra vertical) — coluna do visualizer fora do layer
  da pill e `Behavior on width` por barra removido (30 Hz já é o movimento).

**Aberto ainda:** dos ~14% tocando, ~10% não é o FBO da arte (o diagnóstico
layer-off deu ~15,7%). Candidato barato restante (auditoria path 3, não aplicado
para não mexer na suavidade do MediaMode): baixar a taxa efetiva do Cava
(`scripts/cava/raw_output_config.txt` `framerate = 30` → 20/15, ou throttle 2:1)
— indistinguível a olho para 4 barras.

### 3.1-histórico Visualizer da bar — (contexto original, item aberto mais quente)
O usuário identificou: `qs` a ~38–39% de um núcleo com mídia tocando cai
drasticamente ao trocar o estilo do widget de media da bar para um **sem
visualizer**. Presente em três superfícies com o mesmo padrão
(`CavaService.visualizerPoints` 30 Hz → 4 barras):
- `modules/ii/bar/widgets/media/NeuralMedia.qml` (o reportado)
- `modules/ii/dynamicIsland/widgets/FloatingNotchMedia.qml` (linhas ~895)
- `modules/ii/dock/DockMediaWidget.qml` (já usa `getBarHeight` direto, sem
  animação — o precedência "correta")

**Já feito antes de parar:** removidas as duas `Behavior` de NumberAnimation
por barra de `modules/common/widgets/ModernVisualizerBar.qml` (altura aplicada
direto, como o dock). **Não resolveu** o percentual → o custo está na
arquitetura de render, não nas animações.

**Suspeita principal (não corrigida, a pedido de pausa):**
`NeuralMedia.qml:274` tem `layer.enabled: true` + `OpacityMask` na **raiz do
widget inteiro**; mais três layers internas (315, 340/357). Cada amostra do
Cava (30 Hz) muda uma altura → **redesenha o FBO inteiro mascarado, com as
layers filhas, a 30 Hz, duas barras por amostra ×2 (barra da frente + fundo)**.
Caminhos a testar na próxima sessão, em ordem:
1. tirar as barras do visualizer **de dentro** da sub-árvore com layer/mask
   raiz (mascara-se o card de arte, não a barinha; ver se `bar0Val…bar3Val`
   podem alimentar um `Rectangle` sem camada, como no dock);
2. medir o custo de paint com um `visible: false` no Item das barras (A/B sem
   mudar estilo de config);
3. reduzir frequência efetiva: só repintar quando `|Δ| > ε` por barra, ou
   throttle de 2 em 2 amostras — 15 Hz é indistinguível a olho para 4 barras;
4. repetir 1–3 em `FloatingNotchMedia` e conferir que `DockMediaWidget` não
   precisa de nada.

### 3.2 Itens da auditoria ainda sem correção aplicada
- **F1 (barra, maior sinal):** decompor o custo residente da barra com ela
  **funcional** (um grupo de observadores/widget por vez), não removida.
- **C1 (calendário):** lateral/pickers sob demanda *funcional* (o que foi
  medido era stub).
- **P1:** unificar privacy probe + screenshare **só depois de validar o
  backend compartilhado** (a P1 voltou para "parcial/bloqueado"); hoje o
  `privacy_probe.py` e o `screensharestate.sh` ainda são dois leitores de
  PipeWire separados, cada um no seu gate — a duplicação de processo morreu
  (§2.1), a duplicação de *observador* continua viva.
- **M1:** gate dos visualizadores por modo/visibilidade com fonte de áudio
  real controlada (a §3.1 é o lado concreto disso).
- **§4 da auditoria:** perfil nativo do bloco de ~596 MiB (jemalloc
  decay/background purge) — exige bancada controlada, não foi iniciada.
- **`vrr = 0`** em 180 Hz (fora do shell; maior alavancagem de GPU restante).
- **§5 gate de blur por superfície opaca** — `verticalBar` ainda é a candidata
  segura (a `backgroundWidgets` tem `tintOpacity` ativo do usuário).
- ScreenShareIndicator: o `toggleVisible` imperativo em `onLoaded` continua
  (com `Component.onCompleted` seed no Record Indicator como precedente);
  funcional, não testado ao vivo com compartilhamento ativo.

### 3.3 Verificações pendentes desta rodada
- Confirmar com um compartilhamento de tela real que o indicador aparece
  (o flock não pode deixar o estado morrer entre producers — o heartbeat de
  6 s e a takeover de 5 s cobrem isso no papel; não testado com `wf-recorder`
  ao vivo).
- Confirmar que quick toggle/`VpnDialog` mostram estado correto com o poll
  leve (conectar → status CLI passa a ser consultado só quando aquele
  provedor é o ativo).
- Re-roda da suíte RAM (idle 60 s) **sem mídia tocando** para separar o custo
  do §3.1 do ganho das §2.x.

## 4. Arquivos alterados nesta rodada

| Arquivo | Mudança |
|---|---|
| `scripts/screenShare/screensharestate.sh` | flock+heartbeat separados, takeover limitado, guarda de órfão |
| `modules/ii/bar/widgets/indicators/ScreenShareIndicator.qml` | comentários do mecanismo (código: restaurado ao formato com flock no script) |
| `services/VpnService.qml` | `pollStatus()` leve; handler `active` novo (bug: saída antes descartada) |
| `modules/ii/sidebarPolicies/SidebarPoliciesContent.qml` | `visitedTabs` limitado a atual+anterior |
| `modules/common/widgets/ModernVisualizerBar.qml` | sem `Behavior` por barra (insuficiente; ver §3.1) |
| `scripts/email/*.py` (9 arquivos) + `scripts/google/*.py` (3) + `google_tasks/api.py` + `google_calendar/api.py` | `timeout=30` em todo `urlopen` de produção |
| `/run/user/1000/quickshell/by-id/*` (3 órfãos) | logs arquivados para `~/.local/share/quickshell/orphaned-logs.20260910_153751/` |
