pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.tablet.windows
import "../../tablet/windows/TabletWindowGeometry.js" as WindowGeometry

/**
 * Window controls for Phone Mirror / Scrcpy.
 *
 * Provides:
 * - Top toolbar accompanying the window with drag, close, stop screensharing pill,
 *   and toggle for --flex-display vs normal mode.
 * - Toolbar and resize controls are only visible on the workspace where scrcpy is located.
 * - Normal mode: opens as a floating window resized to exact phone dimensions,
 *   with resizable corner indicator.
 * - Flex display mode: opens in tiling mode (virtual secondary display),
 *   without resize indicator.
 * - Support for Bluetooth/custom device images matched by name.
 * - Clean borderless styling for the controls overlay.
 */
Scope {
    id: root

    Variants {
        model: Quickshell.screens

        delegate: Scope {
            id: screenScope
            required property ShellScreen modelData

            PanelWindow {
                id: controlsWindow

                readonly property string screenName: controlsWindow.screen?.name ?? ""

                readonly property var monitor: {
                    for (const candidate of (HyprlandData.monitors ?? [])) {
                        if (String(candidate?.name ?? "") === controlsWindow.screenName)
                            return candidate;
                    }
                    return null;
                }

                /**
                 * Target scrcpy / phone mirror window on this monitor and active workspace.
                 */
                readonly property var target: {
                    const clients = HyprlandData.windowList ?? [];
                    const activeWs = controlsWindow.monitor?.activeWorkspace?.id
                        ?? (Hyprland.monitorFor(controlsWindow.screen)?.activeWorkspace?.id ?? -1);

                    for (const client of clients) {
                        if (!client || client.fullscreen)
                            continue;
                        const isScrcpy = String(client.class ?? "").toLowerCase() === "scrcpy"
                            || String(client.title ?? "").startsWith("ii-phone-mirror-")
                            || String(client.title ?? "").toLowerCase().includes("scrcpy");
                        if (!isScrcpy)
                            continue;
                        const clientMonitor = TabletWindowActions.monitorForClient(client);
                        if (String(clientMonitor?.name ?? "") !== controlsWindow.screenName)
                            continue;
                        const clientWs = Number(client?.workspace?.id ?? -2);
                        if (activeWs !== -1 && clientWs !== -2 && clientWs !== activeWs)
                            continue;
                        return client;
                    }
                    return null;
                }

                readonly property string targetAddress: TabletWindowActions.normalizeAddress(controlsWindow.target?.address)

                readonly property bool shellSurfaceOpen: GlobalStates.screenLocked

                readonly property bool shown: controlsWindow.target !== null && !controlsWindow.shellSurfaceOpen

                property bool isFlexDisplay: Boolean(Config.options?.phone?.scrcpy?.appMode?.flexDisplay)
                property bool controlsExpanded: false

                /**
                 * Resolve device image:
                 * 1. User custom images in bluetoothDeviceImages
                 * 2. BluetoothStatus matched friendly device image
                 * 3. Catalog match from BluetoothDeviceImages service (e.g. S23, S24)
                 */
                readonly property string deviceImageSource: {
                    const devName = (KdeConnectService.activeDeviceDisplayName || "").toLowerCase();
                    const images = Config.options?.bluetoothDeviceImages || [];
                    const imageFor = mac => {
                        for (let i = 0; i < images.length; i++) {
                            if (images[i].mac === mac && images[i].image)
                                return images[i].image;
                        }
                        return "";
                    };

                    const devices = BluetoothStatus.friendlyDeviceList || [];
                    for (let i = 0; i < devices.length; i++) {
                        const d = devices[i];
                        const btName = (d.name || "").toLowerCase();
                        if (devName !== "" && btName !== "" && (btName === devName || btName.includes(devName) || devName.includes(btName))) {
                            const custom = imageFor(d.address);
                            if (custom !== "")
                                return "file://" + Directories.shellConfig + "/bluetooth_images/" + custom;
                            const builtIn = BluetoothDeviceImages.sourceFor(d);
                            if (builtIn !== "")
                                return builtIn;
                        }
                    }

                    for (let i = 0; i < images.length; i++) {
                        if (images[i].name && devName !== "" && images[i].name.toLowerCase().includes(devName) && images[i].image)
                            return "file://" + Directories.shellConfig + "/bluetooth_images/" + images[i].image;
                    }

                    if (devName !== "") {
                        const direct = BluetoothDeviceImages.sourceFor({ name: KdeConnectService.activeDeviceDisplayName });
                        if (direct !== "")
                            return direct;
                    }

                    return "";
                }

                // ── Geometry in surface coordinates ─────────────────────
                readonly property real windowX: (Number(controlsWindow.target?.at?.[0] ?? 0))
                    - Number(controlsWindow.monitor?.x ?? 0)
                readonly property real windowY: (Number(controlsWindow.target?.at?.[1] ?? 0))
                    - Number(controlsWindow.monitor?.y ?? 0)
                readonly property real windowWidth: Number(controlsWindow.target?.size?.[0] ?? 0)
                readonly property real windowHeight: Number(controlsWindow.target?.size?.[1] ?? 0)

                readonly property real stripHeight: Math.max(Appearance.sizes.minimumTouchTarget, 40)
                readonly property real handleSize: Math.max(Appearance.sizes.minimumTouchTarget, 36)
                readonly property real gap: 6

                readonly property bool stripAbove: controlsWindow.windowY - controlsWindow.stripHeight - controlsWindow.gap >= 0

                anchors {
                    top: true
                    bottom: true
                    left: true
                    right: true
                }
                color: "transparent"
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.namespace: "quickshell:phoneWindowControls"
                WlrLayershell.layer: WlrLayer.Top
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

                visible: !GlobalStates.screenLocked && controlsWindow.shown

                // Only the strip and resize handle capture mouse input; scrcpy itself receives all inside clicks
                mask: Region {
                    regions: [stripRegion, handleRegion]
                }

                Region {
                    id: stripRegion
                    item: strip
                    intersection: controlsWindow.shown ? Intersection.Combine : Intersection.Subtract
                }

                Region {
                    id: handleRegion
                    item: resizeHandle
                    intersection: (controlsWindow.shown && !controlsWindow.isFlexDisplay && Boolean(controlsWindow.target?.floating))
                        ? Intersection.Combine : Intersection.Subtract
                }

                property real dragX: -1
                property real dragY: -1
                property real liveWidth: -1
                property real liveHeight: -1

                property real pendingX: -1
                property real pendingY: -1
                property real pendingWidth: -1
                property real pendingHeight: -1

                readonly property real effectiveX: WindowGeometry.effective(
                    controlsWindow.dragX, controlsWindow.pendingX, controlsWindow.windowX)
                readonly property real effectiveY: WindowGeometry.effective(
                    controlsWindow.dragY, controlsWindow.pendingY, controlsWindow.windowY)
                readonly property real effectiveWidth: WindowGeometry.effective(
                    controlsWindow.liveWidth, controlsWindow.pendingWidth, controlsWindow.windowWidth)
                readonly property real effectiveHeight: WindowGeometry.effective(
                    controlsWindow.liveHeight, controlsWindow.pendingHeight, controlsWindow.windowHeight)

                readonly property bool dragging: controlsWindow.dragX >= 0 || controlsWindow.liveWidth >= 0

                function clearPending() {
                    settleTimeout.stop();
                    controlsWindow.pendingX = -1;
                    controlsWindow.pendingY = -1;
                    controlsWindow.pendingWidth = -1;
                    controlsWindow.pendingHeight = -1;
                }

                onWindowXChanged: controlsWindow.settleIfReported()
                onWindowYChanged: controlsWindow.settleIfReported()
                onWindowWidthChanged: controlsWindow.settleIfReported()
                onWindowHeightChanged: controlsWindow.settleIfReported()

                function settleIfReported() {
                    if (controlsWindow.pendingX < 0 && controlsWindow.pendingY < 0
                            && controlsWindow.pendingWidth < 0 && controlsWindow.pendingHeight < 0)
                        return;
                    const reported = {
                        x: controlsWindow.windowX,
                        y: controlsWindow.windowY,
                        width: controlsWindow.windowWidth,
                        height: controlsWindow.windowHeight
                    };
                    const pending = {
                        x: controlsWindow.pendingX,
                        y: controlsWindow.pendingY,
                        width: controlsWindow.pendingWidth,
                        height: controlsWindow.pendingHeight
                    };
                    if (WindowGeometry.geometrySettled(reported, pending))
                        controlsWindow.clearPending();
                }

                Timer {
                    id: settleTimeout
                    interval: 600
                    repeat: false
                    onTriggered: controlsWindow.clearPending()
                }

                property string lastManagedAddress: ""
                onTargetAddressChanged: {
                    controlsWindow.clearPending();
                    if (controlsWindow.targetAddress.length > 0 && controlsWindow.targetAddress !== controlsWindow.lastManagedAddress) {
                        controlsWindow.lastManagedAddress = controlsWindow.targetAddress;
                        controlsWindow.initializeWindowGeometry();
                    }
                }

                function initializeWindowGeometry() {
                    if (!controlsWindow.target || controlsWindow.targetAddress.length === 0)
                        return;

                    if (controlsWindow.isFlexDisplay) {
                        // Flex display mode: Virtual secondary display (DeX/desktop style) -> TILING
                        if (controlsWindow.target.floating) {
                            TabletWindowActions.setFloating(controlsWindow.targetAddress, false);
                            TabletWindowActions.requestGeometryRefresh();
                        }
                    } else {
                        // Normal mode: Phone screen mirroring -> FLOATING with exact phone dimensions & aspect ratio
                        if (!controlsWindow.target.floating) {
                            TabletWindowActions.setFloating(controlsWindow.targetAddress, true);
                        }

                        const screenW = controlsWindow.screen?.width ?? 1920;
                        const screenH = controlsWindow.screen?.height ?? 1080;
                        const devW = PhoneMirrorService.deviceWidth;
                        const devH = PhoneMirrorService.deviceHeight;
                        const aspect = (devW > 0 && devH > 0) ? (devW / devH) : PhoneMirrorService.deviceAspect;

                        // Match exact phone dimensions, scaled if needed to fit comfortably on screen
                        let targetH = (devH > 0) ? devH : Math.round(screenH * 0.75);
                        const maxH = Math.round(screenH * 0.82);
                        if (targetH > maxH) {
                            targetH = maxH;
                        }
                        let targetW = Math.round(targetH * aspect);
                        if (targetW > Math.round(screenW * 0.9)) {
                            targetW = Math.round(screenW * 0.9);
                            targetH = Math.round(targetW / aspect);
                        }

                        const originX = Math.round((screenW - targetW) / 2) + Number(controlsWindow.monitor?.x ?? 0);
                        const originY = Math.round((screenH - targetH) / 2) + Number(controlsWindow.monitor?.y ?? 0);

                        TabletWindowActions.setGeometry(controlsWindow.targetAddress, originX, originY, targetW, targetH);
                        controlsWindow.pendingX = originX - Number(controlsWindow.monitor?.x ?? 0);
                        controlsWindow.pendingY = originY - Number(controlsWindow.monitor?.y ?? 0);
                        controlsWindow.pendingWidth = targetW;
                        controlsWindow.pendingHeight = targetH;
                        settleTimeout.restart();
                        TabletWindowActions.requestGeometryRefresh();
                    }
                }

                Timer {
                    id: commitTimer
                    interval: 16
                    repeat: false
                    property bool geometryPending: false
                    onTriggered: {
                        if (controlsWindow.targetAddress.length === 0)
                            return;
                        const originX = controlsWindow.effectiveX + Number(controlsWindow.monitor?.x ?? 0);
                        const originY = controlsWindow.effectiveY + Number(controlsWindow.monitor?.y ?? 0);
                        if (commitTimer.geometryPending) {
                            TabletWindowActions.setGeometry(controlsWindow.targetAddress, originX, originY,
                                                            controlsWindow.effectiveWidth,
                                                            controlsWindow.effectiveHeight);
                        } else {
                            TabletWindowActions.moveTo(controlsWindow.targetAddress, originX, originY);
                        }
                    }
                }

                function commitMove() {
                    commitTimer.geometryPending = false;
                    if (!commitTimer.running)
                        commitTimer.start();
                }

                function commitGeometry() {
                    commitTimer.geometryPending = true;
                    if (!commitTimer.running)
                        commitTimer.start();
                }

                function endDrag() {
                    commitTimer.stop();
                    const finalX = controlsWindow.effectiveX;
                    const finalY = controlsWindow.effectiveY;
                    const resized = controlsWindow.liveWidth >= 0 || controlsWindow.liveHeight >= 0;
                    const finalWidth = controlsWindow.effectiveWidth;
                    const finalHeight = controlsWindow.effectiveHeight;

                    controlsWindow.dragX = -1;
                    controlsWindow.dragY = -1;
                    controlsWindow.liveWidth = -1;
                    controlsWindow.liveHeight = -1;

                    if (controlsWindow.targetAddress.length === 0) {
                        controlsWindow.clearPending();
                        return;
                    }

                    const originX = finalX + Number(controlsWindow.monitor?.x ?? 0);
                    const originY = finalY + Number(controlsWindow.monitor?.y ?? 0);
                    if (resized) {
                        TabletWindowActions.setGeometry(controlsWindow.targetAddress, originX, originY,
                                                        finalWidth, finalHeight);
                    } else {
                        TabletWindowActions.moveTo(controlsWindow.targetAddress, originX, originY);
                    }

                    controlsWindow.pendingX = finalX;
                    controlsWindow.pendingY = finalY;
                    controlsWindow.pendingWidth = resized ? finalWidth : -1;
                    controlsWindow.pendingHeight = resized ? finalHeight : -1;
                    settleTimeout.restart();
                    TabletWindowActions.requestGeometryRefresh();
                }

                // ── The Toolbar accompanying the window ─────────────────
                Rectangle {
                    id: strip
                    x: controlsWindow.isFlexDisplay
                        ? controlsWindow.effectiveX + Math.round((controlsWindow.effectiveWidth - strip.width) / 2)
                        : controlsWindow.effectiveX
                    y: controlsWindow.stripAbove
                        ? controlsWindow.effectiveY - controlsWindow.stripHeight - controlsWindow.gap
                        : controlsWindow.effectiveY + controlsWindow.gap
                    width: controlsWindow.isFlexDisplay
                        ? Math.min(controlsWindow.effectiveWidth - 16, 440)
                        : controlsWindow.effectiveWidth
                    height: controlsWindow.stripHeight
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colLayer1

                    Behavior on x {
                        enabled: !controlsWindow.dragging
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(strip)
                    }
                    Behavior on y {
                        enabled: !controlsWindow.dragging
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(strip)
                    }
                    Behavior on width {
                        enabled: !controlsWindow.dragging
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(strip)
                    }
                    visible: controlsWindow.shown
                    opacity: controlsWindow.shown ? 1 : 0

                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(strip)
                    }

                    // Drag handle region across the toolbar (No hover background effect)
                    MouseArea {
                        id: stripDrag
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.right: stripButtons.left
                        cursorShape: Qt.SizeAllCursor

                        property real pressGlobalX: 0
                        property real pressGlobalY: 0
                        property real originX: 0
                        property real originY: 0

                        onPressed: mouse => {
                            const point = stripDrag.mapToItem(null, mouse.x, mouse.y);
                            stripDrag.pressGlobalX = point.x;
                            stripDrag.pressGlobalY = point.y;
                            stripDrag.originX = controlsWindow.effectiveX;
                            stripDrag.originY = controlsWindow.effectiveY;
                            controlsWindow.clearPending();
                            controlsWindow.dragX = stripDrag.originX;
                            controlsWindow.dragY = stripDrag.originY;
                        }

                        onPositionChanged: mouse => {
                            if (!stripDrag.pressed)
                                return;
                            const point = stripDrag.mapToItem(null, mouse.x, mouse.y);
                            controlsWindow.dragX = stripDrag.originX + (point.x - stripDrag.pressGlobalX);
                            controlsWindow.dragY = stripDrag.originY + (point.y - stripDrag.pressGlobalY);
                            controlsWindow.commitMove();
                        }

                        onReleased: controlsWindow.endDrag()
                        onCanceled: controlsWindow.endDrag()
                    }

                    // Drag dots icon with larger left margin than vertical margin
                    MaterialSymbol {
                        id: dragIcon
                        anchors.left: parent.left
                        anchors.leftMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        text: "drag_indicator"
                        iconSize: Math.round(controlsWindow.stripHeight * 0.5)
                        color: Appearance.colors.colOnLayer1
                        opacity: 0.6
                    }

                    // Phone icon with fill 1 or custom device image
                    Item {
                        id: deviceVisual
                        anchors.left: dragIcon.right
                        anchors.leftMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.round(controlsWindow.stripHeight * 0.55)
                        height: Math.round(controlsWindow.stripHeight * 0.55)

                        Image {
                            id: deviceImg
                            anchors.fill: parent
                            source: controlsWindow.deviceImageSource
                            fillMode: Image.PreserveAspectFit
                            visible: controlsWindow.deviceImageSource !== "" && status === Image.Ready
                            mipmap: true
                            smooth: true
                        }

                        MaterialSymbol {
                            id: phoneIcon
                            anchors.centerIn: parent
                            text: "smartphone"
                            fill: 1
                            iconSize: Math.round(controlsWindow.stripHeight * 0.5)
                            color: Appearance.colors.colPrimary
                            visible: !deviceImg.visible
                        }
                    }

                    StyledText {
                        id: titleLabel
                        anchors.left: deviceVisual.right
                        anchors.leftMargin: 8
                        anchors.right: stripButtons.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: KdeConnectService.activeDeviceDisplayName || Translation.tr("Phone")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer1
                        elide: Text.ElideRight
                    }

                    RowLayout {
                        id: stripButtons
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4

                        // Toggle button to expand/collapse device controls vs window controls
                        TabletWindowControlButton {
                            id: expandControlsToggle
                            symbol: controlsWindow.controlsExpanded ? "chevron_right" : "more_horiz"
                            controlSize: controlsWindow.stripHeight - 10
                            colBackground: controlsWindow.controlsExpanded
                                ? Appearance.colors.colSecondaryContainer
                                : "transparent"
                            colBackgroundHover: controlsWindow.controlsExpanded
                                ? Appearance.colors.colSecondaryContainer
                                : Appearance.colors.colLayer2Hover
                            scale: pressed ? 0.90 : (hovered ? 1.08 : 1.0)

                            Behavior on scale {
                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(expandControlsToggle)
                            }
                            Behavior on colBackground {
                                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(expandControlsToggle)
                            }

                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                text: controlsWindow.controlsExpanded ? "chevron_right" : "more_horiz"
                                iconSize: Math.round((controlsWindow.stripHeight - 10) * 0.55)
                                color: controlsWindow.controlsExpanded
                                    ? Appearance.colors.colOnSecondaryContainer
                                    : Appearance.colors.colOnLayer1
                            }

                            StyledToolTip {
                                requireOverlay: false
                                text: controlsWindow.controlsExpanded
                                    ? Translation.tr("Window controls")
                                    : Translation.tr("Device controls")
                            }

                            releaseAction: () => {
                                controlsWindow.controlsExpanded = !controlsWindow.controlsExpanded;
                            }
                        }

                        // ── Standard window controls (Shown when !controlsExpanded) ──
                        RowLayout {
                            id: standardControls
                            visible: !controlsWindow.controlsExpanded
                            spacing: 4

                            // Toggle --flex-display vs Normal mode
                            TabletWindowControlButton {
                                id: flexDisplayButton
                                symbol: controlsWindow.isFlexDisplay ? "desktop_windows" : "smartphone"
                                controlSize: controlsWindow.stripHeight - 10
                                colBackground: controlsWindow.isFlexDisplay
                                    ? Appearance.colors.colSecondaryContainer
                                    : Appearance.colors.colPrimaryContainer
                                colBackgroundHover: controlsWindow.isFlexDisplay
                                    ? Appearance.colors.colSecondaryContainer
                                    : Appearance.colors.colPrimaryContainer
                                scale: pressed ? 0.90 : (hovered ? 1.08 : 1.0)

                                Behavior on scale {
                                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(flexDisplayButton)
                                }
                                Behavior on colBackground {
                                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(flexDisplayButton)
                                }

                                contentItem: MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: controlsWindow.isFlexDisplay ? "desktop_windows" : "smartphone"
                                    fill: 1
                                    iconSize: Math.round((controlsWindow.stripHeight - 10) * 0.5)
                                    color: controlsWindow.isFlexDisplay
                                        ? Appearance.colors.colOnSecondaryContainer
                                        : Appearance.colors.colOnPrimaryContainer
                                }

                                StyledToolTip {
                                    requireOverlay: false
                                    text: controlsWindow.isFlexDisplay
                                        ? Translation.tr("Flex Display (PC)")
                                        : Translation.tr("Normal mode (Phone)")
                                }

                                releaseAction: () => {
                                    const current = Boolean(Config.options?.phone?.scrcpy?.appMode?.flexDisplay);
                                    Config.options.phone.scrcpy.appMode.flexDisplay = !current;
                                    controlsWindow.lastManagedAddress = "";
                                    controlsWindow.clearPending();
                                    if (PhoneScrcpyService.mirrorRunning) {
                                        PhoneScrcpyService.restartMirror();
                                    } else {
                                        PhoneScrcpyService.launchMirror();
                                    }
                                }
                            }

                            // Stop screensharing button
                            RippleButton {
                                id: stopButton
                                implicitHeight: controlsWindow.stripHeight - 10
                                implicitWidth: stopContent.implicitWidth + 16
                                buttonRadius: Appearance.rounding.full
                                colBackground: "transparent"
                                colBackgroundHover: Appearance.colors.colLayer2Hover
                                colBackgroundActive: Appearance.colors.colLayer2Active
                                borderWidth: 1
                                borderColor: Appearance.colors.colOutline
                                scale: pressed ? 0.94 : (hovered ? 1.04 : 1.0)

                                Behavior on scale {
                                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(stopButton)
                                }

                                contentItem: RowLayout {
                                    id: stopContent
                                    spacing: 6
                                    anchors.centerIn: parent

                                    MaterialSymbol {
                                        text: "stop_screen_share"
                                        iconSize: Math.round((controlsWindow.stripHeight - 10) * 0.5)
                                        color: Appearance.colors.colPrimary
                                    }
                                }

                                StyledToolTip {
                                    requireOverlay: false
                                    text: Translation.tr("Stop screensharing (scrcpy)")
                                }

                                releaseAction: () => {
                                    PhoneScrcpyService.stopMirror();
                                }
                            }

                            // Close button with colErrorContainer always visible
                            TabletWindowControlButton {
                                id: closeButton
                                symbol: "close"
                                controlSize: controlsWindow.stripHeight - 10
                                colBackground: Appearance.colors.colErrorContainer
                                colBackgroundHover: Appearance.colors.colErrorContainer
                                scale: pressed ? 0.90 : (hovered ? 1.08 : 1.0)

                                Behavior on scale {
                                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(closeButton)
                                }

                                contentItem: MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "close"
                                    iconSize: Math.round((controlsWindow.stripHeight - 10) * 0.5)
                                    color: Appearance.colors.colOnErrorContainer
                                }

                                StyledToolTip {
                                    requireOverlay: false
                                    text: Translation.tr("Close")
                                }

                                releaseAction: () => {
                                    TabletWindowActions.closeWindow(controlsWindow.targetAddress);
                                    PhoneScrcpyService.stopMirror();
                                }
                            }
                        }

                        // ── Device controls (Shown when controlsExpanded) ──
                        RowLayout {
                            id: deviceControls
                            visible: controlsWindow.controlsExpanded
                            spacing: 4

                            // Back
                            TabletWindowControlButton {
                                symbol: "arrow_back_ios_new"
                                controlSize: controlsWindow.stripHeight - 10
                                scale: pressed ? 0.90 : (hovered ? 1.08 : 1.0)
                                Behavior on scale {
                                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                                }
                                StyledToolTip {
                                    requireOverlay: false
                                    text: Translation.tr("Back")
                                }
                                releaseAction: () => PhoneMirrorService.goBack()
                            }

                            // Home
                            TabletWindowControlButton {
                                symbol: "circle"
                                controlSize: controlsWindow.stripHeight - 10
                                scale: pressed ? 0.90 : (hovered ? 1.08 : 1.0)
                                Behavior on scale {
                                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                                }
                                StyledToolTip {
                                    requireOverlay: false
                                    text: Translation.tr("Home")
                                }
                                releaseAction: () => PhoneMirrorService.goHome()
                            }

                            // Recents
                            TabletWindowControlButton {
                                symbol: "square"
                                controlSize: controlsWindow.stripHeight - 10
                                scale: pressed ? 0.90 : (hovered ? 1.08 : 1.0)
                                Behavior on scale {
                                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                                }
                                StyledToolTip {
                                    requireOverlay: false
                                    text: Translation.tr("Recents")
                                }
                                releaseAction: () => PhoneMirrorService.goRecents()
                            }

                            // Volume down
                            TabletWindowControlButton {
                                symbol: "volume_down"
                                controlSize: controlsWindow.stripHeight - 10
                                scale: pressed ? 0.90 : (hovered ? 1.08 : 1.0)
                                Behavior on scale {
                                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                                }
                                StyledToolTip {
                                    requireOverlay: false
                                    text: Translation.tr("Volume down")
                                }
                                releaseAction: () => PhoneMirrorService.volumeDown()
                            }

                            // Volume up
                            TabletWindowControlButton {
                                symbol: "volume_up"
                                controlSize: controlsWindow.stripHeight - 10
                                scale: pressed ? 0.90 : (hovered ? 1.08 : 1.0)
                                Behavior on scale {
                                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                                }
                                StyledToolTip {
                                    requireOverlay: false
                                    text: Translation.tr("Volume up")
                                }
                                releaseAction: () => PhoneMirrorService.volumeUp()
                            }

                            // Notifications
                            TabletWindowControlButton {
                                symbol: "expand_more"
                                controlSize: controlsWindow.stripHeight - 10
                                scale: pressed ? 0.90 : (hovered ? 1.08 : 1.0)
                                Behavior on scale {
                                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                                }
                                StyledToolTip {
                                    requireOverlay: false
                                    text: Translation.tr("Notifications")
                                }
                                releaseAction: () => PhoneMirrorService.openNotifications()
                            }

                            // Power
                            TabletWindowControlButton {
                                symbol: "power_settings_new"
                                controlSize: controlsWindow.stripHeight - 10
                                scale: pressed ? 0.90 : (hovered ? 1.08 : 1.0)
                                Behavior on scale {
                                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                                }
                                StyledToolTip {
                                    requireOverlay: false
                                    text: Translation.tr("Power")
                                }
                                releaseAction: () => PhoneMirrorService.togglePower()
                            }
                        }
                    }
                }

                // ── The corner resize handle (Only shown in Normal Floating Mode) ──
                Rectangle {
                    id: resizeHandle
                    x: controlsWindow.effectiveX + controlsWindow.effectiveWidth - controlsWindow.handleSize * 0.6
                    y: controlsWindow.effectiveY + controlsWindow.effectiveHeight - controlsWindow.handleSize * 0.6
                    width: controlsWindow.handleSize
                    height: controlsWindow.handleSize
                    radius: Appearance.rounding.full
                    color: resizeDrag.pressed
                        ? Appearance.colors.colPrimary
                        : (resizeDrag.containsMouse ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer1)
                    scale: resizeDrag.pressed ? 0.92 : (resizeDrag.containsMouse ? 1.14 : 1.0)

                    Behavior on scale {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(resizeHandle)
                    }
                    Behavior on x {
                        enabled: !controlsWindow.dragging
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(resizeHandle)
                    }
                    Behavior on y {
                        enabled: !controlsWindow.dragging
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(resizeHandle)
                    }
                    visible: controlsWindow.shown && !controlsWindow.isFlexDisplay && Boolean(controlsWindow.target?.floating)
                    opacity: (controlsWindow.shown && !controlsWindow.isFlexDisplay && Boolean(controlsWindow.target?.floating)) ? 1 : 0

                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(resizeHandle)
                    }
                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(resizeHandle)
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "south_east"
                        iconSize: Math.round(controlsWindow.handleSize * 0.45)
                        color: resizeDrag.pressed
                            ? Appearance.m3colors.m3onPrimary
                            : (resizeDrag.containsMouse ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer1)
                        Behavior on color {
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                        }
                    }

                    MouseArea {
                        id: resizeDrag
                        anchors.fill: parent
                        cursorShape: Qt.SizeFDiagCursor
                        hoverEnabled: true

                        property real pressGlobalX: 0
                        property real pressGlobalY: 0
                        property real originWidth: 0
                        property real originHeight: 0

                        StyledToolTip {
                            requireOverlay: false
                            text: Translation.tr("Drag to resize phone mirror")
                        }

                        onPressed: mouse => {
                            const point = resizeDrag.mapToItem(null, mouse.x, mouse.y);
                            resizeDrag.pressGlobalX = point.x;
                            resizeDrag.pressGlobalY = point.y;
                            resizeDrag.originWidth = controlsWindow.effectiveWidth;
                            resizeDrag.originHeight = controlsWindow.effectiveHeight;
                            const heldX = controlsWindow.effectiveX;
                            const heldY = controlsWindow.effectiveY;
                            controlsWindow.clearPending();
                            controlsWindow.dragX = heldX;
                            controlsWindow.dragY = heldY;
                            controlsWindow.liveWidth = resizeDrag.originWidth;
                            controlsWindow.liveHeight = resizeDrag.originHeight;
                        }

                        onPositionChanged: mouse => {
                            if (!resizeDrag.pressed)
                                return;
                            const point = resizeDrag.mapToItem(null, mouse.x, mouse.y);
                            controlsWindow.liveWidth = Math.max(TabletWindowActions.minimumWidth,
                                resizeDrag.originWidth + (point.x - resizeDrag.pressGlobalX));
                            controlsWindow.liveHeight = Math.max(TabletWindowActions.minimumHeight,
                                resizeDrag.originHeight + (point.y - resizeDrag.pressGlobalY));
                            controlsWindow.commitGeometry();
                        }

                        onReleased: controlsWindow.endDrag()
                        onCanceled: controlsWindow.endDrag()
                    }
                }
            }
        }
    }
}

