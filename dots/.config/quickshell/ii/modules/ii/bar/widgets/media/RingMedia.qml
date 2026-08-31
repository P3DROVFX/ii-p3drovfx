pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * `ring` media widget.
 *
 * The cover art sits *inside* the progress indicator rather than beside it, so
 * the artwork and "how far through the track we are" occupy one object instead
 * of two. Both are `Cookie9Sided`: the rim is that shape swept by the track
 * position, and the artwork is masked to the same silhouette one size down, so
 * the pair reads as one scalloped object rather than a circle inside a shape.
 * Title over artist to its right; synced lyrics take that block over when there
 * are any.
 *
 * Vertical drops to the ring alone. There is no room for a line of text in a
 * 44px column, and rotating one would be worse than not having it.
 */
MediaWidgetBase {
    id: root

    readonly property real ringSize: root.thickness
    readonly property real ringWeight: Math.max(3, Math.round(root.thickness * 0.11))
    readonly property real artSize: root.ringSize - root.ringWeight * 2
    readonly property real spacing: Math.round(root.thickness * 0.26)

    readonly property int textLength: Math.min(
        Math.max(titleMetrics.advanceWidth, artistMetrics.advanceWidth) + 8,
        root.maxSize)
    readonly property real contentLength: root.ringSize + root.spacing + root.textLength

    implicitWidth: !root.hasTrack ? 0 : root.vertical
        ? Appearance.sizes.verticalBarWidth
        : (root.showLyrics
            ? root.lyricsCustomSize
            : (root.useFixedSize ? root.customSize : root.contentLength))
    implicitHeight: !root.hasTrack ? 0 : root.vertical
        ? root.ringSize + 10
        : Appearance.sizes.baseBarHeight

    Behavior on implicitWidth {
        animation: Appearance.animation.barResize.numberAnimation.createObject(root)
    }

    TextMetrics {
        id: titleMetrics
        font.pixelSize: Appearance.font.pixelSize.smallie
        text: root.cleanedTitle
    }

    TextMetrics {
        id: artistMetrics
        font.pixelSize: Appearance.font.pixelSize.smallest
        text: root.trackArtist
    }

    Item {
        id: ringSlot
        width: root.ringSize
        height: root.ringSize
        anchors.verticalCenter: root.vertical ? undefined : parent.verticalCenter
        anchors.horizontalCenter: root.vertical ? parent.horizontalCenter : undefined
        anchors.verticalCenterOffset: 0
        anchors.left: root.vertical ? undefined : parent.left
        anchors.top: root.vertical ? parent.top : undefined
        anchors.topMargin: root.vertical ? 5 : 0

        // The unplayed rim: the full shape, dimmed.
        MaterialShape {
            anchors.centerIn: parent
            implicitSize: root.ringSize
            shape: MaterialShape.Shape.Cookie9Sided
            color: Appearance.colors.colPrimary
            opacity: 0.22
        }

        // The played rim. A `CircularProgress` can only ever draw an arc, so the
        // sweep is done the other way round: paint the whole shape, then reveal
        // the fraction of it the position has reached with a conical gradient
        // used as a mask. Hard stops either side of `progress` make it a wedge
        // rather than a fade.
        Item {
            id: rimInk
            anchors.fill: parent
            visible: false

            MaterialShape {
                anchors.centerIn: parent
                implicitSize: root.ringSize
                shape: MaterialShape.Shape.Cookie9Sided
                color: Appearance.colors.colPrimary
            }
        }

        Item {
            id: sweepMask
            anchors.fill: parent
            visible: false

            ConicalGradient {
                anchors.fill: parent
                // Zero degrees is 3 o'clock, so start the sweep at the top.
                angle: 270
                gradient: Gradient {
                    GradientStop {
                        position: 0
                        color: "white"
                    }
                    GradientStop {
                        position: Math.max(0.0001, root.progress)
                        color: "white"
                    }
                    GradientStop {
                        position: Math.min(1, Math.max(0.0001, root.progress) + 0.0001)
                        color: "transparent"
                    }
                    GradientStop {
                        position: 1
                        color: "transparent"
                    }
                }
            }
        }

        OpacityMask {
            anchors.fill: parent
            source: rimInk
            maskSource: sweepMask
        }

        // The artwork, one size down and cut to the same silhouette.
        Item {
            id: artSlot
            anchors.centerIn: parent
            width: root.artSize
            height: root.artSize

            MaterialShape {
                anchors.fill: parent
                shape: MaterialShape.Shape.Cookie9Sided
                color: Appearance.colors.colSecondaryContainer
            }

            Image {
                anchors.fill: parent
                source: root.artSource
                visible: root.artSource !== ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
                sourceSize.width: root.artSize * 2
                sourceSize.height: root.artSize * 2

                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: MaterialShape {
                        width: artSlot.width
                        height: artSlot.height
                        shape: MaterialShape.Shape.Cookie9Sided
                    }
                }
            }

            MaterialSymbol {
                anchors.centerIn: parent
                visible: root.artSource === "" || !root.playing
                fill: 1
                text: root.artSource === "" ? "music_note" : "pause"
                iconSize: Math.max(10, Math.round(root.artSize * 0.55))
                color: Appearance.colors.colOnSecondaryContainer
            }
        }
    }

    // ── Metadata, horizontal only ────────────────────────────────────────────
    ColumnLayout {
        id: metaColumn
        visible: !root.vertical && !root.showLyrics
        spacing: -2

        anchors.left: ringSlot.right
        anchors.leftMargin: root.spacing
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter

        StyledText {
            Layout.fillWidth: true
            text: root.cleanedTitle
            font.pixelSize: Appearance.font.pixelSize.smallie
            font.weight: Font.DemiBold
            elide: Text.ElideRight
            color: Appearance.colors.colOnLayer1
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.trackArtist !== ""
            text: root.trackArtist
            font.pixelSize: Appearance.font.pixelSize.smallest
            elide: Text.ElideRight
            color: Appearance.colors.colOnLayer1
            opacity: 0.7
        }
    }

    Loader {
        id: lyricsLoader
        active: root.showLyrics
        visible: active

        anchors.left: ringSlot.right
        anchors.leftMargin: root.spacing
        anchors.right: parent.right
        anchors.rightMargin: 4
        anchors.top: parent.top
        anchors.bottom: parent.bottom

        sourceComponent: root.lyricsStyle === "static" ? staticLyrics : scrollerLyrics
    }

    Component {
        id: staticLyrics

        LyricsStatic {
            horizontalAlignment: Text.AlignLeft
            verticalAlignment: Text.AlignVCenter
            color: Appearance.colors.colOnLayer1
        }
    }

    Component {
        id: scrollerLyrics

        LyricScroller {
            textAlign: "left"
            useGradientMask: root.useGradientMask
            halfVisibleLines: 1
            rowHeight: Math.max(16, Math.round(root.thickness * 0.62))
            defaultLyricsSize: Appearance.font.pixelSize.smallie
        }
    }
}
