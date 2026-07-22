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

    // Mode state options
    property int visualizerMode: 1 // 0: Off, 1: Wave, 2: Bars, 3: Radial
    property real lyricsScaleMultiplier: 1.0
    property bool forcePlainLyrics: false

    Component.onCompleted: {
        Persistent.states.background.mediaMode.userScrollOffset = 0;
        GlobalStates.mediaModeCount++;
    }
    Component.onDestruction: GlobalStates.mediaModeCount--;

    onTrackTitleChanged: Persistent.states.background.mediaMode.userScrollOffset = 0;

    property bool canChangeColor: true
    property string geniusLyricsString: LyricsService.plainLyrics

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
            if (!Config.options.background.mediaMode.changeShellColor)
                return;
            LyricsService.changeShellColor(colorQuantizer.colors[0]);
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
                        color: Appearance.colors.colPrimary
                        points: [120, 340, 560, 280, 490, 780, 320, 640, 450, 210, 530, 380, 620, 290, 410, 150]
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
                        color: Appearance.colors.colPrimary
                        points: [200, 450, 300, 600, 500, 750, 400, 300, 550, 650, 350, 480]
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
                                    colBackground: isActive ? Appearance.colors.colPrimary : ColorUtils.transparentize(Appearance.colors.colLayer2, 0.4)
                                    colBackgroundHover: isActive ? Appearance.colors.colPrimaryHover : Appearance.colors.colLayer2Hover
                                    colBackgroundActive: isActive ? Appearance.colors.colPrimaryActive : Appearance.colors.colLayer2Active

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
                                    color: root.visualizerMode > 0 ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                                    text: {
                                        if (root.visualizerMode === 1) return "waves";
                                        if (root.visualizerMode === 2) return "bar_chart";
                                        if (root.visualizerMode === 3) return "blur_circular";
                                        return "equalizer";
                                    }
                                }

                                onClicked: {
                                    root.visualizerMode = (root.visualizerMode + 1) % 4;
                                }

                                StyledToolTip { text: Translation.tr("Cycle Visualizer Mode") }
                            }

                            // Dynamic Color Sync Toggle
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
                                    color: Config.options.background.mediaMode.changeShellColor ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                                    text: "palette"
                                }

                                onClicked: {
                                    Config.options.background.mediaMode.changeShellColor = !Config.options.background.mediaMode.changeShellColor;
                                }

                                StyledToolTip { text: Translation.tr("Toggle Dynamic Shell Color Sync") }
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
                                    }
                                    LyricsService.mediaModeOpenCount = Math.max(0, LyricsService.mediaModeOpenCount - 1);
                                }

                                StyledToolTip { text: Translation.tr("Exit Fullscreen Media Mode") }
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
                            Layout.preferredWidth: parent.width * 0.44

                            Rectangle {
                                anchors.fill: parent
                                radius: Appearance.rounding.verylarge
                                color: ColorUtils.transparentize(Appearance.colors.colLayer1Base, 0.35)

                                MediaModeCoverArt {
                                    anchors.fill: parent
                                    showLoadingIndicator: !root.downloaded
                                }
                            }
                        }

                        // Right Column (~56%): Synchronized Lyrics Studio Panel
                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.preferredWidth: parent.width * 0.56

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
                                            color: Appearance.colors.colPrimary
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
                                            color: ColorUtils.transparentize(Appearance.colors.colPrimaryContainer, 0.4)

                                            StyledText {
                                                id: statusText
                                                anchors.centerIn: parent
                                                text: LyricsService.syncedLines.length > 0 ? Translation.tr("Synced LRC") : (LyricsService.plainLyrics ? Translation.tr("Plain Text") : Translation.tr("Searching..."))
                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                font.weight: Font.Medium
                                                color: Appearance.colors.colOnPrimaryContainer
                                            }
                                        }

                                        Item { Layout.fillWidth: true }

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

                                        readonly property bool hasSyncedLines: LyricsService.syncedLines.length > 0 && !root.forcePlainLyrics
                                        readonly property bool geniusEnabled: Config.options.lyricsService.enableGenius
                                        readonly property bool lrclibEnabled: Config.options.lyricsService.enableLrclib

                                        Component.onCompleted: {
                                            if (!geniusEnabled && !lrclibEnabled) return;
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
                                                activeColor: Appearance.colors.colPrimary
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
