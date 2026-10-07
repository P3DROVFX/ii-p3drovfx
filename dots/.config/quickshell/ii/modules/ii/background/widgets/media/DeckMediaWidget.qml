import QtQuick
import Quickshell.Widgets
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

/*
 * Deck Media (2x1). The cover as a square slab on the left with the player's
 * name tagged on it; on the right a monospace status caption, the title and
 * artist, an inline wavy seek line between its two times, and the transport:
 * two tonal circles around a wide primary play key.
 */
AbstractBackgroundWidget {
    id: root

    configEntryName: "media_deck"

    visibleWhenLocked: root.lockBehavior === "keep" || root.lockBehavior === "custom"
                    || root.lockBehavior === "center"
                    || root.lockBehavior === "lockOnly"
                    || (Config.options.lock.centerWidget === "media_deck")

    opacity: {
        if (root.lockBehavior === "lockOnly")
            return GlobalStates.screenLocked ? 1 : 0;
        if (GlobalStates.screenLocked && !visibleWhenLocked)
            return 0;
        return 1;
    }

    readonly property var options: Config.options?.background?.widgets?.media_deck ?? ({})
    readonly property real contentScale: (root.options?.widgetSize ?? 100) / 100.0
    implicitWidth: root.designWidth * contentScale
    implicitHeight: root.designHeight * contentScale

    // -- Geometry (design units) --
    readonly property real designWidth: 492
    readonly property real designHeight: 240
    readonly property real padding: 14
    readonly property real artSize: root.designHeight - root.padding * 2
    readonly property real columnGap: 16
    readonly property real buttonSize: 56
    readonly property real gap: 8
    readonly property real titleBoxHeight: 66
    readonly property real titleMaxSize: 32
    readonly property real titleMinSize: 18

    readonly property bool showPlayerChip: root.options?.showPlayerChip ?? true
    readonly property bool showTimes: root.options?.showTimes ?? true

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

            // -- Cover slab --
            ClippingRectangle {
                id: art
                x: root.padding
                y: root.padding
                width: root.artSize
                height: root.artSize
                radius: Appearance.rounding.small
                color: media.colInner

                MaterialSymbol {
                    anchors.centerIn: parent
                    visible: coverImage.status !== Image.Ready
                    text: "album"
                    fill: 1
                    iconSize: Math.round(root.artSize * 0.36)
                    color: media.colText
                }

                Image {
                    id: coverImage
                    anchors.fill: parent
                    source: media.artSource
                    sourceSize: Qt.size(Math.ceil(root.artSize * 2), Math.ceil(root.artSize * 2))
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                    opacity: status === Image.Ready ? 1 : 0

                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                }

                // Player tag
                Rectangle {
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    anchors.margins: 10
                    visible: root.showPlayerChip && media.playerName !== ""
                    width: Math.min(chipRow.implicitWidth + 20, parent.width - 20)
                    height: 30
                    radius: Appearance.rounding.full
                    color: media.colChip

                    Row {
                        id: chipRow
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 5

                        MaterialSymbol {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "graphic_eq"
                            iconSize: Appearance.font.pixelSize.normal
                            color: media.colOnChip
                        }

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.min(implicitWidth, root.artSize - 66)
                            text: media.playerName
                            color: media.colOnChip
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                    }
                }
            }

            // -- Info and transport --
            Item {
                id: panel
                anchors.left: art.right
                anchors.leftMargin: root.columnGap
                anchors.right: parent.right
                anchors.rightMargin: root.padding
                anchors.top: parent.top
                anchors.topMargin: root.padding
                anchors.bottom: parent.bottom
                anchors.bottomMargin: root.padding

                StyledText {
                    id: caption
                    anchors.top: parent.top
                    anchors.left: parent.left
                    text: media.isPlaying ? Translation.tr("NOW PLAYING") : (media.hasPlayer ? Translation.tr("PAUSED") : Translation.tr("IDLE"))
                    color: media.colSubtext
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: Appearance.font.pixelSize.smallest + 1
                    font.letterSpacing: 1.5
                }

                Text {
                    id: title
                    anchors.top: caption.bottom
                    anchors.topMargin: 4
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: root.titleBoxHeight
                    text: media.title
                    color: media.colText
                    font.family: Appearance.font.family.main
                    font.pixelSize: root.titleMaxSize
                    font.variableAxes: ({ "wght": 680, "wdth": 88, "ROND": 100 })
                    fontSizeMode: Text.Fit
                    minimumPixelSize: root.titleMinSize
                    wrapMode: Text.Wrap
                    elide: Text.ElideRight
                    lineHeight: 0.95
                    verticalAlignment: Text.AlignTop
                    renderType: Text.QtRendering
                }

                StyledText {
                    id: artist
                    y: title.y + Math.min(title.height, title.contentHeight) + 2
                    anchors.left: parent.left
                    anchors.right: parent.right
                    text: media.artist
                    color: media.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.small
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }

                Item {
                    id: seekRow
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: buttons.top
                    anchors.bottomMargin: 10
                    height: Math.max(seekBar.implicitHeight, 20)

                    StyledText {
                        id: positionLabel
                        visible: root.showTimes
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: media.positionText
                        color: media.colText
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }

                    MediaSeekBar {
                        id: seekBar
                        anchors.left: root.showTimes ? positionLabel.right : parent.left
                        anchors.leftMargin: root.showTimes ? 8 : 0
                        anchors.right: root.showTimes ? lengthLabel.left : parent.right
                        anchors.rightMargin: root.showTimes ? 8 : 0
                        anchors.verticalCenter: parent.verticalCenter
                        source: media
                    }

                    StyledText {
                        id: lengthLabel
                        visible: root.showTimes
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: media.lengthText
                        color: media.colSubtext
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
                }

                Item {
                    id: buttons
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: root.buttonSize

                    MediaControlButton {
                        id: previousButton
                        anchors.left: parent.left
                        width: root.buttonSize
                        height: root.buttonSize
                        enabled: media.player?.canGoPrevious ?? false
                        symbol: "skip_previous"
                        colFill: media.colTonal
                        colContent: media.colOnTonal
                        onClicked: media.previous()
                    }

                    MediaControlButton {
                        anchors.left: previousButton.right
                        anchors.leftMargin: root.gap
                        anchors.right: nextButton.left
                        anchors.rightMargin: root.gap
                        height: root.buttonSize
                        enabled: media.hasPlayer
                        symbol: media.isPlaying ? "pause" : "play_arrow"
                        symbolSize: 30
                        colFill: media.colAccent
                        colContent: media.colOnAccent
                        restRadius: media.isPlaying ? Appearance.rounding.normal : Appearance.rounding.full
                        onClicked: media.togglePlaying()
                    }

                    MediaControlButton {
                        id: nextButton
                        anchors.right: parent.right
                        width: root.buttonSize
                        height: root.buttonSize
                        enabled: media.player?.canGoNext ?? false
                        symbol: "skip_next"
                        colFill: media.colTonal
                        colContent: media.colOnTonal
                        onClicked: media.next()
                    }
                }
            }
        }
    }
}
