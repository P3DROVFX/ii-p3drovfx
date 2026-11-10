import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * Rows — download over upload, one line each, inside a single pill.
 *
 * The numbers and units of the two rows share one column each, so they line
 * up like a table instead of two independent captions. Horizontally every row
 * leads with a small accent disc. The vertical bar has no width for a one-line
 * "arrow 176 K" (three digits plus arrow and unit overrun 36 px), so each row
 * there is arrow-over-value, and a 2 px divider keeps the two rows reading as
 * rows. With a single direction the one row grows to fill the pill.
 */
Item {
    id: root

    property var net
    property var palette
    property bool vertical: false
    property real thickness: 32
    property real pillRadius: Appearance.rounding.full
    property bool hovered: false

    readonly property bool both: root.net.showBoth
    // One row has the whole short axis to itself, so it is drawn larger.
    readonly property real chip: root.vertical ? 0 : (root.both ? 14 : root.thickness - 8)
    readonly property real iconSize: root.both ? 10 : Appearance.font.pixelSize.normal
    readonly property real numberSize: root.both ? Appearance.font.pixelSize.smaller : Appearance.font.pixelSize.small
    readonly property real unitSize: root.both ? Appearance.font.pixelSize.smallest : Appearance.font.pixelSize.smaller
    // Clear of the rounded end, which the two stacked discs would otherwise touch.
    readonly property real edgeInset: root.vertical ? 0 : (root.both ? root.net.tight(8, 7) : (root.thickness - root.chip) / 2)

    implicitWidth: root.vertical ? root.thickness : rows.implicitWidth + root.edgeInset + root.net.tight(12, 8)
    implicitHeight: root.vertical ? rows.implicitHeight + root.net.tight(14, 8) : root.thickness

    Rectangle {
        anchors.fill: parent
        radius: root.pillRadius
        color: root.hovered ? root.palette.colBackgroundHover : root.palette.colBackground

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }

    ColumnLayout {
        id: rows

        x: root.vertical ? Math.round((root.width - width) / 2) : root.edgeInset
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.vertical ? root.net.tight(5, 3) : root.net.tight(2, 1)

        // Two text lines would not fit the short axis, so the disc sets the row
        // height and the cell is centred on it instead of sizing it.
        Item {
            visible: root.net.showDown
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: downCell.implicitWidth
            implicitHeight: root.both && !root.vertical ? root.chip : downCell.implicitHeight

            NetworkSpeedCell {
                id: downCell
                anchors.verticalCenter: parent.verticalCenter
                vertical: root.vertical
                readout: root.net
                rate: root.net.down
                iconName: "arrow_downward"
                chipSize: root.chip
                chipColor: root.palette.colBackgroundVariant
                iconColor: root.vertical ? root.palette.colOnBackground : root.palette.colOnBackgroundVariant
                numberColor: root.palette.colOnBackground
                unitColor: ColorUtils.mix(root.palette.colOnBackground, root.palette.colBackground, 0.7)
                iconSize: root.vertical ? Appearance.font.pixelSize.small : root.iconSize
                numberSize: root.vertical ? Appearance.font.pixelSize.smaller - 1 : root.numberSize
                unitSize: root.vertical ? Appearance.font.pixelSize.smaller - 2 : root.unitSize
                columnSpacing: root.net.tight(4, 3)
            }
        }

        Rectangle {
            visible: root.vertical && root.both
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: root.thickness - 12
            implicitHeight: 2
            radius: 1
            color: ColorUtils.transparentize(root.palette.colOnBackground, 0.82)
        }

        // Two text lines would not fit the short axis, so the disc sets the row
        // height and the cell is centred on it instead of sizing it.
        Item {
            visible: root.net.showUp
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: upCell.implicitWidth
            implicitHeight: root.both && !root.vertical ? root.chip : upCell.implicitHeight

            NetworkSpeedCell {
                id: upCell
                anchors.verticalCenter: parent.verticalCenter
                vertical: root.vertical
                readout: root.net
                rate: root.net.up
                iconName: "arrow_upward"
                chipSize: root.chip
                chipColor: root.palette.colBackgroundVariant
                iconColor: root.vertical ? root.palette.colOnBackground : root.palette.colOnBackgroundVariant
                numberColor: root.palette.colOnBackground
                unitColor: ColorUtils.mix(root.palette.colOnBackground, root.palette.colBackground, 0.7)
                iconSize: root.vertical ? Appearance.font.pixelSize.small : root.iconSize
                numberSize: root.vertical ? Appearance.font.pixelSize.smaller - 1 : root.numberSize
                unitSize: root.vertical ? Appearance.font.pixelSize.smaller - 2 : root.unitSize
                columnSpacing: root.net.tight(4, 3)
            }
        }
    }
}
