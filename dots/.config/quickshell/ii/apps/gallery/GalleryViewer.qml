pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Effects
import QtMultimedia
import Quickshell.Widgets
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services

/**
 * Unified fullscreen Media Viewer (lazy-loaded via Loader when store.viewerOpen).
 * Supports both local PC media and ii-tools Phone Gallery media:
 *   - Images: fast priority loading (main image decodes before filmstrip), rounded
 *     corners on fitted media, wheel zoom, double-click zoom, working drag pan, 90° rotate.
 *   - Videos: QtMultimedia MediaPlayer + AudioOutput with autoplay, M3E wavy seek bar,
 *     larger ±10s buttons, compact timer, snug volume slider w/ pointer cursor, centered
 *     speed pill, loop, and true edge-to-edge cinema fullscreen with auto-hiding chrome.
 *   - Details side sheet slides smoothly from the right, shifting the media stage in sync.
 */
FocusScope {
    id: root

    required property var store
    required property var phoneBridge
    property bool open: true
    signal toggleFullscreenRequested()
    property bool isFullscreen: false

    readonly property bool isPhone: store.viewerSource === "phone"
    readonly property var currentItem: (store.viewerIndex >= 0 && store.viewerIndex < store.viewerList.length)
        ? store.viewerList[store.viewerIndex]
        : null
    readonly property bool isVideo: currentItem !== null && (isPhone ? currentItem.kind === "video" : currentItem.type === "video")
    readonly property bool cinemaFullscreen: root.isFullscreen && root.isVideo
    readonly property bool immersiveZoom: !root.isVideo && root.zoom > 1.01

    readonly property string itemTitle: {
        if (!currentItem)
            return "";
        return isPhone ? String(currentItem.name ?? currentItem.id) : String(currentItem.title ?? currentItem.file);
    }

    readonly property string localResolvedPath: {
        if (!currentItem)
            return "";
        if (!isPhone)
            return String(currentItem.path ?? "");
        void phoneBridge.fullPaths;
        void phoneBridge.mountDir;
        return phoneBridge.localPathFor(currentItem);
    }

    readonly property string phoneThumbUrl: {
        if (!isPhone || !currentItem)
            return "";
        void phoneBridge.thumbRevision;
        return phoneBridge.thumbPath(currentItem.id);
    }

    readonly property var phoneTransfer: {
        if (!isPhone || !currentItem)
            return null;
        return phoneBridge.fullProgress[String(currentItem.id)] ?? null;
    }

    readonly property bool canPrev: store.viewerIndex > 0
    readonly property bool canNext: store.viewerIndex >= 0 && store.viewerIndex < store.viewerList.length - 1

    // Image transform state
    property real zoom: 1.0
    property int rotationDeg: 0
    property real panX: 0
    property real panY: 0

    // Video state (remembers persisted videoVolume across sessions!)
    property real volume: store.videoVolume
    property bool muted: store.startMuted || store.videoVolume <= 0.01
    property int speedIdx: 1
    readonly property var speeds: [0.5, 1.0, 1.5, 2.0]
    property bool loopVideo: false

    // Cinema fullscreen auto-hide controls state
    property bool pointerActive: true
    property real _lastPtrX: -1
    property real _lastPtrY: -1
    property bool controlsHovered: false
    readonly property bool chromeVisible: !root.cinemaFullscreen
        || root.pointerActive
        || root.controlsHovered
        || player.playbackState !== MediaPlayer.PlayingState
        || root.infoOpen
        || root.confirmDeleteOpen

    // Panels, hero expand/collapse transition & priority loading
    property bool infoOpen: false
    property bool confirmDeleteOpen: false
    property string pendingPhoneAction: ""
    property bool filmstripReady: false
    property real openProgress: 0.0
    property real chromeReveal: 0.0
    property bool closing: false
    property int _openedIndex: -1
    readonly property var originRect: store.viewerOrigin ?? null
    readonly property bool useOriginFlip: originRect !== null && (!closing || store.viewerIndex === _openedIndex)
    readonly property bool heroAnimating: (useOriginFlip && openProgress < 0.999) || closing

    function bumpPointerActivity(): void {
        root.pointerActive = true;
        if (root.cinemaFullscreen && player.playbackState === MediaPlayer.PlayingState && !root.controlsHovered)
            hideChromeTimer.restart();
    }

    function handlePointerMove(px, py): void {
        if (Math.abs(px - root._lastPtrX) < 3 && Math.abs(py - root._lastPtrY) < 3)
            return;
        root._lastPtrX = px;
        root._lastPtrY = py;
        root.bumpPointerActivity();
    }

    onCinemaFullscreenChanged: {
        root.pointerActive = true;
        if (root.cinemaFullscreen && player.playbackState === MediaPlayer.PlayingState)
            hideChromeTimer.restart();
        else
            hideChromeTimer.stop();
    }

    onControlsHoveredChanged: {
        if (root.controlsHovered) {
            hideChromeTimer.stop();
            root.pointerActive = true;
        } else if (root.cinemaFullscreen && player.playbackState === MediaPlayer.PlayingState) {
            hideChromeTimer.restart();
        }
    }

    function resetTransform(): void {
        root.zoom = 1.0;
        root.rotationDeg = 0;
        root.panX = 0;
        root.panY = 0;
    }

    /// Zoom toward a point (mx, my) in imgStage coordinates (defaults to center).
    function setZoomAt(z, mx, my): void {
        const oldZ = root.zoom;
        const newZ = Math.min(5.0, Math.max(1.0, Math.round(z * 10) / 10));
        if (newZ <= 1.0) {
            root.zoom = 1.0;
            root.panX = 0;
            root.panY = 0;
            return;
        }
        if (Math.abs(newZ - oldZ) < 0.001)
            return;
        const cx = imgStage.width / 2;
        const cy = imgStage.height / 2;
        const dx = (mx !== undefined ? mx : cx) - cx;
        const dy = (my !== undefined ? my : cy) - cy;
        const ratio = newZ / oldZ;
        root.panX = dx - (dx - root.panX) * ratio;
        root.panY = dy - (dy - root.panY) * ratio;
        root.zoom = newZ;
    }

    function setZoom(z): void {
        root.setZoomAt(z, imgStage.width / 2, imgStage.height / 2);
    }

    function step(delta): void {
        const next = store.viewerIndex + delta;
        if (next < 0 || next >= store.viewerList.length)
            return;
        store.viewerIndex = next;
    }

    function _loadCurrent(): void {
        root.resetTransform();
        root.confirmDeleteOpen = false;
        root.pendingPhoneAction = "";
        player.stop();
        player.source = "";

        const item = root.currentItem;
        if (!item)
            return;

        // Compute video flag directly from `item` (never read stale `root.isVideo` binding
        // inside onCurrentItemChanged when switching from a photo to a video in the filmstrip).
        const itemIsVideo = root.isPhone ? (item.kind === "video") : (item.type === "video");

        if (root.isPhone) {
            const sid = String(item.id);
            const resolved = phoneBridge.localPathFor(item);
            if (itemIsVideo) {
                if (resolved)
                    root._startVideo(resolved);
                else
                    phoneBridge.prepareItem(sid);
            } else {
                if (!resolved)
                    phoneBridge.requestFull(sid);
            }
        } else if (itemIsVideo) {
            root._startVideo(String(item.path ?? ""));
        }

        if (root.filmstripReady && store.viewerIndex >= 0 && filmstrip.count > store.viewerIndex)
            filmstrip.positionViewAtIndex(store.viewerIndex, ListView.Center);
    }

    function _startVideo(path): void {
        if (!path)
            return;
        const url = path.startsWith("file://") ? path : ("file://" + path);
        player.source = url;
        player.playbackRate = root.speeds[root.speedIdx];
        player.loops = root.loopVideo ? MediaPlayer.Infinite : 1;
        if (store.autoplay)
            player.play();
    }

    function triggerImageShellAction(actionKind): void {
        if (!root.currentItem || root.isVideo)
            return;
        if (root.localResolvedPath) {
            if (actionKind === "wallpaper")
                store.setWallpaper(root.localResolvedPath, false);
            else if (actionKind === "avatar")
                store.setAvatar(root.localResolvedPath);
            return;
        }
        if (root.isPhone) {
            root.pendingPhoneAction = actionKind;
            phoneBridge.requestFull(String(root.currentItem.id));
            store.showSnack(Translation.tr("Downloading full image from phone…"), "", null);
        }
    }

    onCurrentItemChanged: {
        if (root.open)
            root._loadCurrent();
    }

    function requestClose(): void {
        if (!root.open || root.closing)
            return;
        root.closing = true;
        openAnim.stop();
        filmstripDelayTimer.stop();
        hideChromeTimer.stop();
        player.pause();
        root.infoOpen = false;
        root.confirmDeleteOpen = false;
        root.resetTransform();
        closeAnim.restart();
    }

    onOpenChanged: {
        if (root.open) {
            closeAnim.stop();
            root.closing = false;
            root._openedIndex = store.viewerIndex;
            root.infoOpen = false;
            root.confirmDeleteOpen = false;
            root.filmstripReady = false;
            root.openProgress = 0.0;
            root.chromeReveal = 0.0;
            root.forceActiveFocus();
            root._loadCurrent();
            openAnim.restart();
            filmstripDelayTimer.restart();
        } else {
            openAnim.stop();
            closeAnim.stop();
            root.closing = false;
            root._openedIndex = -1;
            filmstripDelayTimer.stop();
            hideChromeTimer.stop();
            player.stop();
            player.source = "";
            // Do NOT assign `mainImg.source = ""` imperatively here: that would break its
            // declarative `root.open ? ... : ""` binding permanently on subsequent opens!
            root.filmstripReady = false;
            root.infoOpen = false;
            root.confirmDeleteOpen = false;
            root.resetTransform();
        }
    }

    onLocalResolvedPathChanged: {
        if (!root.open || !root.localResolvedPath)
            return;
        if (root.isPhone && root.isVideo && String(player.source) === "") {
            root._startVideo(root.localResolvedPath);
        }
        if (root.pendingPhoneAction !== "" && !root.isVideo) {
            const act = root.pendingPhoneAction;
            root.pendingPhoneAction = "";
            root.triggerImageShellAction(act);
        }
    }

    Component.onCompleted: {
        if (root.open) {
            root.forceActiveFocus();
            root._loadCurrent();
            openAnim.restart();
            filmstripDelayTimer.restart();
        }
    }

    Component.onDestruction: {
        player.stop();
        player.source = "";
        mainImg.source = "";
    }

    ParallelAnimation {
        id: openAnim
        NumberAnimation {
            target: root
            property: "openProgress"
            from: 0.0
            to: 1.0
            duration: 300
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.05, 0.7, 0.1, 1.0, 1.0, 1.0]
        }
        SequentialAnimation {
            PauseAnimation { duration: 60 }
            NumberAnimation {
                target: root
                property: "chromeReveal"
                from: 0.0
                to: 1.0
                duration: 220
                easing.type: Easing.OutCubic
            }
        }
    }

    ParallelAnimation {
        id: closeAnim
        NumberAnimation {
            target: root
            property: "chromeReveal"
            to: 0.0
            duration: 120
            easing.type: Easing.InCubic
        }
        NumberAnimation {
            target: root
            property: "openProgress"
            to: 0.0
            duration: 240
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.3, 0.0, 0.8, 0.15, 1.0, 1.0]
        }
        onFinished: {
            if (root.closing)
                store.closeViewer();
        }
    }

    // Give mainImg exclusive decode priority for the first 180ms before populating filmstrip thumbnails
    Timer {
        id: filmstripDelayTimer
        interval: 180
        repeat: false
        onTriggered: {
            root.filmstripReady = true;
            if (store.viewerIndex >= 0 && filmstrip.count > store.viewerIndex)
                filmstrip.positionViewAtIndex(store.viewerIndex, ListView.Center);
        }
    }

    Timer {
        id: hideChromeTimer
        interval: 2400
        repeat: false
        onTriggered: {
            if (root.cinemaFullscreen && player.playbackState === MediaPlayer.PlayingState)
                root.pointerActive = false;
        }
    }

    // Keyboard shortcuts
    Keys.onPressed: event => {
        root.bumpPointerActivity();
        if (event.key === Qt.Key_Escape) {
            if (root.confirmDeleteOpen)
                root.confirmDeleteOpen = false;
            else if (root.isFullscreen)
                root.toggleFullscreenRequested();
            else if (root.infoOpen)
                root.infoOpen = false;
            else
                root.requestClose();
            event.accepted = true;
            return;
        }
        if (event.key === Qt.Key_Left) {
            root.step(-1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Right) {
            root.step(1);
            event.accepted = true;
        } else if ((event.key === Qt.Key_Space || event.key === Qt.Key_K) && root.isVideo) {
            if (player.playbackState === MediaPlayer.PlayingState)
                player.pause();
            else
                player.play();
            event.accepted = true;
        } else if (event.key === Qt.Key_J && root.isVideo) {
            player.position = Math.max(0, player.position - 10000);
            event.accepted = true;
        } else if (event.key === Qt.Key_L && root.isVideo) {
            player.position = Math.min(player.duration, player.position + 10000);
            event.accepted = true;
        } else if (event.key === Qt.Key_M && root.isVideo) {
            root.muted = !root.muted;
            event.accepted = true;
        } else if (event.key === Qt.Key_F) {
            root.toggleFullscreenRequested();
            event.accepted = true;
        } else if (event.key === Qt.Key_I) {
            root.infoOpen = !root.infoOpen;
            event.accepted = true;
        } else if ((event.key === Qt.Key_Plus || event.key === Qt.Key_Equal) && !root.isVideo) {
            root.setZoom(root.zoom + 0.5);
            event.accepted = true;
        } else if (event.key === Qt.Key_Minus && !root.isVideo) {
            root.setZoom(root.zoom - 0.5);
            event.accepted = true;
        } else if (event.key === Qt.Key_R && !root.isVideo) {
            root.rotationDeg = (root.rotationDeg + 90) % 360;
            event.accepted = true;
        } else if (event.key === Qt.Key_Delete && !root.isPhone) {
            root.confirmDeleteOpen = true;
            event.accepted = true;
        }
    }

    // Real QtMultimedia audio + video playback
    MediaPlayer {
        id: player
        videoOutput: videoOutput
        audioOutput: AudioOutput {
            id: audioOut
            volume: root.volume
            muted: root.muted
        }
        onPlaybackStateChanged: {
            if (root.cinemaFullscreen && playbackState === MediaPlayer.PlayingState)
                hideChromeTimer.restart();
            else
                root.pointerActive = true;
        }
        onErrorOccurred: (error, errorString) => {
            if (error !== MediaPlayer.NoError)
                store.showSnack(Translation.tr("Playback error: %1").arg(errorString), "", null);
        }
    }

    // Reusable snappy header icon button with working tooltip (`requireOverlay: false`)
    component ViewerIconBtn: RippleButton {
        id: vib
        required property string iconName
        required property string tipText
        property bool activeState: false
        property bool dangerHover: false
        property bool filledTonal: false
        property int iconPixelSize: 20

        implicitWidth: 40
        implicitHeight: 40
        buttonRadius: (activeState || hovered) ? 13 : 20
        colBackground: activeState
            ? Appearance.colors.colPrimary
            : (filledTonal ? Appearance.colors.colSecondaryContainer : "transparent")
        colBackgroundHover: activeState
            ? Appearance.colors.colPrimaryHover
            : (dangerHover
                ? Appearance.m3colors.m3errorContainer
                : (filledTonal ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer2Hover))

        Behavior on buttonRadius { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }

        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            text: vib.iconName
            fill: vib.activeState ? 1 : 0
            iconSize: vib.iconPixelSize
            color: vib.activeState
                ? Appearance.colors.colOnPrimary
                : (vib.dangerHover && vib.hovered
                    ? Appearance.m3colors.m3onErrorContainer
                    : (vib.filledTonal ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurfaceVariant))
        }

        StyledToolTip {
            requireOverlay: false
            text: vib.tipText
        }
    }

    // Opaque dark cinema backdrop (fades in smoothly during hero expand)
    Rectangle {
        anchors.fill: parent
        color: Appearance.m3colors.m3surfaceContainerLowest
        opacity: root.openProgress
    }

    // Global mouse activity tracker for cinema fullscreen auto-hide (ignores spurious micro-events)
    HoverHandler {
        onPointChanged: root.handlePointerMove(point.position.x, point.position.y)
    }

    // ── Main Content Layout (Stage + Smoothly Sliding Details Sidebar) ──
    RowLayout {
        anchors.fill: parent
        spacing: 0

        // Left: Media area (with overlay chrome in cinema fullscreen, or stacked normally)
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // ── Media Stage (fills 100% edge-to-edge in cinema fullscreen OR image zoom) ─
            Item {
                id: stage
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: (root.cinemaFullscreen || root.immersiveZoom) ? parent.top : topBar.bottom
                anchors.bottom: (root.cinemaFullscreen || root.immersiveZoom) ? parent.bottom : bottomDock.top
                clip: !root.heroAnimating

                // ── Image display (fitted rounded ClippingRectangle + working zoom/pan/rotate) ─
                Item {
                    id: imgStage
                    anchors.fill: parent
                    anchors.leftMargin: root.immersiveZoom ? 0 : 84
                    anchors.rightMargin: root.immersiveZoom ? 0 : 84
                    anchors.topMargin: root.immersiveZoom ? 0 : 8
                    anchors.bottomMargin: root.immersiveZoom ? 0 : 8
                    visible: !root.isVideo

                    // Reference unzoomed box size so fittedW/fittedH stay stable when entering immersiveZoom.
                    // Fall back to thumbUnderlay's synchronous dimensions on frame 0 so non-16:9 images
                    // (e.g. 9:16 portrait) animate straight to their exact aspect ratio without stretching!
                    readonly property real baseBoxW: Math.max(1, stage.width - 168)
                    readonly property real baseBoxH: Math.max(1, root.height - 68 - 84 - 16)
                    readonly property real natW: mainImg.implicitWidth > 0
                        ? mainImg.implicitWidth
                        : (thumbUnderlay.implicitWidth > 0 ? thumbUnderlay.implicitWidth : Number(root.currentItem?.w || 0))
                    readonly property real natH: mainImg.implicitHeight > 0
                        ? mainImg.implicitHeight
                        : (thumbUnderlay.implicitHeight > 0 ? thumbUnderlay.implicitHeight : Number(root.currentItem?.h || 0))
                    readonly property bool swapped: (root.rotationDeg % 180) !== 0
                    readonly property real effW: swapped ? natH : natW
                    readonly property real effH: swapped ? natW : natH
                    readonly property real fitScale: (effW > 0 && effH > 0)
                        ? Math.min(baseBoxW / effW, baseBoxH / effH)
                        : 1
                    readonly property real fittedW: (effW > 0 && effH > 0) ? Math.max(1, Math.round(natW * fitScale)) : baseBoxW
                    readonly property real fittedH: (effW > 0 && effH > 0) ? Math.max(1, Math.round(natH * fitScale)) : baseBoxH

                    // Phone thumbnail fallback while full-res downloads
                    ClippingRectangle {
                        anchors.centerIn: parent
                        width: imgStage.fittedW
                        height: imgStage.fittedH
                        radius: Appearance.rounding.large
                        color: "transparent"
                        visible: root.isPhone && mainImg.status !== Image.Ready && root.phoneThumbUrl.length > 0

                        Image {
                            anchors.fill: parent
                            source: root.phoneThumbUrl
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                        }
                    }

                    // Seamless Google Photos-style single-element FLIP expand + crisp full-res image:
                    // At p=0 the ClippingRectangle matches the clicked tile's exact rect & crop;
                    // as p->1 it expands into the exact aspect-matched target rect (fittedW x fittedH),
                    // so PreserveAspectCrop transitions smoothly into the full uncropped photo with ZERO pop!
                    Item {
                        id: imgTransformHost
                        readonly property bool flipActive: root.heroAnimating && root.useOriginFlip && !root.immersiveZoom
                        readonly property real p: root.openProgress
                        readonly property real targetW: Math.max(1, Math.round(imgStage.fittedW * root.zoom))
                        readonly property real targetH: Math.max(1, Math.round(imgStage.fittedH * root.zoom))
                        readonly property real targetX: (imgStage.width - targetW) / 2 + root.panX
                        readonly property real targetY: (imgStage.height - targetH) / 2 + root.panY
                        readonly property real startX: root.originRect ? (Number(root.originRect.x) - 84) : targetX
                        readonly property real startY: root.originRect ? (Number(root.originRect.y) - 76) : targetY
                        readonly property real startW: root.originRect ? Math.max(1, Number(root.originRect.w)) : targetW
                        readonly property real startH: root.originRect ? Math.max(1, Number(root.originRect.h)) : targetH

                        x: flipActive ? (startX + (targetX - startX) * p) : targetX
                        y: flipActive ? (startY + (targetY - startY) * p) : targetY
                        width: flipActive ? Math.max(1, startW + (targetW - startW) * p) : targetW
                        height: flipActive ? Math.max(1, startH + (targetH - startH) * p) : targetH
                        rotation: root.rotationDeg
                        scale: !root.useOriginFlip ? (0.92 + 0.08 * root.openProgress) : 1.0
                        opacity: !root.useOriginFlip ? root.openProgress : 1.0

                        Behavior on rotation { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                        ClippingRectangle {
                            anchors.fill: parent
                            radius: root.zoom > 1.01
                                ? 0
                                : (imgTransformHost.flipActive
                                    ? (Appearance.rounding.small + (Appearance.rounding.large - Appearance.rounding.small) * imgTransformHost.p)
                                    : Appearance.rounding.large)
                            color: "transparent"

                            // Instant cached thumbnail underlay ONLY while mainImg decodes its first frame
                            Image {
                                id: thumbUnderlay
                                anchors.fill: parent
                                visible: mainImg.status !== Image.Ready && source.toString().length > 0
                                source: (root.open && root.originRect && root.originRect.thumb) ? String(root.originRect.thumb) : ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: false
                                cache: true
                                autoTransform: true
                            }

                            Image {
                                id: mainImg
                                anchors.fill: parent
                                source: (root.open && !root.isVideo && root.localResolvedPath) ? ("file://" + root.localResolvedPath) : ""
                                fillMode: imgTransformHost.flipActive ? Image.PreserveAspectCrop : Image.PreserveAspectFit
                                asynchronous: true
                                cache: false
                                autoTransform: true
                                // Trilinear mipmap eliminates downsampling aliasing at 100%,
                                // while resizing width/height directly lets Qt sample mip level 0
                                // (100% native pixels) cleanly as you zoom in!
                                smooth: root.zoom < 3.0
                                mipmap: true
                                onStatusChanged: {
                                    if (status === Image.Ready && !root.filmstripReady)
                                        root.filmstripReady = true;
                                }
                            }
                        }
                    }

                    // Wheel zoom toward cursor + double click toward cursor + smooth drag pan
                    MouseArea {
                        anchors.fill: parent
                        property real lastX: 0
                        property real lastY: 0
                        cursorShape: root.zoom > 1.0 ? (pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor) : Qt.ArrowCursor

                        onPressed: mouse => {
                            lastX = mouse.x;
                            lastY = mouse.y;
                        }
                        onPositionChanged: mouse => {
                            if (pressed && root.zoom > 1.0) {
                                root.panX += (mouse.x - lastX);
                                root.panY += (mouse.y - lastY);
                                lastX = mouse.x;
                                lastY = mouse.y;
                            }
                        }
                        onDoubleClicked: mouse => root.setZoomAt(root.zoom > 1.0 ? 1.0 : 2.2, mouse.x, mouse.y)
                        onWheel: wheel => {
                            const factor = wheel.angleDelta.y > 0 ? 1.2 : (1 / 1.2);
                            root.setZoomAt(root.zoom * factor, wheel.x, wheel.y);
                        }
                    }

                    // Phone full-image transfer progress pill
                    Rectangle {
                        visible: root.isPhone && root.phoneTransfer !== null
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 16
                        implicitWidth: progRow.implicitWidth + 24
                        implicitHeight: 34
                        radius: 17
                        color: Appearance.m3colors.m3surfaceContainerHigh

                        RowLayout {
                            id: progRow
                            anchors.centerIn: parent
                            spacing: 8
                            MaterialSymbol {
                                text: "downloading"
                                iconSize: 18
                                color: Appearance.colors.colPrimary
                            }
                            StyledText {
                                text: {
                                    const p = root.phoneTransfer;
                                    if (!p || !p.size)
                                        return Translation.tr("Downloading from phone…");
                                    const pct = Math.min(100, Math.round((p.received / p.size) * 100));
                                    return Translation.tr("Downloading original… %1%").arg(pct);
                                }
                                font.family: Appearance.font.family.main
                                font.pixelSize: 13
                                color: Appearance.colors.colOnSurface
                            }
                        }
                    }
                }

                // ── Video display (rounded when windowed, edge-to-edge in cinema fullscreen) ─
                Item {
                    id: vidStage
                    anchors.fill: parent
                    anchors.leftMargin: root.cinemaFullscreen ? 0 : 84
                    anchors.rightMargin: root.cinemaFullscreen ? 0 : 84
                    anchors.topMargin: root.cinemaFullscreen ? 0 : 8
                    anchors.bottomMargin: root.cinemaFullscreen ? 0 : 8
                    visible: root.isVideo

                    readonly property real vidW: videoOutput.sourceRect.width > 0 ? videoOutput.sourceRect.width : 16
                    readonly property real vidH: videoOutput.sourceRect.height > 0 ? videoOutput.sourceRect.height : 9
                    readonly property real vScale: Math.min(width / vidW, height / vidH)
                    readonly property real fittedW: root.cinemaFullscreen ? width : Math.max(1, Math.round(vidW * vScale))
                    readonly property real fittedH: root.cinemaFullscreen ? height : Math.max(1, Math.round(vidH * vScale))

                    ClippingRectangle {
                        id: vidBox
                        readonly property bool flipActive: root.heroAnimating && root.useOriginFlip && !root.cinemaFullscreen
                        readonly property real p: root.openProgress
                        readonly property real targetX: (vidStage.width - vidStage.fittedW) / 2
                        readonly property real targetY: (vidStage.height - vidStage.fittedH) / 2
                        readonly property real startX: root.originRect ? (Number(root.originRect.x) - 84) : targetX
                        readonly property real startY: root.originRect ? (Number(root.originRect.y) - 76) : targetY
                        readonly property real startW: root.originRect ? Math.max(1, Number(root.originRect.w)) : vidStage.fittedW
                        readonly property real startH: root.originRect ? Math.max(1, Number(root.originRect.h)) : vidStage.fittedH

                        x: flipActive ? (startX + (targetX - startX) * p) : targetX
                        y: flipActive ? (startY + (targetY - startY) * p) : targetY
                        width: flipActive ? Math.max(1, startW + (vidStage.fittedW - startW) * p) : vidStage.fittedW
                        height: flipActive ? Math.max(1, startH + (vidStage.fittedH - startH) * p) : vidStage.fittedH
                        radius: root.cinemaFullscreen
                            ? 0
                            : (flipActive
                                ? (Appearance.rounding.small + (Appearance.rounding.large - Appearance.rounding.small) * p)
                                : Appearance.rounding.large)
                        color: "#000000"
                        scale: !root.useOriginFlip ? (0.92 + 0.08 * root.openProgress) : 1.0
                        opacity: !root.useOriginFlip ? root.openProgress : 1.0

                        // Video thumbnail poster underlay until first decoded frame arrives
                        Image {
                            anchors.fill: parent
                            visible: root.open && root.isVideo && player.position === 0 && source.toString().length > 0
                            source: (root.originRect && root.originRect.thumb) ? String(root.originRect.thumb) : ""
                            fillMode: vidBox.flipActive ? Image.PreserveAspectCrop : Image.PreserveAspectFit
                            asynchronous: false
                            cache: true
                        }

                        VideoOutput {
                            id: videoOutput
                            anchors.fill: parent
                            fillMode: VideoOutput.PreserveAspectFit
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: root.chromeVisible ? Qt.ArrowCursor : Qt.BlankCursor
                        onPositionChanged: mouse => root.handlePointerMove(mouse.x, mouse.y)
                        onClicked: {
                            root.bumpPointerActivity();
                            if (player.playbackState === MediaPlayer.PlayingState)
                                player.pause();
                            else
                                player.play();
                        }
                        onDoubleClicked: root.toggleFullscreenRequested()
                    }

                    // Phone video mounting pill
                    Rectangle {
                        visible: root.isPhone && root.isVideo && !root.localResolvedPath
                        anchors.centerIn: parent
                        implicitWidth: vmRow.implicitWidth + 28
                        implicitHeight: 44
                        radius: 22
                        color: Appearance.m3colors.m3surfaceContainerHigh

                        RowLayout {
                            id: vmRow
                            anchors.centerIn: parent
                            spacing: 10
                            MaterialSymbol {
                                text: "smartphone"
                                iconSize: 20
                                color: Appearance.colors.colPrimary
                            }
                            StyledText {
                                text: phoneBridge.videoMounting
                                    ? Translation.tr("Mounting phone storage for playback…")
                                    : Translation.tr("Preparing video from phone…")
                                font.family: Appearance.font.family.main
                                font.pixelSize: 14
                                color: Appearance.colors.colOnSurface
                            }
                        }
                    }
                }

                // ── Prev / Next MaterialShape buttons (auto-hide in cinema fullscreen) ─
                MouseArea {
                    id: prevHover
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    width: 56
                    height: 56
                    enabled: root.canPrev && root.chromeVisible
                    opacity: root.chromeVisible ? (root.canPrev ? 1.0 : 0.28) : 0.0
                    hoverEnabled: true
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: root.step(-1)
                    Behavior on opacity { NumberAnimation { duration: 200 } }

                    MaterialShape {
                        anchors.fill: parent
                        shape: (prevHover.containsMouse && root.canPrev)
                            ? MaterialShape.Shape.Square
                            : MaterialShape.Shape.Circle
                        color: (prevHover.containsMouse && root.canPrev)
                            ? Appearance.colors.colSecondaryContainer
                            : Appearance.m3colors.m3surfaceContainerHigh

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "chevron_left"
                            iconSize: 28
                            color: (prevHover.containsMouse && root.canPrev)
                                ? Appearance.colors.colOnSecondaryContainer
                                : Appearance.colors.colOnSurface
                        }
                    }
                }

                MouseArea {
                    id: nextHover
                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    width: 56
                    height: 56
                    enabled: root.canNext && root.chromeVisible
                    opacity: root.chromeVisible ? (root.canNext ? 1.0 : 0.28) : 0.0
                    hoverEnabled: true
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: root.step(1)
                    Behavior on opacity { NumberAnimation { duration: 200 } }

                    MaterialShape {
                        anchors.fill: parent
                        shape: (nextHover.containsMouse && root.canNext)
                            ? MaterialShape.Shape.Square
                            : MaterialShape.Shape.Circle
                        color: (nextHover.containsMouse && root.canNext)
                            ? Appearance.colors.colSecondaryContainer
                            : Appearance.m3colors.m3surfaceContainerHigh

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "chevron_right"
                            iconSize: 28
                            color: (nextHover.containsMouse && root.canNext)
                                ? Appearance.colors.colOnSecondaryContainer
                                : Appearance.colors.colOnSurface
                        }
                    }
                }
            }

            // ── Linear Gradient Blur Backdrop under Header & Filmstrip during immersiveZoom ─
            // Exact CoverMediaWidget pattern: full-stage MultiEffect + EdgeFadeMask shader
            // + subtle dark scrims. Lazy-loaded ONLY while zoomed (`root.immersiveZoom`).
            Loader {
                id: zoomBlurLoader
                anchors.fill: parent
                z: 4
                active: root.immersiveZoom
                visible: active
                enabled: false

                sourceComponent: Item {
                    anchors.fill: parent

                    ShaderEffectSource {
                        id: stageBlurSrc
                        anchors.fill: parent
                        sourceItem: stage
                        live: true
                        hideSource: false
                        visible: false
                    }

                    // Top linear blur band fading smoothly below the header (~70% tighter height)
                    Item {
                        anchors.fill: parent
                        layer.enabled: true
                        layer.effect: EdgeFadeMask {
                            verticalAxis: true
                            startClear: -0.01
                            startSolid: 0.0
                            endSolid: 0.055
                            endClear: 0.13
                        }

                        MultiEffect {
                            anchors.fill: parent
                            source: stageBlurSrc
                            autoPaddingEnabled: false
                            blurEnabled: true
                            blurMax: 64
                            blur: 0.85
                            saturation: 0.15
                        }
                    }

                    // Bottom linear blur band fading smoothly above the gallery roll (~70% tighter height)
                    Item {
                        anchors.fill: parent
                        layer.enabled: true
                        layer.effect: EdgeFadeMask {
                            verticalAxis: true
                            startClear: 0.87
                            startSolid: 0.945
                            endSolid: 1.0
                            endClear: 1.01
                        }

                        MultiEffect {
                            anchors.fill: parent
                            source: stageBlurSrc
                            autoPaddingEnabled: false
                            blurEnabled: true
                            blurMax: 64
                            blur: 0.85
                            saturation: 0.15
                        }
                    }

                    // Top contrast scrim for white icons/title over bright zoomed images
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        height: 84
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: ColorUtils.transparentize(Appearance.m3colors.m3surfaceContainerLowest, 0.36) }
                            GradientStop { position: 0.6; color: ColorUtils.transparentize(Appearance.m3colors.m3surfaceContainerLowest, 0.72) }
                            GradientStop { position: 1.0; color: "transparent" }
                        }
                    }

                    // Bottom contrast scrim for gallery roll thumbnails over bright zoomed images
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 88
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: "transparent" }
                            GradientStop { position: 0.4; color: ColorUtils.transparentize(Appearance.m3colors.m3surfaceContainerLowest, 0.70) }
                            GradientStop { position: 1.0; color: ColorUtils.transparentize(Appearance.m3colors.m3surfaceContainerLowest, 0.34) }
                        }
                    }
                }
            }

            // ── Top Bar (overlays with subtle gradient in cinema fullscreen, auto-hides) ─
            Rectangle {
                id: topBar
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 68
                z: 5
                opacity: (root.chromeVisible ? 1.0 : 0.0) * root.chromeReveal
                visible: opacity > 0.01
                color: "transparent"
                transform: Translate { y: (1.0 - root.chromeReveal) * -14 }
                Behavior on opacity { NumberAnimation { duration: 180 } }

                // Subtle top scrim when overlaying fullscreen video
                Rectangle {
                    anchors.fill: parent
                    visible: root.cinemaFullscreen
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.72) }
                        GradientStop { position: 1.0; color: "transparent" }
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 8

                    ViewerIconBtn {
                        implicitWidth: 44
                        implicitHeight: 44
                        iconName: "arrow_back"
                        iconPixelSize: 22
                        tipText: Translation.tr("Back (Esc)")
                        onClicked: root.requestClose()
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText {
                            text: root.itemTitle
                            font.family: Appearance.font.family.main
                            font.pixelSize: 17
                            font.variableAxes: ({ "wght": 620, "wdth": 100, "ROND": 100 })
                            color: Appearance.colors.colOnSurface
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        StyledText {
                            text: {
                                if (!root.currentItem)
                                    return "";
                                const ts = root.isPhone ? Number(root.currentItem.taken || 0) : Number(root.currentItem.mtime || 0);
                                const parts = [];
                                if (ts > 0) {
                                    const d = new Date(ts);
                                    parts.push(`${d.getDate()} ${store.monthShortName(d.getMonth())} ${d.getFullYear()} · ${store.pad2(d.getHours())}:${store.pad2(d.getMinutes())}`);
                                }
                                if (root.isPhone) {
                                    parts.push(phoneBridge.deviceName || Translation.tr("Phone"));
                                } else if (root.currentItem.folder) {
                                    parts.push(String(root.currentItem.folder).split("/").join(" › "));
                                }
                                return parts.join(" · ");
                            }
                            font.family: Appearance.font.family.main
                            font.pixelSize: 13
                            color: Appearance.colors.colSubtext
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }

                    // Image zoom & rotate controls
                    RowLayout {
                        visible: !root.isVideo
                        spacing: 2

                        ViewerIconBtn {
                            enabled: root.zoom > 1.0
                            opacity: enabled ? 1.0 : 0.35
                            iconName: "zoom_out"
                            tipText: Translation.tr("Zoom out (-)")
                            onClicked: root.setZoom(root.zoom - 0.5)
                        }

                        StyledText {
                            Layout.preferredWidth: 52
                            horizontalAlignment: Text.AlignHCenter
                            text: `${Math.round(root.zoom * 100)}%`
                            font.family: Appearance.font.family.main
                            font.pixelSize: 16
                            font.variableAxes: ({ "wght": 720, "wdth": 40, "ROND": 100 })
                            color: Appearance.colors.colOnSurfaceVariant
                        }

                        ViewerIconBtn {
                            enabled: root.zoom < 4.0
                            opacity: enabled ? 1.0 : 0.35
                            iconName: "zoom_in"
                            tipText: Translation.tr("Zoom in (+)")
                            onClicked: root.setZoom(root.zoom + 0.5)
                        }

                        ViewerIconBtn {
                            iconName: "rotate_right"
                            tipText: Translation.tr("Rotate (R)")
                            onClicked: root.rotationDeg = (root.rotationDeg + 90) % 360
                        }
                    }

                    // Set as Wallpaper (images only)
                    ViewerIconBtn {
                        visible: !root.isVideo
                        iconName: "wallpaper"
                        tipText: Translation.tr("Set as wallpaper")
                        onClicked: root.triggerImageShellAction("wallpaper")
                    }

                    // Set as Avatar (images only)
                    ViewerIconBtn {
                        visible: !root.isVideo
                        iconName: "account_circle"
                        tipText: Translation.tr("Set as profile avatar")
                        onClicked: root.triggerImageShellAction("avatar")
                    }

                    // Send to Phone (PC media) OR Save to PC (Phone media)
                    ViewerIconBtn {
                        filledTonal: true
                        iconName: root.isPhone ? "download" : "send_to_mobile"
                        tipText: root.isPhone
                            ? Translation.tr("Save to PC (~/Pictures/Phone)")
                            : Translation.tr("Send to phone via ii tools")
                        onClicked: {
                            if (!root.currentItem)
                                return;
                            if (root.isPhone)
                                phoneBridge.saveItemToPc(String(root.currentItem.id));
                            else
                                phoneBridge.sendFileToPhone(root.currentItem.path);
                        }
                    }

                    // Favorite (local media)
                    ViewerIconBtn {
                        visible: !root.isPhone
                        activeState: root.currentItem !== null && store.isFav(root.currentItem.path)
                        iconName: "favorite"
                        tipText: activeState ? Translation.tr("Remove from favorites") : Translation.tr("Add to favorites")
                        onClicked: if (root.currentItem) store.toggleFav(root.currentItem.path)
                    }

                    // Copy path
                    ViewerIconBtn {
                        visible: root.localResolvedPath.length > 0
                        iconName: "content_copy"
                        iconPixelSize: 19
                        tipText: Translation.tr("Copy file path")
                        onClicked: store.copyPath(root.localResolvedPath)
                    }

                    // Info sheet toggle
                    ViewerIconBtn {
                        activeState: root.infoOpen
                        iconName: "info"
                        tipText: Translation.tr("Details (I)")
                        onClicked: root.infoOpen = !root.infoOpen
                    }

                    // Trash (local media only)
                    ViewerIconBtn {
                        visible: !root.isPhone
                        dangerHover: true
                        iconName: "delete"
                        tipText: Translation.tr("Move to trash (Del)")
                        onClicked: root.confirmDeleteOpen = true
                    }
                }
            }

            // ── Bottom Dock: Video controls + Trash confirm + Edge-to-edge Filmstrip ─
            ColumnLayout {
                id: bottomDock
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.leftMargin: 0
                anchors.rightMargin: 0
                anchors.bottomMargin: root.cinemaFullscreen ? 24 : 14
                z: 5
                spacing: 8
                opacity: (root.chromeVisible ? 1.0 : 0.0) * root.chromeReveal
                visible: opacity > 0.01
                transform: Translate { y: (1.0 - root.chromeReveal) * 20 }
                Behavior on opacity { NumberAnimation { duration: 180 } }

                // M3E Floating Video Controls Pill
                Rectangle {
                    visible: root.isVideo
                    Layout.fillWidth: true
                    Layout.leftMargin: 20
                    Layout.rightMargin: 20
                    implicitHeight: 68
                    radius: Appearance.rounding.full
                    color: root.cinemaFullscreen
                        ? Qt.rgba(Appearance.colors.colLayer1.r, Appearance.colors.colLayer1.g, Appearance.colors.colLayer1.b, 0.92)
                        : Appearance.colors.colLayer1

                    HoverHandler {
                        onHoveredChanged: root.controlsHovered = hovered
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 12
                        spacing: 6

                        // Morphing Play / Pause button (snappy 110ms radius!)
                        RippleButton {
                            id: playPauseBtn
                            readonly property bool playing: player.playbackState === MediaPlayer.PlayingState
                            implicitWidth: 60
                            implicitHeight: 52
                            buttonRadius: playing ? 16 : 26
                            colBackground: playing ? Appearance.colors.colPrimaryContainer : Appearance.colors.colPrimary
                            colBackgroundHover: playing ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colPrimaryHover
                            Behavior on buttonRadius { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                            onClicked: {
                                if (playing)
                                    player.pause();
                                else
                                    player.play();
                            }
                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                text: playPauseBtn.playing ? "pause" : "play_arrow"
                                fill: 1
                                iconSize: 28
                                color: playPauseBtn.playing ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnPrimary
                            }
                            StyledToolTip {
                                requireOverlay: false
                                text: playPauseBtn.playing ? Translation.tr("Pause (Space)") : Translation.tr("Play (Space)")
                            }
                        }

                        // Larger -10s / +10s buttons
                        ViewerIconBtn {
                            implicitWidth: 42
                            implicitHeight: 42
                            iconName: "replay_10"
                            iconPixelSize: 26
                            tipText: Translation.tr("Back 10s (J)")
                            onClicked: player.position = Math.max(0, player.position - 10000)
                        }

                        ViewerIconBtn {
                            implicitWidth: 42
                            implicitHeight: 42
                            iconName: "forward_10"
                            iconPixelSize: 26
                            tipText: Translation.tr("Forward 10s (L)")
                            onClicked: player.position = Math.min(player.duration, player.position + 10000)
                        }

                        // Compact vertically-centered Current / Total time
                        RowLayout {
                            Layout.alignment: Qt.AlignVCenter
                            Layout.leftMargin: 4
                            Layout.rightMargin: 6
                            spacing: 4
                            StyledText {
                                Layout.alignment: Qt.AlignVCenter
                                text: store.formatTime(player.position / 1000)
                                font.family: Appearance.font.family.main
                                font.pixelSize: 22
                                font.variableAxes: ({ "wght": 760, "wdth": 38, "ROND": 100 })
                                color: Appearance.colors.colOnSurface
                            }
                            StyledText {
                                Layout.alignment: Qt.AlignVCenter
                                text: "/ " + store.formatTime(player.duration / 1000)
                                font.family: Appearance.font.family.main
                                font.pixelSize: 15
                                font.variableAxes: ({ "wght": 520, "wdth": 38, "ROND": 100 })
                                color: Appearance.colors.colSubtext
                            }
                        }

                        // M3E Wavy Progress Bar (interactive seek)
                        Item {
                            id: seekTrack
                            Layout.fillWidth: true
                            Layout.preferredHeight: 40

                            readonly property real progress: player.duration > 0
                                ? Math.max(0, Math.min(1, player.position / player.duration))
                                : 0
                            readonly property real thumbX: Math.max(2, Math.min(width - 6, progress * width))

                            Rectangle {
                                x: Math.min(seekTrack.width - 2, seekTrack.thumbX + 8)
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.max(0, seekTrack.width - x - 2)
                                height: 4
                                radius: 2
                                color: Appearance.m3colors.m3surfaceContainerHighest
                            }

                            WavyLine {
                                x: 2
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.max(0, seekTrack.thumbX - 6)
                                height: 24
                                lineWidth: 4
                                color: Appearance.colors.colPrimary
                                frequency: Math.max(2, Math.round(seekTrack.width / 36))
                                fullLength: Math.max(100, seekTrack.width)
                                amplitudeMultiplier: player.playbackState === MediaPlayer.PlayingState ? 0.9 : 0.0
                                animateWave: player.playbackState === MediaPlayer.PlayingState
                                Behavior on amplitudeMultiplier { NumberAnimation { duration: 220 } }
                            }

                            Rectangle {
                                x: seekTrack.thumbX - 2
                                anchors.verticalCenter: parent.verticalCenter
                                width: 4
                                height: 26
                                radius: 2
                                color: Appearance.colors.colPrimary
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                function seekAt(mx): void {
                                    if (player.duration <= 0 || seekTrack.width <= 0)
                                        return;
                                    const frac = Math.max(0, Math.min(1, mx / seekTrack.width));
                                    player.position = Math.round(frac * player.duration);
                                }
                                onPressed: mouse => seekAt(mouse.x)
                                onPositionChanged: mouse => { if (pressed) seekAt(mouse.x); }
                            }
                        }

                        // Mute button + compact Volume slider with breathing room before speed pill
                        RowLayout {
                            Layout.rightMargin: 10
                            spacing: 2

                            ViewerIconBtn {
                                implicitWidth: 38
                                implicitHeight: 38
                                iconName: (root.muted || root.volume <= 0.01)
                                    ? "volume_off"
                                    : (root.volume < 0.5 ? "volume_down" : "volume_up")
                                tipText: (root.muted || root.volume <= 0.01)
                                    ? Translation.tr("Unmute (M)")
                                    : Translation.tr("Mute (M)")
                                onClicked: {
                                    root.muted = !root.muted;
                                    if (!root.muted && root.volume <= 0.01) {
                                        root.volume = 0.6;
                                        store.setVideoVolume(0.6);
                                    }
                                }
                            }

                            Slider {
                                id: volSlider
                                Layout.preferredWidth: 64
                                leftPadding: 0
                                rightPadding: 0
                                from: 0
                                to: 1
                                stepSize: 0.05
                                value: root.muted ? 0 : root.volume
                                onMoved: {
                                    root.volume = value;
                                    root.muted = value <= 0.01;
                                    store.setVideoVolume(value);
                                }

                                HoverHandler {
                                    cursorShape: Qt.PointingHandCursor
                                }

                                background: Rectangle {
                                    x: volSlider.leftPadding
                                    y: volSlider.topPadding + volSlider.availableHeight / 2 - height / 2
                                    width: volSlider.availableWidth
                                    height: 4
                                    radius: 2
                                    color: Appearance.m3colors.m3surfaceContainerHighest

                                    Rectangle {
                                        width: volSlider.visualPosition * parent.width
                                        height: parent.height
                                        radius: 2
                                        color: Appearance.colors.colPrimary
                                    }
                                }
                                handle: Rectangle {
                                    x: volSlider.leftPadding + volSlider.visualPosition * (volSlider.availableWidth - width)
                                    y: volSlider.topPadding + volSlider.availableHeight / 2 - height / 2
                                    width: 14
                                    height: 14
                                    radius: 7
                                    color: Appearance.colors.colPrimary
                                }
                            }
                        }

                        // Speed cycle pill (perfectly centered text)
                        RippleButton {
                            implicitWidth: 54
                            implicitHeight: 38
                            leftPadding: 0
                            rightPadding: 0
                            buttonRadius: hovered ? 13 : 19
                            colBackground: Appearance.colors.colSecondaryContainer
                            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                            Behavior on buttonRadius { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                            onClicked: {
                                root.speedIdx = (root.speedIdx + 1) % root.speeds.length;
                                player.playbackRate = root.speeds[root.speedIdx];
                            }
                            contentItem: StyledText {
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                text: `${root.speeds[root.speedIdx]}×`
                                font.family: Appearance.font.family.main
                                font.pixelSize: 14
                                font.variableAxes: ({ "wght": 720, "wdth": 60, "ROND": 100 })
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                            StyledToolTip {
                                requireOverlay: false
                                text: Translation.tr("Playback speed")
                            }
                        }

                        // Loop toggle
                        ViewerIconBtn {
                            implicitWidth: 38
                            implicitHeight: 38
                            activeState: root.loopVideo
                            iconName: "repeat"
                            iconPixelSize: 19
                            tipText: Translation.tr("Repeat")
                            onClicked: {
                                root.loopVideo = !root.loopVideo;
                                player.loops = root.loopVideo ? MediaPlayer.Infinite : 1;
                            }
                        }

                        // Fullscreen toggle (adaptive icon)
                        ViewerIconBtn {
                            implicitWidth: 38
                            implicitHeight: 38
                            iconName: root.isFullscreen ? "fullscreen_exit" : "fullscreen"
                            iconPixelSize: 21
                            tipText: root.isFullscreen ? Translation.tr("Exit fullscreen (F)") : Translation.tr("Fullscreen (F)")
                            onClicked: root.toggleFullscreenRequested()
                        }
                    }
                }

                // Inline Move-to-Trash confirmation bar
                Rectangle {
                    visible: root.confirmDeleteOpen
                    Layout.fillWidth: true
                    Layout.leftMargin: 20
                    Layout.rightMargin: 20
                    implicitHeight: 62
                    radius: Appearance.rounding.large
                    color: Appearance.m3colors.m3surfaceContainerHigh

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 12
                        spacing: 12

                        MaterialShape {
                            implicitWidth: 40
                            implicitHeight: 40
                            shape: MaterialShape.Shape.Cookie9Sided
                            color: Appearance.m3colors.m3errorContainer
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "delete"
                                iconSize: 20
                                color: Appearance.m3colors.m3onErrorContainer
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            StyledText {
                                text: Translation.tr("Move to trash?")
                                font.family: Appearance.font.family.main
                                font.pixelSize: 16
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnSurface
                            }
                            StyledText {
                                text: root.currentItem ? String(root.currentItem.file ?? "") : ""
                                font.family: Appearance.font.family.main
                                font.pixelSize: 13
                                color: Appearance.colors.colOnSurfaceVariant
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }

                        RippleButton {
                            implicitHeight: 40
                            leftPadding: 16
                            rightPadding: 16
                            buttonRadius: 20
                            colBackground: "transparent"
                            colBackgroundHover: Appearance.colors.colLayer2Hover
                            onClicked: root.confirmDeleteOpen = false
                            contentItem: StyledText {
                                anchors.centerIn: parent
                                text: Translation.tr("Cancel")
                                font.family: Appearance.font.family.main
                                font.pixelSize: 14
                                color: Appearance.colors.colOnSurface
                            }
                        }

                        RippleButton {
                            implicitHeight: 40
                            leftPadding: 16
                            rightPadding: 18
                            buttonRadius: 20
                            colBackground: Appearance.m3colors.m3errorContainer
                            colBackgroundHover: Appearance.m3colors.m3error
                            onClicked: {
                                root.confirmDeleteOpen = false;
                                if (root.currentItem && !root.isPhone)
                                    store.trashLocalItem(root.currentItem.path);
                            }
                            contentItem: RowLayout {
                                spacing: 6
                                MaterialSymbol {
                                    text: "delete"
                                    iconSize: 18
                                    color: Appearance.m3colors.m3onErrorContainer
                                }
                                StyledText {
                                    text: Translation.tr("Move")
                                    font.family: Appearance.font.family.main
                                    font.pixelSize: 14
                                    font.weight: Font.DemiBold
                                    color: Appearance.m3colors.m3onErrorContainer
                                }
                            }
                        }
                    }
                }

                // Edge-to-edge virtualized bottom filmstrip (transparent bg, no side clipping!)
                ListView {
                    id: filmstrip
                    visible: !root.cinemaFullscreen
                    Layout.fillWidth: true
                    implicitHeight: 64
                    orientation: ListView.Horizontal
                    leftMargin: 16
                    rightMargin: 16
                    spacing: 6
                    clip: true
                    cacheBuffer: 120
                    model: root.filmstripReady ? store.viewerList : []

                    delegate: Item {
                        id: fsItem
                        required property var modelData
                        required property int index
                        readonly property bool isCurrent: index === store.viewerIndex
                        readonly property string thumbSrc: {
                            if (root.isPhone) {
                                void phoneBridge.thumbRevision;
                                return phoneBridge.thumbPath(modelData.id);
                            }
                            void store.videoMetaRev;
                            return store.thumbUrlFor(modelData);
                        }

                        width: 60
                        height: 60

                        Rectangle {
                            anchors.fill: parent
                            radius: 14
                            color: fsItem.isCurrent ? Appearance.colors.colPrimary : "transparent"

                            ClippingRectangle {
                                anchors.fill: parent
                                anchors.margins: 3
                                radius: 11
                                color: Appearance.colors.colLayer2

                                Image {
                                    anchors.fill: parent
                                    source: fsItem.thumbSrc
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    cache: false
                                    sourceSize: Qt.size(96, 96)
                                    opacity: fsItem.isCurrent || fsMouse.containsMouse ? 1.0 : 0.55
                                }

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    visible: (root.isPhone ? fsItem.modelData.kind === "video" : fsItem.modelData.type === "video")
                                    text: "play_arrow"
                                    fill: 1
                                    iconSize: 18
                                    color: "#FFFFFF"
                                }
                            }
                        }

                        MouseArea {
                            id: fsMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: store.viewerIndex = fsItem.index
                        }
                    }
                }
            }
        }

        // ── Smoothly Sliding Details Info Side Sheet ────────────────────
        Item {
            id: infoDrawer
            Layout.preferredWidth: root.infoOpen ? 344 : 0
            Layout.fillHeight: true
            clip: true
            visible: Layout.preferredWidth > 1

            Behavior on Layout.preferredWidth {
                NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
            }

            Rectangle {
                anchors.fill: parent
                anchors.topMargin: 12
                anchors.rightMargin: 12
                anchors.bottomMargin: 12
                radius: Appearance.rounding.verylarge
                color: Appearance.m3colors.m3surfaceContainerHigh
                opacity: root.infoOpen ? 1.0 : 0.0
                clip: true

                Behavior on opacity { NumberAnimation { duration: 200 } }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 12

                    RowLayout {
                        Layout.fillWidth: true
                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Details")
                            font.family: Appearance.font.family.main
                            font.pixelSize: 22
                            font.variableAxes: ({ "wght": 640, "wdth": 110, "ROND": 100 })
                            color: Appearance.colors.colOnSurface
                        }
                        ViewerIconBtn {
                            implicitWidth: 36
                            implicitHeight: 36
                            iconName: "close"
                            iconPixelSize: 18
                            tipText: Translation.tr("Close details")
                            onClicked: root.infoOpen = false
                        }
                    }

                    Flickable {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentHeight: infoCol.implicitHeight
                        clip: true

                        ColumnLayout {
                            id: infoCol
                            width: parent.width
                            spacing: 8

                            // Big clock & date header
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.bottomMargin: 6
                                spacing: 2
                                readonly property var dt: new Date(
                                    root.currentItem
                                        ? (root.isPhone ? Number(root.currentItem.taken || 0) : Number(root.currentItem.mtime || 0))
                                        : 0
                                )
                                StyledText {
                                    text: `${store.pad2(parent.dt.getHours())}:${store.pad2(parent.dt.getMinutes())}`
                                    font.family: Appearance.font.family.main
                                    font.pixelSize: 64
                                    lineHeight: 0.85
                                    font.variableAxes: ({ "wght": 760, "wdth": 36, "ROND": 100 })
                                    color: Appearance.colors.colPrimary
                                }
                                StyledText {
                                    text: `${store.weekdayName(parent.dt.getDay())}, ${parent.dt.getDate()} ${store.monthFullName(parent.dt.getMonth())}`
                                    font.family: Appearance.font.family.main
                                    font.pixelSize: 16
                                    font.italic: true
                                    color: Appearance.colors.colOnSurface
                                }
                            }

                            Repeater {
                                model: {
                                    const it = root.currentItem;
                                    if (!it)
                                        return [];
                                    const rows = [];
                                    rows.push({
                                        icon: "description",
                                        cap: Translation.tr("FILE"),
                                        val: root.isPhone ? String(it.name ?? it.id) : String(it.file ?? "")
                                    });
                                    rows.push({
                                        icon: root.isPhone ? "smartphone" : "folder",
                                        cap: root.isPhone ? Translation.tr("DEVICE") : Translation.tr("FOLDER"),
                                        val: root.isPhone
                                            ? (phoneBridge.deviceName || Translation.tr("Phone"))
                                            : String(it.folder ?? "")
                                    });
                                    const w = Number(it.w || (!root.isVideo ? mainImg.implicitWidth : 0));
                                    const h = Number(it.h || (!root.isVideo ? mainImg.implicitHeight : 0));
                                    if (w > 0 && h > 0) {
                                        const mp = ((w * h) / 1e6).toFixed(1);
                                        rows.push({
                                            icon: "aspect_ratio",
                                            cap: Translation.tr("RESOLUTION"),
                                            val: root.isVideo ? `${w} × ${h}` : `${w} × ${h} · ${mp} MP`
                                        });
                                    }
                                    const sz = store.formatBytes(it.size);
                                    if (sz) {
                                        rows.push({
                                            icon: "data_usage",
                                            cap: Translation.tr("SIZE"),
                                            val: sz
                                        });
                                    }
                                    rows.push({
                                        icon: root.isVideo ? "movie" : "image",
                                        cap: Translation.tr("TYPE"),
                                        val: root.isVideo
                                            ? Translation.tr("Video")
                                            : (it.ext ? `${it.ext} ${Translation.tr("Image")}` : Translation.tr("Image"))
                                    });
                                    return rows;
                                }

                                delegate: Rectangle {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    implicitHeight: 58
                                    radius: Appearance.rounding.small
                                    color: Appearance.m3colors.m3surfaceContainerHighest

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 12
                                        anchors.rightMargin: 12
                                        spacing: 12

                                        MaterialShape {
                                            implicitWidth: 34
                                            implicitHeight: 34
                                            shape: MaterialShape.Shape.Cookie9Sided
                                            color: Appearance.colors.colPrimaryContainer
                                            MaterialSymbol {
                                                anchors.centerIn: parent
                                                text: parent.parent.parent.modelData.icon
                                                iconSize: 17
                                                color: Appearance.colors.colOnPrimaryContainer
                                            }
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 1
                                            StyledText {
                                                text: parent.parent.parent.modelData.cap
                                                font.family: Appearance.font.family.main
                                                font.pixelSize: 10
                                                font.letterSpacing: 0.8
                                                font.variableAxes: ({ "wght": 720, "wdth": 100, "ROND": 100 })
                                                color: Appearance.colors.colOnSurfaceVariant
                                            }
                                            StyledText {
                                                text: parent.parent.parent.modelData.val
                                                font.family: Appearance.font.family.main
                                                font.pixelSize: 13
                                                font.variableAxes: ({ "wght": 600, "wdth": 100, "ROND": 100 })
                                                color: Appearance.colors.colOnSurface
                                                elide: Text.ElideMiddle
                                                Layout.fillWidth: true
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
