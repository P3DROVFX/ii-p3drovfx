import qs.modules.common
import qs.modules.common.widgets
import qs.modules.akebono
import QtQuick

Item {
    id: root
    property real barHeight: 54
    property bool active: false
    property string icon: ""
    property string label: ""
    property string tooltipText: ""
    property color accent: Appearance.colors.colError
    property color onAccent: Appearance.colors.colOnError
    property bool interactive: false
    signal clicked()

    readonly property bool shelfEmpty: !active

    implicitWidth: pill.implicitWidth
    implicitHeight: barHeight * 0.7

    ShelfPill {
        id: pill
        anchors.verticalCenter: parent.verticalCenter
        implicitWidth: pillRow.implicitWidth + (root.label.length > 0 ? 18 : 14)
        implicitHeight: root.barHeight * 0.7
        color: (pillMouse.containsMouse && root.interactive) ? Qt.darker(root.accent, 1.12) : root.accent
        readonly property bool hovered: pillMouse.containsMouse
        Behavior on color { ColorAnimation { duration: 120 } }

        Row {
            id: pillRow
            anchors.centerIn: parent
            spacing: 5

            MaterialSymbol {
                anchors.verticalCenter: parent.verticalCenter
                text: root.icon
                iconSize: Math.round(root.barHeight * 0.38)
                fill: 1
                color: root.onAccent
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.label.length > 0
                text: root.label
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                color: root.onAccent
            }
        }

        MouseArea {
            id: pillMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: root.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: {
                if (root.interactive)
                    root.clicked();
            }
        }

        StyledToolTip {
            extraVisibleCondition: root.tooltipText.length > 0
            text: root.tooltipText
        }
    }
}
