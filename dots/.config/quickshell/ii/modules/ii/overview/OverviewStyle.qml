pragma Singleton

import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.functions

/**
 * Every colour, radius, size and motion token of the workspace grid.
 *
 * The cells, the window cards and their app chips read from here only, so the
 * whole overview changes from this file. Chip colours are opaque m3 roles: the
 * layer colours carry the content transparency and would let the window
 * picture bleed through the label.
 */
Singleton {
    id: root

    /** Which card design the grid draws: the app-chip "recents" one, or the classic one. */
    readonly property bool recents: Config.options.overview.cardDesign === "recents"

    // ── Classic design ──────────────────────────────────────────────────
    readonly property color classicColActiveOutline: Appearance.colors.colSecondary
    readonly property real classicActiveOutlineWidth: 2
    readonly property color classicColDropTint: ColorUtils.transparentize(Appearance.colors.colLayer1Hover, 0.9)
    readonly property color classicColDropOutline: Appearance.colors.colLayer2Hover
    readonly property color classicColOnCell: ColorUtils.transparentize(Appearance.colors.colOnLayer1, 0.8)
    readonly property string classicNumberFamily: Appearance.font.family.numbers
    readonly property real classicNumberRatio: 0.36
    readonly property color classicColWindowHover: ColorUtils.transparentize(Appearance.colors.colLayer2Hover, 0.7)
    readonly property color classicColWindowPressed: ColorUtils.transparentize(Appearance.colors.colLayer2Active, 0.5)
    readonly property color classicColScrollingFallback: Appearance.m3colors.m3surfaceContainerLowest
    readonly property real classicIconGapRatio: 0.06
    readonly property real classicIconRatioCentered: 0.35
    readonly property real classicIconRatioCorner: 0.15
    readonly property real classicIconRatioCompact: 0.6

    // ── Panel and cells ─────────────────────────────────────────────────
    readonly property color colPanel: Appearance.colors.colBackgroundSurfaceContainer
    readonly property color colCell: Appearance.colors.colSurfaceContainerLow
    readonly property color colCellHover: ColorUtils.mix(Appearance.colors.colSurfaceContainerLow, Appearance.colors.colSurfaceContainerHighest, 0.45)
    readonly property color colCellActive: Appearance.colors.colPrimaryContainer
    readonly property color colOnCell: ColorUtils.transparentize(Appearance.colors.colOnLayer1, 0.78)
    readonly property color colOnCellHover: ColorUtils.transparentize(Appearance.colors.colOnLayer1, 0.45)
    readonly property color colOnCellActive: Appearance.colors.colOnPrimaryContainer
    readonly property color colDropTarget: ColorUtils.transparentize(Appearance.m3colors.m3secondaryContainer, 0.18)
    readonly property color colOnDropTarget: Appearance.m3colors.m3onSecondaryContainer
    readonly property color colSwapTarget: ColorUtils.transparentize(Appearance.m3colors.m3tertiaryContainer, 0.22)
    readonly property color colSwapShape: Appearance.m3colors.m3tertiary
    readonly property color colOnSwapShape: Appearance.m3colors.m3onTertiary
    readonly property color colDim: Appearance.m3colors.m3surfaceContainerLowest
    readonly property color colWindowFallback: Appearance.m3colors.m3surfaceContainerHigh
    readonly property color colFlash: Appearance.m3colors.m3inverseSurface

    readonly property real panelPadding: 10
    readonly property real cellSpacing: 10
    readonly property real radiusCellOuter: Appearance.rounding.large
    readonly property real radiusCellJoin: Appearance.rounding.verysmall
    readonly property real radiusCellActive: Appearance.rounding.large
    readonly property real radiusWindowMin: Appearance.rounding.small
    readonly property real radiusDropShape: Appearance.rounding.normal

    // ── Window cards ────────────────────────────────────────────────────
    /** Windows away from the current workspace sit back by this much. */
    readonly property real dimOpacity: 0.32
    readonly property real otherMonitorOpacity: 0.4
    readonly property real flashOpacity: 0.55
    readonly property real pressScale: 0.97
    readonly property real shadowBlur: 14
    readonly property real shadowBlurRaised: 30
    readonly property real shadowOpacity: 0.26
    readonly property real shadowOpacityRaised: 0.5
    readonly property real shadowOffset: 3
    readonly property real shadowOffsetRaised: 8
    /** The centred icon stands in for a picture that has not arrived. */
    readonly property real fallbackIconRatio: 0.3

    // ── App chip ────────────────────────────────────────────────────────
    readonly property color colChip: Appearance.m3colors.m3surfaceContainerHighest
    readonly property color colOnChip: Appearance.m3colors.m3onSurface
    readonly property color colChipHovered: Appearance.m3colors.m3secondaryContainer
    readonly property color colOnChipHovered: Appearance.m3colors.m3onSecondaryContainer
    readonly property color colChipFocused: Appearance.m3colors.m3primary
    readonly property color colOnChipFocused: Appearance.m3colors.m3onPrimary
    readonly property real chipBadgeTint: 0.1

    readonly property real chipHeight: 30
    readonly property real chipHeightCompact: 24
    readonly property real chipInset: 6
    readonly property real chipInsetCompact: 4
    readonly property real chipPaddingEnd: 6
    readonly property real chipSpacing: 6
    readonly property real chipIconBadge: 22
    readonly property real chipIconBadgeCompact: 18
    readonly property real chipIconSize: 16
    readonly property real chipIconSizeCompact: 14
    readonly property real chipChevronSize: 18
    readonly property real chipChevronSizeCompact: 16
    /** A name narrower than this is dropped instead of eliding into a stub. */
    readonly property real chipMinNameWidth: 34
    readonly property real chipMaxNameWidth: 132
    readonly property int chipNameSize: Appearance.font.pixelSize.smaller
    readonly property var chipNameAxes: ({ "wght": 640, "wdth": 88, "ROND": 100 })
    /** Below either size a card shows its centred icon and no chip. */
    readonly property real chipMinCardWidth: 56
    readonly property real chipMinCardHeight: 40
    readonly property real chipCompactCardWidth: 160
    readonly property int actionDoneDuration: 1100

    // ── Window menu (opens from the chip) ───────────────────────────────
    readonly property color colMenuContainer: Appearance.m3colors.m3surfaceContainer
    readonly property color colMenu: Appearance.m3colors.m3surfaceContainerHighest
    readonly property color colOnMenu: Appearance.m3colors.m3onSurface
    readonly property color colMenuItemHover: Appearance.m3colors.m3secondaryContainer
    readonly property color colOnMenuItemHover: Appearance.m3colors.m3onSecondaryContainer
    readonly property color colMenuItemActive: Appearance.colors.colSecondaryContainerHover
    readonly property color colMenuToggled: Appearance.m3colors.m3primary
    readonly property color colOnMenuToggled: Appearance.m3colors.m3onPrimary
    readonly property color colMenuDanger: Appearance.m3colors.m3error
    readonly property color colMenuDangerHover: Appearance.m3colors.m3errorContainer
    readonly property color colOnMenuDangerHover: Appearance.m3colors.m3onErrorContainer
    readonly property color colMenuDangerActive: Appearance.colors.colErrorContainerHover
    readonly property real menuWidth: 204
    readonly property real menuGap: 8
    readonly property real menuSectionGap: 8
    readonly property real menuPadding: 6
    readonly property real menuGroupGap: 4
    readonly property real menuItemHeight: 42
    /** Rows round with `rounding.normal`; the group's corners stay concentric around them. */
    readonly property real menuItemRadiusOuter: Appearance.rounding.normal
    readonly property real menuRadiusJoin: Appearance.rounding.verysmall
    readonly property real menuRadiusOuter: root.menuItemRadiusOuter + root.menuPadding
    readonly property real menuItemPadding: 14
    readonly property real menuItemSpacing: 12
    readonly property real menuIconSize: 20
    readonly property real menuToggleSize: 24
    readonly property real menuToggleIconSize: 16
    readonly property int menuLabelSize: Appearance.font.pixelSize.small
    readonly property var menuLabelAxes: ({ "wght": 520, "wdth": 100, "ROND": 100 })
    readonly property var menuLabelAxesHover: ({ "wght": 640, "wdth": 100, "ROND": 100 })
    readonly property real menuSlide: 10
    /** The pointer may leave the card and its menu for this long before it closes. */
    readonly property int menuCloseDelay: 450

    function radiusFor(size) {
        return Appearance.rounding.scale === 0 ? 0 : size / 2;
    }
    /** A menu row in a group: outer corners large, joins small, a full pill under the pointer. */
    function menuItemRadius(height, first, last, top, active) {
        if (Appearance.rounding.scale === 0)
            return 0;
        if (active)
            return height / 2;
        return (top ? first : last) ? Math.min(root.menuItemRadiusOuter, height / 2) : root.menuRadiusJoin;
    }

    // ── Workspace numbers ───────────────────────────────────────────────
    readonly property string numberFamily: Appearance.font.family.main
    readonly property real numberRatio: 0.42
    readonly property real numberWeightIdle: 520
    readonly property real numberWeightBold: 780
    readonly property real numberWidthIdle: 34
    readonly property real numberWidthBold: 46
    function numberAxes(boldness) {
        return {
            "wght": Math.round(root.numberWeightIdle + (root.numberWeightBold - root.numberWeightIdle) * boldness),
            "wdth": Math.round(root.numberWidthIdle + (root.numberWidthBold - root.numberWidthIdle) * boldness),
            "ROND": 100
        };
    }

    // ── Motion ──────────────────────────────────────────────────────────
    readonly property var motionFast: Appearance.animation.elementMoveFast
    readonly property var motionMove: Appearance.animation.elementMove
    readonly property var motionSmall: Appearance.animation.elementMoveSmall
    readonly property var motionEnter: Appearance.animation.elementMoveEnter
    readonly property var motionResize: Appearance.animation.elementResize
}
