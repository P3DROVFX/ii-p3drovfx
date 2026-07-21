# Plano de Implementação: Redesign & Refatoração do Módulo OnScreenDisplay (OSD default)

> **Arquivo alvo:** `modules/ii/onScreenDisplay/OnScreenDisplay.qml` (e arquivos auxiliares criados/modificados listados em cada task).
> **Módulo entry-point:** `panelFamilies/IllogicalImpulseFamily.qml:93` instancia `OnScreenDisplay {}` no modo default. (NÃO confundir com `modules/ii/topLayer/osd/OsdDrop.qml` — esse é o OSD do modo **Connect** e não deve ser tocado.)
> **Agente executor:** leia cada task do começo ao fim e execute os passos literalmente. Não invente soluções alternativas. Use os tokens numéricos definidos no topo do arquivo OSD.
> **Regras globais do projeto (AGENTS.md):** nunca use `border`/`border.width > 0`, nunca use cores hex hardcoded (use `Appearance.colors.*` ou `Appearance.m3colors.*`), nunca use `radius` hardcoded (use `Appearance.rounding.*`), nunca instancie Singletons, sempre use widgets de `modules/common/widgets/`. Não adicione animações decorativas em loop (pulse/glow).

---

## Contexto Crítico que o agente precisa saber antes de começar

Antes de tocar em qualquer botão, leia e entenda estes fatos **descobertos na investigação**:

1. **O toggle de "system sounds" NÃO funciona porque a chave de config não existe.**
   - `Config.options.sounds` (`modules/common/Config.qml:1582-1586`) declara apenas `battery`, `pomodoro`, `theme`. **NUNCA** declara `enable`.
   - O código atual do OSD faz `Config.options.sounds.enable = !Config.options.sounds.enable` (linhas 559, 724) — como a chave não está declarada no `JsonObject`, o assign é silenciosamente ignorado e o binding de retorno lê `undefined` → sempre `false`.
   - **Consequência:** todos os `toggled:`/`colBackground:` baseados em `Config.options.sounds.enable` no `topButton` e `expandedTopSystemSoundsButton` lêem sempre falso/falsy → botão não muda visualmente ao clicar.

2. **A referência a `SoundService` é inválida.** `SoundService.preview(...)` (linhas 561, 726), `SoundService.volume` (linhas 760, 761) e `Audio.qml:114,149` usam `SoundService` que **não existe** como singleton em `services/` nem em `qmldir`. Resultado: warnings silenciosos no log e o slider de notificações fica sem dados.
   - **Decisão do plano:** NÃO criar `SoundService.qml`. Repor o toggle de system sounds para refletir o **mute real** do sink via `Audio.toggleMute()` / `Audio.sink.audio.muted` (esse é ocorrência do pedido "toggles não tem integração correta com Audio.qml"). O `notificationSoundSlider` deve ser repurpose para controlar o **volume do sink master** ou removido (ver Task A.3).

3. **Layout atual do expanded tem dois `ColumnLayout` siblings (`collapsedColumn` linhas 475-634, `expandedColumn` 636-910) que fazem cross-fade opaco por 200ms** — é justamente isso que o usuário quer trocar por um "slide horizontal suave dos elementos internos".

4. **Posicionamento do slider principal hoje:**
   - Em estado contracted: `collapsedColumn` está anchored top+right+bottom, slider `verticalSlider` dentro dele é o slider visível (Layout.fillHeight) à direita do OSD.
   - Em estado expanded: `mainVolumeSlider` dentro de `expandedSlidersRow` é o último filho da row (extrema direita) — coincide x com `verticalSlider`. Mas como ambos existem como instâncias separadas e há cross-fade de 200ms, há flicker.
   - O usuário quer **UM único slider principal fixo à direita**, com os outros sliders deslizando (fade horizontal) à esquerda dele. Isto exige REMOVER `verticalSlider` e `mainVolumeSlider` e criar uma única instância "persistente" ancorada à direita, fora dos columns.

5. **Mapeamento cor→token disponível no Appearance** (`modules/common/Appearance.qml`): as variantes de hover/active já existem para PRIMARY e SECONDARY_CONTAINER:
   - `colPrimary`, `colPrimaryHover`, `colPrimaryActive`, `colOnPrimary`, `colPrimaryContainer`, `colPrimaryContainerHover`, `colPrimaryContainerActive`, `colOnPrimaryContainer`
   - `colSecondaryContainer`, `colSecondaryContainerHover`, `colSecondaryContainerActive`, `colOnSecondaryContainer`
   - `colLayer1`, `colLayer1Hover`, `colLayer1Active`, `colOnLayer1`, `colLayer1Base`, `colLayer1Inactive`
   - `m3surfaceContainer`, `m3error`, `m3onError`, `m3errorContainer`, `m3onErrorContainer`, `m3outline`
   - Sombra: `Appearance.colors.colShadow` + componente `StyledDropShadow { target: <seuRectangle> }` (`modules/common/widgets/StyledDropShadow.qml`).

6. **Shadow NÃO pode interceptar cliques** (memória projeto #8). O `PanelWindow` já tem `mask: Region { item: osdGroupWrapper }` — manter isso; o shadow fica dentro do `osdGroupWrapper` mas Visívelmente fora do `osdContainer`, fora da máscara, sem `HoverHandler` próprio.

---

## PARTE 1 · Correções de Código e Refatoração

### Task A.1 — Adicionar schema de config que está faltando

**O quê:** Declarar chaves de configuração persistidas que o OSD já tentou (sem sucesso) ler/escrever, e adicionar as novas preferências exigidas pelo redesign.

**Onde:** `modules/common/Config.qml`, dentro do `property JsonObject sounds: JsonObject { ... }` (linha ~1582).

**Como:**

```qml
property JsonObject sounds: JsonObject {
    property bool battery: false
    property bool pomodoro: false
    property string theme: "freedesktop"
    property bool enable: true              // toggle "Mute system sounds" (USADO pelo topo do OSD de volume)
    property bool easyEffectsToggle: false // estado on/off salvo pelo toggle EasyEffects dentro do OSD
    property bool monoAudio: false         // estado on/off do toggle mono/stereo dentro do OSD
    property int volume: 70                // 0..100 — volume "system sounds preview" (será lido pelo notificationSoundSlider)
}
```

E dentro do `property JsonObject light: JsonObject { ... }` (linha ~1183), no nó `night`:

```qml
property JsonObject night: JsonObject {
    property bool automatic: true
    property string from: "19:00"
    property string to: "06:30"
    property int colorTemperature: 5000
    property int gammaTemperature: 4500   // 1000..6000 — usado pelo novo slider de nightlight tint dentro do OSD de brightness
}
```

Também no `property JsonObject light` (não dentro de night): adicionar `keyboardBacklight` se ainda não existir (default true) — apenas para registrar preferência de "ligar keyboard backlight ao usar o sistema" opcional (caso usemos depois). São key opcionais; não obrigatório declarar tudo. O essencial é `sounds.enable`, `sounds.easyEffectsToggle`, `sounds.monoAudio`, `sounds.volume` e `light.night.gammaTemperature`.

> **NOTA:** Toda nova propriedade num `JsonObject` aninhado deve ser `property bool`/`property int`/`property string` (tipo primitivo explícito) — nunca `property var` — per AGENTS.md §1 (evitar segfault reflexivo do `JsonAdapter`).

Após escrever as chaves, execute `qs log -f -c ii` e confirme que nenhum warning novo de QML aparece.

---

### Task A.2 — Reparar integração dos toggles com Audio.qml + "muted força slider a 0"

**O quê:** Reescrever toda referência a `Config.options.sounds.enable` no `topButton` (linhas 505-565) e no `expandedTopSystemSoundsButton` (linhas 656-731) para usar o mute real do sink. "Ao mutar o som, o slider deve ir para 0 imediatamente."

**Onde:** `modules/ii/onScreenDisplay/OnScreenDisplay.qml`.

**Como:**

1. Remover todos os bindings `Config.options.sounds.enable` dentro de `topButton` e `expandedTopSystemSoundsButton`. Substituir as 5 ocorrências (linhas 510, 519, 533, 542, 559, 665, 671, 685, 691, 705, 723) por:

   ```qml
   property bool _muted: Audio.sink?.audio?.muted ?? false
   ```

   No `toggled:` usar `_muted`. No `colBackground:` usar `_muted ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer`. No `colRipple:` usar `_muted ? Appearance.colors.colPrimaryActive : Appearance.colors.colSecondaryContainerActive`. No ícone: `_muted ? "volume_off" : "volume_up"`. No `color` do símbolo: `_muted ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer`.

2. No `onClicked` de ambos:
   ```qml
   Audio.toggleMute();
   root.triggerOsd();
   ```
   Remover qualquer referência a `SoundService.preview(...)`. Remover também o `Config.options.sounds.enable = !Config.options.sounds.enable`.

3. **Comportamento do slider ao mutar:** no `osdRoot`, já existe `property real displayValue: root.currentValue` com `Behavior on displayValue` habilitado apenas quando `!isDragging`. Modificar **o getter de `currentValue`** quando `currentIndicator === "volume"`:
   ```qml
   } else if (currentIndicator === "volume") {
       if (Audio.sink && Audio.sink.audio)
           return Audio.sink.audio.muted ? 0 : Audio.sink.audio.volume;
       return 0;
   }
   ```
   Assim, `displayValue` (e portanto o slider principal) cai para 0 imediatamente quando `muted` vira true. Não há necessidade de animação especial — o `SmoothedAnimation` do `Behavior on displayValue` (velocity 4.0) já cuida da transição visual em ~100ms.

4. **Comportamento inverso ao desmutar:** quando `muted` passa de true → false, o volume real anterior continua salvo no pipewire (pipewire não apaga volume ao mutar) → o binding reavalia e o slider volta ao valor real.

5. Reparar também a referência a `SoundService.volume` no `notificationSoundSlider` (linhas 760-761):
   ```qml
   from: 0
   to: 100
   value: Config.options.sounds.volume
   rawValue: Config.options.sounds.volume / 100
   tooltipContent: Math.round(value) + "%"
   usePercentTooltip: true
   onMoved: {
       Config.options.sounds.volume = Math.round(value);
       root.triggerOsd();
   }
   ```
   (Slider agora opera em 0-100, com `usePercentTooltip: true` conforme SpecsMembership do `StyledVerticalSlider`.)

**Verificação:** abra o shell, abra o OSD de volume, clique no botão do topo → ícone deve virar `volume_off` e slider cair a 0 imediatamente. Clique novamente → ícone `volume_up` e slider volta ao valor real.

---

### Task A.3 — Refatorar animações expand/contract para o novo comportamento de "slide horizontal"

**O quê:** Trocar o cross-fade atual (`collapsedColumn.opacity 0↔1` vs `expandedColumn.opacity 0↔1`, ambos 200ms) por:
- Drop do `collapsedColumn` e `expandedColumn` como dois layouts paralelos que aparecem/desaparecem por opacidade.
- Substituir por uma única `osdContainer` ColumnLayout que sempre renderiza; anexar elementos "extras" (sliders adicionais + toggles) com `OpacityMask` em gradiente horizontal dependendo de `expandedProgress`.
- O `topButton` é instância única ancorada ao topo-direita, crescendo em largura (sem trocar de instância).
- O slider principal fica fixo à direita, mesmo durante a animação.

**Sintaxe de implementação Do agente (concreta):**

1. **Remova:** todo o `ColumnLayout { id: collapsedColumn ... }` (linhas 475-634) e o `ColumnLayout { id: expandedColumn ... }` (linhas 636-910). Mantenha o `osdContainer` Rectangle.

2. Dentro do `osdContainer` (após o `color`/`radius`), criar uma única estrutura:
   ```qml
   ColumnLayout {
       id: osdLayout
       anchors.fill: parent
       anchors.margins: osdMargin
       spacing: osdItemSpacing

       // (1) Top button — único, anchored fillWidth, com Behavior on Layout.preferredWidth
       OsdTopButton { id: topButton; ... }   // ver Task A.3.1

       // (2) Section title "Output" (label)
       OsdSectionLabel { text: Translation.tr("Output") }

       // (3) Device output selector (apenas no indicator de volume)
       OsdDeviceOutputButton { id: deviceOutputButton; visible: currentIndicator === "volume"; ... }

       // (4) Sliders row (altura fill)
       OsdSlidersRow {
           id: slidersRow
           Layout.fillWidth: true
           Layout.fillHeight: true
           LockMainSliderRight: true
       }

       // (5) Section title "Input" visivel apenas no volume
       OsdSectionLabel { visible: currentIndicator === "volume"; text: Translation.tr("Input") }

       // (6) Linha de toggles fill-width — endereçada na Task B.1
       OsdToggleRow { id: toggleRow; ... }

       // (7) Collapse button — bottom-right, anchored
       OsdCollapseButton { id: collapseButton; ... }
   }
   ```

3. Em vez de cross-fade, **animação por `expandedProgress` 0→1**:
   - Os elementos "extras" (todos exceto `topButton`, `mainVolumeSlider` e `collapseButton`) ficam embrulhados num `Item { id: expandableContainer; opacity: expandedProgress; visible: expandedProgress > 0.001; width: ... ; height: ... }`.
   - Quando `expandedProgress === 0`: `expandableContainer` invisível, `topButton` tem width = `osdButtonHeight` (círculo), `mainVolumeSlider` visível à direita; o OSD fica visualmente igual ao estado contracted.
   - Quando `expandedProgress === 1`: tudo visível e `topButton` tem fill width.

4. — Largura do osdContainer anima conforme expanded:
   ```qml
   width: osdContractedWidth + (osdExpandedWidth - osdContractedWidth) * osdRoot.expandedProgress
   ```
   (mantém o `Behavior on width` existente, linhas 456-461.)

5. — TopButton growth: declarar `Layout.preferredWidth: osdButtonHeight + (osdLayout.width - osdButtonHeight - osdCollapseButtonWidth) * osdRoot.expandedProgress`. Adicionar `Behavior on Layout.preferredWidth { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }`. Visualmente: o botão começa como quadrado à direita (44 de largura) e cresce para a esquerda até preencher quase toda a largura superior.

6. Sliders extras surgem à esquerda do slider principal com fade horizontal:
   - Criar um `Item { id: extrasSliders; anchors.right: mainVolumeSlider.left; anchors.rightMargin: osdGroupSpacing; height: mainVolumeSlider.height; width: (mainVolumeSlider.x - osdMargin - osdGroupSpacing) * expandedProgress }`.
   - Dentro dele os sliders adicionais (`notificationSoundSlider + Repeater programPlaybackRepeater + micSlider when applicable`).
   - Aplicar `layer.enabled: true; layer.effect: OpacityMask { maskSource: extrasFadeMask }`; `extrasFadeMask` é um `Canvas` que desenha um `LinearGradient` horizontal **alpha** com cores `Qt.rgba(1,1,1,0)` (esquerda) → `Qt.rgba(1,1,1,1)` (direita); preencher todo o `extrasSliders.width`. Sempre que `expandedProgress` mudar, chamar `requestPaint()` para o Canvas redesenhar a faixa opaca correspondente à progressão.
   - Quando `expandedProgress === 0`: a `extrasSliders.width === 0` e o mask faz tudo invisível → sem sliders extras.
   - Quando `expandedProgress === 1`: todos os extras opacos → transição completa.

> **CRÍTICO:** o `mainVolumeSlider` não sofre fade e nem é movido durante a animação — fica fixo à direita. O `extrasSliders` cresce à esquerda dele, com gradient fade do transparente (esquerda) para o opaco (junto ao slider principal).

7. Os demais elementos (seção de toggles, etc.) ani**mam** só verticalmente: `opacity: expandedProgress`, com `Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.InOutQuad } }`. Sem translação em Y, pois o usuário só pediu o slide horizontal suave para os sliders.

8. Remover todos os console.log de "OSD DEBUG" (linhas 453-454).

**Verificação:** ao clicar no collapse button, o slider principal fica fixo à direita sem nenhum salto visual. Os demais sliders adicionais surgem da esquerda em fade horizontal macio.

---

### Task A.3.1 — Extrair subcomponentes do OSD para arquivos próprios

**O quê:** Quebrar o arquivo gigante `OnScreenDisplay.qml` (1037 linhas) em componentes reutilizáveis em `modules/ii/onScreenDisplay/components/` (criar pasta). O arquivo principal fica apenas com a lógica de janela + estado, delegando tudo visual aos subcomponentes.

**Onde:** criar `modules/ii/onScreenDisplay/components/` com os 6 sub-arquivos abaixo.

**Como — criar/transferir código para:**

| Arquivo | Conteúdo | Observações |
|---|---|---|
| `components/OsdTopButton.qml` | O `topButton` (instância única com `grow horizontal`). Props expostas: `currentIndicator`, `isExpanded`, emits `clicked()`. Internamente decide lógica por `currentIndicator` (mute sink, dark mode, osk open) — herdam do código original linhas 505-565, mas com cores STANDARDIZADAS (ver Task C.1). |
| `components/OsdCollapseButton.qml` | botão de expand/collapse circular com ícone `keyboard_arrow_left` + `Rotation` (animado). Props: `isExpanded`, `hasExpandableIndicator` (bool): emite `clicked()`. |
| `components/OsdSectionLabel.qml` | `StyledText` com `font.pixelSize: Appearance.font.pixelSize.smaller; font.bold: true; color: Appearance.m3colors.m3outline; text: <required string>`. Apenas estrutura. |
| `components/OsdSlidersRow.qml` | Item com o `mainVolumeSlider` (fixo à direita) + `extrasSliders` (cresce à esquerda com fade horizontal). Props: `currentIndicator`, `expandedProgress`, `isDragging`. Internamente instancia `StyledVerticalSlider` principal + `Repeater` (program playback) resp. `StyledVerticalSlider` (mic / notif / gamma / nightlight / gammaSlider). Respeita o **Spacing Rules** da Task A.4. |
| `components/OsdToggleRow.qml` | RowLayout com os botões fill-width (EasyEffects, Mono/Stereo, Mute Mic, System Sounds, Keyboard Backlight, Nightlight Toggle). Renderiza condicionalmente conforme `currentIndicator`. Ver Task B.1 para conteúdo. |
| `components/OsdDeviceOutputButton.qml` | RippleButton fill-width com ícone `media_output` + nome do device ativo (ler `Pipewire.defaultAudioSink?.description`). Click abre `OsdDeviceOutputPopup`. |

Parent `ColumnLayout` do `OnScreenDisplay.qml` importa o namespace `qs.modules.ii.onScreenDisplay.components` para usar todos.

> **NOTa:** Os subcomponentes **nÃO** devem declarar `width`/`height` explícitos — todos os tamanhos viram props passados do pai (ver Task A.4 de tokens).

---

### Task A.4 — Eliminar todos os tamanhos hardcoded; centralizar tokens no topo do arquivo

**O quê:** Substituir todos os números hardcoded de dimensão (44, 56, 180, 38, 8, 6, 296, 396, 220, 12, 28, 22, 24, 350, 200, 400) por tokens declarados **no topo do `osdRoot` PanelWindow** (dentro do `PanelWindow` sourceComponent do `osdLoader`).

**Onde:** `modules/ii/onScreenDisplay/OnScreenDisplay.qml`, no início do corpo do `PanelWindow { id: osdRoot }` (logo após a linha `Component.onCompleted: { openedProgress = 1.0; }`).

**Como:**

Adicionar este bloco antes de qualquer `Item`:

```qml
// === SIZING TOKENS (declared once, derived) ===
// úNICO valor de altura hardcoded do OSD; tudo o mais deriva dele:
readonly property real osdBaseHeight: 600
readonly property real osdMargin: 12                  // margin H/V uniforme dentro do osdContainer
readonly property real osdItemSpacing: 10             // vertical spacing entre items no ColumnLayout
readonly property real osdRowSpacing: 8                // in-group spacing (entre sliders do mesmo grupo)
readonly property real osdGroupSpacing: 28            // cross-group spacing (entre grupos de sliders)
readonly property real osdButtonHeight: 56            // altura dos toggles/circle buttons
readonly property real osdCollapseButtonHeight: 44    // botão circular de collapse
readonly property real osdSliderTrackWidth: 38        // configuration dos sliders verticais (token M do StyledVerticalSlider)
readonly property real osdSliderFillHeight: osdBaseHeight - 2 * osdMargin - 2 * osdButtonHeight - 3 * osdItemSpacing - osdCollapseButtonHeight  // tem que casar — virado para altura do sliders row

// largura contracted: largura mínima = 2*margin + slider track/configuração == 2*osdMargin + SliderTrackWidth + 16 de folga (mesma largura do topButton circle)
readonly property real osdContractedWidth: 2 * osdMargin + osdButtonHeight

// largura expanded: deve ser "grande horizontalmente" — empiricamente:
readonly property real osdExpandedWidth: 760          // grande horizontalmente conforme requirement

// largura dos subelementos extras inferiores (sliders)
readonly property real osdExtrasMaxWidth: osdExpandedWidth - osdContractedWidth  // espaço total disponível à esquerda do slider principal
```

Regras a observar ao migrar o código:

1. **Nenhum subcomponente deve declarar `width:` ou `height:`** literal. Tudo via `Layout.fillWidth: true` / `Layout.fillHeight: true` / `Layout.preferredHeight: <token>`.
2. Os `RippleButton` (topButton, toggles, collapse) usam `Layout.preferredHeight: osdButtonHeight` (ou `osdCollapseButtonHeight` para o collapse).
3. Cada `StyledVerticalSlider` usa `Layout.fillWidth: true` (o `StyledVerticalSlider` já faz `Layout.fillHeight: true` internamente linhas 62) e `property configuration: osdSliderTrackWidth` — nunca hardcoded 38.
4. As ancoras do `osdContainer` dentro de `osdGroupWrapper` devem usar `osdMargin` em vez de 6/16/etc.
5. Altura do `osdContainer`: `height: osdBaseHeight`. Altura do `osdGroupWrapper`: `osdBaseHeight + 2 * osdMargin` (espaço extra para shadow).
6. `radius` do `osdContainer`: usar `Appearance.rounding.windowRounding` quando expanded, `Appearance.rounding.full` quando contracted (afina para pílula quando contract). Mantém `Behavior on radius`.

**Remover todos estes números hardcoded:**
| Aparece em | Token que substitui |
|---|---|
| `Layout.preferredWidth: 44 / 56` (botões) | `osdButtonHeight` |
| `Layout.preferredHeight: 44 / 56` (botões) | `osdButtonHeight` |
| `buttonRadius: 22 / 28` | `osdButtonHeight / 2` |
| `Layout.preferredHeight: 180` (sliders) | `osdSliderFillHeight` (Layout.fillHeight:true) |
| `configuration: 38` | `osdSliderTrackWidth` |
| `spacing: 6 / 8` (ColumnLayout) | `osdItemSpacing` |
| `spacing: 6` (RowLayout expandedSlidersRow) | `osdRowSpacing` |
| `topMargin: 6; rightMargin: 6; bottomMargin: 6` | `osdMargin` |
| `implicitWidth: 56; implicitHeight: 120` (OsdProgramSlider) | `implicitWidth: osdButtonHeight; implicitHeight: osdSliderFillHeight` |
| `iconSize: 22/24/20` (MaterialSymbol) | `Appearance.font.pixelSize.normal / Appearance.font.pixelSize.huge` — nunca hardcoded |

Tornar `osdContractedWidth` e `osdExpandedWidth` **readonly properties** no `osdContainer`. Usar:
```qml
width: osdContractedWidth + (osdExpandedWidth - osdContractedWidth) * osdRoot.expandedProgress
```

---

### Task A.5 — Spacing Rules para grupos de sliders

**O quê:** Implementar o padrão "space-between groups, with larger spacing separating groups than within" dentro do `OsdSlidersRow`.

**Onde:** `modules/ii/onScreenDisplay/components/OsdSlidersRow.qml`.

**Como (regra concreta):**

- `OsdSlidersRow` é um `RowLayout { spacing: osdRowSpacing; Layout.fillWidth: true; Layout.fillHeight: true; layoutDirection: Qt.RightToLeft }` (RightToLeft para que o `mainVolumeSlider` fique à direita ao ser declarado primeiro).
- Inserir **ITEM separador** explicitamente entre grupos:
  - **Sliders do grupo de Program Playback** (Repeater de `OsdProgramSlider`) — `Layout.fillHeight: true`.
  - `Item { Layout.preferredWidth: osdGroupSpacing }` (espaçador entre grupos, mais largo que `osdRowSpacing`).
  - **Sliders do grupo de System Sounds** (`notificationSoundSlider` e `mainVolumeSlider`) — separados por `osdRowSpacing` entre si.
  - (Para o indicator de volume): outro `Item { Layout.preferredWidth: osdGroupSpacing }` + **Mic slider** (separate group).
  - (Para o indicator de brightness): outro `Item { Layout.preferredWidth: osdGroupSpacing }` + `gammaSlider` + `nightlightSlider`.

> **NOTA:** o `mainVolumeSlider` é filho de `OsdSlidersRow` (declarado por último, ou primeiro com RightToLeft) — nunca está dentro do expandable extras container. A única maneira dele sumir é se `currentIndicator` mudar para algo não-volume — nesse caso é a props do `OsdSlidersRow` que decide qual é o `main` slider conforme indicator.

Ordem dentro do RowLayout RightToLeft (portanto da direita→esquerda):
1. `mainVolumeSlider` (extrema direita, FIXO — fade nunca se aplica).

2. (Grupos adicionais surgem à esquerda.)
   - Volume indicator: `Item { Layout.preferredWidth: osdGroupSpacing; opacity: expandedProgress }` → `notificationSoundSlider (opacity: expandedProgress)` → `Item spacer` → `programPlaybackRepeater (opacity: expandedProgress)` → `Item spacer (larger)` → `micSlider (opacity: expandedProgress)` (se aplic igualable no mesmo grupo ou em grupo separado).
   - Brightness indicator: `mainVolumeSlider` é o `brightnessSlider` real (mesma instância reconfigurada via `currentIndicator`). À esquerda: `gammaSlider` e `nightlightSlider` em grupos separados.

Os novos sliders do brightness (`gammaSlider`, `nightlightSlider`, `keyboardSlider`) podem ser agrupados: Gamma Group | Nightlight Group | Keyboard backlight group — cada grupo com fill-size entre si e separators de `osdGroupSpacing` entre grupos.

---

### Task A.6 — Fix do Slider widget: valor sempre no topo da highlight part; corrigir resolução do handler

**O quê:** Dois bugs em `StyledVerticalSlider` (linhas 1-219):
1. O número do valor (texto) aparece em locais inconsistentes — deve aparecer no **topo da highlight part** (acima do handle, dentro da parte ativa do track).
2. "Handler parece ter resolução baixa" — apresenta-se com intents de pixel quebrados; trata-se do `implicitHeight` e `y` do handle estarem float sem arredondamento + o `handleMargins` multiplicado per-pixel.

**Onde:** `modules/common/widgets/StyledVerticalSlider.qml`.

**Como:**

1. **Ajustar o do handle:** No `handle: Rectangle { ... }` (linha 152), arredondar `y` e altura:
   ```qml
   y: Math.round(root.topPadding + (root.visualPosition * root.effectiveDraggingHeight) - (root.handleHeight / 2))
   implicitHeight: Math.round(root.handleHeight)
   implicitWidth: Math.round(root.handleWidth)
   width: implicitWidth
   height: implicitHeight
   ```
   Adicionar `layer.samples: 4` no handle para suavizar edge antialiasing.

2. **Valor sempre acima da highlight (caindo para 0 ocultar fallback):**
   - Substituir o `StyledText` final (linhas 205-218) por um `StyledText` ancorado ao TOP da parte ativa do track:
   ```qml
   StyledText {
       id: valueTooltipInline
       parent: background  // fica sobre o track ativo
       anchors.horizontalCenter: background.horizontalCenter
       anchors.bottom: background.activeValues.length > 0
              ? undefined
              : background.top   // quando visualPosition === 0, fica no topo do track
       y: Math.round(root.topPadding + (root.visualPosition * root.effectiveDraggingHeight) - height - 4)
       text: Math.round(root.rawValue * 100)
       color: {
           if (root.rawValue > root.to) return Appearance.colors.colOnErrorContainer;
           return Appearance.colors.colOnPrimary;
       }
       font.pixelSize: Appearance.font.pixelSize.smaller
       font.bold: true
       visible: (Config.ready && Config.options.osd.showValues) || (root.rawValue > root.to)
       Behavior on y { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
   }
   ```
   - **Caso especial:** quando `rawValue` é 0, o handle cobrirá o texto (handle fica no fundo do track). Neste caso, o texto deve aparecer **acima** do track em vez de acima do handle:
   ```qml
   y: root.rawValue < 0.05
      ? Math.round(root.topPadding + 2)  // topo do track todo
      : Math.round(root.topPadding + (root.visualPosition * root.effectiveDraggingHeight) - height - 4)
   ```
   Isso faz com que o número sempre fique acima do handle na altura atual, e quando `value=0`, aparece no topo do track.

3. Y do ícone `MaterialSymbol` (linhas 177-186) já está ok (`anchors.bottom: nearBottom ? handle.bottom : root.bottom`); apenas substituir `iconSize: 18` hardcoded por `Appearance.font.pixelSize.normal`.

4. Adicionar `Behavior on value`: o `SmoothedAnimation { velocity: Appearance.animation.elementMoveFast.velocity }` já existe (linhas 66-70). Manter — isso garante que quando o usuário move manualmente o slider, há uma transição controlada; ao arrastar (`pressed` true), o Qt pula direto. Mantém.

5. **NOTA DO USUÁRIO — Limite do slider principal de volume:** o slider principal deve ir APENAS até 1.0 (100%). Valores acima de 1.0 (até `osdRoot.maxLimit` = 1.5) são representados apenas via `rawValue` (número) e coloração `colError`. Portanto, **não alterar `to: 1.0`** — mantenha conforme a config do usuário "audio.protection". O código atual está correto em `to: (root.currentIndicator === "volume" || root.currentIndicator === "playerVolume") ? 1.0 : osdRoot.maxLimit`. Apenas documentar com comentário inline:
   ```qml
   // DO NOT change `to: 1.0` for volume. Values > 100% are represented by the error color
   // and the rawValue tooltip, but the slider track itself fills only to 100%.
   ```

---

## PARTE 2 · Features Novas

### Task B.1 — Expanded Volume: toggles EasyEffects, Mono/Stereo, Mic volume slider, Mute mic, Device output selector

**O quê:** Adicionar ao expanded do indicator de volume:
- Toggle EasyEffects (liga/desliga EasyEffects)
- Toggle Mono/Stereo (cria serviço para isto)
- Slider de Microphone volume (controla `Audio.source.audio.volume`)
- Toggle Mute Mic (toggle `Audio.source.audio.muted`)
- Botão Device Output (abre popup que lista `Audio.outputDevices`)

**Layout (o agente está encarregado disso):** dentro do `OsdToggleRow` (`components/OsdToggleRow.qml`), quando `currentIndicator === "volume"`, renderize:

```
[ === Volume OSD expanded layout: 5 ROWS na vertical dentro do expandedColumn === ]

ROW A (topo) — Mute Output toggle (sempre presente — alvo: Audio.sink mute)
  · fill-width (Layout.fillWidth:true)
  · height: osdButtonHeight
  · ícone: mute ? "volume_off" : "volume_up"
  · texto: mute ? "Unmute output" : "Mute output"
  · cores: colPrimary quando muted (toggled=true), colSecondaryContainer quando unmuted
  · onClicked: Audio.toggleMute(); root.triggerOsd()

ROW B — Device Output selector (NOVO componente OsdDeviceOutputButton)
  · fill-width, height osdButtonHeight
  ·ColBackground: colSecondaryContainer (sempre secondary: ainda não é uma "ação ativa")
  · ícone esquerda: "media_output"
  · texto principal: "Output device"
  · texto secundário (em linha menor): Pipewire.defaultAudioSink?.description
  · onClicked: abre OsdDeviceOutputPopup (ver Task B.1.D)

(secção label) "Sliders" (OsdSectionLabel)

ROW C — Sliders Row (altura fill, agrupa 3 grupos de sliders):
  Grupos:
    [GRUPO Program Playback] — Repeater de OsdProgramSlider (um por Audio.outputAppNodes)
      · spacing entre cada: osdRowSpacing
    [SPACER] — Item width = osdGroupSpacing (visualmente separa)
    [GRUPO System Sounds] — notificationSoundSlider + mainVolumeSlider
      · spacing entre cada: osdRowSpacing
    [SPACER]
    [GRUPO Input/Mic] — micSlider (StyledVerticalSlider fillHeight)
      · spacing entre cada grupo, usando osdGroupSpacing

(secção label) "Audio Options" (OsdSectionLabel)

ROW D — Row com 2 toggles fill-width:
  · Toggle EasyEffects (icon "graphic_eq")
    · toggled: EasyEffects.active
    · onClicked: EasyEffects.toggle()
    · cores STANDARD: colSecondaryContainer quando off, colPrimary quando on
  · Toggle Mono/Stereo (icon "hearing")
    · toggled: Config.options.sounds.monoAudio
    · onClicked: MonoAudioService.toggle(); (ver Task B.1.A)
    · ícone de on/off:
      · on  → "hearing_disabled" + "Mono"
      · off → "surround_sound" + "Stereo"
    · cores STANDARD

ROW E — Row com 2 toggles fill-width:
  · Toggle Mute Mic (icon mute ? :"mic_off":"mic")
    · toggled: Audio.source?.audio?.muted ?? false
    · onClicked: Audio.toggleMicMute()
  · Toggle System Sounds enable (icon "volume_up")
    · toggled: Config.options.sounds.enable (AGORA funciona pq schema foi declarado)
    · onClicked: Config.options.sounds.enable = !checked
    · ON → "pause_circle"; OFF → unmute icon "play_circle" (representa ability de testar "playEvent")

ROW F — Collapse Button (canto inferior direito):
  · OsdCollapseButton anchored right, width = osdCollapseButtonHeight (44), height = osdCollapseButtonHeight
```

> **NOTA:** O agente DEVE usar a coluna de cores explicitada na Task C.1: terciária/container inativo, primária ativo.

#### Task B.1.A — Criar `services/MonoAudioService.qml`

**O quê:** Singleton pequeno para alternating entre stereo e down-mixing mono usando `pactl load-module module-remap-sink` (downmix L+R into both L+R) + mudar default sink, e restaurar quando desligar.

**Onde:** `services/MonoAudioService.qml` (novo arquivo).

**Como:**

```qml
pragma Singleton
pragma ComponentBehavior: Bound
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

Singleton {
    id: root

    property bool active: false            // true = mono downmix ON
    property int loadedModuleIndex: -1     // pactl load-module returns module index
    property string savedDefaultSinkName: "" // para restaurar
    readonly property string monoSinkName: "ii_mono_downmix"

    function toggle() {
        root.active ? root.disable() : root.enable()
    }
    function enable() {
        if (root.active) return
        const masterSinkName = Audio.sink?.name ?? ""
        if (!masterSinkName) return
        root.savedDefaultSinkName = masterSinkName
        // Loads a remap sink that downmixes stereo to mono in both channels
        enableProc.command = ["bash", "-c",
            `pactl load-module module-remap-sink sink_name=${root.monoSinkName} master=${masterSinkName} channels=2 channel_map=mono,mono master_channel_map=left,right sink_properties=device.description='ii-Mono'`]
        enableProc.running = true
    }
    function disable() {
        if (!root.active) return
        disableProc.command = ["bash", "-c",
            `pactl unload-module ${root.loadedModuleIndex}` +
            (root.savedDefaultSinkName ? `; pactl set-default-sink ${root.savedDefaultSinkName}` : "")]
        disableProc.running = true
        root.active = false
    }
    Process { id: enableProc; stdout: SplitParser { onRead: d => { const idx = parseInt(d.trim()); if (!isNaN(idx)) { root.loadedModuleIndex = idx; root.active = true; Quickshell.execDetached(["pactl", "set-default-sink", root.monoSinkName]); } } } }
    Process { id: disableProc; onExited: (code, st) => { root.loadedModuleIndex = -1; root.savedDefaultSinkName = ""; } }
}
```

> **NOTA tropeço linguagem:** O `pactl load-module` escreve o module index no `stdout` na primeira linha. Atribuir esse status a `loadedModuleIndex`.

> **LIMITA:** Não garanti restauração quando Pipewire re inicializa ou quando o sink master muda. É aceitável para um.optional feature; user pode toggle para reset.

Adicionar `MonoAudioService` no `qmldir` implícito de `qs.services` se necessário (não há qmldir explícito, ele deverá ser resolvido por nome. Verificar com `qs log -f -c ii` por warnings. Se não for resolvido, criar `services/qmldir` com `singleton MonoAudioService MonoAudioService.qml`.)

#### Task B.1.B — Slider de Microphone Volume

**O quê:** Slider vertical que controla o volume do `Audio.source.audio.volume`.

**Onde:** `components/OsdSlidersRow.qml` (novo), dentro do grupo "Input/Mic" quando `currentIndicator === "volume"`.

**Como:**

```qml
StyledVerticalSlider {
    id: micSlider
    Layout.fillHeight: true
    configuration: osdSliderTrackWidth
    from: 0
    to: 100
    usePercentTooltip: true
    value: Math.round((Audio.source?.audio?.volume ?? 0) * 100)
    rawValue: (Audio.source?.audio?.volume ?? 0)
    materialSymbol: "mic"
    shape: MaterialShape.Shape.Circle
    onMoved: {
        if (Audio.source && Audio.source.audio) {
            Audio.source.audio.volume = value / 100;
            if (Audio.source.audio.muted && value > 0) {
                Audio.source.audio.muted = false;
            }
        }
        root.triggerOsd();
    }
    // Track/handle colors STANDARD: usar cores STANDARD (ver Task C.1) — herda defaults de StyledVerticalSlider (que já usa colPrimary/colSecondaryContainer).
}
```

> Quando ` Audio.source.audio.muted === true`, mostrar overlay de "muted" igual ao `OsdProgramSlider` (padrão: Rectangle semi-transparente com ícone `mic_off` em cima do símbolo).

#### Task B.1.C — Toggle Mute Mic

Fazer parte da ROW E no layout (ver Task B.1). Ligação:

```qml
OsdToggleIconButton {
    iconText: (Audio.source?.audio?.muted ?? false) ? "mic_off" : "mic"
    label: (Audio.source?.audio?.muted ?? false) ? Translation.tr("Unmute mic") : Translation.tr("Mute mic")
    toggled: (Audio.source?.audio?.muted ?? false)
    onClicked: {
        Audio.toggleMicMute();
        root.triggerOsd();
    }
}
```

#### Task B.1.D — Device Output Popup

**O quê:** Popup compacto que lista os `Audio.outputDevices` (sinks físicos). Replicação simplificada do `VolumeDeviceEntry` (visto em `modules/ii/sidebarDashboard/volumeMixer/VolumeDialogContent.qml:241-540`), porém como Window Dialog/Popup flutuante.

**Onde:** criar dois arquivos novos:
- `modules/ii/onScreenDisplay/components/OsdDeviceOutputButton.qml` — botão.
- `modules/ii/onScreenDisplay/popups/OsdDeviceOutputPopup.qml` — popup em si.
- `modules/ii/onScreenDisplay/popups/OsdDeviceOutputItem.qml` — delegate de cada device.

**Como:**

Usar `StyledPopup` (componente existente em `modules/common/widgets/StyledPopup.qml`).

```qml
// OsdDeviceOutputButton.qml
RippleButton {
    id: button
    Layout.fillWidth: true
    Layout.preferredHeight: osdButtonHeight
    buttonRadius: Appearance.rounding.normal
    colBackground: Appearance.colors.colSecondaryContainer
    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
    colRipple: Appearance.colors.colSecondaryContainerActive
    contentItem: RowLayout {
        spacing: 12
        MaterialSymbol { text: "media_output"; iconSize: Appearance.font.pixelSize.normal; color: Appearance.colors.colOnSecondaryContainer }
        ColumnLayout {
            spacing: 0
            StyledText { text: Translation.tr("Output device"); font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colOnSecondaryContainer; Layout.fillWidth: true; elide: Text.ElideRight }
            StyledText { text: Pipewire.defaultAudioSink?.description ?? ""; font.pixelSize: Appearance.font.pixelSize.smaller; color: Appearance.m3colors.m3outline; Layout.fillWidth: true; elide: Text.ElideRight }
        }
    }
    onClicked: {
        deviceOutputPopupLoader.active = true
        deviceOutputPopupLoader.item.show()
        root.triggerOsd()
    }
}
Loader {
    id: deviceOutputPopupLoader
    active: false
    sourceComponent: OsdDeviceOutputPopup {}
}
```

`OsdDeviceOutputPopup` estende `StyledPopup` com:
- `width: 320`, `height: 360`
- `Repeater { model: Audio.outputDevices; delegate: OsdDeviceOutputItem { ... } }`
- Cada item: `RippleButton` fill-width:
  - ícone esquerda: ícone dinâmico baseado em tipo (mute | vol_up | vol_down | vol_mute)
  - nome: `Audio.friendlyDeviceName(node)`
  - índice atual destacado com `colPrimary` (igual ao `devEntry.isActive` linhas 264-290 do VolumeDialogContent)
  - onClicked: `Audio.setDefaultSink(modelData)`

#### Task B.1.E — EasyEffects Toggle

Implementação simples dentro do `OsdToggleRow`:

```qml
OsdToggleIconButton {
    iconText: "graphic_eq"
    label: EasyEffects.active ? Translation.tr("Disable EasyEffects") : Translation.tr("Enable EasyEffects")
    toggled: EasyEffects.active
    onClicked: EasyEffects.toggle()
}
```

---

### Task B.2 — Expanded Brightness: Gamma slider + Nightlight tint temperature slider + Keyboard backlight toggle

**O quê:** Dentro do expanded do indicator de brightness (`currentIndicator === "brightness"`):
- Slider de Gamma (25 a 100)
- Slider de Nightlight tint temperature (1000 a 6000)
- Toggle Keyboard Backlight (liga/desliga backlight)

**Layout dentro do expandedColumn quando brightness indicator:**

```
ROW A — Dark Mode toggle (top button, fill width — COMPORTAMENTO EXISTENTE mantém)
  · currentIndicator === "brightness" → toggle DarkMode.
  · Cores STANDARD conforme Task C.1.

(secção label) "Display"

ROW C — Sliders Row (grupos de sliders verticais):
  · brightnessSlider (FIXO à direita via RightToLeft layout, fillWidth)
  · [Spacer osdGroupSpacing]
  · gammaSlider (35-100 via Hyprsunset.setGamma)
  · [Spacer osdGroupSpacing]
  · nightlightSlider (1000-6000, seta Config.options.light.night.gammaTemperature + chama Hyprsunset.enableTemperature() se valor != 6000)
  · [Spacer osdGroupSpacing]
  · keyboardBacklightSlider (0..100, usa KeyboardBacklight.setValue) — slider também pode existir em contracted? Simplesmente expanded.

(secção label) "Backlight & Nightlight"

ROW D — Row com 2 toggles fill-width:
  · Nightlight Toggle (icon "wb_twilight") — mantém o comportamento do `expandedBottomMusicButton` original (linhas 803-870) para brightness:
    · toggled: Hyprsunset.temperatureActive
    · onClicked: Hyprsunset.toggleTemperature()
  · Keyboard Backlight Toggle (icon "keyboard")
    · toggled: KeyboardBacklight.currentValue > 0
    · onClicked: KeyboardBacklight.setValue(KeyboardBacklight.currentValue > 0 ? 0 : KeyboardBacklight.maxValue)

ROW E — Collapse Button (Canto inferior direito)
```

**Implementação concreta:**

Gamma slider (conecte ao `Hyprsunset.gamma`):

```qml
StyledVerticalSlider {
    id: gammaSlider
    Layout.fillHeight: true
    configuration: osdSliderTrackWidth
    from: Hyprsunset.gammaLowerLimit   // 25
    to: 100
    usePercentTooltip: false
    tooltipContent: Hyprsunset.gamma + "%"
    value: Hyprsunset.gamma
    rawValue: Hyprsunset.gamma
    materialSymbol: "wb_twilight"
    shape: MaterialShape.Shape.Circle
    onMoved: {
        Hyprsunset.setGamma(Math.round(value));
        root.triggerOsd();
    }
    visible: root.currentIndicator === "brightness"
}
```

Nightlight temperature slider:

```qml
StyledVerticalSlider {
    id: nightlightSlider
    Layout.fillHeight: true
    configuration: osdSliderTrackWidth
    from: 1000
    to: 6000
    usePercentTooltip: false
    tooltipContent: Math.round(value) + "K"
    value: Config.options.light.night.gammaTemperature
    rawValue: Config.options.light.night.gammaTemperature
    materialSymbol: "wb_iridescent"
    shape: MaterialShape.Shape.Circle
    onMoved: {
        Config.options.light.night.gammaTemperature = Math.round(value);
        // se chega 6000, desativa temperature; se diferir de 6000, ativa
        if (Math.round(value) === 6000) {
            Hyprsunset.disableTemperature();
        } else {
            Hyprsunset.enableTemperature();
        }
        root.triggerOsd();
    }
    visible: root.currentIndicator === "brightness"
}
```

Keyboard backlight slider:

```qml
StyledVerticalSlider {
    id: keyboardBacklightSlider
    Layout.fillHeight: true
    configuration: osdSliderTrackWidth
    from: 0
    to: 100
    usePercentTooltip: true
    value: KeyboardBacklight.percentage
    rawValue: KeyboardBacklight.percentage / 100
    materialSymbol: "keyboard"
    shape: MaterialShape.Shape.Hexagon
    onMoved: {
        if (KeyboardBacklight.available && KeyboardBacklight.ready) {
            const step = Math.round(value * KeyboardBacklight.maxValue / 100);
            KeyboardBacklight.setValue(step);
        }
        root.triggerOsd();
    }
    visible: root.currentIndicator === "brightness" && KeyboardBacklight.available
}
```

Keyboard backlight toggle (Row E):

```qml
OsdToggleIconButton {
    iconText: "keyboard"
    label: KeyboardBacklight.currentValue > 0 ? Translation.tr("Keyboard backlight off") : Translation.tr("Keyboard backlight on")
    toggled: KeyboardBacklight.currentValue > 0
    onClicked: {
        if (KeyboardBacklight.available && KeyboardBacklight.ready) {
            KeyboardBacklight.setValue(KeyboardBacklight.currentValue > 0 ? 0 : KeyboardBacklight.maxValue);
        }
        root.triggerOsd();
    }
}
```

Existing top button (`OsdTopButton`) for brightness mantém toggle DarkMode (currentIndicator === "brightness" → uso de `DarkModeService.enableDarkMode/disableDarkMode`). Agora no expanded FARÁ uso de cores padronizadas: `colPrimary` quando dark mode ative, `colSecondaryContainer` quando inativo. (Substituir `Appearance.colors.colLayer2` existentes — linhas 514, 517, 519, 670, 672, 689, 691, 705, 708.)

---

## PARTE 3 · Mudanças de Design

### Task C.1 — Padronização completa das cores

**O quê:** Toda a UI do OSD deve usar EXCLUSIVAMENTE os tokens abaixo, sem nenhum `colLayerX` (salvo para o background do container), sem nenhum hex, sem nenhum `colLayer2Active` (que está reservado para sidebar).

**Regras de cor concretas:**

| Elemento | Propriedade | Valor (TOKEN) |
|---|---|---|
| `osdContainer` background (não-transparent mode) | `color` | `Appearance.m3colors.m3surfaceContainer` |
| `osdContainer` background (transparent mode ativo) | `color` | `Appearance.colors.colLayer1` |
| Combinação: |  | `Config.options.appearance.transparency.popups ? Appearance.colors.colLayer1 : Appearance.m3colors.m3surfaceContainer` |
| Toggle DESLIGADO (off) | `colBackground` | `Appearance.colors.colSecondaryContainer` |
| Toggle DESLIGADO hover | `colBackgroundHover` | `Appearance.colors.colSecondaryContainerHover` |
| Toggle DESLIGADO press/ripple | `colRipple` | `Appearance.colors.colSecondaryContainerActive` |
| Toggle LIGADO (on) | `colBackground` | `Appearance.colors.colPrimary` |
| Toggle LIGADO hover | `colBackgroundHover` | `Appearance.colors.colPrimaryHover` |
| Toggle LIGADO press/ripple | `colRipple` | `Appearance.colors.colPrimaryActive` |
| Ícone on | `color` | `Appearance.colors.colOnPrimary` |
| Ícone off | `color` | `Appearance.colors.colOnSecondaryContainer` |
| Texto on | `color` | `Appearance.colors.colOnPrimary` |
| Texto off | `color` | `Appearance.colors.colOnSecondaryContainer` |
| Track do slider | `trackColor` | `Appearance.colors.colSecondaryContainer` |
| Highlight do slider (abaixo de 100%) | `highlightColor` | `Appearance.colors.colPrimary` |
| Highlight do slider (acima de 100%) | `highlightColor` | `Appearance.colors.colErrorContainer` (default de `StyledVerticalSlider`) |
| Handle do slider | `handleColor` | `Appearance.colors.colPrimary` (acima de 100% → `Appearance.colors.colError`) |
| Texto do valor do slider (≤ 100) | `color` | `Appearance.colors.colOnPrimary` |
| Texto do valor do slider (> 100) | `color` | `Appearance.colors.colOnErrorContainer` |
| Section label title (OsdSectionLabel) | `color` | `Appearance.m3colors.m3outline` |
| Device output popup background | `color` | `Appearance.m3colors.m3surfaceContainer` |
| Item de device ativo no popup | `color` | `ColorUtils.transparentize(Appearance.colors.colPrimary, 0.35)` (mesmo que VolumeDialogContent) |
| Protection message box | `color` | `Appearance.m3colors.m3error` |
| Music/SongRec circle (esquerda inferior quando contracted em volume/brightness — o antigo `musicCircle` linhas 913-980) | `colBackground` off | `Config.options.appearance.transparency.popups ? Appearance.colors.colLayer1 : Appearance.m3colors.m3surfaceContainer` |
| Music/SongRec circle on | `colBackground` | `Appearance.colors.colPrimary` (padronizado com a regra geral) |

> **IMPORTANTE:** o binding `toggled:` de cada RippleButton deve refletir EXATAMENTE o estado do concreto (mute, easyeffects active, dark mode, songrec running, temperature active, keyboard backlight on, mono audio on). O `colBackground` deve usar ternário simples: `toggled ? colPrimary : colSecondaryContainer`. Já o `RippleButton` tem internamente `colBackgroundToggled` (seGRID) — passar `colPrimary` é provavelmente o suficiente. Verificar a API do `RippleButton` em `modules/common/widgets/RippleButton.qml` para nomes de props disponíveis e usar conforme foi feito nos `expandedBottomMusicButton` (linhas 803-870).

> **Caso aplicável** — o dark mode toggle no indicator de brightness deve ter o "toggled = !darkmode" PELO menos aparéncia para refletir "light mode ON" — exatidão deve seguir: ícone "light_mode" quando light mode ativo e "dark_mode" quando dark mode ativo é OK como está; apenas a cor vem da tabela acima.

**Onde aplicar:** TODOS os `RippleButton` do `OnScreenDisplay.qml` — fazer find/replace de `Appearance.colors.colLayer2` → `Appearance.colors.colSecondaryContainer` (e variantes, conforme tabela). Aplicar consistentemente nos subcomponentes novos de `components/` e `popups/`.

---

### Task C.2 — Adicionar Drop Shadow

**O quê:** Adicionar uma sombra (StyledDropShadow) embaixo do OSD, tanto contracted quanto expanded.

**Onde:** `OnScreenDisplay.qml`, dentro do `osdGroupWrapper` (linhas 424-981), ANTES do `osdContainer` (linha 440).

**Como:**

```qml
Item {
    id: osdGroupWrapper
    // ... props existentes ...

    // Shadow — DECLARADO ANTES de osdContainer para ficar abaixo no z-order
    StyledDropShadow {
        id: osdShadow
        target: osdContainer
        radius: 24
        samples: 49      // 2 * radius + 1
        color: Appearance.colors.colShadow
        transparentBorder: true
        // anchors.fill: osdContainer não é correto — o DropShadow já segue source Box
    }

    Rectangle {
        id: osdContainer
        // ... existente ...
    }
}
```

Nota sobre mask: o `PanelWindow` tem `mask: Region { item: osdGroupWrapper }` (linha 265-267). O `StyledDropShadow` estende-se além da geometria do `osdContainer` em ~24px de raio. Como `osdGroupWrapper` tem dimensÕes fixas (`width: osdContainer.width + 32; height: osdBaseHeight + 2*osdMargin`), o shadow pode renderizar fora — mas a Region apenas captura o rectulean do próprio osdGroupWrapper. Por isso, **aumentar os limites do osdGroupWrapper** para incluir a área do shadow:

```qml
width: osdContainer.width + 2 * osdMargin     // para haver 32px total de folga
height: osdContainer.height + 2 * osdMargin
```

E centralizar o osdContainer verticalmente dentro de osdGroupWrapper:

```qml
anchors.centerIn: parent
```

em vez de `anchors.top: parent.top; anchors.topMargin: 16`. Isto garante que o shadow seja renderizado simétrico ao redor.

**Verificação visual:** deve ser possível ver uma sombra suave ao redor do OSD sem dobramento de cliques (clicar à direita/left do OSD, fora da máscara, ainda atinge o aplicativo subjacente).

---

### Task C.3 — Tooltip em TODOS os sliders e toggles

**O quê:** Todos os elementos interativos do OSD (`topButton`, `collapseButton`, cada `StyledVerticalSlider`, cada `RippleButton`) devem exibir tooltip no hover do mouse. O `StyledVerticalSlider` já tem `StyledToolTip` no handle (linhas 166-173). Para os botões, anexar explicitamente.

**Onde:** 每 `OsdTopButton.qml`, `OsdCollapseButton.qml`, `OsdToggleRow.qml` (todos botões), `OsdDeviceOutputButton.qml`, `OsdDeviceOutputItem.qml` (cada device button do popup).

**Como — Wrapper padrão:**

```qml
RippleButton {
    // ... props ...    
    StyledToolTip {
        text: <descrição curta>   // ex.: "Mute output", "Enable EasyEffects", "Switch to stereo"
        extraVisibleCondition: parent.hovered     // supondo que RippleButton expõe `hovered`
    }
}
```

> Confirmar se `RippleButton` tem `property bool hovered` herdada de `HoverHandler` — procurar em `modules/common/widgets/RippleButton.qml`. Se não tiver, adicionar `HoverHandler { id: hoverHandler; enabled: parent.enabled }` dentro de cada botão e usar `extraVisibleCondition: hoverHandler.hovered` (ver assinatura do `StyledToolTip` em `modules/common/widgets/StyledToolTip.qml`).

**Texto dos tooltips — por tipo de elemento:**

| Elemento (volume indicator) | Tooltip text |
|---|---|
| Main volume slider | `Math.round(rawValue * 100) + "%"` + (rawValue > 1 ? " (boost)" : "") |
| Program app slider | `"Volume of " + Audio.appNodeDisplayName(node)` |
| Notification sound slider | `Translation.tr("System sounds preview volume") + " - " + Math.round(value) + "%"` |
| Mic slider | `Translation.tr("Microphone volume") + " - " + Math.round(value) + "%"` |
| Mute output toggle | `Audio.sink?.audio?.muted ? Translation.tr("Unmute output") : Translation.tr("Mute output")` |
| Device output button | `Translation.tr("Choose output device")` |
| EasyEffects toggle | `EasyEffects.active ? Translation.tr("Disable EasyEffects") : Translation.tr("Enable EasyEffects")` |
| Mono/Stereo toggle | `Config.options.sounds.monoAudio ? Translation.tr("Switch to stereo") : Translation.tr("Switch to mono")` |
| Mute mic toggle | `Audio.source?.audio?.muted ? Translation.tr("Unmute mic") : Translation.tr("Mute mic")` |
| System sounds enable toggle | `Config.options.sounds.enable ? Translation.tr("Disable system sounds") : Translation.tr("Enable system sounds")` |
| Collapse button | `Translation.tr("Collapse OSD")` |

| Elemento (brightness indicator) | Tooltip text |
|---|---|
| Brightness slider | `Math.round(value) + "%"` |
| Gamma slider | `Translation.tr("Gamma") + " - " + value + "%"` |
| Nightlight slider | `Translation.tr("Nightlight temperature") + " - " + value + "K"` |
| Keyboard backlight slider | `Translation.tr("Keyboard backlight") + " - " + Math.round(value) + "%"` |
| Dark mode toggle (topButton) | `Appearance.m3colors.darkmode ? Translation.tr("Switch to light mode") : Translation.tr("Switch to dark mode")` |
| Nightlight toggle | `Hyprsunset.temperatureActive ? Translation.tr("Disable nightlight") : Translation.tr("Enable nightlight")` |
| Keyboard backlight toggle | `KeyboardBacklight.currentValue > 0 ? Translation.tr("Turn off keyboard backlight") : Translation.tr("Turn on keyboard backlight")` |

> ** importa adiconar a nota de segurança do slider de volume**: junto ao tooltip, dentro do código fonte, mantenha o comentário especificado na Task A.6 sobre o limite do slider (não mudar `to: 1.0`).

---

### Task C.4 — Teste final & checklist

Após aplicar TODAS as tasks acima, valida (em sequencia, cada um com `qs log -f -c ii` aberto):

1. **Toggles funcionam:**
   - [ ] Click no topButton com indicator de volume →ользу toggle sink mute; ícone é atualizado; slider vai a 0 imediatamente.
   - [ ] Click no topButton expand-darkmode → dark mode toggle executa; tema aplica.
   - [ ] Click no EasyEffects toggle → processo `easyeffects --gapplication-service` está rodando (verificar com `pgrep -x easyeffects`).
   - [ ] Click no Mono/Stereo → `pactl list short modules` deve monostrar módulo `module-remap-sink` carregado; default sink trocado para `ii_mono_downmix`; inverter desativa.
   - [ ] Click no mute mic → `pactl list sources short` microfone muted.
   - [ ] Click no System Sounds enable → `cat ~/.config/quickshell/ii/config.json | jq .sounds.enable` reflete o novo estado.

2. **Animations e layout:**
   - [ ] Expand/collapse: slider principal fica fixo à direita mesmo durante a animação. Sem flicker de instâncias duplicadas.
   - [ ] TopButton cresce suave (350ms) do quadrado (44px) para fill-large.

3. **Sizing responsivo:**
   - [ ] Mude `osdBaseHeight: 700` no topo do arquivo — deve ver todo o OSD escalar proporcionalmente sem deformação.
   - [ ] Larguras internas se ajustam automaticamente; nenhum `width: <numero>` hardcoded fora do bloco de tokens.

4. **Cores:**
   - [ ] Comparar visualmente: toggle off deve ter o mesmo background do `i` secundário da sidebar de buttons (não há `colLayer2`); toggle on deve ter background primary (igual ao toggle de Quickselect).
   - [ ] Sem hex code; grep global grep por `#"[0-9A-Fa-f]` no OnScreenDisplay.qml deve voltar zero match.

5. **Shadow:**
   - [ ] Shadow visible em redor do OSD em ambos os estados. Cliques no pixel do shadow (fora do osdContainer) passam para a janela abaixo.

6. **Tooltips:**
   - [ ] Hover de cada botão mostra tooltip correspondente à tabela C.3.
   - [ ] Hover de cada slider (ao cima do handle) mostra o valor atual.

7. **Feature brightness:**
   - [ ] Gamma slider move → `hyprctl hyprsunset gamma <value>` é invocado (verificar com `hyprctl hyprsunset gamma` retorna o valor).
   - [ ] Nightlight slider move em qualquer direção → colorTemperature atualizado; se move para 6000, nightlight desativa; se move para qualquer outro valor, nightlight ativa.
   - [ ] Keyboard backlight slider move → brilho do teclado físico muda (verificar com `cat /sys/class/leds/*/brightness`).
   - [ ] Keyboard backlight toggle → liga/desliga completamente.

8. **Device output popup:**
   - [ ] Click no Device Output button → popup abre listando `Audio.outputDevices`.
   - [ ] Click em um device → default sink troca; nome no button atualiza.

9. **Slider valor destacado acima do handle:** mover qualquer slider com o mouse → número aparece acima do handle na cor primária. Mover para 0 → número aparece no topo do track.

---

## Apêndice A — Ordem de implementação recomendada

Para evitar regressões intermediárias, seguir esta ordem das tasks:

1. **A.1** — Declarar chaves de Config (foundation para tudo).
2. **A.2** — Reparar integração com Audio.qml (toggle system sounds).
3. **C.1** — Padronizar cores (preview das outras mudanças).
4. **A.4** — Sizing tokens (foundation).
5. **A.3** — Reescrever layout (essencial para verify).
6. **A.3.1** — Extrair componentes (reorg após A.3 funcionar).
7. **B.1.A-E** — Implementar features volume (EasyEffects, Mono/Stereo, Mic, Mute Mic, Device Output).
8. **B.2** — Implementar features brightness (Gamma, Nightlight, Keyboard Backlight).
9. **A.5** — Implementar spacing rules dentro grupos de sliders.
10. **A.6** — Fix do `StyledVerticalSlider` (valor topo + resolução).
11. **C.2** — Adicionar drop shadow.
12. **C.3** — Adicionar tooltips em todos.
13. **C.4** — Executar checklist final.

---

## Apêndice B — Arquivos a Criar / Modificar

| Arquivo | Ação | Task |
|---|---|---|
| `modules/common/Config.qml` | Modificar — adicionar `sounds.enable/easyEffectsToggle/monoAudio/volume`, `light.night.gammaTemperature` | A.1 |
| `modules/ii/onScreenDisplay/OnScreenDisplay.qml` | Modificar — reescrita completa do OSD root | A.2, A.3, A.4, C.1, C.2 |
| `modules/ii/onScreenDisplay/components/` (pasta) | Criar | — |
| `modules/ii/onScreenDisplay/components/OsdTopButton.qml` | Criar | A.3.1 |
| `modules/ii/onScreenDisplay/components/OsdCollapseButton.qml` | Criar | A.3.1 |
| `modules/ii/onScreenDisplay/components/OsdSectionLabel.qml` | Criar | A.3.1 |
| `modules/ii/onScreenDisplay/components/OsdSlidersRow.qml` | Criar | A.3.1, A.5, A.6, B.1.B, B.2 |
| `modules/ii/onScreenDisplay/components/OsdToggleRow.qml` | Criar | A.3.1, B.1.A-E, B.2 |
| `modules/ii/onScreenDisplay/components/OsdDeviceOutputButton.qml` | Criar | B.1.D |
| `modules/ii/onScreenDisplay/popups/OsdDeviceOutputPopup.qml` | Criar | B.1.D |
| `modules/ii/onScreenDisplay/popups/OsdDeviceOutputItem.qml` | Criar | B.1.D |
| `modules/common/widgets/StyledVerticalSlider.qml` | Modificar — fix valor, resolução handle, tooltip | A.6 |
| `services/MonoAudioService.qml` | Criar | B.1.A |
| `services/qmldir` | Verificar/criar se MonoAudioService não resolve | B.1.A |

---

## Apêndice C — Resumo visual do Expanded Volume OSD

```
+-----------------------------------------------------+
| ICON  Mute / Unmute output (fill-width)              |  ← TopButton (Row A)
+-----------------------------------------------------+
|  [media_output] Output device                       |  ← DeviceOutputButton (Row B)
|  Focusrite Scarlett Solo                            |
+-----------------------------------------------------+
                             Sliders                       ← OsdSectionLabel
+-----------------------------------------------------+
| Program Playback  |    | Notifications  |    | Mic    |  ← SlidersRow (Row C)
|  [Spotify] [Brave] |    |    [Vol]       |    | [mic]  |     (Right-to-left)
|  sliders           |    | [main Vol FIX] |    | slider |
|  (extras fade)    | gS | (FIXO direita) | gS |        |     groups separated by osdGroupSpacing
+-----------------------------------------------------+
                             Audio Options                  ← OsdSectionLabel
+----------------------------+ +--------------------------+
| [graphic_eq] Disable EasyFX | | [hearing] Switch to mono |  ← ToggleRow D
+----------------------------+ +--------------------------+
+----------------------------+ +--------------------------+
| [mic_off]  Unmute mic       | | [vol]  Disable sys sounds|  ← ToggleRow E
+----------------------------+ +--------------------------+
                                       [arrow left] collapse   ← CollapseButton (Row F, anchored right)
+-----------------------------------------------------+
```

> **Spacings**: spaces-VÍRGULA-contra o usuário quer = `osdRowSpacing` (8px) within groups, `osdGroupSpacing` (28px) between sliders groups. `osdMargin` (12px) uniforme entre osdContainer e os elementos internos.

## Apêndice D — Resumo visual do Expanded Brightness OSD

```
+-----------------------------------------------------+
| ICON  Dark mode toggle (fill-width)                  |
+-----------------------------------------------------+
                          Display                            ← OsdSectionLabel
+-----------------------------------------------------+
| Gamma |    | Nightlight |    | Keyboard | Brightness |  ← SlidersRow (Right-to-left)
| (25-100) | gS | (1000-6000) | gS | (0-100) | (0-100) |     (main brightness FIXO direita)
+-----------------------------------------------------+
                     Backlight & Nightlight                  ← OsdSectionLabel
+----------------------------+ +--------------------------+
| [wb_twilight] Disable nightlight | | [keyboard] KB light off | ← ToggleRow
+----------------------------+ +--------------------------+
                                       [arrow left] collapse
+-----------------------------------------------------+
```

---

## NOTA FINAL

Este plano contempla todas as exigências levantadas:
- [x] Correção dos toggles com Audio.qml (A.2)
- [x] Animação expand/contract por slide horizontal suave com slider principal fixo (A.3)
- [x] TopButton apenas cresce em largura (A.3 passo 5)
- [x] Refatoração de tamanhos para responsividade total via tokens centralizados (A.4)
- [x] Spacing larger entre grupos de sliders (A.5)
- [x] Slider sempre mostra valor no topo da highlight part + handler resolution fix (A.6)
- [x] Limite do slider principal mantido em 100% (A.6 NOTA)
- [x] EasyEffects, Mono/Stereo, Mic volume, Mute mic, Device output no expanded de volume (B.1)
- [x] Mute faz slider ir para 0 imediatamente (A.2 passo 3)
- [x] Gamma slider, Nightlight temperature slider, Keyboard backlight toggle no expanded de brightness (B.2)
- [x] Background = m3surfaceContainer ou colLayer1 se transparency (C.1)
- [x] Toggles: colSecondaryContainer (off) / colPrimary (on); hover/press variante própria (C.1)
- [x] Slider track = colSecondaryContainer (C.1)
- [x] Drop shadow embaixo do OSD (C.2)
- [x] Tooltips em todos os sliders e toggles (C.3)
- [x] Sem borders em qualquer elemento (aplicado globalmente por regra do projeto)