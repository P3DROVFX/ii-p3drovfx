import QtQuick
import QtQuick.Effects
import Quickshell.Widgets
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.background.overview
import qs.modules.ii.background.widgets

/*
 * Cover Media (1x2). The cover bleeds over the whole card. The title is set big
 * and wide over a scrim at the top with the artist on a chip; the bottom of the
 * cover melts into a blur that carries the transport as one connected button
 * group. No seek line: the cover is the widget.
 */
AbstractBackgroundWidget {
    id: root

    configEntryName: "media_cover"

    visibleWhenLocked: root.lockBehavior === "keep" || root.lockBehavior === "custom"
                    || root.lockBehavior === "center"
                    || root.lockBehavior === "lockOnly"
                    || (Config.options.lock.centerWidget === "media_cover")

    opacity: {
        if (root.lockBehavior === "lockOnly")
            return GlobalStates.screenLocked ? 1 : 0;
        if (GlobalStates.screenLocked && !visibleWhenLocked)
            return 0;
        return 1;
    }

    readonly property var options: Config.options?.background?.widgets?.media_cover ?? ({})
    readonly property real contentScale: (root.options?.widgetSize ?? 100) / 100.0
    implicitWidth: root.designWidth * contentScale
    implicitHeight: root.designHeight * contentScale

    // -- Geometry (design units) --
    readonly property real designWidth: 240
    readonly property real designHeight: 492
    readonly property real padding: 16
    readonly property real contentWidth: root.designWidth - root.padding * 2
    // The cover is drawn past the card on every side so the blur's falloff at
    // the image border lands outside the clip, not along the card's edge.
    readonly property real bleed: 40
    readonly property real titleBoxHeight: 150
    readonly property real titleMaxSize: 46
    readonly property real titleMinSize: 20
    readonly property real groupHeight: 60
    readonly property real groupGap: 3
    // Where the blur starts fading in and where it is fully on, as card fractions.
    readonly property real blurClearAt: 0.6
    readonly property real blurSolidAt: 0.8

    readonly property real blurStrength: Math.max(0, Math.min(100, root.options?.blurStrength ?? 70)) / 100
    readonly property bool showArtistChip: root.options?.artistChip ?? true

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

        ClippingRectangle {
            id: card
            anchors.fill: parent
            radius: Appearance.rounding.large
            color: WidgetColorScheme.tintBackground(media.colInner)

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }

            // -- No cover --
            MaterialSymbol {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: -20
                visible: !art.ready
                text: "music_note"
                fill: 1
                iconSize: 120
                color: ColorUtils.transparentize(media.colText, 0.6)
            }

            // -- The cover, full bleed --
            Image {
                id: art
                readonly property bool ready: status === Image.Ready && media.artSource !== ""
                x: -root.bleed
                y: -root.bleed
                width: root.designWidth + root.bleed * 2
                height: root.designHeight + root.bleed * 2
                source: media.artSource
                sourceSize: Qt.size(Math.ceil(width * 2), Math.ceil(height * 2))
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
                opacity: ready ? 1 : 0

                Behavior on opacity {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }
            }

            // -- Blur band: the same picture blurred, faded in towards the bottom --
            Item {
                anchors.fill: parent
                visible: art.ready && root.blurStrength > 0
                layer.enabled: visible
                layer.effect: EdgeFadeMask {
                    verticalAxis: true
                    startClear: root.blurClearAt
                    startSolid: root.blurSolidAt
                    endSolid: 1
                    endClear: 1.01
                }

                MultiEffect {
                    x: art.x
                    y: art.y
                    width: art.width
                    height: art.height
                    source: art
                    autoPaddingEnabled: false
                    blurEnabled: true
                    blurMax: 64
                    blur: root.blurStrength
                    saturation: 0.15
                }
            }

            // -- Scrims: the scheme's surface, so text and keys keep their contrast --
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: parent.height * 0.5
                gradient: Gradient {
                    GradientStop { position: 0.0; color: ColorUtils.transparentize(media.colCard, 0.12) }
                    GradientStop { position: 0.55; color: ColorUtils.transparentize(media.colCard, 0.6) }
                    GradientStop { position: 1.0; color: ColorUtils.transparentize(media.colCard, 1) }
                }
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: parent.height * (1 - root.blurClearAt)
                gradient: Gradient {
                    GradientStop { position: 0.0; color: ColorUtils.transparentize(media.colCard, 1) }
                    GradientStop { position: 1.0; color: ColorUtils.transparentize(media.colCard, 0.45) }
                }
            }

            // -- Title and artist --
            Text {
                id: title
                x: root.padding
                y: root.padding + 2
                width: root.contentWidth
                height: root.titleBoxHeight
                text: media.title
                color: media.colText
                font.family: Appearance.font.family.main
                font.pixelSize: root.titleMaxSize
                font.variableAxes: ({ "wght": 880, "wdth": 118, "ROND": 100, "opsz": 144 })
                fontSizeMode: Text.Fit
                minimumPixelSize: root.titleMinSize
                wrapMode: Text.Wrap
                elide: Text.ElideRight
                lineHeight: 0.88
                verticalAlignment: Text.AlignTop
                renderType: Text.QtRendering
            }

            Rectangle {
                id: artistChip
                x: root.padding
                y: title.y + Math.min(title.height, title.contentHeight) + 10
                width: Math.min(artistLabel.implicitWidth + 24, root.contentWidth)
                height: 30
                radius: Appearance.rounding.full
                color: root.showArtistChip ? media.colChip : "transparent"

                StyledText {
                    id: artistLabel
                    anchors.left: parent.left
                    anchors.leftMargin: root.showArtistChip ? 12 : 0
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, root.contentWidth - 24)
                    text: media.artist
                    color: root.showArtistChip ? media.colOnChip : media.colText
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.variableAxes: ({ "wght": 600, "wdth": 100, "ROND": 100 })
                    elide: Text.ElideRight
                }
            }

            // -- Transport: one connected group [ << ][   ▶   ][ >> ] --
            Item {
                id: group
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: root.padding
                height: root.groupHeight

                // Outer corners are pills; the joins open up while a segment is
                // pressed, and the middle one turns square while music plays.
                readonly property real outer: Appearance.rounding.full
                readonly property real join: Appearance.rounding.verysmall
                readonly property real sideWidth: 62

                CoverGroupButton {
                    id: previousKey
                    anchors.left: parent.left
                    width: group.sideWidth
                    height: parent.height
                    enabled: media.player?.canGoPrevious ?? false
                    symbol: "skip_previous"
                    colFill: media.colTonal
                    colContent: enabled ? media.colOnTonal : ColorUtils.transparentize(media.colOnTonal, 0.62)
                    leftCorner: group.outer
                    rightCorner: down ? group.outer : group.join
                    onClicked: media.previous()
                }

                CoverGroupButton {
                    anchors.left: previousKey.right
                    anchors.leftMargin: root.groupGap
                    anchors.right: nextKey.left
                    anchors.rightMargin: root.groupGap
                    height: parent.height
                    enabled: media.hasPlayer
                    symbol: media.isPlaying ? "pause" : "play_arrow"
                    symbolSize: 32
                    colFill: media.colAccent
                    colContent: media.colOnAccent
                    readonly property real corner: (down || !media.isPlaying) ? group.outer : Appearance.rounding.normal
                    leftCorner: corner
                    rightCorner: corner
                    onClicked: media.togglePlaying()
                }

                CoverGroupButton {
                    id: nextKey
                    anchors.right: parent.right
                    width: group.sideWidth
                    height: parent.height
                    enabled: media.player?.canGoNext ?? false
                    symbol: "skip_next"
                    colFill: media.colTonal
                    colContent: enabled ? media.colOnTonal : ColorUtils.transparentize(media.colOnTonal, 0.62)
                    leftCorner: down ? group.outer : group.join
                    rightCorner: group.outer
                    onClicked: media.next()
                }
            }
        }
    }

    // A segment of the connected group: the transport button with its two
    // sides' corners set apart and eased through one animated value each
    // (RippleButton keeps its own corner Behaviors for grouped layouts).
    component CoverGroupButton: MediaControlButton {
        id: segment
        // Over the cover a faded key lets the picture through; keep the fill
        // solid and let the glyph carry the disabled state instead.
        opacity: 1
        property real leftCorner: 0
        property real rightCorner: 0
        readonly property real cap: segment.height / 2
        // Capped before the ease, so a pill-to-join change animates over the
        // whole duration instead of idling above the cap and then snapping.
        property real leftAnimated: Math.min(segment.cap, segment.leftCorner)
        property real rightAnimated: Math.min(segment.cap, segment.rightCorner)
        Behavior on leftAnimated {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        Behavior on rightAnimated {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        topLeftRadius: segment.leftAnimated
        bottomLeftRadius: segment.leftAnimated
        topRightRadius: segment.rightAnimated
        bottomRightRadius: segment.rightAnimated
    }
}
