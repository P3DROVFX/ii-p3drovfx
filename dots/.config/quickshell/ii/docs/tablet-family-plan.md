# Plano — Tablet Panel Family

> **Referência de produto:** Google Pixel Tablet rodando Android 16.
> O objetivo é uma cópia funcional fiel, preservando apenas os elementos de identidade
> visual do ii que fazem sentido em tela de toque (principalmente os múltiplos designs
> de bar).

> **Status:** Fase 0 concluída (merge com `dev` + isolamento arquitetural + limpeza).
> Fases 1 a 7 são o trabalho futuro descrito aqui.

---

## 1. Por que este documento existe

A tablet family nasceu herdando o `IllogicalImpulseFamilyBase`, um composition root
compartilhado com a ii. Isso funcionou para chegar rápido a algo utilizável, mas criava
duas dívidas que só piorariam com o tamanho:

1. **Todo painel novo da ii aparecia na tablet sem revisão.** A tablet não escolhia sua
   superfície — ela recebia a da ii e desligava o que não queria, de dentro da ii.
2. **Todo requisito da tablet empurrava um parâmetro para dentro da ii.** `sizeScale`,
   `touchScale`, `zoom`, `placeholderScale`, `revealProgress`, `entranceOnOpen`,
   `baseCellHeight` — parâmetros com default identidade que só a tablet usa, espalhados
   por arquivos que a ii precisa continuar evoluindo.

A regra que este plano estabelece:

> **A tablet family não deve exigir edições em `modules/ii/`.**
> Quando ela precisa de um componente da ii, ou ele é *promovido* para `modules/common/`
> (sem mudar comportamento para a ii), ou é *reescrito* em `modules/tablet/`.

---

## 2. Arquitetura de camadas

```
                    ┌──────────────────────────────────────────┐
  composition       │  panelFamilies/IllogicalImpulseFamily    │
  roots             │  panelFamilies/TabletFamily              │  ← únicos que podem
                    │  panelFamilies/WaffleFamily              │    misturar famílias
                    └──────────────────────────────────────────┘
                                       │
       ┌───────────────────────────────┼───────────────────────────────┐
       ▼                               ▼                               ▼
  modules/ii/                    modules/tablet/                 modules/waffle/
       │                               │                               │
       └───────────────────────────────┼───────────────────────────────┘
                                       ▼
                            modules/common/   (widgets, singletons, registries)
                                       ▼
                            services/          (estado, IPC, daemons)
```

### As três regras

| # | Regra | Por quê |
|---|-------|---------|
| 1 | `services/` e `modules/common/` **não importam nenhuma família** | São compartilhados por todas. Um serviço que conhece uma família não pode ser raciocinado sem ela, e essa família nunca mais pode ser deletada. |
| 2 | `modules/tablet/` **não importa `qs.modules.ii.*`** | Emprestar componente da ii é permitido, mas só a partir de `panelFamilies/TabletFamily.qml`, para a dívida ficar contável em um arquivo só. |
| 3 | `modules/ii/` **não importa `qs.modules.tablet.*`** nem waffle | Mesma razão da regra 1, na direção contrária. |

### Como as regras são cobradas

```bash
./scripts/dev/check-panel-family-layering.sh
```

Falha em qualquer violação **nova**. As conhecidas ficam em
`scripts/dev/panel-family-layering-baseline.txt` — são dívida registrada, não permissão.
O script também avisa quando uma entrada do baseline deixa de ocorrer, para ser removida.

Rodar antes de todo commit que toque em `panelFamilies/`, `modules/tablet/` ou
`modules/common/`.

### O padrão sancionado para "a tablet precisa de algo diferente"

Quando código compartilhado precisa se comportar de outro jeito na tablet, **não** teste
`Config.options.panelFamily === "tablet"` no local de uso. Adicione uma *capability* ao
singleton de política e leia a capability:

| Singleton | Responde | Exemplo |
|-----------|----------|---------|
| `PanelFamily` | qual família roda e o que ela impõe | `PanelFamily.touchFirst`, `.pinsBarToTop`, `.restrictedCustomization` |
| `BarPlacement` | onde a bar **está** (≠ onde a config diz) | `BarPlacement.vertical`, `.bottom` |
| `BarInteraction` | como a bar é **operada** | `BarInteraction.clickToShow`, `.autoHide`, `.enablePopups` |

A preferência persistida nunca é reescrita — trocar de família não pode alterar a config
do usuário. O Settings continua lendo e escrevendo `Config` diretamente.

---

## 3. Fase 0 — concluída

### 3.1 Merge com `dev`

`agent/tablet-family-base` estava 521 commits atrás de `origin/dev`. Merge feito com 14
conflitos resolvidos:

| Arquivo | Resolução |
|---|---|
| `Config.qml` | Uniu `panelFamily` com `tablet` + `ai.tools.mode` do dev |
| `PagePlaceholder.qml` | Manteve `titlePixelSize`/`descriptionPixelSize` do dev **e** o `sizeScale` da branch, multiplicando um pelo outro |
| `BarWindow.qml` | `hoverTriggered` do dev + `effectiveBarHeight` da branch |
| `BluetoothConnectionPopup`, `ColorPickerPopup`, `LocalSendPopup` | Lado do dev (`sidebarPush`, que segue a sidebar em vez de fechar o popup) com `BarPlacement` no lugar de `Config.options.bar.*` |
| `Overview.qml`, `WrappedFrameVisuals.qml` | Idem |
| `NotificationList.qml` | Refatoração de `collapsed`/`SpaceArbitration` do dev + as duas props de host touch |
| `AndroidSliderWidgetBase.qml` | Split horizontal/vertical do dev, com `touchScale`/`scaled()` reaplicados na estrutura nova |
| `AndroidQuickPanel.qml` | Entrance do dev (dirigido por `SidebarDashboardContent`) + os estágios de `reveal` da branch |
| `BarConfig`, `SidebarsConfig` | Versão do dev + os controles de tablet reaplicados |
| `IllogicalImpulseFamily.qml` | Ver 3.2 |

**Defeito encontrado no merge:** o dev refatorou `PanelFamilyLoader` para carregar famílias
por URL (`familyUrl` + `active: wanted && source !== ""`), mas o loader da tablet continuou
usando a forma antiga `component: TabletFamily {}`. Sem `familyUrl`, `source` ficava vazio e
`active` permanentemente falso — **a tablet family não estava carregando de jeito nenhum**.
O git fez auto-merge sem conflito porque as edições estavam em posições diferentes do
arquivo. Corrigido.

### 3.2 Composition root próprio

- `panelFamilies/IllogicalImpulseFamilyBase.qml` **deletado**.
- `IllogicalImpulseFamily.qml` voltou a ser dono da própria lista (mais próximo do dev →
  menos conflito futuro), com apenas as substituições `BarPlacement`.
- `TabletFamily.qml` passou a listar explicitamente suas superfícies, cada omissão
  anotada com o motivo.

### 3.3 Limpeza — o que a tablet family não carrega mais

| Removido | Motivo |
|---|---|
| **Dock** | Será substituída pela dock do Android (Fase 3) |
| **Dynamic Island** | A bar é status bar fixa; notch não tem papel |
| Screen corners | Hot-zone de canto é afordância de ponteiro; bordas são gestos |
| Vertical bar | Bar fixada no topo |
| Wrapped frame | Cromo de desktop |
| TopLayer / Connect mode | Connect é um shell mode de desktop |
| Tiling assistant (3 painéis) | Arrastar janela para grid precisa de ponteiro |
| Scratchpad overlay | Gerenciamento de janela de desktop |
| Cheatsheet | Referência de atalhos de teclado, em aparelho sem teclado |
| Keypress display | Auxiliar de screencast de teclado |
| Keyboard layout popup | Troca de layout pertence ao teclado virtual |
| Usage overlay | Superfície de diagnóstico de desktop |
| Modes / ModeFlash | Automação de desktop — revisitar quando houver lugar na UI |
| Game/widget overlay | Superfície de desktop |
| Color picker popup | Utilitário de desktop |
| Video editor | Aplicativo de desktop |

Verificado em runtime: `hyprctl layers` na tablet mostra `quickshell:bar` em `y=0`,
`quickshell:tabletShade`, `quickshell:background` — **sem** `quickshell:dock` e **sem**
`quickshell:screenCorners`.

### 3.4 Bar fixa no topo + popups só no toque

- `BarPlacement.familyPinsBarToTop` já vinha da branch; agora lê `PanelFamily.pinsBarToTop`.
- `BarInteraction` novo: em família touch-first, `clickToShow` e `enablePopups` são
  forçados `true` e `autoHide` forçado `false`.
- Varredura mecânica de 44 arquivos: `Config.options.bar.tooltips.clickToShow` →
  `BarInteraction.clickToShow`. Mesma classe de mudança que a varredura `BarPlacement`
  que a branch já tinha feito, e uma melhoria para a ii em si (uma fonte de política em
  vez de 44 leituras diretas).

### 3.5 Inversão da dependência `services/ → modules/tablet/`

`TouchGestureService` importava `qs.modules.tablet.sidebarDashboard` e tinha quatro blocos
`if (Config.options.panelFamily === "tablet" && origin === "topEdge")`.

Agora: `modules/common/TouchGestureDragRegistry.qml` define um contrato genérico de *drag
contínuo* (`claims`/`begin`/`update`/`release`/`cancel`/`actionId`).
`modules/tablet/sidebarDashboard/TabletShadeDragHandler.qml` implementa o contrato e se
registra a partir do `TabletFamily.qml`. O serviço não sabe mais que existe uma família
tablet.

> Este é o **exemplo de referência** para toda inversão futura de dependência.

### 3.6 Settings com escopo por família

`SettingsPageRegistry` ganhou campo opcional `families`. Páginas de superfícies que a
família não renderiza (`dock`, `dynamicIsland`, `cheatSheet`, `tiling`, `modes`) saem da
sidebar e do ciclo de teclado, em vez de mostrar switches inertes. Os índices do array
plano continuam estáveis entre famílias, então deep links e `pageIndexById()` não quebram.
Grupos que ficariam vazios somem inteiros.

---

## 4. Dívida atual (burn-down)

`scripts/dev/panel-family-layering-baseline.txt` — 16 entradas.

| Arquivo | Importa | Resolução planejada |
|---|---|---|
| `TabletDashboardContent.qml` | 14× `qs.modules.ii.sidebarDashboard.*` | **Fase 2** — promover quick toggles, diálogos e notification list para `modules/common/` |
| `TabletTrayDialog.qml` | `qs.modules.ii.bar.widgets.tray` | **Fase 2** — promover o modelo de tray |
| `modules/common/widgets/CalendarView.qml` | `qs.modules.waffle.looks` | Pré-existente, não relacionado à tablet. Corrigir junto |

### Parâmetros com default-identidade ainda dentro da ii

Cada um é um lugar onde a tablet empurrou configuração para a ii. Devem sumir conforme a
tablet ganha componentes próprios:

| Local | Parâmetro | Quem usa |
|---|---|---|
| `modules/ii/bar/Bar.qml`, `bar/core/BarWindow.qml` | `sizeScale` / `effectiveBarHeight` | **ninguém** — resto de uma abordagem abandonada. Remover já na Fase 1 |
| `modules/ii/bar/Bar.qml` | `forceTop` | `TabletFamily` — legítimo, pode ficar |
| `AndroidQuickPanel.qml` | `baseCellHeight`, `revealProgress`, `stageReveal()`, `entranceOnOpen` | tablet shade → some na Fase 2 |
| `AndroidQuickToggleButton.qml`, `AndroidSliderWidgetBase.qml` | `touchScale`, `scaled()` | idem |
| `NotificationList.qml` | `zoom`, `placeholderScale` | idem |
| `modules/common/widgets/PagePlaceholder.qml` | `sizeScale` | **fica** — `modules/common` é camada compartilhada, parametrizar é o correto |
| `modules/common/widgets/DialogHostLoader.qml`, `Android16Battery.qml` | idem | **fica**, mesma razão |

> `entranceOnOpen` já ficou sem efeito depois do merge (o dev moveu o disparo do entrance
> para `SidebarDashboardContent`). A propriedade foi mantida só para o host tablet continuar
> parseando; remover junto com a Fase 2.

### Bug pré-existente (não é regressão)

`Can't assign to existing role 'modelData' of different type [List -> VariantMap]` —
~118 ocorrências no boot, ~22 a cada abertura de sidebar. **Reproduz também na família ii**
(verificado abrindo a sidebar direita na ii). Origem: `StableQuickToggleModel` /
`AndroidQuickPanel`. Corrigir na Fase 2, quando o grid for promovido.

---

## 5. Fases futuras

### Fase 1 — Bar de tablet (curta)

**Objetivo:** a bar já está fixa no topo e só abre no toque; falta o acabamento.

- [ ] Remover `sizeScale`/`effectiveBarHeight` de `Bar.qml` e `BarWindow.qml` (código morto).
- [ ] Altura da bar em modo tablet: hoje usa `Appearance.sizes.barHeight` (30–50px pela
      config). O Pixel Tablet usa ~48dp de status bar. Escalar em `Appearance`, **não**
      por janela — a lição do `sizeScale` é que widget interno mede pelo valor global.
- [ ] Alvos de toque na bar: mínimo 48×48dp por widget (hoje vários são ~24px).
- [ ] Manter todos os designs de bar (`Hug`, `Float`, `Rect`) — é identidade do ii.
      Excluir apenas `Dynamic Island` (cornerStyle 3) da seleção quando `PanelFamily.isTablet`.
- [ ] Status bar restrita: o Android não deixa customizar ordem livremente. Decidir se
      congelamos o layout ou mantemos o editor (→ **Pergunta 3**).

### Fase 2 — Promoção dos componentes compartilhados

**Objetivo:** zerar as 15 violações da tablet no baseline.

- [ ] Criar `modules/common/quickToggles/` e mover para lá: `AndroidQuickPanel`,
      `androidStyle/*`, `StableQuickToggleModel`, `QuickToggleCatalog.js`,
      `QuickToggleLayout.js`, e os diálogos (`wifiNetworks`, `bluetoothDevices`,
      `volumeMixer`, `nightLight`, `darkMode`, `localSend`, `vpn`, `tailscale`,
      `dnsOverTls`, `idleInhibitor`, `screenShader`).
      - A ii passa a importar de `modules/common/quickToggles` — **sem mudança de
        comportamento**, é um `git mv` mais ajuste de import.
- [ ] Mover `NotificationList` / notification widgets para `modules/common/notifications/`.
- [ ] Mover o modelo de system tray para `modules/common/tray/`.
- [ ] Remover `baseCellHeight`/`revealProgress`/`stageReveal`/`entranceOnOpen`/`touchScale`
      da versão promovida e substituir por um objeto de **métricas** injetado pelo host
      (`QuickToggleMetrics { cellHeight; spacing; iconSize; trackHeight }`), com um preset
      `desktop` e um `touch`. Fica explícito quem quer o quê, em vez de multiplicadores
      espalhados.
- [ ] Corrigir o warning `modelData` durante a promoção.
- [ ] Baseline volta a ter apenas a entrada do `CalendarView`.

### Fase 3 — Tela inicial: workspaces + dock + gaveta de apps

Esta é a maior fase e a que mais se aproxima do Android.

#### 3a. Workspaces como telas iniciais

- [ ] Deslizar horizontalmente no desktop (área sem janela) troca de workspace, com o
      wallpaper acompanhando o dedo (parallax) — igual às home screens do Android.
- [ ] Indicador de página (bolinhas) acima da dock.
- [ ] O `Background` da ii já existe e já suporta widgets de desktop; a home screen tablet
      é uma camada nova por cima dele, **não** um fork.

#### 3b. Grid de ícones no desktop

- [ ] Sistema de grid: colunas × linhas configuráveis (Android: 5×5 no Pixel Tablet).
- [ ] Arrastar app da gaveta para o desktop, arrastar entre workspaces, arrastar para
      remover, criar pasta ao soltar um ícone sobre outro.
- [ ] Persistência em `Persistent.qml` (não em `config.json` — é estado, não preferência),
      por workspace e por monitor.
- [ ] Long-press abre menu de contexto (Remover / Informações do app / Widgets).

#### 3c. Dock nova

- [ ] `modules/tablet/dock/` — implementação nova, **não** derivada de `modules/ii/dock/`
      (6919 linhas de features de desktop: magnificação, live preview, agrupamento,
      widgets de mídia/clima/esporte, reorder por drag, context menu por arquivo).
- [ ] Comportamento Pixel Tablet: barra flutuante centralizada na base, ~6 apps fixos +
      divisória + até 3 apps recentes, cantos bem arredondados, fundo translúcido.
- [ ] Fica visível na home screen; some (ou vira handle fino) quando há app em foreground.
- [ ] Deslizar para cima **a partir da dock** abre a gaveta de apps.

#### 3d. Gaveta de apps

- [ ] `modules/tablet/appDrawer/` — grade alfabética de todos os apps, com campo de busca
      integrado no topo.
- [ ] Substitui o papel do `SearchWidget`/launcher da ii nesta família.
- [ ] Reaproveitar `DesktopEntries` e `Fuzzy` (já em `services`/`common`) — a lógica de
      `AppGridWidget.qml` é boa, o layout é que precisa ser touch.
- [ ] Decisão pendente sobre os painéis especiais do launcher (clipboard, emoji, AI,
      tradutor, calculadora…) → **Pergunta 1**.

### Fase 4 — Gestos em tudo

O `TouchGestureService` já existe e já suporta bordas/cantos com progresso contínuo via
`TouchGestureDragRegistry`. Falta cobrir gestos **fora** das bordas.

| Gesto | Ação | Como |
|---|---|---|
| Deslizar ↓ da borda superior | Central de controle (shade) | ✅ **já funciona** |
| Deslizar ← / → no desktop | Trocar de workspace | Novo: precisa de handler de *drag no corpo*, não só de borda |
| Deslizar ↑ a partir da base | Gaveta de apps | Registrar `bottomEdge` no `DragRegistry` |
| Deslizar ↑ e segurar | Visão geral de apps recentes | Distinguir por tempo/velocidade no mesmo handler |
| Deslizar ← / → da borda lateral | Voltar (back) | `leftEdge`/`rightEdge` → despachar `back` |
| Deslizar → da borda esquerda (longo) | Painel de policies | Ver Fase 5 |
| Pinça no desktop | Seletor de wallpaper / widgets | Novo, precisa de multi-touch no serviço |

- [ ] Estender `TouchGestureService` para reconhecer arrasto iniciado **fora** das bordas
      (hoje `originFor()` só classifica bordas e cantos).
- [ ] Estender `TouchGestureDragRegistry` para múltiplos handlers simultâneos (hoje é um
      só) — a home screen e a shade vão querer bordas diferentes ao mesmo tempo.
- [ ] Preset de bindings da tablet: hoje o default global é `topEdge: cheatsheet`,
      `bottomEdge: overview`. Precisa de defaults por família.

### Fase 5 — Layout de módulos adaptado

- [ ] **Sidebar Policies como janela de aplicativo:** entra deslizando da esquerda, ocupa
      largura de app (não de sidebar), com barra de título própria e botão de voltar.
      Hoje é uma sidebar de largura fixa ancorada na borda.
- [ ] **Diálogos da shade:** já são redimensionados (`dialogWidth` em
      `TabletDashboardContent`), mas ainda usam o layout de sidebar de 460px por dentro.
- [ ] **Media controls, session screen, polkit, wallpaper selector:** revisar alvos de
      toque e larguras.
- [ ] **On-screen keyboard:** promover a cidadão de primeira classe — hoje é opcional.

### Fase 6 — Settings adaptado para toque

- [ ] Layout de duas colunas (master-detail) como o Settings do Android, em vez da sidebar
      estreita + conteúdo.
- [ ] Alvos de toque: `ConfigSwitch`, `ConfigSpinBox`, `ConfigSelectionArray` com altura
      mínima de 48dp e área de toque expandida.
- [ ] `ConfigSpinBox` é hostil a dedo (setas pequenas) — trocar por slider ou stepper grande.
- [ ] Rolagem por arrasto com física de fling.
- [ ] Página **Tablet** nova, agrupando o que hoje está espalhado: shade (edge drag, live
      backdrop), home screen (grid, workspaces), dock, gaveta de apps, gestos.
- [ ] Mover os controles de tablet que hoje estão em `SidebarsConfig.qml` para essa página.
- [ ] Remover/ocultar mais páginas conforme superfícies forem retiradas (o mecanismo
      `families` já existe, é só adicionar o campo).

### Fase 7 — Restrição de customização

O usuário definiu a tablet family como "algo totalmente restrito". Depois que as fases
acima estabilizarem:

- [ ] Auditar todas as opções ainda visíveis em modo tablet e decidir, uma a uma, se o
      Android equivalente permite aquilo.
- [ ] `PanelFamily.restrictedCustomization` já existe como capability — usar para esconder
      seções inteiras.
- [ ] Documentar em `AGENTS.md` que a tablet family é intencionalmente menos configurável,
      para nenhum agente futuro "consertar" isso.

---

## 6. Ordem sugerida

```
Fase 1 (bar)  →  Fase 2 (promoção)  →  Fase 4 (gestos)  →  Fase 3 (home screen)
                                              ↓
                                     Fase 5 (layout)  →  Fase 6 (settings)  →  Fase 7
```

A Fase 2 vem cedo porque toda a Fase 3 vai querer os componentes compartilhados já limpos.
A Fase 4 vem antes da 3 porque a home screen **depende** de arrasto fora das bordas.

---

## 7. Perguntas para decidir

### Pergunta 1 — Launcher e seus painéis especiais

O `SearchWidget` do ii não é só um lançador de apps: tem clipboard, emoji, símbolos
Material, calculadora, tradutor, AI chat, downloader de mídia, browser de arquivos,
capturas, esportes, tarefas, timers, teste de digitação, keybinds, gerenciamento de janelas.

Na Fase 3d a gaveta de apps substitui o launcher. O que fazer com esses painéis?

- **(a)** Gaveta de apps é só apps. Os painéis somem da tablet.
- **(b)** Gaveta de apps é só apps, e os painéis viram "apps do sistema" que aparecem na
  própria grade da gaveta (como o Android faz com Relógio, Calculadora, etc.).
- **(c)** Gaveta com abas: `Apps` | `Ferramentas`, mantendo os painéis na segunda aba.
- **(d)** Manter o `SearchWidget` inteiro acessível por outro gesto, separado da gaveta.

### Pergunta 2 — Overview / apps recentes

Hoje a tablet usa o `Overview` da ii (grade de workspaces com miniaturas de janela).
O Android tem duas coisas distintas: **home screens** (workspaces com ícones) e **recentes**
(carrossel horizontal de apps abertos).

- **(a)** Fazer as duas: home screen nova + recentes novo, aposentando o `Overview` na tablet.
- **(b)** Manter o `Overview` como "recentes" e construir só a home screen.
- **(c)** Fundir: uma tela só, workspaces em cima e ícones embaixo.

### Pergunta 3 — Customização da bar

Você disse que quer manter os diversos designs de bar. Mas o Android não deixa reordenar
a status bar.

- **(a)** Manter os designs **e** o editor de layout de widgets (mais liberdade que o Android).
- **(b)** Manter os designs, congelar o layout num preset "Android" (relógio à esquerda,
  status à direita) — cópia mais fiel.
- **(c)** Manter os designs, oferecer 2–3 presets prontos sem editor livre.

### Pergunta 4 — Ícones no desktop vs. widgets de desktop

O ii já tem widgets de desktop (`modules/ii/background/widgets/` — relógio, clima, mídia,
fotos, at-a-glance) com sistema próprio de posicionamento e redimensionamento.

- **(a)** Grid de ícones do Android **e** os widgets do ii convivem no mesmo grid.
- **(b)** Grid de ícones substitui os widgets na tablet.
- **(c)** Grid de ícones + widgets, mas os widgets também passam a ocupar células do grid
  (como os widgets do Android ocupam N×M células).

> A opção (c) é a mais fiel ao Android e a mais trabalhosa: exige portar o sistema de
> posicionamento livre dos widgets para posicionamento por célula.

### Pergunta 5 — Alvo de hardware e escala

Você usa o Pixel Tablet como referência de comportamento, mas em que hardware isto vai
rodar de fato?

- Resolução e DPI do aparelho alvo?
- Deve funcionar também em modo retrato, ou só paisagem? (`TabletDashboardContent` hoje
  assume paisagem: toggles à esquerda, notificações à direita.)
- Vai existir teclado/mouse conectado às vezes? Isso muda se `BarInteraction.clickToShow`
  deve ser forçado ou apenas ter default diferente.

### Pergunta 6 — Modos, tiling e automação

Removi `modes`, `tiling`, `cheatsheet`, `usage overlay`, `game overlay`, `color picker`,
`video editor` e `scratchpad` da tablet family por julgamento próprio. Confirma? Algum
deles você quer de volta com UI adaptada?

- Em especial: **`modes`** (Modos & Rotinas) tem equivalente no Android (Modos, Não
  perturbe, Bedtime) e talvez valha uma versão tablet.

### Pergunta 7 — Multi-monitor

A tablet family instancia painéis por tela (`Quickshell.screens`). Um tablet tem uma tela,
mas você está desenvolvendo num laptop com monitor externo.

- Manter suporte multi-monitor completo, ou restringir a tablet family à tela primária e
  simplificar bastante o código?

---

## 8. Checklist de verificação (rodar antes de cada commit da tablet)

```bash
# 1. Camadas
./scripts/dev/check-panel-family-layering.sh

# 2. Instância única — nunca subir uma segunda
qs list --all --no-color

# 3. Reinício limpo e erros reais depois do último reload
ii-restart && sleep 12 && qs log -c ii -t 80 | grep -iE "ERROR|unavailable"

# 4. As superfícies certas existem (e as removidas não)
hyprctl layers | grep namespace
#    esperado na tablet: quickshell:bar (y=0), quickshell:tabletShade,
#                        quickshell:background, quickshell:backgroundWidgets
#    NÃO esperado:       quickshell:dock, quickshell:screenCorners

# 5. Trocar de família ida e volta sem erro
qs -c ii ipc call panelFamily cycle
```

---

## 9. Arquivos-chave

| Arquivo | Papel |
|---|---|
| `panelFamilies/TabletFamily.qml` | Composition root da tablet. **Único** lugar que pode emprestar da ii |
| `modules/common/PanelFamily.qml` | Qual família roda e o que ela impõe |
| `modules/common/BarPlacement.qml` | Onde a bar está (≠ config) |
| `modules/common/BarInteraction.qml` | Como a bar é operada (toque vs. ponteiro) |
| `modules/common/TouchGestureDragRegistry.qml` | Contrato de drag contínuo — **exemplo de referência de inversão de dependência** |
| `modules/tablet/sidebarDashboard/TabletShadeDragHandler.qml` | Lado tablet do contrato |
| `modules/tablet/sidebarDashboard/TabletShadeWindow.qml` | Janela da shade (blur, backdrop, arrasto) |
| `modules/tablet/sidebarDashboard/TabletDashboardContent.qml` | Conteúdo da shade — maior fonte de dívida |
| `scripts/dev/check-panel-family-layering.sh` | Cobrança das regras |
| `scripts/dev/panel-family-layering-baseline.txt` | Dívida registrada |
