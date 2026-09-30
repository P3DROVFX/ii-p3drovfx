import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * A row that opens something: the timetable rail's Date / Calendar row. The shape turns
 * under the pointer, and the chevron turns down while what it opened is showing below.
 */
Rectangle {
    id: root

    property string symbol: ""
    property int shapeKind: MaterialShape.Shape.Cookie12Sided
    property string caption: ""
    property string value: ""
    property bool expanded: false
    property bool showChevron: true
    property bool highlighted: false
    // An action's row: the caption names it and the value explains it, so the caption leads.
    property bool captionLeads: false
    default property alias trailing: trailingRow.data

    signal triggered()

    Layout.fillWidth: true
    implicitHeight: 62
    radius: Appearance.rounding.small
    color: root.highlighted ? ClockStyle.colSecondaryContainer
        : pointer.containsMouse ? ClockStyle.colFieldHover : ClockStyle.colField

    Behavior on color {
        animation: ClockStyle.motionFast.colorAnimation.createObject(this)
    }

    MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.triggered()
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 12
        spacing: 10

        MaterialShapeWrappedMaterialSymbol {
            text: root.symbol
            iconSize: 18
            padding: 9
            shape: root.shapeKind
            color: root.highlighted ? ClockStyle.colTertiary : ClockStyle.colPrimaryContainer
            colSymbol: root.highlighted ? ClockStyle.colOnTertiary : ClockStyle.colOnPrimaryContainer
            rotation: pointer.containsMouse || root.expanded ? 18 : 0
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                text: root.caption
                font.pixelSize: root.captionLeads ? Appearance.font.pixelSize.normal : Appearance.font.pixelSize.smallest
                font.weight: root.captionLeads ? Font.DemiBold : Font.Bold
                color: root.highlighted ? ClockStyle.colOnSecondaryContainer
                    : root.captionLeads ? ClockStyle.colOnSurface : ClockStyle.colOnSurfaceVariant
            }

            StyledText {
                Layout.fillWidth: true
                text: root.value
                font.pixelSize: root.captionLeads ? Appearance.font.pixelSize.smaller : Appearance.font.pixelSize.small
                font.weight: root.captionLeads ? Font.Normal : Font.Bold
                color: root.highlighted ? ClockStyle.colOnSecondaryContainer
                    : root.captionLeads ? ClockStyle.colOnSurfaceVariant : ClockStyle.colOnSurface
                elide: Text.ElideRight
            }
        }

        RowLayout {
            id: trailingRow
            spacing: 2
        }

        MaterialSymbol {
            visible: root.showChevron
            text: "chevron_right"
            iconSize: Appearance.font.pixelSize.large
            color: ClockStyle.colOnSurfaceVariant
            rotation: root.expanded ? 90 : 0

            Behavior on rotation {
                animation: ClockStyle.motionSpatial.numberAnimation.createObject(this)
            }
        }
    }
}
