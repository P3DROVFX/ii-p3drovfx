pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * `tonal` media widget.
 *
 * A tonal card and nothing else: the cover art on a Material shape at the
 * leading end, and the title — or the synced lyrics — beside it.
 *
 * It carries no progress indicator on purpose. Two earlier attempts failed for
 * the same underlying reason: a fill sweeping the pill made the title
 * unreadable once the track was half over, and a rule along the bottom edge was
 * masked down to a stub by the pill's own curve. `ring` is the variant whose
 * job is showing position; this one's job is the card.
 */
MediaWidgetBase {
    id: root

    readonly property real badgeSize: Math.round(root.thickness * 0.76)
    readonly property real padding: Math.round(root.thickness * 0.16)
    readonly property real gap: Math.round(root.thickness * 0.22)

    readonly property int textLength: Math.min(titleMetrics.advanceWidth + 6, root.maxSize)
    readonly property real cardLength: root.vertical
        ? root.badgeSize + root.padding * 2
        : root.padding * 2 + root.badgeSize + root.gap + root.textLength

    implicitWidth: !root.hasTrack ? 0 : root.vertical
        ? Appearance.sizes.verticalBarWidth
        : (root.showLyrics
            ? root.lyricsCustomSize
            : (root.useFixedSize ? root.customSize : root.cardLength))
    implicitHeight: !root.hasTrack ? 0 : root.vertical
        ? root.cardLength
        : Appearance.sizes.baseBarHeight

    Behavior on implicitWidth {
        animation: Appearance.animation.barResize.numberAnimation.createObject(root)
    }

    TextMetrics {
        id: titleMetrics
        font.pixelSize: Appearance.font.pixelSize.smallie
        text: root.cleanedTitle
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: root.vertical ? root.thickness : parent.width
        height: root.vertical ? parent.height : root.thickness
        radius: Appearance.rounding.full
        color: Appearance.colors.colSecondaryContainer

        // `clip` is rectangular in QML, so a child's square corners would poke
        // out of the card's rounded ones. Masking to the card's own shape is
        // the only thing that actually rounds a child.
        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: card.width
                height: card.height
                radius: card.radius
            }
        }

        MaterialShape {
            id: artBadge
            implicitSize: root.badgeSize
            shape: MaterialShape.Shape.Cookie12Sided
            color: Appearance.colors.colPrimaryContainer

            anchors.left: root.vertical ? undefined : parent.left
            anchors.leftMargin: root.vertical ? 0 : root.padding
            anchors.verticalCenter: root.vertical ? undefined : parent.verticalCenter
            anchors.top: root.vertical ? parent.top : undefined
            anchors.topMargin: root.vertical ? root.padding : 0
            anchors.horizontalCenter: root.vertical ? parent.horizontalCenter : undefined

            Image {
                anchors.fill: parent
                source: root.artSource
                visible: root.artSource !== ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
                sourceSize.width: root.badgeSize * 2
                sourceSize.height: root.badgeSize * 2

                // Clipped to the badge's silhouette, so the artwork takes the
                // Material shape instead of sitting in a square on top of it.
                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: MaterialShape {
                        width: artBadge.width
                        height: artBadge.height
                        shape: MaterialShape.Shape.Cookie12Sided
                    }
                }
            }

            MaterialSymbol {
                anchors.centerIn: parent
                visible: root.artSource === "" || !root.playing
                fill: 1
                text: root.artSource === "" ? "music_note" : "pause"
                iconSize: Math.max(11, Math.round(root.badgeSize * 0.56))
                color: Appearance.colors.colOnPrimaryContainer
            }
        }

        StyledText {
            id: titleLabel
            visible: !root.vertical && !root.showLyrics
            anchors.left: artBadge.right
            anchors.leftMargin: root.gap
            anchors.right: parent.right
            anchors.rightMargin: root.padding
            anchors.verticalCenter: parent.verticalCenter
            text: root.cleanedTitle
            font.pixelSize: Appearance.font.pixelSize.smallie
            font.weight: Font.DemiBold
            elide: Text.ElideRight
            color: Appearance.colors.colOnSecondaryContainer
        }

        Loader {
            active: root.showLyrics
            visible: active
            anchors.left: artBadge.right
            anchors.leftMargin: root.gap
            anchors.right: parent.right
            anchors.rightMargin: root.padding
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            sourceComponent: root.lyricsStyle === "static" ? staticLyrics : scrollerLyrics
        }

    }

    Component {
        id: staticLyrics

        LyricsStatic {
            horizontalAlignment: Text.AlignLeft
            verticalAlignment: Text.AlignVCenter
            color: Appearance.colors.colOnSecondaryContainer
        }
    }

    Component {
        id: scrollerLyrics

        LyricScroller {
            textAlign: "left"
            useGradientMask: root.useGradientMask
            halfVisibleLines: 1
            rowHeight: Math.max(16, Math.round(root.thickness * 0.58))
            defaultLyricsSize: Appearance.font.pixelSize.smallie
        }
    }
}
