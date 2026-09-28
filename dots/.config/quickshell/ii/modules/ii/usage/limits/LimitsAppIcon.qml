import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/** An app's icon by window class, with a symbol when no desktop entry draws one. */
Item {
    id: root

    property string appKey: ""
    property real size: 32
    property string fallbackSymbol: "apps"
    property color colFallback: Appearance.colors.colSubtext
    readonly property string iconName: root.appKey.length > 0 ? AppStats.iconFor(root.appKey) : ""

    implicitWidth: root.size
    implicitHeight: root.size

    IconImage {
        anchors.centerIn: parent
        visible: root.iconName.length > 0
        implicitSize: root.size
        source: root.iconName.length > 0 ? Quickshell.iconPath(root.iconName, "") : ""
    }

    MaterialSymbol {
        anchors.centerIn: parent
        visible: root.iconName.length === 0
        text: root.fallbackSymbol
        iconSize: Math.round(root.size * 0.78)
        color: root.colFallback
    }
}
