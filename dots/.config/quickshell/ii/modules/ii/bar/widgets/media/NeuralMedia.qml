import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.utils
import qs.modules.common.models
import qs.services
import qs
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Qt5Compat.GraphicalEffects

Item {
    id: root

    Layout.fillHeight: true
    property bool vertical: false
    property bool isMaterial: true

    readonly property MprisPlayer activePlayer: MprisController.activePlayer
    readonly property string cleanedTitle: StringUtils.cleanMusicTitle(activePlayer?.trackTitle) || Translation.tr("No media")
    readonly property string trackArtist: activePlayer?.trackArtist ?? ""
    readonly property bool hasTrack: (activePlayer?.trackTitle ?? "").length > 0
    readonly property bool playing: activePlayer ? activePlayer.playbackState === MprisPlaybackState.Playing : false

    property int customSize: Config.options.bar.mediaPlayer.customSize
    property int lyricsCustomSize: Config.options.bar.mediaPlayer.lyrics.customSize
    property bool useFixedSize: Config.options.bar.mediaPlayer.useFixedSize
    readonly property bool lyricsEnabled: Config.options.bar.mediaPlayer.lyrics.enable
    readonly property bool artworkEnabled: Config.options.bar.mediaPlayer.artwork.enable

    readonly property int artSize: Appearance.sizes.baseBarHeight - 8
    readonly property int barWidth: Math.max(4, Math.min(8, artSize / 5))
    readonly property int visualizerWidth: 4 * barWidth + 2 * 3
    readonly property int spacing: 4

    readonly property string artUrl: MprisController.artUrl
    readonly property bool isLocalArt: artUrl.startsWith("file://")
    property string artDownloadLocation: Directories.coverArt
    property string artFileName: Qt.md5(artUrl)
    property string artFilePath: `${artDownloadLocation}/${artFileName}`
    property bool artDownloaded: false
    readonly property string artSource: {
        if (!artUrl) return "";
        if (isLocalArt) return artUrl;
        return artDownloaded ? Qt.resolvedUrl(artFilePath) : artUrl;
    }

    readonly property string localArtFilePath: {
        if (!artUrl || artUrl === "") return "";
        if (isLocalArt) return FileUtils.trimFileProtocol(artUrl);
        return artDownloaded ? artFilePath : "";
    }

    readonly property string resolvedArtPath: localArtFilePath !== "" ? Qt.resolvedUrl(localArtFilePath) : ""

    readonly property bool useDynamicColors: Config.options.media.dynamicAlbumColors && localArtFilePath !== ""

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

    readonly property color artTextColor: useDynamicColors ? blendedColors.colOnSurface : Appearance.colors.colOnSurface
    readonly property color artSubtextColor: useDynamicColors ? blendedColors.colOnSurfaceVariant : Appearance.colors.colOnSurfaceVariant

    TextMetrics {
        id: titleMetrics
        font.family: Appearance.font.family.main
        font.pixelSize: Appearance.font.pixelSize.smaller
        font.weight: Font.DemiBold
        text: cleanedTitle
    }

    TextMetrics {
        id: artistMetrics
        font.family: Appearance.font.family.main
        font.pixelSize: Appearance.font.pixelSize.smallest
        text: trackArtist
    }

    readonly property int textWidth: Math.max(titleMetrics.advanceWidth, artistMetrics.advanceWidth)
    readonly property int calculatedPillWidth: Math.min(textWidth + 24, Config.options.bar.mediaPlayer.maxSize)

    implicitWidth: (lyricsEnabled && LyricsService.hasSyncedLines)
        ? lyricsCustomSize
        : useFixedSize
            ? customSize
            : (calculatedPillWidth + visualizerWidth + 24)
    implicitHeight: Appearance.sizes.baseBarHeight - 8
    height: implicitHeight

    Behavior on implicitWidth {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(root)
    }

    onHasTrackChanged: {
        if (typeof rootItem !== "undefined") {
            rootItem.toggleVisible(hasTrack);
        }
    }

    Component.onCompleted: {
        LyricsService.initiliazeLyrics();
        if (typeof rootItem !== "undefined") {
            rootItem.toggleVisible(hasTrack);
        }
    }

    onArtFilePathChanged: {
        if (!artUrl || artUrl.length === 0) {
            artDownloaded = false;
            return;
        }
        if (isLocalArt) {
            artDownloaded = true;
            return;
        }
        artDownloaded = false;
        artDownloader.command = ["bash", "-c", `[ -f '${artFilePath}' ] || (mkdir -p '${artDownloadLocation}' && curl -4 -sSL '${artUrl}' -o '${artFilePath}.tmp' && mv '${artFilePath}.tmp' '${artFilePath}')`]
        artDownloader.running = true;
    }

    Process {
        id: artDownloader
        running: false
        onExited: {
            artDownloaded = true;
        }
    }

    Timer {
        running: activePlayer?.playbackState == MprisPlaybackState.Playing
        interval: Config.options.resources.updateInterval
        repeat: true
        onTriggered: activePlayer.positionChanged()
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
            return minH;
        let val = 0;
        if (index === 0) val = bar0Val;
        else if (index === 1) val = bar1Val;
        else if (index === 2) val = bar2Val;
        else if (index === 3) val = bar3Val;

        let norm = Math.min(1.0, Math.max(0.0, val * 2.0));
        let maxH = artSize - 10;
        return minH + norm * (maxH - minH);
    }

    function getBarAmplitude(index) {
        if (!root.playing) return 0.0;
        let val = 0;
        if (index === 0) val = bar0Val;
        else if (index === 1) val = bar1Val;
        else if (index === 2) val = bar2Val;
        else if (index === 3) val = bar3Val;
        return Math.min(1.0, Math.max(0.0, val * 2.0));
    }

    Process {
        id: cavaProc
        running: root.playing
        command: ["cava", "-p", `${FileUtils.trimFileProtocol(Directories.scriptPath)}/cava/raw_output_config.txt`]
        stdout: SplitParser {
            onRead: data => {
                let points = data.split(";").map(p => parseFloat(p.trim())).filter(p => !isNaN(p));
                root.visualizerPoints = points;
            }
        }
    }

    MouseArea {
        id: mediaMouseArea
        anchors.fill: parent
        hoverEnabled: !Config.options.bar.tooltips.clickToShow
        acceptedButtons: Qt.MiddleButton | Qt.BackButton | Qt.ForwardButton | Qt.RightButton | Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onEntered: {
            GlobalStates.setMediaWidgetHovered(true);
            if (hoverEnabled) {
                var globalPos = root.mapToItem(null, 0, 0);
                GlobalStates.mediaPopupRect = Qt.rect(globalPos.x, globalPos.y, root.width, root.height);
                GlobalStates.mediaControlsOpen = true;
            }
        }
        onExited: {
            GlobalStates.setMediaWidgetHovered(false);
        }
        onPressed: event => {
            if (event.button === Qt.MiddleButton) {
                activePlayer.togglePlaying();
            } else if (event.button === Qt.BackButton) {
                activePlayer.previous();
            } else if (event.button === Qt.ForwardButton || event.button === Qt.RightButton) {
                activePlayer.next();
            } else if (event.button === Qt.LeftButton) {
                if (!hoverEnabled) {
                    var globalPos = root.mapToItem(null, 0, 0);
                    GlobalStates.mediaPopupRect = Qt.rect(globalPos.x, globalPos.y, root.width, root.height);
                    GlobalStates.mediaControlsOpen = !GlobalStates.mediaControlsOpen;
                }
            }
        }
    }

    // ── CONTRACTED LAYOUT (album-art full background, matching FloatingNotchMedia) ──

    // Rounded clip mask
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

    // Vignette mask (horizontal + vertical gradients combined)
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

    // Album art layers (background blurred + sharp foreground with vignette)
    Item {
        anchors.fill: parent

        // Current art (visible when no transition in progress)
        Item {
            anchors.fill: parent
            visible: root.artSource !== ""

            Image {
                anchors.fill: parent
                source: root.artSource
                fillMode: Image.PreserveAspectCrop
                smooth: true
                asynchronous: true
                cache: false
                sourceSize.width: root.artSize * 2
                sourceSize.height: root.artSize * 2
                layer.enabled: true
                layer.effect: MultiEffect {
                    blurEnabled: true
                    blurMax: 128
                    blur: root.playing ? 50 / 128 : 90 / 128

                    Behavior on blur {
                        NumberAnimation {
                            duration: 500
                            easing.type: Easing.OutCubic
                        }
                    }
                }
            }

            Item {
                anchors.fill: parent
                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: contractedVignetteMask
                }

                Image {
                    anchors.fill: parent
                    source: root.artSource
                    fillMode: Image.PreserveAspectCrop
                    smooth: true
                    asynchronous: true
                    cache: false
                    sourceSize.width: root.artSize * 2
                    sourceSize.height: root.artSize * 2
                }
            }
        }
    }

    // Fallback gradient when no art
    Rectangle {
        anchors.fill: parent
        visible: root.artSource === ""
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
        visible: root.artSource === ""
        text: "music_note"
        iconSize: Appearance.font.pixelSize.large
        color: Appearance.colors.colOnSurface
        opacity: 0.5
    }

    // ── Radial gradient dimming overlay ──
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

    // ── Content row ──
    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        spacing: 8

        // Left: metadata or lyrics
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // Synced lyrics view
            Loader {
                id: compactLyricsLoader
                anchors.fill: parent
                anchors.margins: 4
                active: root.lyricsEnabled && LyricsService.hasSyncedLines
                visible: active
                sourceComponent: LyricScroller {
                    id: lyricScroller
                    anchors.fill: parent
                    textAlign: "left"
                    rowHeight: 16
                    halfVisibleLines: 1
                    useGradientMask: true
                    defaultLyricsSize: Appearance.font.pixelSize.smallest
                }
            }

            // Standard metadata display
            ColumnLayout {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1
                visible: !compactLyricsLoader.visible

                StyledText {
                    Layout.fillWidth: true
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.Black
                    font.styleName: "Rounded"
                    font.hintingPreference: Font.PreferNoHinting
                    color: root.artTextColor
                    text: root.cleanedTitle
                    maximumLineCount: 1
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignLeft
                    verticalAlignment: Text.AlignVCenter
                }

                StyledText {
                    Layout.fillWidth: true
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: root.artSubtextColor
                    text: root.trackArtist
                    maximumLineCount: 1
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignLeft
                }
            }
        }

        // Right: visualizer bars
        Item {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: root.visualizerWidth
            implicitHeight: root.artSize

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
                        maxHeight: root.artSize - 10
                        minHeight: root.barWidth
                        amplitude: root.getBarAmplitude(index)
                        bgAmplitude: root.getBarAmplitude((index + 1) % 4)
                        color: root.useDynamicColors ? root.blendedColors.colPrimary : root.artTextColor
                        fgColor: root.useDynamicColors ? root.blendedColors.colTertiary : Appearance.colors.colTertiary
                        glowColor: root.useDynamicColors ? root.blendedColors.colOnPrimary : "#FFFFFF"
                        playing: root.playing
                    }
                }
            }
        }
    }
}
