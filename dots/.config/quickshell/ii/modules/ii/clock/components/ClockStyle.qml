pragma Singleton

import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.widgets

/**
 * Every colour, radius, size and motion token of the clock app.
 *
 * Change a value here and every tab follows. Nothing below is a raw number the design
 * system already has a token for; the numbers that remain are layout measurements the
 * app owns (breakpoints, card sizes), all on the 4 px grid.
 */
Singleton {
    id: root

    // ── Surfaces ────────────────────────────────────────────────────────
    readonly property color colBackground: Appearance.colors.colLayer0
    readonly property color colOnBackground: Appearance.colors.colOnLayer0
    readonly property color colSurface: Appearance.colors.colSurfaceContainerLow
    readonly property color colSurfaceHigh: Appearance.colors.colSurfaceContainerHigh
    readonly property color colSurfaceHighest: Appearance.colors.colSurfaceContainerHighest
    readonly property color colSurfaceHover: Appearance.colors.colSurfaceContainerHighestHover
    readonly property color colSurfaceActive: Appearance.colors.colSurfaceContainerHighestActive
    readonly property color colOnSurface: Appearance.colors.colOnSurface
    readonly property color colOnSurfaceVariant: Appearance.colors.colOnSurfaceVariant
    readonly property color colSubtext: Appearance.colors.colSubtext
    readonly property color colScrim: Appearance.colors.colScrim
    readonly property color colOutline: Appearance.colors.colOutlineVariant

    // ── Accents ─────────────────────────────────────────────────────────
    readonly property color colPrimary: Appearance.colors.colPrimary
    readonly property color colPrimaryHover: Appearance.colors.colPrimaryHover
    readonly property color colPrimaryActive: Appearance.colors.colPrimaryActive
    readonly property color colOnPrimary: Appearance.colors.colOnPrimary
    readonly property color colPrimaryContainer: Appearance.colors.colPrimaryContainer
    readonly property color colPrimaryContainerHover: Appearance.colors.colPrimaryContainerHover
    readonly property color colPrimaryContainerActive: Appearance.colors.colPrimaryContainerActive
    readonly property color colOnPrimaryContainer: Appearance.colors.colOnPrimaryContainer
    readonly property color colSecondaryContainer: Appearance.colors.colSecondaryContainer
    readonly property color colSecondaryContainerHover: Appearance.colors.colSecondaryContainerHover
    readonly property color colSecondaryContainerActive: Appearance.colors.colSecondaryContainerActive
    readonly property color colOnSecondaryContainer: Appearance.colors.colOnSecondaryContainer
    readonly property color colTertiary: Appearance.colors.colTertiary
    readonly property color colOnTertiary: Appearance.colors.colOnTertiary
    readonly property color colTertiaryContainer: Appearance.colors.colTertiaryContainer
    readonly property color colTertiaryContainerHover: Appearance.colors.colTertiaryContainerHover
    readonly property color colTertiaryContainerActive: Appearance.colors.colTertiaryContainerActive
    readonly property color colOnTertiaryContainer: Appearance.colors.colOnTertiaryContainer
    readonly property color colError: Appearance.colors.colError
    readonly property color colOnError: Appearance.colors.colOnError
    readonly property color colErrorContainer: Appearance.colors.colErrorContainer
    readonly property color colErrorContainerHover: Appearance.colors.colErrorContainerHover
    readonly property color colOnErrorContainer: Appearance.colors.colOnErrorContainer

    // Per-tab accent pairs. An enabled alarm is a primary container and its switch the
    // primary itself — one hue family, so the control reads as part of the card instead of
    // a blue sticker on an orange one. Idle cards sit one step above the window.
    readonly property color colActiveCard: root.colPrimaryContainer
    readonly property color colActiveCardHover: root.colPrimaryContainerHover
    readonly property color colOnActiveCard: root.colOnPrimaryContainer
    readonly property color colIdleCard: Appearance.colors.colLayer1
    readonly property color colIdleCardHover: Appearance.colors.colLayer1Hover
    readonly property color colOnIdleCard: root.colOnSurfaceVariant
    readonly property color colFocus: root.colPrimary
    readonly property color colBreak: root.colTertiary

    // Panes: the rail and the side sheet are slabs on layer 1; rows inside a sheet sit on
    // the highest container, the way the timetable's event rail builds its form.
    readonly property color colPane: Appearance.colors.colLayer1
    readonly property color colSheet: Appearance.m3colors.m3surfaceContainerHigh
    readonly property color colField: Appearance.m3colors.m3surfaceContainerHighest
    readonly property color colFieldHover: Appearance.colors.colSurfaceContainerHighestHover
    readonly property color colRailRow: Appearance.colors.colLayer2
    readonly property color colRailRowHover: Appearance.colors.colLayer2Hover
    readonly property color colRailRowActive: Appearance.colors.colLayer2Active

    // ── Shape ───────────────────────────────────────────────────────────
    readonly property real radiusSmall: Appearance.rounding.small
    readonly property real radiusNormal: Appearance.rounding.normal
    readonly property real radiusLarge: Appearance.rounding.large
    readonly property real radiusExtraLarge: Appearance.rounding.verylarge
    readonly property real radiusFull: Appearance.rounding.full
    readonly property real radiusCard: Appearance.rounding.verylarge
    readonly property real radiusFab: Appearance.rounding.large
    readonly property real radiusFabPressed: Appearance.rounding.normal
    readonly property real radiusKey: Appearance.rounding.full
    readonly property real radiusKeyPressed: Appearance.rounding.normal

    function pill(height) {
        return Math.min(height / 2, root.radiusFull);
    }

    // ── Shape ───────────────────────────────────────────────────────────
    // The shape a row's icon morphs into on focus, hover or "on": a relative of its idle
    // shape, so a state change reads as the same badge changing, not a spin.
    readonly property var morphs: ({
        [MaterialShape.Shape.Circle]: MaterialShape.Shape.Cookie4Sided,
        [MaterialShape.Shape.Cookie4Sided]: MaterialShape.Shape.Cookie6Sided,
        [MaterialShape.Shape.Cookie6Sided]: MaterialShape.Shape.Cookie9Sided,
        [MaterialShape.Shape.Cookie7Sided]: MaterialShape.Shape.Cookie12Sided,
        [MaterialShape.Shape.Cookie9Sided]: MaterialShape.Shape.Cookie12Sided,
        [MaterialShape.Shape.Cookie12Sided]: MaterialShape.Shape.Sunny,
        [MaterialShape.Shape.Sunny]: MaterialShape.Shape.VerySunny,
        [MaterialShape.Shape.VerySunny]: MaterialShape.Shape.Sunny,
        [MaterialShape.Shape.Clover4Leaf]: MaterialShape.Shape.Clover8Leaf,
        [MaterialShape.Shape.Clover8Leaf]: MaterialShape.Shape.Flower,
        [MaterialShape.Shape.Flower]: MaterialShape.Shape.Clover8Leaf,
        [MaterialShape.Shape.Burst]: MaterialShape.Shape.SoftBurst,
        [MaterialShape.Shape.SoftBurst]: MaterialShape.Shape.Burst,
        [MaterialShape.Shape.Boom]: MaterialShape.Shape.SoftBoom,
        [MaterialShape.Shape.SoftBoom]: MaterialShape.Shape.Boom,
        [MaterialShape.Shape.Puffy]: MaterialShape.Shape.PuffyDiamond,
        [MaterialShape.Shape.PuffyDiamond]: MaterialShape.Shape.Puffy
    })

    function morphOf(shape) {
        return root.morphs[shape] ?? MaterialShape.Shape.SoftBurst;
    }

    // ── Type ────────────────────────────────────────────────────────────
    readonly property string fontMain: Appearance.font.family.main
    readonly property string fontTitle: Appearance.font.family.title
    readonly property string fontNumbers: Appearance.font.family.numbers
    readonly property string fontExpressive: Appearance.font.family.expressive
    readonly property var axesDigits: ({ "wght": 560, "wdth": 30, "ROND": 100 })
    readonly property var axesDigitsBold: ({ "wght": 760, "wdth": 40, "ROND": 100 })
    readonly property var axesDisplay: ({ "wght": 460, "wdth": 100, "ROND": 100 })
    readonly property var axesTitle: Appearance.font.variableAxes.titleRounded
    readonly property int textSmall: Appearance.font.pixelSize.smaller
    readonly property int textNormal: Appearance.font.pixelSize.small
    readonly property int textLarge: Appearance.font.pixelSize.large
    readonly property int textTitle: Appearance.font.pixelSize.huge
    readonly property real iconSmall: Appearance.font.pixelSize.normal
    readonly property real iconNormal: Appearance.font.pixelSize.larger + 3
    readonly property real iconLarge: Appearance.font.pixelSize.huge + 6

    // ── Spacing (4 px grid) ─────────────────────────────────────────────
    readonly property int gapTiny: 4
    readonly property int gapSmall: 8
    readonly property int gap: 12
    readonly property int gapLarge: 16
    readonly property int gapHuge: 24
    readonly property int pagePadding: 16
    readonly property int pagePaddingWide: 24
    readonly property int cardPadding: 20

    // ── Sizes ───────────────────────────────────────────────────────────
    readonly property int iconButton: 40
    readonly property int fabSize: 64
    readonly property int fabSizeLarge: 88
    /// Room a scrolling page keeps free under its last row for the page FAB.
    readonly property int fabClearance: 88 + 16 * 2
    readonly property int navBarHeight: 76
    readonly property int topBarHeight: 64
    readonly property int chipHeight: 36
    readonly property int buttonHeight: 44
    readonly property int rowHeight: 52
    readonly property int paneGap: 12
    readonly property int panePadding: 10
    readonly property int railExpandedWidth: 228
    readonly property int railCollapsedWidth: 76
    readonly property int sheetWidth: 360
    readonly property int sheetWidthMin: 300
    readonly property int alarmCardMinWidth: 260
    readonly property int alarmCardMaxWidth: 300
    readonly property int eventCardWidth: 220
    readonly property int eventCardHeight: 92
    readonly property int worldCardMinWidth: 280
    readonly property int worldCardHeight: 112
    readonly property int worldHeroMaxWidth: 420
    readonly property int worldDialMin: 160
    readonly property int displayDigitMin: 48
    readonly property int displayDigitMax: 120
    readonly property int emptyShape: 136
    readonly property int emptyShapeSmall: 112
    readonly property int timerCardMinWidth: 440
    readonly property int keypadKeyMax: 84
    readonly property int keypadKeyMin: 44
    readonly property int sheetMaxWidth: 560
    readonly property int windowMinWidth: 360
    readonly property int windowMinHeight: 480

    // ── Breakpoints (window width) ──────────────────────────────────────
    readonly property int compactMax: 700
    readonly property int mediumMax: 900
    /// Below this the rail stays collapsed whatever was saved.
    readonly property int railExpandMin: 1100

    // ── Motion ──────────────────────────────────────────────────────────
    readonly property var motionFast: Appearance.animation.elementMoveFast
    readonly property var motionSpatial: Appearance.animation.elementMoveSmall
    readonly property var motionDefault: Appearance.animation.elementMove
    readonly property var motionEnter: Appearance.animation.elementMoveEnter
    readonly property var motionExit: Appearance.animation.elementMoveExit
    readonly property bool reducedMotion: Appearance.reducedMotion
    readonly property int staggerStep: 36
    readonly property real enterOffset: 24
}
