pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.widgets
import qs.modules.common.utils
import qs.services
import qs.modules.common.functions
import "MediaModePanelLayout.js" as MediaModePanelLayout

Item { // Fullscreen MediaMode instance
    id: root

    signal closeRequested(bool allMonitors)
    signal localMusicFilesRequested()
    signal localMusicFolderRequested()

    opacity: 0
    Behavior on opacity {
        NumberAnimation {
            duration: 300
            easing.type: Easing.OutQuad
        }
    }

    // The visual tree receives its playback context explicitly. In Phase 1 an
    // application source wraps MprisPlayer; Phase 2 can supply the local proxy
    // without making cover art, lyrics or controls reach into MprisController.
    readonly property string mediaSource: MprisController.effectiveMediaModeSource
    readonly property bool applicationsSource: mediaSource === "applications"
    readonly property bool localSource: mediaSource === "local"

    property string _prevMediaSource: root.mediaSource

    readonly property var player: applicationsSource
        ? MprisController.activePlayer
        : (LocalMediaService.hasSession ? LocalMediaService.player : null)
    readonly property bool hasPlaybackContext: player !== null
    readonly property bool showLocalEmptyState: localSource && !hasPlaybackContext
    readonly property bool queueEligible: localSource
        && LocalMediaService.playlistOpen
        && LocalMediaService.queueSnapshot.entries?.length > 0
    // Automatic lyric expansion / collapse:
    // When a song has identified lyrics, lyrics expand automatically.
    // When a song has no identified lyrics, lyrics collapse automatically.
    // Manual user toggles apply to the current song and reset on track change.
    property string localLyricsPreference: "auto"
    property string currentTrackKey: `${root.player?.trackArtist ?? ""} - ${root.player?.trackTitle ?? ""}`
    onCurrentTrackKeyChanged: {
        root.localLyricsPreference = "auto";
    }

    readonly property bool localLyricsHasIdentifiedLyrics: LyricsService.hasAnyLyrics
    readonly property bool localLyricsExpanded: !queueEligible
        || !localQueueExpanded
        || (localLyricsPreference === "expanded")
        || (localLyricsPreference === "auto" && localLyricsHasIdentifiedLyrics)
    // Recolher Letras preserva o cabeçalho e a ação de reabrir. Só a
    // configuração global pode remover a superfície de letras por completo.
    readonly property bool lyricsPanelVisible: showLyricsPanel
    readonly property bool lyricsContentVisible: lyricsPanelVisible
        && (!queueEligible || localLyricsExpanded)
    readonly property bool rightPanelEligible: lyricsPanelVisible || queueEligible
    readonly property bool rightPanelTargetVisible: rightPanelEligible && !coverExpanded
    readonly property bool rightPanelVisible: rightPanelAnimationProgress > 0.001
    property bool coverExpanded: Persistent.states.background.mediaMode.coverExpanded ?? false
    property real rightPanelAnimationProgress: rightPanelTargetVisible ? 1.0 : 0.0
    Behavior on rightPanelAnimationProgress {
        NumberAnimation {
            duration: Appearance.animation.elementMove.duration
            easing.type: Appearance.animation.elementMove.type
            easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
        }
    }
    readonly property real panelGap: Appearance.sizes.elevationMargin * 2
    readonly property real lyricsHeaderHeight: Appearance.sizes.minimumTouchTarget
        + Appearance.sizes.elevationMargin * 4
    readonly property real queueHeaderHeight: Appearance.sizes.minimumTouchTarget
        + Appearance.sizes.elevationMargin * 2
    property real rightPanelHeight: 0
    readonly property var rightPanelLayout: MediaModePanelLayout.resolve(
        rightPanelHeight, panelGap, lyricsPanelVisible, queueEligible,
        lyricsContentVisible, localQueueExpanded, lyricsHeaderHeight, queueHeaderHeight)
    property bool localQueueExpanded: true
    property string artUrl: applicationsSource
        ? MprisController.artUrl
        : (LocalMediaService.player?.trackArtUrl ?? "")
    property string artDownloadLocation: Directories.coverArt
    property string artFileName: Qt.md5(artUrl)
    property string artFilePath: `${artDownloadLocation}/${artFileName}`
    property bool downloaded: false
    property string displayedArtFilePath: ""
    property bool fileBrowserOpen: false

    function openFileBrowser(audioOnly: bool): void {
        fileBrowser.audioOnly = audioOnly;
        root.fileBrowserOpen = true;
        fileBrowser.open();
    }

    readonly property string trackTitle: root.player?.trackTitle || ""

    // Music video mode state
    readonly property bool videoActive: applicationsSource
        && Config.options.background.mediaMode.musicVideo.enable
        && MusicVideoService.videoPlaying

    // Dynamic Color Palette Logic
    property bool dynamicColorEnabled: Config.options.background.mediaMode.changeShellColor
    property color albumArtExtractedColor: colorQuantizer.colors.length > 0 ? colorQuantizer.colors[0] : Appearance.colors.colPrimary
    property color activeExtractedColor: videoActive ? VideoColorSampler.currentExtractedColor : albumArtExtractedColor
    
    property color extractedColor: activeExtractedColor
    Behavior on extractedColor {
        ColorAnimation {
            duration: Math.min(400, (Config.options.background.mediaMode.musicVideo.videoSamplingInterval ?? 200) * 0.8)
            easing.type: Easing.InOutQuad
        }
    }

    property color dynamicAccentColor: dynamicColorEnabled ? extractedColor : Appearance.colors.colPrimary
    property color dynamicAccentContainer: dynamicColorEnabled ? ColorUtils.transparentize(extractedColor, 0.3) : Appearance.colors.colPrimaryContainer
    property color dynamicOnAccentContainer: dynamicColorEnabled ? ColorUtils.getContrastingTextColor(extractedColor) : Appearance.colors.colOnPrimaryContainer

    Binding {
        target: VideoColorSampler
        property: "active"
        value: videoActive && root.dynamicColorEnabled
    }

    Binding {
        target: VideoColorSampler
        property: "ipcSocket"
        value: MusicVideoService.ipcSocket
    }

    // Mode state options (Bound to Config.options.background.mediaMode)
    property int visualizerMode: Config.options.background.mediaMode.visualizerMode ?? 1 // 0: Off, 1: Waves, 2: Bars, 3: Radial
    property bool showLyricsPanel: Config.options.background.mediaMode.showLyrics ?? true
    property bool showPlayerSwitcher: Config.options.background.mediaMode.showPlayerSwitcher ?? true

    property real lyricsScaleMultiplier: 1.0
    property bool forcePlainLyrics: false

    // Real Cava & Procedural Dynamic Visualizer Points
    property list<var> visualizerPoints: []
    property real animPhase: 0.0
    readonly property bool cavaActive: CavaService.visualizerPoints.length > 0

    Connections {
        target: CavaService
        function onVisualizerPointsChanged() {
            if (CavaService.visualizerPoints && CavaService.visualizerPoints.length > 0) {
                let pts = [];
                for (let i = 0; i < CavaService.visualizerPoints.length; i++) {
                    pts.push(CavaService.visualizerPoints[i]);
                }
                root.visualizerPoints = pts;
            }
        }
    }

    Timer {
        id: proceduralVisualizerTimer
        interval: 50 // ~20 FPS
        running: root.visualizerMode > 0 && !root.cavaActive
        triggeredOnStart: true
        repeat: true
        onTriggered: {
            root.animPhase += 0.04;
            let pts = [];
            const isPlaying = root.player?.isPlaying ?? false;
            for (let i = 0; i < 16; i++) {
                if (isPlaying) {
                    let base = 350 + 120 * Math.sin(root.animPhase + i * 0.28) + 60 * Math.cos(root.animPhase * 0.5 + i * 0.18);
                    pts.push(Math.max(100, Math.min(750, base)));
                } else {
                    pts.push(40);
                }
            }
            root.visualizerPoints = pts;
        }
    }

    onVideoActiveChanged: {
        if (videoActive) {
            Quickshell.execDetached(["hyprctl", "keyword", "layerrule", "unset,quickshell:background"]);
        } else {
            Quickshell.execDetached(["hyprctl", "keyword", "layerrule", "blur,quickshell:background"]);
        }
    }

    onMediaSourceChanged: {
        if (!applicationsSource)
            MusicVideoService.stopVideo();
        if (_prevMediaSource === "local" && root.mediaSource === "applications") {
            if (LocalMediaService.player?.isPlaying)
                LocalMediaService.pause();
        } else if (_prevMediaSource === "applications" && root.mediaSource === "local") {
            if (MprisController.activePlayer?.isPlaying)
                MprisController.activePlayer.pause();
        }
        _prevMediaSource = root.mediaSource;
    }

    Component.onCompleted: {
        Persistent.states.background.mediaMode.userScrollOffset = 0;
        root.opacity = 1.0;
        if (videoActive) {
            Quickshell.execDetached(["hyprctl", "keyword", "layerrule", "unset,quickshell:background"]);
        }
    }
    Component.onDestruction: {
        Quickshell.execDetached(["hyprctl", "keyword", "layerrule", "blur,quickshell:background"]);
    }

    onTrackTitleChanged: Persistent.states.background.mediaMode.userScrollOffset = 0

    function updateArt() {
        if (!root.artUrl) {
            root.displayedArtFilePath = "";
            root.downloaded = false;
            return;
        }
        if (root.artUrl && root.artUrl.startsWith("file://")) {
            root.displayedArtFilePath = root.artUrl;
            root.downloaded = true;
            return;
        }

        coverArtDownloader.targetFile = root.artUrl;
        coverArtDownloader.artFilePath = root.artFilePath;
        root.downloaded = false;
        coverArtDownloader.running = true;
    }

    function refreshArtwork() {
        root.displayedArtFilePath = "";
        root.updateArt();
    }

    onArtFilePathChanged: {
        if (!root.artUrl || root.artUrl.length == 0) {
            root.displayedArtFilePath = "";
            return;
        }
        updateArt();
    }

    Process { // Cover art downloader
        id: coverArtDownloader
        property string targetFile: root.artUrl
        property string artFilePath: root.artFilePath
        command: ["bash", "-c", `[ -f '${artFilePath}' ] || curl -sSL '${targetFile}' -o '${artFilePath}'`]
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                root.displayedArtFilePath = Qt.resolvedUrl(root.artFilePath);
                root.downloaded = true;
            }
        }
    }

    ColorQuantizer {
        id: colorQuantizer
        source: root.displayedArtFilePath
        depth: 0 // 2^0 = 1 color
        rescaleSize: 1 // Rescale to 1x1 pixel for faster processing

        onColorsChanged: {
            if (Config.options.background.mediaMode.changeShellColor && colorQuantizer.colors.length > 0) {
                LyricsService.changeShellColor(colorQuantizer.colors[0]);
            }
        }
    }

    Item {
        id: localEmptyState
        anchors.fill: parent
        visible: root.showLocalEmptyState
        opacity: visible ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }

        Rectangle {
            anchors.fill: parent
            color: Appearance.colors.colLayer0
        }

        ColumnLayout {
            anchors.centerIn: parent
            width: Math.min(parent.width - Appearance.sizes.editModeMargin * 2,
                Appearance.sizes.mediaControlsWidth * 2)
            spacing: Appearance.sizes.elevationMargin * 2

            MaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                text: "library_music"
                iconSize: Appearance.font.pixelSize.hugeass * 2
                color: Appearance.colors.colPrimary
            }

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Start a local music session")
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.huge
                font.family: Appearance.font.family.title
                font.weight: Font.Bold
                color: Appearance.colors.colOnLayer0
            }

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Choose a song or a folder. Playback stays separate from this window.")
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colSubtext
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: Appearance.sizes.elevationMargin

                RippleButton {
                    implicitWidth: musicFileButtonContent.implicitWidth + Appearance.sizes.elevationMargin * 3
                    implicitHeight: Appearance.sizes.minimumTouchTarget
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colPrimary
                    colBackgroundHover: Appearance.colors.colPrimaryHover
                    colBackgroundActive: Appearance.colors.colPrimaryActive
                    onClicked: {
                        root.localMusicFilesRequested();
                        root.openFileBrowser(true);
                    }

                    RowLayout {
                        id: musicFileButtonContent
                        anchors.centerIn: parent
                        spacing: Appearance.sizes.elevationMargin / 2

                        MaterialSymbol {
                            text: "audio_file"
                            iconSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnPrimary
                        }

                        StyledText {
                            text: Translation.tr("Open music")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnPrimary
                        }
                    }
                }

                RippleButton {
                    implicitWidth: musicFolderButtonContent.implicitWidth + Appearance.sizes.elevationMargin * 3
                    implicitHeight: Appearance.sizes.minimumTouchTarget
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colPrimaryContainer
                    colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                    colBackgroundActive: Appearance.colors.colPrimaryContainerActive
                    onClicked: {
                        root.localMusicFolderRequested();
                        root.openFileBrowser(false);
                    }

                    RowLayout {
                        id: musicFolderButtonContent
                        anchors.centerIn: parent
                        spacing: Appearance.sizes.elevationMargin / 2

                        MaterialSymbol {
                            text: "folder_open"
                            iconSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnPrimaryContainer
                        }

                        StyledText {
                            text: Translation.tr("Open folder")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnPrimaryContainer
                        }
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: LocalMediaService.importStatus.length > 0
                    || LocalMediaSelection.lastSelectionDescription.length > 0
                text: LocalMediaService.importStatus.length > 0
                    ? LocalMediaService.importStatus
                    : LocalMediaSelection.lastSelectionDescription
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }

            RippleButton {
                Layout.alignment: Qt.AlignHCenter
                visible: LocalMediaService.importActive
                implicitWidth: cancelImportContent.implicitWidth + Appearance.sizes.elevationMargin * 3
                implicitHeight: Appearance.sizes.minimumTouchTarget
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colLayer2
                colBackgroundHover: Appearance.colors.colLayer2Hover
                colBackgroundActive: Appearance.colors.colLayer2Active
                onClicked: LocalMediaService.cancelImport()

                RowLayout {
                    id: cancelImportContent
                    anchors.centerIn: parent
                    spacing: Appearance.sizes.elevationMargin / 2

                    MaterialSymbol {
                        text: "cancel"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnLayer2
                    }

                    StyledText {
                        text: Translation.tr("Cancel import")
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer2
                    }
                }
            }

            RippleButton {
                Layout.alignment: Qt.AlignHCenter
                visible: MprisController.applicationPlayers.length > 0
                implicitWidth: useApplicationPlayerContent.implicitWidth + Appearance.sizes.elevationMargin * 3
                implicitHeight: Appearance.sizes.minimumTouchTarget
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colLayer2
                colBackgroundHover: Appearance.colors.colLayer2Hover
                colBackgroundActive: Appearance.colors.colLayer2Active
                onClicked: {
                    if (root.localSource && LocalMediaService.player?.isPlaying)
                        LocalMediaService.pause();
                    LocalMediaService.releaseMprisControl();
                    MprisController.setMediaModeSource("applications");
                }

                RowLayout {
                    id: useApplicationPlayerContent
                    anchors.centerIn: parent
                    spacing: Appearance.sizes.elevationMargin / 2

                    MaterialSymbol {
                        text: "apps"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnLayer2
                    }

                    StyledText {
                        text: Translation.tr("Use app player")
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer2
                    }
                }
            }
        }
    }

    Loader {
        id: loader
        anchors.fill: parent
        active: root.hasPlaybackContext
        sourceComponent: Item {
            anchors.fill: parent

            // Music video mode state
            readonly property bool videoActive: root.videoActive
            readonly property bool videoSearching: root.applicationsSource
                && Config.options.background.mediaMode.musicVideo.enable
                && MusicVideoService.searchFailed === false
                && !MusicVideoService.videoPlaying
                && MusicVideoService.lastSearchQuery !== ""

            // Fullscreen Background Base
            Rectangle {
                id: background
                anchors.fill: parent
                color: ColorUtils.applyAlpha(Appearance.colors.colLayer0, videoActive ? 0.0 : 1.0)

                Behavior on color {
                    ColorAnimation {
                        duration: 800
                        easing.type: Easing.InOutQuad
                    }
                }

                // Feature 6: Crossfade / Dissolve curtain on track change when video is active
                Rectangle {
                    id: videoCrossfadeOverlay
                    anchors.fill: parent
                    color: Appearance.colors.colLayer0
                    z: 1
                    opacity: 0.0

                    Connections {
                        target: MusicVideoService
                        function onCurrentVideoUrlChanged() {
                            if (videoActive) {
                                crossfadeAnim.restart();
                            }
                        }
                    }

                    SequentialAnimation {
                        id: crossfadeAnim
                        NumberAnimation {
                            target: videoCrossfadeOverlay
                            property: "opacity"
                            to: 0.85
                            duration: 250
                            easing.type: Easing.OutQuad
                        }
                        PauseAnimation {
                            duration: 150
                        }
                        NumberAnimation {
                            target: videoCrossfadeOverlay
                            property: "opacity"
                            to: 0.0
                            duration: 400
                            easing.type: Easing.InQuad
                        }
                    }
                }

                // Clean Opacity Overlay over the video (provides clear, sharp video with subtle UI contrast)
                Rectangle {
                    anchors.fill: parent
                    color: Qt.rgba(0, 0, 0, 0.15)
                    visible: videoActive
                    z: 2
                }

                // Blurred Album Art Parallax Background (permanece totalmente visível até que o vídeo comece)
                FloatingArtBackground {
                    anchors.fill: parent
                    opacity: videoActive ? 0 : (Config.options.background.mediaMode.backgroundOpacity / 100)
                    animationSpeedScale: Config.options.background.mediaMode.backgroundAnimation.speedScale / 10
                    artFilePath: root.displayedArtFilePath
                    overlayColor: ColorUtils.transparentize(Appearance.colors.colLayer0, videoActive ? 0.75 : 0.25)
                    animationEnabled: Config.options.background.mediaMode.backgroundAnimation.enable && !videoActive

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 800
                            easing.type: Easing.InOutQuad
                        }
                    }

                    workspaceNorm: {
                        const chunkSize = Config?.options.bar.workspaces.shown ?? 10;
                        const lower = Math.floor(bgRoot.firstWorkspaceId / chunkSize) * chunkSize;
                        const upper = Math.ceil(bgRoot.lastWorkspaceId / chunkSize) * chunkSize;
                        const range = upper - lower;
                        const id = bgRoot.monitor.activeWorkspace?.id ?? 1;
                        return range > 0 ? (id - lower) / range : 0.5;
                    }
                }

                // Ambient Audio Wave Visualizer Layer
                Item {
                    anchors.fill: parent
                    visible: root.visualizerMode === 1
                    z: 3

                    WaveVisualizer {
                        anchors.fill: parent
                        live: root.player?.isPlaying ?? false
                        color: root.dynamicAccentColor
                        points: root.visualizerPoints
                    }
                }

                // Ambient Bar Visualizer Layer
                Row {
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    height: 120
                    spacing: 12
                    visible: root.visualizerMode === 2
                    z: 3

                    Repeater {
                        model: root.visualizerPoints.length > 0 ? root.visualizerPoints.length : 16
                        delegate: ModernVisualizerBar {
                            required property int index
                            barWidth: 12
                            maxHeight: 110
                            minHeight: 12
                            color: root.dynamicAccentColor
                            fgColor: Appearance.colors.colTertiary
                            playing: root.player?.isPlaying ?? false
                            amplitude: {
                                const pt = root.visualizerPoints[index] ?? 100;
                                return Math.max(0.1, Math.min(1.0, pt / 900.0));
                            }
                            bgAmplitude: amplitude * 0.8
                        }
                    }
                }

                // Ambient Radial Wave Visualizer Layer
                Item {
                    anchors.centerIn: parent
                    width: Math.min(parent.width, parent.height) * 0.7
                    height: width
                    visible: root.visualizerMode === 3
                    z: 3

                    RadialWaveVisualizer {
                        anchors.fill: parent
                        live: root.player?.isPlaying ?? false
                        color: root.dynamicAccentColor
                        points: root.visualizerPoints
                    }
                }

                // Main Fullscreen Content Column
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 28
                    spacing: 20

                    // 1. Top Expressive Header Bar
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 52
                        spacing: 16

                        // Left: Active Player Switcher Chips
                        RowLayout {
                            spacing: 8
                            visible: root.showPlayerSwitcher

                            StyledText {
                                text: Translation.tr("Media Player:")
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colSubtext
                            }

                            Repeater {
                                model: MprisController.applicationPlayers
                                delegate: RippleButton {
                                    id: playerChip
                                    required property MprisPlayer modelData
                                    readonly property bool isActive: MprisController.trackedPlayer === modelData

                                    implicitHeight: 36
                                    implicitWidth: chipRow.implicitWidth + 24
                                    buttonRadius: Appearance.rounding.full
                                    colBackground: isActive ? root.dynamicAccentColor : ColorUtils.transparentize(Appearance.colors.colLayer2, 0.4)
                                    colBackgroundHover: isActive ? ColorUtils.mix(root.dynamicAccentColor, Appearance.colors.colLayer1Hover, 0.85) : Appearance.colors.colLayer2Hover
                                    colBackgroundActive: isActive ? ColorUtils.mix(root.dynamicAccentColor, Appearance.colors.colLayer1Active, 0.7) : Appearance.colors.colLayer2Active

                                    RowLayout {
                                        id: chipRow
                                        anchors.centerIn: parent
                                        spacing: 6

                                        MaterialSymbol {
                                            iconSize: 16
                                            color: playerChip.isActive ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                                            text: modelData.isPlaying ? "graphic_eq" : "music_note"
                                        }

                                        StyledText {
                                            text: modelData.identity || modelData.desktopEntry || Translation.tr("Player")
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            font.weight: playerChip.isActive ? Font.Bold : Font.Medium
                                            color: playerChip.isActive ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                                        }
                                    }

                                    onClicked: {
                                        if (root.localSource && LocalMediaService.player?.isPlaying)
                                            LocalMediaService.pause();
                                        LocalMediaService.releaseMprisControl();
                                        MprisController.selectMediaModeApplicationPlayer(modelData);
                                    }

                                    StyledToolTip {
                                        text: Translation.tr("Switch active player to ") + (modelData.identity || modelData.desktopEntry || Translation.tr("Player"))
                                    }
                                }

                            }
                        }

                        RippleButton {
                            id: localChip
                            readonly property bool isActive: root.localSource

                            implicitHeight: 36
                            implicitWidth: localSourceContent.implicitWidth + 24
                            buttonRadius: Appearance.rounding.full
                            colBackground: isActive ? root.dynamicAccentColor : ColorUtils.transparentize(Appearance.colors.colLayer2, 0.4)
                            colBackgroundHover: isActive ? ColorUtils.mix(root.dynamicAccentColor, Appearance.colors.colLayer1Hover, 0.85) : Appearance.colors.colLayer2Hover
                            colBackgroundActive: isActive ? ColorUtils.mix(root.dynamicAccentColor, Appearance.colors.colLayer1Active, 0.7) : Appearance.colors.colLayer2Active
                            onClicked: {
                                if (root.applicationsSource && MprisController.activePlayer?.isPlaying)
                                    MprisController.activePlayer.pause();
                                MprisController.setMediaModeSource("local");
                                LocalMediaService.claimMprisControl();
                            }

                            RowLayout {
                                id: localSourceContent
                                anchors.centerIn: parent
                                spacing: 6

                                MaterialSymbol {
                                    iconSize: 16
                                    color: localChip.isActive ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                                    text: "library_music"
                                }

                                StyledText {
                                    text: Translation.tr("Local music")
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.weight: localChip.isActive ? Font.Bold : Font.Medium
                                    color: localChip.isActive ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                                }
                            }

                            StyledToolTip {
                                text: Translation.tr("Switch to local music player")
                            }
                        }

                        RowLayout {
                            spacing: Appearance.sizes.elevationMargin / 2

                            RippleButton {
                                implicitWidth: 36
                                implicitHeight: 36
                                buttonRadius: Appearance.rounding.full
                                colBackground: root.dynamicAccentContainer
                                colBackgroundHover: ColorUtils.mix(root.dynamicAccentContainer, Appearance.colors.colLayer1Hover, 0.85)
                                colBackgroundActive: ColorUtils.mix(root.dynamicAccentContainer, Appearance.colors.colLayer1Active, 0.7)
                                onClicked: root.openFileBrowser(true)

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "audio_file"
                                    iconSize: 18
                                    color: root.dynamicOnAccentContainer
                                }

                                PopupToolTip {
                                    text: Translation.tr("Open music files")
                                }
                            }

                            RippleButton {
                                implicitWidth: 36
                                implicitHeight: 36
                                buttonRadius: Appearance.rounding.full
                                colBackground: root.dynamicAccentContainer
                                colBackgroundHover: ColorUtils.mix(root.dynamicAccentContainer, Appearance.colors.colLayer1Hover, 0.85)
                                colBackgroundActive: ColorUtils.mix(root.dynamicAccentContainer, Appearance.colors.colLayer1Active, 0.7)
                                onClicked: root.openFileBrowser(false)

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "folder_open"
                                    iconSize: 18
                                    color: root.dynamicOnAccentContainer
                                }

                                PopupToolTip {
                                    text: Translation.tr("Open music folder")
                                }
                            }

                            RippleButton {
                                visible: LocalMediaService.importActive
                                implicitWidth: 36
                                implicitHeight: 36
                                buttonRadius: Appearance.rounding.full
                                colBackground: root.dynamicAccentContainer
                                colBackgroundHover: ColorUtils.mix(root.dynamicAccentContainer, Appearance.colors.colLayer1Hover, 0.85)
                                colBackgroundActive: ColorUtils.mix(root.dynamicAccentContainer, Appearance.colors.colLayer1Active, 0.7)
                                onClicked: LocalMediaService.cancelImport()

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "cancel"
                                    iconSize: 18
                                    color: root.dynamicOnAccentContainer
                                }

                                PopupToolTip {
                                    text: LocalMediaService.importStatus.length > 0
                                        ? LocalMediaService.importStatus
                                        : Translation.tr("Cancel import")
                                }
                            }
                        }

                        Item {
                            Layout.fillWidth: true
                        }

                        // Center/Right: Expressive Quick Action Toolbar
                        RowLayout {
                            spacing: 10

                            // Expanded Cover / Fullscreen Player Mode Toggle
                            RippleButton {
                                implicitWidth: 42
                                implicitHeight: 42
                                buttonRadius: Appearance.rounding.full
                                colBackground: root.coverExpanded
                                    ? root.dynamicAccentColor
                                    : root.dynamicAccentContainer
                                colBackgroundHover: root.coverExpanded
                                    ? ColorUtils.mix(root.dynamicAccentColor, Appearance.colors.colLayer1Hover, 0.85)
                                    : ColorUtils.mix(root.dynamicAccentContainer, Appearance.colors.colLayer1Hover, 0.85)
                                colBackgroundActive: root.coverExpanded
                                    ? ColorUtils.mix(root.dynamicAccentColor, Appearance.colors.colLayer1Active, 0.7)
                                    : ColorUtils.mix(root.dynamicAccentContainer, Appearance.colors.colLayer1Active, 0.7)

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    iconSize: 20
                                    color: root.coverExpanded
                                        ? Appearance.colors.colOnPrimary
                                        : root.dynamicOnAccentContainer
                                    text: root.coverExpanded ? "fullscreen_exit" : "fullscreen"
                                }

                                onClicked: {
                                    root.coverExpanded = !root.coverExpanded;
                                    Persistent.states.background.mediaMode.coverExpanded = root.coverExpanded;
                                }

                                PopupToolTip {
                                    text: root.coverExpanded
                                        ? Translation.tr("Show side panels (Lyrics & Queue)")
                                        : Translation.tr("Expand player card (Fullscreen)")
                                }
                            }

                            // Audio Visualizer Selector Toggle
                            RippleButton {
                                implicitWidth: 42
                                implicitHeight: 42
                                buttonRadius: Appearance.rounding.full
                                colBackground: root.dynamicAccentContainer
                                colBackgroundHover: ColorUtils.mix(root.dynamicAccentContainer, Appearance.colors.colLayer1Hover, 0.85)
                                colBackgroundActive: ColorUtils.mix(root.dynamicAccentContainer, Appearance.colors.colLayer1Active, 0.7)

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    iconSize: 20
                                    color: root.dynamicOnAccentContainer
                                    text: {
                                        if (root.visualizerMode === 1)
                                            return "waves";
                                        if (root.visualizerMode === 2)
                                            return "bar_chart";
                                        if (root.visualizerMode === 3)
                                            return "blur_circular";
                                        return "equalizer";
                                    }
                                }

                                onClicked: {
                                    var nextMode = (root.visualizerMode + 1) % 4;
                                    Config.options.background.mediaMode.visualizerMode = nextMode;
                                }

                                PopupToolTip {
                                    text: Translation.tr("Visualizer Mode: ") + (root.visualizerMode === 1 ? Translation.tr("Waves") : (root.visualizerMode === 2 ? Translation.tr("Bars") : (root.visualizerMode === 3 ? Translation.tr("Radial") : Translation.tr("Off"))))
                                }
                            }

                            // Dynamic Color Sync Toggle
                            RippleButton {
                                implicitWidth: 42
                                implicitHeight: 42
                                buttonRadius: Appearance.rounding.full
                                colBackground: root.dynamicAccentContainer
                                colBackgroundHover: ColorUtils.mix(root.dynamicAccentContainer, Appearance.colors.colLayer1Hover, 0.85)
                                colBackgroundActive: ColorUtils.mix(root.dynamicAccentContainer, Appearance.colors.colLayer1Active, 0.7)

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    iconSize: 20
                                    color: root.dynamicOnAccentContainer
                                    text: "palette"
                                }

                                onClicked: {
                                    Config.options.background.mediaMode.changeShellColor = !Config.options.background.mediaMode.changeShellColor;
                                    if (Config.options.background.mediaMode.changeShellColor && colorQuantizer.colors.length > 0) {
                                        LyricsService.changeShellColor(colorQuantizer.colors[0]);
                                    }
                                }

                                PopupToolTip {
                                    text: Translation.tr("Dynamic Shell Color: Extract colors from album art")
                                }
                            }

                            // Lyrics Sync Offset Adjustment Controls
                            RowLayout {
                                spacing: 4

                                RippleButton {
                                    implicitWidth: 34
                                    implicitHeight: 42
                                    buttonRadius: Appearance.rounding.full
                                    colBackground: root.dynamicAccentContainer
                                    colBackgroundHover: ColorUtils.mix(root.dynamicAccentContainer, Appearance.colors.colLayer1Hover, 0.85)
                                    colBackgroundActive: ColorUtils.mix(root.dynamicAccentContainer, Appearance.colors.colLayer1Active, 0.7)

                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        iconSize: 18
                                        color: root.dynamicOnAccentContainer
                                        text: "more_time"
                                    }

                                    onClicked: {
                                        const offsets = [0, -1000, -500, 500, 1000, 2000];
                                        const current = Config.options.background.mediaMode.lyricsOffsetMs ?? 0;
                                        let idx = offsets.indexOf(current);
                                        let next = offsets[(idx + 1) % offsets.length];
                                        Config.options.background.mediaMode.lyricsOffsetMs = next;
                                    }

                                    PopupToolTip {
                                        text: Translation.tr("Lyrics Sync Offset: ") + ((Config.options.background.mediaMode.lyricsOffsetMs ?? 0) > 0 ? "+" : "") + (Config.options.background.mediaMode.lyricsOffsetMs ?? 0) + "ms (click to cycle)"
                                    }
                                }

                                RippleButton {
                                    implicitWidth: 28
                                    implicitHeight: 42
                                    buttonRadius: Appearance.rounding.full
                                    colBackground: root.dynamicAccentContainer
                                    colBackgroundHover: ColorUtils.mix(root.dynamicAccentContainer, Appearance.colors.colLayer1Hover, 0.85)
                                    colBackgroundActive: ColorUtils.mix(root.dynamicAccentContainer, Appearance.colors.colLayer1Active, 0.7)

                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        iconSize: 16
                                        color: root.dynamicOnAccentContainer
                                        text: "remove"
                                    }

                                    onClicked: {
                                        Config.options.background.mediaMode.lyricsOffsetMs = (Config.options.background.mediaMode.lyricsOffsetMs ?? 0) - 250;
                                    }

                                    PopupToolTip {
                                        text: Translation.tr("Nudge Lyrics -250ms (Earlier)")
                                    }
                                }

                                RippleButton {
                                    implicitWidth: 28
                                    implicitHeight: 42
                                    buttonRadius: Appearance.rounding.full
                                    colBackground: root.dynamicAccentContainer
                                    colBackgroundHover: ColorUtils.mix(root.dynamicAccentContainer, Appearance.colors.colLayer1Hover, 0.85)
                                    colBackgroundActive: ColorUtils.mix(root.dynamicAccentContainer, Appearance.colors.colLayer1Active, 0.7)

                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        iconSize: 16
                                        color: root.dynamicOnAccentContainer
                                        text: "add"
                                    }

                                    onClicked: {
                                        Config.options.background.mediaMode.lyricsOffsetMs = (Config.options.background.mediaMode.lyricsOffsetMs ?? 0) + 250;
                                    }

                                    PopupToolTip {
                                        text: Translation.tr("Nudge Lyrics +250ms (Later)")
                                    }
                                }
                            }

                            // Music Video Background Toggle
                            RippleButton {
                                implicitWidth: 42
                                implicitHeight: 42
                                buttonRadius: Appearance.rounding.full
                                colBackground: root.dynamicAccentContainer
                                colBackgroundHover: ColorUtils.mix(root.dynamicAccentContainer, Appearance.colors.colLayer1Hover, 0.85)
                                colBackgroundActive: ColorUtils.mix(root.dynamicAccentContainer, Appearance.colors.colLayer1Active, 0.7)

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    iconSize: 20
                                    color: root.dynamicOnAccentContainer
                                    text: videoActive ? "play_circle" : (videoSearching ? "hourglass_top" : "music_video")
                                }

                                onClicked: {
                                    Config.options.background.mediaMode.musicVideo.enable = !Config.options.background.mediaMode.musicVideo.enable;
                                    if (Config.options.background.mediaMode.musicVideo.enable) {
                                        MusicVideoService.tryPlayCurrent();
                                    } else {
                                        MusicVideoService.stopVideo();
                                    }
                                }

                                PopupToolTip {
                                    text: Config.options.background.mediaMode.musicVideo.enable ? Translation.tr("Music Video Background: ON (click to disable)") : Translation.tr("Music Video Background: OFF (click to enable)")
                                }
                            }

                            // Stop & Terminate Local Music Player Button (Local Player Only)
                            RippleButton {
                                visible: root.localSource
                                implicitWidth: 42
                                implicitHeight: 42
                                buttonRadius: Appearance.rounding.full
                                colBackground: Appearance.colors.colLayer2
                                colBackgroundHover: Appearance.colors.colErrorContainerHover
                                colBackgroundActive: Appearance.colors.colErrorContainerActive

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    iconSize: 20
                                    color: Appearance.colors.colOnLayer2
                                    text: "power_settings_new"
                                }

                                onClicked: {
                                    LocalMediaService.terminateService();
                                    root.closeRequested(!Config.options.background.mediaMode.togglePerMonitor);
                                }

                                StyledToolTip {
                                    text: Translation.tr("Close Media Mode and stop local music service")
                                }
                            }

                            // Close / Exit Media Mode Button
                            RippleButton {
                                implicitWidth: 42
                                implicitHeight: 42
                                buttonRadius: Appearance.rounding.full
                                colBackground: Appearance.colors.colErrorContainer
                                colBackgroundHover: Appearance.colors.colErrorContainerHover
                                colBackgroundActive: Appearance.colors.colErrorContainerActive

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    iconSize: 20
                                    color: Appearance.colors.colOnErrorContainer
                                    text: "close"
                                }

                                onClicked: {
                                    root.closeRequested(!Config.options.background.mediaMode.togglePerMonitor);
                                }

                                StyledToolTip {
                                    text: Translation.tr("Exit Fullscreen Media Mode")
                                }
                            }
                        }
                    }

                    // 2. Main Responsive 2-Column Split Body
                    RowLayout {
                        id: mainSplitRow
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: Math.round(24 * root.rightPanelAnimationProgress)

                        // Left Column (~44%): Hero Cover Art & Player Control Card
                        Item {
                            id: leftColumn
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.preferredWidth: Math.round((mainSplitRow.width - (24 * root.rightPanelAnimationProgress)) * (1.0 - 0.56 * root.rightPanelAnimationProgress))

                            Rectangle {
                                anchors.fill: parent
                                radius: Appearance.rounding.verylarge
                                color: videoActive ? ColorUtils.transparentize(Appearance.colors.colLayer1Base, 0.70) : ColorUtils.transparentize(Appearance.colors.colLayer1Base, 0.55)

                                Behavior on color {
                                    ColorAnimation { duration: 400; easing.type: Easing.InOutQuad }
                                }

                                MediaModeCoverArt {
                                    anchors.fill: parent
                                    player: root.player
                                    localSource: root.localSource
                                    artFilePath: root.displayedArtFilePath
                                    refreshArtworkAction: root.refreshArtwork
                                    showLoadingIndicator: !root.downloaded
                                    accentColor: root.dynamicAccentColor
                                    accentContainerColor: root.dynamicAccentContainer
                                    onAccentContainerColor: root.dynamicOnAccentContainer
                                    expanded: !root.rightPanelTargetVisible
                                }
                            }
                        }

                        // Right Column (~56%): Lyrics and a local-only queue are
                        // sibling surfaces. Application players never reserve
                        // this area for queue controls.
                        Item {
                            id: rightColumn
                            Layout.fillWidth: false
                            Layout.fillHeight: true
                            Layout.preferredWidth: Math.round((mainSplitRow.width - (24 * root.rightPanelAnimationProgress)) * (0.56 * root.rightPanelAnimationProgress))
                            visible: root.rightPanelAnimationProgress > 0.001
                            clip: true

                            Binding {
                                target: root
                                property: "rightPanelHeight"
                                value: Math.max(100, rightColumn.height)
                            }

                            Item {
                                id: rightColumnContent
                                width: Math.max(300, Math.round((mainSplitRow.width - 24) * 0.56))
                                height: parent.height
                                anchors.left: parent.left
                                opacity: Math.max(0, Math.min(1, root.rightPanelAnimationProgress))

                                transform: Translate {
                                    x: Math.round((1.0 - root.rightPanelAnimationProgress) * 80)
                                }

                                ColumnLayout {
                                    anchors.fill: parent
                                    spacing: root.rightPanelLayout.gap

                                Item {
                                    id: lyricsPanel
                                    Layout.fillWidth: true
                                    Layout.fillHeight: false
                                    property real targetHeight: root.rightPanelLayout.lyricsHeight
                                    Layout.preferredHeight: targetHeight
                                    visible: root.lyricsPanelVisible

                                    Behavior on targetHeight {
                                        NumberAnimation {
                                            duration: Appearance.animation.elementMove.duration
                                            easing.type: Appearance.animation.elementMove.type
                                            easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                                        }
                                    }

                                    Rectangle {
                                        id: lyricsContainer
                                        anchors.fill: parent
                                        radius: Appearance.rounding.verylarge
                                        color: videoActive ? ColorUtils.transparentize(Appearance.colors.colLayer1Base, 0.80) : ColorUtils.transparentize(Appearance.colors.colLayer1Base, 0.65)

                                        Behavior on color {
                                            ColorAnimation { duration: 400; easing.type: Easing.InOutQuad }
                                        }

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 24
                                    spacing: 16

                                    // Lyrics Studio Header Toolbar
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 12

                                        MaterialSymbol {
                                            iconSize: 22
                                            color: root.dynamicAccentColor
                                            text: "lyrics"
                                        }

                                        StyledText {
                                            text: Translation.tr("Lyrics Studio")
                                            font.pixelSize: Appearance.font.pixelSize.large
                                            font.weight: Font.Bold
                                            font.family: Appearance.font.family.title
                                            color: Appearance.colors.colOnLayer0
                                        }

                                        // Status Chip
                                        Rectangle {
                                            implicitWidth: statusText.implicitWidth + 16
                                            implicitHeight: 24
                                            radius: Appearance.rounding.full
                                            color: ColorUtils.transparentize(root.dynamicAccentContainer, 0.4)

                                            StyledText {
                                                id: statusText
                                                anchors.centerIn: parent
                                                text: {
                                                    if (lyricsItem.hasSyncedLines)
                                                        return LyricsService.usingCustomLyrics
                                                            ? Translation.tr("Custom LRC")
                                                            : (LyricsService.usingLocalLyrics
                                                                ? Translation.tr("Local LRC")
                                                                : Translation.tr("Synced LRC"));
                                                    if (LyricsService.usingLocalLyrics)
                                                        return Translation.tr("Local text");
                                                    if (LyricsService.plainLyrics && LyricsService.plainLyrics.trim().length > 0) {
                                                        const p = Config.options.lyricsService.lyricsProvider;
                                                        if (p === "ytmusic")
                                                            return Translation.tr("YouTube Music");
                                                        if (p === "genius")
                                                            return Translation.tr("Genius");
                                                        if (p === "lrclib")
                                                            return Translation.tr("LRCLib Plain");
                                                        return Translation.tr("Plain Text");
                                                    }
                                                    if (lyricsItem.instrumental)
                                                        return Translation.tr("Instrumental");
                                                    if (lyricsItem.searching)
                                                        return Translation.tr("Searching...");
                                                    return Translation.tr("No lyrics");
                                                }
                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                font.weight: Font.Medium
                                                color: ColorUtils.contrastRatio(root.dynamicAccentColor, Appearance.colors.colLayer1Base) >= 3.0
                                                    ? root.dynamicAccentColor
                                                    : Appearance.colors.colOnLayer0
                                            }
                                        }

                                        Item {
                                            Layout.fillWidth: true
                                        }

                                        RippleButton {
                                            visible: root.queueEligible
                                            implicitWidth: Appearance.sizes.minimumTouchTarget - Appearance.sizes.elevationMargin
                                            implicitHeight: implicitWidth
                                            buttonRadius: Appearance.rounding.full
                                            colBackground: Appearance.colors.colLayer2
                                            colBackgroundHover: Appearance.colors.colLayer2Hover
                                            colBackgroundActive: Appearance.colors.colLayer2Active
                                            onClicked: {
                                                if (root.localLyricsExpanded) {
                                                    root.localLyricsPreference = "collapsed";
                                                    root.localQueueExpanded = true;
                                                } else {
                                                    root.localLyricsPreference = "expanded";
                                                }
                                            }

                                            MaterialSymbol {
                                                anchors.centerIn: parent
                                                text: root.localLyricsExpanded ? "keyboard_arrow_up" : "keyboard_arrow_down"
                                                iconSize: Appearance.font.pixelSize.normal
                                                color: Appearance.colors.colOnLayer2
                                            }

                                            PopupToolTip {
                                                text: root.localLyricsExpanded
                                                    ? Translation.tr("Collapse lyrics")
                                                    : Translation.tr("Expand lyrics")
                                            }
                                        }

                                        // Provider Selector Buttons
                                        Row {
                                            spacing: 4

                                            Repeater {
                                                model: [
                                                    {
                                                        key: "auto",
                                                        icon: "auto_awesome",
                                                        tip: Translation.tr("Auto (LRC → YTMusic → Genius)")
                                                    },
                                                    {
                                                        key: "lrclib",
                                                        icon: "timer",
                                                        tip: Translation.tr("LRCLib synced/plain")
                                                    },
                                                    {
                                                        key: "ytmusic",
                                                        icon: "smart_display",
                                                        tip: Translation.tr("YouTube Music")
                                                    },
                                                    {
                                                        key: "genius",
                                                        icon: "music_note",
                                                        tip: Translation.tr("Genius (plain)")
                                                    }
                                                ]

                                                delegate: RippleButton {
                                                    required property var modelData
                                                    implicitWidth: 28
                                                    implicitHeight: 28
                                                    buttonRadius: Appearance.rounding.full
                                                    readonly property bool isActive: Config.options.lyricsService.lyricsProvider === modelData.key
                                                    readonly property string tipText: modelData.tip
                                                    colBackground: isActive ? ColorUtils.transparentize(root.dynamicAccentColor, 0.25) : ColorUtils.transparentize(Appearance.colors.colLayer2, 0.5)
                                                    colBackgroundHover: isActive ? ColorUtils.transparentize(root.dynamicAccentColor, 0.15) : Appearance.colors.colLayer2Hover
                                                    colBackgroundActive: Appearance.colors.colLayer2Active

                                                    MaterialSymbol {
                                                        anchors.centerIn: parent
                                                        iconSize: 14
                                                        color: parent.isActive ? root.dynamicAccentColor : Appearance.colors.colOnLayer2
                                                        text: modelData.icon
                                                    }
                                                    onClicked: {
                                                        Config.options.lyricsService.lyricsProvider = modelData.key;
                                                        LyricsService.initiliazeLyrics();
                                                    }
                                                    PopupToolTip {
                                                        text: parent.tipText
                                                    }
                                                }
                                            }
                                        }

                                        // Font Zoom Controls
                                        RippleButton {
                                            implicitWidth: 32
                                            implicitHeight: 32
                                            buttonRadius: Appearance.rounding.full
                                            colBackground: ColorUtils.transparentize(Appearance.colors.colLayer2, 0.5)
                                            colBackgroundHover: Appearance.colors.colLayer2Hover
                                            colBackgroundActive: Appearance.colors.colLayer2Active

                                            MaterialSymbol {
                                                anchors.centerIn: parent
                                                iconSize: 16
                                                color: Appearance.colors.colOnLayer2
                                                text: "remove"
                                            }
                                            onClicked: root.lyricsScaleMultiplier = Math.max(0.7, root.lyricsScaleMultiplier - 0.15)
                                            StyledToolTip {
                                                text: Translation.tr("Decrease Lyrics Size")
                                            }
                                        }

                                        RippleButton {
                                            implicitWidth: 32
                                            implicitHeight: 32
                                            buttonRadius: Appearance.rounding.full
                                            colBackground: ColorUtils.transparentize(Appearance.colors.colLayer2, 0.5)
                                            colBackgroundHover: Appearance.colors.colLayer2Hover
                                            colBackgroundActive: Appearance.colors.colLayer2Active

                                            MaterialSymbol {
                                                anchors.centerIn: parent
                                                iconSize: 16
                                                color: Appearance.colors.colOnLayer2
                                                text: "add"
                                            }
                                            onClicked: root.lyricsScaleMultiplier = Math.min(1.8, root.lyricsScaleMultiplier + 0.15)
                                            StyledToolTip {
                                                text: Translation.tr("Increase Lyrics Size")
                                            }
                                        }

                                        // Refresh Lyrics Button
                                        RippleButton {
                                            implicitWidth: 32
                                            implicitHeight: 32
                                            buttonRadius: Appearance.rounding.full
                                            colBackground: ColorUtils.transparentize(Appearance.colors.colLayer2, 0.5)
                                            colBackgroundHover: Appearance.colors.colLayer2Hover
                                            colBackgroundActive: Appearance.colors.colLayer2Active

                                            MaterialSymbol {
                                                anchors.centerIn: parent
                                                iconSize: 16
                                                color: Appearance.colors.colOnLayer2
                                                text: "refresh"
                                            }
                                            onClicked: LyricsService.initiliazeLyrics()
                                            StyledToolTip {
                                                text: Translation.tr("Reload Lyrics")
                                            }
                                        }
                                    }

                                    // Lyrics Content Area
                                    Item {
                                        id: lyricsItem
                                        Layout.fillWidth: true
                                        Layout.fillHeight: root.lyricsContentVisible
                                        visible: root.lyricsContentVisible || opacity > 0
                                        opacity: root.lyricsContentVisible ? 1 : 0

                                        Behavior on opacity {
                                            NumberAnimation {
                                                duration: Appearance.animation.elementMoveFast.duration
                                                easing.type: Appearance.animation.elementMoveFast.type
                                                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                                            }
                                        }

                                        readonly property bool providerAllowsSynced: Config.options.lyricsService.lyricsProvider === "auto" || Config.options.lyricsService.lyricsProvider === "lrclib"
                                        readonly property bool hasSyncedLines: LyricsService.syncedLines.length > 0
                                            && !root.forcePlainLyrics
                                            && (LyricsService.usingLocalLyrics || providerAllowsSynced)
                                        readonly property bool geniusEnabled: Config.options.lyricsService.enableGenius
                                        readonly property bool lrclibEnabled: Config.options.lyricsService.enableLrclib
                                        readonly property bool ytmusicEnabled: Config.options.lyricsService.enableYtmusic
                                        readonly property bool anyProviderEnabled: geniusEnabled || lrclibEnabled || ytmusicEnabled

                                        // Four mutually exclusive "no scrolling lyrics" answers, only the
                                        // last of which is actually a failure.
                                        readonly property bool hasPlainLyrics: !hasSyncedLines && LyricsService.hasPlainLyrics
                                        readonly property bool instrumental: !hasSyncedLines && !hasPlainLyrics
                                            && LyricsService.instrumental
                                        readonly property bool searching: !hasSyncedLines && !hasPlainLyrics
                                            && !instrumental && (LyricsService.localLyricsLoading
                                                || (anyProviderEnabled && LyricsService.searching))
                                        readonly property bool notFound: !hasSyncedLines && !hasPlainLyrics
                                            && !instrumental && !searching

                                        Component.onCompleted: {
                                            // Local sidecars use the same parser and state surface as
                                            // online lyrics, even if every remote provider is disabled.
                                            if (root.localSource || geniusEnabled || lrclibEnabled || ytmusicEnabled)
                                                LyricsService.initiliazeLyrics();
                                        }

                                        FadeLoader {
                                            shown: lyricsItem.hasPlainLyrics
                                            anchors.fill: parent
                                            sourceComponent: LyricsFlickable {
                                                anchors.fill: parent
                                                player: root.player
                                                fontPixelSize: Appearance.font.pixelSize.hugeass * 1.2 * root.lyricsScaleMultiplier
                                            }
                                        }

                                        FadeLoader {
                                            shown: lyricsItem.searching
                                            anchors.fill: parent
                                            sourceComponent: MediaModeLyricsSkeleton {
                                                anchors.fill: parent
                                                largeFontSize: Appearance.font.pixelSize.hugeass * 1.3 * root.lyricsScaleMultiplier
                                                activeColor: root.dynamicAccentColor
                                            }
                                        }

                                        FadeLoader {
                                            shown: lyricsItem.instrumental || lyricsItem.notFound
                                            anchors.fill: parent
                                            sourceComponent: MediaModeLyricsFallback {
                                                anchors.fill: parent
                                                mode: lyricsItem.instrumental ? "instrumental" : "notFound"
                                                largeFontSize: Appearance.font.pixelSize.hugeass * 1.3 * root.lyricsScaleMultiplier
                                                activeColor: root.dynamicAccentColor
                                                onAccentContainerColor: root.dynamicOnAccentContainer
                                                artFilePath: root.displayedArtFilePath
                                                player: root.player
                                                visualizerPoints: root.visualizerPoints
                                                playing: root.player?.isPlaying ?? false
                                            }
                                        }

                                        FadeLoader {
                                            shown: lyricsItem.hasSyncedLines
                                            anchors.fill: parent
                                            sourceComponent: MediaModeLyrics {
                                                anchors.fill: parent
                                                player: root.player
                                                // Resting size; the centred line renders at
                                                // focusedFontSizeMultiplier times this.
                                                largeFontSize: Appearance.font.pixelSize.hugeass * 1.3 * root.lyricsScaleMultiplier
                                                activeColor: root.dynamicAccentColor
                                            }
                                        }
                                    }
                                }
                            }

                                }

                            MediaModeQueue {
                                id: queuePanel
                                property real targetHeight: root.rightPanelLayout.queueHeight
                                Layout.fillWidth: true
                                Layout.fillHeight: false
                                Layout.preferredHeight: targetHeight
                                visible: root.queueEligible
                                expanded: root.localQueueExpanded
                                lyricsExpanded: root.localLyricsExpanded
                                lyricsToggleAvailable: root.showLyricsPanel
                                queueSnapshot: LocalMediaService.queueSnapshot
                                accentColor: root.dynamicAccentColor
                                accentContainerColor: root.dynamicAccentContainer
                                onAccentContainerColor: root.dynamicOnAccentContainer
                                onOpenFileBrowserRequested: audioOnly => root.openFileBrowser(audioOnly)
                                onExpandedToggled: {
                                    if (root.localQueueExpanded) {
                                        root.localQueueExpanded = false;
                                        root.localLyricsPreference = "expanded";
                                    } else {
                                        root.localQueueExpanded = true;
                                    }
                                }
                                onLyricsExpandedToggled: {
                                    if (root.localLyricsExpanded) {
                                        root.localLyricsPreference = "collapsed";
                                        root.localQueueExpanded = true;
                                    } else {
                                        root.localLyricsPreference = "expanded";
                                    }
                                }

                                Behavior on targetHeight {
                                    NumberAnimation {
                                        duration: Appearance.animation.elementMove.duration
                                        easing.type: Appearance.animation.elementMove.type
                                        easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
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

    MediaModeFileBrowser {
        id: fileBrowser
        anchors.fill: parent
        z: 100
        accentColor: root.dynamicAccentColor
        accentContainerColor: root.dynamicAccentContainer
        onAccentContainerColor: root.dynamicOnAccentContainer
        onCloseRequested: root.fileBrowserOpen = false
        onTrackPlayed: root.fileBrowserOpen = false
        onFolderPlayed: root.fileBrowserOpen = false
    }
}
