pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

/*
 * Resource Columns. Each picked metric is a pill that fills like a bar of the
 * Health "Steps" chart, its own shape riding the end of the fill and morphing
 * into a burst when the load runs hot. Bars keep one thickness - three of them
 * make a 1x1 card - so more metrics make a longer card, never fatter bars:
 * horizontal = columns growing up, vertical = rows growing right.
 */
AbstractBackgroundWidget {
    id: root

    configEntryName: "resource_columns"

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

    readonly property var options: Config.options?.background?.widgets?.resource_columns ?? ({})
    readonly property real contentScale: (root.options?.widgetSize ?? 100) / 100.0
    readonly property bool isHorizontal: (root.options?.orientation ?? "horizontal") === "horizontal"
    readonly property bool showLabels: root.options?.showLabels ?? true

    // -- Geometry (design units) --
    readonly property real cell: 240
    readonly property real cellGap: 12
    readonly property real padding: 12
    readonly property real barGap: 8
    readonly property real barThickness: (root.cell - root.padding * 2 - root.barGap * 2) / 3
    readonly property int count: metrics.items.length
    readonly property real mainLength: Math.max(root.cell, root.padding * 2 + root.count * root.barThickness + (root.count - 1) * root.barGap)
    readonly property real designWidth: root.isHorizontal ? root.mainLength : root.cell
    readonly property real designHeight: root.isHorizontal ? root.cell : root.mainLength
    readonly property real barLength: root.cell - root.padding * 2

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

        StyledRectangularShadow {
            target: card
            visible: Config.options.background.widgets.enableShadows ?? true
        }

        Rectangle {
            id: card
            anchors.fill: parent
            radius: Appearance.rounding.large
            color: WidgetColorScheme.tintBackground(WidgetColorScheme.cardBgColor)

            // Centred, so a single bar sits in the middle of its 1x1 card.
            Grid {
                anchors.centerIn: parent
                // Columns only: setting rows too trips a transient "more items than cells" while both change.
                columns: root.isHorizontal ? metrics.items.length : 1
                spacing: root.barGap

                Repeater {
                    model: metrics.items

                    delegate: ResourceBar {
                        required property string modelData
                        key: modelData
                        growsUp: root.isHorizontal
                        width: root.isHorizontal ? root.barThickness : root.barLength
                        height: root.isHorizontal ? root.barLength : root.barThickness
                    }
                }
            }
        }
    }

    component ResourceBar: Item {
        id: bar

        property string key
        property bool growsUp: true

        readonly property real length: bar.growsUp ? bar.height : bar.width
        readonly property real thickness: bar.growsUp ? bar.width : bar.height
        readonly property real value: metrics.value(bar.key)
        readonly property bool hot: metrics.isHot(bar.key)
        readonly property color colFill: bar.hot ? WidgetColorScheme.warningColor : WidgetColorScheme.accentColor
        readonly property real badgeSize: Math.min(bar.thickness - 16, 52)
        readonly property real inset: (bar.thickness - bar.badgeSize) / 2
        // The figure sits at the far end of the track, the fill rises towards it.
        readonly property real textExtent: bar.growsUp ? textBlock.height + 18 : textBlock.width + 22
        // How far the fill reaches along the bar, as drawn (animated).
        readonly property real fillExtent: bar.growsUp ? fillRect.height : fillRect.width
        readonly property bool textCovered: bar.fillExtent > bar.length - bar.textExtent + 6

        // Track
        Rectangle {
            anchors.fill: parent
            radius: Math.min(bar.thickness / 2, Appearance.rounding.full)
            color: WidgetColorScheme.pillBgColor
        }

        // Fill: the circle at the base is the badge's seat and reads as zero;
        // the value measures the stretch beyond it.
        Rectangle {
            id: fillRect
            readonly property real target: bar.thickness + (bar.length - bar.thickness) * bar.value
            x: 0
            y: bar.growsUp ? bar.height - height : 0
            width: bar.growsUp ? bar.width : target
            height: bar.growsUp ? target : bar.height
            radius: Math.min(bar.thickness / 2, Appearance.rounding.full)
            color: bar.colFill

            Behavior on width {
                enabled: !bar.growsUp
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }
            Behavior on height {
                enabled: bar.growsUp
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }

        // The metric's shape at the end of the fill; it stops short of the figure.
        MaterialShapeWrappedMaterialSymbol {
            readonly property real along: Math.min(bar.fillExtent - bar.inset - bar.badgeSize,
                                                   bar.length - bar.textExtent - bar.badgeSize - 6)
            x: bar.growsUp ? bar.inset : Math.max(bar.inset, along)
            y: bar.growsUp ? bar.height - bar.badgeSize - Math.max(bar.inset, along) : bar.inset
            implicitSize: bar.badgeSize
            padding: 0
            shape: bar.hot ? MaterialShape.Shape.SoftBurst : metrics.shape(bar.key)
            color: WidgetColorScheme.onAccentColor
            text: metrics.icon(bar.key)
            iconSize: Math.round(bar.badgeSize * 0.48)
            fill: 1
            colSymbol: bar.colFill
        }

        // Figure and label
        Column {
            id: textBlock
            x: bar.growsUp ? (bar.width - width) / 2 : bar.width - width - 18
            y: bar.growsUp ? 14 : (bar.height - height) / 2
            spacing: 0

            Row {
                x: bar.growsUp ? (parent.width - width) / 2 : parent.width - width

                Text {
                    id: figureText
                    text: metrics.figure(bar.key)
                    color: bar.textCovered ? WidgetColorScheme.onAccentColor : WidgetColorScheme.textColorOnBg
                    font.family: Appearance.font.family.main
                    font.pixelSize: 40
                    font.variableAxes: ({ "wght": 760, "wdth": 30, "ROND": 100 })
                    renderType: Text.QtRendering
                }
                Text {
                    anchors.baseline: figureText.baseline
                    text: metrics.unit(bar.key)
                    color: bar.textCovered ? WidgetColorScheme.onAccentColor : WidgetColorScheme.subtextColorOnBg
                    font.family: Appearance.font.family.main
                    font.pixelSize: 15
                    font.variableAxes: ({ "wght": 600, "wdth": 70, "ROND": 100 })
                    renderType: Text.QtRendering
                }
            }

            StyledText {
                visible: root.showLabels
                x: bar.growsUp ? (parent.width - width) / 2 : parent.width - width
                width: Math.min(implicitWidth, bar.growsUp ? bar.thickness - 8 : bar.length * 0.5)
                horizontalAlignment: bar.growsUp ? Text.AlignHCenter : Text.AlignRight
                text: metrics.label(bar.key).toUpperCase()
                color: bar.textCovered ? WidgetColorScheme.onAccentColor : WidgetColorScheme.subtextColorOnBg
                font.family: Appearance.font.family.monospace
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.letterSpacing: 1
                elide: Text.ElideRight
            }
        }
    }
}
