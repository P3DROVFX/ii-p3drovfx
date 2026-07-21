# Análise: Desktop Widgets + Lock Screen Integration

> Data: 2026-07-13
> Escopo: `modules/ii/background/`, `modules/ii/lock/`, `modules/common/Config.qml`

---

## 1. Bugs Encontrados

### Bug 1: `lockAnimationActive` é `undefined` — sistema de freeze de layout quebrado

**Severidade:** Alta
**Arquivos afetados:**
- `Background.qml:1008` — `visible` do FadeLoader sempre `true`
- `ClockWidget.qml:19-30` — `implicitHeight/Width` nunca congela
- `MediaWidget.qml:33-44` — mesmo problema
- `ExpressiveMediaWidget.qml:31-42` — mesmo problema

**Descrição:**
A propriedade `bgRoot.lockAnimationActive` é referenciada em 4 arquivos mas **nunca foi declarada** em `Background.qml` (onde `bgRoot` é o `PanelWindow` na linha 177). Como acesso a propriedade inexistente em JavaScript retorna `undefined` (falsy):

- `!undefined` = `true` → FadeLoader `visible` sempre `true`
- `undefined ? lastStaticHeight : contentColumn.implicitHeight` → sempre usa `contentColumn.implicitHeight`
- O snapshot `lastStaticWidth/Height` nunca é usado para congelar layout

**Impacto:**
- Layout reflow/jitter durante a animação de centralização no lock screen
- `disableAnimationOnLock` (config exposta no UI) é dead code — não faz nada
- `lastStaticWidth/Height` são atualizados continuamente mas nunca lidos no momento certo

**Fix:**
Adicionar em `bgRoot` (Background.qml ~linha 181):
```qml
property bool lockAnimationActive: GlobalStates.screenLocked
```

---

### Bug 2: `centerWidget` é hardcoded para `"clock" | "media" | "none"` — não extensível

**Severidade:** Média
**Arquivos afetados:**
- `Config.qml:1109` — `property string centerWidget: "clock"`
- `ClockWidget.qml:37,58` — hardcoded `"clock"`
- `MediaWidget.qml:24,26` — hardcoded `"media"`
- `ExpressiveMediaWidget.qml:19` — hardcoded `"media"`

**Descrição:**
O sistema só permite centralizar clock ou media no lock screen. Weather e Date não podem ser centralizados. Cada widget implementa sua própria lógica de `forceCenter` com strings hardcoded:

```qml
// ClockWidget.qml
readonly property bool forceCenter: (GlobalStates.screenLocked && Config.options.lock.centerWidget === "clock")
visibleWhenLocked: (Config.options.lock.centerWidget === "clock")

// MediaWidget.qml
readonly property bool forceCenter: (GlobalStates.screenLocked && Config.options.lock.centerWidget === "media")
visibleWhenLocked: (Config.options.lock.centerWidget === "media")
```

**Impacto:**
- Impossível centralizar Weather ou Date no lock
- Cada novo widget requer copy-paste de ~15 linhas de boilerplate
- Violação de Open/Closed Principle

**Fix:**
Mover `forceCenter` para `AbstractBackgroundWidget` usando o `widgetId` da instância:
```qml
// AbstractBackgroundWidget.qml
readonly property bool forceCenter: GlobalStates.screenLocked 
    && widgetInstance?.lockBehavior === "center"
```

---

### Bug 3: `visibleWhenLocked` é acoplado ao `centerWidget`

**Severidade:** Média
**Arquivos afetados:**
- `AbstractBackgroundWidget.qml:23,45` — property + opacity binding
- Todos os widgets que setam `visibleWhenLocked`

**Descrição:**
A lógica atual cria uma dependência indesejada:
- Se `centerWidget === "clock"` → clock fica visível no lock
- Se `centerWidget === "media"` → media fica visível no lock
- Todos os outros widgets → invisíveis no lock

Não há forma de:
- Manter TODOS os widgets visíveis no lock
- Selecionar um widget específico para aparecer no lock SEM centralizá-lo
- Ter widgets diferentes no desktop vs lock

**Impacto:**
- UX limitada: usuário não pode ter clock + weather visíveis no lock
- `showOnlyWhenLocked` do clock é um hack hardcoded no widget, não no config de instância

**Fix:**
Expandir `activeWidgets` schema para incluir `lockBehavior` por instância:
```js
{
  "id": "widget_clock_cookie",
  "widgetId": "clock_cookie",
  "x": 1518, "y": 168,
  "placementStrategy": "free",
  "lockBehavior": "keep"  // "keep" | "hide" | "center" | "lockOnly"
}
```

---

## 2. Problemas Arquiteturais

### Arch 1: Duplicação massiva de lógica de centralização

**Arquivos afetados:**
- `ClockWidget.qml:37-53` — 17 linhas de boilerplate
- `MediaWidget.qml:26-57` — 32 linhas de boilerplate
- `ExpressiveMediaWidget.qml` — ~30 linhas de boilerplate

**Descrição:**
Cada widget reimplementa:
```qml
readonly property bool forceCenter: (...)
readonly property real centeringX: (screenWidth - implicitWidth) / 2
readonly property real centeringY: (screenHeight - implicitHeight) / 2

onForceCenterChanged: {
    animDuration = 700;
    animResetTimer.restart();
}

Timer {
    id: animResetTimer
    interval: 750
    repeat: false
    onTriggered: { animDuration = Appearance.animation.elementMove.duration; }
}

targetX: forceCenter ? centeringX : (normalPositioning...)
targetY: forceCenter ? centeringY : (normalPositioning...)
```

**Impacto:**
- ~80 linhas duplicadas em 3 arquivos
- Inconsistências futuras (um widget pode ter lógica diferente)
- Dificulta manutenção

**Fix:**
Mover toda a lógica para `AbstractBackgroundWidget.qml`. Widgets específicos apenas declaram `lockBehavior` no config.

---

### Arch 2: Sem separação entre "desktop widgets" e "lock screen widgets"

**Arquivos afetados:**
- `Config.qml:606` — `activeWidgets` array
- `Background.qml:28-170` — `syncActiveWidgets()`

**Descrição:**
O mesmo `activeWidgets` array controla ambos os contextos. Não há conceito de:
- "lock-only widget" (aparece só no lock)
- "desktop-only widget" (aparece só no desktop)
- "different position on lock" (posição diferente no lock)

A única distinção é `showOnlyWhenLocked` no clock (hardcoded no widget, não no config de instância).

**Impacto:**
- Impossível ter um widget "Info do Sistema" que só aparece no lock
- Impossível ter o media player em posições diferentes no desktop vs lock

**Fix:**
Expandir schema de `activeWidgets`:
```js
{
  "id": "widget_media_circular",
  "widgetId": "media_circular",
  "x": 249, "y": 612,
  "placementStrategy": "free",
  "lockBehavior": "center",        // "keep" | "hide" | "center" | "lockOnly"
  "lockX": null,                   // posição X no lock (null = usa centering)
  "lockY": null,                   // posição Y no lock (null = usa centering)
  "lockScale": 1.0                 // escala no lock (null = usa widgetsScale)
}
```

---

### Arch 3: Widget instances não têm metadata de contexto

**Arquivos afetados:**
- `Config.qml:606` — schema atual
- `Background.qml:1022-1033` — Binding do `widgetInstance`

**Descrição:**
Cada entrada em `activeWidgets` é:
```js
{ "id": "...", "widgetId": "...", "x": 0, "y": 0, "placementStrategy": "free" }
```

Falta:
- `lockBehavior: string` — como o widget se comporta no lock
- `lockX/lockY: real` — posição customizada no lock
- `lockScale: real` — escala customizada no lock
- `zIndex: int` — camadas de widgets (quem fica por cima)
- `size: {w, h}` — para centralização precisa sem depender de `implicitWidth/Height`

**Impacto:**
- Centralização depende de `implicitWidth/Height` que pode mudar durante animação
- Impossível ter widgets em camadas (ex: relógio por cima de um card de clima)
- Lock screen não pode ter layout diferente do desktop

**Fix:**
Expandir schema (ver Arch 2). Adicionar `zIndex` para suporte futuro a camadas.

---

### Arch 4: `sourceComponent` no Repeater é um if-chain gigante

**Arquivos afetados:**
- `Background.qml:1010-1018` — 8 if-statements

**Descrição:**
```qml
sourceComponent: {
    if (delegateRoot.widgetId === "clock_cookie") return component_clock_cookie;
    if (delegateRoot.widgetId === "clock_digital") return component_clock_digital;
    if (delegateRoot.widgetId === "clock_nagasaki") return component_clock_nagasaki;
    if (delegateRoot.widgetId === "media_circular") return component_media_circular;
    if (delegateRoot.widgetId === "media_expressive") return component_media_expressive;
    if (delegateRoot.widgetId === "weather_default") return component_weather_default;
    if (delegateRoot.widgetId === "weather_expressive") return component_weather_expressive;
    if (delegateRoot.widgetId === "date_default") return component_date_default;
    return null;
}
```

**Impacto:**
- Cada novo widget requer:
  1. Adicionar `Component {}` acima (linhas 899-991)
  2. Adicionar `if` no `sourceComponent`
- Violação de Open/Closed Principle
- `WidgetsRegistry.getQmlPath(widgetId)` já existe mas não é usado

**Fix:**
Usar `Component` dinâmico via `WidgetsRegistry`:
```qml
sourceComponent: {
    const qmlPath = WidgetsRegistry.getQmlPath(delegateRoot.widgetId);
    if (!qmlPath) return null;
    return Qt.createComponent(qmlPath);
}
```

Ou manter os `Component` inline mas usar um `map` object:
```qml
property var componentMap: ({
    "clock_cookie": component_clock_cookie,
    "clock_digital": component_clock_digital,
    // ...
})

sourceComponent: componentMap[delegateRoot.widgetId] || null
```

---

## 3. Proposta: Sistema de Widgets estilo Android

### Comparação com Android

| Conceito Android | Equivalente Atual | Gap |
|---|---|---|
| **Home screen widgets** | `activeWidgets` no desktop | Funciona |
| **Lock screen widgets** | `centerWidget` (1 widget, centralizado) | Muito limitado |
| **Widget stacks/pages** | Não existe | Não existe |
| **Per-widget settings** | Sub-páginas no WidgetsConfig | Funciona |
| **Resize handles** | `widgetsScale` global | Sem resize por-widget |
| **Widget categories** | Categorias no WidgetsConfig | Sem filtro por contexto |

---

### Features Propostas

#### A. Schema de `activeWidgets` expandido

```js
{
  "id": "widget_clock_cookie",
  "widgetId": "clock_cookie",
  "x": 1518, "y": 168,
  "placementStrategy": "free",
  // NOVOS:
  "lockBehavior": "keep",        // "keep" | "hide" | "center" | "lockOnly"
  "lockX": null,                 // posição X no lock (null = centraliza)
  "lockY": null,                 // posição Y no lock (null = centraliza)
  "lockScale": 1.0,              // escala individual no lock
  "zIndex": 0                    // camada (futuro)
}
```

**`lockBehavior`:**
- `"keep"` — widget permanece na mesma posição no lock (substitui `visibleWhenLocked: true`)
- `"hide"` — widget desaparece no lock (default atual para non-center widgets)
- `"center"` — widget é centralizado no lock (substitui `centerWidget === "clock"`)
- `"lockOnly"` — widget só aparece no lock, nunca no desktop (substitui `showOnlyWhenLocked`)

Isso elimina `centerWidget`, `showOnlyWhenLocked`, e `visibleWhenLocked` como propriedades hardcoded.

#### B. Centralização genérica no `AbstractBackgroundWidget`

Mover a lógica de `forceCenter`/`centeringX`/`centeringY`/`animDuration` para a base:

```qml
// AbstractBackgroundWidget.qml
readonly property bool forceCenter: widgetInstance?.lockBehavior === "center" && GlobalStates.screenLocked
readonly property real centeringX: (screenWidth - implicitWidth) / 2
readonly property real centeringY: (screenHeight - implicitHeight) / 2

targetX: forceCenter ? centeringX : (normalPositioning...)
targetY: forceCenter ? centeringY : (normalPositioning...)

onForceCenterChanged: {
    animDuration = 700;
    animResetTimer.restart();
}
```

Cada widget específico deleta ~15 linhas de boilerplate.

#### C. Fix do `lockAnimationActive`

Adicionar em `bgRoot`:
```qml
property bool lockAnimationActive: GlobalStates.screenLocked
```

Ou, mais precisamente, com delay para cobrir a transição completa:
```qml
property bool lockAnimationActive: false
Connections {
    target: GlobalStates
    function onScreenLockedChanged() {
        if (GlobalStates.screenLocked) lockAnimationActive = true;
        else lockAnimResetTimer.restart(); // 800ms delay
    }
}
Timer {
    id: lockAnimResetTimer
    interval: 800
    onTriggered: lockAnimationActive = false
}
```

#### D. Toggle para travar posição dos widgets

```qml
// Config.qml
property bool lockWidgetPositions: false

// AbstractBackgroundWidget.qml
draggable: !isPreview && !Config.options.background.widgets.lockWidgetPositions 
           && (placementStrategy === "free" || placementStrategy === "draggable")
```

Simples. Adicionar toggle no `WidgetsConfig.qml` global controls.

#### E. Múltiplos widgets centralizados no lock (estilo Android)

Em vez de 1 widget centralizado, permitir N widgets com `lockBehavior: "center"`. Layout:
- Se 1 widget: centraliza normalmente
- Se 2+ widgets: empilha verticalmente com spacing configurável

```qml
// Config.qml
property JsonObject lock: JsonObject {
    property real centerSpacing: 20
    property string centerAlignment: "vertical" // "vertical" | "horizontal"
}
```

#### F. Lock screen widget presets (estilo "Widget Stacks" do Android)

Permitir o usuário criar "presets" de layout para o lock screen:
```qml
// Config.qml
property list<var> lockPresets: [
    { "name": "Minimal", "widgets": ["clock_digital"], "centerAlignment": "vertical" },
    { "name": "Music", "widgets": ["media_expressive", "clock_cookie"], "centerAlignment": "vertical" },
    { "name": "Info", "widgets": ["clock_cookie", "weather_default", "date_default"] }
]
```

UI: carrossel de presets nas configurações de lock screen, com preview.

#### G. Per-widget resize (estilo Android resize handles)

```js
// activeWidgets entry:
{ "id": "...", "widgetId": "...", "x": 0, "y": 0, 
  "scaleOverride": 1.5,  // substitui widgetsScale global para este widget
  "lockedScale": 0.8 }   // escala específica no lock
```

UI: handles de resize nos cantos do widget durante modo de edição (grid ativo).

#### H. Widget visibility rules (context-aware)

```qml
// Config.qml - por widget instance
property string visibilityRule: "always" 
// "always" | "noFullscreen" | "noWindows" | "lockOnly" | "desktopOnly"
```

#### I. Drag-and-drop entre desktop e lock (concept)

No modo de edição, ter um "lock screen preview" onde o usuário pode arrastar widgets para definir o layout do lock. Similar ao Android onde você vê a preview do lock screen nas configurações.

---

## 4. Melhorias Imediatas (Quick Wins)

| # | Melhoria | Esforço | Impacto |
|---|---|---|---|
| 1 | Fix `lockAnimationActive` | Low | Elimina jitter no lock |
| 2 | Mover `forceCenter` para `AbstractBackgroundWidget` | Medium | Elimina 45+ linhas duplicadas |
| 3 | `lockWidgetPositions` toggle | Low | Feature simples e útil |
| 4 | Expandir `centerWidget` para qualquer widget | Medium | Weather/Date como center widget |
| 5 | `lockBehavior` per-widget no `activeWidgets` | Medium | Substitui 3 configs hardcoded |
| 6 | Dynamic component loading via `WidgetsRegistry.getQmlPath()` | Low | Elimina if-chain no Repeater |
| 7 | Lock screen widget preview nas settings | High | UX similar ao Android |

---

## 5. Plano de Implementação

### Fase 1: Bug Fixes (Alta Prioridade)

1. **Fix `lockAnimationActive`** — Adicionar property em `bgRoot`
2. **Tornar `centerWidget` extensível** — Mover lógica para `AbstractBackgroundWidget`
3. **Desacoplar `visibleWhenLocked`** — Usar `lockBehavior` por instância

### Fase 2: Refatoração Arquitetural

1. **Centralizar `forceCenter`** — Mover para `AbstractBackgroundWidget`
2. **Separar desktop vs lock** — Adicionar `lockBehavior` ao schema
3. **Expandir metadata** — Adicionar `lockX/Y`, `lockScale`, `zIndex`
4. **Dynamic loading** — Usar `WidgetsRegistry` no Repeater

### Fase 3: Features Novas

1. **`lockWidgetPositions` toggle** — Config + UI
2. **Múltiplos widgets centralizados** — Layout engine no lock
3. **Lock screen presets** — UI de presets com preview
4. **Per-widget resize** — Handles de resize

---

## 6. Arquivos Envolvidos

### Core
- `modules/ii/background/Background.qml` — `bgRoot`, `WidgetCanvas`, Repeater
- `modules/ii/background/widgets/AbstractBackgroundWidget.qml` — Base class
- `modules/common/Config.qml` — `activeWidgets` schema, `lock` config

### Widgets Específicos
- `modules/ii/background/widgets/clock/ClockWidget.qml`
- `modules/ii/background/widgets/media/MediaWidget.qml`
- `modules/ii/background/widgets/media/ExpressiveMediaWidget.qml`
- `modules/ii/background/widgets/weather/WeatherWidget.qml`
- `modules/ii/background/widgets/weather/ExpressiveWeatherWidget.qml`
- `modules/ii/background/widgets/DateWidget/DateWidget.qml`

### Registry & Config UI
- `modules/ii/background/widgets/WidgetsRegistry.qml`
- `modules/settings/configs/WidgetsConfig.qml`

### Lock Screen
- `modules/ii/lock/Lock.qml`
- `modules/ii/lock/LockSurface.qml`

---

## 7. Compatibilidade e Migração

### Migração de `activeWidgets` existente

```js
// Antes:
{ "id": "widget_clock_cookie", "widgetId": "clock_cookie", "x": 1518, "y": 168, "placementStrategy": "free" }

// Depois (com defaults):
{ 
  "id": "widget_clock_cookie", 
  "widgetId": "clock_cookie", 
  "x": 1518, "y": 168, 
  "placementStrategy": "free",
  "lockBehavior": "hide",  // default
  "lockX": null,
  "lockY": null,
  "lockScale": 1.0
}
```

### Migração de `centerWidget` config

```js
// Antes:
Config.options.lock.centerWidget = "clock"

// Depois (automático via migração):
// Para cada widget em activeWidgets:
if (widgetId.startsWith("clock") && Config.options.lock.centerWidget === "clock") {
    widget.lockBehavior = "center";
}
```

### Deprecations

- `Config.options.lock.centerWidget` → substituído por `lockBehavior` por instância
- `Config.options.background.widgets.clock.showOnlyWhenLocked` → substituído por `lockBehavior: "lockOnly"`
- `visibleWhenLocked` property em widgets → substituído por `lockBehavior` binding

---

## 8. Features Implementadas (2026-07-13)

### 8.1. Bug Fix: `lockAnimationActive`
**Arquivo:** `Background.qml:181-198`

Adicionado `property bool lockAnimationActive` em `bgRoot` com `Connections` no `GlobalStates.screenLocked` e timer de 800ms para reset. Isso resolve o jitter de layout durante a animação de centralização no lock screen.

### 8.2. Sistema `lockBehavior` por Widget
**Arquivos:** `AbstractBackgroundWidget.qml`, `Config.qml`, `Background.qml`, `ClockWidget.qml`, `MediaWidget.qml`, `ExpressiveMediaWidget.qml`

Schema expandido de `activeWidgets`:
```js
{
  "id": "widget_clock_cookie",
  "widgetId": "clock_cookie",
  "x": 1518, "y": 168,
  "placementStrategy": "free",
  "lockBehavior": "hide"  // "hide" | "keep" | "center" | "lockOnly"
}
```

**Comportamentos:**
- `"hide"` — widget desaparece no lock (default)
- `"keep"` — widget permanece na mesma posição no lock
- `"center"` — widget é centralizado no lock
- `"lockOnly"` — widget só aparece no lock, nunca no desktop

**Compatibilidade retroativa:** O sistema ainda respeita `Config.options.lock.centerWidget` como fallback para widgets sem `lockBehavior` definido.

### 8.3. Centralização Genérica no `AbstractBackgroundWidget`
**Arquivo:** `AbstractBackgroundWidget.qml:27-80`

Lógica de `forceCenter`, `centeringX/Y`, `onForceCenterChanged`, e `lockAnimResetTimer` movida para a base. Cada widget específico deletou ~15-25 linhas de boilerplate.

### 8.4. Múltiplos Widgets Centralizados no Lock
**Arquivos:** `AbstractBackgroundWidget.qml:35-75`, `Config.qml:1174-1175`, `LockScreenConfig.qml`

Quando múltiplos widgets têm `lockBehavior: "center"`, eles são empilhados automaticamente:
- `Config.options.lock.centerSpacing` — espaçamento entre widgets (default: 20px)
- `Config.options.lock.centerAlignment` — direção do empilhamento (`"vertical"` | `"horizontal"`)

Cada widget calcula sua posição baseada no índice na lista de widgets centralizados:
```qml
readonly property real centeredOffsetY: {
    if (centeredWidgetCount <= 1) return 0;
    let spacing = Config.options.lock.centerSpacing || 20;
    let totalHeight = centeredWidgetCount * (implicitHeight + spacing) - spacing;
    let myY = centeredWidgetIndex * (implicitHeight + spacing);
    return myY - (totalHeight - implicitHeight) / 2;
}
```

### 8.5. Toggle `lockWidgetPositions`
**Arquivos:** `Config.qml:587`, `AbstractBackgroundWidget.qml:118`, `WidgetsConfig.qml`

Toggle global que impede drag de todos os widgets:
```qml
draggable: !isPreview && !(Config.options.background.widgets.lockWidgetPositions ?? false) && (placementStrategy === "free" || placementStrategy === "draggable")
```

UI adicionada no `WidgetsConfig.qml` na seção de controles globais.

### 8.6. UI de `lockBehavior` por Widget
**Arquivos:** `Config.qml:99-119`, `WidgetsConfig.qml:326-395`

Cada card de widget ativo agora exibe um seletor de `lockBehavior` com 4 opções:
- 🙈 `visibility_off` — Hidden on lock
- 👁️ `visibility` — Keep position on lock
- 🎯 `center_focus_strong` — Center on lock
- 🔒 `lock` — Only show on lock

Helpers adicionados em `Config.qml`:
- `getWidgetLockBehavior(widgetId)`
- `setWidgetLockBehavior(widgetId, newLockBehavior)`

### 8.7. Component Map no Repeater
**Arquivo:** `Background.qml:970-978`

If-chain de 8 `if` statements substituído por `widgetComponentMap` object:
```qml
property var widgetComponentMap: ({
    "clock_cookie": component_clock_cookie,
    "clock_digital": component_clock_digital,
    // ...
})

sourceComponent: widgetCanvas.widgetComponentMap[delegateRoot.widgetId] || null
```

---

## 9. Testes e Validação

### Checklist de Testes

- [ ] Lock/unlock sem jitter de layout
- [ ] Widget centralizado no lock (clock, media, weather, date)
- [ ] Múltiplos widgets com `lockBehavior: "center"` empilhados corretamente
- [ ] Múltiplos widgets com `lockBehavior: "keep"` visíveis no lock
- [ ] Widget com `lockBehavior: "lockOnly"` não aparece no desktop
- [ ] Widget com `lockBehavior: "hide"` não aparece no lock
- [ ] `lockWidgetPositions: true` impede drag
- [ ] Migração de `activeWidgets` antigo funciona
- [ ] `disableAnimationOnLock` funciona após fix de `lockAnimationActive`
- [ ] UI de lockBehavior no WidgetsConfig funciona

---

## 10. Referências

- Android Widget Stacks: https://developer.android.com/develop/ui/views/launch/shortcuts
- Material 3 Widget Guidelines: https://m3.material.io/components/cards
- Quickshell PanelWindow: https://quickshell.org/docs/wayland/panel-window
- Hyprland Lock Screen: `ext-session-lock-v1` protocol

---

**Próximos passos:** Iniciar implementação na ordem: Bugs 1, 2, 3 → Arch 1, 2, 3, 4.
