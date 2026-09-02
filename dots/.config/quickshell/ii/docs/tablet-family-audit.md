# Auditoria — Tablet Panel Family

> **Data:** 2026-09-02 · **Branch:** `agent/tablet-family-base` · **Base:** `980fbe8b0`
> **Documento irmão:** [`tablet-family-plan.md`](./tablet-family-plan.md) — o plano descreve o que
> foi construído; este documento descreve **o que falta para isso ser um tablet**.
>
> **Referências de produto:** Google Pixel Tablet / Android 16 (QPR), Samsung Galaxy Tab
> (One UI 7/8).

---

## 0. Como ler este documento

O plano original está essencialmente cumprido: as sete fases entregaram bar, gaveta, dock,
home screen, recentes, app windows e uma página de Settings própria, com a arquitetura de
camadas cobrada por script e baseline em zero. Esta auditoria **não questiona nada disso**.

Ela responde a outra pergunta: *pegando este shell e colocando numa tela de toque sem
teclado nem mouse, o que impede alguém de usá-lo como usa um tablet?*

A resposta tem três camadas, e a ordem importa:

| Camada | Pergunta | Seção |
|---|---|---|
| **Bloqueadores** | O que torna o dispositivo inoperante ou preso? | §2 |
| **Paridade** | O que um usuário de Android procura e não encontra? | §3–§6 |
| **Acabamento** | O que existe mas ainda parece um desktop encolhido? | §7 |

Severidades usadas no backlog (§8):

- 🔴 **P0** — o usuário fica sem saída, ou a funcionalidade prometida não funciona.
- 🟠 **P1** — paridade de tablet que o usuário procura no primeiro dia.
- 🟡 **P2** — paridade que se sente na primeira semana.
- 🔵 **P3** — polimento; melhora a percepção, não desbloqueia nada.

---

## 1. Sumário executivo

| Área | Estado | Nota | O que falta em uma linha |
|---|---|---|---|
| Arquitetura de camadas | ✅ | — | Baseline em 0, guarda passando. Nada a fazer. |
| Bar / status bar | 🟢 Bom | 8/10 | Some sob gaveta e recentes; ainda mostra workspaces numerados. |
| Dock / taskbar | 🟢 Bom | 8/10 | Fica **embaixo** de recentes; sem arrastar app da dock para split. |
| Gaveta de apps | 🟡 Regular | 6/10 | Densidade de desktop (~12 colunas), sem A–Z, sem sugestões, sem paginação. |
| Shade / quick settings | 🟢 Bom | 8/10 | Split shade correto. Falta brilho adaptativo, tiles de rotação. |
| **Recentes** | 🔴 Fraco | 4/10 | **Não é MRU**, sem menu de app, sem "limpar tudo", sem split. |
| **Gestos** | 🟡 Regular | 5/10 | Sem back lateral, sem "↑ e segurar", sem quick-switch. Nada validado em hardware. |
| **OSK** | 🔴 Fraco | 3/10 | Auto-show desligado, binário não compilado, **ausente na lock screen**. |
| **Lock screen** | 🔴 Fraco | 2/10 | Sem teclado, sem PIN pad → **não desbloqueia sem teclado físico**. |
| Home screen | 🟡 Regular | 6/10 | Botão Home não leva à home screen configurada. Sem pastas, sem widgets tocáveis. |
| Multi-janela | 🔴 Ausente | 1/10 | Nenhum caminho de UI para split-screen, app pairs ou pop-up view. |
| Troca de família | 🔴 Ausente | 0/10 | Só IPC e keybind. **Nenhuma UI em lugar nenhum.** |
| Settings | 🟢 Bom | 7/10 | Página Tablet existe; falta fling e revisão interna dos diálogos. |

**Veredito:** a *estrutura* de um tablet está pronta e é boa. O que falta é a camada onde o
tablet encosta no dedo — desbloquear, digitar, voltar, alternar app. São cinco bloqueadores
(§2), e quatro deles são pequenos em código.

---

## 2. Bloqueadores (P0)

### B1 — Não dá para desbloquear a tela sem teclado físico 🔴

O caso mais grave da auditoria, e o único que deixa o dispositivo **inutilizável**.

| Evidência | Arquivo |
|---|---|
| Deck (OSK padrão) não renderiza com a tela bloqueada | `onScreenKeyboard/DeckWindow.qml` — `visible: !GlobalStates.screenLocked` |
| OSK clássica idem | `onScreenKeyboard/OnScreenKeyboard.qml` |
| O helper de auto-show é desligado ao bloquear | `services/OskAutoShow.qml` — `running: root.enabled && !GlobalStates.screenLocked` |
| A lock screen só tem campo de texto — sem keypad, sem botão de teclado | `modules/ii/lock/LockSurface.qml` (`ToolbarTextField`); `grep -l keypad modules/ii/lock/` → vazio |

Ou seja: bloqueou a tela, **acabou**. Não existe caminho de toque para digitar a senha.
Isso é correto para a família ii (um desktop tem teclado); é fatal para uma família que o
próprio plano define como "nada aqui pressupõe teclado físico".

**Correção — e o primeiro rascunho dela estava errado.**

A ideia óbvia é remover a condição `!GlobalStates.screenLocked` e deixar a OSK aparecer por
cima. **Isso não pode funcionar.** O lock é um `WlSessionLock`
(`modules/common/panels/lock/LockScreen.qml`), e o protocolo de session lock cobre *todas* as
camadas do layer-shell — é a razão de o protocolo existir, não um descuido a contornar. Uma
OSK layer-shell nunca vai ser desenhada ali, com ou sem a condição.

O teclado tem que ser desenhado **dentro da própria lock surface**:

1. **`LockTouchKeyboard`** em `modules/common/panels/lock/` — filho da `WlSessionLockSurface`,
   com três camadas (letras, símbolos, PIN numérico).
2. **Digita atribuindo a `LockContext.currentText`**, não sintetizando eventos com ydotool.
   Este é o caminho de desbloqueio: se falhar, o aparelho vira tijolo até aparecer um teclado
   físico. O ydotool precisa de daemon rodando, nó uinput gravável e permissões — uma sessão
   bloqueada é exatamente o pior lugar para descobrir que falta alguma delas. Atribuir uma
   string não precisa de nada disso.
3. **Efeito colateral de segurança, de graça:** nada que este teclado digita pode escapar da
   lock surface, porque nunca chega a virar um evento de entrada.

A promoção da OSK para `modules/common/` continua valendo — as três famílias a instanciam e o
módulo não importa nada da ii — mas ela **não é** o que resolve o desbloqueio.

### B2 — A OSK não sobe sozinha 🔴

`OskAutoShow.qml` é uma implementação **boa** — correlaciona `zwp_input_method_v2` com
eventos de `/dev/input` para distinguir foco por dedo de foco por mouse, tem grace period,
não fecha um teclado que o usuário abriu à mão. Nada errado com o código.

O problema é que ela **não está ligada nem instalada**:

| Evidência | Onde |
|---|---|
| Desligada por padrão | `modules/common/Config.qml` — `osk.autoShow.enable: false` |
| O binário não existe — só o fonte | `ls scripts/osk/` → `osk_autoshow_src/`, `README.md`. Sem `osk_autoshow` |
| Nenhuma UI de build | `TouchGesturesConfig.qml` tem `codeSnippet` para compilar o `touch_gestures`; a página de OSK não tem equivalente |
| Não aparece na página Tablet | `TabletConfig.qml` cobre shade, dock, home e gestos — não cobre teclado |

Sem isso, num tablet, **tocar num campo de texto não faz nada**. O usuário tem que saber que
existe uma gaveta, achar "On-screen Keyboard" nela, e abrir na mão — antes de cada campo.

**Correção:** default `true` quando `PanelFamily.touchFirst`; um cartão de build na página
Tablet no mesmo padrão do `TouchGesturesConfig`; e o estado do helper visível (o
`OskAutoShow` já emite `unavailable` quando outro input method segura o seat — hoje isso só
vai para o log).

### B3 — O botão Home não leva à sua home screen 🔴

`TabletNavigation.home()` despacha `workspace = 'empty'`. Isso vai para o **primeiro workspace
vazio**, que muda conforme o que está aberto.

Mas os ícones da home são persistidos **por workspace**
(`TabletHomeIcons.iconsFor(workspaceId)`, `Persistent.states.tablet.homeIconsJson`). E
adicionar da gaveta usa `TabletHomeIcons.currentWorkspace`, que é o workspace focado —
que pode estar cheio de janelas.

O resultado prático:

```
workspace 1: [Firefox]              ← você configurou seus ícones aqui
workspace 2: (vazio)
workspace 3: (vazio)

toca Home → vai para o workspace 2 → tela vazia, sem os seus ícones
```

No Android, Home **sempre** volta para a mesma página do launcher. Aqui ele volta para uma
tela em branco aleatória, e os ícones que o usuário posicionou ficam inalcançáveis atrás
das janelas do workspace onde foram criados.

**Correção:** a família precisa de um conceito de *home workspace* — o primeiro workspace do
monitor é a home. `home()` vai para ele; um segundo toque em Home (como no Android) vai para
a gaveta. Adicionar da gaveta escreve no home workspace, não no focado.

### B4 — Recentes não mostra os recentes 🔴

`TabletRecentsContent.qml`:

```qml
readonly property var windows: {
    const list = [];
    for (const toplevel of (ToplevelManager.toplevels?.values ?? [])) { ... }
    return list.reverse();
}
```

O comentário diz *"Most recently focused last in ToplevelManager's order"*. Isso está
errado: `ToplevelManager.toplevels` está em **ordem de criação**, e ativar uma janela não a
reordena. O que a tela mostra é "aberto mais recentemente", não "usado mais recentemente" —
que é exatamente a informação que uma tela de recentes existe para dar.

O dado certo já está no projeto e já é usado em quatro lugares: `focusHistoryID` do
`HyprlandData.windowList` (`GlobalStates.qml`, `OverviewWidget.qml`,
`WindowManagementPanel.qml`, `TilingAssistant.qml`). `focusHistoryID === 0` é a janela
ativa; ordenar ascendente **é** a ordem MRU.

**Correção:** ordenar por `focusHistoryID`, casando `HyprlandData.windowList` com os
toplevels por `address`. Detalhes do reprojeto completo em §3.

### B5 — Não existe interface para trocar de panel family 🔴

Três famílias, uma troca a quente que funciona (`PanelFamilyLoader` em `shell.qml`
recarrega por URL), e **nenhuma UI**:

| Caminho | Onde | Descoberto por |
|---|---|---|
| `qs -c ii ipc call panelFamily cycle` | `shell.qml` | Ler o AGENTS.md |
| Keybind `panelFamilyCycle` | `shell.qml` | Ler o AGENTS.md |
| Settings | — | **não existe** |
| Welcome | — | **não existe** |

Confirmado por varredura: `grep -rn panelFamily modules/settings/` só encontra três `visible:`
que *escondem* controles quando a família é tablet. Ninguém pode escolher a família.

Além de não existir, o único caminho que existe é **cíclico**: para ir de `ii` a `waffle` o
usuário passa obrigatoriamente por `tablet`, recarregando duas famílias inteiras. Proposta de
design completa em §5.

---

## 3. Recentes — reprojeto para o padrão Android 16

### 3.1 O que o Pixel Tablet faz

| Elemento | Comportamento no Android 16 |
|---|---|
| Ordem | MRU estrito. O app atual é o primeiro card, à esquerda do centro. |
| Posição inicial | Carrossel **já rolado** para o app atual, não para o começo da lista. |
| Card | Snapshot + ícone e título **acima** do card, não dentro dele. |
| Toque no ícone | Abre menu: **Split screen**, **Pop-up / Free form**, **App info**, **Pause app**. |
| Ações sob o card | **Screenshot** e **Select** (seleção de texto no snapshot). |
| Fechar | Arrastar o card para cima. |
| Limpar tudo | Botão **Clear all** no fim do carrossel. |
| Taskbar | **Continua visível** por baixo; arrastar um app dela para um lado abre split. |
| Split pair | Dois apps em split aparecem como **um card só**, dividido. |
| Gaveta | Swipe para cima **dentro** de recentes abre a gaveta de apps. |
| Vazio | Ilustração + "No recent items". |

### 3.2 O que temos

| Elemento | Estado |
|---|---|
| Carrossel horizontal | ✅ |
| Snapshot por card (`ScreencopyView`, `live: false`) | ✅ |
| Ícone + título | ✅ mas **acima do snapshot, dentro do card** |
| Arrastar p/ cima fecha | ✅ com threshold generoso |
| Toque foca | ✅ com `deferredRequested` (bom achado do plano) |
| "New workspace" | ✅ |
| Estado vazio | ✅ `PagePlaceholder` |
| **Ordem MRU** | ❌ ordem de criação (B4) |
| **Posição inicial** | ❌ sempre `contentX = 0` |
| **Menu do ícone** | ❌ |
| **Clear all** | ❌ |
| **Split screen** | ❌ |
| **Screenshot / Select** | ❌ |
| **Taskbar visível** | ❌ dock é `WlrLayer.Top`, recentes é `Overlay` |
| **Cards agrupados por workspace** | ❌ lista plana |
| **Swipe up → gaveta** | ❌ |

### 3.3 Proposta

Em ordem de valor por linha de código:

**R1 — Ordem MRU e rolagem inicial** (P0, pequeno)
Ordenar por `focusHistoryID`. Casar toplevel ↔ cliente Hyprland por `address` — o mesmo
casamento que `GlobalStates` já faz. Depois de montar a lista, posicionar
`carousel.contentX` no card do app atual, não em zero. Sem isso, num tablet com dez janelas o
app que você acabou de sair está fora da tela.

**R2 — Menu do card** (P1, médio)
Tocar no ícone/título abre um `TabletMenuCard` — o componente único de menu que o commit
`980fbe8b0` já criou justamente para isso. Ações:

| Ação | Implementação em Hyprland |
|---|---|
| App info | abre o `.desktop` no visualizador / Settings |
| Fechar | `toplevel.close()` (já existe no swipe) |
| **Dividir à esquerda / direita** | mover a janela para o workspace ativo + `hl.dsp.window.*` de layout |
| Flutuar | `hl.dsp.window.float({ action = 'toggle' })` — já mapeado no registry |
| Tela cheia | `hl.dsp.window.fullscreen(...)` — idem |
| Mover para workspace | submenu |

As três últimas já existem como ações do `TouchGestureActionRegistry`; é reuso, não código
novo.

**R3 — Clear all** (P1, pequeno)
Pill no fim do carrossel, ao lado do "New workspace". Fecha todo toplevel listado. Precisa de
confirmação? No Android não tem — mas no Android os apps salvam estado. Aqui fecha editores.
**Recomendação: sem diálogo, mas com um `Undo` de 5s** no mesmo padrão do dismiss de
notificação, que o projeto já tem.

**R4 — Manter a dock visível** (P1, pequeno)
Duas opções: subir a dock para `Overlay` (arriscado — passa a competir com shade e gaveta),
ou a superfície de recentes desenhar sua **própria** fileira de dock no rodapé, reusando
`TabletDockButton`. **A segunda é a certa**: recentes é uma superfície `Overlay` de tela
cheia, e o Android desenha a taskbar *dentro* do Overview em vez de deixar a de baixo
aparecer. Também é o pré-requisito para arrastar um app da dock para dentro de um split.

**R5 — Split-screen a partir de recentes** (P2, grande — ver §6)
Depende de R2 e R4. É a maior lacuna funcional de tablet que temos, e a única que exige
pensar sobre o Hyprland em vez de sobre QML.

**R6 — Cards de par (split pair)** (P3)
Quando dois clientes tiled dividem um workspace, desenhar **um card** com os dois snapshots
lado a lado, e ativá-lo levar aos dois. Depende de R5 existir primeiro.

**R7 — Swipe up dentro de recentes abre a gaveta** (P2, pequeno)
Coerente com o Android e barato: recentes já é uma superfície própria; um handler de arrasto
vertical no fundo dela chama `GlobalStates.openAppDrawer`.

**R8 — Escala de foco no carrossel** (P3)
O card centrado 1.0, os vizinhos ~0.92 com opacidade menor. É o que dá ao carrossel do
Android a leitura de "pilha", e é uma propriedade derivada de `contentX` — barato.

---

## 4. Gestos, navegação e OSK

### 4.1 Matriz de gestos

| Gesto | Android 16 | Nós | Estado |
|---|---|---|---|
| ↓ da borda superior | Shade / quick settings | Shade, seguindo o dedo | ✅ `TabletShadeDragHandler` |
| ↑ da base | Home | **Gaveta de apps** | ⚠️ divergência deliberada — ver 4.2.a |
| ↑ da base **e segurar** | Recentes | — | ❌ `Fase 3e`, não feito |
| ↑ da base e arrastar de lado | Quick switch entre apps | — | ❌ |
| ← da borda direita | **Voltar** | Abre a shade (`rightEdge: "sidebarRight"`) | ❌ conflito — ver 4.2.b |
| → da borda esquerda | **Voltar** | Abre Intelligence (policies) | ❌ conflito |
| ← / → no corpo | Trocar de página da home | Trocar de workspace | ✅ `TabletWorkspaceDragHandler` |
| 3 dedos ← / → | (Samsung: voltar/multitarefa) | Trocar workspace | ✅ |
| 3 dedos ↑ / ↓ | (Samsung: screenshot) | Gaveta / shade | ✅ |
| 2 dedos ↓ na status bar | Quick settings direto | — | ❌ |
| Toque longo na home | Wallpaper & style | — | ❌ |

### 4.2 Achados

**a) A base abre a gaveta, não a home.** No Android, ↑ da base é *sempre* Home, e a gaveta é
um segundo ↑ a partir da home. Aqui ↑ vai direto para a gaveta
(`TabletAppDrawerDragHandler`). Não é um bug — é uma escolha, e é defensável num shell onde a
home é um workspace vazio. Mas ela **queima o gesto mais usado do Android** e é a razão pela
qual "↑ e segurar → recentes" nunca foi implementado: os dois gestos partem da mesma borda e
hoje não há como distingui-los. **Decisão do mantenedor necessária** (ver §9, Q1).

**b) As bordas laterais não voltam.** O plano lista "← / → da borda lateral → Voltar" como *a
fazer*. Na prática está pior que "a fazer": os defaults do `Config` são
`leftEdge: "sidebarLeft"` e `rightEdge: "sidebarRight"`, e a borda esquerda é **reivindicada**
pelo `TabletPoliciesDragHandler` para abrir Intelligence. Então na tablet hoje:

- borda esquerda → abre um chat de IA
- borda direita → abre a shade (que a borda de cima também abre)
- **voltar** → só existe no botão da dock

Num tablet Android, deslizar da lateral é o gesto de voltar, e é o segundo mais usado depois
do Home. A ação `back` já existe e já é vinculável — falta só ser o **default da família**.

Proposta de defaults por família (o plano já tem o mecanismo: o campo `families`):

| Borda | ii (hoje) | tablet (proposto) |
|---|---|---|
| `leftEdge` | `sidebarLeft` | **`back`** |
| `rightEdge` | `sidebarRight` | **`back`** |
| `topEdge` | `cheatsheet` | (reivindicado pela shade) |
| `bottomEdge` | `overview` | (reivindicado pela gaveta) |

E policies passa a ser alcançado pelo canto inferior esquerdo, ou pela gaveta — onde já está
como app. Um gesto de borda inteira para um chat de IA é caro demais.

**c) Sem indicador visual de voltar.** O Android desenha uma seta que cresce e "gruda" na
borda enquanto o dedo arrasta. Sem ela o usuário não sabe se armou o gesto. O
`TouchGestureService` já emite `gestureProgressChanged` e existe overlay de feedback
(`visualFeedback: true`) — falta a forma específica de seta.

**d) `edgeWidth: 24` é global.** O Android expõe a sensibilidade do gesto de voltar como uma
preferência de acessibilidade, com três níveis. Numa tela grande 24px é pouco; numa pequena é
muito. Deveria ser derivado do DPI e ajustável na página Tablet.

**e) Nada foi validado em hardware.** O próprio plano avisa (§Fase 4): esta máquina não tem
touchscreen, `hyprctl devices` não lista Touch. Vale para todos os gestos, inclusive os que
estão marcados ✅. **Nenhum item desta seção pode ser fechado sem um dispositivo real.**

**f) Ordem de `back` incompleta.** `TabletNavigation.back()` desempilha superfícies do shell
e para. Correto e bem documentado — mas não fecha diálogos da shade
(`TabletDashboardContent` tem doze `show*Dialog`), não fecha o menu de contexto da dock, e
não fecha a OSK. Num tablet, "voltar" com um diálogo aberto tem que fechar o diálogo.

### 4.3 OSK

Além de B1 e B2:

| Item | Estado |
|---|---|
| Deck em tela cheia, altura configurável | ✅ `heightPercent: 35` |
| Layout seguindo o Hyprland | ✅ |
| Glifos secundários (shift/AltGr) | ✅ |
| Fixar (pin) com zona exclusiva | ✅ |
| Auto-show ao focar campo | ⚠️ implementado, **desligado e sem binário** (B2) |
| Na lock screen | ❌ **impossível como layer-shell** (B1) |
| Reservar espaço quando não fixada | ❌ `exclusiveZone: pinned ? ... : 0` — não fixada, cobre o campo que você está digitando |
| Sugestão de palavra / autocorreção | ❌ |
| Teclado dividido (split) para digitar com polegares | ❌ — é *o* recurso de teclado de tablet no Android e no One UI |
| Teclado flutuante / redimensionável | ⚠️ o estilo "classic" é flutuante, mas não é o padrão nem é arrastável |
| Ditado por voz | ⚠️ `DictationService` existe, mas não tem tecla na OSK |
| Emoji na OSK | ❌ (existe painel de emoji na gaveta, o que não é a mesma coisa) |
| Haptics | ❌ — `grep -rn haptic` → nada no projeto |

O item de **teclado dividido** merece destaque: num tablet de 11" segurado com as duas mãos,
um teclado de largura total é inalcançável. Android e One UI oferecem split por padrão em
telas grandes.

O item de **zona exclusiva** é o mais barato e o mais irritante na prática: com o teclado não
fixado, ele cobre a metade inferior da tela — inclusive o campo de texto que o abriu. O
Android sempre empurra o conteúdo. Como a auto-show sabe quando *ela* abriu o teclado
(`OskAutoShow.autoShown`), dá para reservar espaço só nesse caso.

### 4.4 Checklist de validação em hardware

Nada em §4 pode ser marcado como pronto sem rodar isto num touchscreen:

```
[ ] hyprctl devices  →  lista uma seção "Touch Devices"
[ ] qs log -f -c ii | grep TouchGestures  →  "Device registered"
[ ] ↓ do topo abre a shade e ela segue o dedo (sem saltar no release)
[ ] ↑ da base abre a gaveta e ela segue o dedo
[ ] ← e → no wallpaper trocam workspace; ← e → sobre uma janela NÃO trocam
[ ] 3 dedos: ←/→ workspace, ↑ gaveta, ↓ shade — uma vez por mão apoiada
[ ] borda lateral volta (depois de 4.2.b)
[ ] tocar num campo de texto sobe o teclado (depois de B2)
[ ] bloquear e desbloquear a tela só com o dedo (depois de B1)
[ ] caneta/digitalizador: as mesmas bordas respondem (faixa de ponteiro)
```

---

## 5. Seletor de panel family

### 5.1 O que construir

Uma superfície irmã do `SessionScreen` — mesmo idioma visual, mesma coreografia de entrada,
mesmo dismiss. O `SessionScreen` já é o modelo certo: fundo escurecido com clique para
cancelar, coluna centrada com título e instrução, grade de botões grandes com cascata de
entrada (`SessionActionButton.animateIn()`), navegação por teclado com `KeyNavigation`.

Diferenças em relação ao `SessionScreen`, e por quê:

- **Cartões, não botões de ícone.** Trocar de família muda a tela inteira; um ícone de 64px
  não diz o que vai acontecer.
- **Seleção direta, não ciclo.** Três famílias, três alvos. O `cyclePanelFamily` continua
  existindo para o keybind; a UI não deve fazer o usuário passar por uma família que ele não
  quer só para chegar na terceira.
- **Marca a atual e não recarrega ao tocar nela.** `Config.options.panelFamily = X` com o
  valor que já está lá é um no-op, mas o usuário não sabe disso.

### 5.2 Onde ele é alcançado

| Entrada | Por quê |
|---|---|
| **Settings → uma página nova, "Shell"** | Onde alguém procura primeiro. Deve ser a **primeira** página, porque decide o que as outras páginas configuram. |
| **Linha de ações do sistema da shade** (`TabletSystemActionRow`) | Já tem avatar, lápis, engrenagem e power. Um ícone de "trocar interface" pertence a esse grupo. |
| **Welcome, na página de experiência** | Um primeiro boot que não pergunta isso escolhe pelo usuário. |
| **Ação vinculável** no `ShellActionRegistry`/`TouchGestureActionRegistry` | Hoje o `panelFamilyCycle` é um `GlobalShortcut` solto, fora do registry — então não pode ser vinculado a gesto nem aparece no seletor de ações do Settings. |
| **`SessionScreen`** | Um botão "Trocar interface" ao lado de Lock/Sleep/Logout, já que a metáfora é a mesma. |

### 5.3 Cuidados

- **A troca é a quente e funciona**, mas destrói e reconstrói todas as superfícies. Precisa de
  um estado de transição visível — a tela não pode simplesmente piscar por 1–2s sem explicação.
- **Nenhuma preferência guardada pode ser reescrita.** É a regra do §3.2 do plano e ela vale
  aqui em dobro: trocar de família não pode tocar em `bar.position`, `dock.*` nem
  `bar.cornerStyle`. Se o seletor gravar qualquer coisa além de `panelFamily`, é bug.
- **`restrictedCustomization` esconde seções inteiras do Settings** na tablet. A página do
  seletor não pode ser uma delas, senão o usuário fica sem saída pela UI — exatamente o
  problema que a página existe para resolver.
- A superfície deve **existir nas três famílias**. Vive em `modules/common/`, não em
  `modules/tablet/`.

---

## 6. Comparação de recursos — Android 16 e One UI

Só o que é relevante para um shell de desktop com touchscreen. "Não fazer" é uma resposta
legítima e está marcada como tal.

### 6.1 Multi-janela — a maior lacuna

| Recurso | Android 16 / One UI | Nós | Veredito |
|---|---|---|---|
| Split screen 2 apps | Do recentes ou da taskbar | Hyprland faz tiling, mas **nenhuma UI de toque pede um split** | 🟠 **Fazer** |
| Split 3 apps / grade | One UI | — | 🔵 Não fazer — o tiling do Hyprland já cobre |
| Divisor arrastável | Ambos | Redimensionar tiled só por teclado/mouse | 🟠 **Fazer** — alça de toque no divisor |
| App pair (atalho de par) | One UI | — | 🟡 Fazer depois do split |
| Pop-up view (janela flutuante) | Ambos | `toggleFloating` existe como ação | 🟡 **Adaptar** — expor no menu do card de recentes |
| Desktop windowing | Android 16, estável em tablet | O Hyprland *é* isso | ✅ Já temos, de graça |
| Arrastar app da taskbar p/ split | Ambos | — | 🟠 Fazer (depende de R4) |
| Arrastar e soltar entre apps | Ambos | Depende dos apps + Wayland | 🔵 Não fazer — fora do escopo do shell |

**Por que "fazer" o split apesar de o Hyprland já ladrilhar:** ladrilhar é o que acontece
quando você abre o segundo app. O que falta é **escolher** qual segundo app, com o dedo,
partindo do primeiro. Isso é um fluxo de UI, não um recurso de compositor.

### 6.2 Home screen e launcher

| Recurso | Android / One UI | Nós | Veredito |
|---|---|---|---|
| Grade de ícones em páginas | ✅ | ✅ por workspace | ✅ (com a ressalva B3) |
| **Pastas** (soltar ícone em ícone) | ✅ | ❌ adiado no plano §3b | 🟡 Fazer |
| Arrastar ícone entre páginas | ✅ | ❌ adiado | 🟡 Fazer |
| Widgets na home | ✅ | ✅ o `WidgetCanvas` é isso | ✅ |
| Toque longo na home → papel de parede/estilo | ✅ | ❌ | 🟡 Fazer — barato, e é onde todo usuário de Android procura |
| **Sugestões de app** (linha de preditos) | ✅ | ❌ | 🟡 Fazer — `AppStats` já coleta uso |
| Índice A–Z / rolagem rápida na gaveta | ✅ | ❌ | 🟠 Fazer |
| Busca na gaveta | ✅ | ✅ + ferramentas (melhor que o Android) | ✅ |
| At a Glance (clima/agenda no topo da home) | ✅ | ⚠️ existe como widget de desktop | 🔵 Já coberto |
| Dock/taskbar com recentes | ✅ | ✅ | ✅ |

### 6.3 Notificações e quick settings

| Recurso | Android / One UI | Nós | Veredito |
|---|---|---|---|
| Split shade em tela grande | ✅ | ✅ | ✅ excelente |
| Deslizar para dispensar | ✅ | ✅ `NotificationItem.qml` | ✅ |
| Agrupar por app | ✅ | ✅ | ✅ |
| Ações inline / resposta rápida | ✅ | ⚠️ ações sim; resposta inline não | 🟡 Fazer |
| Notificações na lock screen | ✅ | ✅ `LockNotifications.qml` | ✅ |
| Editor de tiles | ✅ | ✅ (melhor: layout livre) | ✅ |
| **Brilho adaptativo** | ✅ | ❌ | 🟡 Fazer — precisa de sensor ALS |
| **Tile de rotação automática** | ✅ | ❌ (sem retrato, D5) | ⏸️ Ver Q2 |
| Slider de brilho na shade | ✅ | ✅ | ✅ |
| Mídia na shade | ✅ | ✅ | ✅ |

### 6.4 Sistema e hardware

| Recurso | Android / One UI | Nós | Veredito |
|---|---|---|---|
| **Desbloqueio por toque (PIN pad)** | ✅ | ❌ | 🔴 **B1** |
| Biometria | ✅ | ⚠️ `fprintd` via polkit, na lock | 🟡 |
| **Hub Mode / dock de carregamento** | Pixel Tablet: vira porta-retrato / smart display ao encaixar | ⚠️ `OledSaver` é o mais próximo | 🟡 **Fazer** — é *o* recurso do Pixel Tablet, e o projeto já tem meteorologia, agenda, mídia e relógio para preencher |
| Rotação / retrato | ✅ | ❌ por decisão (D5) | ⏸️ Q2 |
| S-Pen / caneta | One UI | ⚠️ caneta reconhecida nas bordas | 🔵 |
| Modo criança / múltiplos usuários | ✅ | ❌ | 🔵 Não fazer |
| Modo uma mão | ✅ | ❌ | 🔵 Não fazer em tablet |
| **Screenshot de tela cheia por gesto** | 3 dedos ↓ (One UI) | ⚠️ ação existe, não é default | 🟡 Fazer |
| Gravação de tela | ✅ | ✅ | ✅ |
| Edge panel (painel lateral) | One UI | ⚠️ borda esquerda abre policies | 🔵 Já coberto de outro jeito |
| Modo DeX (externo) | One UI | ✅ é literalmente trocar para a família ii | ✅ — **e é o argumento mais forte para o seletor de §5** |

> A última linha vale ser lida duas vezes. O que a Samsung vende como DeX — "encaixe o tablet
> e ele vira um desktop" — este projeto já tem, porque tem três famílias e uma troca a quente.
> Falta só um botão. É o melhor retorno por linha de código de toda a auditoria.

---

## 7. UI/UX por superfície (a partir dos prints)

### 7.1 Home + status bar

O que está bom: dock sem fundo direto no wallpaper, indicador de páginas acima dela, botões
de navegação com as formas certas do Android, setas de workspace nas pontas, pill de busca à
esquerda.

| Achado | Severidade |
|---|---|
| A bar mostra **workspaces numerados** (1 2 3 4 5) — metáfora de desktop. O Android mostra hora à esquerda e status à direita. As páginas já são indicadas pelos pontinhos acima da dock; o widget da bar é redundante. | 🟡 |
| O relógio central está renderizado como dois blocos sobrepostos (`22`/`39`) e disputa atenção com o widget grande de relógio no canto superior direito do wallpaper. Dois relógios. | 🔵 |
| A bar tem **muito ícone de sistema** à direita (9 elementos). O Android agrupa em ~4 e o resto vive na shade. Como a shade já é ótima, a bar pode encolher. | 🔵 |
| Não há afordância visível para puxar a shade — o Android também não tem, mas ele ensina no onboarding. O Welcome poderia. | 🔵 |

### 7.2 Gaveta de apps

| Achado | Severidade |
|---|---|
| **~12–13 colunas.** `tileWidth` é `clamp(96, 148, width/8)` → 148px em 1920. O Pixel Tablet usa 6. Isso é densidade de menu de desktop, não de gaveta de tablet. | 🟠 |
| Ícones a `tileWidth * 0.52` em placas de 148px — a placa é grande e o glifo é pequeno, o mesmo problema que o commit `980fbe8b0` corrigiu na bar. | 🟠 |
| **Sem índice A–Z / rolagem rápida.** Com centenas de apps numa lista alfabética, chegar em "Zoom" é uma rolagem longa. | 🟠 |
| **Sem linha de sugestões** antes de digitar — o próprio plano lista isso como pendente (§3d), e `AppStats` já tem o dado. | 🟡 |
| Nomes truncados em duas linhas ("Alienware Command Center") empurram a linha inteira. | 🔵 |
| Apps duplicados visíveis no print (ChatGPT ×2, Cockpit Tools ×3, Contacts ×2, Cisco ×2). Não é problema da tablet — é o índice de `.desktop` — mas numa grade de toque é mais visível. | 🟡 |
| Sem paginação horizontal. Android pagina a gaveta lateralmente; aqui rola verticalmente. Defensável, mas o indicador de scroll é fraco. | 🔵 |

### 7.3 Ferramentas hospedadas na gaveta

O print do File Browser mostra o problema central da decisão D1: as ferramentas são painéis
da ii, desenhados para ponteiro e teclado, dentro de um contêiner de toque.

| Achado | Severidade |
|---|---|
| **Rodapé de dicas de teclado** — "Browse ↵ · Actions Ctrl K · Mark Ctrl Space · Back Backspace" — num shell onde a premissa é não haver teclado. | 🟠 |
| Linhas de lista com ~52px de altura e chevrons de ponteiro. | 🟠 |
| Layout mestre-detalhe de duas colunas com o painel de detalhe quase vazio, ocupando metade de uma tela de 1920px. | 🟡 |
| O painel de detalhe mostra permissões `drwxr-xr-x 0755` e owner — informação de terminal numa superfície de tablet. | 🔵 |

Isto é a Fase 5 pendente ("revisar o layout *interno* dos diálogos"), e vale para todas as
ferramentas hospedadas. **Recomendação:** em vez de adaptar cada uma, adicionar ao contêiner
de ferramentas uma capability `touchFirst` que as ferramentas leem para esconder rodapés de
atalho e trocar densidade — uma mudança, N ferramentas.

### 7.4 Shade

A superfície mais próxima da paridade. Split shade correto, tiles grandes com rótulo e
subtítulo (melhor que o Android, que só mostra o rótulo), calendário/tarefas/pomodoro como
tiles reais, linha de ações do sistema no rodapé, notificações agrupadas com contador.

| Achado | Severidade |
|---|---|
| Os dois sliders do topo (brilho e volume) não têm **ícone dentro da trilha**, então uma trilha quase vazia e uma quase cheia parecem dois estados do mesmo controle sem dizer de quê. O Android põe o glifo dentro do slider. | 🟡 |
| A coluna de notificações usa ~50% da largura para 3 notificações, enquanto a de toggles está apertada. Uma arbitragem por ocupação (`SpaceArbitration.js` já existe) resolveria. | 🔵 |
| O rodapé "6 apps are active" com chevron é bom (padrão do Android 14+), mas está do lado da coluna errada — no Android fica junto às notificações. | 🔵 |
| Não há gesto para expandir quick settings — aqui já vem tudo expandido, que é a escolha certa para tablet. | ✅ |

### 7.5 Recentes

Coberto em §3. Do print especificamente:

| Achado | Severidade |
|---|---|
| Os cards começam colados na borda esquerda e o quarto está **cortado** pela direita, sem nenhuma dica de que há mais. | 🟠 |
| Todos os cards no mesmo tamanho e opacidade — nada indica qual é o app atual. | 🟠 |
| Muito espaço vertical vazio (cards ocupam ~30% da altura). O Android usa cards bem maiores. | 🟡 |
| "New workspace" está bom, mas sozinho — falta o par natural "Clear all". | 🟠 |

---

## 8. Backlog priorizado

Coluna **St**: ⬜ a fazer · 🟨 em andamento · ✅ feito.

| # | St | Item | Sev | Esforço | Arquivos principais |
|---|---|---|---|---|---|
| 1 | ✅ | Teclado de toque na lock screen (dentro da lock surface) | 🔴 P0 | M | `common/panels/lock/LockTouchKeyboard.qml`, `ii/lock/LockSurface.qml` |
| 2 | ✅ | Camada PIN numérica no mesmo teclado | 🔴 P0 | P | idem, `lock.touchKeyboard.mode` |
| 3 | ⬜ | Auto-show da OSK ligada por padrão + build do helper na UI | 🔴 P0 | P | `common/Config.qml`, `settings/configs/TabletConfig.qml`, `scripts/osk/` |
| 4 | ⬜ | Recentes em ordem MRU + rolar até o app atual | 🔴 P0 | P | `tablet/recents/TabletRecentsContent.qml` |
| 5 | ⬜ | Home workspace determinístico | 🔴 P0 | M | `tablet/navigation/TabletNavigation.qml`, `tablet/homeScreen/TabletHomeIcons.qml` |
| 6 | ⬜ | Seletor de panel family (superfície + entradas) | 🔴 P0 | M | novo em `modules/common/`, `settings/`, `welcome/`, `TabletSystemActionRow.qml` |
| 7 | ⬜ | `back` nas bordas laterais como default da tablet | 🟠 P1 | P | `common/Config.qml`, `TabletPoliciesDragHandler.qml` |
| 8 | ⬜ | Menu do card de recentes (info, fechar, flutuar, dividir) | 🟠 P1 | M | `tablet/recents/`, `tablet/menu/TabletMenuCard.qml` |
| 9 | ⬜ | "Clear all" em recentes, com undo | 🟠 P1 | P | `tablet/recents/TabletRecentsContent.qml` |
| 10 | ⬜ | Dock desenhada dentro de recentes | 🟠 P1 | M | `tablet/recents/`, `tablet/dock/TabletDockButton.qml` |
| 11 | ⬜ | Densidade da gaveta (~6–7 colunas, ícones maiores) | 🟠 P1 | P | `tablet/appDrawer/TabletAppDrawerContent.qml` |
| 12 | ⬜ | Índice A–Z / rolagem rápida na gaveta | 🟠 P1 | M | `tablet/appDrawer/` |
| 13 | ⬜ | Ferramentas hospedadas sem afordância de teclado | 🟠 P1 | M | contêiner de ferramentas + capability |
| 14 | ⬜ | OSK reserva espaço quando aberta por auto-show | 🟠 P1 | P | `common/onScreenKeyboard/`, `services/OskAutoShow.qml` |
| 15 | ⬜ | Split-screen a partir de recentes / dock | 🟠 P1 | G | recentes, dock, dispatchers do Hyprland |
| 16 | ⬜ | Seta de feedback no gesto de voltar | 🟡 P2 | M | `ii/touchGestures/` |
| 17 | ⬜ | `back` fecha diálogos e menus antes de superfícies | 🟡 P2 | P | `tablet/navigation/TabletNavigation.qml` |
| 18 | ⬜ | "↑ e segurar" → recentes (depende de Q1) | 🟡 P2 | M | `TabletAppDrawerDragHandler.qml`, `TouchGestureService.qml` |
| 19 | ⬜ | Teclado dividido (split keyboard) | 🟡 P2 | G | `common/onScreenKeyboard/DeckContent.qml` |
| 20 | ⬜ | Sugestões de app na gaveta e na home | 🟡 P2 | M | `tablet/appDrawer/`, `services/AppStats` |
| 21 | ⬜ | Toque longo na home → wallpaper & estilo | 🟡 P2 | P | `tablet/homeScreen/TabletHomeIconsLayer.qml` |
| 22 | ⬜ | Pastas e arrastar ícone entre páginas | 🟡 P2 | M | `tablet/homeScreen/` |
| 23 | ⬜ | Hub Mode (dock de carregamento vira display ambiente) | 🟡 P2 | G | novo; reusa `OledSaver` + widgets |
| 24 | ⬜ | Alça de toque no divisor de janelas tiled | 🟡 P2 | M | fora do shell — precisa de decisão |
| 25 | ⬜ | Ícones dentro das trilhas dos sliders da shade | 🔵 P3 | P | `common/quickToggles/` |
| 26 | ⬜ | Escala de foco e centralização no carrossel de recentes | 🔵 P3 | P | `tablet/recents/` |
| 27 | ⬜ | Bar sem workspaces numerados em família touch-first | 🔵 P3 | P | `settings/configs/BarConfig.qml`, defaults |
| 28 | ⬜ | Quick-switch (arrastar de lado na base) | 🔵 P3 | G | serviço de gestos |
| 29 | ⬜ | Sensibilidade da borda ajustável / por DPI | 🔵 P3 | P | `common/Config.qml`, `TabletConfig.qml` |
| 30 | ⬜ | Haptics em toque longo e commit de gesto | 🔵 P3 | M | novo serviço |

**Ordem de execução:** 1–6 (bloqueadores) → 7, 9, 11, 14, 17 (tudo pequeno, muito retorno) →
4/8/10 fecham recentes → 12, 13, 15 → o resto.

---

## 9. Decisões que precisam do mantenedor

Não implementar nada nesta seção sem resposta — cada uma tem duas saídas defensáveis e a
escolha errada custa retrabalho.

**Q1 — ↑ da base abre a gaveta ou a home?**
Hoje abre a gaveta. O Android abre a home, e a gaveta é o segundo ↑. Manter como está fecha a
porta para "↑ e segurar → recentes" (item 18), porque os dois partem da mesma borda. Trocar
para o padrão Android exige que a home seja um destino determinístico — ou seja, depende de
B3 estar resolvido. *Recomendação: resolver B3, depois adotar o padrão Android.*

**Q2 — Retrato / rotação continua fora?**
A decisão D5 diz "sem modo retrato". Faz sentido para laptops com touchscreen, que não giram.
Não faz sentido nenhum para um tablet de verdade, que é o alvo declarado deste documento — e
o plano cita celulares como hardware alvo. Não estou pedindo para reabrir; estou registrando
que **é a maior divergência estrutural** em relação às duas referências de produto, e que ela
cresce de custo a cada superfície nova que assume paisagem.

**Q3 — Split-screen é escopo do shell?**
O Hyprland já ladrilha. O que falta é a UI para escolher o par com o dedo (item 15). Isso
significa o shell despachando layout, que é território do compositor. *Recomendação: fazer,
limitado a "dividir com a janela ativa" a partir de recentes — sem gerenciador de layout
próprio.*

**Q4 — Ferramentas hospedadas: adaptar cada uma ou dar capability ao contêiner?**
São ~14 painéis. Adaptar um a um é previsível e caro; uma capability `touchFirst` lida por
cada painel é barata e espalha leitura de política por `modules/ii/`, o que o §3.1 do plano
proíbe fora de `modules/common/`. *Recomendação: capability no contêiner + as ferramentas
lendo do contêiner, não de `PanelFamily` — assim a política atravessa por parâmetro, como
`baseCellHeight` já faz.*

---

## 10. Riscos e o que não fazer

- ❌ **Não tentar resolver B1 removendo `!GlobalStates.screenLocked` da OSK.** O session lock
  cobre todas as camadas do layer-shell por protocolo; o teclado tem que ser filho da lock
  surface. Ver B1.
- ❌ **Não subir a dock para `Overlay`** para resolver §3 R4. Ela passaria a competir com
  shade e gaveta, que são superfícies modais. Desenhar uma fileira de dock *dentro* de
  recentes é mais código e menos risco.
- ❌ **Não reescrever a preferência do usuário** ao trocar de família (§5.3). Vale
  especialmente para o item 27: se a bar da tablet deixa de mostrar workspaces, isso é um
  *default de família* resolvido na renderização, não uma edição do `config.json`.
- ❌ **Não fechar nenhum item de gesto sem hardware.** O §4.4 existe por isso.
- ⚠️ **Binding loop apaga a página inteira** (armadilha registrada na Fase 6 do plano). Os
  itens 3, 11 e 29 mexem em spin boxes que leem defaults derivados de família — o padrão
  `Appearance.familyWidgetGridStep` existe exatamente para esse caso; usar.
- ⚠️ **`ListModel` sem `dynamicRoles: true` descarta escritas em silêncio** (bug real da Fase
  2). Vale para qualquer modelo novo em recentes ou na gaveta.
- ⚠️ **`AbstractButton.action` é FINAL.** Um `property string action` num descendente de
  `RippleButton` faz o tipo inteiro ficar *unavailable*, e o erro aparece três arquivos acima,
  no consumidor. Custou uma iteração no item 1.

---

## 11. Como validar

```bash
# camadas — tem que continuar em zero
./scripts/dev/check-panel-family-layering.sh

# instância única antes de qualquer coisa
qs list --all --no-color

# restart limpo e erros reais do boot (não o ring buffer)
ii-restart && sleep 12 && qs log -c ii -t 80 | grep -iE "ERROR|unavailable"

# as superfícies certas
hyprctl layers | grep namespace

# ida e volta entre famílias sem regressão na ii
qs -c ii ipc call panelFamily cycle

# o helper de teclado (depois do item 3)
ls scripts/osk/osk_autoshow && qs log -c ii -t 50 | grep OskAutoShow

# touchscreen presente (obrigatório para tudo em §4)
hyprctl devices | grep -A5 "Touch Devices"
```
