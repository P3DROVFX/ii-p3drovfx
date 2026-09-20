pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Widgets
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.common.models
import qs.modules.common.quickToggles.androidStyle

/**
 * Expressive Media quick toggle.
 * Adapted directly from the desktop background's ExpressiveMediaWidget.
 *
 * Sized and optimized for the quick toggle grid (4x2 or 4x3 banner),
 * featuring LED dot-matrix track title, rotating vinyl disc album pill,
 * time & artist info, wavy progress bar, and transport buttons with no overflow.
 */
AndroidWidgetTileBase {
    id: root

    tooltipText: {
        if (root.player && root.player.trackTitle) {
            var artist = root.player.trackArtist ? root.player.trackArtist : Translation.tr("Unknown Artist");
            return root.player.trackTitle + " - " + artist;
        }
        return Translation.tr("Media Player");
    }

    property MprisPlayer player: MprisController.activePlayer

    readonly property bool useDynamicColors: (Config.options.background.widgets.media.dynamicAlbumColors ?? false) && root.artSource !== ""

    ColorQuantizer {
        id: colorQuantizer
        source: root.artSource
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

    readonly property color colBg: useDynamicColors ? blendedColors.colPrimaryContainer : WidgetColorScheme.cardBgColor
    readonly property color colAlbumBg: useDynamicColors ? blendedColors.colSecondaryContainer : WidgetColorScheme.innerShapeColor
    readonly property color colControlsBg: useDynamicColors ? blendedColors.colSecondaryContainer : WidgetColorScheme.pillFillColor
    readonly property color colText: useDynamicColors ? blendedColors.colOnSecondaryContainer : WidgetColorScheme.textColorOnBg
    readonly property color colTimeMain: useDynamicColors ? blendedColors.colOnSecondaryContainer : WidgetColorScheme.textColorOnPillFill
    readonly property color colTimeSub: useDynamicColors ? ColorUtils.transparentize(blendedColors.colOnSecondaryContainer, 0.3) : ColorUtils.transparentize(WidgetColorScheme.textColorOnPillFill, 0.3)
    readonly property color colProgressHighlight: useDynamicColors ? blendedColors.colPrimary : WidgetColorScheme.accentColor
    readonly property color colProgressTrack: useDynamicColors ? ColorUtils.transparentize(blendedColors.colOnSecondaryContainer, 0.6) : ColorUtils.transparentize(WidgetColorScheme.textColorOnPillFill, 0.6)
    readonly property color colBtnSecondary: useDynamicColors ? blendedColors.colTertiaryContainer : WidgetColorScheme.pillBgColor
    readonly property color colBtnSecondaryHover: useDynamicColors ? ColorUtils.mix(blendedColors.colTertiaryContainer, blendedColors.colPrimary, 0.15) : ColorUtils.mix(WidgetColorScheme.pillBgColor, WidgetColorScheme.accentColor, 0.15)
    readonly property color colBtnSecondaryActive: useDynamicColors ? ColorUtils.mix(blendedColors.colTertiaryContainer, blendedColors.colPrimary, 0.25) : ColorUtils.mix(WidgetColorScheme.pillBgColor, WidgetColorScheme.accentColor, 0.25)
    readonly property color colBtnPlayBg: useDynamicColors ? blendedColors.colPrimary : WidgetColorScheme.accentColor
    readonly property color colBtnPlayRipple: useDynamicColors ? ColorUtils.mix(blendedColors.colPrimary, blendedColors.colOnPrimary, 0.2) : ColorUtils.mix(WidgetColorScheme.accentColor, WidgetColorScheme.onAccentColor, 0.2)
    readonly property color colBtnPlayIcon: useDynamicColors ? blendedColors.colOnPrimary : WidgetColorScheme.onAccentColor
    readonly property color colBtnIcon: useDynamicColors ? blendedColors.colOnSecondaryContainer : WidgetColorScheme.textColorOnPillTrack
    readonly property color colAlbumBorder: useDynamicColors ? ColorUtils.transparentize(blendedColors.colOnSecondaryContainer, 0.5) : WidgetColorScheme.outlineColor

    readonly property bool rotateAlbumArt: Config.options.background.widgets.media.rotateAlbumArt ?? true
    readonly property bool showTimeInfo: Config.options.background.widgets.media.showTimeInfo ?? true
    readonly property bool showArtist: Config.options.background.widgets.media.showArtist ?? true
    readonly property bool showProgressSlider: Config.options.background.widgets.media.showProgressSlider ?? true

    readonly property string trackTitle: player?.trackTitle || Translation.tr("No media")
    readonly property string trackArtist: player?.trackArtist || Translation.tr("Unknown Artist")
    readonly property string artUrl: MprisController.artUrl
    readonly property bool isLocalArt: artUrl.startsWith("file://")

    property string artDownloadLocation: Directories.coverArt
    property string artFileName: (artUrl && artUrl.length > 0) ? Qt.md5(artUrl) : ""
    property string artFilePath: artFileName.length > 0 ? `${artDownloadLocation}/${artFileName}` : ""
    property bool artDownloaded: false

    readonly property string artSource: {
        if (!artUrl || artUrl.length === 0) return "";
        if (isLocalArt) return artUrl;
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
        command: ["bash", "-c", `[ -f ${artFilePath} ] || (curl -4 -sSL '${targetFile}' -o '${artTempPath}' && mv '${artTempPath}' '${artFilePath}')`]
        onExited: {
            artDownloaded = true;
        }
    }

    FontLoader {
        id: ledFont
        source: Qt.resolvedUrl("../../../../../assets/fonts/LED Dot-Matrix.ttf")
    }

    Timer {
        running: root.player?.playbackState == MprisPlaybackState.Playing
        interval: 500
        repeat: true
        onTriggered: {
            if (root.player) root.player.positionChanged();
        }
    }

    Rectangle {
        id: mainBg
        anchors.fill: parent
        color: WidgetColorScheme.tintBackground(root.colBg)
        radius: Appearance.rounding.large
        border.color: WidgetColorScheme.outlineColor
        border.width: 1
        clip: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 6
            spacing: 3

            // Top: LED Dot-Matrix Track Title
            StyledText {
                Layout.fillWidth: true
                text: root.trackTitle.toUpperCase()
                color: root.colText
                font.family: ledFont.name
                font.pixelSize: Math.max(12, Math.min(18, Math.round(root.surface.height * 0.13)))
                font.weight: Font.Light
                elide: Text.ElideRight
                maximumLineCount: 1
                clip: true
            }

            // Main row: Album pill + Controls panel
            RowLayout {
                id: contentRow
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 6

                // 1. Album Art Vinyl Pill (Square aspect)
                Rectangle {
                    id: albumPill
                    Layout.fillHeight: true
                    Layout.preferredWidth: height
                    Layout.alignment: Qt.AlignVCenter
                    color: WidgetColorScheme.tintBackground(root.colAlbumBg)
                    radius: Appearance.rounding.normal

                    Item {
                        id: albumArtItem
                        anchors.centerIn: parent
                        width: Math.max(26, parent.height - 12)
                        height: width
                        clip: true

                        property real _rotationAngle: 0
                        rotation: _rotationAngle

                        Timer {
                            id: rotationTimer
                            running: (root.player?.isPlaying ?? false) && root.rotateAlbumArt
                            interval: 16
                            repeat: true
                            onTriggered: albumArtItem._rotationAngle = (albumArtItem._rotationAngle + 0.6) % 360
                        }

                        Image {
                            id: albumArtImage
                            anchors.fill: parent
                            anchors.margins: 1
                            source: root.artSource
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: false
                            antialiasing: true
                            sourceSize.width: width
                            sourceSize.height: height

                            layer.enabled: true
                            layer.effect: OpacityMask {
                                maskSource: Rectangle {
                                    width: albumArtImage.width
                                    height: albumArtImage.height
                                    radius: width / 2
                                }
                            }
                        }

                        MaterialSymbol {
                            anchors.centerIn: parent
                            visible: albumArtImage.status !== Image.Ready || root.artSource === ""
                            iconSize: Math.max(16, Math.round(albumArtItem.width * 0.45))
                            text: root.player != null ? "music_note" : "music_off"
                            color: WidgetColorScheme.subtextColorOnBg
                        }

                        // Inset ring border on vinyl
                        Rectangle {
                            anchors.fill: parent
                            color: "transparent"
                            radius: width / 2
                            border.color: root.colAlbumBorder
                            border.width: Math.max(3, Math.round(width * 0.07))
                            z: 2
                        }

                        // Center highlight circle
                        Rectangle {
                            anchors.centerIn: parent
                            width: Math.max(8, Math.round(parent.width * 0.22))
                            height: width
                            radius: width / 2
                            color: WidgetColorScheme.highlightCircleColor
                            z: 3
                        }
                    }
                }

                // 2. Controls Panel
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.alignment: Qt.AlignVCenter
                    color: WidgetColorScheme.tintBackground(root.colControlsBg)
                    radius: Appearance.rounding.normal
                    clip: true

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.topMargin: 3
                        anchors.bottomMargin: 3
                        anchors.leftMargin: 6
                        anchors.rightMargin: 6
                        spacing: 1

                        // Time & Artist Row
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            Layout.alignment: Qt.AlignTop

                            StyledText {
                                visible: root.showTimeInfo
                                text: StringUtils.friendlyTimeForSeconds(MprisController.trackPositionOf(root.player))
                                color: root.colTimeMain
                                font.pixelSize: Math.max(11, Math.min(16, Math.round(root.surface.height * 0.11)))
                                font.weight: Font.Bold
                                Layout.alignment: Qt.AlignVCenter
                            }

                            StyledText {
                                visible: root.showTimeInfo
                                text: "/" + (MprisController.hasTrackLength(root.player)
                                    ? StringUtils.friendlyTimeForSeconds(root.player.length) : "\u2013\u2013:\u2013\u2013")
                                color: root.colTimeSub
                                font.pixelSize: Math.max(9, Math.min(11, Math.round(root.surface.height * 0.08)))
                                font.weight: Font.Regular
                                Layout.alignment: Qt.AlignVCenter
                            }

                            StyledText {
                                visible: root.showArtist
                                text: root.trackArtist
                                color: root.colTimeSub
                                font.pixelSize: Math.max(9, Math.min(11, Math.round(root.surface.height * 0.08)))
                                font.weight: Font.Regular
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                horizontalAlignment: Text.AlignRight
                                Layout.alignment: Qt.AlignVCenter
                            }
                        }

                        // Progress Slider
                        Item {
                            visible: root.showProgressSlider
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignTop
                            Layout.preferredHeight: Math.max(10, Math.min(14, Math.round(root.surface.height * 0.10)))

                            Loader {
                                id: sliderLoader
                                anchors.fill: parent
                                active: root.player?.canSeek ?? false
                                sourceComponent: StyledSlider {
                                    configuration: StyledSlider.Configuration.Wavy
                                    highlightColor: root.colProgressHighlight
                                    trackColor: root.colProgressTrack
                                    handleColor: root.colProgressHighlight
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
                                anchors {
                                    verticalCenter: parent.verticalCenter
                                    left: parent.left
                                    right: parent.right
                                }
                                active: !!root.player && !sliderLoader.active
                                sourceComponent: StyledProgressBar {
                                    wavy: root.player?.isPlaying ?? false
                                    highlightColor: root.colProgressHighlight
                                    trackColor: root.colProgressTrack
                                    value: MprisController.trackProgressOf(root.player)
                                }
                            }
                        }

                        // Elastic spacer between slider and transport controls
                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.minimumHeight: 1
                        }

                        // Transport Buttons Row
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: Math.max(30, Math.min(38, Math.round(root.surface.height * 0.30)))
                            Layout.maximumHeight: Math.max(30, Math.min(38, Math.round(root.surface.height * 0.30)))
                            Layout.fillHeight: false
                            Layout.alignment: Qt.AlignBottom
                            spacing: 4

                            RippleButton {
                                Layout.fillWidth: true
                                Layout.preferredWidth: 0
                                Layout.preferredHeight: parent.height
                                Layout.maximumHeight: parent.height
                                Layout.fillHeight: false
                                Layout.alignment: Qt.AlignVCenter
                                colBackground: root.colBtnSecondary
                                colBackgroundHover: root.colBtnSecondaryHover
                                colRipple: root.colBtnSecondaryActive
                                buttonRadius: Appearance.rounding.small
                                contentItem: MaterialSymbol {
                                    text: "skip_previous"
                                    color: root.colBtnIcon
                                    fill: 1
                                    iconSize: Math.max(16, Math.min(22, Math.round(root.surface.height * 0.16)))
                                    horizontalAlignment: Text.AlignHCenter
                                }
                                onClicked: root.player?.previous()
                            }

                            RippleButton {
                                implicitWidth: Math.max(40, Math.min(52, Math.round(root.surface.height * 0.34)))
                                implicitHeight: parent.height
                                Layout.preferredHeight: parent.height
                                Layout.maximumHeight: parent.height
                                Layout.fillHeight: false
                                colBackground: root.colBtnPlayBg
                                colRipple: root.colBtnPlayRipple
                                buttonRadius: root.player?.isPlaying ? Appearance.rounding.small : Appearance.rounding.full

                                Behavior on buttonRadius {
                                    NumberAnimation { duration: 250; easing.type: Easing.OutQuint }
                                }

                                contentItem: MaterialSymbol {
                                    text: root.player?.isPlaying ? "pause" : "play_arrow"
                                    color: root.colBtnPlayIcon
                                    fill: 1
                                    iconSize: Math.max(18, Math.min(24, Math.round(root.surface.height * 0.19)))
                                    horizontalAlignment: Text.AlignHCenter
                                }
                                onClicked: root.player?.togglePlaying()
                            }

                            RippleButton {
                                Layout.fillWidth: true
                                Layout.preferredWidth: 0
                                Layout.preferredHeight: parent.height
                                Layout.maximumHeight: parent.height
                                Layout.fillHeight: false
                                Layout.alignment: Qt.AlignVCenter
                                colBackground: root.colBtnSecondary
                                colBackgroundHover: root.colBtnSecondaryHover
                                colRipple: root.colBtnSecondaryActive
                                buttonRadius: Appearance.rounding.small
                                contentItem: MaterialSymbol {
                                    text: "skip_next"
                                    color: root.colBtnIcon
                                    fill: 1
                                    iconSize: Math.max(16, Math.min(22, Math.round(root.surface.height * 0.16)))
                                    horizontalAlignment: Text.AlignHCenter
                                }
                                onClicked: root.player?.next()
                            }
                        }
                    }
                }
            }
        }
    }
}
