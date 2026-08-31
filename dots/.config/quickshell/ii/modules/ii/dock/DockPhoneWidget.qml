pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

import "./widgets"

/**
 * Compact phone mirror shortcut for the dock.
 *
 * KDE Connect remains the source of truth for the active reachable device;
 * scrcpy is launched through KdeConnectService so this shortcut shares the
 * same ADB, wireless and process lifecycle as the Phone sidebar card.
 */
Item {
    id: root

    property bool isVertical: false
    property var dockContent: null
    property int delegateIndex: -1
    property bool phoneHovered: false

    readonly property real buttonSize: Appearance.sizes.dockButtonSize
    readonly property real dotMargin: root.dockContent?.dotMargin ?? Math.max(1, Math.round((Config.options?.dock.height ?? 60) * 0.2) - 2)
    readonly property real dotMarginV: root.dockContent?.dotMarginV ?? root.dotMargin
    readonly property real slotWidth: root.dockContent?.buttonSlotSize ?? (root.buttonSize + root.dotMargin * 2)
    readonly property real slotHeight: root.dockContent
        ? (root.isVertical ? root.dockContent.buttonSlotSize : root.dockContent.buttonSlotHeight)
        : (root.buttonSize + root.dotMarginV * 2)
    readonly property real magnification: root.dockContent ? root.dockContent._getSlotMagScale(root) : 1.0
    // The tile stays visually subordinate while the phone silhouette gets
    // the stronger macOS-style lift on hover.
    readonly property real backgroundMagnification: 1.0 + (root.magnification - 1.0) * 0.62
    readonly property real iconMagnification: 1.0 + (root.magnification - 1.0) * 1.08
    readonly property int magnificationTransformOrigin: {
        const pos = root.dockContent?.dockPos ?? "bottom";
        if (pos === "top")
            return Item.Top;
        if (pos === "left")
            return Item.Left;
        if (pos === "right")
            return Item.Right;
        return Item.Bottom;
    }
    readonly property bool hasDevice: KdeConnectService.activeDeviceId !== "" && KdeConnectService.activeReachable
    readonly property string deviceName: KdeConnectService.activeDeviceDisplayName || Translation.tr("No connected phone")
    readonly property int deviceCharge: KdeConnectService.activeDevice?.charge ?? -1
    readonly property string deviceImageSource: "file://" + Directories.assetsPath + "/images/devices/Google_Pixel_9_Pro_XL_(Hazel)_rear.svg"
    readonly property bool isRunning: PhoneScrcpyService.mirrorRunning || KdeConnectService.scrcpyRunning
    readonly property bool isLaunching: PhoneScrcpyService.mirrorLaunching || KdeConnectService.scrcpyLaunching

    readonly property string mirrorStatus: {
        if (!PhoneScrcpyService.available && !KdeConnectService.scrcpyAvailable)
            return Translation.tr("scrcpy unavailable");
        if (isRunning)
            return Translation.tr("Mirror running · click to focus");
        if (isLaunching)
            return Translation.tr("Launching scrcpy…");
        if (!KdeConnectService.adbReachable)
            return Translation.tr("ADB not connected");
        return Translation.tr("Click to launch mirror / DeX");
    }
    readonly property string tooltipText: {
        const battery = root.deviceCharge >= 0 ? " · " + String(root.deviceCharge) + "%" : "";
        return root.deviceName + battery + " · KDE Connect\n" + root.mirrorStatus;
    }

    width: root.slotWidth
    height: root.slotHeight
    implicitWidth: width
    implicitHeight: height

    function openMirror(): void {
        if (!root.hasDevice)
            return;
        if (isRunning) {
            PhoneScrcpyService.focusMirror();
            KdeConnectService.focusScrcpyWindow();
            return;
        }

        if (!isLaunching) {
            PhoneScrcpyService.launchMirror();
        }
    }

    MouseArea {
        id: interactionArea
        anchors.fill: parent
        z: 10
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        preventStealing: true
        cursorShape: Qt.PointingHandCursor
        hoverEnabled: true
        property real pressCoord: 0
        property bool dragActive: false

        onEntered: {
            root.phoneHovered = true;
            if (root.dockContent?.suppressHover)
                return;
            root.dockContent?.onButtonEntered(root);
        }
        onExited: {
            root.phoneHovered = false;
            root.dockContent?.onButtonExited(root);
        }
        onPressed: event => {
            if (event.button === Qt.LeftButton)
                pressCoord = root.isVertical ? event.y : event.x;
        }
        onPositionChanged: event => {
            if (!pressed)
                return;
            const currentCoord = root.isVertical ? event.y : event.x;
            const distance = Math.abs(currentCoord - pressCoord);
            if (!dragActive && distance > 5 && root.delegateIndex >= 0) {
                dragActive = true;
                root.dockContent?.startItemDrag(root.delegateIndex, interactionArea, event.x, event.y);
            }
            if (dragActive)
                root.dockContent?.moveItemDrag(interactionArea, event.x, event.y);
        }
        onReleased: event => {
            if (dragActive) {
                dragActive = false;
                root.dockContent?.endItemDrag();
                return;
            }
            if (event.button === Qt.LeftButton)
                root.openMirror();
        }
        onCanceled: {
            if (dragActive) {
                dragActive = false;
                root.dockContent?.cancelDrag();
            }
        }
    }

    Rectangle {
        id: phoneTile
        width: root.buttonSize * 0.86
        height: root.buttonSize * 0.92
        anchors.centerIn: parent
        radius: Appearance.rounding.small
        scale: root.backgroundMagnification
        transformOrigin: root.magnificationTransformOrigin
        color: root.phoneHovered ? Appearance.colors.colLayer2Base : Appearance.colors.colLayer1Base
        opacity: root.hasDevice ? 1.0 : 0.45

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        Image {
            id: phoneIcon
            anchors.fill: parent
            anchors.leftMargin: root.buttonSize * 0.06
            anchors.rightMargin: root.buttonSize * 0.06
            anchors.topMargin: root.buttonSize * 0.05
            anchors.bottomMargin: root.buttonSize * 0.05
            source: root.deviceImageSource
            sourceSize: Qt.size(root.buttonSize * 2, root.buttonSize * 2)
            fillMode: Image.PreserveAspectFit
            scale: root.iconMagnification
            transformOrigin: root.magnificationTransformOrigin
            smooth: true
            antialiasing: true
            mipmap: true
        }
    }

    Rectangle {
        width: Math.max(3, Math.round(root.buttonSize * 0.08))
        height: width
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Math.max(1, root.dotMarginV * 0.35)
        radius: Appearance.rounding.full
        color: KdeConnectService.scrcpyRunning ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
        opacity: KdeConnectService.scrcpyLaunching ? 0.65 : 1.0
    }

    DockTooltip {
        id: phoneTooltip
        // Anchor to the transformed icon bounds so magnification is included
        // when calculating the gap between the icon and the tooltip.
        parentItem: phoneIcon
        text: root.tooltipText
        showTooltip: root.phoneHovered
        tooltipOffset: -root.dotMargin
    }
}
