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
import qs.modules.ii.background.widgets

AbstractBackgroundWidget {
    id: root

    configEntryName: "media_cd"

    implicitWidth: 240
    implicitHeight: 240

    readonly property color cardBgColor: WidgetColorScheme.cardBgColor
    readonly property color textColorOnBg: WidgetColorScheme.textColorOnBg
    readonly property color subtextColorOnBg: WidgetColorScheme.subtextColorOnBg
    readonly property color accentColor: WidgetColorScheme.accentColor

    readonly property MprisPlayer player: MprisController.activePlayer
    readonly property bool isPlaying: MprisController.isPlaying
    readonly property var activeTrack: MprisController.activeTrack
    readonly property string rawArtUrl: MprisController.artUrl

    readonly property string songTitle: activeTrack ? activeTrack.title : Translation.tr("Wonderwall")
    readonly property string artistName: activeTrack ? activeTrack.artist : Translation.tr("Oasis")

    readonly property real position: player ? (player.position ?? 0) : 163
    readonly property real length: player ? (player.length ?? 0) : 258

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

    // Direct resolution of artSource (local vs http/https)
    readonly property bool isLocalArt: root.rawArtUrl.startsWith("file://") || root.rawArtUrl.startsWith("/")
    property string artDownloadLocation: Directories.coverArt
    property string artFileName: Qt.md5(root.rawArtUrl)
    property string artFilePath: `${artDownloadLocation}/${artFileName}`
    property bool downloaded: false

    readonly property string effectiveArtSource: {
        if (!root.rawArtUrl || root.rawArtUrl === "") return "";
        if (root.isLocalArt) return FileUtils.trimFileProtocol(root.rawArtUrl);
        return root.downloaded ? root.artFilePath : "";
    }

    readonly property string resolvedArtPath: root.effectiveArtSource !== "" ? Qt.resolvedUrl(root.effectiveArtSource) : ""

    onRawArtUrlChanged: {
        if (rawArtUrl && rawArtUrl !== "" && !isLocalArt) {
            coverArtDownloader.targetFile = rawArtUrl;
            coverArtDownloader.artFilePath = artFilePath;
            coverArtDownloader.artTempPath = artFilePath + ".tmp";
            downloaded = false;
            coverArtDownloader.running = true;
        }
    }

    Process {
        id: coverArtDownloader
        property string targetFile: root.rawArtUrl
        property string artFilePath: root.artFilePath
        property string artTempPath: root.artFilePath + ".tmp"
        command: ["bash", "-c", `[ -f ${artFilePath} ] || (curl -4 -sSL '${targetFile}' -o '${artTempPath}' && mv '${artTempPath}' '${artFilePath}')`]
        onExited: (exitCode, exitStatus) => {
            root.downloaded = true;
        }
    }

    StyledRectangularShadow {
        id: bgShadow
        target: bgRect
        visible: Config.options.background.widgets.enableShadows ?? true
    }

    // Main Card background
    Rectangle {
        id: bgRect
        anchors.fill: parent
        anchors.margins: 10
        color: root.cardBgColor
        radius: Appearance.rounding.windowRounding
        clip: true

        layer.enabled: Config.options.background.widgets.enableInnerShadow ?? true
        layer.effect: InnerShadow {
            color: Qt.rgba(0, 0, 0, 0.15)
            radius: 8.0
            samples: 16
            horizontalOffset: 0
            verticalOffset: 1
            spread: 0.0
        }

        Item {
            anchors.fill: parent

            // 1. Album Art Circle Container (Anchored to top, height: 100)
            Item {
                id: topCircleContainer
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                width: 176
                height: 100
                clip: true

                // Drop shadow for album art
                DropShadow {
                    anchors.fill: circleMaskArea
                    source: circleMaskArea
                    radius: 20
                    samples: 24
                    color: Qt.rgba(0, 0, 0, 0.18)
                    verticalOffset: 4
                    horizontalOffset: 0
                }

                Item {
                    id: circleMaskArea
                    width: 176
                    height: 176
                    anchors.top: parent.top
                    anchors.topMargin: -86 // Exposes bottom 100px arc inside topCircleContainer
                    anchors.horizontalCenter: parent.horizontalCenter

                    Image {
                        id: coverArtImage
                        anchors.fill: parent
                        source: root.resolvedArtPath !== "" ? root.resolvedArtPath : "file://" + Directories.scriptPath + "/../assets/images/default_cover.png"
                        fillMode: Image.PreserveAspectCrop
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
                }
            }

            // 2. Bottom Content Layout (Anchored strictly to topCircleContainer.bottom)
            ColumnLayout {
                anchors.top: topCircleContainer.bottom
                anchors.topMargin: 4
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 10
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 3

                // Author Name (Reduced opacity subtext)
                StyledText {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignHCenter
                    text: root.artistName
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.family: Appearance.font.family.title
                    color: root.subtextColorOnBg
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }

                // Song Name
                StyledText {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignHCenter
                    text: root.songTitle
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.family: Appearance.font.family.title
                    font.weight: Font.DemiBold
                    color: root.textColorOnBg
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }

                Item { Layout.preferredHeight: 1 }

                // Line Progress Slider
                Item {
                    id: progressTrack
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: 60
                    implicitHeight: 3

                    Rectangle {
                        anchors.fill: parent
                        color: Qt.rgba(root.subtextColorOnBg.r, root.subtextColorOnBg.g, root.subtextColorOnBg.b, 0.2)
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

                // Time Display: 2:43 / 4:18 (Current time bold, Total time reduced opacity)
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 4

                    StyledText {
                        text: root.formatTime(root.position)
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.Bold
                        color: root.textColorOnBg
                    }

                    StyledText {
                        text: "/"
                        font.pixelSize: Appearance.font.pixelSize.normal
                        color: root.subtextColorOnBg
                    }

                    StyledText {
                        text: root.formatTime(root.length)
                        font.pixelSize: Appearance.font.pixelSize.normal
                        color: root.subtextColorOnBg
                    }
                }
            }
        }
    }
}
