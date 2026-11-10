import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

/*
 * Poster Media (1x2). A tall card read top to bottom like a gig poster: the
 * cover cut to a Material shape, the title set big in condensed italic, then
 * the transport as a block of chunky controls - a labelled play pill beside
 * "previous", "next" beside the wavy seek line.
 */
AbstractBackgroundWidget {
    id: root

    configEntryName: "media_poster"

    visibleWhenLocked: root.lockBehavior === "keep" || root.lockBehavior === "custom"
                    || root.lockBehavior === "center"
                    || root.lockBehavior === "lockOnly"
                    || (Config.options.lock.centerWidget === "media_poster")

    opacity: {
        if (root.lockBehavior === "lockOnly")
            return GlobalStates.screenLocked ? 1 : 0;
        if (GlobalStates.screenLocked && !visibleWhenLocked)
            return 0;
        return 1;
    }

    readonly property var options: Config.options?.background?.widgets?.media_poster ?? ({})
    readonly property real contentScale: (root.options?.widgetSize ?? 100) / 100.0
    implicitWidth: root.designWidth * contentScale
    implicitHeight: root.designHeight * contentScale

    // -- Geometry (design units) --
    readonly property real designWidth: 240
    readonly property real designHeight: 492
    readonly property real padding: 14
    readonly property real contentWidth: root.designWidth - root.padding * 2
    readonly property real artSize: 212
    readonly property real titleBoxHeight: 84
    readonly property real buttonSize: 58
    readonly property real gap: 8
    readonly property real titleMaxSize: 64
    readonly property real titleMinSize: 22

    readonly property var artShape: MaterialShape.Shape[root.options?.artShape ?? "Puffy"] ?? MaterialShape.Shape.Puffy
    readonly property bool accentTitle: root.options?.accentTitle ?? true
    readonly property bool showPlayLabel: root.options?.showPlayLabel ?? true

    MediaPlayerSource {
        id: media
        dynamicColors: root.options?.dynamicAlbumColors ?? false
        active: root.visible && root.opacity > 0
        ignoreWindows: root.isPreview
    }

    Item {
        anchors.centerIn: parent
        width: root.designWidth
        height: root.designHeight
        scale: root.contentScale

        StyledRectangularShadow {
            target: card
            visible: Config.options.background.widgets.enableShadows ?? true
        }

        Rectangle {
            id: card
            anchors.fill: parent
            radius: Appearance.rounding.large
            color: WidgetColorScheme.tintBackground(media.colCard)

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }

            MediaShapedArt {
                id: art
                anchors.top: parent.top
                anchors.topMargin: root.padding
                anchors.horizontalCenter: parent.horizontalCenter
                width: root.artSize
                height: root.artSize
                source: media.artSource
                shape: root.artShape
                placeholderColor: media.colInner
                placeholderIconColor: media.colText
            }

            Text {
                id: title
                // The title and artist travel as one block, centred in what the
                // cover and the transport leave free.
                readonly property real blockHeight: Math.min(title.height, title.contentHeight) + 4 + artist.height
                readonly property real freeTop: art.y + art.height
                y: Math.max(title.freeTop + 8, Math.round(title.freeTop + (transport.y - title.freeTop - title.blockHeight) / 2))
                anchors.left: parent.left
                anchors.leftMargin: root.padding
                width: root.contentWidth
                height: root.titleBoxHeight
                text: media.title
                color: root.accentTitle ? media.colAccent : media.colText
                font.family: Appearance.font.family.main
                font.pixelSize: root.titleMaxSize
                font.variableAxes: ({ "wght": 820, "wdth": 52, "slnt": -10, "ROND": 0, "opsz": 144 })
                fontSizeMode: Text.Fit
                minimumPixelSize: root.titleMinSize
                wrapMode: Text.Wrap
                elide: Text.ElideRight
                lineHeight: 0.9
                verticalAlignment: Text.AlignTop
                renderType: Text.QtRendering
            }

            StyledText {
                id: artist
                // Under the fitted text, not the fit box: a one-line title leaves
                // the slack below the pair instead of between them.
                y: title.y + Math.min(title.height, title.contentHeight) + 4
                anchors.left: title.left
                width: root.contentWidth
                text: media.artist
                color: media.colSubtext
                font.family: Appearance.font.family.monospace
                font.pixelSize: Appearance.font.pixelSize.smallie
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            // -- Transport: [ PLAY ][ << ] over [ >> ][ seek ] --
            Item {
                id: transport
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: root.padding
                height: root.buttonSize * 2 + root.gap

                MediaControlButton {
                    id: playButton
                    anchors.left: parent.left
                    anchors.top: parent.top
                    width: parent.width - root.buttonSize - root.gap
                    height: root.buttonSize
                    enabled: media.hasPlayer
                    symbol: media.isPlaying ? "pause" : "play_arrow"
                    label: root.showPlayLabel ? (media.isPlaying ? Translation.tr("PAUSE") : Translation.tr("PLAY")) : ""
                    colFill: media.colAccent
                    colContent: media.colOnAccent
                    restRadius: media.isPlaying ? Appearance.rounding.normal : Appearance.rounding.full
                    onClicked: media.togglePlaying()
                }

                MediaControlButton {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    width: root.buttonSize
                    height: root.buttonSize
                    enabled: media.player?.canGoPrevious ?? false
                    symbol: "skip_previous"
                    colFill: media.colTonal
                    colContent: media.colOnTonal
                    onClicked: media.previous()
                }

                MediaControlButton {
                    id: nextButton
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    width: root.buttonSize
                    height: root.buttonSize
                    enabled: media.player?.canGoNext ?? false
                    symbol: "skip_next"
                    colFill: media.colTonal
                    colContent: media.colOnTonal
                    onClicked: media.next()
                }

                Column {
                    anchors.left: nextButton.right
                    anchors.leftMargin: root.gap + 2
                    anchors.right: parent.right
                    anchors.verticalCenter: nextButton.verticalCenter
                    spacing: 2

                    MediaSeekBar {
                        width: parent.width
                        source: media
                    }

                    Item {
                        width: parent.width
                        height: positionLabel.implicitHeight

                        StyledText {
                            id: positionLabel
                            anchors.left: parent.left
                            text: media.positionText
                            color: media.colText
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: Appearance.font.pixelSize.smaller
                        }

                        StyledText {
                            anchors.right: parent.right
                            text: media.lengthText
                            color: media.colSubtext
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: Appearance.font.pixelSize.smaller
                        }
                    }
                }
            }
        }
    }
}
