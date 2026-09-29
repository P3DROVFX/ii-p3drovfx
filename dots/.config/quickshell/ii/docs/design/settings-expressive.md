# Settings pages — the Material 3 Expressive pattern

> How a Settings page is built after the Colors & Themes redesign (2026-09-28). Read
> `material3-expressive.md` first — this file only adds what is specific to pages inside
> the Settings window. Reference implementation: `modules/settings/configs/ColorsThemesConfig.qml`
> and its components in `modules/settings/configs/colors/`.

---

## 0. The short version

1. **A page is not a list of switches.** Lead with the thing the page is about, shown big
   (the wallpaper, a preview, a status). Switches are the last resort, not the default.
2. **Four building blocks, top to bottom:** hero → main pane → feature tiles → grouped rows.
   Not every page needs all four, but they come in this order.
3. **Surfaces on the ladder.** The page sits on `colLayer0`; panes, tiles and rows are
   `colLayer1`; things inside a pane are `colLayer2`. No borders, no `ContentSection` cards
   for new pages.
4. **State is colour and shape.** A feature that is on turns its tile `colPrimaryContainer`
   and morphs its icon's shape; a chosen item fills with `colSecondaryContainer`.
5. **Decide the layout from the width.** Every block has explicit breakpoints and computes
   its own columns; nothing relies on a layout stretching items.

---

## 1. Page skeleton

```qml
Item {
    id: pageRootItem
    anchors.fill: parent
    property alias contentY: pageRoot.contentY
    property alias activeSubPage: subPageOverlay.activeSubPage

    ContentPage {
        id: pageRoot
        anchors.fill: parent
        forceWidth: false
        opacity: subPageOverlay.slideProgress

        MyHero { Layout.fillWidth: true; Layout.preferredHeight: implicitHeight }
        MyMainPane { Layout.fillWidth: true }
        AppSettingsSection { Layout.topMargin: 12; title: …; symbol: …; /* tiles */ }
        AppSettingsSection { Layout.topMargin: 12; title: …; symbol: …; /* rows */ }
    }

    ConfigSubPageHost { id: subPageOverlay; anchors.fill: parent; z: 10 }
}
```

- `ContentPage` gives 12 px between blocks; a new titled group adds `Layout.topMargin: 12`
  so groups breathe more than the blocks inside them.
- Sub-pages open with `pageRootItem.activeSubPage = Qt.resolvedUrl("widgets/XConfig.qml")`
  (resolved in the page file, relative to `configs/`).
- No floating actions on a page (the old "Restart Shell" FAB is gone). If something needs a
  restart, fix the thing so it applies live.

---

## 2. The blocks

### 2.1 Hero

The subject of the page at the largest size the width allows.

- `radius: Appearance.rounding.verylarge`, content clipped with `ClippingRectangle`
  (never Qt5Compat `OpacityMask`).
- Height from width: `clamp(width / 1.7, 220, 460)`.
- Secondary variants of the subject sit **beside** it (a column of `clamp(0.3·w, 200, 320)`)
  on ≥ 620 px and in a row **below** it on narrower pages.
- Overlays on an image are opaque pills on `colSurfaceContainerHigh`: a name tag
  bottom-left, the main action bottom-right (filled `colPrimary`), status chips top-left,
  a palette/summary strip top-right. **Pills across the same edge share one height**
  (the action takes `tag.height`, 40 px on the hero, 32 px on small cards).
- The whole image is clickable (same action as the main button) with a scrim at 0.35 on
  hover; secondary actions on small cards (swap, remove) fade in on hover as 36 px circles.
- A variant that is off is an **invitation**, not a switch: a `colLayer1` card with a
  `MaterialShapeWrappedMaterialSymbol` that morphs on hover (`Cookie7Sided` →
  `Cookie12Sided`, `Sunny` → `VerySunny`), title in the title face, one-line hint. Clicking
  turns it on and opens the picker.

### 2.2 Main pane

The page's primary control, on a `colLayer1` slab (`radius verylarge`, padding 20).

- **Header:** a shape icon (`Cookie9Sided`, primary container, padding 12, icon 24) +
  title in `family.title` / `titleRounded` / `pixelSize.huge` + a subtitle in `colSubtext`
  that states the current value ("Intense · From your wallpaper"). While the pointer is over
  an option, the subtitle names it instead — so the options need **no tooltips**
  (`ColorPreviewGrid.showTooltips: false`).
- **Binary mode control** (light/dark): an M3E connected button group
  (`ColorsModeToggle`): two segments 3 px apart, outer corners pill, inner corners
  `rounding.verysmall`; the current segment fills `colPrimary` and rounds into a pill
  (animate an intermediate `inner` property — `RippleButton` already owns Behaviors on its
  corner radii). 248 px wide beside the title; full width under it below 560 px.
- **Filter chips** switch what the pane shows (`ColorsChip`): dashed outline while off,
  `colSecondaryContainer` + check when chosen, an optional count badge. Show one set of
  options at a time instead of stacking every set in a scroll box.
- **Option grid:** columns balanced over the rows the set needs —
  `maxCols = floor((w + gap) / (72 + gap))`, `rows = ceil(n / maxCols)`,
  `cols = ceil(n / rows)` — so no set ends with a lone straggler. Cell height
  `clamp(cellWidth · 0.6, 64, 80)`. Animate the container's `implicitHeight` when the set
  changes; cross-fade the grids.

### 2.3 Feature tiles

Each optional feature as a tile (`ColorsFeatureTile`) instead of a `ConfigSwitch` row.

- `radius verylarge`, padding 20 (top 18, right 18), fixed height (200) so a row stays level;
  the summary always reserves two lines.
- **Off:** `colLayer1`, icon in a circle on `colSecondaryContainer`.
  **On:** `colPrimaryContainer`, icon shape morphs to the tile's own shape on `colPrimary`
  (`Cookie12Sided`, `Flower`, `SoftBurst`, `Clover4Leaf` — one per tile).
- Switch top-right, vertically centred with the icon, `colPrimary` track / `colOnPrimary`
  thumb when on.
- Title in the title face (`pixelSize.larger`), summary in `pixelSize.smaller` at 0.8
  opacity that **says the live state** ("Night Light 19:00–06:30"), not a generic blurb,
  whenever there is a state to say.
- Footer: sub-options as chips on the tile (tinted with the tile's content colour, chosen =
  `colPrimary`), and a tinted "Configure" pill when a sub-page exists. Clicking the tile
  opens the sub-page; without one it toggles. The tile's `MouseArea` sits **under** the
  content so the switch and buttons keep their clicks.
- Columns: 4 / 2 / 1 from a 300 px minimum — never 3 + 1 for four tiles.

### 2.4 Grouped rows

What is left (paths, pickers, rare options) goes in `AppSettingsSection` groups built from
`AppChoiceRow`, `AppFieldRow`, `AppToggleRow`, `AppStepperRow`. A boolean with two named
outcomes is an `AppChoiceRow` with icon chips ("Built-in" / "System dialog"), not a switch.

---

## 3. Selection

- A chosen swatch/option: tile fill `colSecondaryContainer` (+ hover/active variants) **and**
  a `colPrimary` ring 2.5 px wide standing 2 px off the swatch
  (`ColorPreviewButton.ringGap` / `ringWidth`). Never fill a whole option with `colPrimary`.
- `ColorPreviewButton` declares its own `toggled`, which shadows `RippleButton`'s: the
  base's `colBackgroundToggled*` never apply — drive `colBackground*` from `root.toggled`.
- The ring and fills fade with `elementMoveFast`; nothing scales except the sanctioned
  press/hover feedback.

---

## 4. Responsiveness

Test every page at the Settings minimum (window 750 → page ≈ 496 px), the default
(1100 → ≈ 846 px) and maximised (≈ 1546 px).

| Block | Breakpoint | Narrow | Wide |
|---|---|---|---|
| Hero variants | 620 px | row below the hero | column beside it |
| Pane header | 560 px | mode toggle under the title, full width | beside the title, 248 px |
| Tiles | 300 px min | 1 column | 2 or 4 columns |
| Hero action | card < 420 px | icon-only circle + tooltip | icon + label |

Position hero children with explicit `x/y/width/height` from the computed values rather
than nested layouts — see `qt-nested-layout-fillwidth` for why layouts absorb slack.

---

## 5. Implementation traps

- **A new component folder for a page needs a hand-written `qmldir`**
  (`module qs.modules.settings.configs.<folder>` + one line per type). Pages load by URL,
  so the scanner never discovers the import; without it the log says
  `module … is not installed` and the **previous page stays on screen**.
- **Hot reload does not recompile Settings pages.** Restart the shell to see an edit:
  `killall qs; setsid -f qs -c ii` (check `pgrep -x hyprlock` first).
- Every file that calls `Translation.tr` imports `qs.services` — a missing import is only a
  `ReferenceError` at runtime.
- Settings search indexes the proxy sections listed in the page's `searchSources`
  (`SettingsPageRegistry`), not the new components. Keep a `ContentSection` proxy with the
  real `ConfigSwitch`es there when an option should stay searchable.
- Theme swatches read the shared `ThemePreviewCache`; bind to `ThemePreviewCache.revision`
  rather than relying on catching `cacheChanged`, and repaint a `Canvas` on
  `onAvailableChanged` / `onVisibleChanged` — a paint requested before either is lost.
- New strings go to both `translations/en_US.json` and `translations/pt_BR.json`.

---

## 6. Checklist for a Settings page

- [ ] The subject of the page is a hero, not a row.
- [ ] One main pane with a header that states the current value.
- [ ] Features are tiles with live summaries; switches only inside tiles or grouped rows.
- [ ] Options chosen with `colSecondaryContainer`; state shown by colour + shape morph.
- [ ] Pills along the same edge share a height; no tooltips that repeat on-screen text.
- [ ] Columns computed and balanced; tested at ≈ 496, 846 and 1546 px with no overflow.
- [ ] No FAB, no borders, no `ContentSection` cards on the page itself.
- [ ] `qmldir` for the component folder; shell restarted; `qs log -c ii` clean.
- [ ] Strings in en_US and pt_BR; search proxies still point at real controls.
