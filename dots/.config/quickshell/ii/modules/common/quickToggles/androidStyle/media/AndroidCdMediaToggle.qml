pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.common.models
import qs.modules.common.quickToggles.androidStyle

/**
 * CD Media quick toggle.
 * Adapted directly from the desktop background's CdMediaWidget.
 *
 * Sized and proportioned for the quick toggle grid (2x2 square tile),
 * featuring a vinyl disc cutout peeking from the top, artist name,
 * song title, progress track, and playback timestamp without any overflow.
 */
AndroidWidgetTileBase {
    id: root

    tooltipText: {
        if (root.songTitle && root.songTitle !== "") {
            var artist = root.artistName ? root.artistName : Translation.tr("Unknown Artist");
            return root.songTitle + " - " + artist;
        }
        return Translation.tr("CD Player");
    }

    readonly property MprisPlayer player: MprisController.activePlayer
    readonly property bool isPlaying: MprisController.isPlaying
    readonly property var activeTrack: MprisController.activeTrack
    readonly property string rawArtUrl: MprisController.artUrl

    readonly property string songTitle: activeTrack?.title || player?.trackTitle || Translation.tr("No media")
    readonly property string artistName: activeTrack?.artist || player?.trackArtist || Translation.tr("Unknown Artist")

    readonly property real position: player ? (player.position ?? 0) : 0
    readonly property real length: player ? (player.length ?? 0) : 0

    readonly property bool useDynamicColors: (Config.options.background.widgets.media_cd.dynamicAlbumColors ?? true) && root.effectiveArtSource !== ""

    ColorQuantizer {
        id: colorQuantizer
        source: root.effectiveArtSource
        depth: 0
        rescaleSize: 1
    }

    readonly property color artDominantColor: {
        if (!root.useDynamicColors) return Appearance.colors.colPrimary;
        let raw = colorQuantizer?.colors[0] ?? Appearance.colors.colPrimary;
        let mixed = ColorUtils.mix(raw, Appearance.colors.colPrimaryContainer, 0.8);
        return mixed || Appearance.m3colors.m3secondaryContainer;
    }

    property QtObject blendedColors: AdaptedMaterialScheme {
        color: root.artDominantColor
    }

    readonly property color cardBgColor: useDynamicColors ? blendedColors.colPrimaryContainer : WidgetColorScheme.cardBgColor
    readonly property color textColorOnBg: useDynamicColors ? blendedColors.colOnPrimaryContainer : WidgetColorScheme.textColorOnBg
    readonly property color subtextColorOnBg: useDynamicColors ? ColorUtils.transparentize(blendedColors.colOnPrimaryContainer, 0.4) : WidgetColorScheme.subtextColorOnBg
    readonly property color accentColor: useDynamicColors ? blendedColors.colPrimary : WidgetColorScheme.accentColor

    function formatTime(seconds) {
        if (isNaN(seconds) || seconds < 0) return "0:00";
        let m = Math.floor(seconds / 60);
        let s = Math.floor(seconds % 60);
        return m + ":" + (s < 10 ? "0" : "") + s;
    }

    Timer {
        running: root.isPlaying
        interval: 1000
        repeat: true
        onTriggered: {
            if (root.player) root.player.positionChanged();
        }
    }

    readonly property bool isLocalArt: root.rawArtUrl.startsWith("file://") || root.rawArtUrl.startsWith("/")
    property string artDownloadLocation: Directories.coverArt
    property string artFileName: (root.rawArtUrl && root.rawArtUrl.length > 0) ? Qt.md5(root.rawArtUrl) : ""
    property string artFilePath: artFileName.length > 0 ? `${artDownloadLocation}/${artFileName}` : ""
    property bool downloaded: false

    readonly property string effectiveArtSource: {
        if (!root.rawArtUrl || root.rawArtUrl === "") return "";
        if (root.isLocalArt) return root.rawArtUrl;
        return root.downloaded ? Qt.resolvedUrl(root.artFilePath) : "";
    }

    function refreshArt() {
        if (!root.rawArtUrl || root.rawArtUrl === "") {
            root.downloaded = false;
            return;
        }
        if (root.isLocalArt) {
            root.downloaded = true;
            return;
        }
        coverArtDownloader.targetFile = root.rawArtUrl;
        coverArtDownloader.artFilePath = root.artFilePath;
        coverArtDownloader.artTempPath = root.artFilePath + ".tmp";
        root.downloaded = false;
        coverArtDownloader.running = true;
    }

    onArtFilePathChanged: root.refreshArt()
    Component.onCompleted: root.refreshArt()

    Process {
        id: coverArtDownloader
        property string targetFile: root.rawArtUrl
        property string artFilePath: root.artFilePath
        property string artTempPath: root.artFilePath + ".tmp"
        command: ["bash", "-c", `[ -f ${artFilePath} ] || (curl -4 -sSL '${targetFile}' -o '${artTempPath}' && mv '${artTempPath}' '${artFilePath}')`]
        onExited: (exitCode, exitStatus) => {
            root.downloaded = exitCode === 0;
        }
    }

    // Disc dimensions scaled proportionally for the tile height
    readonly property real discDiameter: Math.max(50, Math.min(root.surface.width * 0.65, Math.round(root.surface.height * 0.72)))
    readonly property real discViewportHeight: Math.max(26, Math.round(root.surface.height * 0.34))
    readonly property real discTopMargin: -Math.round(root.discDiameter * 0.52)

    Rectangle {
        id: bgRect
        anchors.fill: parent
        color: WidgetColorScheme.tintBackground(root.cardBgColor)
        radius: Appearance.rounding.large
        clip: true

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (root.player) root.player.togglePlaying();
            }
        }

        Item {
            anchors.fill: parent

            // 1. CD Disc Cutout Container (Top)
            Item {
                id: topCircleContainer
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                width: root.discDiameter
                height: root.discViewportHeight
                clip: true

                Item {
                    id: circleMaskArea
                    width: root.discDiameter
                    height: root.discDiameter
                    anchors.top: parent.top
                    anchors.topMargin: root.discTopMargin
                    anchors.horizontalCenter: parent.horizontalCenter

                    // Vinyl spin
                    property real _rotationAngle: 0
                    rotation: _rotationAngle

                    Timer {
                        running: root.isPlaying
                        interval: 16
                        repeat: true
                        onTriggered: circleMaskArea._rotationAngle = (circleMaskArea._rotationAngle + 0.6) % 360
                    }

                    Image {
                        id: coverArtImage
                        anchors.fill: parent
                        source: root.effectiveArtSource
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: false
                        visible: false
                    }

                    Rectangle {
                        id: maskCircle
                        anchors.fill: parent
                        radius: width / 2
                        color: "black"
                        visible: false
                    }

                    OpacityMask {
                        anchors.fill: parent
                        source: coverArtImage
                        maskSource: maskCircle
                    }

                    // Fallback symbol when no artwork
                    MaterialSymbol {
                        anchors.centerIn: parent
                        visible: coverArtImage.status !== Image.Ready || root.effectiveArtSource === ""
                        text: root.player != null ? "album" : "music_off"
                        iconSize: Math.max(16, Math.round(circleMaskArea.width * 0.40))
                        color: root.subtextColorOnBg
                    }

                    // Vinyl border ring
                    Rectangle {
                        anchors.fill: parent
                        color: "transparent"
                        radius: width / 2
                        border.color: Qt.rgba(0, 0, 0, 0.25)
                        border.width: 1
                    }

                    // Center hole
                    Rectangle {
                        anchors.centerIn: parent
                        width: Math.max(6, Math.round(circleMaskArea.width * 0.18))
                        height: width
                        radius: width / 2
                        color: WidgetColorScheme.tintBackground(root.cardBgColor)
                        border.color: root.subtextColorOnBg
                        border.width: 1
                        z: 3
                    }
                }
            }

            // 2. Metadata & Progress layout (Bottom)
            ColumnLayout {
                anchors.top: topCircleContainer.bottom
                anchors.topMargin: 2
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 6
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 2

                // Artist Name
                StyledText {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignHCenter
                    text: root.artistName
                    font.pixelSize: Math.max(9, Math.min(11, Math.round(root.surface.height * 0.09)))
                    font.family: Appearance.font.family.title
                    color: root.subtextColorOnBg
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }

                // Song Title
                StyledText {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignHCenter
                    text: root.songTitle
                    font.pixelSize: Math.max(11, Math.min(14, Math.round(root.surface.height * 0.11)))
                    font.family: Appearance.font.family.title
                    font.weight: Font.DemiBold
                    color: root.textColorOnBg
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }

                Item { Layout.fillHeight: true }

                // Line Progress Indicator
                Item {
                    id: progressTrack
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: Math.max(40, Math.min(100, Math.round(root.surface.width * 0.45)))
                    Layout.preferredHeight: 3

                    Rectangle {
                        anchors.fill: parent
                        color: Qt.rgba(root.subtextColorOnBg.r, root.subtextColorOnBg.g, root.subtextColorOnBg.b, 0.25)
                        radius: 1.5
                    }

                    Rectangle {
                        height: parent.height
                        width: parent.width * (root.length > 0 ? Math.min(1.0, Math.max(0.0, root.position / root.length)) : 0.63)
                        color: root.accentColor
                        radius: 1.5
                    }
                }

                Item { Layout.preferredHeight: 1 }

                // Time Display: M:SS / M:SS
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 4

                    StyledText {
                        text: root.formatTime(root.position)
                        font.pixelSize: Math.max(9, Math.min(11, Math.round(root.surface.height * 0.09)))
                        font.weight: Font.Bold
                        color: root.textColorOnBg
                    }

                    StyledText {
                        text: "/"
                        font.pixelSize: Math.max(9, Math.min(11, Math.round(root.surface.height * 0.09)))
                        color: root.subtextColorOnBg
                    }

                    StyledText {
                        text: root.formatTime(root.length)
                        font.pixelSize: Math.max(9, Math.min(11, Math.round(root.surface.height * 0.09)))
                        color: root.subtextColorOnBg
                    }
                }
            }
        }
    }
}
