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
| **1** | Acabamento da bar de tablet | ✅ **concluída** |
| **2** | Promoção dos componentes compartilhados | ✅ **concluída** — baseline em **0** |
| **4** | Gestos: múltiplos handlers + ações por família | ✅ **concluída** (arrasto fora das bordas entregue na Fase 3) |
| **3** | Tela inicial: gaveta, dock, workspaces, grid, recentes | 🟡 **quase** — 1 bloqueio de camada (ver §6) |
| **5** | Application windows + layout de módulos | ⬜ a fazer |
| **6** | Settings adaptado para toque | ⬜ a fazer |
| **7** | Restrição de customização + simplificação multi-monitor | ⬜ a fazer |

> Ordem de execução: **1 → 2 → 4 → 3 → 5 → 6 → 7**.
> A Fase 2 vem cedo porque a Fase 3 quer os componentes compartilhados já limpos.
> A Fase 4 vinha antes da 3 para a home screen ter os gestos prontos. Na prática só a
> metade sem consumidor pôde ser feita antes: o arrasto fora das bordas precisa da home
> screen para ter contra o que ser projetado, então essa parte migrou para a Fase 3.

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
| 4 | **Nenhum import relativo sobe para fora do próprio módulo** | `import "../../../mediaControls"` é a mesma dependência que `import qs.modules.ii`, escrita de um jeito que as regras 1–3 não enxergam — e passa a resolver para outro diretório no instante em que o arquivo é movido. Descer para `common/` ou `services/` continua legal. |

### Como as regras são cobradas

```bash
./scripts/dev/check-panel-family-layering.sh
```

Falha em qualquer violação **nova**. As conhecidas ficam em
`scripts/dev/panel-family-layering-baseline.txt` — são dívida registrada, não permissão.
O script também avisa quando uma entrada do baseline deixa de ocorrer, para ser removida.

> **O baseline está vazio desde a Fase 2, e deve continuar assim.** Adicionar uma linha é
> uma decisão revisada que precisa de um comentário dizendo qual fase a remove — não é um
> jeito de passar pelo check.

A regra 4 nasceu de um caso real: durante a promoção da Fase 2 as regras 1–3 deram OK
enquanto um `import "../../../mediaControls"` continuava apontando para a ii, e depois do
`git mv` passou a apontar para um diretório inexistente. O check resolve cada caminho
relativo e só acusa os que aterrissam em **outra** família.

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

O padrão errado — que estava no grid de toggles e foi removido na Fase 2:

```qml
// ❌ a mesma curva escrita à mão em dois arquivos diferentes
readonly property real touchScale: Math.max(1.0, Math.pow(baseCellHeight / 56, 0.65))
iconSize: root.scaled(16)
```

Duas cópias de uma curva que ninguém reconheceria como deliberada é exatamente como as
duas divergem na primeira vez que alguém ajusta uma delas.

O padrão certo — a derivação mora num lugar só:

```qml
// ✅ modules/common/quickToggles/QuickToggleMetrics.qml
iconSize: QuickToggleMetrics.scaled(root.baseCellHeight, 16)
```

`QuickToggleMetrics` é um **singleton de funções puras** da altura da célula, e não um
objeto que o host instancia e passa para baixo. Foi uma decisão consciente: todo delegate
já recebe `baseCellHeight`, então uma instância seria cerimônia em volta de aritmética.
Quando o valor depender de algo que o delegate *não* recebe, aí sim vale um objeto com
presets nomeados.

Duas coisas que o singleton documenta e que não devem ser "consertadas" sem pensar:

- A escala é **sub-linear** (expoente 0.65) de propósito. Uma célula duas vezes maior não
  quer um ícone duas vezes maior; quer um ícone um pouco maior com muito mais respiro.
- `sliderTrack()` devolve **-1** para dizer "use o preset M". O preset é um valor de enum,
  não uma espessura, então não dá para devolver os dois pelo mesmo caminho.

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

## 6. Dívida atual

### Camadas

`scripts/dev/panel-family-layering-baseline.txt` — **vazio**. As 16 entradas originais
foram quitadas na Fase 2. Ver §2 sobre o que significa adicionar uma linha de volta.

### Parametrização

O que sobrou de parâmetro atravessando fronteira, e por quê:

| Local | Parâmetro | Situação |
|---|---|---|
| `common/quickToggles/AndroidQuickPanel.qml` | `baseCellHeight` | **Fica.** É a unidade de layout do grid, com nome honesto, agora em camada compartilhada. Não é multiplicador solto. |
| `common/quickToggles/AndroidQuickPanel.qml` | `revealProgress`, `stageReveal()` | **Fica.** É a API de reveal dirigida pelo host — o gesto de arrasto da shade precisa dela. Legítima em `common/`. |
| `common/notifications/NotificationList.qml` | `zoom`, `placeholderScale` | **Fica**, mesma razão: camada compartilhada, parametrizar é o correto. |
| `common/widgets/{PagePlaceholder,DialogHostLoader,Android16Battery}` | `sizeScale` etc. | **Ficam.** |
| `modules/ii/bar/Bar.qml` | `forceTop` | **Fica.** É a tablet fixando a bar no topo sem tocar na config guardada. |

Nada disso está mais dentro de `modules/ii/` a não ser o `forceTop`, que é o mecanismo
correto e não uma gambiarra.

### 🚧 Bloqueio: duas superfícies de desktop na mesma camada

Os ícones do home screen (`quickshell:tabletHomeIcons`) e a janela de widgets de desktop da
ii (`quickshell:backgroundWidgets`) estão **ambas na camada Bottom**. A da ii é criada
depois e **não define máscara de input**, então sua região de input cobre a tela inteira e o
compositor nunca roteia um toque para os ícones embaixo.

Os ícones **renderizam corretamente** e toda a interação funciona — verificado subindo a
janela para a camada Top temporariamente, onde arrastar e o badge de remover funcionam. Na
Bottom eles aparecem e não respondem.

**Isto é uma decisão de design, não um bug a corrigir às cegas.** Três caminhos:

| | O que fazer | Custo |
|---|---|---|
| **A** | A tablet family deixa de carregar a superfície de widgets da ii | Perde os widgets de desktop da ii na tablet. Contradiz a D4 ("convivem no mesmo grid"). Hoje custaria o widget `media`, que está ativo. |
| **B** | Promover o canvas de widgets da ii para `modules/common`, e a tablet hospeda um canvas próprio com **widgets + ícones** | É literalmente o que a D4 pediu. Promoção grande, no estilo da Fase 2. |
| **C** | Dar máscara ao `BackgroundWidgetsWindow` da ii, restrita aos widgets fora do modo de edição | Correção legítima na ii (uma superfície que captura input da tela toda na camada Bottom impede qualquer outra de existir ali), mas mexe em arrastar widget, overlay de grid e menus de contexto — risco de regressão real. |

**Recomendação: B.** É o que a D4 pediu e é a única que não troca um problema por outro.
**Precisa da decisão do mantenedor antes de seguir.**

### Conhecido, ainda aberto

- **`SidebarPerformancePolicy.js`** continua em `modules/ii/sidebarDashboard/`. É usado só
  pela ii (`BottomWidgetGroup`, `SidebarDashboardContent`), então está no lugar certo — mas
  se a tablet ganhar uma política de performance própria, vale comparar as duas em vez de
  duplicar.
- **`ClassicQuickPanel` / `classicStyle/`** foram promovidos junto do grid Android porque
  moravam na mesma árvore. A tablet não usa o estilo clássico. Se ele nunca for usado fora
  da ii, pode voltar para lá numa limpeza posterior — não é urgente e mover de novo custa
  mais do que deixar.

---

## 7. Fases futuras

### Fase 1 — Acabamento da bar de tablet ✅

- [x] Removido `sizeScale`/`effectiveBarHeight` de `Bar.qml` e `BarWindow.qml` — era resto
      de uma abordagem abandonada e ninguém mais setava.
- [x] `Appearance.sizes.baseBarHeight` eleva o **piso** para 48 em família touch-first, em
      vez de substituir o valor: uma bar configurada mais alta continua mais alta, e a
      preferência guardada nunca é reescrita. Verificado: tablet renderiza 48, ii continua
      nos 40 configurados.
- [x] `BarComponent` estende widgets estreitos até o mesmo mínimo na **largura**. Widget sem
      conteúdo continua em zero, então nada deixa um buraco de 48px ao se esconder.
- [x] `BarInteraction.cornerStyle` resolve Dynamic Island (3) para Hug na tablet — a família
      não desenha ilha nenhuma, então o estilo guardado dava à bar a silhueta de um notch sem
      nada atrás. Varridos os 16 consumidores de renderização; Settings, Welcome, `Config` e
      `ShellModePolicy` continuam lendo o valor guardado, porque exibem ou validam a
      preferência em si. O estilo também sai das opções do seletor, em vez de ficar apenas
      desabilitado.

**Deliberadamente não feito:** um mínimo horizontal aplicado a todo widget indistintamente.
O layout da bar é ajustado com cuidado e widgets como workspaces são largos de propósito —
alvos horizontais por widget são revisados na Fase 5, junto da adaptação de cada módulo.

### Fase 2 — Promoção dos componentes compartilhados ✅

Baseline de **16 → 0**. O que se moveu:

| De | Para |
|---|---|
| `ii/sidebarDashboard/{SidebarGroupAnimation,DashboardEntranceProgress}` | `common/animations/` |
| `ii/sidebarDashboard/quickToggles/` (44 arquivos) | `common/quickToggles/` |
| `ii/sidebarDashboard/{11 diálogos}` | `common/quickToggleDialogs/` |
| `ii/sidebarDashboard/notifications/` | `common/notifications/` |
| `ii/sidebarDashboard/SidebarSpaceArbitration.js` | `common/functions/SpaceArbitration.js` |
| `ii/mediaControls/AndroidMediaPopup.qml` | `common/media/` |
| `ii/bar/shared/cards/{MetricCard,LoadingPlaceholder}` | `common/widgets/cards/` |
| `ii/bar/widgets/tray/{SysTrayMenu,SysTrayMenuEntry}` | `common/tray/` |
| `common/widgets/CalendarView.qml` | `waffle/notificationCenter/` |

Esse último é o inverso dos outros: `CalendarView` estava em `common/` mas importava
`qs.modules.waffle.looks`, e a waffle era sua única consumidora. Nunca foi um widget
compartilhado, só um widget no diretório errado.

Também nesta fase:

- [x] `QuickToggleMetrics` (ver §3.4) unifica a curva de escala que estava duplicada.
- [x] `entranceOnOpen` removido dos dois lados — ficou sem efeito quando o merge do dev
      moveu o disparo do entrance para `SidebarDashboardContent`.
- [x] `BottomWidgetGroup` parado atrás de `showBottomWidgetGroup: false` removido do
      conteúdo da shade. A tablet pagava uma dependência entre famílias por código que nunca
      rodava; os widgets de calendário/tarefas/timer voltam como *tiles* no grid (Fase 3),
      que é outra construção, não este Loader ressuscitado.
- [x] **Bug real corrigido**, não só o warning: `StableQuickToggleModel` guardava o payload
      num papel chamado `modelData`. Um `ListModel` fixa o tipo do papel no primeiro uso e
      infere objeto aninhado como lista, então todo `setProperty()` posterior era recusado e
      **descartado em silêncio** — ou seja, um tile movido para novo `layoutX`/`layoutY`
      continuava desenhando na geometria antiga até a linha ser reconstruída por outro
      motivo. `dynamicRoles: true` resolve. 118 warnings no boot e ~22 por abertura de
      sidebar, nas duas famílias, foram a zero.
- [x] Regra 4 adicionada ao guarda (ver §2).

### Fase 4 — Gestos 🟡

| Gesto | Ação | Estado |
|---|---|---|
| ↓ da borda superior | Central de controle (shade) | ✅ |
| ↑ da base | Gaveta de apps | ✅ |
| ← / → no corpo do desktop | Trocar de workspace | ✅ |
| ↑ e segurar | Recentes | Fase 3e — distinguir por tempo/velocidade |
| ← / → da borda lateral | Voltar (back) | a fazer |
| → da borda esquerda (longo) | Policies como app window | Fase 5 |

> ⚠️ **Nenhum gesto foi verificado ponta a ponta.** Esta máquina de desenvolvimento tem
> touchpad e nenhum touchscreen (`hyprctl devices` não lista Touch), então o reconhecedor
> não pode ser acionado. Vale para o pull-down da shade que já existia também. Testar no
> hardware alvo.

- [x] `TouchGestureDragRegistry` suporta **múltiplos handlers**, resolvidos por origem.
      Dois handlers reivindicando a mesma borda é bug da família, não camada suportada:
      o primeiro registrado vence e a colisão é logada, porque escolher em silêncio
      deixaria a superfície perdedora simplesmente sem responder. `handlerFor()` também
      sobrevive a um handler que lança exceção.
- [x] Ações de gesto ganharam o campo `families`, igual às páginas de settings. Seis delas
      nomeiam superfície que a tablet não renderiza; o serviço trata esse binding como
      **não vinculado** e o seletor do Settings não oferece a ação. Isso é ativo hoje: o
      `topEdge` guardado é `cheatsheet`. Quatro das seis voltam quando a Fase 5 lhes der
      app windows.

**Adiado de propósito:** reconhecer arrasto iniciado **fora** de uma borda. O modelo de
travel para um arrasto 2D livre é um contrato, e projetá-lo sem o consumidor que vai usá-lo
é exatamente como se constrói a abstração errada. Vai junto da home screen, na Fase 3.

### Fase 3 — Tela inicial

#### 3d. Gaveta de apps (D1) ✅
- [x] `modules/tablet/appDrawer/` — grade alfabética de todos os apps + barra de busca no topo.
- [x] Digitar mostra **chips de ferramentas** vindos do `SearchPanelRegistry`; escolher uma
      **substitui a grade** pelo painel dela, no mesmo contêiner. Seta de voltar retorna à
      grade; Escape volta um nível por vez (ferramenta → busca → fechado).
- [x] O host das ferramentas é **injetado** pelo `TabletFamily`, porque os painéis moram na
      ii. Sem injeção a gaveta continua completa, só sem ferramentas.
- [x] Claim da borda inferior via `TouchGestureDragRegistry` (↑ abre a gaveta).
- [ ] Lista de sugestões de ferramentas **antes** de digitar (segunda iteração).

#### 3c. Dock nova ✅
- [x] `modules/tablet/dock/` — implementação nova, **não** derivada de `modules/ii/dock/`.
- [x] Pill flutuante na base: fixos → divisória → até 3 abertos → botão da gaveta.
      Ponto embaixo do ícone marca app rodando, como no Android.
- [x] Compartilha a lista de fixos via `TaskbarApps` — são os favoritos do usuário, não
      propriedade da dock de um shell, então os pinos atravessam as famílias.
- [x] `exclusionMode: Ignore` (flutua, não reserva faixa) e máscara de input só no pill.
- [x] Some enquanto a gaveta está aberta.

#### 3a. Workspaces como home screens 🟡
- [x] Arrasto horizontal no corpo do desktop troca workspace. Só age quando o toque cai
      onde nenhuma janela cobre — senão o arrasto é do aplicativo. Origem `surface` nova no
      `TouchGestureService`, com `dx`/`dy` no contrato do registry.
- [ ] Wallpaper acompanhando o dedo (parallax).
- [ ] Indicador de página acima da dock.

#### 3b. Ícones no grid (D4) 🟡
- [x] `Appearance.sizes.widgetGridStep` — 40 na tablet, 10 no resto. Sem grid novo.
- [x] `modules/tablet/homeScreen/` — ícones no wallpaper, um conjunto por workspace.
- [x] Long-press na gaveta adiciona ao home screen atual; arrastar move (com snap no grid);
      long-press no ícone arma um badge × que exige um segundo toque deliberado.
- [x] Persistência em `Persistent.states.tablet.homeIconsJson`, por workspace.
- [ ] **Bloqueado por conflito de camada** — ver §6.
- [ ] Arrastar entre workspaces; pasta ao soltar ícone sobre ícone.

#### 3e. Recentes (D2) ✅
- [x] `modules/tablet/recents/` — carrossel de janelas abertas com screencopy, ícone e
      título; toque foca a janela, arrasto para cima fecha.
- [x] Pill "New workspace" leva a um workspace vazio.
- [x] `Overview` da ii aposentado no `TabletFamily.qml`, junto do `OverviewWindowTransition`.

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
| `modules/tablet/sidebarDashboard/TabletDashboardContent.qml` | Conteúdo da shade |
| `modules/common/quickToggles/` | Grid de quick toggles, compartilhado ii + tablet |
| `modules/common/quickToggles/QuickToggleMetrics.qml` | Escala do chrome do grid — **exemplo de referência de parametrização** |
| `modules/common/quickToggleDialogs/` | Os 11 diálogos dos toggles |
| `modules/common/notifications/` | Lista de notificações compartilhada |
| `scripts/dev/check-panel-family-layering.sh` | Cobrança das regras |
| `scripts/dev/panel-family-layering-baseline.txt` | Dívida registrada |
