import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick

Item {
    id: root

    property string icon: ""
    property int size: 20
    property color color: Appearance.colors.colOnLayer0

    readonly property bool svg: root.icon === "distro" || root.icon.endsWith("-symbolic")

    implicitWidth: root.size
    implicitHeight: root.size

    Loader {
        anchors.fill: parent
        active: root.svg
        sourceComponent: CustomIcon {
            source: root.icon === "distro" ? SystemInfo.distroIcon : root.icon
            colorize: true
            color: root.color
        }
    }

    MaterialSymbol {
        anchors.centerIn: parent
        visible: !root.svg
        text: root.icon
        iconSize: root.size
        color: root.color
    }
}
