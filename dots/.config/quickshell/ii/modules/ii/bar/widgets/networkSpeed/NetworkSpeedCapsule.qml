import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * Capsule — one pill, a filled disc per direction in the inverse surface.
 *
 * The disc carries the arrow (variant pair), the pill carries the numbers
 * (background pair). Two different surfaces, so the direction and the value
 * never compete for the same colour. Vertical keeps the grammar and stacks the
 * two discs, each over its compact value.
 */
Item {
    id: root

    property var net
    property var palette
    property bool vertical: false
    property real thickness: 32
    property real pillRadius: Appearance.rounding.full
    property bool hovered: false

    readonly property real chip: root.vertical ? root.thickness - root.net.tight(12, 10) : root.thickness - root.net.tight(8, 6)
    readonly property real edgeInset: (root.thickness - root.chip) / 2

    implicitWidth: root.vertical ? root.thickness : grid.implicitWidth + root.edgeInset + root.net.tight(12, 8)
    implicitHeight: root.vertical ? grid.implicitHeight + root.net.tight(14, 8) : root.thickness

    Rectangle {
        anchors.fill: parent
        radius: root.pillRadius
        color: root.hovered ? root.palette.colBackgroundHover : root.palette.colBackground

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }

    GridLayout {
        id: grid

        x: root.vertical ? Math.round((root.width - width) / 2) : root.edgeInset
        y: root.vertical ? root.net.tight(7, 4) : Math.round((root.height - height) / 2)
        columns: root.vertical ? 1 : 2
        columnSpacing: root.net.tight(12, 8)
        rowSpacing: root.net.tight(6, 3)

        NetworkSpeedCell {
            visible: root.net.showDown
            vertical: root.vertical
            readout: root.net
            rate: root.net.down
            iconName: "arrow_downward"
            chipSize: root.chip
            chipColor: root.palette.colBackgroundVariant
            iconColor: root.palette.colOnBackgroundVariant
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
            chipSize: root.chip
            chipColor: root.palette.colBackgroundVariant
            iconColor: root.palette.colOnBackgroundVariant
            numberColor: root.palette.colOnBackground
            unitColor: ColorUtils.mix(root.palette.colOnBackground, root.palette.colBackground, 0.7)
            Layout.alignment: root.vertical ? Qt.AlignHCenter : Qt.AlignVCenter
        }
    }
}
