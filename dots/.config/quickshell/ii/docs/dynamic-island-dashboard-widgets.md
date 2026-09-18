# Dynamic Island dashboard: adding widgets

The Dynamic Island's expanded default face is a dashboard: a grid of quick-toggle tiles.
It is the **same quick-toggle system as the sidebar dashboard**. The tiles, resizing,
drag-to-reorder, the tray ("drawer") of unused tiles, persistence and the details dialogs
are all shared. A tile written once works in the sidebar, the tablet shade and the island.
The exception is a tile restricted to one host family (see [Families](#families)).

This guide covers:

1. [How the pieces fit](#1-how-the-pieces-fit)
2. [The size system](#2-the-size-system)
3. [Adding a simple toggle](#3-adding-a-simple-toggle)
4. [Adding a slider](#4-adding-a-slider)
5. [Adding a custom widget tile](#5-adding-a-custom-widget-tile)
6. [Adding a details page (the dialog)](#6-adding-a-details-page)
7. [Design rules](#7-design-rules)
8. [Checklist](#8-checklist)
9. [Testing](#9-testing)

---

## 1. How the pieces fit

```
IslandDashboard.qml                      (island host: frame, edit toolbar, pages)
 └─ AndroidQuickPanel                    (grid + tray, shared with the sidebar)
     ├─ QuickToggleEditController        (add / remove / move / resize, validation)
     ├─ QuickToggleLayout.js             (the packer: tiles -> x/y/width/height)
     ├─ QuickToggleCatalog.js            (every tile type, its kind and allowed sizes)
     └─ AndroidToggleDelegateChooser     (type string -> QML tile component)
         └─ Android<Name>Toggle.qml      (the tile)
             └─ <Name>Toggle.qml         (optional model: name, icon, state, actions)
```

| File | Role |
|---|---|
| `modules/common/quickToggles/androidStyle/QuickToggleCatalog.js` | The **only** size policy. Declares each type's `kind`, `defaultSize`, `allowedSizes`/`maxHeight`, `families` and `permanent`. It also assigns tray categories. |
| `modules/common/quickToggles/androidStyle/QuickToggleLayout.js` | The packer. It places tiles left to right, top to bottom, first fit. Rows made only of sliders are drawn shorter. |
| `modules/common/quickToggles/androidStyle/AndroidToggleDelegateChooser.qml` | Maps the `type` string to a tile component. It also re-emits `open<Name>Dialog` signals. |
| `modules/common/quickToggles/androidStyle/AndroidQuickToggleButton.qml` | Base for normal toggle tiles. It handles the circle icon, the label/status, the morph between sizes and edit mode. |
| `modules/common/quickToggles/androidStyle/AndroidSliderWidgetBase.qml` | Base for slider tiles. |
| `modules/common/quickToggles/androidStyle/EditableQuickToggleItem.qml` | The edit overlay: drag, resize handle, remove/add badge. Every tile needs one (the bases include it). |
| `modules/common/models/quickToggles/<Name>Toggle.qml` | Optional `QuickToggleModel`: name, status text, icon, toggled state and actions. The tile and the launcher search both reuse it. |
| `modules/common/quickToggles/AbstractQuickPanel.qml` | Declares the `open<Name>Dialog` signals every panel exposes. |
| `modules/common/quickToggles/AndroidQuickPanel.qml` | The grid and the tray. It forwards the dialog signals to its host. |
| `modules/common/quickToggleDialogs/<name>/<Name>Dialog.qml` | The details UI, a `WindowDialog`. The sidebar shows it as a dialog; the island shows it as a page. |
| `modules/ii/dynamicIsland/dashboard/IslandDashboard.qml` | The island host. It maps dialog signals to pages and owns the columns × rows frame. |
| `modules/ii/dynamicIsland/dashboard/DashboardMetrics.qml` | Predicts the dashboard's size from the config before the grid exists, so the island's morph aims at the real size. |
| `modules/common/Config.qml` → `dynamicIsland.dashboard.quickToggles` | The persisted island layout: `columns`, `rows`, `layoutVersion` and `pages` (one page). |
| `services/QuickToggleRegistry.qml` | Optional. Makes a model searchable from the launcher. |
| `modules/common/quickToggles/QuickToggleIcon.qml` | Optional. An animated icon for a type; types not listed fall back to the Material symbol. |

A persisted tile is a plain object:

```js
{ "id": "network", "type": "network", "sizeW": 2, "sizeH": 1 }
```

- `type` selects the catalog entry and the delegate.
- `id` is the stable identity (it defaults to `type`). Two tiles of the same type need
  different ids.
- `sizeW`/`sizeH` are the size in grid cells.

The panel adds `layoutX`/`layoutY`/`pixelWidth` at runtime; they are never saved.

---

## 2. The size system

### Cells

The grid unit is a cell of **96 × 56 px** with **6 px** spacing. In the island these
come from `DashboardMetrics.cellWidth`, `cellHeight` and `spacing`. The panel adds 6 px
padding, and the island adds an 8 px frame on every side.

A tile `W` cells wide and `H` cells tall measures:

```
width  = W * 96 + (W - 1) * 6
height = H * 56 + (H - 1) * 6
```

The special width **`W = 0`** is the **square icon-only tile**: 56 × 56 (`cellHeight`
wide). Only `kind: "toggle"` tiles can use it, and only with `H = 1`.

### Kinds and their sizes

| `kind` | Base component | Sizes | Notes |
|---|---|---|---|
| `toggle` | `AndroidQuickToggleButton` | Any `W` from `0` to `columns`, any `H` from `1` to `maxHeight` (8). `W = 0` requires `H = 1`. | The layout morphs with size. A 0×1 or 1×1 tile shows just the icon. A tile 2 or more wide shows icon + name + status. A tall tile can use `tall1x2OverrideComponent` / `wide2x2OverrideComponent`. |
| `slider` | `AndroidSliderWidgetBase` | `W` from `1` to `columns`, `H` from `1` to `maxHeight`. The default is `[4, 1]`. | A row made only of sliders is drawn at `QuickToggleMetrics.sliderWidgetHeight(56)` instead of 56 px. The packer calls these compact rows. |
| `media` | custom (`AndroidMediaWidgetToggle`) | Only `allowedSizes`: `[2,1]`, `[2,2]`, `[4,2]`. | |
| `dashboardWidget` / `fullDashboardWidget` | custom | `[1,2]` only | Restricted to the tablet family. |
| `toolbar` | custom (`AndroidDashboardToolbarToggle`) | `[2,1]`, `[3,1]`, `[4,1]` | Island only, and permanent. |

A new kind is free-form: the kind string only matters to your delegate and to the tray
category. A kind other than `toggle` and `slider` is filed under **Widgets**.

### How a size is decided

`QuickToggleCatalog.normalizeSize(type, w, h, columns)` is the single authority:

1. If the entry has `allowedSizes`, the size snaps to the nearest allowed size that fits
   in `columns`. The distance used is `|Δw| + |Δh|`.
2. Otherwise the width is clamped to `[0 or 1, columns]` (0 only for toggles) and the
   height to `[1, maxHeight]`.
3. `fixedHeight`, if present, forces the height.

`QuickToggleResize.js` derives the resize handle's range from the same function, so a
tile can only ever be resized to a size the catalog allows. **Never add size checks in
QML.** Put every constraint in the catalog entry.

Use the catalog fields like this:

| Field | Meaning |
|---|---|
| `defaultSize: [w, h]` | The size a tile gets when added from the tray. |
| `allowedSizes: [[w,h], ...]` | A closed list of sizes. Use it for widgets whose content only works at some sizes. One entry means the tile cannot be resized. |
| `maxHeight: n` | The height cap when there is no `allowedSizes` (toggles and sliders use 8). |
| `fixedHeight: n` | Forces the height to `n`. |
| `families: ["island", ...]` | Hosts that offer the tile. Omit it to offer the tile everywhere. |
| `permanent: true` | The tile can be moved and resized but not removed. |

### Families

Each host passes a `familyId` to `AndroidQuickPanel`. The island dashboard passes
`"island"`, and the sidebar passes the current panel family.
`QuickToggleCatalog.availableForFamily(type, family)` hides a type from a host's tray
when the type's `families` list does not include that host. An island-only tile
therefore needs `families: ["island"]`.

### The island's grid

- The island's size follows its layout: its width is `columns` cells, and its height is
  the packed rows (`DashboardMetrics.restHeight`). The default is **6 × 6**.
- The edit toolbar changes `columns` and `rows`. It stops at what fits on the screen
  (`maxColumns`, `maxRows`), and it will not shrink below what the current tiles need.
- Adding a tile to a full grid calls `growToFit`. It adds a row while the screen has the
  height for it, and otherwise a column. If neither fits, the add is refused.
- In edit mode the tray takes the remaining screen height and scrolls when it runs out.

A tile larger than the island's maximum grid can never be added. Keep `defaultSize`
(and the smallest allowed size) small enough to fit a 1080p screen.

---

## 3. Adding a simple toggle

Example: a "Caffeine" toggle with type `caffeine`.

### 3.1 The model (optional but recommended)

`modules/common/models/quickToggles/CaffeineToggle.qml`:

```qml
import QtQuick
import qs.services
import qs.modules.common

QuickToggleModel {
    name: Translation.tr("Caffeine")
    statusText: toggled ? Translation.tr("On") : Translation.tr("Off")
    tooltipText: Translation.tr("Caffeine")
    icon: "coffee"                 // a Material Symbols name

    toggled: Caffeine.active       // bind to a service; never keep state here
    mainAction: () => Caffeine.toggle()

    // Set hasMenu to give the tile a details page (section 6). With it, right-click
    // or press-and-hold emits openMenu, and so does a plain click on a tile 2 or more
    // cells wide or 2 or more tall.
    hasMenu: false
}
```

The `QuickToggleModel` fields are:

- Text: `name`, `statusText`, `tooltipText`, `icon`, `hasStatusText`.
- State: `available`, `toggled`.
- Actions: `mainAction` (tap), `hasMenu`, `altAction` (right-click when there is no
  menu).

### 3.2 The tile

`modules/common/quickToggles/androidStyle/AndroidCaffeineToggle.qml`:

```qml
import qs.modules.common.models.quickToggles

AndroidQuickToggleButton {
    toggleModel: CaffeineToggle {}
}
```

Optional visual properties on `AndroidQuickToggleButton` (see `AndroidNetworkToggle.qml`):

- `backgroundIcon`: a large faded glyph behind wide tiles.
- `expandedIconShape`: the Material shape behind the icon on wide tiles (`"Circle"`,
  `"Cookie7Sided"`, …).
- `centerExpandedIcon`, `expandedStatusTransparency`, `expandedTitle`, `expandedStatus`.
- `tall1x2OverrideComponent` / `wide2x2OverrideComponent`: custom content for tall
  sizes.

You can also skip the model and set `name`, `statusText`, `buttonIcon`, `toggled`,
`mainAction` and `hasMenu` directly on the button.

### 3.3 Register the type in the catalog

`QuickToggleCatalog.js`, in `TOGGLE_TYPES`:

```js
caffeine: { kind: "toggle", defaultSize: [1, 1], maxHeight: 8 },
```

The tray category is **System & tools** by default. For **Connectivity**, add the type
to `TYPE_CATEGORIES`:

```js
caffeine: "connectivity",
```

The four sections are `connectivity`, `system`, `sliders` and `widgets`. Their labels and
icons live in `AndroidQuickPanel.trayCategoryMeta`. Adding a new section means adding it
to `CATEGORY_ORDER` in the catalog and to `trayCategoryMeta` in the panel. Keep the
sections few: the grids are narrow.

### 3.4 Register the delegate

In `AndroidToggleDelegateChooser.qml`, copy an existing `DelegateChoice` and change the
`roleValue` and the component. The block of property assignments is identical for every
tile:

```qml
DelegateChoice {
    roleValue: "caffeine"
    AndroidCaffeineToggle {
        required property int index
        required property var modelData
        buttonIndex: index
        isUnused: root.isUnused
        buttonData: modelData
        editMode: root.editMode
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.sizeW
        pageIndex: root.pageIndex
        gridColumns: root.gridColumns
        panel: root.panel
        gridRef: root.gridRef
        entranceTrigger: root.entranceTrigger
        // Only when the tile has a details page (section 6):
        // onOpenMenu: root.openCaffeineDialog()
    }
}
```

A type without a `DelegateChoice` is kept in the config but renders as nothing, and
Quickshell does not report an error.

### 3.5 That's it for the tray

The tray lists every catalog type available to the host's family that is not on the
grid. Your tile appears there automatically, at its `defaultSize`, under its category.
Nothing is added to the default layout until the user drags the tile in.

To ship the tile **on by default** in the island, add it to
`dynamicIsland.dashboard.quickToggles.pages[0]` in `Config.qml`:

```js
{ "id": "caffeine", "type": "caffeine", "sizeW": 1, "sizeH": 1 },
```

Existing users keep their saved layout, so this only affects new configs. Bump
`layoutVersion` only if you also write a migration.

### 3.6 Optional extras

- **Launcher search:** add a `Component { id: caffeineComp; CaffeineToggle {} }`, a
  `"caffeine": caffeineComp` entry in `_modelComponentMap` and an entry with `keywords`
  in `services/QuickToggleRegistry.qml`.
- **Animated icon:** add a `case "caffeine":` in `QuickToggleIcon.qml`.
- **Translations:** every string passes through `Translation.tr(...)`. Add the keys to
  `translations/en_US.json` and `translations/pt_BR.json`.

---

## 4. Adding a slider

```qml
// AndroidFooSliderToggle.qml
import QtQuick
import qs.services

AndroidSliderWidgetBase {
    id: root
    tooltipText: Translation.tr("Foo")
    materialSymbol: root.sliderValue > 0 ? "foo_on" : "foo_off"
    sliderValue: Number(Foo.level ?? 0)          // 0..1
    onMoved: value => Foo.setLevel(value)
}
```

Catalog entry: `fooSlider: { kind: "slider", defaultSize: [4, 1], maxHeight: 8 }`.

- The tray files it under **Sliders** automatically.
- `DashboardMetrics.compactTypes` and the panel both recognise it as compact because the
  kind is `"slider"`.
- Register the `DelegateChoice` as in 3.4.

---

## 5. Adding a custom widget tile

Use this when the content is not a toggle (a clock, a now-playing card, a mini
calendar). Two references:

- `AndroidDashboardToolbarToggle.qml`: the smallest full example of a custom tile.
- `AndroidMediaWidgetToggle.qml`: a rich widget with several allowed sizes.

### 5.1 The contract every tile must honour

The delegate chooser and the edit controller talk to every tile through the same
properties. A custom tile must declare all of them:

```qml
Item {
    id: root

    // Set by the delegate chooser
    required property int buttonIndex
    required property var buttonData          // { id, type, sizeW, sizeH, layoutX, layoutY, ... }
    required property real baseCellWidth
    required property real baseCellHeight
    required property real cellSpacing
    required property int cellSize

    property bool editMode: false
    property bool isUnused: false              // true when drawn in the tray
    property bool isDragging: false
    property real dragOffsetX: 0
    property real dragOffsetY: 0
    property int pageIndex: 0
    property int gridColumns: 4
    property var panel: null                   // the AndroidQuickPanel
    property var gridRef: null
    property int entranceTrigger: -1

    // Read by the edit overlay
    property string tooltipText: ""
    readonly property bool hovered: false

    // Resize direction, read by the edit controller
    readonly property real resizeDirectionX: editableItem.directionX
    readonly property real resizeDirectionY: editableItem.directionY
    ...
}
```

### 5.2 Size and position

Copy the geometry block from `AndroidDashboardToolbarToggle.qml` unchanged:

- `catalogSize` / `effectiveSizeW` / `effectiveSizeH` come from
  `QuickToggleCatalog.normalizeSize(...)`.
- `implicitWidth` / `implicitHeight` come from the cell formula in §2.
- `Binding on x/y` from `buttonData.layoutX/layoutY`. While the tile is resizing, the
  binding uses `editableItem.resizeOriginX/Y` instead.
- `Behavior on x/y` uses `elementMoveFast`, disabled while dragging or resizing.
- `z: 100` while dragging or resizing.

The packer owns placement. A tile never positions itself.

### 5.3 The visual surface and the edit overlay

```qml
Rectangle {
    id: visualButton
    // While resizing, follow the live preview; otherwise fill the tile.
    width: editableItem.resizing ? editableItem.previewWidth : root.width
    height: editableItem.resizing ? editableItem.previewHeight : root.height
    radius: Config.options.appearance.sharpMode ? 0
        : Math.min(width / 2, height / 2, Appearance.rounding.large)
    color: Appearance.colors.colLayer2
    scale: root.isDragging ? 1.05 : 1.0
    opacity: root.isDragging ? 0.95 : 1.0
    transform: Translate {
        x: root.isDragging ? root.dragOffsetX : 0
        y: root.isDragging ? root.dragOffsetY : 0
    }
    // Behaviors on width/height (elementResize, disabled while resizing) and scale
    // (clickBounce) - see the toolbar tile.

    // Your content goes here, anchored to visualButton, not to root, so it follows
    // the resize preview and the drag.
}

EditableQuickToggleItem {
    id: editableItem
    target: root
    visualItem: visualButton
}
```

`EditableQuickToggleItem` provides drag, reorder, the resize handle and the add/remove
badge. Content that must stay interactive in edit mode (like the toolbar's edit button)
goes above it with `z: 20`. All other content should be disabled in edit mode
(`enabled: !root.editMode`), so a press starts a drag instead.

### 5.4 Adapt to the size

Branch the layout on `root.effectiveSizeW` / `effectiveSizeH` (for example, an icon
only at `[1,1]`, a title at `[2,1]`, a full card at `[2,2]`). Declare only the sizes
you actually designed in `allowedSizes`. For a smooth change while the user drags the
resize handle, blend on `visualButton.width/height` instead of switching instantly.
`AndroidQuickToggleButton` does this with `morphWideProgress` / `morphTallProgress`.

### 5.5 In the tray

The tray draws the same component with `isUnused: true`. Keep it cheap there: no
timers, no service polling, no heavy loaders. Run live updates only when
`!root.isUnused` and the host is visible.

### 5.6 Register

- Catalog: `clockWidget: { kind: "widget", defaultSize: [2, 2], allowedSizes: [[2,1],[2,2]], families: ["island"] }`.
  Leave out `families` if the sidebar should offer the widget too.
- `DelegateChoice` in the chooser, with the same property block as 3.4.
- The tray files any kind other than `toggle` and `slider` under **Widgets**.

### 5.7 The island must know the size before it builds

`DashboardMetrics` predicts the dashboard's height with the same packer. This works for
any tile as long as its size comes only from the catalog, which it does if you follow
5.2. Do not give a tile an implicit size that depends on its content: the island's
morph would aim at the predicted size and then jump to the tile's real one.

---

## 6. Adding a details page

In the sidebar a tile's details open as a floating dialog. In the island the **same
dialog** opens as a page that replaces the grid. It slides in from the left with a fade
and gets a back button. You write the dialog once, and `WindowDialog`'s page mode
handles the rest.

### 6.1 Write the dialog

`modules/common/quickToggleDialogs/caffeine/CaffeineDialog.qml`. The directory becomes
the import `qs.modules.common.quickToggleDialogs.caffeine`.

```qml
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

WindowDialog {
    id: root
    backgroundWidth: 400          // dialog width in the sidebar; a page fills the island

    // ── Header: the FIRST child. Title on the left, the master switch on the right.
    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 4
        Layout.rightMargin: 4
        spacing: 0

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Caffeine")
            font.pixelSize: Appearance.font.pixelSize.larger
            font.weight: Font.Bold
            color: Appearance.colors.colOnLayer1
        }

        StyledSwitch {
            checked: Caffeine.active
            onToggled: Caffeine.toggle()
        }
    }

    // ── Content
    WindowDialogParagraph {
        Layout.fillWidth: true
        text: Translation.tr("Keeps the screen awake.")
    }
    // For lists, give the content Layout.fillHeight: true and make it scroll itself
    // (see WifiDialogContent).

    // ── Buttons: the LAST child.
    WindowDialogButtonRow {
        Layout.fillWidth: true
        Item { Layout.fillWidth: true }
        DialogButton {
            buttonText: Translation.tr("Done")
            onClicked: root.dismiss()
        }
    }
}
```

How page mode treats this dialog:

- **Header detection.** If the first child is a `RowLayout` or a `WindowDialogTitle`, it
  is the header. The back button is placed at its left, and the header is indented
  52 px to make room. Without such a header, the page gets its own bar with the back
  button and `pageTitle`, which the host sets.
- **No dialog chrome.** Page mode removes the scrim, the card background, the rounding
  and the pop-in (scale 0.88 plus a 40 px rise). The host does the motion.
- **Height.** `pageContentHeight` is the content's implicit height, plus the 12 px
  margins and the bar. The island grows or shrinks to it, capped at the screen, and
  never goes below the dashboard's resting height. Set `backgroundHeight` (as
  `WifiDialog` does with 600) for dialogs whose content is a scrolling list, which has
  no useful implicit height.
- **Back.** The back button calls `dismiss()`, and so should the Done button. The host
  listens to `dismiss` and slides back to the grid.
- **Details.** If the dialog opens the full settings, emit `signal detailsRequested()`,
  and guard any sidebar-specific side effect with a `closeOwningSidebarOnDetails`
  property (see `WifiDialog`). The island sets that property to false and treats
  `detailsRequested` as "leave the page".
- **Keyboard.** While a page is open the island takes keyboard focus, so text fields
  such as a Wi-Fi password work.
- **Lifetime.** The page is created when opened and destroyed after its exit slide.
  Start scanning or polling in `onShowChanged` (with `show` true) and stop it in
  `Component.onDestruction`, as `WifiDialog` does.

### 6.2 Wire the signal

1. `modules/common/quickToggles/AbstractQuickPanel.qml`: `signal openCaffeineDialog`.
2. `AndroidToggleDelegateChooser.qml`:
   - Add `signal openCaffeineDialog`.
   - In the tile's choice, add `onOpenMenu: root.openCaffeineDialog()`.
3. `AndroidQuickPanel.qml`: the chooser is instantiated **twice** (the grid and the
   tray). Add `onOpenCaffeineDialog: root.openCaffeineDialog()` to both.
4. The model: set `hasMenu: true`.

### 6.3 Register the page in the island

`modules/ii/dynamicIsland/dashboard/IslandDashboard.qml`:

```qml
import qs.modules.common.quickToggleDialogs.caffeine      // 1. import

readonly property var pageComponents: ({
    ...,
    caffeine: caffeinePage                                // 2. map the id
})

AndroidQuickPanel {
    ...
    onOpenCaffeineDialog: dashboard.showPage("caffeine")  // 3. route the signal
}

// 4. The component. pageMode MUST be declared here, at creation. Set later, the
//    dialog is born in dialog mode and its pop-in plays under the page slide.
Component { id: caffeinePage; CaffeineDialog { pageMode: true } }
```

If the dialog has no header row, also add a title to `pageTitles`:

```qml
readonly property var pageTitles: ({ ..., caffeine: Translation.tr("Caffeine") })
```

### 6.4 The sidebar

The sidebar hosts the same dialogs as real dialogs through its own `on<Name>Dialog`
handlers. Wire the new signal there too if the tile should have details in the sidebar.

---

## 7. Design rules

- **Colors.** Use only `Appearance.colors.*` / `Appearance.m3colors.*`; never
  hard-code a color. Use these pairings:

  | Surface | Color |
  |---|---|
  | Tile at rest | `colLayer2` |
  | Tile hovered | `colLayer2Hover` |
  | Toggled tile | `colPrimary` with `colOnPrimary` content |
  | Section or card inside a page | `colLayer2`, or `colSecondaryContainer` for callouts |
  | Text on a tile | `colOnLayer2` |
  | Text on a page | `colOnLayer1` |

- **Radii.** Use `Appearance.rounding.*`. Tiles use
  `min(width/2, height/2, rounding.large)`, and 0 when
  `Config.options.appearance.sharpMode` is on. For connected button groups (M3
  Expressive), use `rounding.full` on the outer ends and `rounding.verysmall` inside
  (see `GridStepper`).
- **Type.** Use `StyledText` with `Appearance.font.pixelSize.*`. Titles use `larger` and
  bold, labels use `small`, and secondary text uses `smaller`.
- **Icons.** Use `MaterialSymbol` with Material Symbols names.
- **Chrome that scales with the cell.** Use `QuickToggleMetrics.scaled(baseCellHeight, v)`
  for icon sizes, paddings and radii inside a tile. The tablet host uses larger cells,
  and your tile should scale with them.
- **Motion.** Use `Appearance.animation.*` presets and `Appearance.animationCurves.*`.
  - Never put a `Behavior` on a value derived from something that is already animating.
    Compute it from the animated value instead.
  - Never let a tile's content drive its own size. The catalog and the packer decide it.
- **Density.** A 1×1 tile is 96 × 56 px: an icon and at most one short word. Put
  anything richer on a wider or taller allowed size.
- **Performance.**
  - The dashboard is rebuilt every time the island expands. Keep tiles light: no
    synchronous file IO or process spawns on creation.
  - Put expensive children in `Loader { asynchronous: true }`.
  - Tie timers to visibility.
- **Strings.** Every visible string goes through `Translation.tr()`, with keys in
  `en_US.json` and `pt_BR.json`.

---

## 8. Checklist

Simple toggle:

- [ ] `models/quickToggles/<Name>Toggle.qml` (model)
- [ ] `quickToggles/androidStyle/Android<Name>Toggle.qml` (tile)
- [ ] `QuickToggleCatalog.js`: entry in `TOGGLE_TYPES`, plus `TYPE_CATEGORIES` if connectivity
- [ ] `AndroidToggleDelegateChooser.qml`: a `DelegateChoice`
- [ ] Translations
- [ ] Optional: default layout in `Config.qml`, `QuickToggleRegistry.qml`, `QuickToggleIcon.qml`

With a details page:

- [ ] `quickToggleDialogs/<name>/<Name>Dialog.qml` (header `RowLayout` first, button row last)
- [ ] `hasMenu: true` on the model
- [ ] `AbstractQuickPanel.qml`: signal
- [ ] `AndroidToggleDelegateChooser.qml`: signal and `onOpenMenu`
- [ ] `AndroidQuickPanel.qml`: forward the signal in **both** chooser instances
- [ ] `IslandDashboard.qml`: import, `pageComponents`, `on…Dialog` handler, and
      `Component { …Dialog { pageMode: true } }`; `pageTitles` if there is no header
- [ ] The sidebar host, if the page should be there too

Custom widget:

- [ ] The full tile contract (§5.1), the geometry block (§5.2), and `visualButton` +
      `EditableQuickToggleItem` (§5.3)
- [ ] `allowedSizes` listing only designed sizes; `families` if it is host-specific
- [ ] Cheap when `isUnused`

---

## 9. Testing

Quickshell accepts many mistakes silently: a missing import, an unknown property in a
delegate, a type with no `DelegateChoice`. Check the log after every change:

```sh
qs log -c ii | tail -40
```

`console.log` is not persisted. Use `console.warn` for temporary probes.

To confirm a page's size and header detection without clicking through, add a temporary
`console.warn(pageLoader.item.pageContentHeight, pageLoader.item.pageHeaderRow)` in
`IslandDashboard`'s `pageLoader.onLoaded` and open the page once.

Then test by hand:

1. Open the island dashboard and press the toolbar's edit button.
2. Find the tile in the tray under its category. Drag it into the grid.
3. Resize it through every allowed size. Reorder it. Check that a full grid grows by a
   row, or a column when the screen is too short.
4. Leave edit mode, tap it (`mainAction`), then right-click it or tap a wide version to
   open its page.
5. Check the page's back button and Done, and check that the island's height matches
   the page.
6. Remove the tile and confirm it returns to the tray.
