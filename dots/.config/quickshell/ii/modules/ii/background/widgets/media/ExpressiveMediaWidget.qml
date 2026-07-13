import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.modules.ii.background.widgets

AbstractBackgroundWidget {
    id: root

    configEntryName: "media"

    visibleWhenLocked: (Config.options.lock.centerWidget === "media")

    readonly property bool forceCenter: (GlobalStates.screenLocked && Config.options.lock.centerWidget === "media")
    readonly property real centeringX: (root.screenWidth - root.implicitWidth) / 2
    readonly property real centeringY: (root.screenHeight - root.implicitHeight) / 2

    property real lastStaticWidth: 400
    property real lastStaticHeight: 240

    readonly property real computedWidth: cardPadding * 2 + albumContainerSize + cardSpacing + 350
    readonly property real computedHeight: 240

    implicitWidth: (typeof bgRoot !== 'undefined' && bgRoot.lockAnimationActive) ? lastStaticWidth : computedWidth
    implicitHeight: (typeof bgRoot !== 'undefined' && bgRoot.lockAnimationActive) ? lastStaticHeight : computedHeight

    onComputedWidthChanged: {
        if (typeof bgRoot === 'undefined' || !bgRoot.lockAnimationActive) {
            lastStaticWidth = computedWidth;
        }
    }
    onComputedHeightChanged: {
        if (typeof bgRoot === 'undefined' || !bgRoot.lockAnimationActive) {
            lastStaticHeight = computedHeight;
        }
    }

    onForceCenterChanged: {
        root.animDuration = 700;
        animResetTimer.restart();
    }

    Timer {
        id: animResetTimer
        interval: 750
        repeat: false
        onTriggered: { root.animDuration = Appearance.animation.elementMove.duration; }
    }

    targetX: forceCenter ? centeringX : ((placementStrategy === "free" || placementStrategy === "draggable") ? Math.max(0, Math.min(configEntry.x, scaledScreenWidth - width)) : calculatedX)
    targetY: forceCenter ? centeringY : ((placementStrategy === "free" || placementStrategy === "draggable") ? Math.max(0, Math.min(configEntry.y, scaledScreenHeight - height)) : calculatedY)

    property MprisPlayer player: MprisController.activePlayer

    readonly property color colBg: Appearance.colors.colPrimaryContainer
    readonly property color colAlbumBg: Appearance.colors.colSurfaceContainerLow
    readonly property color colControlsBg: Appearance.colors.colSecondaryContainer
    readonly property color colText: Appearance.colors.colOnSurface
    readonly property color colTimeMain: Appearance.colors.colOnPrimaryContainer
    readonly property color colTimeSub: ColorUtils.transparentize(Appearance.colors.colOnPrimaryContainer, 0.4)
    readonly property color colProgressHighlight: Appearance.colors.colPrimary
    readonly property color colProgressTrack: ColorUtils.transparentize(Appearance.colors.colOnPrimaryContainer, 0.6)
    readonly property color colBtnSecondary: Appearance.colors.colTertiaryContainer
    readonly property color colBtnSecondaryHover: Appearance.colors.colTertiaryContainerHover
    readonly property color colBtnSecondaryActive: Appearance.colors.colTertiaryContainerActive
    readonly property color colBtnPlayBg: Appearance.colors.colPrimary
    readonly property color colBtnPlayRipple: Appearance.colors.colPrimaryHover
    readonly property color colBtnPlayIcon: Appearance.colors.colOnPrimary
    readonly property color colBtnIcon: Appearance.colors.colOnSecondaryContainer
    readonly property color colAlbumBorder: Appearance.colors.colOnPrimaryContainer

    readonly property int globalRadius: Appearance.rounding.large
    readonly property int controlsRadius: Appearance.rounding.large
    readonly property int btnRadius: Appearance.rounding.large
    readonly property int btnPlayRadius: Appearance.rounding.full

    readonly property int cardPadding: 12
    readonly property int cardSpacing: 10
    readonly property int albumContainerSize: 148
    readonly property int albumCircleSize: 128
    readonly property int albumBorderWidth: 8
    readonly property int centerDotSize: 32
    readonly property int controlsPadding: 16
    readonly property int controlsSpacing: 8
    readonly property int timerSpacing: 6
    readonly property int timerPrimarySize: Appearance.font.pixelSize.huge
    readonly property int timerSecondarySize: Appearance.font.pixelSize.small
    readonly property int btnRowHeight: 44
    readonly property int btnPlayWidth: 44

    readonly property string trackTitle: player?.trackTitle || Translation.tr("No media")
    readonly property string trackArtist: player?.trackArtist || Translation.tr("Unknown Artist")
    readonly property string artUrl: MprisController.artUrl
    readonly property bool isLocalArt: artUrl.startsWith("file://")
    
    property string artDownloadLocation: Directories.coverArt
    property string artFileName: Qt.md5(artUrl)
    property string artFilePath: `${artDownloadLocation}/${artFileName}`
    property bool artDownloaded: false

    readonly property string artSource: {
        if (!artUrl) return "";
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
        interval: Config.options.resources.updateInterval
        repeat: true
        onTriggered: root.player.positionChanged()
    }

    StyledRectangularShadow {
        id: bgShadow
        target: mainBg
        visible: Config.options.background.widgets.enableShadows ?? true
    }

    Rectangle {
        id: mainBg
        anchors.fill: parent
        anchors.margins: 8
        color: root.colBg
        radius: root.globalRadius
        border.color: Appearance.colors.colLayer0Border
        border.width: 1
        clip: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: root.cardPadding
            spacing: root.cardSpacing

            StyledText {
                Layout.fillWidth: true
                text: root.trackTitle.toUpperCase()
                color: root.colText
                font.family: ledFont.name
                font.pixelSize: 28
                font.weight: Font.Light
                elide: Text.ElideRight
                Layout.bottomMargin: -6
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: root.cardSpacing

                Rectangle {
                    id: albumPill
                    Layout.fillHeight: true
                    Layout.preferredWidth: height
                    Layout.alignment: Qt.AlignVCenter
                    color: root.colAlbumBg
                    radius: root.globalRadius

                    Item {
                        id: albumArtItem
                        anchors.centerIn: parent
                        width: parent.height - 20
                        height: parent.height - 20

                        RotationAnimator {
                            target: albumArtItem
                            from: 0
                            to: 360
                            duration: 10000
                            loops: Animation.Infinite
                            running: root.player?.isPlaying
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
                            visible: albumArtImage.status !== Image.Ready
                            iconSize: 48
                            text: "music_note"
                            color: Appearance.colors.colSubtext
                        }

                        // Inset ring border on top of image
                        Rectangle {
                            anchors.fill: parent
                            color: "transparent"
                            radius: width / 2
                            border.color: root.colAlbumBorder
                            border.width: root.albumBorderWidth
                            z: 2
                        }

                        Rectangle {
                            anchors.centerIn: parent
                            width: root.centerDotSize
                            height: root.centerDotSize
                            radius: width / 2
                            color: Appearance.m3colors.m3surfaceContainer
                            z: 3
                        }
                    }
                }

                // Controls panel
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.alignment: Qt.AlignVCenter
                    color: root.colControlsBg
                    radius: root.controlsRadius
                    clip: true

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.topMargin: root.controlsPadding
                        anchors.leftMargin: root.controlsPadding
                        anchors.rightMargin: root.controlsPadding
                        anchors.bottomMargin: root.controlsPadding
                        spacing: root.controlsSpacing

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: root.timerSpacing
                            Layout.alignment: Qt.AlignTop

                            Text {
                                text: StringUtils.friendlyTimeForSeconds(root.player?.position ?? 0)
                                color: root.colTimeMain
                                font.pixelSize: root.timerPrimarySize
                                font.weight: Font.ExtraBold
                                Layout.alignment: Qt.AlignTop
                            }

                            Text {
                                text: StringUtils.friendlyTimeForSeconds(root.player?.length ?? 0)
                                color: root.colTimeSub
                                font.pixelSize: root.timerSecondarySize
                                font.weight: Font.Regular
                                Layout.alignment: Qt.AlignTop
                                Layout.topMargin: 4
                            }

                            StyledText {
                                text: root.trackArtist
                                color: root.colTimeSub
                                font.pixelSize: root.timerSecondarySize
                                font.weight: Font.Regular
                                Layout.maximumWidth: 150
                                elide: Text.ElideRight
                                horizontalAlignment: Text.AlignLeft
                                Layout.alignment: Qt.AlignTop
                                Layout.topMargin: 4
                            }

                            Item {
                                Layout.fillWidth: true
                            }
                        }

                        Item {
                            Layout.fillWidth: true
                            implicitHeight: Math.max(sliderLoader.implicitHeight, progressLoader.implicitHeight)

                            Loader {
                                id: sliderLoader
                                anchors.fill: parent
                                active: root.player?.canSeek ?? false
                                sourceComponent: StyledSlider {
                                    configuration: StyledSlider.Configuration.Wavy
                                    highlightColor: root.colProgressHighlight
                                    trackColor: root.colProgressTrack
                                    handleColor: root.colProgressHighlight
                                    value: root.player?.position / root.player?.length
                                    onMoved: root.player.position = value * root.player.length
                                }
                            }

                            Loader {
                                id: progressLoader
                                anchors {
                                    verticalCenter: parent.verticalCenter
                                    left: parent.left
                                    right: parent.right
                                }
                                active: !(root.player?.canSeek ?? false)
                                sourceComponent: StyledProgressBar {
                                    wavy: root.player?.isPlaying
                                    highlightColor: root.colProgressHighlight
                                    trackColor: root.colProgressTrack
                                    value: root.player?.position / root.player?.length
                                }
                            }
                        }

                        // Buttons row
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: root.btnRowHeight
                            spacing: root.controlsSpacing

                            RippleButton {
                                Layout.fillWidth: true
                                Layout.preferredWidth: 0
                                Layout.preferredHeight: root.btnPlayWidth
                                Layout.alignment: Qt.AlignVCenter
                                colBackground: root.colBtnSecondary
                                colBackgroundHover: root.colBtnSecondaryHover
                                colRipple: root.colBtnSecondaryActive
                                buttonRadius: root.btnRadius
                                contentItem: MaterialSymbol {
                                    text: "skip_previous"
                                    color: root.colBtnIcon
                                    fill: 1
                                    iconSize: Appearance.font.pixelSize.huge
                                    horizontalAlignment: Text.AlignHCenter
                                }
                                onClicked: root.player?.previous()
                            }

                            RippleButton {
                                implicitWidth: root.btnPlayWidth
                                implicitHeight: root.btnPlayWidth
                                colBackground: root.colBtnPlayBg
                                colRipple: root.colBtnPlayRipple
                                buttonRadius: root.player?.isPlaying ? Appearance.rounding.small : Appearance.rounding.full

                                Behavior on buttonRadius {
                                    NumberAnimation {
                                        duration: 250
                                        easing.type: Easing.OutQuint
                                    }
                                }

                                contentItem: MaterialSymbol {
                                    text: root.player?.isPlaying ? "pause" : "play_arrow"
                                    color: root.colBtnPlayIcon
                                    fill: 1
                                    iconSize: Appearance.font.pixelSize.huge
                                    horizontalAlignment: Text.AlignHCenter
                                }
                                onClicked: root.player?.togglePlaying()
                            }

                            RippleButton {
                                Layout.fillWidth: true
                                Layout.preferredWidth: 0
                                Layout.preferredHeight: root.btnPlayWidth
                                Layout.alignment: Qt.AlignVCenter
                                colBackground: root.colBtnSecondary
                                colBackgroundHover: root.colBtnSecondaryHover
                                colRipple: root.colBtnSecondaryActive
                                buttonRadius: root.btnRadius
                                contentItem: MaterialSymbol {
                                    text: "skip_next"
                                    color: root.colBtnIcon
                                    fill: 1
                                    iconSize: Appearance.font.pixelSize.huge
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
