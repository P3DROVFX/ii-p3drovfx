pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Widgets
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

/*
 * Resource Tiles. One 1x1 tile per picked metric, in a row or a column: the
 * figure in tall condensed digits, a badge whose shape follows the load (calm
 * circle, busy cookie, hot burst), the metric's own shape as a large clipped
 * ornament, and a still wavy line with the detail over it.
 */
AbstractBackgroundWidget {
    id: root

    configEntryName: "resource_tiles"

    visibleWhenLocked: root.lockBehavior === "keep" || root.lockBehavior === "custom"
                    || root.lockBehavior === "center"
                    || root.lockBehavior === "lockOnly"

    opacity: {
        if (root.lockBehavior === "lockOnly")
            return GlobalStates.screenLocked ? 1 : 0;
        if (GlobalStates.screenLocked && !visibleWhenLocked)
            return 0;
        return 1;
    }

    readonly property var options: Config.options?.background?.widgets?.resource_tiles ?? ({})
    readonly property real contentScale: (root.options?.widgetSize ?? 100) / 100.0
    readonly property bool isHorizontal: (root.options?.orientation ?? "horizontal") === "horizontal"
    readonly property bool showOrnament: root.options?.showOrnament ?? true
    readonly property bool showDetail: root.options?.showDetail ?? true

    // -- Geometry (design units) --
    readonly property real cell: 240
    readonly property real cellGap: 12
    readonly property real padding: 18
    readonly property real badgeSize: 46
    readonly property real ornamentSize: 300
    readonly property real figureSize: 108
    readonly property int count: metrics.items.length
    readonly property real mainLength: root.count * root.cell + (root.count - 1) * root.cellGap
    readonly property real designWidth: root.isHorizontal ? root.mainLength : root.cell
    readonly property real designHeight: root.isHorizontal ? root.cell : root.mainLength

    implicitWidth: root.designWidth * root.contentScale
    implicitHeight: root.designHeight * root.contentScale

    ResourceMetricSource {
        id: metrics
        keys: root.options?.items ?? ["cpu", "ram", "disk"]
        active: root.visible
    }

    Item {
        anchors.centerIn: parent
        width: root.designWidth
        height: root.designHeight
        scale: root.contentScale

        Grid {
            anchors.fill: parent
            // Columns only: setting rows too trips a transient "more items than cells" while both change.
            columns: root.isHorizontal ? root.count : 1
            spacing: root.cellGap

            Repeater {
                model: metrics.items

                delegate: ResourceTile {
                    required property string modelData
                    key: modelData
                    width: root.cell
                    height: root.cell
                }
            }
        }
    }

    component ResourceTile: Item {
        id: tile

        property string key

        readonly property real value: metrics.value(tile.key)
        readonly property bool hot: metrics.isHot(tile.key)
        readonly property color colAccent: tile.hot ? WidgetColorScheme.warningColor : WidgetColorScheme.accentColor
        // Shape is state: calm, busy, hot.
        readonly property var loadShape: tile.hot ? MaterialShape.Shape.SoftBurst
            : (tile.value >= 0.5 ? MaterialShape.Shape.Cookie9Sided : MaterialShape.Shape.Circle)

        StyledRectangularShadow {
            target: tileCard
            visible: Config.options.background.widgets.enableShadows ?? true
        }

        ClippingRectangle {
            id: tileCard
            anchors.fill: parent
            radius: Appearance.rounding.large
            color: WidgetColorScheme.tintBackground(WidgetColorScheme.cardBgColor)

            // Ornament: the metric's own shape, big and clipped by the tile.
            MaterialShape {
                visible: root.showOrnament
                x: tileCard.width - root.ornamentSize * 0.62
                y: tileCard.height - root.ornamentSize * 0.66
                implicitSize: root.ornamentSize
                shape: metrics.shape(tile.key)
                color: tile.colAccent
                opacity: 0.1
            }

            MaterialShapeWrappedMaterialSymbol {
                x: root.padding
                y: root.padding
                implicitSize: root.badgeSize
                padding: 0
                shape: tile.loadShape
                color: tile.hot ? WidgetColorScheme.warningColor : WidgetColorScheme.pillFillColor
                text: metrics.icon(tile.key)
                iconSize: 22
                fill: 1
                colSymbol: tile.hot ? WidgetColorScheme.cardBgColor : WidgetColorScheme.textColorOnPillFill
            }

            StyledText {
                anchors.right: parent.right
                anchors.rightMargin: root.padding + 2
                y: root.padding + (root.badgeSize - height) / 2
                width: Math.min(implicitWidth, tileCard.width - root.badgeSize - root.padding * 3)
                horizontalAlignment: Text.AlignRight
                text: metrics.label(tile.key).toUpperCase()
                color: WidgetColorScheme.subtextColorOnBg
                font.family: Appearance.font.family.monospace
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.letterSpacing: 1.5
                elide: Text.ElideRight
            }

            // The figure
            Row {
                x: root.padding - 4
                anchors.bottom: detailText.top
                anchors.bottomMargin: -6

                Text {
                    id: figureText
                    text: metrics.figure(tile.key)
                    color: tile.hot ? WidgetColorScheme.warningColor : WidgetColorScheme.textColorOnBg
                    font.family: Appearance.font.family.main
                    font.pixelSize: root.figureSize
                    font.variableAxes: ({ "wght": 760, "wdth": 32, "ROND": 100 })
                    renderType: Text.QtRendering

                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                }
                Text {
                    anchors.baseline: figureText.baseline
                    text: metrics.unit(tile.key)
                    color: WidgetColorScheme.subtextColorOnBg
                    font.family: Appearance.font.family.main
                    font.pixelSize: 30
                    font.variableAxes: ({ "wght": 600, "wdth": 60, "ROND": 100 })
                    renderType: Text.QtRendering
                }
            }

            StyledText {
                id: detailText
                anchors.left: parent.left
                anchors.leftMargin: root.padding
                anchors.right: parent.right
                anchors.rightMargin: root.padding
                anchors.bottom: line.top
                anchors.bottomMargin: 8
                height: root.showDetail ? implicitHeight : 0
                visible: root.showDetail
                text: metrics.detail(tile.key)
                color: WidgetColorScheme.subtextColorOnBg
                font.pixelSize: Appearance.font.pixelSize.small
                elide: Text.ElideRight
            }

            StyledProgressBar {
                id: line
                anchors.left: parent.left
                anchors.leftMargin: root.padding
                anchors.right: parent.right
                anchors.rightMargin: root.padding
                anchors.bottom: parent.bottom
                anchors.bottomMargin: root.padding + 2
                wavy: true
                animateWave: false
                highlightColor: tile.colAccent
                trackColor: WidgetColorScheme.pillBgColor
                value: tile.value
            }
        }
    }
}
