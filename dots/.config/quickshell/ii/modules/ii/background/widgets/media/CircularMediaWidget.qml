import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Services.Mpris
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs
import qs.services
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

AbstractBackgroundWidget {
    id: root

    configEntryName: "circular_media"

    visibleWhenLocked: root.lockBehavior === "keep" || root.lockBehavior === "center" || root.lockBehavior === "lockOnly" || (Config.options.lock.centerWidget === "media")

    // Default size is 240x240 for 1:1 widgets as per AGENTS.md guidelines
    implicitWidth: 240
    implicitHeight: 240

    readonly property bool useAlbumColors: Config.ready ? (Config.options.background.widgets.circular_media.useAlbumColors ?? true) : true
    readonly property MprisPlayer player: MprisController.activePlayer
    readonly property bool playing: player ? player.playbackState === MprisPlaybackState.Playing : false
    readonly property string artUrl: player?.trackArtUrl ?? ""
    readonly property string trackTitle: StringUtils.cleanMusicTitle(player?.trackTitle) || Translation.tr("No media")
    readonly property string trackArtist: player?.trackArtist || Translation.tr("Unknown Artist")

    property bool isLocalArt: artUrl.startsWith("file://")
    property string artDownloadLocation: Directories.coverArt
    property string artFileName: Qt.md5(artUrl)
    property string artFilePath: `${artDownloadLocation}/${artFileName}`
    property bool artDownloaded: false

    readonly property string artSource: {
        if (!artUrl)
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
        command: ["bash", "-c", `[ -f ${artFilePath} ] || (curl -4 -sSL '${targetFile}' -o '${artTempPath}' && mv '${artTempPath}' '${artFilePath}')`]
        onExited: {
            artDownloaded = true;
        }
    }

    ColorQuantizer {
        id: colorQuantizer
        source: root.artSource
        depth: 0
        rescaleSize: 1
    }

    property color artDominantColor: ColorUtils.mix((colorQuantizer?.colors[0] ?? Appearance.colors.colPrimary), Appearance.colors.colPrimaryContainer, 0.8) || Appearance.m3colors.m3secondaryContainer

    property QtObject blendedColors: AdaptedMaterialScheme {
        color: root.artDominantColor
    }

    readonly property bool useDynamicColors: root.useAlbumColors && root.artSource !== ""

    // Vibrant button coloring using only colPrimary, colOnPrimary, and colPrimaryContainer
    readonly property color activeAccentColor: root.useDynamicColors ? blendedColors.colPrimary : Appearance.colors.colPrimary
    readonly property color activeAccentContainer: root.useDynamicColors ? blendedColors.colPrimaryContainer : Appearance.colors.colPrimaryContainer
    readonly property color activeOnPrimary: root.useDynamicColors ? blendedColors.colOnPrimary : Appearance.colors.colOnPrimary

    readonly property color activeTextColor: root.useDynamicColors ? (blendedColors.colOnSecondaryContainer ?? blendedColors.colOnPrimary) : Appearance.colors.colOnSurface
    readonly property color activeSubtextColor: root.useDynamicColors ? blendedColors.colSecondary : Appearance.colors.colOnSurfaceVariant

    // Trigger position updates for the progress bar
    Timer {
        running: root.playing
        interval: Config.options.resources.updateInterval ?? 1000
        repeat: true
        onTriggered: {
            if (root.player) {
                root.player.positionChanged();
            }
        }
    }

    readonly property real progressValue: {
        if (!root.player || root.player.length <= 0)
            return 0.0;
        return Math.max(0.0, Math.min(1.0, root.player.position / root.player.length));
    }

    // Outer bezel shadow support
    StyledDropShadow {
        target: bezelRing
        visible: Config.options.background.widgets.enableShadows ?? true
    }

    // Outer Bezel Ring (Moldura) using opaque solid colBackgroundSurfaceContainer base
    Rectangle {
        id: bezelRing
        anchors.fill: parent
        radius: width / 2
        color: Appearance.m3colors.m3shadow // Opaque base to prevent transparency leaks

        // Inner Screen Container
        Rectangle {
            id: innerScreen
            anchors.fill: parent
            anchors.margins: parent.width * 0.08 // 8% bezel thickness
            radius: width / 2
            color: Appearance.m3colors.m3shadow

            // Opaque Background Artwork + Gradient Container (with circular masking)
            Item {
                id: artBackgroundContainer
                anchors.fill: parent
                z: 0

                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: artBackgroundContainer.width
                        height: artBackgroundContainer.height
                        radius: artBackgroundContainer.width / 2
                    }
                }

                // Opaque base behind album art
                Rectangle {
                    anchors.fill: parent
                    color: Appearance.m3colors.m3shadow
                }

                // Album Art with a light blur
                Image {
                    id: albumArtImage
                    anchors.fill: parent
                    source: root.artSource
                    fillMode: Image.PreserveAspectCrop
                    visible: root.artSource !== ""
                    asynchronous: true

                    layer.enabled: true
                    layer.effect: FastBlur {
                        radius: 4 // light blur
                    }
                }

                // Radial Gradient: smooth/wide fade region, starts closer to the center
                RadialGradient {
                    id: radialGrad
                    anchors.fill: parent
                    horizontalRadius: width / 2
                    verticalRadius: height / 2
                    gradient: Gradient {
                        GradientStop {
                            position: 0.0
                            color: "transparent"
                        }
                        GradientStop {
                            position: 0.25
                            color: "transparent"
                        }
                        GradientStop {
                            position: 0.62
                            color: ColorUtils.transparentize(Appearance.m3colors.m3shadow, 0.4)
                        }
                        GradientStop {
                            position: 0.75
                            color: ColorUtils.transparentize(Appearance.m3colors.m3shadow, 0.2)
                        }
                        GradientStop {
                            position: 1.0
                            color: Appearance.m3colors.m3shadow
                        }
                    }
                }
            }

            // Main Content Layout (Completely outside the art layer, sitting on top of the gradient)
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: parent.width * 0.02 // minimized margins
                spacing: 1 // minimized spacing
                z: 2

                // Spacer top
                Item {
                    Layout.fillHeight: true
                }

                // Row with App Icon and Song Title (Centered Row block)
                Item {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredHeight: root.width * 0.08
                    width: Math.min(root.width * 0.85, titleRow.implicitWidth)

                    Row {
                        id: titleRow
                        anchors.centerIn: parent
                        spacing: 6

                        MaterialShape {
                            id: sourceIconBadge
                            width: root.width * 0.075
                            height: width
                            anchors.verticalCenter: parent.verticalCenter
                            shapeString: "Circle"
                            color: "transparent"

                            Loader {
                                id: appIconLoader
                                anchors.fill: parent
                                active: root.player && root.player.desktopEntry !== ""
                                sourceComponent: IconImage {
                                    implicitSize: parent.width
                                    anchors.centerIn: parent
                                    source: Quickshell.iconPath(root.player ? root.player.desktopEntry : "audio-x-generic", "audio-x-generic")
                                }
                            }

                            Loader {
                                anchors.fill: parent
                                active: !appIconLoader.active
                                sourceComponent: MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "music_note"
                                    iconSize: parent.width * 0.8
                                    color: root.activeTextColor
                                }
                            }
                        }

                        StyledText {
                            text: root.trackTitle
                            color: root.activeTextColor
                            font.pixelSize: root.width * 0.05 // reduced font size
                            font.weight: Font.Bold
                            font.styleName: "Rounded"
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.min(root.width * 0.46, implicitWidth)
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }
                    }
                }

                // Artist Name Row
                StyledText {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignHCenter
                    Layout.leftMargin: parent.width * 0.06
                    Layout.rightMargin: parent.width * 0.06
                    text: root.trackArtist
                    color: root.activeSubtextColor
                    font.pixelSize: root.width * 0.038 // reduced font size
                    font.weight: Font.Normal
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }

                // Minimal Spacer between text and controls
                Item {
                    Layout.preferredHeight: 3
                }

                // Controls Area (Previous, Play/Pause + Squiggle progress, Next)
                Item {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredHeight: root.width * 0.28
                    Layout.preferredWidth: root.width * 0.76

                    Row {
                        anchors.centerIn: parent
                        spacing: root.width * 0.05

                        // Previous Button (Vertical capsule/pill height matching play/pause button directly)
                        RippleButton {
                            id: prevButton
                            width: root.width * 0.20
                            height: playPauseButton.height // matches the actual pause button height
                            anchors.verticalCenter: parent.verticalCenter
                            buttonRadius: width / 2 // vertical capsule shape
                            colBackground: root.activeAccentColor
                            colBackgroundHover: ColorUtils.mix(root.activeAccentColor, root.activeAccentColor, 0.9)
                            colRipple: ColorUtils.mix(root.activeAccentColor, root.activeAccentColor, 0.8)

                            contentItem: MaterialSymbol {
                                text: "skip_previous"
                                iconSize: parent.width * 0.6
                                color: root.activeAccentContainer
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            onClicked: {
                                if (root.player)
                                    root.player.previous();
                            }
                        }

                        // Play/Pause central button wrapper (includes thickness for progress border)
                        Item {
                            id: centralButtonWrapper
                            width: root.width * 0.26
                            height: width
                            anchors.verticalCenter: parent.verticalCenter

                            // Underlay progress bar in Cookie9Sided shape with thicker borders
                            MaterialShape {
                                id: progressBgOutline
                                anchors.fill: parent
                                shapeString: "Cookie9Sided"
                                color: "transparent"
                                borderColor: ColorUtils.transparentize(root.activeAccentColor, 0.3)
                                borderWidth: 0.055
                            }

                            MaterialShape {
                                id: progressActiveOutline
                                anchors.fill: parent
                                shapeString: "Cookie9Sided"
                                color: "transparent"
                                borderColor: root.activeAccentColor
                                borderWidth: 0.055
                                visible: false
                            }

                            ConicalGradient {
                                id: conicalMask
                                anchors.fill: progressActiveOutline
                                angle: -90
                                visible: false
                                gradient: Gradient {
                                    GradientStop {
                                        position: 0.0
                                        color: "white"
                                    }
                                    GradientStop {
                                        position: root.progressValue
                                        color: "white"
                                    }
                                    GradientStop {
                                        position: root.progressValue + 0.0001
                                        color: "transparent"
                                    }
                                    GradientStop {
                                        position: 1.0
                                        color: "transparent"
                                    }
                                }
                            }

                            OpacityMask {
                                anchors.fill: progressActiveOutline
                                source: progressActiveOutline
                                maskSource: conicalMask
                            }

                            // Play/Pause button shape inside Cookie9Sided
                            RippleButton {
                                id: playPauseButton
                                anchors.fill: parent
                                anchors.margins: parent.width * 0.08
                                buttonRadius: width / 2
                                colBackground: root.activeAccentColor
                                colBackgroundHover: ColorUtils.mix(root.activeAccentColor, root.activeAccentColor, 0.9)
                                colRipple: ColorUtils.mix(root.activeAccentContainer, root.activeAccentColor, 0.8)

                                layer.enabled: true
                                layer.effect: OpacityMask {
                                    maskSource: MaterialShape {
                                        width: playPauseButton.width
                                        height: playPauseButton.height
                                        shapeString: "Cookie9Sided"
                                    }
                                }

                                contentItem: MaterialSymbol {
                                    text: root.playing ? "pause" : "play_arrow"
                                    fill: 1
                                    iconSize: parent.width * 0.5
                                    color: root.activeAccentContainer
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }

                                onClicked: {
                                    if (root.player)
                                        root.player.togglePlaying();
                                }
                            }
                        }

                        // Next Button (Vertical capsule/pill height matching play/pause button directly)
                        RippleButton {
                            id: nextButton
                            width: root.width * 0.20
                            height: playPauseButton.height // matches the actual pause button height
                            anchors.verticalCenter: parent.verticalCenter
                            buttonRadius: width / 2 // vertical capsule shape
                            colBackground: root.activeAccentColor
                            colBackgroundHover: ColorUtils.mix(root.activeAccentColor, root.activeAccentColor, 0.9)
                            colRipple: ColorUtils.mix(root.activeAccentColor, root.activeAccentColor, 0.8)

                            contentItem: MaterialSymbol {
                                text: "skip_next"
                                iconSize: parent.width * 0.6
                                color: root.activeAccentContainer
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            onClicked: {
                                if (root.player)
                                    root.player.next();
                            }
                        }
                    }
                }

                // Spacer
                Item {
                    Layout.fillHeight: true
                }

                // Audio Output Device Pill Shape (Centered at the Bottom)
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredHeight: root.width * 0.13

                    RippleButton {
                        id: devicePill
                        implicitHeight: root.width * 0.09
                        leftPadding: root.width * 0.04
                        rightPadding: root.width * 0.04
                        colBackground: ColorUtils.transparentize(Appearance.colors.colSurfaceContainerHigh, 0.4)
                        colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colSurfaceContainerHighestHover, 0.4)
                        colRipple: ColorUtils.transparentize(Appearance.colors.colSurfaceContainerHighestActive, 0.3)
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

                        contentItem: Item {
                            implicitWidth: deviceRowLayout.implicitWidth
                            implicitHeight: devicePill.height

                            Row {
                                id: deviceRowLayout
                                anchors.centerIn: parent
                                spacing: 4

                                MaterialSymbol {
                                    text: devicePill.audioDeviceIcon
                                    iconSize: devicePill.height * 0.5
                                    color: root.activeTextColor
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                StyledText {
                                    text: devicePill.activeAudioDeviceName !== "" ? devicePill.activeAudioDeviceName : Translation.tr("Audio")
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    font.weight: Font.Bold
                                    color: root.activeTextColor
                                    width: Math.min(root.width * 0.32, implicitWidth)
                                    elide: Text.ElideRight
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                        }
                    }
                }

                // Spacer bottom
                Item {
                    Layout.fillHeight: true
                }
            }
        }
    }
}
