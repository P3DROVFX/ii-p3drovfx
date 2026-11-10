pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar.shared

/**
 * The expressive colour themes as swatches painted from the bar's own theme table
 * (`BarThemes`): the bar's fill, a widget plate on it and the highlight dot. Shape is the
 * state — a circle at rest, a rounded square when chosen — and the chosen name turns
 * primary. One row; the swatches shrink before the row wraps.
 *
 * options: [{ value, label }]
 */
Item {
    id: root

    readonly property real maxSwatch: 64
    readonly property real minSwatch: 44
    readonly property real labelGap: 6

    property var options: []
    property string currentValue: "content"
    signal selected(string value)

    readonly property real cell: width / Math.max(1, root.options.length)
    readonly property real swatch: Math.max(root.minSwatch, Math.min(root.maxSwatch, root.cell - 24))

    implicitHeight: root.swatch + root.labelGap + 18

    BarThemes {
        id: themes
    }

    Repeater {
        model: root.options

        delegate: Item {
            id: item
            required property var modelData
            required property int index
            readonly property var theme: themes.getTheme(item.modelData.value)
            readonly property bool chosen: item.modelData.value === root.currentValue

            x: item.index * root.cell
            width: root.cell
            height: root.implicitHeight

            MouseArea {
                id: area
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: if (!item.chosen) root.selected(item.modelData.value)
            }

            // The bar's fill over a band of the widget plate, the highlight on the seam.
            ClippingRectangle {
                id: swatch
                anchors.horizontalCenter: parent.horizontalCenter
                width: root.swatch
                height: root.swatch
                radius: item.chosen ? Math.min(width * 0.3, Appearance.rounding.large) : width / 2
                Behavior on radius {
                    enabled: !Appearance.reducedMotion
                    animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
                }
                color: item.theme.barBackground
                scale: area.pressed ? 0.95 : area.containsMouse ? 1.02 : 1
                Behavior on scale {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                Rectangle {
                    y: parent.height * 0.58
                    width: parent.width
                    height: parent.height - y
                    color: item.theme.componentBackground
                }
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: parent.height * 0.58 - height / 2
                    width: Math.round(parent.width * 0.3)
                    height: width
                    radius: width / 2
                    color: item.theme.highlight
                }
            }

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                y: swatch.height + root.labelGap
                width: parent.width - 4
                horizontalAlignment: Text.AlignHCenter
                text: item.modelData.label
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: item.chosen ? Font.Bold : Font.Normal
                color: item.chosen ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                elide: Text.ElideRight
            }
        }
    }
}
