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

Item { // Fullscreen MediaMode instance
    id: root

    property MprisPlayer player: MprisController.activePlayer
    property var artUrl: MprisController.artUrl
    property string artDownloadLocation: Directories.coverArt
    property string artFileName: Qt.md5(artUrl)
    property string artFilePath: `${artDownloadLocation}/${artFileName}`
    property bool downloaded: false
    property string displayedArtFilePath: ""

    readonly property string trackTitle: root.player?.trackTitle || ""

    // Dynamic Color Palette Logic
    property bool dynamicColorEnabled: Config.options.background.mediaMode.changeShellColor
    property color extractedColor: colorQuantizer.colors.length > 0 ? colorQuantizer.colors[0] : Appearance.colors.colPrimary
    property color dynamicAccentColor: dynamicColorEnabled ? extractedColor : Appearance.colors.colPrimary
    property color dynamicAccentContainer: dynamicColorEnabled ? ColorUtils.mix(extractedColor, Appearance.colors.colPrimaryContainer, 0.4) : Appearance.colors.colPrimaryContainer
    property color dynamicOnAccentContainer: dynamicColorEnabled ? (extractedColor.hslLightness < 0.5 ? "#ffffff" : "#000000") : Appearance.colors.colOnPrimaryContainer

    // Mode state options (Bound to Config.options.background.mediaMode)
    property int visualizerMode: Config.options.background.mediaMode.visualizerMode ?? 1 // 0: Off, 1: Waves, 2: Bars, 3: Radial
    property bool showLyricsPanel: Config.options.background.mediaMode.showLyrics ?? true
    property bool showPlayerSwitcher: Config.options.background.mediaMode.showPlayerSwitcher ?? true

    property real lyricsScaleMultiplier: 1.0
    property bool forcePlainLyrics: false

    // Real Cava & Procedural Dynamic Visualizer Points
    property list<var> visualizerPoints: []
    property real animPhase: 0.0
    property bool cavaActive: false

    Timer {
        id: proceduralVisualizerTimer
        interval: 50 // ~20 FPS
        running: (root.player?.isPlaying ?? false) && root.visualizerMode > 0 && !root.cavaActive
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

    Process {
        id: cavaProc
        running: root.visualizerMode > 0
        command: ["cava", "-p", `${FileUtils.trimFileProtocol(Directories.scriptPath)}/cava/raw_output_config.txt`]
        stdout: SplitParser {
            onRead: data => {
                let pts = data.split(";").map(p => parseFloat(p.trim())).filter(p => !isNaN(p));
                if (pts.length > 0) {
                    root.cavaActive = true;
                    root.visualizerPoints = pts;
                }
            }
        }
    }

    Component.onCompleted: {
        Persistent.states.background.mediaMode.userScrollOffset = 0;
        GlobalStates.mediaModeCount++;
    }
    Component.onDestruction: GlobalStates.mediaModeCount--;

    onTrackTitleChanged: Persistent.states.background.mediaMode.userScrollOffset = 0;

    function updateArt() {
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

    Loader {
        id: loader
        anchors.fill: parent
        active: true
        sourceComponent: Item {
            anchors.fill: parent

            // Fullscreen Background Base
            Rectangle {
                id: background
                anchors.fill: parent
                color: ColorUtils.applyAlpha(Appearance.colors.colLayer0, 1)

                // Blurred Album Art Parallax Background
                FloatingArtBackground {
                    anchors.fill: parent
                    opacity: Config.options.background.mediaMode.backgroundOpacity / 100
                    animationSpeedScale: Config.options.background.mediaMode.backgroundAnimation.speedScale / 10
                    artFilePath: root.displayedArtFilePath
                    overlayColor: ColorUtils.transparentize(Appearance.colors.colLayer0, 0.25)
                    animationEnabled: Config.options.background.mediaMode.backgroundAnimation.enable

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
                                model: MprisController.players
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
                                        MprisController.trackedPlayer = modelData;
                                    }

                                    StyledToolTip {
                                        text: Translation.tr("Switch active player to ") + (modelData.identity || modelData.desktopEntry || Translation.tr("Player"))
                                    }
                                }
                            }
                        }

                        Item { Layout.fillWidth: true }

                        // Center/Right: Expressive Quick Action Toolbar
                        RowLayout {
                            spacing: 10

                            // Audio Visualizer Selector Toggle
                            RippleButton {
                                implicitWidth: 42
                                implicitHeight: 42
                                buttonRadius: Appearance.rounding.full
                                colBackground: ColorUtils.transparentize(Appearance.colors.colLayer2, 0.5)
                                colBackgroundHover: Appearance.colors.colLayer2Hover
                                colBackgroundActive: Appearance.colors.colLayer2Active

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    iconSize: 20
                                    color: root.visualizerMode > 0 ? root.dynamicAccentColor : Appearance.colors.colSubtext
                                    text: {
                                        if (root.visualizerMode === 1) return "waves";
                                        if (root.visualizerMode === 2) return "bar_chart";
                                        if (root.visualizerMode === 3) return "blur_circular";
                                        return "equalizer";
                                    }
                                }

                                onClicked: {
                                    var nextMode = (root.visualizerMode + 1) % 4;
                                    root.visualizerMode = nextMode;
                                    Config.options.background.mediaMode.visualizerMode = nextMode;
                                }

                                StyledToolTip {
                                    text: Translation.tr("Visualizer Mode: ") + (root.visualizerMode === 1 ? Translation.tr("Waves") : (root.visualizerMode === 2 ? Translation.tr("Bars") : (root.visualizerMode === 3 ? Translation.tr("Radial") : Translation.tr("Off"))))
                                }
                            }

                            // Dynamic Color Sync Toggle
                            RippleButton {
                                implicitWidth: 42
                                implicitHeight: 42
                                buttonRadius: Appearance.rounding.full
                                colBackground: Config.options.background.mediaMode.changeShellColor ? root.dynamicAccentColor : ColorUtils.transparentize(Appearance.colors.colLayer2, 0.5)
                                colBackgroundHover: Config.options.background.mediaMode.changeShellColor ? ColorUtils.mix(root.dynamicAccentColor, Appearance.colors.colLayer1Hover, 0.85) : Appearance.colors.colLayer2Hover
                                colBackgroundActive: Config.options.background.mediaMode.changeShellColor ? ColorUtils.mix(root.dynamicAccentColor, Appearance.colors.colLayer1Active, 0.7) : Appearance.colors.colLayer2Active

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    iconSize: 20
                                    color: Config.options.background.mediaMode.changeShellColor ? Appearance.colors.colOnPrimary : Appearance.colors.colSubtext
                                    text: "palette"
                                }

                                onClicked: {
                                    Config.options.background.mediaMode.changeShellColor = !Config.options.background.mediaMode.changeShellColor;
                                    if (Config.options.background.mediaMode.changeShellColor && colorQuantizer.colors.length > 0) {
                                        LyricsService.changeShellColor(colorQuantizer.colors[0]);
                                    }
                                }

                                StyledToolTip {
                                    text: Translation.tr("Dynamic Shell Color: Extract colors from album art")
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
                                    if (typeof mediaModeLoader !== "undefined") {
                                        mediaModeLoader.active = false;
                                    } else {
                                        GlobalStates.mediaModeCount = Math.max(0, GlobalStates.mediaModeCount - 1);
                                    }
                                    LyricsService.mediaModeOpenCount = Math.max(0, LyricsService.mediaModeOpenCount - 1);
                                }

                                StyledToolTip {
                                    text: Translation.tr("Exit Fullscreen Media Mode")
                                }
                            }
                        }
                    }

                    // 2. Main Responsive 2-Column Split Body
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 24

                        // Left Column (~44%): Hero Cover Art & Player Control Card
                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.preferredWidth: root.showLyricsPanel ? parent.width * 0.44 : parent.width

                            Rectangle {
                                anchors.fill: parent
                                radius: Appearance.rounding.verylarge
                                color: ColorUtils.transparentize(Appearance.colors.colLayer1Base, 0.35)

                                MediaModeCoverArt {
                                    anchors.fill: parent
                                    showLoadingIndicator: !root.downloaded
                                    accentColor: root.dynamicAccentColor
                                    accentContainerColor: root.dynamicAccentContainer
                                    onAccentContainerColor: root.dynamicOnAccentContainer
                                }
                            }
                        }

                        // Right Column (~56%): Synchronized Lyrics Studio Panel
                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.preferredWidth: parent.width * 0.56
                            visible: root.showLyricsPanel

                            Rectangle {
                                id: lyricsContainer
                                anchors.fill: parent
                                radius: Appearance.rounding.verylarge
                                color: ColorUtils.transparentize(Appearance.colors.colLayer1Base, 0.35)

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
                                                    if (lyricsItem.hasSyncedLines) return Translation.tr("Synced LRC");
                                                    if (LyricsService.plainLyrics && LyricsService.plainLyrics.trim().length > 0) {
                                                        const p = Config.options.lyricsService.lyricsProvider;
                                                        if (p === "ytmusic") return Translation.tr("YouTube Music");
                                                        if (p === "genius") return Translation.tr("Genius");
                                                        if (p === "lrclib") return Translation.tr("LRCLib Plain");
                                                        return Translation.tr("Plain Text");
                                                    }
                                                    return Translation.tr("Searching...");
                                                }
                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                font.weight: Font.Medium
                                                color: root.dynamicOnAccentContainer
                                            }
                                        }

                                        Item { Layout.fillWidth: true }

                                        // Provider Selector Buttons
                                        Row {
                                            spacing: 4

                                            Repeater {
                                                model: [
                                                    { key: "auto",    icon: "auto_awesome", tip: Translation.tr("Auto (LRC → YTMusic → Genius)") },
                                                    { key: "lrclib",  icon: "timer",        tip: Translation.tr("LRCLib synced/plain") },
                                                    { key: "ytmusic", icon: "smart_display", tip: Translation.tr("YouTube Music") },
                                                    { key: "genius",  icon: "music_note",   tip: Translation.tr("Genius (plain)") }
                                                ]

                                                delegate: RippleButton {
                                                    required property var modelData
                                                    implicitWidth: 28
                                                    implicitHeight: 28
                                                    buttonRadius: Appearance.rounding.full
                                                    readonly property bool isActive: Config.options.lyricsService.lyricsProvider === modelData.key
                                                    readonly property string tipText: modelData.tip
                                                    colBackground: isActive
                                                        ? ColorUtils.transparentize(root.dynamicAccentColor, 0.25)
                                                        : ColorUtils.transparentize(Appearance.colors.colLayer2, 0.5)
                                                    colBackgroundHover: isActive
                                                        ? ColorUtils.transparentize(root.dynamicAccentColor, 0.15)
                                                        : Appearance.colors.colLayer2Hover
                                                    colBackgroundActive: Appearance.colors.colLayer2Active

                                                    MaterialSymbol {
                                                        anchors.centerIn: parent
                                                        iconSize: 14
                                                        color: parent.isActive
                                                            ? root.dynamicAccentColor
                                                            : Appearance.colors.colOnLayer2
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
                                            StyledToolTip { text: Translation.tr("Decrease Lyrics Size") }
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
                                            StyledToolTip { text: Translation.tr("Increase Lyrics Size") }
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
                                            StyledToolTip { text: Translation.tr("Reload Lyrics") }
                                        }
                                    }

                                    // Lyrics Content Area
                                    Item {
                                        id: lyricsItem
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true

                                        readonly property bool providerAllowsSynced: Config.options.lyricsService.lyricsProvider === "auto" || Config.options.lyricsService.lyricsProvider === "lrclib"
                                        readonly property bool hasSyncedLines: LyricsService.syncedLines.length > 0 && !root.forcePlainLyrics && providerAllowsSynced
                                        readonly property bool geniusEnabled: Config.options.lyricsService.enableGenius
                                        readonly property bool lrclibEnabled: Config.options.lyricsService.enableLrclib
                                        readonly property bool ytmusicEnabled: Config.options.lyricsService.enableYtmusic

                                        Component.onCompleted: {
                                            if (!geniusEnabled && !lrclibEnabled && !ytmusicEnabled) return;
                                            LyricsService.initiliazeLyrics();
                                        }

                                        FadeLoader {
                                            shown: !lyricsItem.hasSyncedLines
                                            anchors.fill: parent
                                            sourceComponent: LyricsFlickable {
                                                anchors.fill: parent
                                                player: root.player
                                                fontPixelSize: Appearance.font.pixelSize.hugeass * 1.2 * root.lyricsScaleMultiplier
                                            }
                                        }

                                        FadeLoader {
                                            shown: lyricsItem.hasSyncedLines
                                            anchors.fill: parent
                                            sourceComponent: LyricsSyllable {
                                                anchors.fill: parent
                                                largeFontSize: Appearance.font.pixelSize.hugeass * 1.8 * root.lyricsScaleMultiplier
                                                activeColor: root.dynamicAccentColor
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
