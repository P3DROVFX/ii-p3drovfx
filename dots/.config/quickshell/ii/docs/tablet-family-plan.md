# Plano — Tablet Panel Family

> **Referência de produto:** Google Pixel Tablet rodando Android 16.
> O objetivo é uma cópia funcional fiel, preservando os elementos de identidade do ii que
> fazem sentido em tela de toque (principalmente os múltiplos designs de bar e a
> personalização dos widgets da bar).

> **Hardware alvo:** laptops com touchscreen e celulares. Comporta-se como o sistema atual,
> apenas melhor adaptado a escalas maiores de monitor. **Sem modo retrato.** Teclado e mouse
> continuam funcionando normalmente — a family é *touch-first*, não *touch-only*.

---

## Estado da implementação

| Fase | Escopo | Estado |
|---|---|---|
| **0** | Merge com `dev`, isolamento arquitetural, limpeza | ✅ **concluída** |
| **1** | Acabamento da bar de tablet | ⬜ a fazer |
| **2** | Promoção dos componentes compartilhados | ⬜ a fazer |
| **4** | Gestos fora das bordas | ⬜ a fazer |
| **3** | Tela inicial: workspaces, grid, dock, gaveta de apps | ⬜ a fazer |
| **5** | Application windows + layout de módulos | ⬜ a fazer |
| **6** | Settings adaptado para toque | ⬜ a fazer |
| **7** | Restrição de customização + simplificação multi-monitor | ⬜ a fazer |

> Ordem de execução: **1 → 2 → 4 → 3 → 5 → 6 → 7**.
> A Fase 2 vem cedo porque a Fase 3 quer os componentes compartilhados já limpos.
> A Fase 4 vem antes da 3 porque a home screen **depende** de arrasto fora das bordas.

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

---

## 3. Guidelines para agentes

> Leia esta seção inteira antes de tocar em qualquer coisa da tablet family.
> Ela existe porque as decisões abaixo já custaram retrabalho uma vez.

### 3.1 A pergunta que você deve fazer primeiro

Antes de escrever uma linha, classifique o que você vai mexer:

```
O componente é usado por mais de uma família?
├── SIM  → mora em modules/common/. Parametrize com defaults identidade.
│          Nunca teste a família lá dentro.
└── NÃO  → mora em modules/<família>/. Pode ser específico à vontade.

Preciso que código compartilhado se comporte diferente na tablet?
└── Adicione uma CAPABILITY ao singleton de política e leia a capability.
    NUNCA escreva Config.options.panelFamily === "tablet" fora de modules/common/.
```

### 3.2 Os singletons de política

| Singleton | Responde | Propriedades |
|-----------|----------|--------------|
| `PanelFamily` | qual família roda e o que ela impõe | `current`, `isTablet`, `touchFirst`, `pinsBarToTop`, `restrictedCustomization` |
| `BarPlacement` | onde a bar **está** (≠ onde a config diz) | `vertical`, `bottom`, `familyPinsBarToTop` |
| `BarInteraction` | como a bar é **operada** | `clickToShow`, `autoHide`, `enablePopups` |

**Prefira a capability ao nome da família.** `PanelFamily.touchFirst` continua fazendo
sentido quando existir uma quarta família; `PanelFamily.isTablet` não.

**A preferência persistida nunca é reescrita.** Trocar de família não pode alterar o
`config.json` do usuário. O Settings continua lendo e escrevendo `Config` diretamente —
`BarPlacement`/`BarInteraction` só resolvem o valor *efetivo* na hora de renderizar.

### 3.3 Como promover um componente da ii para compartilhado

Este é o procedimento da Fase 2 e vai se repetir. Sempre nesta ordem:

1. `git mv modules/ii/<x> modules/common/<x>` — mover primeiro, **sem mudar nada**.
2. Ajustar os imports da ii. Rodar o shell. **A ii tem que ficar idêntica.** Commit.
3. Só então parametrizar o que a tablet precisa. Commit separado.
4. Trocar o import da tablet de `qs.modules.ii.*` para `qs.modules.common.*`.
5. Remover a linha correspondente do baseline. Rodar o guarda.

Nunca faça 1–3 num commit só. Se a ii quebrar, você precisa saber se foi a mudança de
lugar ou a parametrização.

### 3.4 Como parametrizar sem espalhar multiplicadores

O padrão errado (o que está lá hoje e será removido):

```qml
// ❌ multiplicador solto, cada consumidor reinventa a escala
readonly property real touchScale: Math.max(1.0, Math.pow(baseCellHeight / 56, 0.65))
iconSize: root.scaled(16)
```

O padrão certo — um objeto de métricas com presets nomeados:

```qml
// ✅ o host escolhe um preset; o componente só lê valores
QuickToggleMetrics {
    id: metrics
    preset: PanelFamily.touchFirst ? QuickToggleMetrics.Touch : QuickToggleMetrics.Desktop
}
iconSize: metrics.iconSize
```

Fica explícito quem quer o quê, e o valor de toque é ajustável num lugar só.

### 3.5 Regras de runtime (do AGENTS.md, repetidas porque doem)

- **Nunca suba uma segunda instância.** `qs list --all --no-color` antes de qualquer coisa.
  O processo se chama `qs`, não `quickshell` — `pgrep quickshell` não acha nada.
- **Logs são um ring buffer.** `qs log -c ii -t N` mostra as últimas N linhas, que podem
  ser de antes da sua mudança. Para saber se um erro é atual, faça restart limpo e leia o
  log do boot, não o buffer.
- **O hot-reload dispara em arquivo salvo pela metade.** Um erro no log durante uma edição
  em várias etapas pode ser de um estado intermediário. Confirme com restart limpo.
- **`qmllint --bare` não pega tudo.** Ele passou num arquivo que o Quickshell recusou.
  A verificação real é o shell carregando.

### 3.6 Checklist antes de cada commit

```bash
# 1. Camadas
./scripts/dev/check-panel-family-layering.sh

# 2. Instância única
qs list --all --no-color

# 3. Restart limpo + erros reais do boot
ii-restart && sleep 12 && qs log -c ii -t 80 | grep -iE "ERROR|unavailable"

# 4. As superfícies certas existem (e as removidas não)
hyprctl layers | grep namespace
#    esperado na tablet: quickshell:bar (y=0), quickshell:tabletShade,
#                        quickshell:background, quickshell:backgroundWidgets
#    NÃO esperado:       quickshell:dock, quickshell:screenCorners

# 5. Trocar de família ida e volta sem erro (a ii não pode ter regredido)
qs -c ii ipc call panelFamily cycle
```

### 3.7 O que NÃO fazer

- ❌ Adicionar propriedade em `modules/ii/` porque a tablet precisa. Promova ou reescreva.
- ❌ `Config.options.panelFamily === "tablet"` fora de `modules/common/`.
- ❌ Escalar a janela da bar por `sizeScale`. Já foi tentado e revertido: os widgets
  internos medem por `Appearance.sizes.barHeight`, então a janela cresce e o conteúdo não —
  backgrounds somem, alvos de toque erram, popups ancoram errado. **Geometria de bar muda
  em `Appearance`.**
- ❌ Adicionar entrada no baseline para não mexer no código. O baseline é dívida
  registrada, e cada linha precisa de um comentário dizendo qual fase a remove.
- ❌ Commit misturando mudança de lugar com mudança de comportamento.

---

## 4. Fase 0 — concluída

### 4.1 Merge com `dev`

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
| `IllogicalImpulseFamily.qml` | Ver 4.2 |

**Defeito encontrado no merge:** o dev refatorou `PanelFamilyLoader` para carregar famílias
por URL (`familyUrl` + `active: wanted && source !== ""`), mas o loader da tablet continuou
usando a forma antiga `component: TabletFamily {}`. Sem `familyUrl`, `source` ficava vazio e
`active` permanentemente falso — **a tablet family não estava carregando de jeito nenhum**.
O git fez auto-merge sem conflito porque as edições estavam em posições diferentes do
arquivo. Corrigido.

### 4.2 Composition root próprio

- `panelFamilies/IllogicalImpulseFamilyBase.qml` **deletado**.
- `IllogicalImpulseFamily.qml` voltou a ser dono da própria lista (mais próximo do dev →
  menos conflito futuro), com apenas as substituições `BarPlacement`.
- `TabletFamily.qml` passou a listar explicitamente suas superfícies, cada omissão
  anotada com o motivo.

### 4.3 Limpeza

Verificado em runtime: `hyprctl layers` na tablet mostra `quickshell:bar` em `y=0`,
`quickshell:tabletShade`, `quickshell:background` — **sem** `quickshell:dock` e **sem**
`quickshell:screenCorners`.

### 4.4 Bar fixa no topo + popups só no toque

- `BarPlacement.familyPinsBarToTop` agora lê `PanelFamily.pinsBarToTop`.
- `BarInteraction` novo: em família touch-first, `clickToShow` e `enablePopups` são
  forçados `true` e `autoHide` forçado `false`.
- Varredura mecânica de 44 arquivos: `Config.options.bar.tooltips.clickToShow` →
  `BarInteraction.clickToShow`. É uma melhoria para a ii em si (uma fonte de política em
  vez de 44 leituras diretas), e `clickToShow` funciona igualmente bem com mouse.

### 4.5 Inversão da dependência `services/ → modules/tablet/`

`modules/common/TouchGestureDragRegistry.qml` define um contrato genérico de *drag
contínuo* (`claims`/`begin`/`update`/`release`/`cancel`/`actionId`).
`modules/tablet/sidebarDashboard/TabletShadeDragHandler.qml` implementa o contrato e se
registra a partir do `TabletFamily.qml`. O serviço não sabe mais que existe uma família
tablet.

> Este é o **exemplo de referência** para toda inversão futura de dependência.

### 4.6 Settings com escopo por família

`SettingsPageRegistry` ganhou campo opcional `families`. Páginas de superfícies que a
família não renderiza saem da sidebar e do ciclo de teclado. Os índices do array plano
continuam estáveis entre famílias, então deep links e `pageIndexById()` não quebram.

---

## 5. Decisões tomadas

Respostas do mantenedor às perguntas da revisão da Fase 0. **São vinculantes** — não
reabrir sem falar com ele.

### D1 — Gaveta de apps com barra de busca que abre ferramentas

A gaveta de apps tem uma **barra de busca no topo**, como no Android. Os painéis especiais
do launcher da ii (clipboard, emoji, símbolos, calculadora, tradutor, AI, downloader,
browser de arquivos, capturas, esportes, tarefas, timers, teste de digitação, keybinds)
viram **ferramentas** acessíveis por essa busca: ao abrir uma ferramenta, o conteúdo dela
**substitui o conteúdo da gaveta**, no mesmo contêiner.

Futuramente, uma lista de sugestões na própria busca oferece as ferramentas antes de digitar.

### D2 — Home screen nova + recentes novo

Duas superfícies distintas, ambas novas. O `Overview` da ii é aposentado na tablet.

- **Home screen:** workspaces com ícones e widgets.
- **Recentes:** exibe **apenas os apps abertos recentemente**, ou abre uma workspace nova.
  Design igual ao Android em modo tablet.

### D3 — Personalização da bar preservada

Mantém os designs de bar **e** o editor de layout/reordenamento de widgets. Mais liberdade
que o Android, deliberadamente. Só o `Dynamic Island` (cornerStyle 3) sai da seleção.

### D4 — Grid: aumentar o passo do canvas existente

Sem sistema de grid novo. `WidgetCanvas.alignmentGridStep` (hoje `10`) passa a ser maior na
tablet, o que já simula as células do Android. Ícones de app e widgets de desktop convivem
no mesmo canvas.

### D5 — Touch-first, não touch-only

Laptops com touchscreen e celulares. Sem modo retrato. Teclado e mouse continuam
funcionando como hoje. A adaptação é de **escala** e de **alvo de toque**, não de remoção
de suporte a ponteiro.

### D6 — Quase tudo volta, como application windows

**Removidos de fato:** tiling assistant, game/widget overlay, color picker.
Mais os já removidos por serem afordância de ponteiro ou cromo de desktop: dock antiga,
dynamic island, screen corners, vertical bar, wrapped frame, TopLayer/Connect, keypress
display, keyboard layout popup.

**Voltam como application windows na gaveta de apps**, como se fossem apps do Android:
`modes`, `cheatsheet`, `usage stats`, `video editor`, `scratchpad`.

> Isto define o subsistema central da Fase 5: **`TabletAppWindow`**, um hospedeiro que
> apresenta superfícies do shell como janelas de app com barra de título e botão voltar.
> O painel de policies (que entra deslizando da esquerda) é o primeiro cliente dele.

### D7 — Multi-monitor simplifica aos poucos

Pode simplificar, mas incrementalmente, junto das fases que já tocam cada superfície.
Não é uma fase própria.

---

## 6. Dívida atual (burn-down)

`scripts/dev/panel-family-layering-baseline.txt` — 16 entradas.

| Arquivo | Importa | Resolução planejada |
|---|---|---|
| `TabletDashboardContent.qml` | 14× `qs.modules.ii.sidebarDashboard.*` | **Fase 2** |
| `TabletTrayDialog.qml` | `qs.modules.ii.bar.widgets.tray` | **Fase 2** |
| `modules/common/widgets/CalendarView.qml` | `qs.modules.waffle.looks` | Pré-existente, corrigir junto na Fase 2 |

### Parâmetros com default-identidade ainda dentro da ii

| Local | Parâmetro | Destino |
|---|---|---|
| `modules/ii/bar/Bar.qml`, `bar/core/BarWindow.qml` | `sizeScale` / `effectiveBarHeight` | **Fase 1** — código morto, ninguém usa |
| `modules/ii/bar/Bar.qml` | `forceTop` | fica, é legítimo |
| `AndroidQuickPanel.qml` | `baseCellHeight`, `revealProgress`, `stageReveal()`, `entranceOnOpen` | **Fase 2** |
| `AndroidQuickToggleButton.qml`, `AndroidSliderWidgetBase.qml` | `touchScale`, `scaled()` | **Fase 2** |
| `NotificationList.qml` | `zoom`, `placeholderScale` | **Fase 2** |
| `modules/common/widgets/PagePlaceholder.qml`, `DialogHostLoader.qml`, `Android16Battery.qml` | `sizeScale` etc. | **ficam** — camada compartilhada, parametrizar é o correto |

### Bug pré-existente (não é regressão)

`Can't assign to existing role 'modelData' of different type [List -> VariantMap]` —
~118 no boot, ~22 por abertura de sidebar. **Reproduz também na ii** (verificado abrindo a
sidebar direita). Origem: `StableQuickToggleModel` / `AndroidQuickPanel`. Corrigir na Fase 2.

---

## 7. Fases futuras

### Fase 1 — Acabamento da bar de tablet

- [ ] Remover `sizeScale`/`effectiveBarHeight` de `Bar.qml` e `BarWindow.qml` (código morto).
- [ ] Altura da bar em modo tablet ~48dp (Pixel Tablet). Escalar em `Appearance`,
      **não** por janela.
- [ ] Alvos de toque mínimos de 48×48dp nos widgets da bar.
- [ ] Excluir `Dynamic Island` (cornerStyle 3) do seletor quando `PanelFamily.isTablet`
      (D3 mantém o resto da personalização).

### Fase 2 — Promoção dos componentes compartilhados

- [ ] `modules/common/quickToggles/` ← `AndroidQuickPanel`, `androidStyle/*`,
      `StableQuickToggleModel`, `QuickToggleCatalog.js`, `QuickToggleLayout.js` e os
      diálogos (`wifiNetworks`, `bluetoothDevices`, `volumeMixer`, `nightLight`,
      `darkMode`, `localSend`, `vpn`, `tailscale`, `dnsOverTls`, `idleInhibitor`,
      `screenShader`).
- [ ] `modules/common/notifications/` ← `NotificationList` e afins.
- [ ] `modules/common/tray/` ← modelo de system tray.
- [ ] Substituir os multiplicadores por `QuickToggleMetrics` com presets `Desktop`/`Touch`
      (ver §3.4).
- [ ] Corrigir o warning `modelData` durante a promoção.
- [ ] Corrigir `CalendarView` → `qs.modules.waffle.looks`.
- [ ] Baseline zerado.

### Fase 4 — Gestos fora das bordas

| Gesto | Ação | Estado |
|---|---|---|
| ↓ da borda superior | Central de controle (shade) | ✅ funciona |
| ← / → no corpo do desktop | Trocar de workspace | novo — precisa de drag fora de borda |
| ↑ da base | Gaveta de apps | novo — registrar `bottomEdge` |
| ↑ e segurar | Recentes | novo — distinguir por tempo/velocidade |
| ← / → da borda lateral | Voltar (back) | novo |
| → da borda esquerda (longo) | Policies como app window | Fase 5 |

- [ ] `TouchGestureService`: reconhecer arrasto iniciado **fora** das bordas
      (hoje `originFor()` só classifica bordas e cantos).
- [ ] `TouchGestureDragRegistry`: suportar **múltiplos handlers** simultâneos
      (hoje é um só). Home screen e shade querem bordas diferentes ao mesmo tempo.
- [ ] Defaults de binding por família (hoje o global é `topEdge: cheatsheet`,
      `bottomEdge: overview`).

### Fase 3 — Tela inicial

#### 3a. Workspaces como home screens
- [ ] Arrasto horizontal no desktop troca workspace, wallpaper acompanhando (parallax).
- [ ] Indicador de página acima da dock.
- [ ] Camada nova sobre o `Background` existente, **não** um fork.

#### 3b. Ícones no grid (D4)
- [ ] `alignmentGridStep` maior na tablet — sem sistema de grid novo.
- [ ] Arrastar app da gaveta para o desktop; entre workspaces; para remover; pasta ao
      soltar ícone sobre ícone.
- [ ] Persistência em `Persistent.qml` (é estado, não preferência), por workspace e monitor.
- [ ] Long-press → menu de contexto.

#### 3c. Dock nova
- [ ] `modules/tablet/dock/` — implementação nova, **não** derivada de `modules/ii/dock/`
      (6919 linhas de features de desktop).
- [ ] Comportamento Pixel Tablet: barra flutuante na base, ~6 fixos + divisória + até 3
      recentes, cantos arredondados, fundo translúcido.
- [ ] Visível na home; some (ou vira handle) com app em foreground.
- [ ] ↑ a partir da dock abre a gaveta.

#### 3d. Gaveta de apps (D1)
- [ ] `modules/tablet/appDrawer/` — grade alfabética + **barra de busca no topo**.
- [ ] Abrir uma ferramenta pela busca **substitui o conteúdo da gaveta** pelo painel.
- [ ] Reaproveitar `DesktopEntries` e `Fuzzy`; a lógica de `AppGridWidget.qml` serve, o
      layout é que precisa ser touch.
- [ ] Lista de sugestões de ferramentas antes de digitar (segunda iteração).

#### 3e. Recentes (D2)
- [ ] `modules/tablet/recents/` — carrossel de apps abertos, design Android tablet.
- [ ] Botão/gesto para abrir workspace nova.
- [ ] Aposentar o `Overview` da ii no `TabletFamily.qml`.

### Fase 5 — Application windows (D6)

O subsistema central desta fase.

- [ ] `modules/tablet/appWindow/TabletAppWindow.qml` — hospedeiro que apresenta uma
      superfície do shell como janela de app: barra de título, botão voltar, animação de
      entrada por um lado, dispensa por gesto.
- [ ] Registro de "apps do sistema" que a gaveta lista junto dos apps reais.
- [ ] Migrar para app window: **policies** (entra da esquerda), **modes**, **cheatsheet**,
      **usage stats**, **video editor**, **scratchpad**.
- [ ] Diálogos da shade: hoje redimensionados por fora (`dialogWidth`) mas com layout
      interno de sidebar de 460px.
- [ ] Media controls, session screen, polkit, wallpaper selector: revisar alvos de toque.
- [ ] On-screen keyboard vira cidadão de primeira classe.

### Fase 6 — Settings adaptado para toque

- [ ] Layout master-detail em duas colunas, como o Settings do Android.
- [ ] Alvos de 48dp em `ConfigSwitch`, `ConfigSpinBox`, `ConfigSelectionArray`.
- [ ] `ConfigSpinBox` é hostil a dedo — trocar por slider ou stepper grande.
- [ ] Rolagem com física de fling.
- [ ] Página **Tablet** nova: shade, home screen, dock, gaveta, gestos. Move para lá os
      controles hoje espalhados em `SidebarsConfig.qml`.

### Fase 7 — Restrição de customização + simplificação

- [ ] Auditar opção por opção o que o Android equivalente permite.
- [ ] Usar `PanelFamily.restrictedCustomization` para esconder seções inteiras.
- [ ] Documentar em `AGENTS.md` que a tablet é intencionalmente menos configurável, para
      nenhum agente futuro "consertar" isso.
- [ ] Multi-monitor (D7): simplificar incrementalmente junto de cada superfície tocada.

---

## 8. Arquivos-chave

| Arquivo | Papel |
|---|---|
| `panelFamilies/TabletFamily.qml` | Composition root da tablet. **Único** lugar que pode emprestar da ii |
| `modules/common/PanelFamily.qml` | Qual família roda e o que ela impõe |
| `modules/common/BarPlacement.qml` | Onde a bar está (≠ config) |
| `modules/common/BarInteraction.qml` | Como a bar é operada (toque vs. ponteiro) |
| `modules/common/TouchGestureDragRegistry.qml` | Contrato de drag contínuo — **exemplo de referência de inversão de dependência** |
| `modules/common/widgets/widgetCanvas/WidgetCanvas.qml` | Grid do desktop (`alignmentGridStep`) |
| `modules/tablet/sidebarDashboard/TabletShadeDragHandler.qml` | Lado tablet do contrato de drag |
| `modules/tablet/sidebarDashboard/TabletShadeWindow.qml` | Janela da shade (blur, backdrop, arrasto) |
| `modules/tablet/sidebarDashboard/TabletDashboardContent.qml` | Conteúdo da shade — maior fonte de dívida |
| `scripts/dev/check-panel-family-layering.sh` | Cobrança das regras |
| `scripts/dev/panel-family-layering-baseline.txt` | Dívida registrada |
