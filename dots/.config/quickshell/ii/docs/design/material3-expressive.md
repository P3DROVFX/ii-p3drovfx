# Material 3 Expressive — design reference for this shell

> Written from the Clock app (`modules/ii/clock/`), which is
> the most complete Material 3 Expressive surface in the shell. Use it as the base for new
> apps, overlays and redesigns: read it before designing, and copy the Clock's components
> instead of inventing new ones.

---

## 0. The short version

1. **Surfaces, not lines.** Separate things with gaps, fills and corner radii — never with
   borders or dividers. (The only outline allowed is the dashed "unselected" chip/button
   borrowed from the timetable rail.)
2. **One accent family per element.** A card and the control on it share a hue family
   (primary container + primary switch). Never a blue switch on an orange card.
3. **Type carries the hierarchy.** Big condensed digits for the one number a screen is
   about; the rounded title face for headings; small bold captions over values.
4. **Shape is state.** Circles for idle, rounded squares for active; a state change
   **morphs** the shape into another one (focus, hover, toggle). Rotation is reserved for
   values that turn (a swap, elapsed time) — never as decoration or on a loop.
5. **Nothing floats over the page that could open beside it.** Dialogs are side sheets on
   the right that push the page; only true pickers (time/date) are modal.
6. **Motion follows the value.** Rings drain over each second, shapes rotate with progress,
   tiles re-deal with move transitions. Decide layout on the settled size; only stretch
   on the animating one.
7. **Use the space.** On a desktop window, fill it: dense grids, heroes that span columns,
   side-by-side panes. Empty space is a bug, not "breathing room".

---

## Hard rules (non-negotiable)

These hold on every screen, overlay and widget. They override anything else in this
document.

- **No borders. Ever.** Never set `border.width` / `border.color` — not on hover, not on
  focus, not "just a thin line". Hierarchy comes from fill, corner radius and surface
  elevation. The dashed "unselected" chip (§0) is the only sanctioned outline; a module
  that has another exception documents it locally, and it sets no precedent.
- **No nested cards.** A component that draws its own surface (`ConfigSwitch`,
  `ConfigSpinBox`, `ConfigSlider`, `ConfigSubpageRow`, form rows…) is never wrapped in
  another card. In Settings, `ContentSubsection` holds only a title plus a
  `ConfigSelectionArray` (or a `NoticeBox`); interactive controls are direct children of
  the section's `ColumnLayout`, toggled with `visible:` when conditional.
- **Colour pairs never cross.** Content is always the `on*` half of the *same* pair as the
  surface it sits on:

  | Surface | Content |
  |---|---|
  | `colPrimary` | `colOnPrimary` |
  | `colPrimaryContainer` | `colOnPrimaryContainer` |
  | `colSecondaryContainer` | `colOnSecondaryContainer` |
  | `colTertiary` | `colOnTertiary` |
  | `colTertiaryContainer` | `colOnTertiaryContainer` |
  | `colSurfaceContainerHigh(est)` | `colOnSurface` |
  | `colError` | `colOnError` |
  | `colErrorContainer` | `colOnErrorContainer` |

  The theme never warns: an `on*` colour "looks" like a text colour but can be black on dark
  brown in another palette. Check real contrast against the generated scheme before
  trusting a pair.
- **Colour roles are reserved.** `colSecondaryContainer` is the neutral default for pills;
  primary is real emphasis only; tertiary is persistent, non-actionable status; `colError*`
  is **only** destructive actions or real failures — never generic "attention" (say it in
  words, not in red).
- **Hover and press from tokens.** Use the `*Hover` / `*Active` tokens, never
  `Qt.lighter()` / `Qt.darker()`. A container without a ready token uses
  `ColorUtils.mix(container, onContainer, 0.9)`.
- **No pulses.** No breathing glow, oscillating scale, or opacity cycling in a loop. They
  distract and keep the GPU busy. One-shot entrances with a defined end are fine.
- **No decorative scale.** No scale-pop or generic bounce. Scale only with a functional
  reason: press feedback (§8.2) or a state that needs a momentary highlight.
- **One geometry, one animation.** Never animate the same size/position in two places
  (e.g. a `Behavior` on the shape *and* another on the slot that holds it) — the expressive
  curves overshoot, so the user sees two movements. Interpolate one `progress` value and
  derive every dimension from it. Appearance (`opacity`, icon `scale`, `color`) may keep
  its own Behaviors.
- **Library before custom.** Buttons, text, icons, shapes, switches, sliders, progress bars
  and popups already exist in `modules/common/widgets/` (`RippleButton`, `StyledText`,
  `MaterialSymbol`, `MaterialShape`, `StyledSwitch`, `StyledSlider`, `StyledProgressBar`,
  `StyledPopup`…). A `Rectangle` + `MouseArea` posing as a button is a violation.
- **Elevation, not outlines.** Depth uses `StyledDropShadow` / `StyledRectangularShadow`,
  gated on the relevant shadow option.
- **Don't repeat a technique inside a module.** If a shape is already the background of one
  card, don't use a shape as background for the next; vary with contrast, pattern,
  typography, motion — or negative space, which gives the eye a rest when the interface is
  dense with toggles and information.

---

## 1. Tokens — never hard-code

All colour, radius, size and motion values come from a style singleton. The Clock's is
`modules/ii/clock/components/ClockStyle.qml`; new apps should create their own
`<App>Style.qml` with the same shape, mapped onto `Appearance`.

```qml
// <App>Style.qml
pragma Singleton
Singleton {
    readonly property color colBackground: Appearance.colors.colLayer0
    readonly property color colPane: Appearance.colors.colLayer1          // rail, panes
    readonly property color colSheet: Appearance.m3colors.m3surfaceContainerHigh      // side sheets
    readonly property color colField: Appearance.m3colors.m3surfaceContainerHighest   // rows inside sheets
    readonly property color colFieldHover: Appearance.colors.colSurfaceContainerHighestHover
    readonly property real radiusCard: Appearance.rounding.verylarge
    readonly property var motionFast: Appearance.animation.elementMoveFast
    readonly property var motionDefault: Appearance.animation.elementMove
    // …s
}
```

Rules:
- Colours: `Appearance.colors.*` / `Appearance.m3colors.*` only.
- Radii: `Appearance.rounding.*` only (`small` 12, `normal` 17, `large` 23, `verylarge` 32,
  `full`). Respect `rounding.scale === 0` (sharp mode) — use helpers such as
  `pill(h) = min(h/2, rounding.large)`.
- Motion: `Appearance.animation.*` (`elementMoveFast`, `elementMove`, `elementMoveEnter`,
  `elementMoveExit`, `elementMoveSmall`) and `Appearance.animationCurves.*`.
- Honour `Appearance.reducedMotion`: every `Behavior` gets `enabled: !reducedMotion` where
  the motion is not essential.

---

## 2. Colour

### 2.1 Surface ladder

| Layer | Token | Used for |
|---|---|---|
| Window | `colLayer0` | the app background |
| Pane | `colLayer1` | rail, hero panes, idle cards, settings rows, lap/durations panes |
| Pane hover | `colLayer1Hover` | idle card hover |
| Rail row | `colLayer2` (+Hover/Active) | destinations in the rail |
| Sheet | `m3surfaceContainerHigh` | side sheet background |
| Field | `m3surfaceContainerHighest` | rows, fields, tiles inside a sheet; dial faces |

A step up the ladder means "this sits on that". Never place two neighbours on the same
layer without a gap between them.

### 2.2 Accent roles

| Role | Container / on-container | Meaning |
|---|---|---|
| Primary | `colPrimary` / `colOnPrimary` | *the* state: current destination, the hero tile, the play button when idle, a selected day |
| Primary container | `colPrimaryContainer` / on | an **enabled** thing: alarm on, FAB, running play button, time tile hover |
| Secondary container | `colSecondaryContainer` / on | selected chips, toggled rows, idle controls (+1:00, reset), the row being edited |
| Tertiary / container | `colTertiary*` | a second voice: break phase, "on" icon shape in toggle rows, day badge |
| Error container | `colErrorContainer` / on | destructive buttons (delete), missed alarms, finished timers, slow laps |

**Harmony rule.** A control inherits its card's family. Enabled alarm card =
`colPrimaryContainer`, its switch = `colPrimary` track + `colOnPrimary` thumb. A toggled
form row = `colSecondaryContainer`, its switch = `colOnSecondaryContainer` track +
`colSecondaryContainer` thumb. Disabled cards drop to `colLayer1` and the switch to the
default inactive colours.

### 2.3 Tinted actions on any card

Small actions on a card are tinted with the card's *content* colour, not a fixed colour:
`applyAlpha(colContent, 0.08)` idle, `0.16` hover, `0.24` pressed. Delete is always
`colErrorContainer` / `colOnErrorContainer`. See `ClockCardAction`.

---

## 3. Typography

| Use | Font | Axes / size |
|---|---|---|
| The one number (alarm time, timer, stopwatch, world time) | `Appearance.font.family.main` (Google Sans Flex) | `axesDigitsBold` = `{wght: 760, wdth: 40, ROND: 100}` — tall, condensed, rounded; size computed from the space |
| Inactive number | same | `axesDigits` = `{wght: 560, wdth: 30, ROND: 100}` |
| Page title, hero line, FAB/rail labels | `family.title` + `variableAxes.titleRounded` | `pixelSize.huge` (+4 for app bar) |
| Card label | main | `textNormal`, DemiBold |
| Caption over a value (forms) | main | `pixelSize.smallest`, **Bold**, `colOnSurfaceVariant` |
| Value under a caption | main | `pixelSize.small`/`normal`, Bold |
| Secondary line | main | `textSmall`, `colSubtext`, opacity ~0.8 |

- You can also make the design more expressive by contrasting with different variable axis texts changing width, weight and sizes, italic, non rounded, different texts are crucial

Rules:
- **Stack digits when it buys size.** An alarm tile shows `19` over `16` only if the stacked
  size beats the inline size by 20%; otherwise `19:16`. Always compute the digit size from
  the *remaining* height after header and footer, so the footer is never pushed out.
- **Animate weight, don't swap it.** Interpolate `wght`/`wdth` with a `Behavior` on a
  0→1 `boldness` value (see `AlarmCard.digitAxes`).
- Round every computed font size (`Math.round`) — fractional sizes re-rasterise per frame
  and shimmer during layout animations.
- Truncated text elides (`Text.ElideRight`) and gets a tooltip only when `truncated`.
- Title case for headings and buttons ("New alarm"), sentence case for descriptions.

---

## 4. Shape

- **Material shapes** (`MaterialShape`, `MaterialShapeWrappedMaterialSymbol`) carry icons in
  forms and badges: `Cookie4/6/7/9/12Sided`, `Sunny`, `SoftBurst`, `Clover4Leaf`, `Flower`.
  Each form row uses its own shape so a sheet does not read as a column of identical dots.
- **Shape = state:** circle when idle, rounded square when active (play button: radius
  `size/2` → `min(size*0.3, verylarge)`). Keep the footprint constant; only the corners move.
- **Morph, don't spin:** focus, hover and toggle states swap
  the shape for another (`MaterialShape` morphs between polygons on its own when `shape`
  changes): e.g. `Clover4Leaf` → `Sunny` while a text field has focus, `Cookie9Sided` →
  `Cookie12Sided` on hover. A shape that rotates when a field gains focus reads as
  strange — don't do it. Rotation stays only where it carries meaning: a swap button
  turning half a turn per swap, a stopwatch turning with elapsed time. (Older Clock code
  still rotates form icons on hover; don't copy that into new screens.)
- **Ornaments** are big and clipped: a scalloped shape ~1.9× the tile height parked off the
  right edge at 8–10% opacity, cut by a mask of the tile (`MultiEffect` + a `Rectangle` mask
  kept in the tree — never Qt5Compat `OpacityMask`, which leaks window references). It may
  rotate slowly with real time (once a minute), never on a loop.
- **Grouped lists** (rail, settings): one shape for the group — outer corners
  `rounding.large`, joins `rounding.verysmall`; the current row becomes a pill and the rows
  facing it round too, so the selection presses a notch into the group (`ClockRailItem`).
  **Every row has its own background** (`colLayer2`, hover/active variants; selected =
  `colPrimary`), and the pressed row also turns pill with its neighbours following, as in
  `modules/settings/SidebarNavButton.qml`. A scrolling list sits in a container with
  `rounding.large` corners that clips rows as they scroll: `CornerCutouts` in the page
  colour over an opaque background, a `MultiEffect` mask layer only when the background is
  translucent (`modules/settings/Sidebar.qml`; translator `TranslatorLanguageSheet`).

---

## 5. Layout

### 5.1 App frame (the Notes/Clock pattern)

```
┌ app bar: [rail toggle] Title / subtitle ........................ [actions] [close] ┐
├──────────┬────────────────────────────────────────────────┬───────────────────────┤
│  rail    │  page                                          │  side sheet (opens)   │
│ (76/228) │                                                │  (300–380, pushes)    │
│ places   │                                 [large FAB] ◢  │                       │
│ …        │                                                │                       │
│ Settings │                                                │                       │
└──────────┴────────────────────────────────────────────────┴───────────────────────┘
```

- Window: floats, centred, the same size as Usage/Modes
  (`min(1500, max(900, 0.92·screenW)) + 40` × `min(700, max(460, 0.62·screenH)) + 100`);
  Hyprland rules `float` + `center` by title.
- Panes are slabs on `colLayer1` with `paneGap` (12) between them. No dividers.
- **Rail:** collapsed (icons + tooltips) / expanded (labels + badges), persisted, forced
  collapsed below 1100 px. Destinations as one grouped shape; **Settings at the bottom**;
  live badges (counts, "•" for running).
- **Compact (< 700 px):** rail → bottom navigation bar; the side sheet takes the full width.
- **FAB:** the page's main action as the cheatsheet `FloatingActionButton` — large
  (`baseSize` 88, icon 34), `expanded: hovered` so the label unfolds to the left, inside
  the page's bottom-right corner so an opening sheet pushes it. Hide it (slide down + fade)
  when the page has no action. Scrolling pages keep `fabClearance` free at the bottom.

### 5.2 Using desktop space

- **Dense grids.** Tile minimum ~260 px; columns = `floor((w+gap)/(min+gap))`; heights from
  width (`w·0.82`, clamped). A hero tile spans 2 columns.
- **Every grid item carries its own width.** Never let a layout stretch columns — a lone
  item swells to the full row and neighbours collapse to slivers.
- **Side-by-side ≥ ~820 px:** hero pane + list (world clock), stage + laps (stopwatch),
  stage + durations (pomodoro), tonight + history (bedtime). Below: stacked, scrolling.
- **Lists that deserve room get one column** (world clock cities): bigger rows, bigger
  type, an extra line of information.
- **Show secondary panes only when they have content** (laps pane appears on the first lap,
  sliding in by width).

### 5.3 Settled width vs live width (no shaking)

When a sheet opens or the rail folds, the page width animates. **Decide layout on the
settled width, stretch on the live one:**

```qml
// app root
readonly property real pageLayoutWidth: width - gaps - railWidth - (sheetOpen ? sheetWidth + gap : 0)
// page
property real layoutWidth: width                   // passed pageLayoutWidth
readonly property int columns: from(layoutWidth)   // stable during the animation
readonly property real tileLayoutWidth: …(layoutWidth)
Flow {
    width: Math.max(liveWidth, layoutWidth)       // never narrower than the settled layout
    move: Transition { NumberAnimation { properties: "x,y"; … } }
    Tile { width: Math.floor(tileLayoutWidth); Behavior on width { … } }
}
```

Font sizes, stacking and ring sizes read `layoutWidth`, never `width`.

---

## 6. Components (copy these)

All in `modules/ii/clock/components/` unless noted.

| Component | What it is |
|---|---|
| `ClockRail` / `ClockRailItem` | Notes-style rail and destination rows (grouped shape, badges, hover 1.02 / press 0.95) |
| `ClockNavigation` | bottom navigation bar for compact windows |
| `ClockTopBar` | app bar: rail toggle, title (animated), subtitle (fades with the page), actions, close |
| `ClockSidePanel` | host for side sheets: `show(component, props)`, `close()`, `closeNow()`; destroys sheets after they slide away |
| `ClockSheet` | a side sheet: title/subtitle, header icon actions, close, scrolling body, footer actions; entrance = fade + 24 px slide |
| `ClockPickerHost` | the shell's `TimePickerPopup`/`DatePickerPopup`, owned by the window so they centre over the app; callback API |
| `ClockFormField` | timetable "Title" row: shape icon + caption + text input |
| `ClockFormPicker` | timetable "Date" row: shape icon + caption + value + chevron (turns 90° when expanded) |
| `ClockFormToggle` | timetable "All day" row: fills secondary container when on, shape swaps to tertiary and turns |
| `ClockFormChip` | timetable duration chip: dashed outline unselected, secondary container selected |
| `ClockSheetAction` | sheet footer button: dashed outline (secondary) or filled pill (primary), `danger` variant |
| `ClockCardAction` | hover action on a card, tinted with the card's content colour, `danger` for delete |
| `ClockProgressRing` | M3E wavy circular progress (see §8) |
| `ClockPlayButton` | circle ↔ rounded-square start/pause, constant footprint |
| `ClockDayChips` | seven day circles, locale week start |
| `ClockStepper` | − value + with wheel support |
| `ClockEmptyState` | expressive shape + title + subtitle, one-shot entrance |
| `ClockSettingsSection` / `ClockSettingsRow` | grouped settings (only title + control inside rows; no nested cards) |
| `common/widgets/FloatingActionButton` | the FAB (expand on hover) |
| `common/widgets/StaggeredEntrance` | one-shot staggered fade/scale for lists and grids |

### 6.1 Forms (the timetable rail vocabulary)

A sheet's body is a column of filled rows (`colField`, radius `small`, 56–66 px), each with:
a Material-shape icon (`padding 9`, `iconSize 18`, primary-container colours), a small bold
caption, and a bold value. Choices are rows of dashed `ClockFormChip`s. Booleans are
`ClockFormToggle` rows. Big values (a time) get a tall tile with the value in expressive
digits; the whole tile opens the picker and fills with primary container on hover.

Footer: `[ Cancel (dashed) ]` over `[ Primary action (filled pill) ]`, full width, 46–48 px.
Destructive and secondary actions live as icon buttons in the sheet header.

Keyboard: Esc closes the sheet, Ctrl+Enter saves, Enter in the title saves.

---

## 7. Sheets vs popups

- **Side sheet** (right, pushes the page, width `clamp(0.28·w, 300, 360)`): editors,
  creation flows, search/pickers with lists (timezone search), renames, secondary keypads.
  The page stays visible; the edited item is highlighted in place.
- **Modal picker** (centred over the whole window, scrim): only the shared time/date
  pickers, which need their fixed dial/grid size. Host them at window level, not inside the
  narrow sheet. In small hosts (a sidebar widget) where the dial would be clipped, use an
  inline editor instead (quick chips + steppers).
- **Never** a centred dialog for editing.
- One sheet at a time; switching tab drops it (`closeNow`). Sheets are built on demand and
  destroyed after closing.

---

## 8. Motion

### 8.1 Curves and durations

| Situation | Token |
|---|---|
| Colour, opacity, small reveals | `elementMoveFast` |
| Size, position, layout re-deal, sheets | `elementMove` (expressive default spatial, slight overshoot) |
| Small springy things (switch thumb, chip widths) | `elementMoveSmall` / `expressiveFastSpatial` |
| Entering / leaving pages | `elementMoveEnter` + `emphasizedDecel` / `elementMoveExit` + `emphasizedAccel` |

### 8.2 Patterns

- **Tab switch:** old page fades out (half exit duration) → swap → new page fades in while
  translating up 24 px. The title changes at once; the subtitle fades with the page.
- **Page over page (settings):** a 0→1 progress drives opacity and a short translate
  (≤ 96 px), emphasized decel in / accel out. Never bind an overlay's x to a width that can
  animate — it will drag the "closed" overlay back into view.
- **Side sheet:** the slot animates its width (`elementMove`) and clips; the sheet inside
  keeps a fixed width pinned right, so it slides instead of reflowing; its content arrives
  with a fade + 24 px slide.
- **Hover reveal (ToDo pattern):** one `revealProgress` (0→1, `elementMoveFast`) drives the
  width of a clipped action slot *and* the label's elision; the action row is anchored to
  the slot's left so buttons slide in from the right. Engagement = `HoverHandler.hovered ||
  any action has activeFocus` (use `HoverHandler`, not `MouseArea.containsMouse`).
- **Grids:** `Flow` with `move: Transition` + `Behavior on width` on tiles.
- **Continuous values:** a value that ticks once a second glides linearly over exactly that
  second (`tickDuration: 1000`); larger jumps (reset, +1:00) take the eased curve.
- **Wave never switches off:** the progress ring's amplitude animates to 0 on pause instead
  of swapping ring styles.
- **Rotation that means time:** stopwatch shape rotates one turn per minute from the
  elapsed time; pomodoro shape turns a quarter per phase, counted across phases so it never
  unwinds; hands animate on the shortest arc (unwrapped angle).
- **Variable-font emphasis:** interpolate axes (§3).
- **Staggered entrances** (`StaggeredEntrance`) for lists/tiles on first build only.
- **FAB:** label expands on hover; slides down + fades when the page has no action.
- **Press feedback:** rail/buttons 0.95 on press, 1.02 on hover (Notes pattern) — the only
  sanctioned scale; no decorative scale, no pulses, no infinite loops.

---

## 9. Screens (reference implementations)

- **Alarms** — hero tile (2 columns, primary, big "In 23h 57m" line, skip, phone chip,
  clipped ornament) + tiles with stacked expressive digits, repeat summary, full-size switch
  and hover actions (edit, duplicate, delete). Missed-alarm banners (error container) above
  the grid. Timetable suggestions strip below.
- **World clock** — hero pane (digital time with seconds in primary, date, analog dial
  carrying every city as a tag) + single-column city rows (day/night shape badge, name in
  title face, relation · offset · abbreviation, local date, big time; hover: move, rename,
  remove).
- **Timer** — keypad fills the page when nothing runs; otherwise horizontal cards: ring
  (with state shape inside) left, big time + "of 5m" right, and a bar of three equal-height
  rectangular controls (+1:00 / play / reset, stretch 2:3:2 so play is exactly centred).
- **Stopwatch** — scalloped dial rotating with elapsed seconds, colour = state, laps pane
  appears on the first lap (fastest primary container, slowest error container).
- **Pomodoro** — phase chip, wavy ring in the phase colour, rotating phase shape behind the
  digits, segmented cycle indicator (current segment widens and fills with progress),
  durations pane with timetable-style rows.
- **Bedtime** — "Tonight" pane (target tile with the switch, wind-down and reminder chips,
  night chips, link to Modes) + 14-night chart (bars hang from the target line: up = early,
  down = late; estimated nights faded) with stat tiles (streak, on-time count, average).
- **Settings** — two columns of grouped sections on wide windows; chips for choices.

---

## 10. Performance rules that shape the design

- Build on demand, release when closed: `RetainedLoader` (async, 30 s retention) for the
  window — the same scheme as Usage/Modes. Only the visible tab exists.
- Nothing ticks while hidden (`SystemClock.enabled: window.visible`).
- Hidden items still render and bind — gate expensive bindings on visibility.
- A Canvas (`MaterialShape`) repaints only while visible; rotate it with transforms, don't
  resize it every frame when avoidable.
- Keep services headless and small; UIs read them.

---

## 11. References

- Material 3 Expressive (Google I/O 2025) — Pixel Clock alarms (stacked condensed digits,
  toggle on tile), world clock dial with city tags, Gmail extended FAB, Health "This week"
  chart, Messages/Photos expressive shapes.
- This shell: cheatsheet timetable `EventSidebar` (form vocabulary, side rail, dashed
  chips), sidebar dashboard ToDo `TaskList` (hover reveal), Notes app (rail, app frame),
  Usage/Modes (window size, retained loader), cheatsheet `FloatingSearchBar` (FAB).

---

## 12. Checklist for a new screen

- [ ] Style singleton with tokens; no raw colours/radii/durations.
- [ ] No borders, no nested cards, no pulses, no decorative scale.
- [ ] Every content colour is the `on*` half of its surface's pair; error only for real failures.
- [ ] No technique repeated inside the module.
- [ ] App frame: app bar, rail (collapsible, settings at bottom), page, side sheet slot.
- [ ] Main action as the hover-expanding FAB inside the page.
- [ ] Every editor is a side sheet built from the form components; pickers at window level.
- [ ] Cards: one hue family per card; controls follow it; hover actions tinted.
- [ ] Layout decisions on the settled width; tiles have explicit widths; `Flow` + move.
- [ ] The key number in expressive digits, sized from remaining space, rounded.
- [ ] Motion: every state change animated with the right token; no loops, no decorative scale.
- [ ] Empty states with an expressive shape and a single call to action.
- [ ] Space used: dense grids / side-by-side panes on desktop, stacked on compact.
- [ ] Lazy build, release on close, nothing ticking while hidden.
- [ ] Strings through `Translation.tr` (en_US + pt_BR).
