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
                screen: screenScope.modelData

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
                        // Only the mirror window. Every scrcpy window has the
                        // class "scrcpy", including the sidebar's embedded one
                        // parked off-screen and the throwaway unlock mirror —
                        // matching on the class dragged those into view.
                        const title = String(client.title ?? "");
                        const isMirror = title.startsWith("ii-phone-mirror-")
                            || title.startsWith("ii scrcpy");
                        if (!isMirror)
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
                readonly property string deviceImageSource: BluetoothDeviceImages.sourceForPhone(KdeConnectService.activeDeviceDisplayName)

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

                readonly property bool stripAbove: controlsWindow.effectiveY - controlsWindow.stripHeight - controlsWindow.gap >= 0

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
                property bool userAdjustedGeometry: false
                property bool _pendingOrientationRefit: false

                onTargetAddressChanged: {
                    controlsWindow.clearPending();
                    controlsWindow._pendingOrientationRefit = false;
                    if (controlsWindow.targetAddress.length === 0) {
                        controlsWindow.userAdjustedGeometry = false;
                        return;
                    }
                    if (controlsWindow.targetAddress !== controlsWindow.lastManagedAddress) {
                        controlsWindow.lastManagedAddress = controlsWindow.targetAddress;
                        controlsWindow.userAdjustedGeometry = false;
                        HyprlandData.updateMonitors();
                        controlsWindow.initializeWindowGeometry();
                    }
                }

                // The phone's resolution is read over adb when the mirror is
                // asked for and can land after the window does; the window is
                // cropped again with it rather than left at the fallback aspect.
                // A rotation (scrcpy's video size, via PhoneMirrorService.mirrorAspect)
                // refits the window in place.
                Connections {
                    target: PhoneMirrorService
                    function onDeviceHeightChanged() {
                        if (!controlsWindow.dragging && !controlsWindow.userAdjustedGeometry
                                && controlsWindow.targetAddress.length > 0)
                            controlsWindow.initializeWindowGeometry();
                    }
                    function onMirrorAspectChanged() {
                        if (controlsWindow.targetAddress.length === 0)
                            return;
                        if (controlsWindow.dragging) {
                            controlsWindow._pendingOrientationRefit = true;
                            return;
                        }
                        controlsWindow.refitForOrientation();
                    }
                }

                function usableBounds() {
                    const screenW = controlsWindow.screen?.width ?? 1920;
                    const screenH = controlsWindow.screen?.height ?? 1080;
                    const area = TabletWindowActions.usableArea(controlsWindow.monitor);
                    if (!area || area.width <= 0 || area.height <= 0)
                        return { minX: 0, minY: 0, width: screenW, height: screenH };
                    const monX = Number(controlsWindow.monitor?.x ?? 0);
                    const monY = Number(controlsWindow.monitor?.y ?? 0);
                    return {
                        minX: area.x - monX,
                        minY: area.y - monY,
                        width: area.width,
                        height: area.height
                    };
                }

                function fitSizeToBounds(targetW, targetH, aspect, bounds) {
                    const safeAspect = (aspect > 0) ? aspect : (9 / 20);
                    const stripReserve = controlsWindow.stripHeight + controlsWindow.gap;
                    const availH = Math.max(TabletWindowActions.minimumHeight,
                        bounds.height - (bounds.height > stripReserve + TabletWindowActions.minimumHeight ? stripReserve : 0));
                    const maxW = Math.max(TabletWindowActions.minimumWidth, Math.round(bounds.width * 0.94));
                    const maxH = Math.max(TabletWindowActions.minimumHeight, Math.round(availH * 0.94));

                    let w = Math.max(TabletWindowActions.minimumWidth, Math.round(targetW));
                    let h = Math.max(TabletWindowActions.minimumHeight, Math.round(w / safeAspect));

                    if (w > maxW) {
                        w = maxW;
                        h = Math.round(w / safeAspect);
                    }
                    if (h > maxH) {
                        h = maxH;
                        w = Math.round(h * safeAspect);
                    }
                    if (w < TabletWindowActions.minimumWidth) {
                        w = TabletWindowActions.minimumWidth;
                        h = Math.round(w / safeAspect);
                    }
                    if (h < TabletWindowActions.minimumHeight) {
                        h = TabletWindowActions.minimumHeight;
                        w = Math.round(h * safeAspect);
                    }
                    return { width: w, height: h };
                }

                function clampOriginToBounds(localX, localY, w, h, bounds) {
                    const stripReserve = controlsWindow.stripHeight + controlsWindow.gap;
                    const minY = bounds.minY + (h + stripReserve <= bounds.height ? stripReserve : 0);
                    const maxX = bounds.minX + Math.max(0, bounds.width - w);
                    const maxY = bounds.minY + Math.max(0, bounds.height - h);
                    return {
                        x: Math.round(Math.max(bounds.minX, Math.min(maxX, localX))),
                        y: Math.round(Math.max(minY, Math.min(maxY, localY)))
                    };
                }

                function applyWindowGeometry(localX, localY, w, h) {
                    const originX = localX + Number(controlsWindow.monitor?.x ?? 0);
                    const originY = localY + Number(controlsWindow.monitor?.y ?? 0);
                    TabletWindowActions.setGeometry(controlsWindow.targetAddress, originX, originY, w, h);
                    controlsWindow.pendingX = localX;
                    controlsWindow.pendingY = localY;
                    controlsWindow.pendingWidth = w;
                    controlsWindow.pendingHeight = h;
                    settleTimeout.restart();
                    TabletWindowActions.requestGeometryRefresh();
                }

                function aspectLockedResize(rawW, rawH, aspect, curX, curY) {
                    const safeAspect = (aspect > 0) ? aspect : (9 / 20);
                    const bounds = controlsWindow.usableBounds();
                    const minH = Math.max(TabletWindowActions.minimumHeight,
                        Math.ceil(TabletWindowActions.minimumWidth / safeAspect));
                    const maxAvailW = Math.max(TabletWindowActions.minimumWidth, (bounds.minX + bounds.width) - curX);
                    const maxAvailH = Math.max(TabletWindowActions.minimumHeight, (bounds.minY + bounds.height) - curY);
                    const maxH = Math.max(minH, Math.min(maxAvailH, Math.floor(maxAvailW / safeAspect)));

                    // Project cursor delta onto the aspect diagonal so horizontal,
                    // vertical, and diagonal drags all track smoothly without jumping.
                    const projectedH = (rawW * safeAspect + rawH) / (safeAspect * safeAspect + 1);
                    let h = Math.round(Math.max(minH, Math.min(maxH, projectedH)));
                    let w = Math.round(h * safeAspect);

                    if (w < TabletWindowActions.minimumWidth) {
                        w = TabletWindowActions.minimumWidth;
                        h = Math.round(w / safeAspect);
                    }
                    if (h < TabletWindowActions.minimumHeight) {
                        h = TabletWindowActions.minimumHeight;
                        w = Math.round(h * safeAspect);
                    }
                    return { width: w, height: h };
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
                        return;
                    }

                    // Normal mode: Phone screen mirroring -> FLOATING with exact phone dimensions & aspect ratio
                    if (!controlsWindow.target.floating) {
                        TabletWindowActions.setFloating(controlsWindow.targetAddress, true);
                    }

                    const bounds = controlsWindow.usableBounds();
                    const stripReserve = controlsWindow.stripHeight + controlsWindow.gap;
                    const availH = Math.max(TabletWindowActions.minimumHeight, bounds.height - stripReserve);
                    const devW = PhoneMirrorService.mirrorWidth;
                    const devH = PhoneMirrorService.mirrorHeight;
                    const aspect = PhoneMirrorService.mirrorAspect;

                    const maxLongSide = Math.round(Math.min(bounds.width * 0.9, availH * 0.85));
                    const naturalLong = (devW > 0 && devH > 0) ? Math.max(devW, devH) : maxLongSide;
                    const longSide = Math.min(naturalLong, maxLongSide);
                    const rawW = aspect >= 1 ? longSide : Math.round(longSide * aspect);
                    const rawH = aspect >= 1 ? Math.round(longSide / aspect) : longSide;

                    const fitted = controlsWindow.fitSizeToBounds(rawW, rawH, aspect, bounds);
                    const topMinY = bounds.minY + (fitted.height + stripReserve <= bounds.height ? stripReserve : 0);
                    const centeredX = bounds.minX + (bounds.width - fitted.width) / 2;
                    const centeredY = topMinY + (bounds.height - (topMinY - bounds.minY) - fitted.height) / 2;
                    const origin = controlsWindow.clampOriginToBounds(centeredX, centeredY, fitted.width, fitted.height, bounds);

                    controlsWindow.applyWindowGeometry(origin.x, origin.y, fitted.width, fitted.height);
                }

                function refitForOrientation() {
                    if (!controlsWindow.target || controlsWindow.targetAddress.length === 0)
                        return;
                    if (controlsWindow.isFlexDisplay || !controlsWindow.target.floating)
                        return;

                    const curX = controlsWindow.effectiveX;
                    const curY = controlsWindow.effectiveY;
                    const curW = controlsWindow.effectiveWidth;
                    const curH = controlsWindow.effectiveHeight;
                    if (curW <= 0 || curH <= 0) {
                        controlsWindow.initializeWindowGeometry();
                        return;
                    }

                    const bounds = controlsWindow.usableBounds();
                    const aspect = PhoneMirrorService.mirrorAspect;
                    // Keep the same longest side (which also preserves area across 90° rotations).
                    const longSide = Math.max(curW, curH);
                    const rawW = aspect >= 1 ? longSide : Math.round(longSide * aspect);
                    const rawH = aspect >= 1 ? Math.round(longSide / aspect) : longSide;

                    const fitted = controlsWindow.fitSizeToBounds(rawW, rawH, aspect, bounds);
                    const centerX = curX + (curW - fitted.width) / 2;
                    const centerY = curY + (curH - fitted.height) / 2;
                    const origin = controlsWindow.clampOriginToBounds(centerX, centerY, fitted.width, fitted.height, bounds);

                    if (Math.abs(fitted.width - curW) <= 2 && Math.abs(fitted.height - curH) <= 2
                            && Math.abs(origin.x - curX) <= 2 && Math.abs(origin.y - curY) <= 2)
                        return;

                    controlsWindow.applyWindowGeometry(origin.x, origin.y, fitted.width, fitted.height);
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
                    controlsWindow.userAdjustedGeometry = true;
                    settleTimeout.restart();
                    TabletWindowActions.requestGeometryRefresh();

                    if (controlsWindow._pendingOrientationRefit) {
                        controlsWindow._pendingOrientationRefit = false;
                        controlsWindow.refitForOrientation();
                    }
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

                            // Record the phone screen to a file, beside the mirror
                            TabletWindowControlButton {
                                id: recordButton
                                readonly property bool recording: PhoneScrcpyService.recordingRunning || PhoneScrcpyService.recordingLaunching
                                symbol: recordButton.recording ? "stop_circle" : "radio_button_checked"
                                controlSize: controlsWindow.stripHeight - 10
                                colBackground: recordButton.recording
                                    ? Appearance.colors.colErrorContainer
                                    : Appearance.colors.colLayer2
                                colBackgroundHover: recordButton.recording
                                    ? Appearance.colors.colErrorContainer
                                    : Appearance.colors.colLayer2Hover
                                scale: pressed ? 0.90 : (hovered ? 1.08 : 1.0)

                                Behavior on scale {
                                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(recordButton)
                                }
                                Behavior on colBackground {
                                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(recordButton)
                                }

                                contentItem: MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: recordButton.symbol
                                    fill: 1
                                    iconSize: Math.round((controlsWindow.stripHeight - 10) * 0.5)
                                    color: recordButton.recording
                                        ? Appearance.colors.colOnErrorContainer
                                        : Appearance.colors.colError
                                }

                                StyledToolTip {
                                    requireOverlay: false
                                    text: PhoneScrcpyService.recordingRunning
                                        ? Translation.tr("Stop recording · %1").arg(PhoneScrcpyService._fmtDuration(PhoneScrcpyService.recordingElapsedMs))
                                        : PhoneScrcpyService.recordingLaunching
                                            ? Translation.tr("Starting recording…")
                                            : Translation.tr("Record the phone screen")
                                }

                                releaseAction: () => PhoneScrcpyService.toggleRecording()
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
                                    PhoneScrcpyService.stopMirroring();
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
                                    PhoneScrcpyService.stopMirroring();
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
                        property real dragAspect: 9 / 20

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
                            resizeDrag.dragAspect = PhoneMirrorService.mirrorAspect > 0
                                ? PhoneMirrorService.mirrorAspect
                                : (resizeDrag.originWidth / Math.max(1, resizeDrag.originHeight));
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
                            const rawW = resizeDrag.originWidth + (point.x - resizeDrag.pressGlobalX);
                            const rawH = resizeDrag.originHeight + (point.y - resizeDrag.pressGlobalY);
                            const sized = controlsWindow.aspectLockedResize(
                                rawW, rawH, resizeDrag.dragAspect,
                                controlsWindow.effectiveX, controlsWindow.effectiveY);
                            controlsWindow.liveWidth = sized.width;
                            controlsWindow.liveHeight = sized.height;
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

