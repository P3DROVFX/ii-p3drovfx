import QtQuick
import QtQuick.Effects
import qs.modules.common

// Existing AndroidMediaPopup artwork, vignette and shading palette. The tile
// supplies clipping and opacity while resizing; this keeps the settled look.
Item {
    id: root
    property string artSource: ""
    property bool playing: false
    readonly property bool artReady: artImage.status === Image.Ready
    // Strong-level blur: wider while paused, so the cover recedes behind the controls.
    readonly property real edgeBlur: playing ? 0.7 : 1.0
    // Room past the visible box for the blur to read real pixels, not transparency:
    // without it the strongest blur - the edges - fades into a dark fringe.
    readonly property real bleed: 40
    // The visible box inside each bled level, in that level's coordinates.
    readonly property rect visibleRect: Qt.rect(root.bleed, root.bleed, Math.max(1, root.width), Math.max(1, root.height))

    // The cover, sharp in the middle and blurred progressively towards every edge,
    // in one shader pass over three levels of the same picture. It replaced a
    // RadialGradient OpacityMask fading a sharp copy over a blurred one, which
    // only reached the edges as an ellipse and ghosted the picture in between.
    Item {
        anchors.fill: parent
        visible: root.artSource !== ""

        Image {
            id: artImage
            x: -root.bleed
            y: -root.bleed
            width: root.width + 2 * root.bleed
            height: root.height + 2 * root.bleed
            source: root.artSource
            asynchronous: true
            fillMode: Image.PreserveAspectCrop
        }
        MultiEffect {
            id: mediumLevel
            anchors.fill: artImage
            source: artImage
            autoPaddingEnabled: false
            blurEnabled: true
            blurMax: 64
            blur: 0.35 * root.edgeBlur
        }
        MultiEffect {
            id: strongLevel
            anchors.fill: artImage
            source: artImage
            autoPaddingEnabled: false
            blurEnabled: true
            blurMax: 64
            blur: root.edgeBlur
            Behavior on blur {
                NumberAnimation { duration: 400; easing.type: Easing.OutCubic }
            }
        }

        // The three levels are only ever sampled, through sources that hide them
        // from the scene (a visible level would paint under the effect, see the
        // media popup "shadow" entry in DOC.md).
        //
        // The sources are hidden child items, not inline property values: a
        // parentless source is never told its window is gone, and keeps the levels
        // referencing it. Every PanelWindow deletes its QQuickWindow when hidden, so
        // the next show, or deleting the card, touched freed memory and crashed
        // (preceded by "Cannot use same item on different windows").
        ShaderEffectSource {
            id: artLevel
            visible: false
            sourceItem: artImage
            sourceRect: root.visibleRect
            hideSource: true
        }
        ShaderEffectSource {
            id: mediumSource
            visible: false
            sourceItem: mediumLevel
            sourceRect: root.visibleRect
            hideSource: true
        }
        ShaderEffectSource {
            id: strongSource
            visible: false
            sourceItem: strongLevel
            sourceRect: root.visibleRect
            hideSource: true
        }
        ShaderEffect {
            anchors.fill: parent
            property var source: artLevel
            property var mediumBlur: mediumSource
            property var strongBlur: strongSource
            readonly property real itemWidth: width
            readonly property real itemHeight: height
            readonly property real band: Math.min(width, height) * 0.42
            fragmentShader: Qt.resolvedUrl("shaders/radialEdgeBlur.frag.qsb")
        }
    }

        // The wash only exists to keep controls legible over cover art. With no
        // artwork it painted a black veil over the tile's own surface, which is
        // exactly what the empty 4x2 quick-toggle widget showed as "black background".
        Item {
            anchors.fill: parent
            visible: root.artSource !== ""
            opacity: root.playing ? 0.55 : 0.75

            Behavior on opacity {
                NumberAnimation {
                    duration: 400
                    easing.type: Easing.OutCubic
                }
            }

            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.0) }
                    GradientStop { position: 0.5; color: Qt.rgba(0, 0, 0, 0.05) }
                    GradientStop { position: 0.8; color: Qt.rgba(0, 0, 0, 0.25) }
                    GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.45) }
                }
            }

            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.3)
                opacity: root.playing ? 0.0 : 0.5

                Behavior on opacity {
                    NumberAnimation {
                        duration: 500
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }

}
