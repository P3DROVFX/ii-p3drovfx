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
| **3** | Tela inicial: gaveta, dock, workspaces, ícones, recentes | ✅ **concluída** (2 polimentos adiados, ver 3a/3b) |
| **5** | Application windows + layout de módulos | 🟡 **parcial** — app windows prontos; layout dos módulos a fazer |
| **6** | Settings adaptado para toque | 🟡 **parcial** — página Tablet e alvos de toque prontos |
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

### ✅ Resolvido: duas superfícies de desktop na mesma camada

Os ícones do home screen eram uma `PanelWindow` própria na camada Bottom, **embaixo** da
janela de widgets de desktop da ii. Essa janela não define máscara de input, então sua
região cobre a tela inteira e o compositor nunca roteava um toque para os ícones: eles
renderizavam perfeitamente e não respondiam a nada.

**Resolvido pelo Plano B — uma superfície só — mas por injeção, não por promoção.**
`BackgroundWidgetsWindow` depende de seis submódulos do background da ii (wallpaper,
lockscreen, parallax, overview, blur); promovê-lo significa promover todos, ou forkar uma
cópia pior que perde parallax e a coreografia de lock. Em vez disso ele ganhou um
`canvasOverlay` que a família preenche — o mesmo padrão de ponto de extensão que o
`Bar.forceTop` já sancionado: ~10 linhas na ii, zero mudança de comportamento para ela, e
os ícones acabam **literalmente no canvas dos widgets**, dividindo espaço de coordenadas,
parallax e grid. É mais "mesmo grid" (D4) do que dois canvas seriam.

Três armadilhas que isso revelou, **todas renderizando sem um único erro**:

| Sintoma | Causa |
|---|---|
| Overlay visível e intocável | `z: -1` no Loader. Um filho atrás do pai perde o press para ele, e o canvas é um `MouseArea`. Ordem de declaração dá o mesmo empilhamento sem custo de input. |
| Todo arrasto perdido no 1º pixel | `MouseArea` pai rouba o grab do filho no movimento. `preventStealing: true` no ícone. |
| Badge de remover nunca clicável | Um long press **sempre** termina em `clicked`, e esse clique desarmava o badge que o mesmo gesto tinha acabado de armar. |

---

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
      rodava; calendário, tarefas, cronômetro, countdown e pomodoro voltaram como *tiles*
      funcionais no grid da shade, que é outra construção, não este Loader ressuscitado.
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

### Como abrir cada superfície sem touchscreen

| Superfície | Mouse | IPC | Atalho bindável |
|---|---|---|---|
| Gaveta de apps | botão `apps` na dock | `qs -c ii ipc call appDrawer toggle` | `quickshell:appDrawerToggle` |
| Recentes | botão `filter_none` na dock | `qs -c ii ipc call recents toggle` | `quickshell:recentsToggle` |
| Central de controle (shade) | botão dashboard na bar | `qs -c ii ipc call sidebarRight toggle` | `quickshell:sidebarRightToggle` |
| Apps do sistema (usage, modes…) | buscar na gaveta | — | — |
| Ícones do home screen | clique no wallpaper | — | — |

Para bindar no Hyprland, o padrão do projeto é
`hl.bind("SUPER + X", hl.dsp.global("quickshell:appDrawerToggle"))`.

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
- [x] Abertura fullscreen: a dock desce antes de desaparecer, um scrim translúcido preserva o
      app atual no fundo e a gaveta sobe da base; busca e grade derivam do mesmo progresso. A
      layer fica mapeada e com máscara de input vazia no repouso para não pular os frames iniciais.
- [ ] Lista de sugestões de ferramentas **antes** de digitar (segunda iteração).

#### 3c. Dock — igual à do Android ✅
- [x] `modules/tablet/dock/` — implementação nova, **não** derivada de `modules/ii/dock/`.
- [x] **Sem fundo**: linha horizontal na largura da tela, ícones direto no wallpaper, como
      na home screen do Android. Glifos com contorno e divisórias brancas, porque o
      wallpaper embaixo é arbitrário.
- [x] **Botões de navegação** do Android no lado direito: `arrow_back_ios_new`,
      `check_box_outline_blank` e `radio_button_unchecked`, com o mesmo hit target vertical
      dos apps. A ordem é configurável.
      Voltar sai da superfície do shell que estiver por cima, em ordem, e é inerte numa home
      screen vazia — exatamente como o do Android, já que não existe "tela anterior"
      genérica para um aplicativo qualquer. Home fecha o que estiver aberto e cai num
      workspace vazio.
- [x] **Auto-hide igual ao da ii**: fixada sempre aparece, senão só enquanto o workspace não
      tem nada aberto. Os botões de navegação **ficam de fora dessa regra** — são controles
      de sistema, e um shell cujo único caminho de volta some ao abrir algo é um shell onde
      dá para ficar preso.
- [x] Fixos → divisória → até 3 abertos → botão da gaveta. Ponto embaixo do ícone marca app
      rodando, como no Android.
- [x] Compartilha a lista de fixos via `TaskbarApps` — são os favoritos do usuário, não
      propriedade da dock de um shell, então os pinos atravessam as famílias.
- [x] Reserva uma faixa real via `exclusionMode: Normal` + `exclusiveZone`: apps tiled param
      acima da dock. A faixa é liberada ao esconder a dock ou se o usuário escolher o modo
      overlay.
- [x] Reutiliza `DockIcon` do módulo comum: máscara Material, monocromia e dimming são os
      mesmos da dock do ii, sem acoplamento da TabletFamily ao módulo `ii`.
- [x] Settings › Tablet concentra reserva, auto-hide, visibilidade de apps/navegação/recentes/
      gaveta/divisórias, tamanho, contador de páginas (e compactação sem ele) e aparência
      adaptativa dos ícones.
- [x] Some enquanto a gaveta está aberta.

#### 3a. Workspaces como home screens ✅
- [x] Arrasto horizontal no corpo do desktop troca workspace. Só age quando o toque cai
      onde nenhuma janela cobre — senão o arrasto é do aplicativo. Origem `surface` nova no
      `TouchGestureService`, com `dx`/`dy` no contrato do registry.
- [x] Indicador de página acima da dock, só com os workspaces **deste monitor** (senão o
      indicador discorda do swipe, que se move dentro do monitor).
- [ ] **Adiado:** wallpaper acompanhando o dedo (parallax durante o arrasto). Polimento;
      exige dirigir o parallax do background da ii a partir do gesto.

#### 3b. Ícones no grid (D4) 🟡
- [x] `Appearance.sizes.widgetGridStep` — 40 na tablet, 10 no resto. Sem grid novo.
- [x] `modules/tablet/homeScreen/` — ícones no wallpaper, um conjunto por workspace.
- [x] Long-press na gaveta adiciona ao home screen atual; arrastar move (com snap no grid);
      long-press no ícone arma um badge × que exige um segundo toque deliberado.
- [x] Persistência em `Persistent.states.tablet.homeIconsJson`, por workspace.
- [x] **Conflito de camada resolvido** — os ícones foram para dentro do canvas de widgets
      via `BackgroundWidgetsWindow.canvasOverlay`. Ver abaixo.
- [ ] **Adiado:** arrastar ícone entre workspaces; pasta ao soltar ícone sobre ícone.

#### 3e. Recentes (D2) ✅
- [x] `modules/tablet/recents/` — carrossel de janelas abertas com screencopy, ícone e
      título; toque foca a janela, arrasto para cima fecha.
- [x] Pill "New workspace" leva a um workspace vazio.
- [x] `Overview` da ii aposentado no `TabletFamily.qml`, junto do `OverviewWindowTransition`.

### Fase 5 — Application windows (D6) 🟡

- [x] `modules/tablet/appWindow/TabletAppWindow.qml` é uma `FloatingWindow` (xdg toplevel),
      não uma `PanelWindow` Overlay: Hyprland abre o módulo numa workspace vazia e aplica as
      regras de janela `ii Tablet: …` para flutuar e centralizar. A barra própria oferece
      **voltar** à esquerda e **fechar** à direita, pois ambos são necessários num fluxo de
      tablet mesmo quando o compositor não expõe decorações; dismiss por clique fora e Escape
      continuam removidos.
- [x] `TabletSystemApps` hospeda todo conteúdo independente da ii na mesma janela nativa:
      Usage, Modes, cada policy e as páginas Timetable, Keybinds, Periodic Table, Amino
      Acids, Commands, Workspaces, Email e Typing Test. `TabletFamily` injeta os componentes
      para manter `modules/tablet/` sem importar `modules/ii/`.
- [x] Renderizam como símbolo em placa tingida em vez de fingir ser ícone de app.
- [x] Componentes de conteúdo são da ii → **injetados** pelo composition root.
- [x] **Policies não são mais sidebar** na tablet: o arrasto da borda esquerda continua
      abrindo Intelligence, mas como aplicação nativa. `sidebarLeft*` é no-op para a família,
      `effectiveLeftOpen` é sempre falso e o parallax lateral do background é desativado por
      capability; atalhos herdados não conseguem movimentar o wallpaper.
- [x] Entradas do cheatsheet são apps nativos separados, sem carregar o antigo
      `Cheatsheet` Overlay. Deep links (`openCheatsheet` e `openTimetableAt`) são roteados
      para o id de aplicação correspondente na tablet e preservam a data solicitada.
- [x] `TabletSystemKeybinds` assume os targets globais de Hyprland na composição tablet:
      Super abre/fecha a gaveta com o mesmo debounce do ii, Super+Tab abre Recentes e os
      atalhos de cheatsheet, Usage e Modes abrem suas janelas nativas. O indicador de números
      de workspace fica desativado para uma família touch-first.
- [x] A máscara de input da gaveta é removida assim que começa a fechar, embora a animação
      visual permaneça mapeada. Assim o botão Apps da dock pode receber o próximo toque em
      vez de ele ser absorvido pela Overlay transparente em saída.
- [x] Apps da dock têm o mesmo menu contextual da dock ii: clique direito no ponteiro e
      toque longo abrem Launch, ações do desktop entry, Live Preview, Pin/Unpin e fechar
      janela(s). A cópia fica em `modules/tablet/dock/`, sem importar a família ii.
- [x] Apps de sistema **sempre listados** na gaveta, liderando a grade. Escondê-los atrás
      da busca significava que só achava quem já sabia que existiam.
- [x] **Long-press alcança todo `altAction`** no `RippleButton`. Era só botão direito — o
      caminho por trás do diálogo de cada quick toggle e das tooltips que literalmente dizem
      *"Right-click to configure"*. Um dedo não tem botão direito, então na tablet essas
      ações não tinham entrada nenhuma. Armado só quando existe `altAction` e só em família
      touch-first; a ação roda no **release**, porque abrir o diálogo com o dedo ainda
      pressionado colocava o scrim dele embaixo do dedo e o release dispensava o que tinha
      acabado de abrir. O clique final é suprimido, senão abrir os ajustes de um toggle o
      alternaria no caminho.
- [x] **On-screen keyboard** como app da gaveta — cidadão de primeira classe, já que nada
      aqui pressupõe teclado físico e alcançá-lo só por keybind é circular.
      **Confirmado pelo mantenedor com ponteiro real:** funciona. O que falhava nos testes
      era o clique direito *sintético* do `ydotool` não contando, não a cadeia do shell.
- [x] **Gaveta reordena ao vivo em vez de ser reconstruída.** Atribuir um array JS novo
      reseta a view, e um reset não dispara transição de `move`: cada tile é destruído e
      recriado onde caiu, que é o oposto do que se quer. As linhas agora têm chave e são
      reconciliadas no lugar (mesmo diff da lista de resultados da ii), então
      `move`/`displaced` têm o que animar. A entrada anima `scale`, nunca `opacity` — uma
      transição de opacidade interrompida deixa o tile invisível, e um tile que não pinta é
      pior que um que não anima.
- [x] **Ordenação e categorias**: A–Z, Z–A, categoria e mais usados, mas só com a busca
      vazia — com query, a relevância *é* a ordem, e é ela que se move enquanto o usuário
      digita. As categorias vêm dos `.desktop`, colapsadas das treze categorias principais
      do freedesktop em grupos navegáveis, e também são chips de filtro.
- [x] **Long-press abre menu** em vez de mandar o app para a home silenciosamente. O menu
      oferece os atalhos do próprio `.desktop`, abrir, adicionar à home e fixar na dock, e
      é desenhado dentro da gaveta — uma segunda superfície disputaria o foco de teclado
      exclusivo da gaveta por algo que o Android desenha no próprio launcher.
- [x] **Menu contextual touch-first da gaveta.** Clique direito e toque longo abrem a mesma
      superfície; cada ação tem alvo de toque amplo, respiro próprio, superfície Material
      e raio dinâmico em grupo. A lista interna rola quando um `.desktop` oferece muitas
      ações, sem aumentar o menu além da viewport.
- [x] **A coluna inteira de quick toggles rola como uma superfície só.** A rolagem vertical
      cobre páginas configuradas, editor e gaveta de toggles; a gaveta não captura um segundo
      gesto vertical nem fica comprimida numa subviewport curta.
- [x] **Cinco widgets funcionais como quick toggles fixos:** calendário, tarefas,
      cronômetro, countdown e pomodoro aparecem na gaveta apenas na família tablet. Todos
      usam footprint quadrado fixo `1x2`; toque executa a ação imediata e toque longo/clique
      direito abre a ferramenta completa correspondente.
- [x] **Barra de busca na dock**: pílula ou círculo compacto, com os dois botões das pontas
      escolhidos pelo usuário — inclusive os painéis de busca da shell, então "clipboard na
      dock" é ajuste e não pedido de recurso. A pílula sabe desenhar uma ação e nada sobre o
      que ela faz; a dock resolve isso.
- [x] **A dock sobe junto com a gaveta.** Ela não estava sendo descarregada, estava sendo
      **cortada**: uma superfície de layer não tem overflow, e a superfície tinha exatamente
      a altura da dock. Agora há uma folga transparente acima, mascarada e fora da zona
      exclusiva.
- [x] **Blur progressivo na gaveta.** O blur do compositor não é um valor que o cliente
      dirija: a força é o alpha da própria superfície, e a regra `ignore_alpha` da shell
      transforma isso num limiar — daí ele aparecer de uma vez no fim. A gaveta borra um
      screencopy congelado, como a shade já fazia. Com `appearance.transparency` desligado
      não há captura nem blur: fundo sólido.
- [x] **A grade termina em fade, não em corte.** Margem inferior 0 e uma máscara de alfa:
      `ScrollEdgeFade` pinta uma faixa de cor, o que só encerra conteúdo quando a superfície
      atrás é daquela cor — aqui é um screencopy borrado, então qualquer cor que a faixa
      pintasse era ela mesma translúcida e a última fileira continuava visivelmente fatiada
      por baixo do lavado. Mascarar o alfa funciona contra qualquer fundo, porque o que
      aparece através *é* o fundo.
- [x] **Borda inferior como alvo de ponteiro.** `TouchGestureService` lê evdev e só aceita
      dispositivos que classifica como touchscreen, então uma caneta de mesa digitalizadora
      — que chega como ponteiro — nunca alcançava o registro de arrasto e o swipe não fazia
      nada. A shade sempre teve uma faixa de ponteiro na borda de cima, que é exatamente por
      que arrastá-la para baixo funciona com a mesma caneta. Esta é a mesma faixa, invertida;
      o toque continua pelo serviço, e os dois caminhos dirigem o mesmo controller.
- [x] **Botões de navegação com as formas do Android**: chevron, círculo, quadrado. Home
      desenhava o quadrado e recentes o círculo — o par trocado.
- [x] **Notificações legíveis na shade.** Estavam no tamanho que a sidebar de 460px do
      desktop precisa, numa superfície que é a tela inteira. A linha de controles delas
      agora tem a mesma altura da linha de ações do sistema ao lado, então as duas colunas
      terminam na mesma linha. `NotificationList` ganhou altura e escala de conteúdo para
      repassar, em vez de a tablet enfiar a mão dentro dos botões; ambos com padrão neutro.
- [x] **Setas de workspace na dock**, uma em cada extremo. O swipe já existia mas precisa de
      wallpaper nu para começar, ou seja, fica inalcançável exatamente quando há algo aberto
      — que é quando mudar de tela mais importa. Despacham o mesmo que o swipe.
- [x] **Swipes multitoque na tela.** O touchpad do compositor não existe num tablet, e o par
      que ele traz — scratchpad para dentro e para fora — é ideia de gerenciamento de janela
      de desktop. Na touchscreen: lateral troca de workspace, para cima abre a gaveta, para
      baixo puxa a shade. Reconhecidos antes do filtro de contato único, porque os outros
      dedos da mão não são o contato ativo e o movimento deles é o gesto inteiro. Armam com
      a contagem exata e disparam uma vez por mão apoiada.
- [x] **Back virou ação vinculável.** O que "voltar" significa é específico da família e
      `modules/common` não pode importar uma para descobrir, então a tablet instala um
      handler, como já fazia com o keybind de policies.
- [ ] Diálogos da shade: largura já é parametrizada (`WindowDialog.preferredDialogWidth`
      via `DialogHostLoader.dialogWidth`, 560–980 na tablet). Falta revisar o layout
      *interno* — listas e linhas ainda desenhadas para a sidebar estreita.
- [ ] Media controls, session screen, polkit, wallpaper selector: revisar alvos de toque.

### Fase 6 — Settings adaptado para toque 🟡

- [x] **Página Tablet** nova: shade, dock, home screen e gestos. Listada só para a família
      que ela configura. Os controles estavam espalhados por qualquer página de desktop que
      o recurso da tablet lembrasse — a borda de arrasto da shade morava em "Sidebars" —
      então achar um exigia saber de qual recurso da ii a tablet tinha emprestado.
- [x] **Passo do grid virou preferência de verdade** (`background.widgets.gridStep`, 0 =
      deixa a família decidir). Era constante no `Appearance`.
- [x] **Alvos de toque** nos controles compartilhados, com **piso** e não altura fixa, e
      só em família touch-first (a ii foi verificada lado a lado e não mudou):
      `StyledSpinBox` (os quadrados +/- eram 35px e são a área de toque inteira),
      `StyledSwitch` (voltou ao tamanho M3 — o 0.75 serve a ponteiro, mas este controle é
      *arrastado*, não só tocado), e as linhas de `ConfigSwitch`, `ConfigSpinBox`,
      `ConfigSubpageRow` e `ConfigSlider`.
- [ ] Layout master-detail em duas colunas, como o Settings do Android. Hoje já é
      sidebar + conteúdo, que é master-detail; falta avaliar se vale mudar.
- [ ] Rolagem com física de fling.

> ⚠️ **Armadilha que custou tempo:** a página nova renderizou **completamente vazia**, com
> um único aviso no log — *binding loop*. O spin box do passo do grid lia
> `Appearance.sizes.widgetGridStep` como fallback, e essa propriedade resolve através da
> mesma chave de config que o controle escreve. `Appearance` agora expõe
> `familyWidgetGridStep` (o default da família, independente do valor guardado) para
> exatamente esse caso. **Um loop de binding aqui não degrada: apaga a página.**

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
