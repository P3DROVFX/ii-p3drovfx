pragma Singleton

import QtQuick
import Quickshell
import qs.modules.common

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

    // Per-tab accent pairs: an enabled alarm, a running timer, a focus phase, a break.
    readonly property color colActiveCard: root.colTertiaryContainer
    readonly property color colOnActiveCard: root.colOnTertiaryContainer
    readonly property color colIdleCard: root.colSurfaceHigh
    readonly property color colOnIdleCard: root.colSubtext
    readonly property color colFocus: root.colPrimary
    readonly property color colBreak: root.colTertiary

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
    readonly property int navBarHeight: 76
    readonly property int navRailWidth: 96
    readonly property int navIndicatorWidth: 56
    readonly property int navIndicatorHeight: 32
    readonly property int topBarHeight: 64
    readonly property int chipHeight: 36
    readonly property int alarmCardMinWidth: 172
    readonly property int alarmCardHeight: 212
    readonly property int alarmCardHeightStacked: 244
    readonly property int alarmDigitMin: 40
    readonly property int eventCardWidth: 220
    readonly property int eventCardHeight: 104
    readonly property int worldCardMinWidth: 300
    readonly property int worldCardHeight: 96
    readonly property int worldHeroMaxWidth: 460
    readonly property int worldDialMin: 160
    readonly property int displayDigitMin: 48
    readonly property int displayDigitMax: 120
    readonly property int emptyShape: 136
    readonly property int emptyShapeSmall: 112
    readonly property int timerCardMinWidth: 280
    readonly property int keypadKeyMax: 84
    readonly property int keypadKeyMin: 48
    readonly property int sheetMaxWidth: 560
    readonly property int sheetHandleWidth: 32
    readonly property int sheetHandleHeight: 4
    readonly property int buttonHeight: 44
    readonly property int windowMinWidth: 360
    readonly property int windowMinHeight: 480

    // ── Breakpoints (window width) ──────────────────────────────────────
    readonly property int compactMax: 600
    readonly property int mediumMax: 900

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
