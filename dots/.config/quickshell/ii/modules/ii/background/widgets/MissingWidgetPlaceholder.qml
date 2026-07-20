import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Rectangle {
    id: placeholderRoot

    required property string widgetId
    required property real widgetX
    required property real widgetY

    visible: {
        if (!widgetId.startsWith("ext:")) return false;
        if (!WidgetExtensionManager.ready) return false;
        let extId = widgetId.substring(4);
        return !WidgetExtensionManager.isWidgetInstalled(extId);
    }

    x: widgetX
    y: widgetY
    width: 220
    height: 96
    radius: Appearance.rounding.large
    color: missingPlaceholderMouse.containsMouse
        ? Qt.rgba(0.12, 0, 0, 0.72)
        : Qt.rgba(0, 0, 0, 0.55)
    border.color: Qt.rgba(1, 0.4, 0.4, 0.5)
    border.width: 1

    Behavior on color { ColorAnimation { duration: 120 } }

    MouseArea {
        id: missingPlaceholderMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: Config.removeWidgetFromDesktop(placeholderRoot.widgetId)
    }

    Column {
        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
        }
        spacing: 4

        MaterialSymbol {
            text: "extension_off"
            iconSize: 18
            color: "#ff8a8a"
            anchors.horizontalCenter: parent.horizontalCenter
        }

        Text {
            text: placeholderRoot.widgetId.substring(4) + "\nnot installed"
            color: "#ffaaaa"
            font.pixelSize: 10
            horizontalAlignment: Text.AlignHCenter
            anchors.horizontalCenter: parent.horizontalCenter
        }

        // Remove hint
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: removeHintRow.implicitWidth + 16
            height: 20
            radius: height / 2
            color: Qt.rgba(1, 0.3, 0.3, 0.3)

            Row {
                id: removeHintRow
                anchors.centerIn: parent
                spacing: 3

                MaterialSymbol {
                    text: "close"
                    iconSize: 10
                    color: "#ffaaaa"
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    text: "Click to remove"
                    color: "#ffaaaa"
                    font.pixelSize: 9
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }
}
