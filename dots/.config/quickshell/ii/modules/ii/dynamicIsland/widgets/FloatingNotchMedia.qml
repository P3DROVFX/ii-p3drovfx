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

    readonly property MprisPlayer player: MprisController.activePlayer
    readonly property bool playing: player ? player.playbackState === MprisPlaybackState.Playing : false
    readonly property string artUrl: MprisController.artUrl
    readonly property string title: (MprisController.activeTrack && MprisController.activeTrack.title) ? MprisController.activeTrack.title : "No title"
    readonly property string artist: (MprisController.activeTrack && MprisController.activeTrack.artist) ? MprisController.activeTrack.artist : "Unknown Artist"
    readonly property string identity: player ? (player.identity ?? "") : ""
    readonly property var activeTrackRef: MprisController.activeTrack

    property bool isExpanded: false

    readonly property Item widgetBg: {
        var p = root.parent;
        if (p && p.parent) {
            return p.parent;
        }
        return root;
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

    readonly property color artTextColor: root.useDynamicColors
        ? root.blendedColors.colOnPrimary
        : (root.currentArtUrl !== "" ? Appearance.colors.colOnSurfaceVariant : Appearance.colors.colOnSurface)
    readonly property color artSubtextColor: root.useDynamicColors
        ? root.blendedColors.colOnPrimary
        : Appearance.colors.colOnSurfaceVariant

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
        if (root.isExpanded) {
            lyricTransitionAnimation.stop();
            lyricTransitionAnimation.start();
        } else {
            root.activeLyricText = root.displaySongText;
        }
    }

    onIsExpandedChanged: {
        if (root.isExpanded) {
            LyricsService.initiliazeLyrics();
            root.activeLyricText = root.displaySongText;
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
    property var visualizerPoints: []

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

    Process {
        id: cavaProc
        running: !root.isExpanded && root.playing
        command: ["cava", "-p", `${FileUtils.trimFileProtocol(Directories.scriptPath)}/cava/raw_output_config.txt`]
        stdout: SplitParser {
            onRead: data => {
                let points = data.split(";").map(p => parseFloat(p.trim())).filter(p => !isNaN(p));
                root.visualizerPoints = points;
            }
        }
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
        visible: !root.isExpanded

        // OpacityMask to clip album art to rounded corners
        Rectangle {
            id: contractedMaskRect
            anchors.fill: parent
            radius: Appearance.rounding.small
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
                    GradientStop { position: 0.15; color: "transparent" }
                    GradientStop { position: 0.35; color: "white" }
                    GradientStop { position: 0.65; color: "white" }
                    GradientStop { position: 0.85; color: "transparent" }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }

            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    orientation: Gradient.Vertical
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.5; color: "white" }
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
            color: root.useDynamicColors ? root.blendedColors.colOnLayer0 : Appearance.colors.colOnSurfaceVariant
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
                    GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.0) }
                    GradientStop { position: 0.5; color: Qt.rgba(0, 0, 0, 0.05) }
                    GradientStop { position: 0.8; color: Qt.rgba(0, 0, 0, 0.25) }
                    GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.45) }
                }
            }

            // Extra dim layer when paused
            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.3)
                opacity: root.playing ? 0.0 : 0.5

                Behavior on opacity {
                    NumberAnimation {
                        duration: 500
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }

        // ── Content row ─────────────────────────────────────────────────────
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
                    Layout.fillWidth: true
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.Black
                    font.styleName: "Rounded"
                    font.hintingPreference: Font.PreferNoHinting
                    color: root.artTextColor
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
                    Layout.fillWidth: true
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: root.artSubtextColor
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
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: root.barWidth * 4 + 2 * 3
                implicitHeight: root.elementHeight

                Row {
                    anchors.centerIn: parent
                    height: parent.height
                    spacing: 2

                    Repeater {
                        model: 4
                        Rectangle {
                            required property int index
                            anchors.verticalCenter: parent.verticalCenter
                            width: root.barWidth
                            height: root.getBarHeight(index)
                            radius: root.barWidth / 2
                            color: root.artTextColor

                            Behavior on height {
                                NumberAnimation {
                                    duration: 85
                                    easing.type: Easing.OutCubic
                                }
                            }
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
        visible: root.isExpanded

        // Mask shape defining the rounded sections
        Rectangle {
            id: maskRect
            anchors.fill: parent
            radius: Appearance.rounding.windowRounding
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
                    GradientStop { position: 0.15; color: "transparent" }
                    GradientStop { position: 0.35; color: "white" }
                    GradientStop { position: 0.65; color: "white" }
                    GradientStop { position: 0.85; color: "transparent" }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }

            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    orientation: Gradient.Vertical
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.5; color: "white" }
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
                    GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.0) }
                    GradientStop { position: 0.5; color: Qt.rgba(0, 0, 0, 0.05) }
                    GradientStop { position: 0.8; color: Qt.rgba(0, 0, 0, 0.25) }
                    GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.45) }
                }
            }

            // Extra dim layer when paused
            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.3)
                opacity: root.playing ? 0.0 : 0.5

                Behavior on opacity {
                    NumberAnimation {
                        duration: 500
                        easing.type: Easing.OutCubic
                    }
                }
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
        visible: root.isExpanded

        // Top Row: Brand Icon (left) + Audio Output Device (right)
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 24

            // App program source icon
            MaterialShape {
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
                        source: Quickshell.iconPath(root.player ? root.player.desktopEntry : "audio-x-generic", "audio-x-generic")
                    }
                }

                Loader {
                    anchors.fill: parent
                    active: !appIconLoader.active
                    sourceComponent: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "music_note"
                        iconSize: Appearance.font.pixelSize.smallest
                        color: root.useDynamicColors ? root.blendedColors.colOnLayer0 : Appearance.colors.colOnSurface
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
                colBackground: root.useDynamicColors ? root.blendedColors.colPrimaryContainer : Appearance.colors.colPrimaryContainer
                colBackgroundHover: root.useDynamicColors ? root.blendedColors.colPrimaryContainerHover : Appearance.colors.colPrimaryContainerHover
                colRipple: root.useDynamicColors ? root.blendedColors.colOnPrimary : Appearance.colors.colOnPrimaryContainer
                buttonRadius: Appearance.rounding.full

                readonly property string activeAudioDeviceName: Audio.sink ? (Audio.sink.description || "") : ""
                readonly property string audioDeviceIcon: {
                    let desc = activeAudioDeviceName.toLowerCase();
                    if (desc.includes("headphone") || desc.includes("headset") || desc.includes("wired")) {
                        return "headphones";
                    }
                    return "volume_up";
                }

                onClicked: {
                    GlobalStates.openRightSidebar();
                    Qt.callLater(() => {
                        GlobalStates.requestVolumeDialog = true;
                    });
                }

                contentItem: RowLayout {
                    id: audioPillLayout
                    spacing: 4

                    MaterialSymbol {
                        text: audioPill.audioDeviceIcon
                        iconSize: Appearance.font.pixelSize.smallest
                        color: root.useDynamicColors ? root.blendedColors.colOnPrimary : Appearance.colors.colOnPrimaryContainer
                    }

                    StyledText {
                        text: audioPill.activeAudioDeviceName !== "" ? audioPill.activeAudioDeviceName : Translation.tr("Wired headphones")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.bold: true
                        color: root.useDynamicColors ? root.blendedColors.colOnPrimary : Appearance.colors.colOnPrimaryContainer
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
                                    color: root.artTextColor
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
                        visible: !LyricsService.hasSyncedLines
                        anchors.fill: parent
                        font.family: Appearance.font.family.main
                        font.pixelSize: Appearance.font.pixelSize.large
                        font.weight: Font.Black
                        font.styleName: "Rounded"
                        color: root.artTextColor
                        text: root.displaySongText
                        maximumLineCount: 2
                        wrapMode: Text.WordWrap
                        elide: Text.ElideRight
                        verticalAlignment: Text.AlignVCenter
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    font.family: Appearance.font.family.main
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: root.artSubtextColor
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
                colBackground: root.useDynamicColors ? root.blendedColors.colPrimaryContainer : Appearance.colors.colPrimaryContainer
                colBackgroundHover: root.useDynamicColors ? root.blendedColors.colPrimaryContainerHover : Appearance.colors.colPrimaryContainerHover
                colRipple: root.useDynamicColors ? root.blendedColors.colPrimaryContainerActive : Appearance.colors.colPrimaryContainerActive
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
                        color: root.useDynamicColors ? root.blendedColors.colOnPrimary : Appearance.colors.colOnPrimaryContainer
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
                                    return root.useDynamicColors ? root.blendedColors.colSubtext : Appearance.colors.colSubtext;
                                }
                                return root.useDynamicColors ? root.blendedColors.colSubtext : Appearance.colors.colPrimaryContainer;
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
                    active: root.player ? (root.player.canSeek ?? false) : false
                    sourceComponent: StyledSlider {
                        configuration: StyledSlider.Configuration.Wavy
                        highlightColor: root.useDynamicColors ? root.blendedColors.colPrimaryContainer : Appearance.colors.colPrimaryContainer
                        trackColor: root.useDynamicColors ? root.blendedColors.colLayer1 : Appearance.colors.colSurfaceContainer
                        handleColor: root.useDynamicColors ? root.blendedColors.colPrimaryContainer : Appearance.colors.colPrimaryContainer
                        value: (root.player && root.player.length > 0) ? (root.player.position / root.player.length) : 0
                        onMoved: if (root.player)
                            root.player.position = value * root.player.length
                    }
                }

                Loader {
                    id: progressBarLoader
                    anchors {
                        verticalCenter: parent.verticalCenter
                        left: parent.left
                        right: parent.right
                    }
                    active: root.player ? !(root.player.canSeek ?? false) : false
                    sourceComponent: StyledProgressBar {
                        wavy: root.player ? root.playing : false
                        highlightColor: root.useDynamicColors ? root.blendedColors.colPrimaryContainer : Appearance.colors.colPrimaryContainer
                        trackColor: root.useDynamicColors ? root.blendedColors.colLayer1 : Appearance.colors.colSurfaceContainer
                        value: (root.player && root.player.length > 0) ? (root.player.position / root.player.length) : 0
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
                                    return root.useDynamicColors ? root.blendedColors.colSubtext : Appearance.colors.colSubtext;
                                }
                                return root.useDynamicColors ? root.blendedColors.colSubtext : Appearance.colors.colPrimaryContainer;
                            }
                            opacity: root.player && root.player.canGoNext ? 1.0 : 0.4
                        }
                    }
            }
        }
    }
}
