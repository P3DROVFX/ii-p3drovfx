// Contract animation v3: removed Behavior conflicts (forced reload 2026-07-13-18:30)
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets
import Quickshell.Io
import Quickshell.Services.Mpris
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.common.models
import qs.services
import Qt5Compat.GraphicalEffects

Item {
    id: root
    anchors.fill: parent
    transformOrigin: Item.Center

    readonly property MprisPlayer player: MprisController.activePlayer
    readonly property bool playing: player ? player.playbackState === MprisPlaybackState.Playing : false
    readonly property string artUrl: MprisController.artUrl
    readonly property string title: (MprisController.activeTrack && MprisController.activeTrack.title) ? MprisController.activeTrack.title : "No title"
    readonly property string artist: (MprisController.activeTrack && MprisController.activeTrack.artist) ? MprisController.activeTrack.artist : "Unknown Artist"
    readonly property string identity: player ? (player.identity ?? "") : ""
    readonly property var activeTrackRef: MprisController.activeTrack

    property bool isExpanded: false
    property real expandContractRatio: 1.4

    // Drives the whole-widget scale-down during contract. Independent from the
    // individual layout scales so the size change is always visible even if
    // Behavior on scale is dormant on child items.
    property real _contractScale: 1.0
    scale: _contractScale

    readonly property Item widgetBg: {
        var p = root.parent;
        if (p && p.parent) {
            return p.parent;
        }
        return root;
    }

    readonly property real notchBottomRadius: {
        var p = root.parent;
        while (p) {
            if (p.notchBackground && p.notchBackground.bottomRadius !== undefined)
                return p.notchBackground.bottomRadius;
            p = p.parent;
        }
        return Appearance.rounding.windowRounding;
    }

    readonly property int elementHeight: Math.max(20, Math.min(42, root.height - 10))
    readonly property int barWidth: Math.max(4, Math.min(8, elementHeight / 5))

    property string displayTitle: ""
    property string displayArtist: ""
    property real titleOpacity: 1.0
    property real titleYOffset: 0.0

    property string activeLyricText: ""
    property real lyricOpacity: 1.0
    property real lyricYOffset: 0.0

    property string currentArtUrl: ""
    property string previousArtUrl: ""
    property string pendingArtUrl: ""
    property bool awaitingImageLoad: false
    property bool artTransitioning: false
    property int artCacheBuster: 0
    property bool _initialized: false

    property real artOutgoingBlur: 0
    property real artOutgoingScale: 1.0
    property real artIncomingBlur: 0
    property real artIncomingScale: 1.0
    property real artVignetteBlur: root.playing ? 50 : 90
    property real artVignetteInner: 0.2
    property real artVignetteOuter: 0.85

    // Soft patch behind one element over bright art (see refreshArtPatches). The blurred edge lets
    // the cover fade into it instead of showing a box.
    component ArtPatch: RectangularShadow {
        id: patch
        required property string zone
        readonly property var spec: root.artPatches[patch.zone] ?? null
        readonly property real pad: 6
        visible: opacity > 0
        x: (patch.spec?.x ?? 0) - patch.pad
        y: (patch.spec?.y ?? 0) - patch.pad
        width: (patch.spec?.w ?? 0) + 2 * patch.pad
        height: (patch.spec?.h ?? 0) + 2 * patch.pad
        radius: Math.min(height / 2, 16)
        blur: 20
        spread: 0
        color: patch.spec?.white ? "white" : "black"
        opacity: patch.spec?.alpha ?? 0
        cached: true

        Behavior on opacity {
            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
        }
    }

    readonly property color containerFillColor: root.useDynamicColors ? ColorUtils.mix(Appearance.m3colors.m3primaryContainer,
        root.artDominantColor, 0.85) : Appearance.m3colors.m3primaryContainer
    // The fade toward the bottom edge (and the paused dim) goes toward the island's own background:
    // black in dark mode, white in light mode, where darkening would sink the dark text into it
    readonly property color artDimColor: Appearance.m3colors.darkmode ? "black" : "white"
    readonly property color containerContentColor: Appearance.m3colors.m3onPrimaryContainer
    // The played part of the seek wave. In dark mode it is lifted halfway to the text colour: the
    // cover's primary alone can be a mid tone (pink on a red cover) that no patch can rescue.
    readonly property color seekColor: {
        const primary = root.useDynamicColors ? root.blendedColors.colPrimary : Appearance.colors.colPrimary;
        return Appearance.m3colors.darkmode ? ColorUtils.mix(Appearance.colors.colOnSurface, primary, 0.5) : primary;
    }
    readonly property color lightTrackColor: root.useDynamicColors ? root.blendedColors.colLayer1 : Appearance.colors.colSurfaceContainer
    readonly property color lightVizColor: root.useDynamicColors ? root.blendedColors.colPrimary : Appearance.colors.colOnSurface


    property bool isLocalArt: root.artUrl.startsWith("file://")
    property string artDownloadLocation: Directories.coverArt
    property string artFileName: Qt.md5(root.artUrl)
    property string artFilePath: `${artDownloadLocation}/${artFileName}`
    property bool artDownloaded: false

    readonly property string localArtFilePath: {
        if (!root.artUrl || root.artUrl === "") return "";
        if (root.isLocalArt) return FileUtils.trimFileProtocol(root.artUrl);
        return root.artDownloaded ? root.artFilePath : "";
    }

    readonly property string resolvedArtPath: root.localArtFilePath !== "" ? Qt.resolvedUrl(root.localArtFilePath) : ""

    readonly property bool useDynamicColors: Config.options.media.dynamicAlbumColors && root.localArtFilePath !== ""

    ColorQuantizer {
        id: colorQuantizer
        source: root.resolvedArtPath
        depth: 0
        rescaleSize: 1
    }

    property color artDominantColor: ColorUtils.mix(
        (colorQuantizer?.colors[0] ?? Appearance.colors.colPrimary),
        Appearance.colors.colPrimaryContainer, 0.8
    ) || Appearance.m3colors.m3secondaryContainer

    property QtObject blendedColors: AdaptedMaterialScheme {
        color: root.artDominantColor
    }

    // ── Cover-aware backdrop ─────────────────────────────────────────────────
    // The cover is shrunk to a small grid once per track (artSampler). Each text or control is then
    // checked against what is really painted behind it — art at 85 % over the island, then the
    // vertical dim — and gets a soft dark patch (ArtPatch) just strong enough for its colour to
    // stay readable. Dark art gets no patch; no grid (remote art still downloading, magick failed)
    // leaves the plain look.
    readonly property int artGridSize: 24
    property var artGrid: null
    property var artPatches: ({})

    // Luminance samples of what sits behind `item` inside the art layer `bg` (text items only over
    // their glyphs), plus that area in bg coordinates. dimOpacity is the dim overlay's opacity for
    // that layer. null when there is no grid or no geometry yet.
    function zoneBackdrop(item, bg, dimOpacity) {
        const g = root.artGrid;
        // Text items: only the glyph box (left-aligned; vertically centred when the item says so)
        const w = item?.contentWidth !== undefined ? Math.min(item.width, item.contentWidth) : item?.width;
        const h = item?.contentHeight !== undefined ? Math.min(item.height, item.contentHeight) : item?.height;
        if (!g || !item || !bg || bg.width <= 0 || bg.height <= 0 || !(w > 0) || !(h > 0))
            return null;

        const top = item.verticalAlignment === Text.AlignVCenter ? (item.height - h) / 2 : 0;
        const r = item.mapToItem(bg, 0, top, w, h);
        const scale = Math.max(bg.width / g.w, bg.height / g.h); // PreserveAspectCrop
        const ox = (bg.width - g.w * scale) / 2;
        const oy = (bg.height - g.h * scale) / 2;
        const island = Qt.color(Appearance.m3colors.m3background);
        const dimStops = [[0, 0], [0.5, 0.05], [0.8, 0.25], [1, 0.45]];
        const pausedDim = root.playing ? 0 : 0.15;
        const columns = Math.max(4, Math.ceil(r.width / 6));
        const rows = 4;

        const samples = [];
        for (let i = 0; i < columns; i++) {
            for (let j = 0; j < rows; j++) {
                const x = r.x + (i + 0.5) / columns * r.width;
                const y = r.y + (j + 0.5) / rows * r.height;
                const gx = Math.floor((x - ox) / scale / g.w * root.artGridSize);
                const gy = Math.floor((y - oy) / scale / g.h * root.artGridSize);
                const px = g.px[Math.max(0, Math.min(root.artGridSize - 1, gy)) * root.artGridSize
                    + Math.max(0, Math.min(root.artGridSize - 1, gx))];
                if (!px)
                    continue;

                const t = Math.max(0, Math.min(1, y / bg.height));
                let d = 0;
                for (let k = 1; k < dimStops.length; k++) {
                    if (t > dimStops[k][0])
                        continue;
                    const [t0, d0] = dimStops[k - 1];
                    const [t1, d1] = dimStops[k];
                    d = d0 + (d1 - d0) * (t - t0) / (t1 - t0);
                    break;
                }
                const fade = Math.min(1, d * dimOpacity + pausedDim * dimOpacity);
                const fadeTo = Appearance.m3colors.darkmode ? 0 : 1;
                const blend = (a, b) => (0.85 * a + 0.15 * b) * (1 - fade) + fadeTo * fade;
                samples.push(ColorUtils.relativeLuminance(Qt.rgba(blend(px[0], island.r), blend(px[1], island.g),
                    blend(px[2], island.b), 1)));
            }
        }
        return samples.length > 0 ? { "rect": r, "samples": samples } : null;
    }

    // How strong a patch behind `samples` must be for `fg` to reach `minContrast` (WCAG) against
    // the brightest tenth of it. Dark mode gets a black patch; light mode (dark text) a white one.
    function patchFor(samples, fg, minContrast) {
        const fgL = ColorUtils.relativeLuminance(fg);
        const sorted = samples.slice().sort((a, b) => a - b);
        if (!Appearance.m3colors.darkmode) {
            // Lightening: L' ≈ L + (1 - L)·a over the darkest tenth
            const L = sorted[Math.floor(sorted.length * 0.1)];
            const needed = (fgL + 0.05) * minContrast - 0.05;
            return { "white": true, "alpha": L >= needed ? 0 : Math.min(0.7, (needed - L) / (1 - L)) };
        }
        // Darkening by a in sRGB scales linear luminance by about (1 - a)^2.2
        const L = sorted[Math.min(sorted.length - 1, Math.floor(sorted.length * 0.9))];
        const allowed = (fgL + 0.05) / minContrast - 0.05;
        return { "white": false, "alpha": L <= allowed ? 0 : Math.min(0.7, 1 - Math.pow(allowed / L, 1 / 2.2)) };
    }

    function refreshArtPatches() {
        // Mid-animation the layouts are still scaled; the animations' onFinished calls back in
        if (expandAnim.running || contractAnim.running)
            return;

        const expandedDim = root.playing ? 0.55 : 0.75;
        const contractedDim = root.playing ? 0.7 : 0.85;
        const text = Appearance.colors.colOnSurface;
        const subtext = Appearance.colors.colOnSurfaceVariant;
        // [item, art layer, dim, foreground, minimum contrast]; 4.5 for text and the thin seek wave,
        // 3 for icons
        const zones = {
            "appIcon": [appIconShape, expandedBg, expandedDim, text, 3],
            // Synced lyrics scroll through the whole area; a plain title only covers its glyphs
            "title": [LyricsService.hasSyncedLines ? expandedTitleArea : expandedTitleText, expandedBg, expandedDim, text, 4.5],
            "artist": [expandedArtistText, expandedBg, expandedDim, subtext, 4.5],
            "prev": [prevBtn, expandedBg, expandedDim, text, 3],
            "next": [nextBtn, expandedBg, expandedDim, text, 3],
            "progress": [progressArea, expandedBg, expandedDim, root.seekColor, 4.5],
            "contractedTitle": [contractedTitleText, contractedLayout, contractedDim, text, 4.5],
            "contractedArtist": [contractedArtistText, contractedLayout, contractedDim, subtext, 4.5],
            "contractedViz": [contractedViz, contractedLayout, contractedDim, root.lightVizColor, 3]
        };

        const result = {};
        for (const zone in zones) {
            const [item, bg, dim, fg, minContrast] = zones[zone];
            const backdrop = root.zoneBackdrop(item, bg, dim);
            // Keep the previous patch while a layer has no geometry (collapsed, hidden)
            if (!backdrop) {
                if (root.artGrid && root.artPatches[zone] !== undefined)
                    result[zone] = root.artPatches[zone];
                continue;
            }
            const patch = root.patchFor(backdrop.samples, fg, minContrast);
            const r = backdrop.rect;
            result[zone] = {
                "x": Math.round(r.x), "y": Math.round(r.y), "w": Math.round(r.width), "h": Math.round(r.height),
                "white": patch.white, "alpha": Math.round(patch.alpha * 100) / 100
            };
        }
        if (JSON.stringify(result) !== JSON.stringify(root.artPatches))
            root.artPatches = result;
    }

    function scheduleArtPatches() {
        Qt.callLater(root.refreshArtPatches);
    }

    onArtGridChanged: root.scheduleArtPatches()
    // Theme switch: the fade colour and the patch direction flip
    onArtDimColorChanged: root.scheduleArtPatches()
    // Same cover, new title (next track of an album): the glyph boxes moved
    onDisplayTitleChanged: root.scheduleArtPatches()
    onDisplayArtistChanged: root.scheduleArtPatches()
    onWidthChanged: root.scheduleArtPatches()
    onHeightChanged: root.scheduleArtPatches()

    onLocalArtFilePathChanged: {
        root.artGrid = null;
        artSampler.running = false;
        if (root.localArtFilePath === "")
            return;
        // MPRIS art URLs are percent-encoded; magick needs the real file name
        let path = root.localArtFilePath;
        try {
            path = decodeURIComponent(path);
        } catch (e) {}
        artSampler.samplePath = path;
        artSampler.forPath = root.localArtFilePath;
        Qt.callLater(() => artSampler.running = true);
    }

    Process {
        id: artSampler
        property string samplePath: ""
        property string forPath: ""
        command: ["bash", "-c", `magick identify -format '%w %h\\n' "$1[0]" && magick "$1[0]" -alpha off -resize ${root.artGridSize}x${root.artGridSize}! -depth 8 txt:-`,
            "_", samplePath]
        stdout: StdioCollector {
            onStreamFinished: {
                if (artSampler.forPath !== root.localArtFilePath)
                    return;
                const lines = text.split("\n");
                const dims = (lines[0] ?? "").trim().split(" ").map(Number);
                if (dims.length !== 2 || !(dims[0] > 0) || !(dims[1] > 0))
                    return;

                const px = new Array(root.artGridSize * root.artGridSize);
                for (let i = 1; i < lines.length; i++) {
                    const m = lines[i].match(/^(\d+),(\d+):.*#([0-9A-Fa-f]{6})/);
                    if (!m)
                        continue;
                    const hex = parseInt(m[3], 16);
                    px[Number(m[2]) * root.artGridSize + Number(m[1])] = [(hex >> 16 & 255) / 255,
                        (hex >> 8 & 255) / 255, (hex & 255) / 255];
                }
                root.artGrid = { "w": dims[0], "h": dims[1], "px": px };
            }
        }
    }

    function effectiveSource(url) {
        if (!url || url === "")
            return "";
        return url + "?v=" + artCacheBuster;
    }

    function snapToArt(newUrl) {
        previousArtUrl = "";
        currentArtUrl = newUrl;
        pendingArtUrl = "";
        awaitingImageLoad = false;
        artTransitioning = false;
        preloadFallbackTimer.stop();
        artOutgoingBlur = 0;
        artOutgoingScale = 1.0;
        artIncomingBlur = 0;
        artIncomingScale = 1.0;
    }

    function requestArtChange(newUrl) {
        if (newUrl === currentArtUrl && artCacheBuster > 0 && !artTransitioning && !awaitingImageLoad && currentArtUrl !== "") {
            pendingArtUrl = newUrl;
            artCacheBuster++;
            awaitingImageLoad = true;
            preloadFallbackTimer.restart();
            return;
        }

        if (newUrl === "" || currentArtUrl === "") {
            snapToArt(newUrl);
            return;
        }

        if (artTransitioning || awaitingImageLoad) {
            if (pendingArtUrl !== newUrl)
                pendingArtUrl = newUrl;
            return;
        }

        pendingArtUrl = newUrl;
        artCacheBuster++;
        awaitingImageLoad = true;
        preloadFallbackTimer.restart();
    }

    function startOutgoingPhase() {
        if (pendingArtUrl === "")
            return;
        awaitingImageLoad = false;
        preloadFallbackTimer.stop();

        previousArtUrl = currentArtUrl;
        currentArtUrl = pendingArtUrl;
        pendingArtUrl = "";

        artOutgoingBlur = 0;
        artOutgoingScale = 1.0;
        artOutgoingAnimation.restart();
    }

    Process {
        id: artDownloader
        property string targetFile: root.artUrl
        property string artFilePath: root.artFilePath
        property string artTempPath: root.artFilePath + ".tmp"
        command: ["bash", "-c", `[ -f ${artFilePath} ] || (curl -4 -sSL '${targetFile}' -o '${artTempPath}' && mv '${artTempPath}' '${artFilePath}')`]
        onExited: {
            root.artDownloaded = true;
        }
    }

    Behavior on artVignetteBlur {
        NumberAnimation {
            duration: 500
            easing.type: Easing.OutCubic
        }
    }

    onPlayingChanged: {
        artVignetteBlur = root.playing ? 50 : 90;
        root.scheduleArtPatches();
    }

    function imageLoadFailed() {
        if (!awaitingImageLoad)
            return;
        awaitingImageLoad = false;
        preloadFallbackTimer.stop();
        snapToArt(pendingArtUrl);
    }

    readonly property string displaySongText: {
        if (LyricsService.hasSyncedLines && LyricsService.statusText !== "") {
            return LyricsService.statusText;
        }
        return root.title;
    }

    onDisplaySongTextChanged: {
        root.scheduleArtPatches();
        if (root.isExpanded) {
            lyricTransitionAnimation.stop();
            lyricTransitionAnimation.start();
        } else {
            root.activeLyricText = root.displaySongText;
        }
    }

    // Cached widget widths to compute a meaningful expand/contract ratio.
    // expandedBg.width and root.width are both equal when expanded (no useful ratio),
    // so we track the actual expanded and contracted widths separately across
    // hover cycles to derive the real size ratio for the contract animation.
    property real _lastExpandedWidth: 0
    property real _lastContractedWidth: 0
    readonly property real _effectiveExpandContractRatio: {
        if (root._lastExpandedWidth > 0 && root._lastContractedWidth > 0) {
            return Math.max(1.0, root._lastExpandedWidth / root._lastContractedWidth);
        }
        return root.expandContractRatio;
    }

    // Waits for the container's Behavior on width (500ms) to settle, then samples
    // root.width and stores it in the appropriate bucket for the ratio computation.
    Timer {
        id: widthCaptureTimer
        interval: 600
        repeat: false
        onTriggered: {
            if (root.width <= 0)
                return;
            if (root.isExpanded)
                root._lastExpandedWidth = root.width;
            else
                root._lastContractedWidth = root.width;
            if (root._lastExpandedWidth > 0 && root._lastContractedWidth > 0) {
                root.expandContractRatio = Math.max(1.0, root._lastExpandedWidth / root._lastContractedWidth);
            }
        }
    }

    onIsExpandedChanged: {
        root.scheduleArtPatches();
        if (root.isExpanded) {
            LyricsService.initiliazeLyrics();
            root.activeLyricText = root.displaySongText;
            contractAnim.stop();
            expandAnim.restart();
        } else {
            expandAnim.stop();
            contractAnim.restart();
        }
        // Sample the settled width after the container's 500ms width Behavior
        widthCaptureTimer.restart();
    }

    ParallelAnimation {
        id: expandAnim
        // Zones are measured on settled geometry; mid-animation the layout is still scaled
        onFinished: root.scheduleArtPatches()
        NumberAnimation { target: contractedLayout; property: "opacity"; to: 0.0; duration: 500; easing.type: Easing.OutBack; easing.overshoot: 0.5 }
        NumberAnimation { target: contractedLayout; property: "scale"; to: 0.95; duration: 500; easing.type: Easing.OutBack; easing.overshoot: 0.5 }
        NumberAnimation { target: expandedBg; property: "opacity"; to: 1.0; duration: 500; easing.type: Easing.OutBack; easing.overshoot: 0.5 }
        NumberAnimation { target: expandedBg; property: "scale"; to: 1.0; duration: 500; easing.type: Easing.OutBack; easing.overshoot: 0.5 }
        NumberAnimation { target: expandedLayout; property: "opacity"; to: 1.0; duration: 500; easing.type: Easing.OutBack; easing.overshoot: 0.5 }
        NumberAnimation { target: expandedLayout; property: "scale"; to: 1.0; duration: 500; easing.type: Easing.OutBack; easing.overshoot: 0.5 }
        NumberAnimation { target: root; property: "_contractScale"; to: 1.0; duration: 500; easing.type: Easing.OutBack; easing.overshoot: 0.5 }
    }

    SequentialAnimation {
        id: contractAnim
        onFinished: root.scheduleArtPatches()
        // Initial state: contractedLayout invisible, whole widget scaled up to expanded size.
        // Both layouts stay loaded during the animation; the whole-widget scale on root
        // gives a visible "scale together" effect independent of child Behavior fallbacks.
        PropertyAction { target: contractedLayout; property: "scale"; value: root._effectiveExpandContractRatio }
        PropertyAction { target: contractedLayout; property: "opacity"; value: 0.0 }
        PropertyAction { target: expandedBg; property: "scale"; value: 1.0 }
        PropertyAction { target: expandedBg; property: "opacity"; value: 1.0 }
        PropertyAction { target: expandedLayout; property: "opacity"; value: 1.0 }
        PropertyAction { target: expandedLayout; property: "scale"; value: 1.0 }
        PropertyAction { target: root; property: "_contractScale"; value: root._effectiveExpandContractRatio }
        // 500ms cross-fade + whole-widget scale matching the dynamic island's container animation.
        // expanded scales down + fades out, contracted scales down + fades in, root shrinks.
        ParallelAnimation {
            NumberAnimation { target: expandedBg; property: "opacity"; to: 0.0; duration: 500; easing.type: Easing.OutBack; easing.overshoot: 0.5 }
            NumberAnimation { target: expandedBg; property: "scale"; to: 1.0 / root._effectiveExpandContractRatio; duration: 500; easing.type: Easing.OutBack; easing.overshoot: 0.5 }
            NumberAnimation { target: expandedLayout; property: "opacity"; to: 0.0; duration: 500; easing.type: Easing.OutBack; easing.overshoot: 0.5 }
            NumberAnimation { target: expandedLayout; property: "scale"; to: 0.95; duration: 500; easing.type: Easing.OutBack; easing.overshoot: 0.5 }
            NumberAnimation { target: contractedLayout; property: "opacity"; to: 1.0; duration: 500; easing.type: Easing.OutBack; easing.overshoot: 0.5 }
            NumberAnimation { target: contractedLayout; property: "scale"; to: 1.0; duration: 500; easing.type: Easing.OutBack; easing.overshoot: 0.5 }
            NumberAnimation { target: root; property: "_contractScale"; to: 1.0; duration: 500; easing.type: Easing.OutBack; easing.overshoot: 0.5 }
        }
    }

    SequentialAnimation {
        id: lyricTransitionAnimation
        NumberAnimation {
            target: root
            property: "lyricOpacity"
            to: 0.0
            duration: 120
            easing.type: Easing.OutQuad
        }
        PropertyAction {
            target: root
            property: "activeLyricText"
            value: root.displaySongText
        }
        NumberAnimation {
            target: root
            property: "lyricYOffset"
            from: 15
            to: 0.0
            duration: 180
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: root
            property: "lyricOpacity"
            to: 1.0
            duration: 180
            easing.type: Easing.OutCubic
        }
    }

    SequentialAnimation {
        id: artOutgoingAnimation
        onFinished: {
            root.previousArtUrl = "";
            root.artIncomingBlur = 30;
            root.artIncomingScale = 0.95;
            root.artTransitioning = true;
            artIncomingAnimation.restart();
        }
        ParallelAnimation {
            NumberAnimation {
                target: root
                property: "artOutgoingBlur"
                to: 30
                duration: 300
                easing.type: Easing.OutQuad
            }
            NumberAnimation {
                target: root
                property: "artOutgoingScale"
                to: 1.05
                duration: 300
                easing.type: Easing.OutQuad
            }
        }
    }

    SequentialAnimation {
        id: artIncomingAnimation
        onFinished: {
            root.artTransitioning = false;
            if (root.pendingArtUrl !== "" && root.pendingArtUrl !== root.currentArtUrl) {
                const next = root.pendingArtUrl;
                root.pendingArtUrl = "";
                root.requestArtChange(next);
            }
        }
        ParallelAnimation {
            NumberAnimation {
                target: root
                property: "artIncomingBlur"
                to: 0
                duration: 400
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: root
                property: "artIncomingScale"
                to: 1.0
                duration: 400
                easing.type: Easing.OutExpo
            }
        }
    }

    Image {
        id: artPreload
        source: root.awaitingImageLoad ? root.effectiveSource(root.pendingArtUrl) : ""
        visible: false
        asynchronous: true
        width: 16
        height: 16
        smooth: false
        mipmap: false
        onStatusChanged: {
            if (status === Image.Ready) {
                if (root.awaitingImageLoad)
                    root.startOutgoingPhase();
            } else if (status === Image.Error) {
                if (root.awaitingImageLoad)
                    root.imageLoadFailed();
            }
        }
    }

    Timer {
        id: preloadFallbackTimer
        interval: 200
        repeat: false
        onTriggered: {
            if (root.awaitingImageLoad)
                root.startOutgoingPhase();
        }
    }

    onArtUrlChanged: {
        var shouldDownload = false;
        
        if (!root.artUrl || root.artUrl === "") {
            root.artDownloaded = false;
        } else if (root.isLocalArt) {
            root.artDownloaded = true;
        } else {
            shouldDownload = true;
            artDownloader.targetFile = root.artUrl;
            artDownloader.artFilePath = root.artFilePath;
            artDownloader.artTempPath = root.artFilePath + ".tmp";
            root.artDownloaded = false;
        }
        
        if (shouldDownload) {
            artDownloader.running = true;
        }

        if (!root._initialized)
            return;
        if (root.artUrl === root.currentArtUrl && root.currentArtUrl !== "")
            return;
        root.requestArtChange(root.artUrl);
    }

    onActiveTrackRefChanged: {
        if (!root._initialized)
            return;
        if (root.activeTrackRef === null || root.activeTrackRef === undefined)
            return;
        root.requestArtChange(root.artUrl);
    }

    Connections {
        target: MprisController
        function onTrackChanged(reverse) {
            root.displayTitle = root.title;
            root.displayArtist = root.artist;
            root.activeLyricText = root.displaySongText;
            if (!root._initialized)
                return;
            Qt.callLater(function() {
                root.requestArtChange(root.artUrl);
            });
        }
    }

    // Trigger animation on title OR identity (player source) change
    onTitleChanged: {
        if (displayTitle === "") {
            displayTitle = root.title;
            displayArtist = root.artist;
        } else {
            songSwitchAnimation.stop();
            songSwitchAnimation.start();
        }
    }

    onIdentityChanged: {
        if (displayTitle !== "") {
            songSwitchAnimation.stop();
            songSwitchAnimation.start();
        }
    }

    SequentialAnimation {
        id: songSwitchAnimation
        ParallelAnimation {
            NumberAnimation {
                target: root
                property: "titleOpacity"
                to: 0.0
                duration: 150
                easing.type: Easing.OutQuad
            }
            NumberAnimation {
                target: root
                property: "titleYOffset"
                to: -24
                duration: 150
                easing.type: Easing.OutQuad
            }
        }
        PropertyAction {
            target: root
            property: "displayTitle"
            value: root.title
        }
        PropertyAction {
            target: root
            property: "displayArtist"
            value: root.artist
        }
        PropertyAction {
            target: root
            property: "titleYOffset"
            value: 24
        }
        ParallelAnimation {
            NumberAnimation {
                target: root
                property: "titleOpacity"
                to: 1.0
                duration: 220
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: root
                property: "titleYOffset"
                to: 0.0
                duration: 220
                easing.type: Easing.OutCubic
            }
        }
    }

    Timer {
        running: root.isExpanded && root.playing
        interval: 1000
        repeat: true
        onTriggered: {
            if (root.player) {
                root.player.positionChanged();
            }
        }
    }

    function formatTime(seconds) {
        if (isNaN(seconds) || seconds < 0)
            return "0:00";
        let mins = Math.floor(seconds / 60);
        let secs = Math.floor(seconds % 60);
        return mins + ":" + (secs < 10 ? "0" : "") + secs;
    }

    // Real Cava Visualizer integration
    property var visualizerPoints: CavaService.visualizerPoints

    readonly property real bar0Val: visualizerPoints.length > 5 ? visualizerPoints[3] / 1000.0 : 0
    readonly property real bar1Val: visualizerPoints.length > 11 ? visualizerPoints[9] / 1000.0 : 0
    readonly property real bar2Val: visualizerPoints.length > 18 ? visualizerPoints[16] / 1000.0 : 0
    readonly property real bar3Val: visualizerPoints.length > 28 ? visualizerPoints[25] / 1000.0 : 0

    function getBarHeight(index) {
        let minH = barWidth;
        if (!root.playing)
            return minH; // Reset to perfect circle when paused
        let val = 0;
        if (index === 0)
            val = bar0Val;
        else if (index === 1)
            val = bar1Val;
        else if (index === 2)
            val = bar2Val;
        else if (index === 3)
            val = bar3Val;

        let norm = Math.min(1.0, Math.max(0.0, val * 2.0));
        let maxH = elementHeight - 10;
        return minH + norm * (maxH - minH);
    }

    function getBarAmplitude(index) {
        if (!root.playing)
            return 0.0;
        let val = 0;
        if (index === 0)
            val = bar0Val;
        else if (index === 1)
            val = bar1Val;
        else if (index === 2)
            val = bar2Val;
        else if (index === 3)
            val = bar3Val;
        return Math.min(1.0, Math.max(0.0, val * 2.0));
    }

    Component.onCompleted: {
        LyricsService.initiliazeLyrics();
        root.displayTitle = root.title;
        root.displayArtist = root.artist;
        root.activeLyricText = root.displaySongText;
        if (root.artUrl !== "" && root.currentArtUrl === "")
            root.snapToArt(root.artUrl);
        root._initialized = true;
    }

    // ==========================================
    // 1. CONTRACTED MODE (album-art full background)
    // ==========================================
    Item {
        id: contractedLayout
        anchors.fill: parent
        visible: true
        opacity: 1.0
        scale: 1.0

        // No Behavior on opacity/scale: contractAnim/expandAnim are the sole drivers.
        // Previous Behaviors had identical 500ms OutBack overshoot 0.5 easing that
        // conflicted with contractAnim, causing the expanded art to "snap" out and
        // the contracted scale to bounce back to its binding value (1.0).

        // OpacityMask to clip album art to rounded corners
        Rectangle {
            id: contractedMaskRect
            anchors.fill: parent
            radius: Math.max(0, root.notchBottomRadius - 4)
            visible: false
        }

        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: contractedMaskRect
        }

        Item {
            id: contractedVignetteMask
            anchors.fill: parent
            visible: true

            Rectangle {
                id: contractedHMask
                anchors.fill: parent
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.08; color: "transparent" }
                    GradientStop { position: 0.2; color: Qt.rgba(1, 1, 1, 0.3) }
                    GradientStop { position: 0.35; color: Qt.rgba(1, 1, 1, 0.7) }
                    GradientStop { position: 0.45; color: "white" }
                    GradientStop { position: 0.55; color: "white" }
                    GradientStop { position: 0.65; color: Qt.rgba(1, 1, 1, 0.7) }
                    GradientStop { position: 0.8; color: Qt.rgba(1, 1, 1, 0.3) }
                    GradientStop { position: 0.92; color: "transparent" }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }

            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    orientation: Gradient.Vertical
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.15; color: Qt.rgba(1, 1, 1, 0.3) }
                    GradientStop { position: 0.35; color: Qt.rgba(1, 1, 1, 0.7) }
                    GradientStop { position: 0.5; color: "white" }
                    GradientStop { position: 0.65; color: Qt.rgba(1, 1, 1, 0.7) }
                    GradientStop { position: 0.85; color: Qt.rgba(1, 1, 1, 0.3) }
                    GradientStop { position: 1.0; color: "transparent" }
                }
                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: contractedHMask
                }
            }
        }

        Item {
            anchors.fill: parent

            Item {
                anchors.fill: parent
                visible: root.previousArtUrl !== ""

                Image {
                    anchors.fill: parent
                    source: root.previousArtUrl !== "" ? root.effectiveSource(root.previousArtUrl) : ""
                    fillMode: Image.PreserveAspectCrop
                    smooth: true
                    asynchronous: true
                    layer.enabled: root.artVignetteBlur > 0
                    layer.effect: MultiEffect {
                        blurEnabled: root.artVignetteBlur > 0
                        blurMax: 128
                        blur: root.artVignetteBlur / 128
                    }
                }

                Item {
                    anchors.fill: parent
                    layer.enabled: true
                    layer.effect: OpacityMask {
                        maskSource: contractedVignetteMask
                    }

                    Image {
                        id: contractedArtOutgoing
                        anchors.centerIn: parent
                        width: parent.width * root.artOutgoingScale
                        height: parent.height * root.artOutgoingScale
                        source: root.previousArtUrl !== "" ? root.effectiveSource(root.previousArtUrl) : ""
                        fillMode: Image.PreserveAspectCrop
                        smooth: true
                        asynchronous: true
                        layer.enabled: root.artOutgoingBlur > 0
                        layer.effect: MultiEffect {
                            blurEnabled: root.artOutgoingBlur > 0
                            blurMax: 128
                            blur: root.artOutgoingBlur / 128
                        }
                    }
                }
            }

            Item {
                anchors.fill: parent
                visible: root.currentArtUrl !== ""

                Image {
                    anchors.fill: parent
                    source: root.currentArtUrl !== "" ? root.effectiveSource(root.currentArtUrl) : ""
                    fillMode: Image.PreserveAspectCrop
                    smooth: true
                    asynchronous: true
                    layer.enabled: root.artVignetteBlur > 0
                    layer.effect: MultiEffect {
                        blurEnabled: root.artVignetteBlur > 0
                        blurMax: 128
                        blur: root.artVignetteBlur / 128
                    }
                }

                Item {
                    anchors.fill: parent
                    layer.enabled: true
                    layer.effect: OpacityMask {
                        maskSource: contractedVignetteMask
                    }

                    Image {
                        id: contractedArtIncoming
                        anchors.centerIn: parent
                        width: parent.width * root.artIncomingScale
                        height: parent.height * root.artIncomingScale
                        source: root.currentArtUrl !== "" ? root.effectiveSource(root.currentArtUrl) : ""
                        fillMode: Image.PreserveAspectCrop
                        smooth: true
                        asynchronous: true
                        layer.enabled: root.artIncomingBlur > 0
                        layer.effect: MultiEffect {
                            blurEnabled: root.artIncomingBlur > 0
                            blurMax: 128
                            blur: root.artIncomingBlur / 128
                        }
                    }
                }
            }
        }

        // Fallback gradient when no art
        Rectangle {
            anchors.fill: parent
            visible: root.currentArtUrl === ""
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop {
                    position: 0.0
                    color: Appearance.colors.colSurfaceContainerHighest
                }
                GradientStop {
                    position: 1.0
                    color: Appearance.colors.colSurfaceContainer
                }
            }
        }

        // Music note icon centered when no art
        MaterialSymbol {
            anchors.centerIn: parent
            visible: root.currentArtUrl === ""
            text: "music_note"
            iconSize: Appearance.font.pixelSize.large
            color: Appearance.colors.colOnSurface
            opacity: 0.5
        }

        // ── Radial gradient dimming overlay ──────────────────────────────────
        Item {
            anchors.fill: parent
            opacity: root.playing ? 0.7 : 0.85

            Behavior on opacity {
                NumberAnimation {
                    duration: 400
                    easing.type: Easing.OutQuad
                }
            }

            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.0; color: ColorUtils.applyAlpha(root.artDimColor, 0.0) }
                    GradientStop { position: 0.5; color: ColorUtils.applyAlpha(root.artDimColor, 0.05) }
                    GradientStop { position: 0.8; color: ColorUtils.applyAlpha(root.artDimColor, 0.25) }
                    GradientStop { position: 1.0; color: ColorUtils.applyAlpha(root.artDimColor, 0.45) }
                }
            }

            // Extra dim layer when paused
            Rectangle {
                anchors.fill: parent
                color: ColorUtils.applyAlpha(root.artDimColor, 0.3)
                opacity: root.playing ? 0.0 : 0.5

                Behavior on opacity {
                    NumberAnimation {
                        duration: 500
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }

        // Readability patches, above the fade: the sampler judges the art after it
        Repeater {
            model: ["contractedTitle", "contractedArtist", "contractedViz"]
            delegate: ArtPatch {
                required property string modelData
                zone: modelData
            }
        }

    }

    // ── Contracted content row (text + visualizer) ───────────────────────────
    // Kept OUTSIDE contractedLayout's masked layer so the 30 Hz visualizer no
    // longer forces the whole album-art FBO + OpacityMask to re-render on every
    // Cava sample (the steady-state cost the 2026-09-10 pass traced to the media
    // visualizer). Mirrors contractedLayout's opacity/scale/visibility so it
    // still fades and scales with the expand/contract animation; at rest
    // (opacity 1, scale 1) the split renders identically to the old nesting.
    Item {
        anchors.fill: parent
        visible: contractedLayout.visible
        opacity: contractedLayout.opacity
        scale: contractedLayout.scale

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 8

            // Left: metadata always visible
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 1

                StyledText {
                    id: contractedTitleText

                    Layout.fillWidth: true
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.Black
                    font.styleName: "Rounded"
                    font.hintingPreference: Font.PreferNoHinting
                    color: Appearance.colors.colOnSurface
                    text: root.displayTitle
                    maximumLineCount: 1
                    elide: Text.ElideRight
                    opacity: root.titleOpacity
                    transform: Translate {
                        y: root.titleYOffset
                    }
                    verticalAlignment: Text.AlignVCenter
                }

                StyledText {
                    id: contractedArtistText

                    Layout.fillWidth: true
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colOnSurfaceVariant
                    text: root.displayArtist
                    maximumLineCount: 1
                    elide: Text.ElideRight
                    opacity: root.titleOpacity
                    transform: Translate {
                        y: root.titleYOffset
                    }
                }
            }

            // Right: visualizer bars
            Item {
                id: contractedViz
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: root.barWidth * 4 + 2 * 3
                implicitHeight: root.elementHeight

                Row {
                    anchors.centerIn: parent
                    height: parent.height
                    spacing: 2

                    Repeater {
                        model: 4
                        ModernVisualizerBar {
                            required property int index
                            anchors.verticalCenter: parent.verticalCenter
                            barWidth: root.barWidth
                            maxHeight: root.elementHeight - 10
                            minHeight: root.barWidth
                            amplitude: root.getBarAmplitude(index)
                            bgAmplitude: root.getBarAmplitude((index + 1) % 4)
                            color: root.lightVizColor
                            fgColor: root.useDynamicColors ? root.blendedColors.colTertiary : Appearance.colors.colTertiary
                            glowColor: root.useDynamicColors ? root.blendedColors.colOnPrimary : "#FFFFFF"
                            playing: root.playing
                        }
                    }
                }
            }
        }
    }

    // ==========================================
    // 2. EXPANDED MODE (Premium Spotify-like layout)
    // ==========================================

    // Background Album Art Overlay
    Item {
        id: expandedBg

        readonly property bool isMultiWidget: {
            var p = root.parent;
            while (p && !p.hasOwnProperty("activeWidgetsList")) {
                p = p.parent;
            }
            return (p && p.activeWidgetsList.length > 1);
        }

        x: -(root.widgetBg.width - root.width) / 2
        y: -(root.widgetBg.height - root.height) / 2
        width: root.widgetBg.width
        height: root.widgetBg.height
        visible: true
        opacity: 0.0
        scale: 0.95

        // No Behavior on opacity/scale: contractAnim/expandAnim are the sole drivers.
        // See note on contractedLayout above for rationale.

        // Mask shape defining the rounded sections
        Rectangle {
            id: maskRect
            anchors.fill: parent
            radius: Math.max(0, root.notchBottomRadius - 4)
            visible: false
        }

        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: maskRect
        }

        Item {
            id: expandedVignetteMask
            anchors.fill: parent
            visible: true

            Rectangle {
                id: expandedHMask
                anchors.fill: parent
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.08; color: "transparent" }
                    GradientStop { position: 0.2; color: Qt.rgba(1, 1, 1, 0.3) }
                    GradientStop { position: 0.35; color: Qt.rgba(1, 1, 1, 0.7) }
                    GradientStop { position: 0.45; color: "white" }
                    GradientStop { position: 0.55; color: "white" }
                    GradientStop { position: 0.65; color: Qt.rgba(1, 1, 1, 0.7) }
                    GradientStop { position: 0.8; color: Qt.rgba(1, 1, 1, 0.3) }
                    GradientStop { position: 0.92; color: "transparent" }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }

            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    orientation: Gradient.Vertical
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.15; color: Qt.rgba(1, 1, 1, 0.3) }
                    GradientStop { position: 0.35; color: Qt.rgba(1, 1, 1, 0.7) }
                    GradientStop { position: 0.5; color: "white" }
                    GradientStop { position: 0.65; color: Qt.rgba(1, 1, 1, 0.7) }
                    GradientStop { position: 0.85; color: Qt.rgba(1, 1, 1, 0.3) }
                    GradientStop { position: 1.0; color: "transparent" }
                }
                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: expandedHMask
                }
            }
        }

        Item {
            anchors.fill: parent

            Item {
                anchors.fill: parent
                visible: root.previousArtUrl !== ""

                Image {
                    anchors.fill: parent
                    source: root.previousArtUrl !== "" ? root.effectiveSource(root.previousArtUrl) : ""
                    fillMode: Image.PreserveAspectCrop
                    opacity: 0.85
                    smooth: true
                    asynchronous: true
                    layer.enabled: root.artVignetteBlur > 0
                    layer.effect: MultiEffect {
                        blurEnabled: root.artVignetteBlur > 0
                        blurMax: 128
                        blur: root.artVignetteBlur / 128
                    }
                }

                Item {
                    anchors.fill: parent
                    layer.enabled: true
                    layer.effect: OpacityMask {
                        maskSource: expandedVignetteMask
                    }

                    Image {
                        id: expandedArtOutgoing
                        anchors.centerIn: parent
                        width: parent.width * root.artOutgoingScale
                        height: parent.height * root.artOutgoingScale
                        source: root.previousArtUrl !== "" ? root.effectiveSource(root.previousArtUrl) : ""
                        fillMode: Image.PreserveAspectCrop
                        opacity: 0.85
                        smooth: true
                        asynchronous: true
                        layer.enabled: root.artOutgoingBlur > 0
                        layer.effect: MultiEffect {
                            blurEnabled: root.artOutgoingBlur > 0
                            blurMax: 128
                            blur: root.artOutgoingBlur / 128
                        }
                    }
                }
            }

            Item {
                anchors.fill: parent
                visible: root.currentArtUrl !== ""

                Image {
                    anchors.fill: parent
                    source: root.currentArtUrl !== "" ? root.effectiveSource(root.currentArtUrl) : ""
                    fillMode: Image.PreserveAspectCrop
                    opacity: 0.85
                    smooth: true
                    asynchronous: true
                    layer.enabled: root.artVignetteBlur > 0
                    layer.effect: MultiEffect {
                        blurEnabled: root.artVignetteBlur > 0
                        blurMax: 128
                        blur: root.artVignetteBlur / 128
                    }
                }

                Item {
                    anchors.fill: parent
                    layer.enabled: true
                    layer.effect: OpacityMask {
                        maskSource: expandedVignetteMask
                    }

                    Image {
                        id: expandedArtIncoming
                        anchors.centerIn: parent
                        width: parent.width * root.artIncomingScale
                        height: parent.height * root.artIncomingScale
                        source: root.currentArtUrl !== "" ? root.effectiveSource(root.currentArtUrl) : ""
                        fillMode: Image.PreserveAspectCrop
                        opacity: 0.85
                        smooth: true
                        asynchronous: true
                        layer.enabled: root.artIncomingBlur > 0
                        layer.effect: MultiEffect {
                            blurEnabled: root.artIncomingBlur > 0
                            blurMax: 128
                            blur: root.artIncomingBlur / 128
                        }
                    }
                }
            }
        }

        // Radial gradient dimming overlay
        Item {
            anchors.fill: parent
            opacity: root.playing ? 0.55 : 0.75

            Behavior on opacity {
                NumberAnimation {
                    duration: 400
                    easing.type: Easing.OutCubic
                }
            }

            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.0; color: ColorUtils.applyAlpha(root.artDimColor, 0.0) }
                    GradientStop { position: 0.5; color: ColorUtils.applyAlpha(root.artDimColor, 0.05) }
                    GradientStop { position: 0.8; color: ColorUtils.applyAlpha(root.artDimColor, 0.25) }
                    GradientStop { position: 1.0; color: ColorUtils.applyAlpha(root.artDimColor, 0.45) }
                }
            }

            // Extra dim layer when paused
            Rectangle {
                anchors.fill: parent
                color: ColorUtils.applyAlpha(root.artDimColor, 0.3)
                opacity: root.playing ? 0.0 : 0.5

                Behavior on opacity {
                    NumberAnimation {
                        duration: 500
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }

        // Readability patches, above the fade: the sampler judges the art after it
        Repeater {
            model: ["appIcon", "title", "artist", "prev", "next", "progress"]
            delegate: ArtPatch {
                required property string modelData
                zone: modelData
            }
        }
    }

    ColumnLayout {
        id: expandedLayout
        anchors.fill: parent
        anchors.leftMargin: {
            var p = root.parent;
            while (p && !p.hasOwnProperty("activeWidgetsList")) {
                p = p.parent;
            }
            return (p && p.activeWidgetsList.length > 1) ? 8 : 12;
        }
        anchors.rightMargin: anchors.leftMargin
        anchors.topMargin: anchors.leftMargin
        anchors.bottomMargin: {
            var p = root.parent;
            while (p && !p.hasOwnProperty("activeWidgetsList")) {
                p = p.parent;
            }
            return (p && p.activeWidgetsList.length > 1) ? 4 : 8;
        }
        spacing: 6
        visible: true
        opacity: 0.0
        scale: 0.95

        // No Behavior on opacity/scale: contractAnim/expandAnim are the sole drivers.
        // See note on contractedLayout above for rationale.

        // Top Row: Brand Icon (left) + Audio Output Device (right)
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 24

            // App program source icon
            MaterialShape {
                id: appIconShape
                implicitWidth: 24
                implicitHeight: 24
                shapeString: "Cookie12Sided"
                color: "transparent"
                Layout.alignment: Qt.AlignLeft | Qt.AlignTop

                Loader {
                    id: appIconLoader
                    anchors.fill: parent
                    active: root.player && root.player.desktopEntry !== ""
                    sourceComponent: IconImage {
                        implicitSize: Appearance.font.pixelSize.huge
                        // desktopEntry is the entry id (com.msob7y.namida), not an icon name
                        source: Quickshell.iconPath(DesktopEntries.byId(root.player?.desktopEntry ?? "")?.icon
                            || (root.player?.desktopEntry ?? ""), "audio-x-generic")
                    }
                }

                Loader {
                    anchors.fill: parent
                    active: !appIconLoader.active
                    sourceComponent: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "music_note"
                        iconSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colOnSurface
                    }
                }
            }

            Item {
                Layout.fillWidth: true
            }

            // Audio output device pill (headphones/speaker)
            RippleButton {
                id: audioPill
                implicitHeight: 24
                leftPadding: 8
                rightPadding: 8
                Layout.alignment: Qt.AlignTop
                colBackground: root.containerFillColor
                colBackgroundHover: ColorUtils.mix(root.containerFillColor, root.containerContentColor, 0.9)
                colBackgroundActive: ColorUtils.mix(root.containerFillColor, root.containerContentColor, 0.8)
                colRipple: ColorUtils.applyAlpha(root.containerContentColor, 0.2)

                buttonRadius: Appearance.rounding.full

                readonly property string activeAudioDeviceName: Audio.sink ? (Audio.sink.description || "") : ""
                readonly property string audioDeviceIcon: {
                    let desc = activeAudioDeviceName.toLowerCase();
                    if (desc.includes("headphone") || desc.includes("headset") || desc.includes("wired")) {
                        return "headphones";
                    }
                    return "volume_up";
                }

                onClicked: GlobalStates.openAudioOutputSettings()

                contentItem: RowLayout {
                    id: audioPillLayout
                    spacing: 4

                    MaterialSymbol {
                        text: audioPill.audioDeviceIcon
                        iconSize: Appearance.font.pixelSize.smallest
                        color: root.containerContentColor
                    }

                    StyledText {
                        text: audioPill.activeAudioDeviceName !== "" ? audioPill.activeAudioDeviceName : Translation.tr("Wired headphones")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.bold: true
                        color: root.containerContentColor
                        Layout.maximumWidth: 100
                        elide: Text.ElideRight
                    }
                }
            }
        }

        // Middle Row: Metadata/Lyrics (left) + Large Play/Pause (right)
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 16

            // Left Side: Metadata column (Song title/Lyrics on top, artist below)
            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 2

                Item {
                    id: expandedTitleArea
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    Column {
                        id: expandedLyricsContainer
                        width: parent.width
                        spacing: 0
                        y: expandedLyricsContainer.baseY - expandedLyricsContainer.rowHeight - expandedLyricsContainer.scrollOffset
                        visible: LyricsService.hasSyncedLines

                        readonly property int rowHeight: Math.floor(parent.height / 2.5)
                        readonly property real baseY: (parent.height - rowHeight) / 2
                        readonly property int targetCurrentIndex: LyricsService.hasSyncedLines ? LyricsService.currentIndex : -1
                        property int lastIndex: -1
                        property bool isMovingForward: true
                        property real scrollOffset: 0
                        readonly property real animProgress: rowHeight > 0 ? Math.abs(scrollOffset) / rowHeight : 0

                        onTargetCurrentIndexChanged: {
                            if (targetCurrentIndex !== lastIndex && LyricsService.hasSyncedLines) {
                                isMovingForward = targetCurrentIndex > lastIndex;
                                lastIndex = targetCurrentIndex;
                                expandedScrollAnim.stop();
                                scrollOffset = isMovingForward ? -rowHeight : rowHeight;
                                expandedScrollAnim.start();
                            }
                        }

                        NumberAnimation {
                            id: expandedScrollAnim
                            target: expandedLyricsContainer
                            property: "scrollOffset"
                            to: 0
                            duration: 400
                            easing.type: Easing.OutQuart
                        }

                        Repeater {
                            model: 3

                            Item {
                                required property int index
                                property int lineOffset: index - 1
                                property int actualIndex: expandedLyricsContainer.targetCurrentIndex + lineOffset
                                property bool isValidLine: LyricsService.hasSyncedLines && actualIndex >= 0 && actualIndex < LyricsService.syncedLines.length

                                width: parent.width
                                height: expandedLyricsContainer.rowHeight

                                property int oldLineOffset: expandedLyricsContainer.isMovingForward ? lineOffset + 1 : lineOffset - 1

                                    function getOpacityForOffset(offset) {
                                        let dist = Math.abs(offset);
                                        if (dist === 0) return 1.0;
                                        if (dist === 1) return 0.35;
                                        return 0.1;
                                    }
                                property real targetOpacity: getOpacityForOffset(lineOffset)
                                property real startOpacity: getOpacityForOffset(oldLineOffset)
                                opacity: startOpacity + (targetOpacity - startOpacity) * (1.0 - expandedLyricsContainer.animProgress)

                                function getScaleForOffset(offset) {
                                    return Math.abs(offset) === 0 ? 1.0 : 0.9;
                                }
                                property real targetScale: getScaleForOffset(lineOffset)
                                property real startScale: getScaleForOffset(oldLineOffset)
                                scale: startScale + (targetScale - startScale) * (1.0 - expandedLyricsContainer.animProgress)

                                transformOrigin: Item.Center

                                StyledText {
                                    anchors.fill: parent
                                    font.family: Appearance.font.family.main
                                    font.pixelSize: Appearance.font.pixelSize.large
                                    font.weight: Math.abs(lineOffset) === 0 ? Font.Black : Font.Medium
                                    font.styleName: Math.abs(lineOffset) === 0 ? "Rounded" : "Regular"
                                    font.hintingPreference: Font.PreferNoHinting
                                    color: Appearance.colors.colOnSurface
                                    text: isValidLine ? LyricsService.syncedLines[actualIndex].text : ""
                                    horizontalAlignment: Text.AlignLeft
                                    verticalAlignment: Text.AlignVCenter
                                    elide: Text.ElideRight
                                    wrapMode: Text.WordWrap
                                    maximumLineCount: 2
                                }
                            }
                        }
                    }

                    StyledText {
                        id: expandedTitleText

                        visible: !LyricsService.hasSyncedLines
                        anchors.fill: parent
                        font.family: Appearance.font.family.main
                        font.pixelSize: Appearance.font.pixelSize.large
                        font.weight: Font.Black
                        font.styleName: "Rounded"
                        color: Appearance.colors.colOnSurface
                        text: root.displaySongText
                        maximumLineCount: 2
                        wrapMode: Text.WordWrap
                        elide: Text.ElideRight
                        verticalAlignment: Text.AlignVCenter
                    }
                }

                StyledText {
                    id: expandedArtistText

                    Layout.fillWidth: true
                    font.family: Appearance.font.family.main
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnSurfaceVariant
                    text: root.displayArtist
                    maximumLineCount: 1
                    elide: Text.ElideRight
                    opacity: root.titleOpacity
                    transform: Translate {
                        y: root.titleYOffset
                    }
                }
            }

            // Right Side: Large Play/Pause Button
            RippleButton {
                id: playBtn
                implicitWidth: 52
                implicitHeight: 52
                buttonRadius: 18
                colBackground: root.containerFillColor
                colBackgroundHover: ColorUtils.mix(root.containerFillColor, root.containerContentColor, 0.9)
                colBackgroundActive: ColorUtils.mix(root.containerFillColor, root.containerContentColor, 0.8)
                colRipple: ColorUtils.applyAlpha(root.containerContentColor, 0.2)

                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter

                onClicked: {
                    if (root.player) {
                        if (root.playing)
                            root.player.pause();
                        else
                            root.player.play();
                    }
                }

                contentItem: Item {
                    implicitWidth: 52
                    implicitHeight: 52
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: root.playing ? "pause" : "play_arrow"
                        iconSize: Appearance.font.pixelSize.hugeass
                        color: root.containerContentColor
                        fill: 1
                    }
                }
            }
        }

        // Bottom Row: Prev Button + Progress Bar + Next Button
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 24
            spacing: 12
            Layout.alignment: Qt.AlignBottom

            // Previous Button
            RippleButton {
                id: prevBtn
                implicitWidth: 24
                implicitHeight: 24
                buttonRadius: 12
                colBackground: "transparent"
                colBackgroundHover: "transparent"
                colRipple: root.useDynamicColors ? root.blendedColors.colPrimaryContainer : Appearance.colors.colPrimaryContainer

                onClicked: {
                    if (root.player)
                        root.player.previous();
                }

                    contentItem: Item {
                        implicitWidth: 24
                        implicitHeight: 24
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "skip_previous"
                            iconSize: Appearance.font.pixelSize.normal
                            fill: 1
                            color: {
                                if (!root.player || !root.player.canGoPrevious) {
                                    return Appearance.colors.colOnSurfaceVariant;
                                }
                                return Appearance.colors.colOnSurface;
                            }
                            opacity: root.player && root.player.canGoPrevious ? 1.0 : 0.4
                        }
                    }
            }

            // Progress Slider
            Item {
                id: progressArea
                Layout.fillWidth: true
                Layout.preferredHeight: 16
                Layout.alignment: Qt.AlignVCenter

                Loader {
                    id: sliderLoader
                    anchors.fill: parent
                    active: root.player?.canSeek ?? false
                    sourceComponent: StyledSlider {
                        configuration: StyledSlider.Configuration.Wavy
                        highlightColor: root.seekColor
                        trackColor: root.lightTrackColor
                        handleColor: root.seekColor
                        value: MprisController.trackProgressOf(root.player)
                        // Nothing to seek to while the player publishes no length.
                        enabled: MprisController.hasTrackLength(root.player)
                        onMoved: MprisController.seekFraction(root.player, value)
                        // QQuickSlider writes `value` itself while the user drags, which destroys
                        // the binding below it. Without this the bar froze where the drag left it
                        // and never followed the track again.
                        onPressedChanged: if (!pressed)
                            value = Qt.binding(() => MprisController.trackProgressOf(root.player))
                    }
                }

                Loader {
                    id: progressBarLoader
                    anchors {
                        verticalCenter: parent.verticalCenter
                        left: parent.left
                        right: parent.right
                    }
                    active: !!root.player && !sliderLoader.active
                    sourceComponent: StyledProgressBar {
                        wavy: root.player ? root.playing : false
                        highlightColor: root.seekColor
                        trackColor: root.lightTrackColor
                        value: MprisController.trackProgressOf(root.player)
                    }
                }
            }

            // Next Button
            RippleButton {
                id: nextBtn
                implicitWidth: 24
                implicitHeight: 24
                buttonRadius: 12
                colBackground: "transparent"
                colBackgroundHover: "transparent"
                colRipple: root.useDynamicColors ? root.blendedColors.colPrimaryContainer : Appearance.colors.colPrimaryContainer

                onClicked: {
                    if (root.player)
                        root.player.next();
                }

                    contentItem: Item {
                        implicitWidth: 24
                        implicitHeight: 24
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "skip_next"
                            iconSize: Appearance.font.pixelSize.normal
                            fill: 1
                            color: {
                                if (!root.player || !root.player.canGoNext) {
                                    return Appearance.colors.colOnSurfaceVariant;
                                }
                                return Appearance.colors.colOnSurface;
                            }
                            opacity: root.player && root.player.canGoNext ? 1.0 : 0.4
                        }
                    }
            }
        }
    }
}
