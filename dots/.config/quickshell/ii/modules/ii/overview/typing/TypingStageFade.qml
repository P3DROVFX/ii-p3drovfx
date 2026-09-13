pragma ComponentBehavior: Bound

import QtQuick
import Qt5Compat.GraphicalEffects
import qs.modules.common

/**
 * Edge fade for a scrolling surface that sits on a translucent panel.
 *
 * ScrollEdgeFade paints the surface colour over each end, which only reads
 * correctly when that colour is opaque. The launcher's background is
 * `colBackgroundSurfaceContainer`, which is transparentized by the appearance
 * settings, so a band painted with it lands as a visibly lighter rectangle over
 * whatever is behind the panel.
 *
 * This fades the content's own alpha instead, so there is no colour to match,
 * and cross-fades a blurred copy in on the way out: the last row goes out of
 * focus before it goes out of sight.
 */
Item {
    id: root

    required property Item target
    /** Height of the faded band at each end, in pixels. */
    property real fadeSize: 40
    property bool blurEdges: false
    property real blurRadius: root.fadeSize * 0.55
    /** How far past an edge still counts as "there is more", in pixels. */
    property real edgeTolerance: 2

    anchors.fill: target

    readonly property real startGap: {
        const view = root.target;
        return view ? (view.contentY ?? 0) - ((view.originY ?? 0) - (view.topMargin ?? 0)) : 0;
    }
    readonly property real endGap: {
        const view = root.target;
        if (!view)
            return 0;
        return ((view.originY ?? 0) + (view.contentHeight ?? 0) + (view.bottomMargin ?? 0))
            - ((view.contentY ?? 0) + (view.height ?? 0));
    }
    readonly property bool fadeStart: root.startGap > root.edgeTolerance
    readonly property bool fadeEnd: root.endGap > root.edgeTolerance
    // Nothing scrolls out of view, so the surface is left exactly as it is and
    // no render target is allocated for it.
    readonly property bool active: root.fadeStart || root.fadeEnd
    readonly property real band: root.height > 0 ? Math.min(0.45, root.fadeSize / root.height) : 0

    ShaderEffectSource {
        id: stageSource
        anchors.fill: parent
        sourceItem: root.target
        live: true
        hideSource: root.active
        visible: false
    }

    FastBlur {
        id: stageBlur
        anchors.fill: parent
        source: stageSource
        radius: root.blurRadius
        visible: false
    }

    OpacityMask {
        anchors.fill: parent
        visible: root.active && root.blurEdges
        source: stageBlur
        maskSource: Rectangle {
            width: Math.max(1, root.width)
            height: Math.max(1, root.height)
            color: "transparent"
            gradient: Gradient {
                // A bump of blur inside each faded band, and nothing at all in
                // the band that is not fading.
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop {
                    position: root.band * 0.5
                    color: root.fadeStart ? Qt.rgba(1, 1, 1, 0.7) : "transparent"
                }
                GradientStop { position: root.band; color: "transparent" }
                GradientStop { position: 1.0 - root.band; color: "transparent" }
                GradientStop {
                    position: 1.0 - root.band * 0.5
                    color: root.fadeEnd ? Qt.rgba(1, 1, 1, 0.7) : "transparent"
                }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }
    }

    OpacityMask {
        anchors.fill: parent
        visible: root.active
        source: stageSource
        maskSource: Rectangle {
            width: Math.max(1, root.width)
            height: Math.max(1, root.height)
            color: "transparent"
            gradient: Gradient {
                GradientStop { position: 0.0; color: root.fadeStart ? "transparent" : "white" }
                GradientStop { position: root.band * 0.35; color: root.fadeStart ? "transparent" : "white" }
                GradientStop { position: root.band; color: "white" }
                GradientStop { position: 1.0 - root.band; color: "white" }
                GradientStop { position: 1.0 - root.band * 0.35; color: root.fadeEnd ? "transparent" : "white" }
                GradientStop { position: 1.0; color: root.fadeEnd ? "transparent" : "white" }
            }
        }
    }
}
