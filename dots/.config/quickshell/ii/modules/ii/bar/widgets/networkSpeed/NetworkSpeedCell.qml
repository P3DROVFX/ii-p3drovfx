import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * One direction of the readout: arrow, number, unit.
 *
 * Horizontal reads left to right; vertical stacks the arrow over a compact
 * "1.2M". The number and unit slots are as wide as their widest value, so a
 * change from "9.9" to "10" (or KB/s to MB/s) never moves the neighbours.
 */
GridLayout {
    id: root

    property bool vertical: false
    property var readout
    property var rate
    property string iconName: "arrow_downward"
    // Where the arrow sits against the value, and whether the unit is the
    // one-letter form. Both follow `vertical`; the rows design overrides them
    // to keep a single line inside the vertical bar.
    property bool stacked: root.vertical
    property bool letterUnit: root.vertical
    property string numberReference: root.readout.numberReference

    property color iconColor: Appearance.colors.colSubtext
    property color numberColor: Appearance.colors.colOnLayer1
    property color unitColor: Appearance.colors.colSubtext

    property real iconSize: root.vertical ? Appearance.font.pixelSize.small : Appearance.font.pixelSize.normal
    property real numberSize: root.vertical ? Appearance.font.pixelSize.smaller - 1 : Appearance.font.pixelSize.small
    property real unitSize: root.vertical ? Appearance.font.pixelSize.smaller - 2 : Appearance.font.pixelSize.smaller
    // A filled disc behind the arrow (the capsule design). 0 = no disc.
    property real chipSize: 0
    property color chipColor: "transparent"
    // Arrows of a direction with no traffic recede, so the active one reads at a glance.
    property real idleOpacity: 0.45

    columns: root.stacked ? 1 : 2
    rowSpacing: 0
    columnSpacing: root.readout.tight(3, 2)

    Item {
        id: iconSlot
        implicitWidth: root.chipSize > 0 ? root.chipSize : arrow.implicitWidth
        implicitHeight: root.chipSize > 0 ? root.chipSize : arrow.implicitHeight
        Layout.alignment: root.stacked ? Qt.AlignHCenter : Qt.AlignVCenter

        Rectangle {
            anchors.fill: parent
            visible: root.chipSize > 0
            radius: width / 2
            color: root.chipColor

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }

        MaterialSymbol {
            id: arrow
            anchors.centerIn: parent
            text: root.iconName
            iconSize: root.iconSize
            fill: 1
            color: root.iconColor
            opacity: root.rate.active ? 1 : root.idleOpacity

            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }
    }

    RowLayout {
        spacing: root.readout.tight(2, 1)
        Layout.alignment: root.stacked ? Qt.AlignHCenter : Qt.AlignVCenter

        StyledText {
            id: numberText
            text: root.rate.number
            font.pixelSize: root.numberSize
            font.weight: Font.Bold
            color: root.numberColor
            horizontalAlignment: Text.AlignRight
            Layout.preferredWidth: Math.max(numberMetrics.advanceWidth, numberText.implicitWidth)

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }

        StyledText {
            id: unitText
            visible: root.letterUnit || root.readout.showUnit
            text: root.letterUnit ? root.rate.compactUnit : root.rate.unit
            font.pixelSize: root.unitSize
            color: root.unitColor
            Layout.preferredWidth: Math.max(unitMetrics.advanceWidth, unitText.implicitWidth)

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }
    }

    TextMetrics {
        id: numberMetrics
        font: numberText.font
        text: root.numberReference
    }

    TextMetrics {
        id: unitMetrics
        font: unitText.font
        text: root.letterUnit ? "M" : root.readout.unitReference
    }
}
