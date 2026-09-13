import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets
import qs
import qs.services
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.widgets
import qs.modules.common.functions
import "QuickToggleResize.js" as Resize

// Playback, cover and metadata keep their identity from compact to expanded.
// The source image is loaded once by Qt, independently of the grid footprint.
ClippingRectangle {
    id: root
    required property var tile
    readonly property var player: MprisController.activePlayer
    readonly property real tall: Resize.progress(height, tile.baseCellHeight, tile.baseCellHeight * 2 + tile.cellSpacing)
    readonly property real wide: Resize.progress(width, tile.baseCellWidth * 2 + tile.cellSpacing,
        tile.baseCellWidth * 4 + tile.cellSpacing * 3)
    readonly property real pad: tile.scaled(12)
    readonly property real controlSize: Resize.mix(tile.scaled(36), tile.scaled(44), tall)
    readonly property real compactPlayX: pad
    readonly property real squarePlayX: (width - controlSize) / 2
    readonly property real largePlayX: width - pad - controlSize
    readonly property real controlsY: Resize.mix((height - controlSize) / 2, height - pad - controlSize, tall)
    readonly property real metadataX: Resize.mix(pad + controlSize + tile.scaled(10), pad, tall)
    readonly property real metadataY: Resize.mix((height - metadata.height) / 2, pad, tall)
    readonly property bool hasLyrics: LyricsService.hasSyncedLines && LyricsService.statusText !== ""
    readonly property string artSource: MprisController.artUrl
    readonly property bool remoteArt: artSource !== "" && !artSource.startsWith("file://")
    readonly property bool useDynamicColors: Config.options.media.dynamicAlbumColors && artSource !== ""
    readonly property color largeControlColor: useDynamicColors ? blendedColors.colPrimaryContainer : Appearance.colors.colPrimaryContainer
    readonly property color largeControlText: useDynamicColors ? blendedColors.colOnPrimaryContainer : Appearance.colors.colOnPrimaryContainer
    readonly property color titleColor: ColorUtils.mix(remoteArt ? "white" : Appearance.colors.colOnLayer0,
        Appearance.colors.colOnSurface, 1 - wide)
    readonly property color artistColor: ColorUtils.mix(remoteArt ? ColorUtils.transparentize("white", 0.3) : Appearance.colors.colSubtext,
        Appearance.colors.colOnSurfaceVariant, 1 - wide)
    ColorQuantizer {
        id: colorQuantizer
        source: root.useDynamicColors && root.wide > 0 ? root.artSource : ""
        depth: 0
        rescaleSize: 1
    }
    AdaptedMaterialScheme {
        id: blendedColors
        color: ColorUtils.mix(colorQuantizer.colors[0] ?? Appearance.colors.colPrimary,
            Appearance.colors.colPrimaryContainer, 0.8)
    }
    color: ColorUtils.mix(Appearance.colors.colLayer2, Appearance.colors.colLayer0, 1 - wide)
    radius: Config.options.appearance.sharpMode ? 0 : Math.min(width / 2, height / 2, Appearance.rounding.large)

    Item {
        anchors.fill: parent
        opacity: 1 - root.wide
        visible: opacity > 0
        Image {
            id: artBackground
            anchors.fill: parent
            source: root.artSource
            asynchronous: true
            cache: true
            sourceSize: Qt.size(Math.ceil(root.tile.baseCellWidth * 4), Math.ceil(root.tile.baseCellHeight * 2))
            fillMode: Image.PreserveAspectCrop
            visible: status === Image.Ready
            opacity: 0.8
            layer.enabled: visible
            layer.effect: StyledBlurEffect { blurMax: 32 }
            Rectangle {
                anchors.fill: parent
                color: ColorUtils.transparentize(Appearance.colors.colLayer0, 0.6)
            }
        }
    }
    QuickToggleMediaBackdrop {
        anchors.fill: parent
        artSource: root.artSource
        playing: root.player?.isPlaying ?? false
        opacity: root.wide
        visible: opacity > 0
    }

    Item {
        anchors.fill: parent
        visible: !!root.player

        // One live button, even when the wide layout moves it to the right.
        RippleButton {
            id: playButton
            objectName: "quickToggleSharedPlay"
            x: Resize.mix(Resize.mix(root.compactPlayX, root.squarePlayX, root.tall), root.largePlayX, root.wide)
            y: Resize.mix(root.controlsY, (root.height - height) / 2, root.wide)
            width: root.controlSize
            height: width
            buttonRadius: Appearance.rounding.full
            colBackground: ColorUtils.mix(Appearance.colors.colPrimary, root.largeControlColor, 1 - root.wide)
            colBackgroundHover: ColorUtils.mix(Appearance.colors.colLayer1Hover,
                root.useDynamicColors ? blendedColors.colPrimaryContainerHover : Appearance.colors.colPrimaryContainerHover, 1 - root.wide)
            colRipple: ColorUtils.mix(Appearance.colors.colPrimaryActive,
                root.useDynamicColors ? blendedColors.colPrimaryContainerActive : Appearance.colors.colPrimaryContainerActive, 1 - root.wide)
            contentItem: MaterialSymbol {
                text: root.player?.isPlaying ? "pause" : "play_arrow"
                color: ColorUtils.mix(Appearance.colors.colOnPrimary, root.largeControlText, 1 - root.wide)
                fill: 1
                iconSize: Resize.mix(root.tile.scaled(22), root.tile.scaled(28), root.tall)
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
            onClicked: root.player?.togglePlaying()
        }

        QuickToggleMorphLayer {
            id: metadata
            objectName: "quickToggleSharedMediaLabels"
            x: root.metadataX
            y: Resize.mix(root.metadataY, root.pad + root.tile.scaled(28), root.wide)
            width: Math.max(0, Resize.mix(root.width - x - root.pad,
                playButton.x - x - root.pad, root.wide))
            height: title.implicitHeight + artist.implicitHeight
            reveal: 1 - (root.hasLyrics ? Resize.progress(root.wide, 0, 0.5) : 0)
            directionX: root.tile.resizeDirectionX
            directionY: root.tile.resizeDirectionY
            travel: root.tile.scaled(12)
            StyledText {
                id: title
                width: parent.width
                text: root.player?.trackTitle || Translation.tr("Untitled")
                color: root.titleColor
                font.pixelSize: root.tile.scaled(Appearance.font.pixelSize.normal)
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            StyledText {
                id: artist
                y: title.height
                width: parent.width
                text: root.player?.trackArtist || Translation.tr("Unknown Artist")
                color: root.artistColor
                font.pixelSize: root.tile.scaled(Appearance.font.pixelSize.small)
                elide: Text.ElideRight
            }
        }

        QuickToggleMorphLayer {
            x: root.pad
            y: root.pad + root.tile.scaled(28)
            width: Math.max(0, playButton.x - x - root.pad)
            height: Math.max(0, root.height - y - root.pad)
            reveal: root.hasLyrics ? Resize.progress(root.wide, 0.45, 1) : 0
            entering: true
            directionX: root.tile.resizeDirectionX
            directionY: root.tile.resizeDirectionY
            travel: root.tile.scaled(12)
            StyledText {
                anchors.fill: parent
                text: LyricsService.statusText
                color: Appearance.colors.colOnSurface
                font.pixelSize: root.tile.scaled(Appearance.font.pixelSize.large)
                font.weight: Font.DemiBold
                wrapMode: Text.WordWrap
                maximumLineCount: 3
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
            }
        }

        Repeater {
            model: 2
            QuickToggleMorphLayer {
                id: skip
                required property int index
                width: root.tile.scaled(32)
                height: width
                x: playButton.x + (index === 0 ? -width - root.tile.scaled(8) : playButton.width + root.tile.scaled(8))
                y: playButton.y + (playButton.height - height) / 2
                reveal: Resize.progress(root.tall, index === 0 ? 0.25 : 0.4, 1)
                    * (1 - Resize.progress(root.wide, 0, 0.5))
                entering: true
                directionX: root.tile.resizeDirectionX
                directionY: root.tile.resizeDirectionY
                travel: root.tile.scaled(10)
                RippleButton {
                    anchors.fill: parent
                    buttonRadius: Appearance.rounding.full
                    contentItem: MaterialSymbol {
                        text: skip.index === 0 ? "skip_previous" : "skip_next"
                        color: root.remoteArt ? "white" : Appearance.colors.colOnSecondaryContainer
                        iconSize: root.tile.scaled(Appearance.font.pixelSize.large)
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    onClicked: {
                        if (skip.index === 0) root.player?.previous();
                        else root.player?.next();
                    }
                }
            }
        }

        QuickToggleMorphLayer {
            x: root.pad
            y: root.pad
            width: Math.max(0, root.width - root.pad * 2)
            height: root.tile.scaled(24)
            reveal: Resize.progress(root.wide, 0.55, 1)
            entering: true
            directionX: root.tile.resizeDirectionX
            directionY: root.tile.resizeDirectionY
            travel: root.tile.scaled(10)
            MaterialSymbol {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "music_note"
                iconSize: root.tile.scaled(Appearance.font.pixelSize.large)
                color: Appearance.colors.colOnLayer2
            }
            RippleButton {
                anchors.right: parent.right
                height: parent.height
                width: Math.min(parent.width * 0.7, implicitWidth)
                buttonRadius: Appearance.rounding.full
                colBackground: root.largeControlColor
                colBackgroundHover: root.useDynamicColors ? blendedColors.colPrimaryContainerHover : Appearance.colors.colPrimaryContainerHover
                colRipple: root.useDynamicColors ? blendedColors.colOnPrimaryContainer : Appearance.colors.colOnPrimaryContainer
                contentItem: StyledText {
                    text: Audio.sink?.description || Translation.tr("Audio")
                    color: root.largeControlText
                    font.pixelSize: root.tile.scaled(Appearance.font.pixelSize.smallest)
                    elide: Text.ElideRight
                }
                onClicked: {
                    GlobalStates.openRightSidebar();
                    Qt.callLater(() => { GlobalStates.requestVolumeDialog = true; });
                }
            }
        }
    }

    Component.onCompleted: LyricsService.initiliazeLyrics()

    Column {
        anchors.centerIn: parent
        visible: !root.player
        spacing: root.tile.scaled(8)
        MaterialSymbol {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "music_note"
            iconSize: root.tile.scaled(Appearance.font.pixelSize.huge)
            color: Appearance.colors.colSubtext
        }
        StyledText {
            text: Translation.tr("No media")
            font.pixelSize: root.tile.scaled(Appearance.font.pixelSize.small)
            color: Appearance.colors.colSubtext
        }
    }
}
