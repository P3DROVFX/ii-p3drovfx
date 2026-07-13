import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.utils
import qs.services
import qs
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Qt5Compat.GraphicalEffects

Item {
    id: root

    Layout.fillHeight: true

    property bool vertical: false

    readonly property MprisPlayer activePlayer: MprisController.activePlayer
    readonly property string cleanedTitle: StringUtils.cleanMusicTitle(activePlayer?.trackTitle) || Translation.tr("No media")
    readonly property string trackArtist: activePlayer?.trackArtist ?? ""
    readonly property bool hasTrack: (activePlayer?.trackTitle ?? "").length > 0
    readonly property bool playing: activePlayer ? activePlayer.playbackState === MprisPlaybackState.Playing : false

    property int customSize: Config.options.bar.mediaPlayer.customSize
    property int lyricsCustomSize: Config.options.bar.mediaPlayer.lyrics.customSize
    property bool useFixedSize: Config.options.bar.mediaPlayer.useFixedSize
    readonly property bool lyricsEnabled: Config.options.bar.mediaPlayer.lyrics.enable
    readonly property bool useGradientMask: Config.options.bar.mediaPlayer.lyrics.useGradientMask
    readonly property string lyricsStyle: Config.options.bar.mediaPlayer.lyrics.style
    readonly property bool artworkEnabled: Config.options.bar.mediaPlayer.artwork.enable

    readonly property int artSize: Appearance.sizes.baseBarHeight - 8
    readonly property int barWidth: Math.max(4, Math.min(8, artSize / 5))
    readonly property int visualizerWidth: 4 * barWidth + 3 * 1
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
            : (calculatedPillWidth + (artworkEnabled ? artSize + spacing : 0) + (hasTrack ? spacing + visualizerWidth : 0))
    implicitHeight: Appearance.sizes.baseBarHeight

    Behavior on implicitWidth {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(root)
    }

    Component.onCompleted: {
        LyricsService.initiliazeLyrics();
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

        let norm = Math.min(1.0, Math.max(0.0, val));
        let maxH = artSize - 10;
        return minH + norm * (maxH - minH);
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

    RowLayout {
        anchors.fill: parent
        spacing: root.spacing

        // Left Side: Album Art (12-sided Material Shape)
        Item {
            id: compactArtContainer
            visible: root.artworkEnabled
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: root.artSize
            Layout.preferredHeight: root.artSize

            MaterialShape {
                id: compactCookieMask
                anchors.fill: parent
                shapeString: "Cookie9Sided"
                color: Appearance.colors.colSurfaceContainerHighest
                visible: false
            }

            Item {
                anchors.fill: parent
                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: compactCookieMask
                }

                Image {
                    anchors.fill: parent
                    source: root.artSource
                    fillMode: Image.PreserveAspectCrop
                    visible: root.artSource !== ""
                    cache: false
                    antialiasing: true
                    sourceSize.width: root.artSize
                    sourceSize.height: root.artSize
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "music_note"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnSurfaceVariant
                    visible: root.artSource === ""
                }
            }
        }

        // Center Side: Rounded Rectangle (Pill) containing metadata or lyrics
        Rectangle {
            id: compactTextContainer
            Layout.fillWidth: true
            Layout.preferredHeight: root.artSize
            Layout.alignment: Qt.AlignVCenter
            color: Appearance.colors.colSurfaceContainerHighest
            radius: Appearance.rounding.verysmall
            clip: true

            readonly property bool hasLyrics: root.lyricsEnabled && LyricsService.hasSyncedLines

            // Synced lyrics view (1 line or 3 lines with edge fade)
            Loader {
                id: compactLyricsLoader
                anchors.fill: parent
                anchors.margins: 4
                active: compactTextContainer.hasLyrics
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

            // Standard metadata display (Song + Artist in two lines)
            ColumnLayout {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 0
                visible: !compactLyricsLoader.visible

                StyledText {
                    id: titleText
                    Layout.fillWidth: true
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.DemiBold
                    text: root.cleanedTitle
                    maximumLineCount: 1
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignLeft
                    color: Appearance.colors.colOnSurface
                }

                StyledText {
                    id: artistText
                    Layout.fillWidth: true
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                    text: root.trackArtist
                    maximumLineCount: 1
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignLeft
                }
            }
        }

        // Right Side: Cava Visualizer (4 bars)
        Item {
            id: compactVisualizerContainer
            visible: root.hasTrack
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: root.visualizerWidth
            Layout.preferredHeight: root.artSize

            Row {
                id: compactVisualizerRow
                anchors.centerIn: parent
                height: parent.height
                spacing: 1

                Repeater {
                    model: 4
                    Rectangle {
                        required property int index
                        anchors.verticalCenter: parent.verticalCenter
                        width: root.barWidth
                        height: root.getBarHeight(index)
                        radius: root.barWidth / 2
                        color: Appearance.colors.colPrimary

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
