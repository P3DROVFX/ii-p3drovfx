pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.widgets
import qs.services
import qs.modules.common.functions
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

Item {
    id: root
    property var player: Mpris.players.values.length > 0 ? (Mpris.players.values[playerSelector.currentIndex] ?? Mpris.players.values[0]) : null
    property var artUrl: player?.trackArtUrl ?? ""
    property string artDownloadLocation: Directories.coverArt
    property string artFileName: (artUrl && artUrl !== "") ? Qt.md5(artUrl) : ""
    property string artFilePath: artFileName !== "" ? `${artDownloadLocation}/${artFileName}` : ""
    property color artDominantColor: (root.hasArt && colorQuantizer.colors.length > 0) ? colorQuantizer.colors[0] : Appearance.colors.colPrimary
    property bool downloaded: false
    property QtObject blendedColors: AdaptedMaterialScheme {
        color: artDominantColor
    }
    property real radius

    property string displayedArtFilePath: root.downloaded ? Qt.resolvedUrl(artFilePath) : ""

    Timer {
        running: root.player?.playbackState == MprisPlaybackState.Playing
        interval: Config.options.resources.updateInterval
        repeat: true
        onTriggered: root.player.positionChanged()
    }

    onArtFilePathChanged: {
        if (!root.artUrl || root.artUrl.length == 0) {
            return
        }
        coverArtDownloader.targetFile = root.artUrl
        coverArtDownloader.artFilePath = root.artFilePath
        root.downloaded = false
        coverArtDownloader.running = true
    }

    Process {
        id: coverArtDownloader
        property string targetFile: root.artUrl
        property string artFilePath: root.artFilePath
        command: ["bash", "-c", `[ -f ${artFilePath} ] || curl -sSL '${targetFile}' -o '${artFilePath}'`]
        onExited: (exitCode, exitStatus) => { root.downloaded = true }
    }

    ColorQuantizer {
        id: colorQuantizer
        source: root.displayedArtFilePath
        depth: 0
        rescaleSize: 1
    }

    readonly property bool hasArt: root.artUrl !== "" && root.downloaded
    
    // ── Native shell colors ──
    property color activeColor: Appearance.colors.colPrimary
    property color activeOnColor: Appearance.colors.colOnPrimary
    
    property color activeContainerColor: Appearance.colors.colSecondaryContainer
    property color activeOnContainerColor: Appearance.colors.colOnSecondaryContainer
    
    property color activeTitleColor: Appearance.colors.colOnLayer2
    property color activeSubtextColor: Appearance.colors.colOnLayer1

    // ── Entrance Animations ──
    property int entranceTrigger: -1
    property real artBlurRadius: 0

    function triggerContentEntrance() {
        root.entranceTrigger++;
    }

    onEntranceTriggerChanged: {
        if (entranceTrigger >= 0) {
            // Reset background slide & opacity
            bgTrans.x = -35
            background.opacity = 0

            // Reset transforms, scale & opacities
            artBackground.opacity = 0
            artBackgroundTrans.y = -25
            artBackground.scale = 0.82
            root.artBlurRadius = 32

            metaColumn.opacity = 0
            metaColumnTrans.y = 15

            lyricsItem.opacity = 0
            lyricsItemTrans.y = 20

            progressRow.opacity = 0
            progressRowTrans.y = 15

            controlsRow.opacity = 0
            controlsRowTrans.y = 15
            prevBtn.opacity = 0
            prevBtn.scale = 0.5
            playPauseBtn.opacity = 0
            playPauseBtn.scale = 0.5
            nextBtn.opacity = 0
            nextBtn.scale = 0.5

            volumeRow.opacity = 0
            volumeRowTrans.y = 15
            volMuteBtn.opacity = 0
            volMuteBtn.scale = 0.5
            volDownBtn.opacity = 0
            volDownBtn.scale = 0.5
            volUpBtn.opacity = 0
            volUpBtn.scale = 0.5

            Qt.callLater(function() {
                playerEntranceAnim.stop()
                playerEntranceAnim.start()
            })
        }
    }

    ParallelAnimation {
        id: playerEntranceAnim

        // Background Slide + Fade
        SequentialAnimation {
            ParallelAnimation {
                NumberAnimation { target: background; property: "opacity"; to: 1.0; duration: 300; easing.type: Easing.OutCubic }
                NumberAnimation { target: bgTrans; property: "x"; to: 0; duration: 350; easing.type: Easing.OutCubic }
            }
        }

        // Album Art Entrance + Blur Unveil
        SequentialAnimation {
            PauseAnimation { duration: 40 }
            ParallelAnimation {
                NumberAnimation { target: artBackground; property: "opacity"; to: 1.0; duration: 350; easing.type: Easing.OutCubic }
                NumberAnimation { target: artBackgroundTrans; property: "y"; to: 0; duration: 380; easing.type: Easing.OutCubic }
                NumberAnimation { target: artBackground; property: "scale"; to: 1.0; duration: 380; easing.type: Easing.OutCubic }
                NumberAnimation { target: root; property: "artBlurRadius"; to: 0; duration: 420; easing.type: Easing.OutQuad }
            }
        }

        // Title & Artist Entrance
        SequentialAnimation {
            PauseAnimation { duration: 120 }
            ParallelAnimation {
                NumberAnimation { target: metaColumn; property: "opacity"; to: 1.0; duration: 280; easing.type: Easing.OutCubic }
                NumberAnimation { target: metaColumnTrans; property: "y"; to: 0; duration: 320; easing.type: Easing.OutCubic }
            }
        }

        // Lyrics Entrance
        SequentialAnimation {
            PauseAnimation { duration: 180 }
            ParallelAnimation {
                NumberAnimation { target: lyricsItem; property: "opacity"; to: 1.0; duration: 300; easing.type: Easing.OutCubic }
                NumberAnimation { target: lyricsItemTrans; property: "y"; to: 0; duration: 340; easing.type: Easing.OutCubic }
            }
        }

        // Progress Row Entrance
        SequentialAnimation {
            PauseAnimation { duration: 230 }
            ParallelAnimation {
                NumberAnimation { target: progressRow; property: "opacity"; to: 1.0; duration: 280; easing.type: Easing.OutCubic }
                NumberAnimation { target: progressRowTrans; property: "y"; to: 0; duration: 320; easing.type: Easing.OutCubic }
            }
        }

        // Playback Controls Row Entrance
        SequentialAnimation {
            PauseAnimation { duration: 270 }
            NumberAnimation { target: controlsRow; property: "opacity"; to: 1.0; duration: 180; easing.type: Easing.OutCubic }
        }

        // Prev Button Cascade
        SequentialAnimation {
            PauseAnimation { duration: 290 }
            ParallelAnimation {
                NumberAnimation { target: prevBtn; property: "opacity"; to: 1.0; duration: 220; easing.type: Easing.OutCubic }
                NumberAnimation { target: prevBtn; property: "scale"; to: 1.0; duration: 280; easing.type: Easing.OutCubic }
            }
        }

        // Play/Pause Button Cascade
        SequentialAnimation {
            PauseAnimation { duration: 340 }
            ParallelAnimation {
                NumberAnimation { target: playPauseBtn; property: "opacity"; to: 1.0; duration: 220; easing.type: Easing.OutCubic }
                NumberAnimation { target: playPauseBtn; property: "scale"; to: 1.0; duration: 300; easing.type: Easing.OutCubic }
            }
        }

        // Next Button Cascade
        SequentialAnimation {
            PauseAnimation { duration: 390 }
            ParallelAnimation {
                NumberAnimation { target: nextBtn; property: "opacity"; to: 1.0; duration: 220; easing.type: Easing.OutCubic }
                NumberAnimation { target: nextBtn; property: "scale"; to: 1.0; duration: 280; easing.type: Easing.OutCubic }
            }
        }

        // Volume Controls Row Entrance
        SequentialAnimation {
            PauseAnimation { duration: 420 }
            NumberAnimation { target: volumeRow; property: "opacity"; to: 1.0; duration: 180; easing.type: Easing.OutCubic }
        }

        // Mute Button Cascade
        SequentialAnimation {
            PauseAnimation { duration: 440 }
            ParallelAnimation {
                NumberAnimation { target: volMuteBtn; property: "opacity"; to: 1.0; duration: 200; easing.type: Easing.OutCubic }
                NumberAnimation { target: volMuteBtn; property: "scale"; to: 1.0; duration: 260; easing.type: Easing.OutCubic }
            }
        }

        // Vol Down Button Cascade
        SequentialAnimation {
            PauseAnimation { duration: 480 }
            ParallelAnimation {
                NumberAnimation { target: volDownBtn; property: "opacity"; to: 1.0; duration: 200; easing.type: Easing.OutCubic }
                NumberAnimation { target: volDownBtn; property: "scale"; to: 1.0; duration: 260; easing.type: Easing.OutCubic }
            }
        }

        // Vol Up Button Cascade
        SequentialAnimation {
            PauseAnimation { duration: 520 }
            ParallelAnimation {
                NumberAnimation { target: volUpBtn; property: "opacity"; to: 1.0; duration: 200; easing.type: Easing.OutCubic }
                NumberAnimation { target: volUpBtn; property: "scale"; to: 1.0; duration: 260; easing.type: Easing.OutCubic }
            }
        }
    }

    Rectangle {
        id: background
        anchors.fill: parent
        anchors.leftMargin: 4
        anchors.rightMargin: 4
        anchors.topMargin: -1
        anchors.bottomMargin: 4
        color: Appearance.colors.colLayer2
        radius: (Appearance && Appearance.rounding) ? Appearance.rounding.normal : 0

        transform: Translate {
            id: bgTrans
            x: 0
        }


        ColumnLayout {
            anchors.fill: parent
            anchors.margins: parent.height * 0.04
            spacing: 0
            visible: root.player !== null

            // ── Player selector ──
            StyledComboBox {
                id: playerSelector
                visible: Mpris.players.values.length > 1
                Layout.fillWidth: true
                Layout.bottomMargin: 8
                model: Mpris.players.values.map(p => p.identity ?? p.desktopEntry ?? "Unknown")
                currentIndex: 0
            }

            // ── Album art ──
            Rectangle {
                id: artBackground
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: Math.min(parent.width * 1, parent.height * 0.45)
                Layout.preferredHeight: Layout.preferredWidth
                radius: (Appearance && Appearance.rounding) ? Appearance.rounding.small : 0
                color: ColorUtils.transparentize(Appearance.colors.colLayer1, 0.5)

                transform: Translate {
                    id: artBackgroundTrans
                    y: 0
                }

                Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

                Item {
                    anchors.fill: parent

                    layer.enabled: true
                    layer.effect: FastBlur {
                        radius: root.artBlurRadius
                        cached: false
                    }

                    StyledImage {
                        id: albumArtImage
                        anchors.fill: parent
                        source: root.displayedArtFilePath
                        fillMode: Image.PreserveAspectCrop
                        cache: false
                        antialiasing: true
                        sourceSize.width: artBackground.width
                        sourceSize.height: artBackground.height

                        Behavior on scale { NumberAnimation { duration: 400; easing.type: Easing.OutBack; easing.overshoot: 1.1 } }

                        layer.enabled: true
                        layer.effect: OpacityMask {
                            maskSource: Rectangle {
                                width: albumArtImage.width
                                height: albumArtImage.height
                                radius: artBackground.radius
                            }
                        }
                    }
                }

                FadeLoader {
                    shown: !root.downloaded && root.artUrl !== ""
                    anchors.centerIn: parent
                    MaterialLoadingIndicator {
                        anchors.centerIn: parent
                        loading: true
                        visible: loading
                        implicitSize: 48
                    }
                }
            }

            // ── Title & Artist ──
            ColumnLayout {
                id: metaColumn
                Layout.fillWidth: true
                Layout.topMargin: parent.height * 0.025
                Layout.bottomMargin: parent.height * 0.02
                spacing: parent.height * 0.005

                transform: Translate {
                    id: metaColumnTrans
                    y: 0
                }

                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: titleText.implicitHeight
                    Layout.minimumHeight: Math.max(16, parent.parent.height * 0.024) * 1.5
                    clip: true

                    StyledText {
                        id: titleText
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        font.pixelSize: Math.max(16, parent.parent.height * 0.024)
                        font.weight: Font.Bold
                        color: root.activeTitleColor
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                        text: StringUtils.cleanMusicTitle(root.player?.trackTitle) || "Untitled"

                        Behavior on text {
                            SequentialAnimation {
                                NumberAnimation { target: titleText; property: "x"; to: -titleText.width; duration: 150; easing.type: Easing.InQuad }
                                PropertyAction { target: titleText; property: "text" }
                                NumberAnimation { target: titleText; property: "x"; from: titleText.width; to: 0; duration: 150; easing.type: Easing.OutQuad }
                            }
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: artistText.implicitHeight
                    Layout.minimumHeight: Math.max(13, parent.parent.height * 0.018) * 1.5
                    clip: true

                    StyledText {
                        id: artistText
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        font.pixelSize: Math.max(13, parent.parent.height * 0.018)
                        color: root.activeSubtextColor
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                        text: root.player?.trackArtist || "Unknown Artist"

                        Behavior on text {
                            SequentialAnimation {
                                NumberAnimation { target: artistText; property: "x"; to: -artistText.width; duration: 150; easing.type: Easing.InQuad }
                                PropertyAction { target: artistText; property: "text" }
                                NumberAnimation { target: artistText; property: "x"; from: artistText.width; to: 0; duration: 150; easing.type: Easing.OutQuad }
                            }
                        }
                    }
                }
            }

            // ── Lyrics ──
            Item {
                id: lyricsItem
                Layout.fillWidth: true
                Layout.fillHeight: true

                transform: Translate {
                    id: lyricsItemTrans
                    y: 0
                }

                readonly property bool hasSyncedLines: LyricsService.syncedLines.length > 0
                readonly property bool geniusEnabled: Config.options.lyricsService.enableGenius
                readonly property bool lrclibEnabled: Config.options.lyricsService.enableLrclib

                Component.onCompleted: {
                    if (!geniusEnabled && !lrclibEnabled) return
                    LyricsService.initiliazeLyrics()
                }

                FadeLoader {
                    shown: !lyricsItem.hasSyncedLines
                    anchors.fill: parent
                    sourceComponent: LyricsFlickable {
                        anchors.fill: parent
                        player: root.player
                        fontPixelSize: Math.max(16, parent.height * 0.024)
                        textColor: root.activeTitleColor
                        loadingIndicatorSize: 96
                        indicatorColor: root.activeContainerColor
                        shapeColor: root.activeOnContainerColor
                    }
                }
                
                FadeLoader {
                    shown: lyricsItem.hasSyncedLines
                    anchors.fill: parent
                    sourceComponent: LyricsSyllable {
                        anchors.fill: parent
                        largeFontSize: Math.max(20, parent.height * 0.04)
                        activeColor: root.activeColor
                    }
                }
            }

            // ── Progress ──
            RowLayout {
                id: progressRow
                Layout.fillWidth: true
                Layout.topMargin: parent.height * 0.01
                spacing: 12

                transform: Translate {
                    id: progressRowTrans
                    y: 0
                }

                StyledText {
                    font.pixelSize: (Appearance && Appearance.pixelSize) ? Appearance.pixelSize.normal : 16
                    color: root.activeSubtextColor
                    font.letterSpacing: -0.4
                    font.features: { "tnum": 1 }
                    text: StringUtils.friendlyTimeForSeconds(root.player ? root.player.position : 0)
                }

                Item {
                    Layout.fillWidth: true
                    implicitHeight: Math.max(sliderLoader.implicitHeight, progressBarLoader.implicitHeight)

                    Loader {
                        id: sliderLoader
                        anchors.fill: parent
                        active: root.player ? (root.player.canSeek ?? false) : false
                        sourceComponent: StyledSlider {
                            configuration: StyledSlider.Configuration.Wavy
                            highlightColor: root.activeColor
                            trackColor: root.activeContainerColor
                            handleColor: root.activeColor
                            value: (root.player && root.player.length > 0) ? (root.player.position / root.player.length) : 0
                            onMoved: if (root.player) root.player.position = value * root.player.length
                        }
                    }

                    Loader {
                        id: progressBarLoader
                        anchors {
                            verticalCenter: parent.verticalCenter
                            left: parent.left
                            right: parent.right
                        }
                        active: root.player ? !(root.player.canSeek ?? false) : false
                        sourceComponent: StyledProgressBar {
                            wavy: root.player ? root.player.isPlaying : false
                            highlightColor: root.activeColor
                            trackColor: root.activeContainerColor
                            value: (root.player && root.player.length > 0) ? (root.player.position / root.player.length) : 0
                        }
                    }
                }

                StyledText {
                    font.pixelSize: (Appearance && Appearance.pixelSize) ? Appearance.pixelSize.normal : 16
                    color: root.activeSubtextColor
                    font.letterSpacing: -0.4
                    font.features: { "tnum": 1 }
                    text: StringUtils.friendlyTimeForSeconds(root.player ? root.player.length : 0)
                }
            }

            // ── Controls ──
            RowLayout {
                id: controlsRow
                Layout.fillWidth: true
                Layout.topMargin: parent.height * 0.02
                Layout.preferredHeight: parent.height * 0.11
                Layout.alignment: Qt.AlignHCenter
                spacing: 10

                transform: Translate {
                    id: controlsRowTrans
                    y: 0
                }

                RippleButton {
                    id: prevBtn
                    property real baseSize: Math.max(42, parent.parent.height * 0.06)
                    implicitWidth: baseSize * 1.5
                    implicitHeight: baseSize * 1.5
                    buttonRadius: (Appearance && Appearance.rounding) ? Appearance.rounding.full : baseSize / 2
                    colBackground: ColorUtils.transparentize(root.activeContainerColor, 0.7)
                    colBackgroundHover: root.hasArt ? blendedColors.colSecondaryContainerHover : Appearance.colors.colSecondaryContainerHover
                    colRipple: root.hasArt ? blendedColors.colSecondaryContainerActive : Appearance.colors.colSecondaryContainerActive
                    
                    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack; easing.overshoot: 1.3 } }

                    downAction: () => { if (root.player) root.player.previous() }
                    contentItem: MaterialSymbol {
                        iconSize: 25
                        fill: 1
                        horizontalAlignment: Text.AlignHCenter
                        color: root.activeOnContainerColor
                        text: "skip_previous"
                    }
                }

                RippleButton {
                    id: playPauseBtn
                    property real baseSize: Math.max(70, parent.parent.height * 0.1)
                    Layout.fillWidth: true
                    implicitHeight: baseSize
                    buttonRadius: (root.player && root.player.isPlaying) ? ((Appearance && Appearance.rounding) ? Appearance.rounding.verylarge : 15) : baseSize / 2
                    colBackground: (root.player && root.player.isPlaying) ? root.activeColor : root.activeContainerColor
                    colBackgroundHover: (root.player && root.player.isPlaying) ? (root.hasArt ? blendedColors.colPrimaryHover : Appearance.colors.colPrimaryHover) : (root.hasArt ? blendedColors.colSecondaryContainerHover : Appearance.colors.colSecondaryContainerHover)
                    colRipple: (root.player && root.player.isPlaying) ? (root.hasArt ? blendedColors.colPrimaryActive : Appearance.colors.colPrimaryActive) : (root.hasArt ? blendedColors.colSecondaryContainerActive : Appearance.colors.colSecondaryContainerActive)
                    
                    Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }
                    Behavior on buttonRadius { NumberAnimation { duration: 300; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }

                    downAction: () => { if (root.player) root.player.togglePlaying() }
                    contentItem: MaterialSymbol {
                        iconSize: 50
                        fill: 1
                        horizontalAlignment: Text.AlignHCenter
                        color: (root.player && root.player.isPlaying) ? root.activeOnColor : root.activeOnContainerColor
                        text: (root.player && root.player.isPlaying) ? "pause" : "play_arrow"
                        Behavior on color {
                            animation: (Appearance && Appearance.animation && Appearance.animation.elementMoveFast) ? Appearance.animation.elementMoveFast.colorAnimation.createObject(this) : null
                        }
                    }
                }

                RippleButton {
                    id: nextBtn
                    property real baseSize: Math.max(42, parent.parent.height * 0.06)
                    implicitWidth: baseSize * 1.5
                    implicitHeight: baseSize * 1.5
                    buttonRadius: (Appearance && Appearance.rounding) ? Appearance.rounding.full : baseSize / 2
                    colBackground: ColorUtils.transparentize(root.activeContainerColor, 0.7)
                    colBackgroundHover: root.hasArt ? blendedColors.colSecondaryContainerHover : Appearance.colors.colSecondaryContainerHover
                    colRipple: root.hasArt ? blendedColors.colSecondaryContainerActive : Appearance.colors.colSecondaryContainerActive
                    
                    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack; easing.overshoot: 1.3 } }

                    downAction: () => { if (root.player) root.player.next() }
                    contentItem: MaterialSymbol {
                        iconSize: 25
                        fill: 1
                        horizontalAlignment: Text.AlignHCenter
                        color: root.activeOnContainerColor
                        text: "skip_next"
                    }
                }
            }

            // ── Volume ──
            RowLayout {
                id: volumeRow
                Layout.fillWidth: true
                Layout.topMargin: 8
                spacing: 8

                transform: Translate {
                    id: volumeRowTrans
                    y: 0
                }

                RippleButton {
                    id: volMuteBtn
                    property real baseSize: Math.max(36, parent.parent.height * 0.05)
                    implicitWidth: baseSize
                    implicitHeight: baseSize
                    buttonRadius: (Appearance && Appearance.rounding) ? Appearance.rounding.large : 0
                    colBackground: ColorUtils.transparentize(root.activeContainerColor, 0.7)
                    colBackgroundHover: root.hasArt ? blendedColors.colSecondaryContainerHover : Appearance.colors.colSecondaryContainerHover
                    colRipple: root.hasArt ? blendedColors.colSecondaryContainerActive : Appearance.colors.colSecondaryContainerActive
                    
                    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }

                    downAction: () => { if (root.player) root.player.volume = root.player.volume > 0 ? 0 : 1.0 }
                    contentItem: MaterialSymbol {
                        iconSize: 18
                        fill: 1
                        horizontalAlignment: Text.AlignHCenter
                        color: root.activeOnContainerColor
                        text: (root.player ? (root.player.volume ?? 1) : 1) <= 0 ? "volume_off"
                            : (root.player ? (root.player.volume ?? 1) : 1) < 0.5 ? "volume_down"
                            : "volume_up"
                    }
                }

                RippleButton {
                    id: volDownBtn
                    property real baseSize: Math.max(36, parent.parent.height * 0.05)
                    Layout.fillWidth: true
                    implicitHeight: baseSize
                    buttonRadius: (Appearance && Appearance.rounding) ? Appearance.rounding.large : 0
                    colBackground: ColorUtils.transparentize(root.activeContainerColor, 0.7)
                    colBackgroundHover: root.hasArt ? blendedColors.colSecondaryContainerHover : Appearance.colors.colSecondaryContainerHover
                    colRipple: root.hasArt ? blendedColors.colSecondaryContainerActive : Appearance.colors.colSecondaryContainerActive
                    
                    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }

                    downAction: () => { if (root.player) root.player.volume = Math.max(0, (root.player.volume ?? 1) - 0.1) }
                    contentItem: MaterialSymbol {
                        iconSize: 18
                        fill: 1
                        horizontalAlignment: Text.AlignHCenter
                        color: root.activeOnContainerColor
                        text: "volume_down"
                    }
                }

                RippleButton {
                    id: volUpBtn
                    property real baseSize: Math.max(36, parent.parent.height * 0.05)
                    Layout.fillWidth: true
                    implicitHeight: baseSize
                    buttonRadius: (Appearance && Appearance.rounding) ? Appearance.rounding.large : 0
                    colBackground: ColorUtils.transparentize(root.activeContainerColor, 0.7)
                    colBackgroundHover: root.hasArt ? blendedColors.colSecondaryContainerHover : Appearance.colors.colSecondaryContainerHover
                    colRipple: root.hasArt ? blendedColors.colSecondaryContainerActive : Appearance.colors.colSecondaryContainerActive
                    
                    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }

                    downAction: () => { if (root.player) root.player.volume = Math.min(1.5, (root.player.volume ?? 1) + 0.1) }
                    contentItem: MaterialSymbol {
                        iconSize: 18
                        fill: 1
                        horizontalAlignment: Text.AlignHCenter
                        color: root.activeOnContainerColor
                        text: "volume_up"
                    }
                }
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 16
            visible: root.player === null

            Item {
                Layout.fillHeight: true
            }

            MaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                text: "music_off"
                iconSize: 64
                color: Appearance.colors.colSubtext
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: Translation.tr("No Active Media")
                font.pixelSize: Appearance.font.pixelSize.huge
                font.weight: Font.Bold
                color: root.activeTitleColor
                horizontalAlignment: Text.AlignHCenter
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: parent.width * 0.85
                text: Translation.tr("Play media from any player (Spotify, browser, etc.) to control playback and view lyrics here.")
                font.pixelSize: Appearance.font.pixelSize.small
                color: root.activeSubtextColor
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                opacity: 0.7
            }

            Item {
                Layout.fillHeight: true
            }
        }
    }
}

