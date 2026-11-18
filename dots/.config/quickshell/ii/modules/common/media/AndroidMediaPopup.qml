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
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.common.models

Item {
    id: root

    required property MprisPlayer player
    property bool showShadow: true
    property bool showBottomControls: true
    property bool showPinButton: true
    property list<real> visualizerPoints: []

    readonly property bool playing: player ? player.playbackState === MprisPlaybackState.Playing : false
    // Per-player art, not the active player's. Every popup instance in the column
    // receives its own `player`; reading MprisController.artUrl here replicated the
    // active source's cover onto all of them.
    readonly property string artUrl: player?.trackArtUrl ?? ""
    readonly property string trackTitle: StringUtils.cleanMusicTitle(player?.trackTitle) || Translation.tr("No media")
    readonly property string trackArtist: player?.trackArtist || Translation.tr("Unknown Artist")
    readonly property string identity: player ? (player.identity ?? "") : ""

    readonly property string artSource: CoverArt.source(root.artUrl)

    property string activeLyricText: ""
    property real lyricOpacity: 1.0
    property real lyricYOffset: 0.0

    property string displayArtist: root.trackArtist
    property real titleOpacity: 1.0
    property real titleYOffset: 0.0


    readonly property bool useDynamicColors: Config.options.media.dynamicAlbumColors && root.artSource !== ""

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

    /**
     * The text sits on the cover, so its colour follows the cover.
     *
     * A fixed onSurface read fine on dark art and vanished on a white one. The
     * quantizer's single colour is the cover's average; seen through the backdrop's
     * dark wash it is roughly what the text sits on, and the readable one of the
     * scheme's two on-colours is picked against it (opaque m3 colours: colLayer0
     * carries alpha and contrastRatio ignores it). `scrimColor` then pushes the
     * cover further away from the text, so mid-grey art cannot sit near both.
     */
    readonly property bool hasArt: root.artSource !== ""
    readonly property color artAverage: colorQuantizer.colors.length > 0
        ? colorQuantizer.colors[0] : Appearance.m3colors.m3surfaceContainer
    readonly property color textBackdrop: root.hasArt
        ? ColorUtils.mix(root.artAverage, "#000000", root.playing ? 0.85 : 0.72)
        : Appearance.m3colors.m3surfaceContainer
    readonly property color artTextColor: ColorUtils.mostReadable(root.textBackdrop,
        [Appearance.m3colors.m3onSurface, Appearance.m3colors.m3inverseOnSurface])
    readonly property bool lightText: ColorUtils.relativeLuminance(root.artTextColor) > 0.35
    readonly property color artSubtextColor: ColorUtils.transparentize(root.artTextColor, 0.22)
    readonly property color scrimColor: root.lightText ? "#000000" : "#ffffff"
    // Translucent overlays on the controls follow the text's side of the contrast.
    readonly property color overlayTint: root.lightText ? Qt.rgba(1, 1, 1, 1) : Qt.rgba(0, 0, 0, 1)

    /**
     * Lyrics belong to one player. LyricsService follows the active one, so every
     * other popup in the column (a browser tab next to the music app) printed the
     * active player's lines - and its current line in place of its own title.
     */
    readonly property bool showLyrics: !!root.player && LyricsService.activePlayer === root.player
        && LyricsService.hasSyncedLines


    readonly property string displaySongText: {
        if (root.showLyrics && LyricsService.statusText !== "") {
            return LyricsService.statusText;
        }
        return root.trackTitle;
    }

    onDisplaySongTextChanged: {
        lyricTransitionAnimation.stop();
        lyricTransitionAnimation.start();
    }

    SequentialAnimation {
        id: lyricTransitionAnimation
        NumberAnimation {
            target: root
            property: "lyricOpacity"
            to: 0.0
            duration: 120
            easing.type: Easing.OutQuad
        }
        PropertyAction {
            target: root
            property: "activeLyricText"
            value: root.displaySongText
        }
        NumberAnimation {
            target: root
            property: "lyricYOffset"
            from: 15
            to: 0.0
            duration: 180
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: root
            property: "lyricOpacity"
            to: 1.0
            duration: 180
            easing.type: Easing.OutCubic
        }
    }

    onTrackTitleChanged: {
        if (displayArtist === "") {
            displayArtist = root.trackArtist;
        }
    }

    Timer {
        running: root.playing && root.visible
        interval: 1000
        repeat: true
        onTriggered: if (root.player) root.player.positionChanged()
    }

    function getBarAmplitude(index) {
        if (!root.playing || root.visualizerPoints.length === 0)
            return 0.0;
        let indices = [2, 5, 9, 14, 20, 26, 32, 38];
        let idx = indices[index] || 0;
        if (idx >= root.visualizerPoints.length) {
            idx = root.visualizerPoints.length - 1;
        }
        let val = root.visualizerPoints[idx] / 1000.0;
        return Math.min(1.0, Math.max(0.0, val * 1.8));
    }

    implicitWidth: 380
    implicitHeight: 220

    Component.onCompleted: {
        LyricsService.initiliazeLyrics();
        root.activeLyricText = root.displaySongText;
    }

    Loader {
        active: root.showShadow
        sourceComponent: StyledRectangularShadow {
            target: mainBg
        }
    }

    Rectangle {
        id: mainBg
        anchors.fill: parent
        color: Appearance.colors.colLayer0
        radius: Appearance.rounding.windowRounding
        clip: true

        // Only the artwork is rounded-clipped. A layer on mainBg would also
        // rasterize the texts below, which come out soft at fractional offsets.
        Item {
            id: artClip
            anchors.fill: parent
            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: mainBg.width
                    height: mainBg.height
                    radius: mainBg.radius
                }
            }

            AndroidMediaArtwork {
                id: artwork
                anchors.fill: parent
                artSource: root.artUrl
                trackKey: JSON.stringify([root.player?.uniqueId ?? "", root.player?.trackTitle ?? "",
                    root.player?.trackArtist ?? "", root.player?.trackAlbum ?? ""])
                hasPlayer: !!root.player
                playing: root.playing
                wide: 1
            }
        }
        Connections {
            target: root.player
            function onPostTrackChanged(): void { artwork.requestArt(true); }
        }

        // Pushes the cover away from the text colour picked for it: dark under light
        // text, light under dark text. Strongest behind the title, thin at the edges.
        Rectangle {
            anchors.fill: parent
            visible: root.hasArt
            radius: mainBg.radius
            opacity: root.lightText ? 0.18 : 0.38
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: root.scrimColor }
                GradientStop { position: 0.7; color: ColorUtils.transparentize(root.scrimColor, 0.35) }
                GradientStop { position: 1.0; color: ColorUtils.transparentize(root.scrimColor, 0.7) }
            }
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            anchors.topMargin: 12
            anchors.bottomMargin: root.showBottomControls ? 10 : 12
            spacing: root.showBottomControls ? 6 : 8

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 24

                MaterialShape {
                    implicitWidth: 24
                    implicitHeight: 24
                    shapeString: "Cookie12Sided"
                    color: "transparent"
                    Layout.alignment: Qt.AlignLeft | Qt.AlignTop

                    Loader {
                        id: appIconLoader
                        anchors.fill: parent
                        active: root.player && root.player.desktopEntry !== ""
                        sourceComponent: IconImage {
                            implicitSize: Appearance.font.pixelSize.huge
                            source: Quickshell.iconPath(root.player ? root.player.desktopEntry : "audio-x-generic", "audio-x-generic")
                        }
                    }

                    Loader {
                        anchors.fill: parent
                        active: !appIconLoader.active
                        sourceComponent: MaterialSymbol {
                            anchors.centerIn: parent
                            text: "music_note"
                            iconSize: Appearance.font.pixelSize.smallest
                            color: root.artTextColor
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                RippleButton {
                    visible: root.showPinButton
                    implicitWidth: root.showPinButton ? 22 : 0
                    implicitHeight: root.showPinButton ? 22 : 0
                    Layout.alignment: Qt.AlignTop
                    colBackground: "transparent"
                    colBackgroundHover: ColorUtils.transparentize(root.overlayTint, 0.9)
                    colRipple: ColorUtils.transparentize(root.overlayTint, 0.85)
                    buttonRadius: Appearance.rounding.full

                    contentItem: MaterialSymbol {
                        text: "keep"
                        iconSize: 18
                        fill: GlobalStates.mediaControlsPinned ? 1 : 0
                        color: GlobalStates.mediaControlsPinned
                            ? (root.useDynamicColors ? root.blendedColors.colPrimary : Appearance.colors.colPrimary)
                            : root.artSubtextColor
                        horizontalAlignment: Text.AlignHCenter
                    }
                    onClicked: GlobalStates.mediaControlsPinned = !GlobalStates.mediaControlsPinned
                }

                RippleButton {
                    id: audioPill
                    implicitHeight: 24
                    leftPadding: 8
                    rightPadding: 8
                    Layout.alignment: Qt.AlignTop
                    colBackground: root.useDynamicColors ? root.blendedColors.colPrimaryContainer : Appearance.colors.colPrimaryContainer
                    colBackgroundHover: root.useDynamicColors ? root.blendedColors.colPrimaryContainerHover : Appearance.colors.colPrimaryContainerHover
                    colRipple: root.useDynamicColors ? root.blendedColors.colOnPrimaryContainer : Appearance.colors.colOnPrimaryContainer
                    buttonRadius: Appearance.rounding.full

                    readonly property string activeAudioDeviceName: Audio.sink ? (Audio.sink.description || "") : ""
                    readonly property string audioDeviceIcon: {
                        let desc = activeAudioDeviceName.toLowerCase();
                        if (desc.includes("headphone") || desc.includes("headset") || desc.includes("wired")) {
                            return "headphones";
                        }
                        return "volume_up";
                    }

                    onClicked: GlobalStates.openAudioOutputSettings()

                    contentItem: RowLayout {
                        id: audioPillLayout
                        spacing: 4

                        MaterialSymbol {
                            text: audioPill.audioDeviceIcon
                            iconSize: Appearance.font.pixelSize.smallest
                            color: root.useDynamicColors ? root.blendedColors.colOnPrimaryContainer : Appearance.colors.colOnPrimaryContainer
                        }

                        StyledText {
                            text: audioPill.activeAudioDeviceName !== "" ? audioPill.activeAudioDeviceName : Translation.tr("Audio")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.bold: true
                            color: root.useDynamicColors ? root.blendedColors.colOnPrimaryContainer : Appearance.colors.colOnPrimaryContainer
                            Layout.maximumWidth: 100
                            elide: Text.ElideRight
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 16

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 2

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true

                        Column {
                            id: lyricsContainer
                            width: parent.width
                            spacing: 0
                            y: lyricsContainer.baseY - lyricsContainer.rowHeight - lyricsContainer.scrollOffset
                            visible: root.showLyrics

                            readonly property int rowHeight: Math.floor(parent.height / 2.5)
                            readonly property real baseY: (parent.height - rowHeight) / 2
                            readonly property int targetCurrentIndex: root.showLyrics ? LyricsService.currentIndex : -1
                            property int lastIndex: -1
                            property bool isMovingForward: true
                            property real scrollOffset: 0
                            readonly property real animProgress: rowHeight > 0 ? Math.abs(scrollOffset) / rowHeight : 0

                            onTargetCurrentIndexChanged: {
                                if (targetCurrentIndex !== lastIndex && root.showLyrics) {
                                    isMovingForward = targetCurrentIndex > lastIndex;
                                    lastIndex = targetCurrentIndex;
                                    scrollAnim.stop();
                                    scrollOffset = isMovingForward ? -rowHeight : rowHeight;
                                    scrollAnim.start();
                                }
                            }

                            NumberAnimation {
                                id: scrollAnim
                                target: lyricsContainer
                                property: "scrollOffset"
                                to: 0
                                duration: 400
                                easing.type: Easing.OutQuart
                            }

                            Repeater {
                                model: 3

                                Item {
                                    required property int index
                                    property int lineOffset: index - 1
                                    property int actualIndex: lyricsContainer.targetCurrentIndex + lineOffset
                                    property bool isValidLine: root.showLyrics && actualIndex >= 0 && actualIndex < LyricsService.syncedLines.length

                                    width: parent.width
                                    height: lyricsContainer.rowHeight

                                    property int oldLineOffset: lyricsContainer.isMovingForward ? lineOffset + 1 : lineOffset - 1

                                    function getOpacityForOffset(offset) {
                                        let dist = Math.abs(offset);
                                        if (dist === 0) return 1.0;
                                        if (dist === 1) return 0.35;
                                        return 0.1;
                                    }
                                    property real targetOpacity: getOpacityForOffset(lineOffset)
                                    property real startOpacity: getOpacityForOffset(oldLineOffset)
                                    opacity: startOpacity + (targetOpacity - startOpacity) * (1.0 - lyricsContainer.animProgress)

                                    function getScaleForOffset(offset) {
                                        return Math.abs(offset) === 0 ? 1.0 : 0.9;
                                    }
                                    property real targetScale: getScaleForOffset(lineOffset)
                                    property real startScale: getScaleForOffset(oldLineOffset)
                                    scale: startScale + (targetScale - startScale) * (1.0 - lyricsContainer.animProgress)

                                    transformOrigin: Item.Center

                                    StyledText {
                                        anchors.fill: parent
                                        font.family: Appearance.font.family.main
                                        font.pixelSize: Appearance.font.pixelSize.large
                                        font.weight: Math.abs(lineOffset) === 0 ? Font.Black : Font.Medium
                                        font.styleName: Math.abs(lineOffset) === 0 ? "Rounded" : "Regular"
                                        font.hintingPreference: Font.PreferNoHinting
                                        color: root.artTextColor
                                        text: isValidLine ? LyricsService.syncedLines[actualIndex].text : ""
                                        horizontalAlignment: Text.AlignLeft
                                        verticalAlignment: Text.AlignVCenter
                                        elide: Text.ElideRight
                                        wrapMode: Text.WordWrap
                                        maximumLineCount: 2
                                    }
                                }
                            }
                        }

                        StyledText {
                            visible: !root.showLyrics
                            anchors.fill: parent
                            font.family: Appearance.font.family.main
                            font.pixelSize: Appearance.font.pixelSize.large
                            font.weight: Font.Black
                            font.styleName: "Rounded"
                            color: root.artTextColor
                            text: root.displaySongText
                            maximumLineCount: 3
                            wrapMode: Text.WordWrap
                            elide: Text.ElideRight
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        font.family: Appearance.font.family.main
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: root.artSubtextColor
                        text: root.displayArtist
                        maximumLineCount: 1
                        elide: Text.ElideRight
                    }
                }

                RippleButton {
                    id: playBtn
                    implicitWidth: 52
                    implicitHeight: 52
                    buttonRadius: 18
                    colBackground: root.useDynamicColors ? root.blendedColors.colPrimaryContainer : Appearance.colors.colPrimaryContainer
                    colBackgroundHover: root.useDynamicColors ? root.blendedColors.colPrimaryContainerHover : Appearance.colors.colPrimaryContainerHover
                    colRipple: root.useDynamicColors ? root.blendedColors.colPrimaryContainerActive : Appearance.colors.colPrimaryContainerActive
                    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter

                    onClicked: {
                        if (root.player) {
                            if (root.playing)
                                root.player.pause();
                            else
                                root.player.play();
                        }
                    }

                    contentItem: Item {
                        implicitWidth: 52
                        implicitHeight: 52
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: root.playing ? "pause" : "play_arrow"
                            iconSize: Appearance.font.pixelSize.hugeass
                            color: root.useDynamicColors ? root.blendedColors.colOnPrimaryContainer : Appearance.colors.colOnPrimaryContainer
                            fill: 1
                        }
                    }
                }
            }

            RowLayout {
                visible: root.showBottomControls
                Layout.fillWidth: true
                Layout.preferredHeight: root.showBottomControls ? 24 : 0
                spacing: 12
                Layout.alignment: Qt.AlignBottom

                RippleButton {
                    id: prevBtn
                    implicitWidth: 24
                    implicitHeight: 24
                    buttonRadius: 12
                    colBackground: "transparent"
                    colBackgroundHover: ColorUtils.transparentize(root.overlayTint, 0.9)
                    colRipple: root.useDynamicColors ? root.blendedColors.colPrimaryContainer : Appearance.colors.colPrimaryContainer

                    onClicked: {
                        if (root.player?.canGoPrevious) {
                            artwork.beginChange();
                            root.player.previous();
                        }
                    }

                    contentItem: Item {
                        implicitWidth: 24
                        implicitHeight: 24
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "skip_previous"
                            iconSize: Appearance.font.pixelSize.normal
                            fill: 1
                            color: {
                                if (!root.player || !root.player.canGoPrevious) {
                                    return root.artSubtextColor;
                                }
                                return root.artTextColor;
                            }
                            opacity: root.player && root.player.canGoPrevious ? 1.0 : 0.4
                        }
                    }
                }

                Item {
                    id: progressArea
                    Layout.fillWidth: true
                    Layout.preferredHeight: 16
                    Layout.alignment: Qt.AlignVCenter

                    Loader {
                        id: sliderLoader
                        anchors.fill: parent
                        active: root.player?.canSeek ?? false
                        sourceComponent: StyledSlider {
                            configuration: StyledSlider.Configuration.Wavy
                            animateWave: root.playing && root.visible
                            highlightColor: root.useDynamicColors ? root.blendedColors.colPrimaryContainer : Appearance.colors.colPrimaryContainer
                            trackColor: ColorUtils.transparentize(root.overlayTint, 0.8)
                            handleColor: root.useDynamicColors ? root.blendedColors.colPrimaryContainer : Appearance.colors.colPrimaryContainer
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
                        id: progressBarLoader
                        anchors {
                            verticalCenter: parent.verticalCenter
                            left: parent.left
                            right: parent.right
                        }
                        active: !!root.player && !sliderLoader.active
                        sourceComponent: StyledProgressBar {
                            wavy: root.player ? root.playing : false
                            animateWave: root.playing && root.visible
                            highlightColor: root.useDynamicColors ? root.blendedColors.colPrimaryContainer : Appearance.colors.colPrimaryContainer
                            trackColor: ColorUtils.transparentize(root.overlayTint, 0.8)
                            value: MprisController.trackProgressOf(root.player)
                        }
                    }
                }

                RippleButton {
                    id: nextBtn
                    implicitWidth: 24
                    implicitHeight: 24
                    buttonRadius: 12
                    colBackground: "transparent"
                    colBackgroundHover: ColorUtils.transparentize(root.overlayTint, 0.9)
                    colRipple: root.useDynamicColors ? root.blendedColors.colPrimaryContainer : Appearance.colors.colPrimaryContainer

                    onClicked: {
                        if (root.player?.canGoNext) {
                            artwork.beginChange();
                            root.player.next();
                        }
                    }

                    contentItem: Item {
                        implicitWidth: 24
                        implicitHeight: 24
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "skip_next"
                            iconSize: Appearance.font.pixelSize.normal
                            fill: 1
                            color: {
                                if (!root.player || !root.player.canGoNext) {
                                    return root.artSubtextColor;
                                }
                                return root.artTextColor;
                            }
                            opacity: root.player && root.player.canGoNext ? 1.0 : 0.4
                        }
                    }
                }
            }
        }
    }
}
