pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.akebono
import qs.modules.akebono.menu
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root

    Variants {
        model: Quickshell.screens

        Scope {
            id: screenScope
            required property var modelData

            Loader {
                active: Config.options.akebono?.standaloneDock ?? false

                sourceComponent: PanelWindow {
                    id: dockRoot
                    readonly property var modelData: screenScope.modelData
                    screen: modelData
                    visible: !GlobalStates.screenLocked
                    color: "transparent"
                    WlrLayershell.namespace: "quickshell:dock"

                    readonly property real dockStripHeight: Config.options?.dock.height ?? 70
                    readonly property int tileSize: Math.round(dockStripHeight * 5 / 6)
                    readonly property int iconSize: Math.round(dockStripHeight * 0.6)
                    readonly property real dockScale: dockStripHeight / 60
                    readonly property real bumpRoom: 210 * dockScale
                    readonly property real previewW: 340 * dockScale
                    readonly property real previewInset: 8 * dockScale
                    readonly property real bottomGap: Appearance.sizes.hyprlandGapsOut
                    readonly property bool monitorFullscreen: fullscreenWatcher.active
                    MonitorFullscreen { id: fullscreenWatcher; screen: dockRoot.modelData }

                    WindowOcclusion {
                        id: dockOcclusion
                        screen: dockRoot.modelData
                        region: Qt.rect(
                            dockRoot.modelData.x + (dockRoot.modelData.width - dockStrip.width) / 2,
                            dockRoot.modelData.y + dockRoot.modelData.height - dockRoot.bottomGap - dockRoot.dockStripHeight,
                            dockStrip.width,
                            dockRoot.dockStripHeight)
                    }

                    readonly property var previewClient: HyprlandData.clientForToplevel(previewCard.toplevel)
                    readonly property real previewSrcW: (previewClient?.size?.[0] ?? 0) > 1 ? previewClient.size[0] : 16
                    readonly property real previewSrcH: (previewClient?.size?.[1] ?? 0) > 1 ? previewClient.size[1] : 9
                    readonly property real previewFit: Math.min(320 * dockScale / previewSrcW, 180 * dockScale / previewSrcH)
                    readonly property real thumbW: previewSrcW * previewFit
                    readonly property real thumbH: previewSrcH * previewFit

                    property bool pinned: Config.options?.dock.pinnedOnStartup ?? false
                    property bool reveal: dockRoot.pinned
                        || (Config.options?.dock.hoverToReveal && (hoverArea.containsMouse || dockStripHover.hovered))
                        || dockRoot.bumpProgress > 0.01
                        || keepAlive.hovered
                        || dockMenu.showing
                        || trashMenu.showing
                        || GlobalStates.desktopIconDragActive
                        || (Config.options?.dock.smartHide
                            ? !dockOcclusion.occluded
                            : !ToplevelManager.activeToplevel?.activated)
                    property real hideOffset: reveal ? 0 : (dockStripHeight + bottomGap)

                    property real bumpProgress: 0
                    property real bumpX: dockSurface.width / 2
                    property string bumpAppId: ""
                    readonly property var bumpEntry: dockRoot.bumpAppId !== ""
                        ? (TaskbarApps.apps.find(a => a.appId === dockRoot.bumpAppId) ?? null)
                        : null
                    property bool slideBump: true
                    property real waveX: 0
                    property real waveProgress: 1
                    property real waveAmp: 6
                    property real waveHalfW: 0

                    readonly property bool popupsDetached: Config.options.akebono?.shelf.popupsDetached ?? false
                    readonly property real popupGap: 18
                    property real detachEnable: popupsDetached ? 1 : 0
                    readonly property real popupDetach: detachEnable * Math.max(0, Math.min(1, (bumpProgress - 0.55) / 0.45))
                    readonly property real popupLift: popupDetach * popupGap

                    Behavior on detachEnable {
                        NumberAnimation { duration: 380; easing.type: Easing.OutCubic }
                    }

                    function fireRipple(localX, amp, dur, halfW = 0) {
                        dockRoot.waveAmp = amp;
                        dockRoot.waveHalfW = halfW;
                        rippleAnim.duration = dur;
                        dockRoot.waveX = localX;
                        rippleAnim.restart();
                    }
                    function closeBump() {
                        if (dockRoot.bumpProgress > 0.5)
                            dockRoot.fireRipple(dockSurface.bumpX, 6, 650);
                        dockRoot.bumpProgress = 0;
                    }

                    anchors {
                        bottom: true
                        left: true
                        right: true
                    }
                    implicitHeight: bumpRoom + dockStripHeight + bottomGap
                    exclusiveZone: (dockRoot.pinned && !monitorFullscreen) ? (dockStripHeight + bottomGap) : 0
                    mask: Region {
                        item: dockMenu.showing ? dockMenu : (trashMenu.showing ? trashMenu : hoverArea)
                        Region {
                            item: (!dockMenu.showing && !trashMenu.showing && dockRoot.bumpProgress > 0.01) ? previewRegion : null
                        }
                    }

                    Behavior on hideOffset {
                        NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
                    }
                    Behavior on bumpProgress {
                        NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
                    }
                    Behavior on bumpX {
                        enabled: dockRoot.slideBump
                        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                    }

                    Timer {
                        id: closeTimer
                        interval: 130
                        onTriggered: {
                            if (!keepAlive.hovered)
                                dockRoot.closeBump();
                        }
                    }
                    NumberAnimation {
                        id: rippleAnim
                        target: dockRoot
                        property: "waveProgress"
                        from: 0
                        to: 1
                        duration: 650
                    }

                    MouseArea {
                        id: hoverArea
                        anchors.bottom: parent.bottom
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: dockStrip.width + 24
                        height: dockRoot.reveal ? (dockRoot.dockStripHeight + dockRoot.bottomGap) : (Config.options?.dock.hoverRegionHeight ?? 2)
                        hoverEnabled: true
                    }

                    ShaderEffect {
                        id: dockSurface
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: dockRoot.bottomGap - dockRoot.hideOffset
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: dockStrip.width + dockRoot.previewW
                        height: dockRoot.bumpRoom + dockRoot.dockStripHeight
                        blending: true

                        property vector2d size: Qt.vector2d(width, height)
                        property color color: Appearance.colors.colLayer0
                        property real radius: Appearance.rounding.large
                        property real smoothing: AkebonoAppearance.squircleSmoothing
                        property real dockHeight: dockRoot.dockStripHeight
                        property real dockWidth: dockStrip.width
                        property real bumpWidth: dockRoot.bumpProgress * (dockRoot.thumbW + dockRoot.previewInset * 2)
                        property real bumpHeight: dockRoot.bumpProgress * (dockRoot.thumbH + dockRoot.previewInset * 2)
                        property real bumpX: Math.max(bumpWidth / 2, Math.min(dockRoot.bumpX, width - bumpWidth / 2))
                        property real sminK: 26
                        property real waveX: dockRoot.waveX
                        property real waveProgress: dockRoot.waveProgress
                        property real waveAmp: dockRoot.waveAmp
                        property real waveHalfW: dockRoot.waveHalfW
                        property real popupDetach: dockRoot.popupDetach
                        property real popupGap: dockRoot.popupGap
                        fragmentShader: Quickshell.shellPath("assets/shaders/akebono/dock.frag.qsb")
                    }

                    Item {
                        id: previewFrame
                        width: dockRoot.thumbW
                        height: dockRoot.thumbH
                        transformOrigin: Item.Bottom
                        scale: dockRoot.bumpProgress
                        opacity: dockRoot.bumpProgress
                        visible: opacity > 0.01
                        x: dockSurface.x + dockSurface.bumpX - width / 2
                        y: dockSurface.y + dockRoot.bumpRoom - dockRoot.previewInset - height - dockRoot.popupLift

                        DockPreviewCard {
                            id: previewCard
                            anchors.fill: parent
                            uiScale: dockRoot.dockScale
                            entry: dockRoot.bumpEntry
                            onDismissRequested: dockRoot.closeBump()
                        }
                    }

                    Item {
                        id: previewRegion
                        anchors.fill: previewFrame
                        z: 5

                        HoverHandler {
                            id: keepAlive
                            onHoveredChanged: keepAlive.hovered ? closeTimer.stop() : closeTimer.restart()
                        }
                    }

                    Item {
                        id: dockStrip
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: dockRoot.bottomGap - dockRoot.hideOffset
                        x: Math.round((parent.width - width) / 2)
                        implicitWidth: stripRow.implicitWidth + 10
                        width: implicitWidth
                        height: dockRoot.dockStripHeight

                        HoverHandler {
                            id: dockStripHover
                        }

                        Row {
                            id: stripRow
                            anchors.centerIn: parent
                            spacing: 8

                            DockApps {
                                id: dockApps
                                anchors.verticalCenter: parent.verticalCenter
                                tileSize: dockRoot.tileSize
                                iconSize: dockRoot.iconSize
                                minimizeFocused: Config.options.akebono?.shelf.minimizeOnClick ?? true
                                onBumpRequested: (centerX, entry) => {
                                    if (dockMenu.showing)
                                        dockMenu.dismiss();
                                    closeTimer.stop();
                                    if ((Config.options.akebono?.preview.enable ?? true) && entry && entry.toplevels.length > 0) {
                                        dockRoot.slideBump = dockRoot.bumpProgress > 0.5;
                                        if (dockRoot.bumpAppId !== entry.appId)
                                            previewCard.previewIndex = 0;
                                        dockRoot.bumpAppId = entry.appId;
                                        dockRoot.bumpX = dockSurface.mapFromItem(dockApps, centerX, 0).x;
                                        dockRoot.bumpProgress = 1;
                                    } else {
                                        dockRoot.closeBump();
                                    }
                                }
                                onBumpCleared: closeTimer.restart()
                                onScrollRequested: (delta, entry) => {
                                    if (entry.appId !== dockRoot.bumpAppId)
                                        return;
                                    previewCard.cycle(delta);
                                }
                                onMenuRequested: (centerX, entry) => {
                                    closeTimer.stop();
                                    dockRoot.closeBump();
                                    const p = dockApps.mapToItem(dockMenu, centerX, 0);
                                    const stripTop = dockStrip.mapToItem(dockMenu, 0, 0);
                                    dockMenu.show(entry, p.x, stripTop.y);
                                }
                            }

                            Rectangle {
                                visible: dockTrashLoader.active
                                anchors.verticalCenter: parent.verticalCenter
                                width: 1
                                height: dockRoot.dockStripHeight * 0.42
                                radius: 1
                                color: Qt.alpha(Appearance.colors.colOnLayer0, 0.18)
                            }

                            Loader {
                                id: dockTrashLoader
                                anchors.verticalCenter: parent.verticalCenter
                                visible: active
                                active: Config.options.dock?.showTrash ?? true
                                sourceComponent: DockTrash {
                                    id: dockTrash
                                    iconSize: dockRoot.iconSize
                                    onMenuRequested: centerX => {
                                        closeTimer.stop();
                                        dockRoot.closeBump();
                                        dockMenu.dismiss();
                                        const p = dockTrash.mapToItem(trashMenu, centerX, 0);
                                        const stripTop = dockStrip.mapToItem(trashMenu, 0, 0);
                                        trashMenu.show([
                                            { "icon": "folder_open", "label": "Open Trash", "action": () => Quickshell.execDetached(["dolphin", "trash:/"]) },
                                            { "icon": "delete_sweep", "label": "Empty Trash", "danger": true, "action": () => Quickshell.execDetached(["bash", "-c", "for b in ktrash5 ktrash ktrash6; do command -v $b >/dev/null && exec $b --empty; done; gio trash --empty"]) }
                                        ], p.x, stripTop.y);
                                    }
                                }
                            }
                        }
                    }

                    DockContextMenu {
                        id: dockMenu
                        anchors.fill: parent
                        boundsWidth: dockRoot.width
                        boundsHeight: dockRoot.height
                    }

                    SdfContextMenu {
                        id: trashMenu
                        anchors.fill: parent
                        boundsWidth: dockRoot.width
                        boundsHeight: dockRoot.height
                        anchorAbove: true
                    }

                    HyprlandFocusGrab {
                        active: dockMenu.showing || trashMenu.showing
                        windows: [dockRoot]
                        onCleared: {
                            dockMenu.dismiss();
                            trashMenu.dismiss();
                        }
                    }

                    DockDropZone {
                        dock: dockApps
                        surface: dockSurface
                        dropTarget: dockStrip
                        edgeSlack: Appearance.rounding.large
                        onRippleRequested: (localX, amp, dur) => dockRoot.fireRipple(localX, amp, dur)
                    }
                }
            }
        }
    }
}
