import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Item {
    id: root
    property bool vertical: false
    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(root.QsWindow.window?.screen)
    readonly property Toplevel activeWindow: ToplevelManager.activeToplevel

    property string activeWindowAddress: `0x${activeWindow?.HyprlandToplevel?.address}`
    property bool focusingThisMonitor: HyprlandData.activeWorkspace?.monitor == monitor?.name
    property var biggestWindow: HyprlandData.biggestWindowForWorkspace(HyprlandData.monitors[root.monitor?.id]?.activeWorkspace.id)

    readonly property bool isFixedSize: Config.options.bar.activeWindow.fixedSize

    readonly property int maxSize: 350
    property int popupWidth: 350
    property int maxPopupWidth: 600
    readonly property int fixedSize: Config.options.bar.activeWindow.customSize

    property string appClassText: root.focusingThisMonitor && root.activeWindow?.activated && root.biggestWindow ? 
                root.activeWindow?.appId : (root.biggestWindow?.class) ?? Translation.tr("Desktop")
                
    property string appTitleText: root.focusingThisMonitor && root.activeWindow?.activated && root.biggestWindow ? 
                root.activeWindow?.title : (root.biggestWindow?.title) ?? `${Translation.tr("Workspace")} ${monitor?.activeWorkspace?.id ?? 1}`
    
    implicitHeight: root.vertical && isFixedSize ? fixedSize : (root.vertical ? Math.max(expressiveText.implicitWidth) + 30 : Appearance.sizes.baseBarHeight)
    implicitWidth: !root.vertical && isFixedSize ? fixedSize : (root.vertical ? Appearance.sizes.verticalBarWidth : Math.min(Math.max(expressiveText.implicitWidth) + 30, maxSize))
    clip: true

    property bool containsMouse: mouseArea.containsMouse

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
    }

    ActiveWindowPopup {
        id: titlePopup
        targetItem: root
        appClassText: root.appClassText
        appTitleText: root.appTitleText
        activeWindowAddress: root.activeWindowAddress
        monitor: root.monitor
        popupWidth: root.popupWidth
        maxPopupWidth: root.maxPopupWidth
    }

    Behavior on implicitWidth {
        NumberAnimation {
            duration: 450
            easing.type: Easing.OutExpo
        }
    }
    Behavior on implicitHeight {
        NumberAnimation {
            duration: 450
            easing.type: Easing.OutExpo
        }
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 4
        radius: Appearance.rounding.full
        color: "transparent"
        border.color: Appearance.colors.colTertiaryContainer
        border.width: 2

        StyledText {
            id: expressiveText
            anchors.centerIn: parent
            rotation: root.vertical ? -90 : 0
            text: root.vertical ? root.appClassText : root.appTitleText
            font.family: Appearance.font.family.expressive
            font.variableAxes: Appearance.font.variableAxes.rounded
            font.weight: Font.Bold
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnLayer0
            elide: Text.ElideRight
            width: root.vertical ? parent.height - 20 : parent.width - 20
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }
}
