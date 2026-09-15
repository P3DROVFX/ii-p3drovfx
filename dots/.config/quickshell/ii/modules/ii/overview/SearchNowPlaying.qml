pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Services.Mpris

import qs
import qs.services
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.widgets
import qs.modules.common.functions

Item {
    id: root

    property var entry
    property int listIndex: 0
    property int listCount: ListView.view ? ListView.view.count : 1
    property int listCurrentIndex: ListView.view ? ListView.view.currentIndex : -1
    property bool isFirst: false
    property bool isLast: false
    property int horizontalMargin: Appearance.sizes.elevationMargin

    signal resultExecuted(string feedbackText)

    readonly property bool isSelected: listIndex >= 0 && listIndex === listCurrentIndex
    readonly property bool supportsHorizontalNavigation: true

    // Data from entry or MprisController
    readonly property string trackTitle: StringUtils.cleanMusicTitle(entry?.trackTitle || MprisController.activePlayer?.trackTitle) || Translation.tr("Nothing playing")
    readonly property string rawArtist: entry?.trackArtist || MprisController.activePlayer?.trackArtist || Translation.tr("Unknown Artist")
    readonly property string playerIdentity: entry?.playerIdentity || MprisController.activePlayer?.identity || ""
    readonly property bool isPlaying: (entry && entry.isPlaying !== undefined) ? entry.isPlaying : MprisController.isPlaying

    // Cover Art Downloader with gate
    readonly property string artUrl: entry?.trackArtUrl || MprisController.artUrl || ""
    readonly property bool isLocalArt: artUrl.startsWith("file://")
    property string artDownloadLocation: Directories.coverArt
    property string artFileName: Qt.md5(artUrl)
    property string artFilePath: `${artDownloadLocation}/${artFileName}`
    property bool artDownloaded: false

    readonly property string artSource: {
        if (!artUrl || artUrl.length === 0)
            return "";
        if (isLocalArt)
            return artUrl;
        return artDownloaded ? Qt.resolvedUrl(artFilePath) : "";
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
        artDownloader.targetFile = artUrl;
        artDownloader.artFilePath = artFilePath;
        artDownloader.artTempPath = artFilePath + ".tmp";
        artDownloaded = false;
        artDownloader.running = true;
    }

    Process {
        id: artDownloader
        property string targetFile: root.artUrl
        property string artFilePath: root.artFilePath
        property string artTempPath: root.artFilePath + ".tmp"
        command: ["bash", "-c", `[ -f '${artFilePath}' ] || (curl -4 -sSL '${targetFile}' -o '${artTempPath}' && mv '${artTempPath}' '${artFilePath}')`]
        onExited: {
            artDownloaded = true;
        }
    }

    property real artVignetteBlur: root.isPlaying ? 50 : 90

    Behavior on artVignetteBlur {
        NumberAnimation {
            duration: 500
            easing.type: Easing.OutCubic
        }
    }

    readonly property bool useDynamicColors: (Config.options.media?.dynamicAlbumColors ?? true) && root.artSource !== ""

    ColorQuantizer {
        id: colorQuantizer
        source: root.artSource
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

    readonly property color artTextColor: Appearance.colors.colOnSurface
    readonly property color artSubtextColor: Appearance.colors.colOnSurfaceVariant

    function activate(): bool {
        root.clicked();
        return true;
    }

    function navigateLeft(): bool {
        MprisController.previous();
        return true;
    }

    function navigateRight(): bool {
        MprisController.next();
        return true;
    }

    function clicked() {
        if (typeof root.entry?.execute === "function") {
            root.entry.execute();
            root.resultExecuted(String(root.entry?.feedbackText ?? ""));
        } else {
            MprisController.togglePlaying();
        }
    }

    implicitHeight: 68

    Rectangle {
        id: mainBg
        anchors.fill: parent
        color: Appearance.colors.colLayer0
        radius: Appearance.rounding.large
        clip: true

        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: mainBg.width
                height: mainBg.height
                radius: mainBg.radius
            }
        }

        // Album Art Blurred / Vignette Backgrounds
        Item {
            anchors.fill: parent

            Image {
                id: artBlurredUnderlay
                anchors.fill: parent
                source: root.artSource
                fillMode: Image.PreserveAspectCrop
                visible: root.artSource !== ""
                layer.enabled: root.artVignetteBlur > 0
                layer.effect: MultiEffect {
                    blurEnabled: root.artVignetteBlur > 0
                    blurMax: 128
                    blur: root.artVignetteBlur / 128
                }
            }

            Item {
                id: vignetteMask
                anchors.fill: parent
                visible: true

                Rectangle {
                    id: hMask
                    anchors.fill: parent
                    color: "transparent"
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0) }
                        GradientStop { position: 0.08; color: Qt.rgba(0, 0, 0, 0) }
                        GradientStop { position: 0.2; color: Qt.rgba(0, 0, 0, 0.3) }
                        GradientStop { position: 0.35; color: Qt.rgba(0, 0, 0, 0.7) }
                        GradientStop { position: 0.45; color: Qt.rgba(0, 0, 0, 1) }
                        GradientStop { position: 0.55; color: Qt.rgba(0, 0, 0, 1) }
                        GradientStop { position: 0.65; color: Qt.rgba(0, 0, 0, 0.7) }
                        GradientStop { position: 0.8; color: Qt.rgba(0, 0, 0, 0.3) }
                        GradientStop { position: 0.92; color: Qt.rgba(0, 0, 0, 0) }
                        GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0) }
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    color: "transparent"
                    gradient: Gradient {
                        orientation: Gradient.Vertical
                        GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0) }
                        GradientStop { position: 0.15; color: Qt.rgba(0, 0, 0, 0.3) }
                        GradientStop { position: 0.35; color: Qt.rgba(0, 0, 0, 0.7) }
                        GradientStop { position: 0.5; color: Qt.rgba(0, 0, 0, 1) }
                        GradientStop { position: 0.65; color: Qt.rgba(0, 0, 0, 0.7) }
                        GradientStop { position: 0.85; color: Qt.rgba(0, 0, 0, 0.3) }
                        GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0) }
                    }
                    layer.enabled: true
                    layer.effect: OpacityMask {
                        maskSource: hMask
                    }
                }
            }

            Item {
                anchors.fill: parent
                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: vignetteMask
                }

                Image {
                    id: artExpanded
                    anchors.fill: parent
                    source: root.artSource
                    fillMode: Image.PreserveAspectCrop
                    opacity: 0.85
                    visible: root.artSource !== ""
                }
            }
        }

        // Dimming overlays
        Item {
            anchors.fill: parent
            opacity: root.isPlaying ? 0.55 : 0.75

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

            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.3)
                opacity: root.isPlaying ? 0.0 : 0.5

                Behavior on opacity {
                    NumberAnimation {
                        duration: 500
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }

        // Content Layout (Centered single row with Title/Artist on left & Play/Pause on right)
        RowLayout {
            id: contentRow
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            anchors.topMargin: 10
            anchors.bottomMargin: 10
            spacing: 16

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 2

                StyledText {
                    Layout.fillWidth: true
                    font.family: Appearance.font.family.main
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.weight: Font.Black
                    font.styleName: "Rounded"
                    color: root.artTextColor
                    text: root.trackTitle
                    maximumLineCount: 1
                    wrapMode: Text.WordWrap
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    font.family: Appearance.font.family.main
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: root.artSubtextColor
                    text: root.rawArtist
                    maximumLineCount: 1
                    elide: Text.ElideRight
                }
            }

            RippleButton {
                id: playBtn
                implicitWidth: 44
                implicitHeight: 44
                buttonRadius: root.isPlaying ? 14 : 22
                Behavior on buttonRadius {
                    NumberAnimation {
                        duration: 250
                        easing.type: Easing.OutCubic
                    }
                }
                colBackground: root.useDynamicColors ? root.blendedColors.colPrimaryContainer : Appearance.colors.colPrimaryContainer
                colBackgroundHover: root.useDynamicColors ? root.blendedColors.colPrimaryContainerHover : Appearance.colors.colPrimaryContainerHover
                colRipple: root.useDynamicColors ? root.blendedColors.colPrimaryContainerActive : Appearance.colors.colPrimaryContainerActive
                Layout.alignment: Qt.AlignVCenter

                onClicked: {
                    MprisController.togglePlaying();
                }

                contentItem: Item {
                    implicitWidth: 44
                    implicitHeight: 44
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: root.isPlaying ? "pause" : "play_arrow"
                        iconSize: Appearance.font.pixelSize.huge
                        color: root.useDynamicColors ? root.blendedColors.colOnPrimaryContainer : Appearance.colors.colOnPrimaryContainer
                        fill: 1
                    }
                }
            }
        }

        // Global MouseArea for clicking anywhere on the card to focus/raise or toggle
        MouseArea {
            anchors.fill: parent
            z: -1
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (MprisController.activePlayer?.canRaise) {
                    MprisController.activePlayer.raise();
                } else {
                    root.clicked();
                }
            }
        }
    }
}
