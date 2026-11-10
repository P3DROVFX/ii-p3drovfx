import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * Graph — a live plot on a plate, the numbers beside it.
 *
 * The plate takes the palette's main surface and the bars its `on` colour, so
 * the plot is always a legible pair; the pill around it is the opposite surface. The
 * plot answers "is something happening and in which direction", the numbers
 * answer "how much". Vertical puts the plate on top and the values under it.
 */
Item {
    id: root

    property var net
    property var palette
    property bool vertical: false
    property real thickness: 32
    property real pillRadius: Appearance.rounding.full
    property bool hovered: false

    readonly property real inset: root.net.tight(4, 3)
    readonly property real gap: root.net.tight(10, 6)
    readonly property real gapV: root.net.tight(6, 4)
    readonly property real plateHeight: root.thickness - root.inset * 2
    readonly property real plateWidth: root.vertical ? root.thickness - root.inset * 2 : root.net.tight(66, 54)

    implicitWidth: root.vertical ? root.thickness : root.inset + root.plateWidth + root.gap + cells.implicitWidth + root.net.tight(12, 8)
    implicitHeight: root.vertical ? root.inset + root.plateHeight + root.gapV + cells.implicitHeight + root.net.tight(10, 6) : root.thickness

    Rectangle {
        anchors.fill: parent
        radius: root.pillRadius
        color: root.hovered ? root.palette.colBackgroundHover : root.palette.colBackground

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }

    Rectangle {
        id: plate

        x: root.vertical ? root.inset : root.inset
        y: root.vertical ? root.inset : Math.round((root.height - height) / 2)
        width: root.plateWidth
        height: root.plateHeight
        radius: Math.min(root.pillRadius, root.vertical ? Appearance.rounding.small : height / 2)
        color: root.hovered ? root.palette.colBackgroundVariantHover : root.palette.colBackgroundVariant

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        NetworkSpeedPlot {
            anchors.centerIn: parent
            slotWidth: root.vertical ? 4 : 5
            barWidth: root.vertical ? 2.5 : 3
            width: Math.floor((plate.width - (root.vertical ? 8 : 18)) / slotWidth) * slotWidth
            height: plate.height - 6
            net: root.net
            barColor: root.palette.colOnBackgroundVariant
        }
    }

    GridLayout {
        id: cells

        x: root.vertical ? Math.round((root.width - width) / 2) : root.inset + root.plateWidth + root.gap
        y: root.vertical ? root.inset + root.plateHeight + root.gapV : Math.round((root.height - height) / 2)
        columns: root.vertical ? 1 : 2
        columnSpacing: root.net.tight(10, 6)
        rowSpacing: root.net.tight(4, 2)

        NetworkSpeedCell {
            visible: root.net.showDown
            vertical: root.vertical
            readout: root.net
            rate: root.net.down
            iconName: "arrow_downward"
            iconColor: root.palette.colOnBackground
            numberColor: root.palette.colOnBackground
            unitColor: ColorUtils.mix(root.palette.colOnBackground, root.palette.colBackground, 0.7)
            Layout.alignment: root.vertical ? Qt.AlignHCenter : Qt.AlignVCenter
        }

        NetworkSpeedCell {
            visible: root.net.showUp
            vertical: root.vertical
            readout: root.net
            rate: root.net.up
            iconName: "arrow_upward"
            iconColor: root.palette.colOnBackground
            numberColor: root.palette.colOnBackground
            unitColor: ColorUtils.mix(root.palette.colOnBackground, root.palette.colBackground, 0.7)
            Layout.alignment: root.vertical ? Qt.AlignHCenter : Qt.AlignVCenter
        }
    }
}
