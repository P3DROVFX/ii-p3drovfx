pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.akebono
import qs.modules.akebono.dock
import qs.modules.akebono.runner
import qs.modules.akebono.shelf
import qs.modules.akebono.shelf.widgets
import qs.modules.akebono.shelf.widgets.controlPanel
import qs.modules.lunae.overview
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io

Scope {
    id: root

    component PopupContainer: Item {
        id: pc
        required property var shelf
        required property bool open
        required property real progress
        required property real anchorX
        required property real panelW
        required property real panelH
        property bool fillContent: false
        default property alias content: slot.data

        visible: open || progress > 0.001
        width: panelW
        height: progress * panelH
        x: shelf.barSurfaceItem.x + anchorX - width / 2
        y: shelf.popupEdgeY(height)
        clip: true
        opacity: progress
        z: 6
        transform: Scale {
            origin.x: pc.width / 2
            origin.y: pc.shelf.topMode ? 0 : pc.height
            xScale: pc.shelf.suckW(pc.open, pc.progress)
        }

        Item {
            id: slot
            width: pc.panelW
            height: pc.fillContent ? pc.height : pc.panelH
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: pc.shelf.topMode ? parent.top : undefined
            anchors.bottom: pc.shelf.topMode ? undefined : parent.bottom
        }
    }

    GlobalShortcut {
        name: "sidebarRightToggle"
        description: "Toggles the akebono quick settings panel"
        onPressed: {
            const inst = shelfVariants.instances.find(s => s.modelData.name === Hyprland.focusedMonitor?.name) ?? shelfVariants.instances[0];
            inst?.shelfWindow?.toggleQuickSettings();
        }
    }

    Variants {
        id: shelfVariants
        model: Quickshell.screens

        Scope {
            id: screenScope
            required property var modelData
            readonly property var shelfWindow: shelfLoader.item
            readonly property string shelfPosition: Config.options.akebono?.shelf.position ?? "bottom"
            property bool repositioning: false
            onShelfPositionChanged: {
                repositioning = true;
                Qt.callLater(() => screenScope.repositioning = false);
            }

            Loader {
                id: shelfLoader
                active: !screenScope.repositioning

                sourceComponent: PanelWindow {
                    id: shelfRoot
                    readonly property var modelData: screenScope.modelData
                    screen: modelData
                    visible: !GlobalStates.screenLocked
                    color: "transparent"
                    WlrLayershell.namespace: shelfRoot.topMode ? "quickshell:akebonoShelfTop" : "quickshell:akebonoShelf"
                    WlrLayershell.keyboardFocus: (shelfRoot.runnerOpen || shelfRoot.trayOverflowOpen) ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

                    readonly property real barHeight: Config.options.akebono?.shelf.height ?? 54
                    readonly property real sideMargin: 10
                    readonly property real cornerRadius: Appearance.rounding.windowRounding
                    readonly property bool runnerOpen: GlobalStates.desktopRunnerOpen
                        && Config.options.akebono.runner.style === "shelf"
                        && (Quickshell.screens.find(s => s.name === (Hyprland.focusedMonitor?.name ?? ""))?.name ?? "") === shelfRoot.modelData.name
                    readonly property real launcherFullH: 550
                    readonly property real launcherW: Math.min(640, barSurface.width - 16)
                    property real launcherProgress: 0
                    property real launcherRawX: 0
                    readonly property bool launcherActive: shelfRoot.runnerOpen || launcherProgress > 0.001
                    readonly property real bumpRoom: Math.max(250, launcherFullH + 40)
                    readonly property real bottomGap: Appearance.sizes.hyprlandGapsOut
                    readonly property string shape: Config.options.akebono?.shelf.shape ?? "inverseHug"
                    readonly property bool floating: shape === "float"
                    readonly property bool inverseHugMode: shape === "inverseHug"
                    readonly property bool hugMode: shape === "hug"
                    readonly property bool rectMode: shape === "rect"
                    readonly property real effRadius: (rectMode || hugMode) ? 0 : cornerRadius
                    readonly property string lengthMode: Config.options.akebono?.shelf.lengthMode ?? "full"
                    readonly property real fixedLength: Config.options.akebono?.shelf.fixedLength ?? 900
                    readonly property real gap: floating ? bottomGap : 0
                    readonly property real dockHeight: inverseHugMode ? barHeight + cornerRadius : barHeight

                    readonly property bool topMode: (Config.options.akebono?.shelf.position ?? "bottom") === "top"
                    readonly property Item barSurfaceItem: barSurface
                    readonly property bool monitorFullscreen: fullscreenWatcher.active
                    MonitorFullscreen { id: fullscreenWatcher; screen: shelfRoot.modelData }

                    readonly property bool popupsDetached: Config.options.akebono?.shelf.popupsDetached ?? false
                    readonly property real popupGap: 18
                    property real detachEnable: popupsDetached ? 1 : 0
                    readonly property real activePopupProgress: Math.max(launcherProgress, trayProgress, qsProgress, mediaProgress, calProgress, weatherProgress, resourcesProgress, chipPopupProgress, bumpProgress)
                    readonly property real popupDetach: detachEnable * Math.max(0, Math.min(1, (activePopupProgress - 0.55) / 0.45))
                    readonly property real popupLift: popupDetach * popupGap

                    Behavior on detachEnable {
                        NumberAnimation { duration: 380; easing.type: Easing.OutCubic }
                    }

                    readonly property real previewInset: 8
                    readonly property var previewClient: HyprlandData.clientForToplevel(previewCard.toplevel)
                    readonly property real previewSrcW: (previewClient?.size?.[0] ?? 0) > 1 ? previewClient.size[0] : 16
                    readonly property real previewSrcH: (previewClient?.size?.[1] ?? 0) > 1 ? previewClient.size[1] : 9
                    readonly property real previewFit: Math.min(320 / previewSrcW, 180 / previewSrcH)
                    readonly property real thumbW: previewSrcW * previewFit
                    readonly property real thumbH: previewSrcH * previewFit

                    property real bumpProgress: 0
                    property real bumpX: 0
                    property string bumpAppId: ""
                    readonly property var bumpEntry: shelfRoot.bumpAppId !== ""
                        ? (TaskbarApps.apps.find(a => a.appId === shelfRoot.bumpAppId) ?? null)
                        : null
                    property real waveX: 0
                    property real waveProgress: 1
                    property real waveAmp: 6
                    property real waveHalfW: 0
                    property bool slideBump: true

                    property var dockInstance: null
                    property var launcherAnchor: null

                    property bool trayOverflowOpen: false
                    property real trayProgress: 0
                    property real trayRawX: 0
                    property var trayAnchor: null

                    property bool qsOpen: false
                    property real statusRawX: 0
                    property var statusAnchor: null
                    readonly property int qsBaseW: 406
                    readonly property int qsDialogW: 300
                    property bool qsDialogOpen: false
                    property real qsW: qsBaseW + (qsDialogOpen ? qsDialogW : 0)
                    property real qsEditH: 0
                    property real qsContentH: 320
                    readonly property real qsMaxH: shelfRoot.topMode
                        ? Math.max(300, shelfRoot.height - barSurface.y - shelfRoot.dockHeight - shelfRoot.popupLift - 34)
                        : Math.max(300, barSurface.y + shelfRoot.bumpRoom - shelfRoot.popupLift - 34)
                    readonly property real qsFullH: Math.min(qsContentH, shelfRoot.qsMaxH)
                    property real qsProgress: 0

                    Behavior on qsEditH {
                        NumberAnimation {
                            duration: Appearance.animation.elementMove.duration
                            easing.type: Appearance.animation.elementMove.type
                            easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                        }
                    }
                    readonly property bool qsActive: qsOpen || qsProgress > 0.001
                    readonly property bool qsGrowLeft: barSurface.qsGrowLeft
                    readonly property real qsWClamped: Math.max(qsBaseW, qsW)
                    property real qsWave: 1

                    Behavior on qsW {
                        NumberAnimation {
                            duration: Appearance.animation.elementMove.duration
                            easing.type: Appearance.animation.elementMove.type
                            easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                        }
                    }
                    NumberAnimation {
                        id: qsWaveAnim
                        target: shelfRoot
                        property: "qsWave"
                        from: 0
                        to: 1
                        duration: Appearance.animation.elementMove.duration + 250
                    }
                    onQsDialogOpenChanged: {
                        if (!shelfRoot.qsDialogOpen && shelfRoot.qsOpen)
                            qsWaveAnim.restart();
                    }

                    property bool calOpen: false
                    property real clockRawX: 0
                    property var clockAnchor: null
                    property real calProgress: 0
                    readonly property bool calActive: calOpen || calProgress > 0.001

                    property bool weatherOpen: false
                    property real weatherRawX: 0
                    property var weatherAnchor: null
                    property real weatherProgress: 0
                    readonly property bool weatherActive: weatherOpen || weatherProgress > 0.001

                    property bool resourcesOpen: false
                    property real resourcesRawX: 0
                    property var resourcesAnchor: null
                    property real resourcesProgress: 0
                    readonly property bool resourcesActive: resourcesOpen || resourcesProgress > 0.001

                    property bool mediaOpen: false
                    readonly property bool mediaLyricsShown: Config.options.akebono?.shelf.media.lyricsShown ?? true
                    property real mediaRawX: 0
                    property var mediaAnchor: null
                    readonly property int mediaW: 420
                    property real mediaFullH: mediaLyricsShown ? 470 : 280
                    property real mediaProgress: 0
                    readonly property bool mediaActive: mediaOpen || mediaProgress > 0.001

                    // Single-slot popup used by chips whose bar widget's own
                    // popup anchors on the full-width bar window (screenshare,
                    // mode, dictation). Rendered inside THIS window so attached
                    // / detached behaviour follows popupsDetached like the rest.
                    property bool chipPopupOpen: false
                    property real chipPopupProgress: 0
                    property real chipRawX: 0
                    property var chipAnchor: null
                    property var chipPopupSource: null
                    property real chipPopupW: 320
                    property real chipPopupH: 180
                    property real chipPopupRadius: Appearance.rounding.normal
                    readonly property bool chipPopupActive: chipPopupOpen || chipPopupProgress > 0.001

                    Behavior on mediaFullH {
                        NumberAnimation { duration: 280; easing.type: Easing.OutCubic }
                    }

                    property vector4d mediaAudio: Qt.vector4d(0, 0, 0, 0)
                    property real mediaAudioPhase: 0
                    readonly property bool mediaAudioActive: shelfRoot.mediaOpen && (Config.options.akebono?.shelf.media.audioRipple ?? false) && (MprisController.activePlayer?.isPlaying ?? false)

                    onMediaAudioActiveChanged: {
                        if (!shelfRoot.mediaAudioActive)
                            shelfRoot.mediaAudio = Qt.vector4d(0, 0, 0, 0);
                    }

                    Connections {
                        target: CavaService
                        function onVisualizerPointsChanged() {
                            if (!shelfRoot.mediaAudioActive)
                                return;
                            const v = CavaService.visualizerPoints;
                            const n = v.length;
                            if (n < 4)
                                return;
                            const q = Math.floor(n / 4);
                            const band = (a, b) => {
                                let m = 0;
                                for (let i = a; i < b; i++)
                                    m = Math.max(m, v[i]);
                                return Math.min(1, m);
                            };
                            const t = Qt.vector4d(band(0, q), band(q, 2 * q), band(2 * q, 3 * q), band(3 * q, n));
                            const c = shelfRoot.mediaAudio;
                            const k = 0.55;
                            shelfRoot.mediaAudio = Qt.vector4d(c.x + (t.x - c.x) * k, c.y + (t.y - c.y) * k, c.z + (t.z - c.z) * k, c.w + (t.w - c.w) * k);
                        }
                    }

                    NumberAnimation {
                        target: shelfRoot
                        property: "mediaAudioPhase"
                        from: 0
                        to: 2 * Math.PI
                        duration: 4000
                        loops: Animation.Infinite
                        running: shelfRoot.mediaAudioActive
                    }

                    function fireRipple(localX, amp, dur, halfW = 0) {
                        shelfRoot.waveAmp = amp;
                        shelfRoot.waveHalfW = halfW;
                        rippleAnim.duration = dur;
                        shelfRoot.waveX = localX;
                        rippleAnim.restart();
                    }

                    function popupRipple(localX, w, h) {
                        const mass = Math.sqrt(Math.max(1, w * h));
                        const amp = Math.max(8, Math.min(22, mass * 0.04));
                        const dur = Math.max(620, Math.min(1100, 480 + mass));
                        shelfRoot.fireRipple(localX, amp, dur, w * 0.35);
                    }

                    function closePlop(localX, w, h) {
                        const mass = Math.sqrt(Math.max(1, w * h));
                        shelfRoot.fireRipple(localX, Math.max(6, Math.min(14, mass * 0.022)), 650, 0);
                    }

                    function suckW(open, p) {
                        return open ? 1 : Math.max(0.05, p);
                    }

                    function closeBump() {
                        if (shelfRoot.bumpProgress > 0.5)
                            shelfRoot.closePlop(barSurface.bumpX, barSurface.bumpWidth, barSurface.bumpHeight);
                        shelfRoot.bumpProgress = 0;
                    }

                    function publishLauncher() {
                        shelfRoot.launcherRawX = shelfRoot.launcherAnchor
                            ? barSurface.mapFromItem(shelfRoot.launcherAnchor, shelfRoot.launcherAnchor.width / 2, 0).x
                            : barSurface.width / 2;
                    }

                    function registerLauncherAnchor(item) {
                        shelfRoot.launcherAnchor = item;
                        shelfRoot.publishLauncher();
                    }
                    function unregisterLauncherAnchor(item) {
                        if (shelfRoot.launcherAnchor === item)
                            shelfRoot.launcherAnchor = null;
                    }
                    function registerDock(item) {
                        shelfRoot.dockInstance = item;
                    }
                    function unregisterDock(item) {
                        if (shelfRoot.dockInstance === item)
                            shelfRoot.dockInstance = null;
                    }

                    function requestBump(dockItem, centerX, entry) {
                        if (shelfMenu.showing) shelfMenu.dismiss();
                        closeTimer.stop();
                        if (Config.options.akebono.preview.enable && entry && entry.toplevels.length > 0) {
                            shelfRoot.slideBump = shelfRoot.bumpProgress > 0.5;
                            if (shelfRoot.bumpAppId !== entry.appId)
                                previewCard.previewIndex = 0;
                            shelfRoot.bumpAppId = entry.appId;
                            shelfRoot.bumpX = barSurface.mapFromItem(dockItem, centerX, 0).x;
                            shelfRoot.bumpProgress = 1;
                        } else {
                            shelfRoot.closeBump();
                        }
                    }
                    function scheduleClearBump() {
                        closeTimer.restart();
                    }
                    function requestScroll(delta, entry) {
                        if (entry.appId !== shelfRoot.bumpAppId) return;
                        previewCard.cycle(delta);
                    }
                    function requestMenu(dockItem, centerX, entry) {
                        closeTimer.stop();
                        shelfRoot.closeBump();
                        const p = dockItem.mapToItem(shelfMenu, centerX, 0);
                        const top = content.mapToItem(shelfMenu, 0, 0);
                        shelfMenu.show(entry, p.x, top.y);
                    }

                    function registerTrayAnchor(item) {
                        shelfRoot.trayAnchor = item;
                        shelfRoot.publishTray();
                    }
                    function unregisterTrayAnchor(item) {
                        if (shelfRoot.trayAnchor === item)
                            shelfRoot.trayAnchor = null;
                    }
                    function publishTray() {
                        shelfRoot.trayRawX = shelfRoot.trayAnchor
                            ? barSurface.mapFromItem(shelfRoot.trayAnchor, shelfRoot.trayAnchor.width / 2, 0).x
                            : barSurface.width / 2;
                    }
                    function toggleTrayOverflow() {
                        shelfRoot.trayOverflowOpen = !shelfRoot.trayOverflowOpen;
                    }

                    readonly property bool anyPopupOpen: shelfRoot.runnerOpen || qsOpen || mediaOpen || calOpen || weatherOpen || resourcesOpen || chipPopupOpen

                    function popupEdgeY(h) {
                        return shelfRoot.topMode
                            ? barSurface.y + shelfRoot.dockHeight + shelfRoot.popupLift
                            : barSurface.y + shelfRoot.bumpRoom - h - shelfRoot.popupLift;
                    }

                    function closeAllPopups(keepRunner = false) {
                        if (!keepRunner)
                            GlobalStates.desktopRunnerOpen = false;
                        shelfRoot.qsOpen = false;
                        shelfRoot.mediaOpen = false;
                        shelfRoot.calOpen = false;
                        shelfRoot.weatherOpen = false;
                        shelfRoot.resourcesOpen = false;
                        shelfRoot.trayOverflowOpen = false;
                        shelfRoot.chipPopupOpen = false;
                        trayMenu.dismiss();
                        shelfMenu.dismiss();
                        shelfRoot.closeBump();
                    }

                    function announcePopup(open, x, w, h) {
                        if (open)
                            shelfRoot.popupRipple(x, w, h);
                        else
                            shelfRoot.closePlop(x, w, h);
                    }
                    function showTrayMenu(item, iconItem) {
                        const p = iconItem.mapToItem(trayMenu, iconItem.width / 2, 0);
                        trayMenu.show(item, p.x, p.y);
                    }

                    function registerStatusAnchor(item) {
                        shelfRoot.statusAnchor = item;
                        shelfRoot.publishStatus();
                    }
                    function unregisterStatusAnchor(item) {
                        if (shelfRoot.statusAnchor === item)
                            shelfRoot.statusAnchor = null;
                    }
                    function publishStatus() {
                        shelfRoot.statusRawX = shelfRoot.statusAnchor
                            ? barSurface.mapFromItem(shelfRoot.statusAnchor, shelfRoot.statusAnchor.width / 2, 0).x
                            : barSurface.width / 2;
                    }
                    function toggleQuickSettings() {
                        if (!shelfRoot.qsOpen) {
                            shelfRoot.closeAllPopups();
                            shelfRoot.publishStatus();
                        }
                        shelfRoot.qsOpen = !shelfRoot.qsOpen;
                    }

                    function registerClockAnchor(item) {
                        shelfRoot.clockAnchor = item;
                        shelfRoot.publishClock();
                    }
                    function unregisterClockAnchor(item) {
                        if (shelfRoot.clockAnchor === item)
                            shelfRoot.clockAnchor = null;
                    }
                    function publishClock() {
                        shelfRoot.clockRawX = shelfRoot.clockAnchor
                            ? barSurface.mapFromItem(shelfRoot.clockAnchor, shelfRoot.clockAnchor.width / 2, 0).x
                            : barSurface.width / 2;
                    }
                    function toggleCalendar() {
                        if (!shelfRoot.calOpen) {
                            shelfRoot.closeAllPopups();
                            shelfRoot.publishClock();
                        }
                        shelfRoot.calOpen = !shelfRoot.calOpen;
                    }

                    function registerWeatherAnchor(item) {
                        shelfRoot.weatherAnchor = item;
                        shelfRoot.publishWeather();
                    }
                    function unregisterWeatherAnchor(item) {
                        if (shelfRoot.weatherAnchor === item)
                            shelfRoot.weatherAnchor = null;
                    }
                    function publishWeather() {
                        shelfRoot.weatherRawX = shelfRoot.weatherAnchor
                            ? barSurface.mapFromItem(shelfRoot.weatherAnchor, shelfRoot.weatherAnchor.width / 2, 0).x
                            : barSurface.width / 2;
                    }
                    function toggleWeather() {
                        if (!shelfRoot.weatherOpen) {
                            shelfRoot.closeAllPopups();
                            shelfRoot.publishWeather();
                        }
                        shelfRoot.weatherOpen = !shelfRoot.weatherOpen;
                    }

                    function registerResourcesAnchor(item) {
                        shelfRoot.resourcesAnchor = item;
                        shelfRoot.publishResources();
                    }
                    function unregisterResourcesAnchor(item) {
                        if (shelfRoot.resourcesAnchor === item)
                            shelfRoot.resourcesAnchor = null;
                    }
                    function publishResources() {
                        shelfRoot.resourcesRawX = shelfRoot.resourcesAnchor
                            ? barSurface.mapFromItem(shelfRoot.resourcesAnchor, shelfRoot.resourcesAnchor.width / 2, 0).x
                            : barSurface.width / 2;
                    }
                    function toggleResources() {
                        if (!shelfRoot.resourcesOpen) {
                            shelfRoot.closeAllPopups();
                            shelfRoot.publishResources();
                        }
                        shelfRoot.resourcesOpen = !shelfRoot.resourcesOpen;
                    }

                    function registerMediaAnchor(item) {
                        shelfRoot.mediaAnchor = item;
                        shelfRoot.publishMedia();
                    }
                    function unregisterMediaAnchor(item) {
                        if (shelfRoot.mediaAnchor === item)
                            shelfRoot.mediaAnchor = null;
                    }
                    function publishMedia() {
                        shelfRoot.mediaRawX = shelfRoot.mediaAnchor
                            ? barSurface.mapFromItem(shelfRoot.mediaAnchor, shelfRoot.mediaAnchor.width / 2, 0).x
                            : barSurface.width / 2;
                    }
                    function toggleMedia() {
                        if (!shelfRoot.mediaOpen) {
                            shelfRoot.closeAllPopups();
                            shelfRoot.publishMedia();
                        }
                        shelfRoot.mediaOpen = !shelfRoot.mediaOpen;
                    }
                    function toggleMediaLyrics() {
                        const m = Config.options.akebono.shelf.media;
                        m.lyricsShown = !m.lyricsShown;
                    }

                    function registerChipAnchor(item) {
                        shelfRoot.chipAnchor = item;
                        shelfRoot.publishChip();
                    }
                    function unregisterChipAnchor(item) {
                        if (shelfRoot.chipAnchor === item)
                            shelfRoot.chipAnchor = null;
                    }
                    function publishChip() {
                        shelfRoot.chipRawX = shelfRoot.chipAnchor
                            ? barSurface.mapFromItem(shelfRoot.chipAnchor, shelfRoot.chipAnchor.width / 2, 0).x
                            : barSurface.width / 2;
                    }
                    function openChipPopup(source, w, h, anchor, radius = Appearance.rounding.normal) {
                        if (shelfRoot.chipPopupOpen)
                            shelfRoot.closeChipPopup();
                        shelfRoot.closeAllPopups();
                        if (anchor)
                            shelfRoot.chipAnchor = anchor;
                        shelfRoot.chipPopupRadius = radius;
                        shelfRoot.chipPopupSource = source;
                        shelfRoot.chipPopupW = w;
                        shelfRoot.chipPopupH = h;
                        shelfRoot.publishChip();
                        shelfRoot.chipPopupOpen = true;
                    }
                    function closeChipPopup() {
                        shelfRoot.chipPopupOpen = false;
                    }
                    function toggleChipPopup(source, w, h, anchor, radius = Appearance.rounding.normal) {
                        if (shelfRoot.chipPopupOpen && shelfRoot.chipPopupSource === source) {
                            shelfRoot.closeChipPopup();
                            return;
                        }
                        shelfRoot.openChipPopup(source, w, h, anchor, radius);
                    }

                    // The chip slot is single-slot and fixed-size; content sets
                    // its own implicit size, so re-measure the loaded content
                    // and resize the container to match on each open.
                    function chipPopupAutoSize() {
                        const item = chipPopupLoader.item;
                        if (!item)
                            return;
                        const w = Number.isFinite(item.implicitWidth) && item.implicitWidth > 0 ? item.implicitWidth : item.width;
                        const h = Number.isFinite(item.implicitHeight) && item.implicitHeight > 0 ? item.implicitHeight : item.height;
                        if (shelfRoot.chipPopupOpen) {
                            if (w > 0)
                                shelfRoot.chipPopupW = w;
                            if (h > 0)
                                shelfRoot.chipPopupH = h;
                        }
                        shelfRoot.publishChip();
                    }

                    Behavior on bumpProgress {
                        NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
                    }
                    Behavior on bumpX {
                        enabled: shelfRoot.slideBump
                        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                    }
                    Behavior on launcherProgress {
                        NumberAnimation { duration: 280; easing.type: Easing.OutCubic }
                    }
                    Behavior on trayProgress {
                        NumberAnimation { duration: 280; easing.type: Easing.OutCubic }
                    }
                    Behavior on qsProgress {
                        NumberAnimation { duration: 320; easing.type: Easing.OutCubic }
                    }
                    Behavior on mediaProgress {
                        NumberAnimation { duration: 320; easing.type: Easing.OutCubic }
                    }
                    Behavior on calProgress {
                        NumberAnimation { duration: 320; easing.type: Easing.OutCubic }
                    }
                    Behavior on weatherProgress {
                        NumberAnimation { duration: 320; easing.type: Easing.OutCubic }
                    }
                    Behavior on resourcesProgress {
                        NumberAnimation { duration: 320; easing.type: Easing.OutCubic }
                    }
                    Behavior on chipPopupProgress {
                        NumberAnimation { duration: 320; easing.type: Easing.OutCubic }
                    }
                    Behavior on chipPopupW {
                        NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
                    }
                    Behavior on chipPopupH {
                        NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
                    }

                    onTrayOverflowOpenChanged: {
                        shelfRoot.trayProgress = shelfRoot.trayOverflowOpen ? 1 : 0;
                        shelfRoot.publishTray();
                        shelfRoot.announcePopup(shelfRoot.trayOverflowOpen, barSurface.trayX, trayOverflowItem.implicitWidth + 8, trayOverflowItem.implicitHeight + 8);
                    }
                    onQsOpenChanged: {
                        shelfRoot.qsProgress = shelfRoot.qsOpen ? 1 : 0;
                        shelfRoot.publishStatus();
                        shelfRoot.announcePopup(shelfRoot.qsOpen, barSurface.qsX, shelfRoot.qsW, shelfRoot.qsFullH);
                    }
                    onMediaOpenChanged: {
                        shelfRoot.mediaProgress = shelfRoot.mediaOpen ? 1 : 0;
                        shelfRoot.publishMedia();
                        shelfRoot.announcePopup(shelfRoot.mediaOpen, barSurface.mediaX, shelfRoot.mediaW, shelfRoot.mediaFullH);
                    }
                    onCalOpenChanged: {
                        shelfRoot.calProgress = shelfRoot.calOpen ? 1 : 0;
                        shelfRoot.publishClock();
                        shelfRoot.announcePopup(shelfRoot.calOpen, barSurface.calX, calPanel.implicitWidth, calPanel.implicitHeight);
                    }
                    onWeatherOpenChanged: {
                        shelfRoot.weatherProgress = shelfRoot.weatherOpen ? 1 : 0;
                        shelfRoot.publishWeather();
                        shelfRoot.announcePopup(shelfRoot.weatherOpen, barSurface.weatherX, weatherPanel.implicitWidth, weatherPanel.implicitHeight);
                    }
                    onResourcesOpenChanged: {
                        shelfRoot.resourcesProgress = shelfRoot.resourcesOpen ? 1 : 0;
                        shelfRoot.publishResources();
                        shelfRoot.announcePopup(shelfRoot.resourcesOpen, barSurface.resX, resourcesPanel.implicitWidth, resourcesPanel.implicitHeight);
                    }
                    onChipPopupOpenChanged: {
                        shelfRoot.chipPopupProgress = shelfRoot.chipPopupOpen ? 1 : 0;
                        shelfRoot.publishChip();
                        shelfRoot.announcePopup(shelfRoot.chipPopupOpen, barSurface.chipX, shelfRoot.chipPopupW, shelfRoot.chipPopupH);
                    }

                    onRunnerOpenChanged: {
                        shelfRoot.launcherProgress = shelfRoot.runnerOpen ? 1 : 0;
                        if (shelfRoot.runnerOpen)
                            shelfRoot.popupRipple(barSurface.launcherX, shelfRoot.launcherW, shelfRoot.launcherFullH);
                        else
                            shelfRoot.closePlop(barSurface.launcherX, shelfRoot.launcherW, shelfRoot.launcherFullH);
                        if (shelfRoot.runnerOpen) {
                            shelfRoot.closeAllPopups(true);
                            launcherPanel.focusSearch();
                        } else {
                            launcherPanel.resetQuery();
                        }
                    }

                    Timer {
                        id: closeTimer
                        interval: 130
                        onTriggered: {
                            if (!keepAlive.hovered)
                                shelfRoot.closeBump();
                        }
                    }
                    NumberAnimation {
                        id: rippleAnim
                        target: shelfRoot
                        property: "waveProgress"
                        from: 0
                        to: 1
                        duration: 650
                    }

                    anchors {
                        top: shelfRoot.topMode
                        bottom: !shelfRoot.topMode
                        left: true
                        right: true
                    }
                    implicitHeight: bumpRoom + barHeight + gap
                    exclusiveZone: monitorFullscreen ? 0 : barHeight + gap
                    mask: Region {
                        item: shelfMenu.showing ? shelfMenu : (trayMenu.showing ? trayMenu : content)
                        Region {
                            item: (!shelfMenu.showing && shelfRoot.bumpProgress > 0.01) ? previewRegion : null
                        }
                        Region {
                            item: shelfRoot.launcherActive ? launcherContainer : null
                        }
                        Region {
                            item: (shelfRoot.trayOverflowOpen || shelfRoot.trayProgress > 0.001) ? trayContainer : null
                        }
                        Region {
                            item: shelfRoot.qsActive ? qsContainer : null
                        }
                        Region {
                            item: shelfRoot.mediaActive ? mediaContainer : null
                        }
                        Region {
                            item: shelfRoot.calActive ? calContainer : null
                        }
                        Region {
                            item: shelfRoot.weatherActive ? weatherContainer : null
                        }
                        Region {
                            item: shelfRoot.resourcesActive ? resourcesContainer : null
                        }
                        Region {
                            item: shelfRoot.chipPopupActive ? chipPopupContainer : null
                        }
                    }

                    ShaderEffect {
                        id: barSurface
                        anchors.top: shelfRoot.topMode ? parent.top : undefined
                        anchors.bottom: shelfRoot.topMode ? undefined : parent.bottom
                        anchors.topMargin: shelfRoot.floating ? shelfRoot.bottomGap : (shelfRoot.inverseHugMode ? -shelfRoot.cornerRadius : 0)
                        anchors.bottomMargin: shelfRoot.floating ? shelfRoot.bottomGap : (shelfRoot.inverseHugMode ? -shelfRoot.cornerRadius : 0)
                        anchors.horizontalCenter: parent.horizontalCenter
                        height: shelfRoot.bumpRoom + shelfRoot.dockHeight
                        blending: true

                        readonly property real fullWidth: shelfRoot.floating ? parent.width - shelfRoot.sideMargin * 2 : parent.width
                        width: {
                            if (shelfRoot.lengthMode === "fit")
                                return content.implicitWidth;
                            if (shelfRoot.lengthMode === "fixed")
                                return Math.max(content.implicitWidth, Math.min(shelfRoot.fixedLength, fullWidth));
                            return fullWidth;
                        }

                        property vector2d size: Qt.vector2d(width, height)
                        property color color: AkebonoAppearance.shelfSurfaceColor
                        property real radius: shelfRoot.effRadius
                        property real smoothing: AkebonoAppearance.squircleSmoothing
                        property real dockHeight: shelfRoot.dockHeight
                        property real dockWidth: width
                        property real bumpWidth: shelfRoot.bumpProgress * (shelfRoot.thumbW + shelfRoot.previewInset * 2)
                        property real bumpHeight: shelfRoot.bumpProgress * (shelfRoot.thumbH + shelfRoot.previewInset * 2)
                        property real bumpX: Math.max(bumpWidth / 2, Math.min(shelfRoot.bumpX, width - bumpWidth / 2))
                        property real sminK: 26
                        property real waveX: shelfRoot.waveX
                        property real waveProgress: shelfRoot.waveProgress
                        property real waveAmp: shelfRoot.waveAmp
                        property real waveHalfW: shelfRoot.waveHalfW
                        property real launcherX: Math.max(shelfRoot.launcherW / 2, Math.min(shelfRoot.launcherRawX, width - shelfRoot.launcherW / 2))
                        property real launcherW: shelfRoot.launcherW * shelfRoot.suckW(shelfRoot.runnerOpen, shelfRoot.launcherProgress)
                        property real launcherH: shelfRoot.launcherProgress * shelfRoot.launcherFullH
                        property real launcherR: 30
                        property real trayW: (trayOverflowItem.implicitWidth + 8) * shelfRoot.suckW(shelfRoot.trayOverflowOpen, shelfRoot.trayProgress)
                        property real trayX: Math.max(trayW / 2, Math.min(shelfRoot.trayRawX, width - trayW / 2))
                        property real trayH: shelfRoot.trayProgress * (trayOverflowItem.implicitHeight + 8)
                        property real trayR: 24
                        readonly property real qsBaseX: Math.max(shelfRoot.qsBaseW / 2, Math.min(shelfRoot.statusRawX, width - shelfRoot.qsBaseW / 2))
                        readonly property bool qsGrowLeft: qsBaseX - shelfRoot.qsBaseW / 2 >= shelfRoot.qsDialogW
                        readonly property real qsExtra: Math.max(0, shelfRoot.qsW - shelfRoot.qsBaseW)
                        property real qsX: qsBaseX + (qsGrowLeft ? -qsExtra / 2 : qsExtra / 2)
                        property real qsW: shelfRoot.qsWClamped * shelfRoot.suckW(shelfRoot.qsOpen, shelfRoot.qsProgress)
                        property real qsWave: shelfRoot.qsWave
                        property real qsWaveX: qsGrowLeft ? qsX - qsW / 2 : qsX + qsW / 2
                        property real qsH: shelfRoot.qsProgress * shelfRoot.qsFullH
                        property real qsR: 32
                        property real mediaX: Math.max(shelfRoot.mediaW / 2, Math.min(shelfRoot.mediaRawX, width - shelfRoot.mediaW / 2))
                        property real chipX: Math.max(shelfRoot.chipPopupW / 2, Math.min(shelfRoot.chipRawX, width - shelfRoot.chipPopupW / 2))
                        property real chipW: shelfRoot.chipPopupW * shelfRoot.suckW(shelfRoot.chipPopupOpen, shelfRoot.chipPopupProgress)
                        property real chipH: shelfRoot.chipPopupProgress * shelfRoot.chipPopupH
                        property real chipR: shelfRoot.chipPopupRadius
                        property real mediaW: shelfRoot.mediaW * shelfRoot.suckW(shelfRoot.mediaOpen, shelfRoot.mediaProgress)
                        property real mediaH: shelfRoot.mediaProgress * shelfRoot.mediaFullH
                        property real mediaR: 32
                        property real calX: Math.max(calPanel.implicitWidth / 2, Math.min(shelfRoot.clockRawX, width - calPanel.implicitWidth / 2))
                        property real calW: calPanel.implicitWidth * shelfRoot.suckW(shelfRoot.calOpen, shelfRoot.calProgress)
                        property real calH: shelfRoot.calProgress * calPanel.implicitHeight
                        property real calR: 32
                        property real weatherX: Math.max(weatherPanel.implicitWidth / 2, Math.min(shelfRoot.weatherRawX, width - weatherPanel.implicitWidth / 2))
                        property real weatherW: weatherPanel.implicitWidth * shelfRoot.suckW(shelfRoot.weatherOpen, shelfRoot.weatherProgress)
                        property real weatherH: shelfRoot.weatherProgress * weatherPanel.implicitHeight
                        property real weatherR: Appearance.rounding.normal
                        property real resX: Math.max(resourcesPanel.implicitWidth / 2, Math.min(shelfRoot.resourcesRawX, width - resourcesPanel.implicitWidth / 2))
                        property real resW: resourcesPanel.implicitWidth * shelfRoot.suckW(shelfRoot.resourcesOpen, shelfRoot.resourcesProgress)
                        property real resH: shelfRoot.resourcesProgress * resourcesPanel.implicitHeight
                        property real resR: Appearance.rounding.normal
                        property vector4d audio: shelfRoot.mediaAudio
                        property real audioPhase: shelfRoot.mediaAudioPhase
                        property real audioAmp: 18
                        property real popupDetach: shelfRoot.popupDetach
                        property real popupGap: shelfRoot.popupGap
                        property real flipY: shelfRoot.topMode ? 1 : 0
                        property real hugRadius: shelfRoot.hugMode ? shelfRoot.cornerRadius : 0
                        fragmentShader: Quickshell.shellPath("assets/shaders/akebono/dock.frag.qsb")

                        Behavior on width {
                            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                        }

                        onWidthChanged: shelfRoot.publishLauncher()
                        onXChanged: shelfRoot.publishLauncher()

                        Item {
                            id: content
                            anchors.top: parent.top
                            anchors.topMargin: shelfRoot.topMode ? shelfRoot.dockHeight - shelfRoot.barHeight : shelfRoot.bumpRoom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: shelfRoot.barHeight
                            implicitWidth: leftSection.implicitWidth + centerSection.implicitWidth + rightSection.implicitWidth + 26 + 48

                            RowLayout {
                                id: leftSection
                                readonly property var sectionModel: Config.options.akebono?.shelf.layout.left ?? []
                                anchors.left: parent.left
                                anchors.leftMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 4

                                Repeater {
                                    model: leftSection.sectionModel
                                    delegate: ShelfModule {
                                        shelf: shelfRoot
                                        list: leftSection.sectionModel
                                        barSection: 0
                                    }
                                }
                            }

                            RowLayout {
                                id: centerSection
                                readonly property var sectionModel: Config.options.akebono?.shelf.layout.center ?? []
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 4

                                Repeater {
                                    model: centerSection.sectionModel
                                    delegate: ShelfModule {
                                        shelf: shelfRoot
                                        list: centerSection.sectionModel
                                        barSection: 1
                                    }
                                }
                            }

                            RowLayout {
                                id: rightSection
                                readonly property var sectionModel: Config.options.akebono?.shelf.layout.right ?? []
                                anchors.right: parent.right
                                anchors.rightMargin: 14
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 4

                                Repeater {
                                    model: rightSection.sectionModel
                                    delegate: ShelfModule {
                                        shelf: shelfRoot
                                        list: rightSection.sectionModel
                                        barSection: 2
                                    }
                                }
                            }
                        }
                    }

                    Item {
                        id: previewFrame
                        width: shelfRoot.thumbW
                        height: shelfRoot.thumbH
                        transformOrigin: shelfRoot.topMode ? Item.Top : Item.Bottom
                        scale: shelfRoot.bumpProgress
                        opacity: shelfRoot.bumpProgress
                        visible: opacity > 0.01
                        x: barSurface.x + barSurface.bumpX - width / 2
                        y: shelfRoot.topMode
                            ? barSurface.y + shelfRoot.dockHeight + shelfRoot.previewInset + shelfRoot.popupLift
                            : barSurface.y + shelfRoot.bumpRoom - shelfRoot.previewInset - height - shelfRoot.popupLift

                        DockPreviewCard {
                            id: previewCard
                            anchors.fill: parent
                            entry: shelfRoot.bumpEntry
                            onDismissRequested: shelfRoot.closeBump()
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

                    PopupContainer {
                        id: launcherContainer
                        shelf: shelfRoot
                        open: shelfRoot.runnerOpen
                        progress: shelfRoot.launcherProgress
                        anchorX: barSurface.launcherX
                        panelW: shelfRoot.launcherW
                        panelH: shelfRoot.launcherFullH
                        fillContent: true

                        LauncherPanel {
                            id: launcherPanel
                            anchors.fill: parent
                            onRequestClose: GlobalStates.desktopRunnerOpen = false
                            onRightClicked: (entry, sx, sy) => {
                                const m = launcherMenu.mapFromItem(null, sx, sy);
                                launcherMenu.show(entry, m.x, m.y);
                            }
                        }
                    }

                    DockDropZone {
                        dock: shelfRoot.dockInstance
                        surface: barSurface
                        dropTarget: content
                        topMode: shelfRoot.topMode
                        edgeSlack: shelfRoot.cornerRadius
                        onRippleRequested: (localX, amp, dur) => shelfRoot.fireRipple(localX, amp, dur)
                    }

                    AppContextMenu {
                        id: launcherMenu
                        anchors.fill: parent
                        boundsWidth: shelfRoot.width
                        boundsHeight: shelfRoot.height
                    }

                    DockContextMenu {
                        id: shelfMenu
                        anchors.fill: parent
                        boundsWidth: shelfRoot.width
                        boundsHeight: shelfRoot.height
                        openAbove: !shelfRoot.topMode
                    }

                    ShelfTrayMenu {
                        id: trayMenu
                        anchors.fill: parent
                        boundsWidth: shelfRoot.width
                        boundsHeight: shelfRoot.height
                        anchorAbove: !shelfRoot.topMode
                    }

                    PopupContainer {
                        id: qsContainer
                        shelf: shelfRoot
                        open: shelfRoot.qsOpen
                        progress: shelfRoot.qsProgress
                        anchorX: barSurface.qsX
                        panelW: shelfRoot.qsWClamped
                        panelH: shelfRoot.qsFullH

                        ControlPanel {
                            id: qsPanel
                            anchors.fill: parent
                            shelf: shelfRoot
                            onCloseRequested: shelfRoot.qsOpen = false
                        }
                    }

                    PopupContainer {
                        id: mediaContainer
                        shelf: shelfRoot
                        open: shelfRoot.mediaOpen
                        progress: shelfRoot.mediaProgress
                        anchorX: barSurface.mediaX
                        panelW: shelfRoot.mediaW
                        panelH: shelfRoot.mediaFullH

                        ShelfMediaPanel {
                            anchors.fill: parent
                            shelf: shelfRoot
                            onCloseRequested: shelfRoot.mediaOpen = false
                        }
                    }

                    PopupContainer {
                        id: calContainer
                        shelf: shelfRoot
                        open: shelfRoot.calOpen
                        progress: shelfRoot.calProgress
                        anchorX: barSurface.calX
                        panelW: calPanel.implicitWidth
                        panelH: calPanel.implicitHeight

                        ShelfCalendarPanel {
                            id: calPanel
                            anchors.fill: parent
                            shelf: shelfRoot
                            onCloseRequested: shelfRoot.calOpen = false
                        }
                    }

                    PopupContainer {
                        id: weatherContainer
                        shelf: shelfRoot
                        open: shelfRoot.weatherOpen
                        progress: shelfRoot.weatherProgress
                        anchorX: barSurface.weatherX
                        panelW: weatherPanel.implicitWidth
                        panelH: weatherPanel.implicitHeight

                        ShelfWeatherPanel {
                            id: weatherPanel
                            anchors.fill: parent
                            shelf: shelfRoot
                            onCloseRequested: shelfRoot.weatherOpen = false
                        }
                    }

                    PopupContainer {
                        id: resourcesContainer
                        shelf: shelfRoot
                        open: shelfRoot.resourcesOpen
                        progress: shelfRoot.resourcesProgress
                        anchorX: barSurface.resX
                        panelW: resourcesPanel.implicitWidth
                        panelH: resourcesPanel.implicitHeight

                        ShelfResourcesPanel {
                            id: resourcesPanel
                            anchors.fill: parent
                            shelf: shelfRoot
                            onCloseRequested: shelfRoot.resourcesOpen = false
                        }
                    }

                    HyprlandFocusGrab {
                        active: shelfRoot.anyPopupOpen
                        windows: [shelfRoot]
                        onCleared: shelfRoot.closeAllPopups()
                    }

                    HyprlandFocusGrab {
                        active: shelfMenu.showing
                        windows: [shelfRoot]
                        onCleared: shelfMenu.dismiss()
                    }

                    PopupContainer {
                        id: trayContainer
                        shelf: shelfRoot
                        open: shelfRoot.trayOverflowOpen
                        progress: shelfRoot.trayProgress
                        anchorX: barSurface.trayX
                        panelW: trayOverflowItem.implicitWidth
                        panelH: trayOverflowItem.implicitHeight

                        ShelfTrayOverflow {
                            id: trayOverflowItem
                            anchors.fill: parent
                            barHeight: shelfRoot.barHeight
                            shelf: shelfRoot
                        }
                    }

                    PopupContainer {
                        id: chipPopupContainer
                        shelf: shelfRoot
                        open: shelfRoot.chipPopupOpen
                        progress: shelfRoot.chipPopupProgress
                        anchorX: barSurface.chipX
                        panelW: shelfRoot.chipPopupW
                        panelH: shelfRoot.chipPopupH
                        fillContent: true

                        Loader {
                            id: chipPopupLoader
                            anchors.fill: parent
                            sourceComponent: shelfRoot.chipPopupSource
                            onLoaded: shelfRoot.chipPopupAutoSize()
                            onItemChanged: shelfRoot.chipPopupAutoSize()
                        }
                    }

                    Connections {
                        target: shelfRoot
                        function onChipPopupOpenChanged() {
                            if (shelfRoot.chipPopupOpen)
                                Qt.callLater(shelfRoot.chipPopupAutoSize);
                        }
                    }

                    HyprlandFocusGrab {
                        active: shelfRoot.trayOverflowOpen || trayMenu.showing
                        windows: [shelfRoot]
                        onCleared: {
                            if (trayMenu.showing)
                                trayMenu.dismiss();
                            else
shelfRoot.trayOverflowOpen = false;
                        shelfRoot.chipPopupOpen = false;
                        }
                    }

                }
            }
        }
    }


}
