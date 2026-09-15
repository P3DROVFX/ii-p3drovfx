pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import Qt5Compat.GraphicalEffects
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Item {
    id: root
    required property var toplevel
    required property var windowData
    required property var overview
    property real xOffset: 0
    property real yOffset: 0

    readonly property var monitorData: overview.monitorData
    readonly property real k: overview.wsScale
    readonly property real initX: Math.max((windowData?.at[0] - (monitorData?.x ?? 0) - (monitorData?.reserved[0] ?? 0)) * k, 0) + xOffset
    readonly property real initY: Math.max((windowData?.at[1] - (monitorData?.y ?? 0) - (monitorData?.reserved[1] ?? 0)) * k, 0) + yOffset
    readonly property real targetW: (windowData?.size[0] ?? 100) * k
    readonly property real targetH: (windowData?.size[1] ?? 100) * k
    readonly property string iconPath: Quickshell.iconPath(AppSearch.guessIcon(windowData?.class), "image-missing")
    property bool hovered: false
    property bool pressed: false

    x: initX
    y: initY
    width: targetW
    height: targetH
    z: Drag.active ? 9999 : (1 + (windowData?.floating ? 1 : 0) + (windowData?.fullscreen ? 2 : 0))

    Behavior on x {
        animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
    }
    Behavior on y {
        animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
    }
    Behavior on width {
        animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
    }
    Behavior on height {
        animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
    }

    layer.enabled: true
    layer.effect: OpacityMask {
        maskSource: Rectangle {
            width: root.width
            height: root.height
            radius: 10
        }
    }

    Timer {
        id: resetPosition
        interval: Config.options.hacks.arbitraryRaceConditionDelay
        onTriggered: {
            root.x = root.initX;
            root.y = root.initY;
        }
    }

    ScreencopyView {
        anchors.fill: parent
        captureSource: GlobalStates.desktopOverviewOpen ? root.toplevel : null
        live: true

        Rectangle {
            anchors.fill: parent
            radius: 10
            color: root.pressed ? ColorUtils.transparentize(Appearance.colors.colLayer2Active, 0.5)
                : root.hovered ? ColorUtils.transparentize(Appearance.colors.colLayer2Hover, 0.7)
                : ColorUtils.transparentize(Appearance.colors.colLayer2)
            border.color: ColorUtils.transparentize(Appearance.m3colors.m3outline, 0.88)
            border.width: 1
        }

        Image {
            anchors.centerIn: parent
            readonly property real iconSize: Math.min(root.targetW, root.targetH) * 0.3
            source: root.iconPath
            width: iconSize
            height: iconSize
            sourceSize: Qt.size(iconSize, iconSize)
        }
    }

    Drag.hotSpot.x: width / 2
    Drag.hotSpot.y: height / 2

    MouseArea {
        id: dragArea
        anchors.fill: parent
        hoverEnabled: true
        onEntered: root.hovered = true
        onExited: root.hovered = false
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        drag.target: parent
        onPressed: (mouse) => {
            root.overview.draggingFromWorkspace = root.windowData?.workspace.id ?? -1;
            root.pressed = true;
            root.Drag.active = true;
            root.Drag.source = root;
            root.Drag.hotSpot.x = mouse.x;
            root.Drag.hotSpot.y = mouse.y;
        }
        onReleased: {
            const targetWorkspace = root.overview.draggingTargetWorkspace;
            root.pressed = false;
            root.Drag.active = false;
            root.overview.draggingFromWorkspace = -1;
            if (targetWorkspace !== -1 && targetWorkspace !== root.windowData?.workspace.id) {
                Hyprland.dispatch(`hl.dsp.window.move({ workspace = ${targetWorkspace}, follow = false, window = "address:${root.windowData?.address}" })`);
                resetPosition.restart();
            } else {
                if (!root.windowData.floating) {
                    resetPosition.restart();
                    return;
                }
                const percentageX = Math.round((root.x - root.xOffset) / root.overview.cardW * 100);
                const percentageY = Math.round((root.y - root.yOffset) / root.overview.cardH * 100);
                Hyprland.dispatch(`hl.dsp.window.move({ x = "${percentageX}%", y = "${percentageY}%", window = "address:${root.windowData?.address}" })`);
            }
        }
        onClicked: (event) => {
            if (!root.windowData)
                return;
            if (event.button === Qt.LeftButton) {
                GlobalStates.desktopOverviewOpen = false;
                Hyprland.dispatch(`hl.dsp.focus({window = "address:${root.windowData.address}"})`);
                event.accepted = true;
            } else if (event.button === Qt.MiddleButton) {
                Hyprland.dispatch(`hl.dsp.window.close({window = "address:${root.windowData.address}"})`);
                event.accepted = true;
            }
        }

        StyledToolTip {
            extraVisibleCondition: false
            alternativeVisibleCondition: dragArea.containsMouse && !root.Drag.active
            text: `${root.windowData?.title}\n[${root.windowData?.class}]`
        }
    }
}
