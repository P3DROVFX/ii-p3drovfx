import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.sidebarPolicies.phone

/** An app's icon by window class, with a symbol when no desktop entry draws one. */
Item {
    id: root

    property string appKey: ""
    property real size: 32
    property string fallbackSymbol: "apps"
    property color colFallback: Appearance.colors.colSubtext
    readonly property string iconName: root.appKey.length > 0 ? AppStats.iconFor(root.appKey) : ""
    readonly property bool isFilePath: root.iconName.startsWith("/")

    implicitWidth: root.size
    implicitHeight: root.size

    IconImage {
        anchors.centerIn: parent
        visible: root.iconName.length > 0 && !root.isFilePath
        implicitSize: root.size
        source: root.iconName.length > 0 && !root.isFilePath ? Quickshell.iconPath(root.iconName, "") : ""
    }

    Image {
        id: phoneIcon
        anchors.centerIn: parent
        width: root.size
        height: root.size
        source: root.isFilePath ? ("file://" + root.iconName) : ""
        sourceSize.width: Math.round(root.size * 2)
        sourceSize.height: Math.round(root.size * 2)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        visible: root.isFilePath && status === Image.Ready

        layer.enabled: root.isFilePath
        layer.effect: OpacityMask {
            maskSource: AndroidIconMask {
                width: phoneIcon.width
                height: phoneIcon.height
                shapeName: Config.options?.phone?.scrcpy?.appMode?.iconShape ?? "oneui"
            }
        }
    }

    MaterialSymbol {
        anchors.centerIn: parent
        visible: root.iconName.length === 0 || (root.isFilePath && phoneIcon.status !== Image.Ready)
        text: root.fallbackSymbol
        iconSize: Math.round(root.size * 0.78)
        color: root.colFallback
    }
}
