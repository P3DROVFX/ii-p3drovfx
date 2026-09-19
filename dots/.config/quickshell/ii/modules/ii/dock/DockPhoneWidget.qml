pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
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
    // The image set for the phone under Bluetooth Device Images, if any. The
    // Bluetooth device is matched by name, else it is the only paired phone
    // that has an image.
    readonly property string customImageFile: {
        const images = Config.options.bluetoothDeviceImages || [];
        if (images.length === 0)
            return "";
        const imageFor = mac => {
            for (let i = 0; i < images.length; i++) {
                if (images[i].mac === mac && images[i].image)
                    return images[i].image;
            }
            return "";
        };
        const name = (KdeConnectService.activeDeviceDisplayName || "").toLowerCase();
        const devices = BluetoothStatus.friendlyDeviceList || [];
        let phoneImages = [];
        for (let i = 0; i < devices.length; i++) {
            const image = imageFor(devices[i].address);
            if (image === "")
                continue;
            const btName = (devices[i].name || "").toLowerCase();
            if (name !== "" && btName !== "" && (btName === name || btName.includes(name) || name.includes(btName)))
                return image;
            if (devices[i].paired && (devices[i].icon || "").startsWith("phone"))
                phoneImages.push(image);
        }
        return phoneImages.length === 1 ? phoneImages[0] : "";
    }
    // Model icons made by assets/icons/phone/generate_phones.py. Its index.json maps
    // the marketing name KDE Connect reports ("Galaxy S24 Ultra") to a PNG; keys are
    // normalised to lowercase alphanumerics (and "+") so "Phone (2a)" == "phone 2a", and
    // a trailing "5G" is dropped because the index and Android don't agree on it.
    readonly property string phoneIconDir: Directories.assetsPath + "/icons/phone"
    property var modelIcons: ({})
    readonly property string modelIconFile: {
        const model = root.normaliseModel(KdeConnectService.activeDevice?.name ?? "");
        if (model === "")
            return "";
        const exact = root.modelIcons[model];
        if (exact)
            return exact;
        // "Samsung Galaxy S24 Ultra" vs "Galaxy S24 Ultra": longest key that is a
        // suffix of the other side wins
        let best = "";
        for (const key in root.modelIcons) {
            if (key.length < 5 || key.length <= best.length)
                continue;
            if (model.endsWith(key) || key.endsWith(model))
                best = key;
        }
        return best !== "" ? root.modelIcons[best] : "";
    }
    readonly property string deviceImageSource: {
        if (modelIconFile !== "")
            return "file://" + root.phoneIconDir + "/" + modelIconFile;
        if (customImageFile !== "")
            return "file://" + Directories.shellConfig + "/bluetooth_images/" + customImageFile;
        return "file://" + root.phoneIconDir + "/phone-generic-android.png";
    }

    readonly property bool generatedIcon: modelIconFile !== "" || customImageFile === ""

    function normaliseModel(name: string): string {
        return name.toLowerCase().replace(/[^a-z0-9+]/g, "").replace(/5g$/, "");
    }

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

    transform: [attention.shift, attention.grow, attention.turn]

    FileView {
        path: root.phoneIconDir + "/index.json"
        // Only rewritten by the generator; a shell reload picks up a new index
        watchChanges: false
        printErrors: false
        onLoaded: {
            let map = {};
            try {
                const index = JSON.parse(text());
                for (const name in index)
                    map[root.normaliseModel(name)] = index[name];
            } catch (e) {
                console.warn("[DockPhoneWidget] bad phone icon index:", e);
            }
            root.modelIcons = map;
        }
    }

    DockAttentionAnimation {
        id: attention
        host: root
        dockPos: root.dockContent?.dockPos ?? "bottom"
    }

    onIsRunningChanged: {
        if (isRunning)
            attention.settle();
    }

    function openMirror(): void {
        if (!root.hasDevice)
            return;
        if (isRunning) {
            PhoneScrcpyService.focusMirror();
            KdeConnectService.focusScrcpyWindow();
            return;
        }

        if (!isLaunching) {
            attention.playLaunch(Config.options?.dock?.launchAnimation ?? "bounce");
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
            if (event.button === Qt.RightButton) {
                if (root.dockContent) {
                    root.dockContent.buttonHovered = false;
                    root.dockContent.lastHoveredButton = null;
                }
                phoneContextMenu.open();
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

    Item {
        // Generated icons share the app tiles' 64-grid, so they take the full button;
        // a custom Bluetooth photo keeps the old, tighter box
        width: root.generatedIcon ? root.buttonSize : root.buttonSize * 0.86
        height: root.generatedIcon ? root.buttonSize : root.buttonSize * 0.92
        anchors.centerIn: parent
        scale: 1.0 + (root.magnification - 1.0) * 0.62
        transformOrigin: root.magnificationTransformOrigin
        opacity: root.hasDevice ? 1.0 : 0.45

        Image {
            id: phoneIcon
            anchors.fill: parent
            anchors.leftMargin: root.generatedIcon ? 0 : root.buttonSize * 0.06
            anchors.rightMargin: root.generatedIcon ? 0 : root.buttonSize * 0.06
            anchors.topMargin: root.generatedIcon ? 0 : root.buttonSize * 0.05
            anchors.bottomMargin: root.generatedIcon ? 0 : root.buttonSize * 0.05
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
        id: phoneIndicator
        visible: root.isRunning
        width: Math.max(3, Math.round(root.buttonSize * 0.08))
        height: width
        anchors.margins: Math.max(1, root.dotMarginV * 0.35)
        state: root.dockContent?.dockPos ?? "bottom"
        // Swap anchors atomically, as DockAppIndicator does on orientation changes.
        states: [
            State {
                name: "top"
                AnchorChanges { target: phoneIndicator; anchors.top: parent.top; anchors.horizontalCenter: parent.horizontalCenter }
            },
            State {
                name: "bottom"
                AnchorChanges { target: phoneIndicator; anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter }
            },
            State {
                name: "left"
                AnchorChanges { target: phoneIndicator; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter }
            },
            State {
                name: "right"
                AnchorChanges { target: phoneIndicator; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter }
            }
        ]
        radius: Appearance.rounding.full
        color: Appearance.colors.colPrimary
    }

    DockPhoneContextMenu {
        id: phoneContextMenu
        anchorItem: root
        // The icon carries the magnification; the widget itself never scales.
        geometryItem: phoneIcon
    }

    Connections {
        target: phoneContextMenu
        function onActiveChanged() {
            if (!root.dockContent)
                return;
            if (phoneContextMenu.active)
                root.dockContent.registerContextMenuOpen();
            else
                root.dockContent.registerContextMenuClose();
        }
    }

    // Safety: if this widget is destroyed while its menu is open, clean up the counter
    Component.onDestruction: {
        if (root.dockContent && phoneContextMenu.active)
            root.dockContent.registerContextMenuClose();
    }

    DockTooltip {
        id: phoneTooltip
        // Anchor to the transformed icon bounds so magnification is included
        // when calculating the gap between the icon and the tooltip.
        parentItem: phoneIcon
        text: root.tooltipText
        // Follow the dock's "Hover content" setting like app buttons do.
        showTooltip: ((Config.options?.dock?.enableAppTooltip ?? false) || GlobalStates.editMode)
            && root.phoneHovered && !phoneContextMenu.active
        tooltipOffset: -root.dotMargin
    }
}
