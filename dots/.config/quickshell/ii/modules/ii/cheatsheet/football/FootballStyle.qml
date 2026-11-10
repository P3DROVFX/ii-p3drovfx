pragma Singleton

import QtQuick
import Quickshell
import qs.modules.common

/**
 * Tokens of the Football overview, mapped onto Appearance like the Clock's
 * ClockStyle. The numbers left are layout measurements the page owns.
 */
Singleton {
    id: root

    // ── Surfaces ────────────────────────────────────────────────────────
    readonly property color colPane: Appearance.colors.colLayer1
    readonly property color colOnPane: Appearance.colors.colOnLayer1
    readonly property color colRow: Appearance.colors.colLayer2
    readonly property color colRowHover: Appearance.colors.colLayer2Hover
    readonly property color colRowActive: Appearance.colors.colLayer2Active
    readonly property color colField: Appearance.m3colors.m3surfaceContainerHighest
    readonly property color colFieldHover: Appearance.colors.colSurfaceContainerHighestHover
    readonly property color colOnSurface: Appearance.colors.colOnSurface
    readonly property color colOnSurfaceVariant: Appearance.colors.colOnSurfaceVariant
    readonly property color colSubtext: Appearance.colors.colSubtext
    readonly property color colOutline: Appearance.m3colors.m3outlineVariant

    // ── Accents ─────────────────────────────────────────────────────────
    readonly property color colPrimary: Appearance.colors.colPrimary
    readonly property color colPrimaryHover: Appearance.colors.colPrimaryHover
    readonly property color colPrimaryActive: Appearance.colors.colPrimaryActive
    readonly property color colOnPrimary: Appearance.colors.colOnPrimary
    readonly property color colPrimaryContainer: Appearance.colors.colPrimaryContainer
    readonly property color colPrimaryContainerHover: Appearance.colors.colPrimaryContainerHover
    readonly property color colOnPrimaryContainer: Appearance.colors.colOnPrimaryContainer
    readonly property color colSecondaryContainer: Appearance.colors.colSecondaryContainer
    readonly property color colSecondaryContainerHover: Appearance.colors.colSecondaryContainerHover
    readonly property color colSecondaryContainerActive: Appearance.colors.colSecondaryContainerActive
    readonly property color colOnSecondaryContainer: Appearance.colors.colOnSecondaryContainer
    readonly property color colTertiary: Appearance.colors.colTertiary
    readonly property color colOnTertiary: Appearance.colors.colOnTertiary
    readonly property color colTertiaryContainer: Appearance.colors.colTertiaryContainer
    readonly property color colOnTertiaryContainer: Appearance.colors.colOnTertiaryContainer
    readonly property color colErrorContainer: Appearance.colors.colErrorContainer
    readonly property color colOnErrorContainer: Appearance.colors.colOnErrorContainer

    // Bookings are the one place a fixed colour carries meaning.
    readonly property color colYellowCard: "#f6c915"
    readonly property color colRedCard: "#d32f2f"

    // ── Shape ───────────────────────────────────────────────────────────
    readonly property real radiusSmall: Appearance.rounding.small
    readonly property real radiusNormal: Appearance.rounding.normal
    readonly property real radiusLarge: Appearance.rounding.large
    readonly property real radiusCard: Appearance.rounding.verylarge
    readonly property real radiusFull: Appearance.rounding.full
    readonly property real radiusJoin: Appearance.rounding.verysmall

    // ── Type ────────────────────────────────────────────────────────────
    readonly property string fontMain: Appearance.font.family.main
    readonly property string fontTitle: Appearance.font.family.title
    readonly property var axesTitle: Appearance.font.variableAxes.titleRounded
    readonly property var axesScore: ({ "wght": 850, "wdth": 45, "ROND": 100 })
    readonly property var axesScoreIdle: ({ "wght": 560, "wdth": 30, "ROND": 100 })
    readonly property var axesCondensed: ({ "wght": 650, "wdth": 75, "ROND": 100 })
    readonly property var axesItalic: ({ "wght": 800, "wdth": 110, "slnt": -10, "ROND": 0 })
    // Broadcast voice: the score in tall heavy digits, the loser's in a light
    // cut of the same face; club names in a slanted condensed headline; small
    // captions wide and heavy in capitals.
    readonly property var axesScoreHeavy: ({ "wght": 1000, "wdth": 50, "ROND": 100 })
    readonly property var axesScoreLight: ({ "wght": 560, "wdth": 50, "ROND": 100 })
    readonly property var axesHeadline: ({ "wght": 850, "wdth": 75, "slnt": -10, "ROND": 0 })
    readonly property var axesCaps: ({ "wght": 800, "wdth": 120, "ROND": 0 })
    readonly property var axesPaneTitle: ({ "wght": 900, "wdth": 60, "slnt": -8, "ROND": 0 })
    readonly property int textSmallest: Appearance.font.pixelSize.smallest
    readonly property int textSmaller: Appearance.font.pixelSize.smaller
    readonly property int textSmall: Appearance.font.pixelSize.small
    readonly property int textNormal: Appearance.font.pixelSize.normal
    readonly property int textLarge: Appearance.font.pixelSize.large
    readonly property int textLarger: Appearance.font.pixelSize.larger
    readonly property int textHuge: Appearance.font.pixelSize.huge

    // ── Layout ──────────────────────────────────────────────────────────
    readonly property int gapTiny: 4
    readonly property int gapSmall: 8
    readonly property int gap: 12
    readonly property int gapLarge: 16
    readonly property int gapHuge: 24
    readonly property int panePadding: 16
    readonly property int rowHeight: 64
    readonly property int compactRowHeight: 52
    readonly property int chipHeight: 36
    readonly property int railWidth: 76
    readonly property int listPaneWidth: 384
    readonly property int listPaneWidthWide: 420

    // ── Motion ──────────────────────────────────────────────────────────
    readonly property var motionFast: Appearance.animation.elementMoveFast
    readonly property var motionDefault: Appearance.animation.elementMove
    readonly property var motionEnter: Appearance.animation.elementMoveEnter
    readonly property bool reducedMotion: Appearance.reducedMotion ?? false
}
