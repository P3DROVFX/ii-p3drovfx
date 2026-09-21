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
6. [Variant groups: several designs, one tray entry](#6-variant-groups-several-designs-one-tray-entry)
7. [Adding a details page (the dialog)](#7-adding-a-details-page)
8. [Design rules](#8-design-rules)
9. [Checklist](#9-checklist)
10. [Testing](#10-testing)

---

## 1. How the pieces fit

```
IslandDashboard.qml                      (island host: frame, edit toolbar, pages)
 └─ AndroidQuickPanel                    (grid + tray, shared with the sidebar)
     ├─ QuickToggleEditController        (add / remove / move / resize, validation)
     ├─ QuickToggleLayout.js             (the packer: tiles -> x/y/width/height)
     ├─ QuickToggleCatalog.js            (every tile type, its kind and allowed sizes)
     ├─ TraySectionModel                 (the tray's sections, keyed by id)
     ├─ QuickToggleVariantSwitcher       (tray arrows for variant groups)
     └─ AndroidToggleDelegateChooser     (type string -> QML tile component)
         └─ Android<Name>Toggle.qml      (the tile; widget tiles build on
             │                            AndroidWidgetTileBase)
             └─ <Name>Toggle.qml         (optional model: name, icon, state, actions)
```

| File | Role |
|---|---|
| `modules/common/quickToggles/androidStyle/QuickToggleCatalog.js` | The **only** size policy. Declares each type's `kind`, `defaultSize`, `allowedSizes`/`maxHeight`, `families` and `permanent`. It also assigns tray categories. |
| `modules/common/quickToggles/androidStyle/QuickToggleLayout.js` | The packer. It places tiles left to right, top to bottom, first fit. Rows made only of sliders are drawn shorter. |
| `modules/common/quickToggles/androidStyle/AndroidToggleDelegateChooser.qml` | Maps the `type` string to a tile component. It also re-emits `open<Name>Dialog` signals. |
| `modules/common/quickToggles/androidStyle/AndroidQuickToggleButton.qml` | Base for normal toggle tiles. It handles the circle icon, the label/status, the morph between sizes and edit mode. |
| `modules/common/quickToggles/androidStyle/AndroidSliderWidgetBase.qml` | Base for slider tiles. |
| `modules/common/quickToggles/androidStyle/AndroidWidgetTileBase.qml` | Base for custom widget tiles: the grid contract, placement, resize and drag surface, and the edit overlay. A widget tile declares only its content (§5). |
| `modules/common/quickToggles/androidStyle/<topic>/` | Folders of related tiles, one design per file (for example `weather/`). Each folder is its own QML module. |
| `modules/common/quickToggles/androidStyle/QuickToggleTrayPreview.qml` | What the tray draws in place of a widget tile: its icon and name (§5.4). |
| `modules/common/quickToggles/androidStyle/QuickToggleVariantSwitcher.qml` | The arrows and dots that cycle a tray tile through its variant group (§6). |
| `modules/common/quickToggles/androidStyle/TraySectionModel.qml` | Keeps the tray's sections by id, so an edit updates only what changed instead of rebuilding the tray. |
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
| `widget` | `AndroidWidgetTileBase` | Its `allowedSizes` (weather: icon `[1,2]`, `[2,2]`, `[2,3]`; card `[2,2]`, `[2,3]`, `[3,3]`). | Custom content; see §5. Often one design of a variant group (§6). |

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
| `minWidth: n` | The narrowest width the tile may be resized or loaded at (1 by default, 0 for toggles). |
| `minHeight: n` | The shortest height the tile may be resized or loaded at (1 by default). |
| `fixedHeight: n` | Forces the height to `n`. |
| `families: ["island", ...]` | Hosts that offer the tile. Omit it to offer the tile everywhere. |
| `permanent: true` | The tile can be moved and resized but not removed. |
| `variantGroup: "name"` | One design of several: the tray shows the group as one entry with arrows to cycle designs (§6). |

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

    // Set hasMenu to give the tile a details page (section 7). With it, right-click
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
        // Only when the tile has a details page (section 7):
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

Use this when the content is not a toggle (a clock, a weather card, a mini calendar).
Build it on **`AndroidWidgetTileBase`**. The base implements everything the grid, the
tray and the edit controller need from a tile, so your file holds only the design.

References:

| File | What it shows |
|---|---|
| `androidStyle/weather/AndroidWeatherIconShapeToggle.qml` | The smallest widget tile on the base (about 60 lines). |
| `androidStyle/weather/AndroidWeatherCardToggle.qml` | A layout that adds rows as the tile grows taller. |
| `androidStyle/AndroidDashboardToolbarToggle.qml` | A tile that keeps a button live in edit mode (written before the base; it shows the raw contract). |
| `androidStyle/AndroidMediaWidgetToggle.qml` | A rich widget with several allowed sizes. |

### 5.1 Where the file goes

Keep one design per file, and group related tiles in a folder under `androidStyle/`:

```
modules/common/quickToggles/androidStyle/
├── AndroidWidgetTileBase.qml           (the base)
└── weather/                            (one folder per topic)
    ├── AndroidWeatherIconShapeToggle.qml
    └── AndroidWeatherCardToggle.qml
```

A folder is a QML module of its own. It is imported as
`qs.modules.common.quickToggles.androidStyle.weather`, and a file in it imports the base
with `import qs.modules.common.quickToggles.androidStyle`.

### 5.2 The tile

```qml
pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.quickToggles.androidStyle

AndroidWidgetTileBase {
    id: root

    tooltipText: Translation.tr("Weather")

    // Everything declared here is placed inside the tile's surface: it follows the
    // resize preview and the drag, and sits under the edit overlay.
    StyledText {
        anchors.centerIn: parent
        text: Weather.data?.temp ?? ""
        color: Appearance.colors.colOnLayer2
    }
}
```

What the base gives you:

| Property | Meaning |
|---|---|
| `surface` | The live surface Item. Use `surface.width/height` for sizes that must follow the resize preview while the user drags the handle. |
| `effectiveSizeW` / `effectiveSizeH` | The tile's size in cells, from the catalog. Branch layouts on them. |
| `surfaceColor` | The tile's fill. Default `colLayer2`; set `"transparent"` for a design that draws its own background. |
| `surfaceRadius` | The corner radius. Defaults to the grid's tile radius (0 in sharp mode). |
| `clipContent` | Clip children to the surface (default `true`; the clip is rectangular). |
| `isUnused` | `true` when the tile is drawn in the tray (see 5.4). |
| `editMode`, `panel`, `buttonData`, … | The standard contract, already declared (5.6). |

Do not set `x`, `y`, `width` or `height` on the tile: the packer places it and the
catalog sizes it.

### 5.3 Adapt to the size

- Declare in `allowedSizes` only the sizes you designed.
- Size content from `root.surface` (or anchors), never from fixed numbers, so it keeps
  up while the user drags the resize handle.
- Prefer layouts that degrade: the weather card shows its header at `[2,2]` and adds
  forecast rows as `surface.height` grows:

  ```qml
  readonly property int dayRows: Math.max(0, Math.min(3, Math.floor((root.surface.height - 96) / 24)))
  ```

- A tile's cell size is `96 × 56 px` with `6 px` spacing (see §2), so `[2,2]` is
  198 × 118 px and `[2,3]` is 198 × 180 px.

### 5.4 In the tray

**Widget tiles are not built in the tray.** Anything whose kind is `widget`, `media`,
`dashboardWidget` or `fullDashboardWidget` is stood in for by `QuickToggleTrayPreview`:
the tile's icon and name on an ordinary tile surface. It drags, packs and adds exactly
like the real tile; the real one is built when it lands on the grid. This is what keeps
opening edit mode cheap (31 ms instead of ~200 ms) and stops it getting slower as the
catalog grows.

So a new widget tile needs **one line** in the preview's `meta` table - its icon and
its name:

```qml
weatherCard: { icon: "partly_cloudy_day", label: Translation.tr("Weather") },
```

A type that is not listed falls back to a generic icon and its raw type name, which is
a bug worth fixing, not a supported state.

Toggles and sliders are still built for real in the tray, because they are cheap and
their state is worth seeing. Keep them cheap:

- no timers, polling or animations while `isUnused`;
- no `Loader`s for heavy content, or make them `active: !root.isUnused`;
- read services through bindings (they already update), never start them;
- the drawn (animated) icons are off in the tray - `QuickToggleIcon.allowAnimated` is
  `false` there, and the Material symbol is drawn instead.

**Sections open one at a time.** Only the open section's tiles exist: closing a section
destroys them, opening one builds them. Nothing is needed from a tile for this, but it
is another reason a tile must be cheap to build.

### 5.5 Interactive content

`EditableQuickToggleItem` (inside the base) takes presses in edit mode for drag and
resize. Outside edit mode your content receives input normally. Content that must stay
usable in edit mode (like the toolbar's edit button) goes above the overlay with
`z: 20`. Everything else should be `enabled: !root.editMode`, so a press starts a drag.

### 5.6 The raw contract

If a tile cannot use the base (its surface is not a single rectangle), it must declare
the contract itself. `AndroidDashboardToolbarToggle.qml` is the reference:

- **Properties set by the chooser:**
  - required: `buttonIndex`, `buttonData`, `baseCellWidth`, `baseCellHeight`,
    `cellSpacing`, `cellSize`;
  - optional: `editMode`, `isUnused`, `isDragging`, `dragOffsetX/Y`, `pageIndex`,
    `gridColumns`, `panel`, `gridRef`, `entranceTrigger`.
- **Read by the overlay:** `tooltipText`, `hovered`.
- **Resize direction:** `resizeDirectionX/Y` from the overlay.
- **Geometry:**
  - size from `QuickToggleCatalog.normalizeSize()`;
  - `Binding on x/y` from `buttonData.layoutX/layoutY` (the resize origin while
    resizing);
  - `Behavior on x/y` (`elementMoveFast`, off while dragging or resizing);
  - `z: 100` while dragging or resizing.
- **The surface:** follows `editableItem.previewWidth/Height` while resizing and takes
  the drag `Translate`; an `EditableQuickToggleItem` targets it.

### 5.7 Register

1. **Catalog** (`QuickToggleCatalog.js`):

   ```js
   weatherCard: { kind: "widget", defaultSize: [2, 3], allowedSizes: [[2, 2], [2, 3], [3, 3]] },
   ```

   Add `families: ["island"]` to restrict it to one host, and `variantGroup` to make it
   one design of several (§6).

2. **Delegate** (`AndroidToggleDelegateChooser.qml`): import the folder's module and add
   a `DelegateChoice` with the standard property block (§3.4).

3. **Tray section:** any kind other than `toggle` and `slider` is filed under
   **Widgets**.

### 5.8 The island must know the size before it builds

`DashboardMetrics` predicts the dashboard's height with the same packer. That works for
any tile whose size comes only from the catalog, which the base guarantees. Never give a
tile an implicit size that depends on its content: the island's morph would aim at the
predicted size and then jump to the real one.

---

## 6. Variant groups: several designs, one tray entry

A variant group is several designs of the same tile: the weather icon in a shape and the
weather card, for example. In the tray they share **one entry**. The user cycles through
the designs with arrows on the tile, then adds the one they want. On the grid, each
design is an ordinary type of its own.

### 6.1 How it behaves

- **Tray:**
  - The tray shows one tile per group: the design last shown, or the group's first.
  - Hovering the tile shows an arrow on each side and a row of dots underneath (which
    design, out of how many).
  - The arrows appear only when the group has **more than one design still off the
    grid**.
  - Clicking an arrow shows the previous or next design in place.
  - The add badge adds the design on show.
- **Grid:**
  - Added designs are separate tiles. They never show arrows and never change design.
  - Adding one design leaves the group's other designs in the tray; with only one left,
    its arrows disappear.
  - Several designs of a group can be on the grid at once.
- **Persistence:** which design the tray shows is not saved (`trayVariantChoice`); the
  grid saves types as usual.

### 6.2 Making a group

Give each design its own type and file (§5), and add the same `variantGroup` to each
catalog entry:

```js
weatherIconShape: { kind: "widget", variantGroup: "weather", defaultSize: [2, 2], allowedSizes: [[1, 2], [2, 2], [2, 3]] },
weatherCard:      { kind: "widget", variantGroup: "weather", defaultSize: [2, 3], allowedSizes: [[2, 2], [2, 3], [3, 3]] },
```

- **Order:** the order in the catalog is the order of the arrows; the first design is
  the group's default in the tray.
- **Sizes:** designs may have different `defaultSize` and `allowedSizes`; the tray
  re-packs the section when the user cycles.
- **Category and family:** keep designs in the same tray category (the same `kind`, or
  the same `TYPE_CATEGORIES` entry). Families (`families`) may differ; a host sees only
  the designs it allows.
- **Group names** are free strings. Use the topic (`"weather"`, `"clock"`), and match
  the folder name.

Nothing else is needed: the tray and the arrows read the catalog.

### 6.3 The pieces

| Piece | Where | Role |
|---|---|---|
| `variantGroup(type)`, `variantsOf(group)` | `QuickToggleCatalog.js` | Which group a type is in; a group's types in catalog order. |
| `unusedToggles` | `AndroidQuickPanel.qml` | Collapses each group to its chosen design before the tray is packed. |
| `trayVariantChoice`, `trayVariants()`, `trayVariantFor()`, `cycleTrayVariant()` | `AndroidQuickPanel.qml` | The tray's choice per group, the designs still available, cycling. |
| `QuickToggleVariantSwitcher.qml` | `androidStyle/` | The arrows and dots. It is an overlay placed from the packed geometry, above the tray tile. It has a hover handler only, so the tile underneath still gets drags and its add badge. |

The tile files know nothing about groups. A design needs no code to take part, only the
catalog field.

---

## 7. Adding a details page

In the sidebar a tile's details open as a floating dialog. In the island the **same
dialog** opens as a page that replaces the grid. It slides in from the left with a fade
and gets a back button. You write the dialog once, and `WindowDialog`'s page mode
handles the rest.

### 7.1 Write the dialog

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

### 7.2 Wire the signal

1. `modules/common/quickToggles/AbstractQuickPanel.qml`: `signal openCaffeineDialog`.
2. `AndroidToggleDelegateChooser.qml`:
   - Add `signal openCaffeineDialog`.
   - In the tile's choice, add `onOpenMenu: root.openCaffeineDialog()`.
3. `AndroidQuickPanel.qml`: the chooser is instantiated **twice** (the grid and the
   tray). Add `onOpenCaffeineDialog: root.openCaffeineDialog()` to both.
4. The model: set `hasMenu: true`.

### 7.3 Register the page in the island

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

### 7.4 The sidebar

The sidebar hosts the same dialogs as real dialogs through its own `on<Name>Dialog`
handlers. Wire the new signal there too if the tile should have details in the sidebar.

---

## 8. Design rules

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

## 9. Checklist

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

- [ ] The tile on `AndroidWidgetTileBase` (§5.2), in a topic folder (§5.1), one design
      per file
- [ ] `allowedSizes` listing only designed sizes; `families` if it is host-specific
- [ ] Cheap when `isUnused`

Variant group:

- [ ] Each design is its own type, file and `DelegateChoice` (§5)
- [ ] The same `variantGroup` on every design's catalog entry, in the order the arrows
      should follow; the default design first
- [ ] All designs in the same tray category

---

## 10. Testing

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
