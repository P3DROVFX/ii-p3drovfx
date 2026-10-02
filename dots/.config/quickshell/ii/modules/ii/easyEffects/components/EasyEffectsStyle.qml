pragma Singleton

import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * Every colour, radius, size and motion token of the EasyEffects app.
 *
 * Mapped onto `Appearance`, the way the clock's style is (see docs/design/material3-expressive.md
 * §1). The numbers that remain are layout measurements the app owns: card and row sizes
 * and the breakpoints that decide how many columns a page gets.
 */
Singleton {
    id: root

    // ── Surfaces ────────────────────────────────────────────────────────
    readonly property color colBackground: Appearance.colors.colLayer0
    readonly property color colOnBackground: Appearance.colors.colOnLayer0
    /// A pane: the rail, the effects header, a device column.
    readonly property color colPane: Appearance.colors.colLayer1
    readonly property color colPaneHover: Appearance.colors.colLayer1Hover
    /// A row or card sitting on the window (or in a pane): one step above the pane.
    readonly property color colRow: Appearance.colors.colLayer2
    readonly property color colRowHover: Appearance.colors.colLayer2Hover
    /// The side sheet and the rows inside it.
    readonly property color colSheet: Appearance.m3colors.m3surfaceContainerHigh
    readonly property color colField: Appearance.m3colors.m3surfaceContainerHighest
    readonly property color colFieldHover: Appearance.colors.colSurfaceContainerHighestHover
    readonly property color colOnSurface: Appearance.colors.colOnSurface
    readonly property color colOnSurfaceVariant: Appearance.colors.colOnSurfaceVariant
    readonly property color colSubtext: Appearance.colors.colSubtext
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
    readonly property color colOnTertiaryContainer: Appearance.colors.colOnTertiaryContainer
    readonly property color colError: Appearance.colors.colError
    readonly property color colErrorContainer: Appearance.colors.colErrorContainer
    readonly property color colOnErrorContainer: Appearance.colors.colOnErrorContainer

    // Tints: a small action on a card is the card's own content colour, faint (docs §2.3).
    readonly property real tintIdle: 0.08
    readonly property real tintHover: 0.16
    readonly property real tintPressed: 0.24
    /// The pills on a filled hero or card.
    readonly property real tintPill: 0.18
    /// A dimmed (switched-off or absent) row.
    readonly property real dimmed: 0.62
    /// The quieter text on a filled container: its content colour, a little thinner.
    readonly property real tintSubtext: 0.8
    /// The big shapes behind a hero and a banner.
    readonly property real tintShape: 0.15
    readonly property real opacityOrnament: 0.1
    readonly property real opacityWave: 0.55
    readonly property real opacityCurve: 0.75
    readonly property real opacityCurveActive: 0.9
    readonly property real opacityIndex: 0.7
    readonly property real opacityDisabled: 0.35
    readonly property real opacityBannerText: 0.86
    /// The dashes of an unchosen chip and the level lines of a curve.
    readonly property real tintDash: 0.8
    readonly property real tintGrid: 0.5
    readonly property real letterSpacingCaption: 0.2

    function tint(color, amount) {
        return ColorUtils.applyAlpha(color, amount);
    }

    // ── Shape ───────────────────────────────────────────────────────────
    readonly property real radiusPane: Appearance.rounding.verylarge
    readonly property real radiusCard: Appearance.rounding.verylarge
    readonly property real radiusRow: Appearance.rounding.large
    readonly property real radiusField: Appearance.rounding.small
    readonly property real radiusChip: Appearance.rounding.normal
    readonly property real radiusJoin: Appearance.rounding.verysmall
    readonly property real radiusFull: Appearance.rounding.full
    readonly property real radiusFab: Appearance.rounding.large
    readonly property real radiusFabPressed: Appearance.rounding.normal

    function pill(height) {
        return Math.min(height / 2, root.radiusFull);
    }

    /// The shape a preset's or effect's badge is drawn in: one per name, stable, so a
    /// grid reads as a set of different things and not a row of identical dots.
    readonly property var badgeShapes: [
        MaterialShape.Shape.Cookie9Sided,
        MaterialShape.Shape.SoftBurst,
        MaterialShape.Shape.Clover4Leaf,
        MaterialShape.Shape.Cookie12Sided,
        MaterialShape.Shape.Sunny,
        MaterialShape.Shape.Cookie7Sided,
        MaterialShape.Shape.Flower,
        MaterialShape.Shape.Puffy
    ]

    /// The shape a badge morphs into while its row is on: a relative of its idle shape.
    readonly property var morphs: ({
        [MaterialShape.Shape.Cookie9Sided]: MaterialShape.Shape.Cookie12Sided,
        [MaterialShape.Shape.Cookie12Sided]: MaterialShape.Shape.Sunny,
        [MaterialShape.Shape.Cookie7Sided]: MaterialShape.Shape.Cookie12Sided,
        [MaterialShape.Shape.Sunny]: MaterialShape.Shape.VerySunny,
        [MaterialShape.Shape.Clover4Leaf]: MaterialShape.Shape.Clover8Leaf,
        [MaterialShape.Shape.SoftBurst]: MaterialShape.Shape.Burst,
        [MaterialShape.Shape.Flower]: MaterialShape.Shape.Clover8Leaf,
        [MaterialShape.Shape.Puffy]: MaterialShape.Shape.PuffyDiamond
    })

    function morphOf(shape) {
        return root.morphs[shape] ?? MaterialShape.Shape.SoftBurst;
    }

    function shapeFor(key) {
        const text = String(key ?? "");
        let hash = 0;
        for (let i = 0; i < text.length; i++)
            hash = (hash * 31 + text.charCodeAt(i)) % 9973;
        return root.badgeShapes[hash % root.badgeShapes.length];
    }

    // ── Type ────────────────────────────────────────────────────────────
    readonly property string fontMain: Appearance.font.family.main
    readonly property string fontTitle: Appearance.font.family.title
    readonly property string fontNumbers: Appearance.font.family.numbers
    readonly property var axesTitle: Appearance.font.variableAxes.titleRounded
    /// The one big word on a screen: tall, bold, rounded.
    readonly property var axesDisplay: ({ "wght": 760, "wdth": 100, "ROND": 100 })
    /// A device or effect name beside a quiet caption: heavier than the body, still wide.
    readonly property var axesName: ({ "wght": 650, "wdth": 100, "ROND": 100 })
    /// A small caps label over a value.
    readonly property var axesCaption: ({ "wght": 720, "wdth": 100, "ROND": 100 })
    readonly property int textCaption: Appearance.font.pixelSize.smaller
    readonly property int textSmall: Appearance.font.pixelSize.smallie
    readonly property int textNormal: Appearance.font.pixelSize.small
    readonly property int textBody: Appearance.font.pixelSize.normal
    readonly property int textName: Appearance.font.pixelSize.larger
    readonly property int textHeading: Appearance.font.pixelSize.huge + 2
    readonly property int textCardTitle: Appearance.font.pixelSize.huge
    readonly property int textBanner: Appearance.font.pixelSize.huge + 10
    readonly property int textHero: Appearance.font.pixelSize.huge * 2 + 8
    readonly property real iconSmall: Appearance.font.pixelSize.normal + 2
    readonly property real iconNormal: Appearance.font.pixelSize.larger + 3
    readonly property real iconLarge: Appearance.font.pixelSize.huge + 6

    // ── Spacing (4 px grid) ─────────────────────────────────────────────
    readonly property int gapTiny: 4
    readonly property int gapSmall: 8
    readonly property int gap: 12
    readonly property int gapLarge: 16
    readonly property int gapHuge: 24
    readonly property int panePadding: 20
    readonly property int heroPadding: 24
    readonly property int cardPadding: 18

    // ── Sizes ───────────────────────────────────────────────────────────
    readonly property int railRowHeight: 60
    readonly property int iconButton: 44
    readonly property int buttonHeight: 44
    readonly property int heroButtonHeight: 52
    readonly property int chipHeight: 44
    readonly property int pillHeight: 32
    readonly property int pillHeightLarge: 36
    readonly property int fabSize: 88
    readonly property int fabIcon: 34
    readonly property int fabSizeCompact: 64
    readonly property int fabClearance: 88 + 16 * 2
    readonly property int presetCardMinWidth: 252
    readonly property int presetCardHeight: 190
    readonly property int presetBadge: 56
    readonly property int heroWidth: 400
    readonly property int heroWidthMin: 320
    readonly property int heroShape: 232
    readonly property int heroShapeCore: 144
    readonly property int effectRowHeight: 68
    readonly property int effectBadge: 48
    readonly property int headerHeight: 92
    readonly property int responseHeight: 156
    readonly property int sheetWidth: 400
    readonly property int sheetWidthMin: 320
    readonly property int sheetBadge: 48
    readonly property int controlBadge: 36
    readonly property int fieldBadge: 40
    readonly property int bannerHeight: 132
    readonly property int deviceRowHeight: 92
    readonly property int deviceBadge: 56
    readonly property int deviceColumnBadge: 52
    readonly property int deviceSelectMinWidth: 180
    readonly property int bandSliderHeight: 150
    readonly property int bandSliderWidth: 26
    readonly property int tabCountBadge: 22
    readonly property int valueFieldWidth: 76
    readonly property int bandColumnMin: 30

    // ── Breakpoints (page width, after the rail and any sheet) ──────────
    /// Below this the hero folds into a strip above the grid.
    readonly property int heroSideMin: 860
    /// Below this the page is one stacked column.
    readonly property int stackedMax: 620
    /// The least a device pane needs to keep its name and its preset choice side by side.
    readonly property int devicePaneMin: 470
    /// Below this the Devices banner drops its row of device badges.
    readonly property int bannerClusterMin: 1000

    // ── Motion ──────────────────────────────────────────────────────────
    readonly property var motionFast: Appearance.animation.elementMoveFast
    readonly property var motionSpatial: Appearance.animation.elementMoveSmall
    readonly property var motionDefault: Appearance.animation.elementMove
    readonly property bool reducedMotion: Appearance.reducedMotion
}
