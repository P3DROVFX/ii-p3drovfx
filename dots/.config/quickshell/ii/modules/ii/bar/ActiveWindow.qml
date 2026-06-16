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
    readonly property int fixedSize: root.vertical ? 150 : Config.options.bar.activeWindow.customSize

    property string appClassText: root.focusingThisMonitor && root.activeWindow?.activated && root.biggestWindow ? 
                root.activeWindow?.appId : (root.biggestWindow?.class) ?? Translation.tr("Desktop")
                
    property string appTitleText: root.focusingThisMonitor && root.activeWindow?.activated && root.biggestWindow ? 
                root.activeWindow?.title : (root.biggestWindow?.title) ?? `${Translation.tr("Workspace")} ${monitor?.activeWorkspace?.id ?? 1}`
    
    implicitHeight: root.vertical && isFixedSize ? fixedSize : (root.vertical ? Math.max(classText.implicitWidth, titleText.implicitWidth) + 20 : colLayout.implicitHeight)
    implicitWidth: !root.vertical && isFixedSize ? fixedSize : (root.vertical ? undefined : Math.min(Math.max(classText.implicitWidth, titleText.implicitWidth) + 20, maxSize))
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
        animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
    }
    Behavior on implicitHeight {
        animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
    }

    ColumnLayout {
        visible: true
        id: colLayout

        anchors.verticalCenter: parent.verticalCenter
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: -4

        width: root.vertical ? implicitWidth : root.width
        height: root.vertical ? root.height : implicitHeight

        StyledText {
            id: classText
            Layout.leftMargin: 6
            visible: !root.vertical
            Layout.fillWidth: true
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            elide: Text.ElideRight
            text: root.appClassText
        }

        StyledText {
            id: titleText
            Layout.leftMargin: root.vertical ? 0 : 6
            Layout.fillWidth: true
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnLayer0
            elide: Text.ElideRight
            rotation: root.vertical ? -90 : 0
            text: root.vertical ? root.appClassText : root.appTitleText
        }
    }
}