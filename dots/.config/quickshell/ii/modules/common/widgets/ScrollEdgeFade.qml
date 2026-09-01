import QtQuick
import Qt5Compat.GraphicalEffects
import qs.modules.common
import qs.modules.common.functions

/**
 * The ends of a scrolling view, faded into the surface behind it.
 *
 * Each end is shown only while there is something past it, so a list that
 * fits gets no decoration at all. With `blurEdges` the fade also carries a
 * blurred copy of the view's own pixels, which is what keeps text from
 * appearing to be cut in half at the edge: it goes out of focus first and
 * out of sight after.
 */
Item {
    id: root
    z: 99
    required property Item target
    property real fadeSize: Appearance.m3colors.darkmode ? 40 : 20
    property color color: Appearance.colors.colLayer1Base
    property bool vertical: true
    /**
     * Whether the fade blurs what it is fading. Off by default: it costs a
     * live copy of the band per visible end, which is worth it on a
     * transcript and not on a short list of rows.
     */
    property bool blurEdges: false
    property real blurStrength: 0.9
    /**
     * How far past an edge counts as "there is more". `atYBeginning` and
     * `atYEnd` go false for a fraction of a pixel — a margin, a rounding, a
     * flick that settled just short — and the fade would sit there covering
     * a list that is already at its end.
     */
    property real edgeTolerance: 2

    anchors.fill: target

    /** Whether the view has anything to scroll at all. */
    readonly property bool overflowing: {
        const view = root.target;
        if (!view)
            return false;
        if (root.vertical)
            return (view.contentHeight ?? 0) > (view.height ?? 0) + root.edgeTolerance;
        return (view.contentWidth ?? 0) > (view.width ?? 0) + root.edgeTolerance;
    }

    /** How much is hidden before the start of the view, and after its end. */
    readonly property real startGap: {
        const view = root.target;
        if (!view)
            return 0;
        if (root.vertical)
            return (view.contentY ?? 0) - ((view.originY ?? 0) - (view.topMargin ?? 0));
        return (view.contentX ?? 0) - ((view.originX ?? 0) - (view.leftMargin ?? 0));
    }

    readonly property real endGap: {
        const view = root.target;
        if (!view)
            return 0;
        if (root.vertical)
            return ((view.originY ?? 0) + (view.contentHeight ?? 0) + (view.bottomMargin ?? 0)) - ((view.contentY ?? 0) + (view.height ?? 0));
        return ((view.originX ?? 0) + (view.contentWidth ?? 0) + (view.rightMargin ?? 0)) - ((view.contentX ?? 0) + (view.width ?? 0));
    }

    EndGradient {
        anchors {
            top: parent.top
            left: parent.left
            right: root.vertical ? parent.right : undefined
            bottom: root.vertical ? undefined : parent.bottom
        }
        atStart: true
        shown: root.overflowing && root.startGap > root.edgeTolerance
    }

    EndGradient {
        anchors {
            bottom: parent.bottom
            right: parent.right
            left: root.vertical ? parent.left : undefined
            top: root.vertical ? undefined : parent.top
        }
        atStart: false
        shown: root.overflowing && root.endGap > root.edgeTolerance
    }

    component EndGradient: Item {
        id: endGradient
        required property bool shown
        required property bool atStart
        /**
         * Gradient stops have to be written in ascending order, so the band
         * keeps its stops where they are and swaps the colours instead: the
         * edge of the view is the first stop at the top and the last one at
         * the bottom.
         */
        readonly property real midPosition: endGradient.atStart ? 0.55 : 0.45

        height: root.vertical ? root.fadeSize : (parent?.height ?? 0)
        width: root.vertical ? (parent?.width ?? 0) : root.fadeSize

        opacity: shown ? 1 : 0
        visible: opacity > 0
        Behavior on opacity {
            animation: Appearance?.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        Loader {
            // The blurred copy sits under the colour fade, so the two read as
            // one edge rather than as a blurred strip with a gradient on top.
            id: blurLoader
            anchors.fill: parent
            active: root.blurEdges && endGradient.visible

            sourceComponent: Item {
                ShaderEffectSource {
                    id: edgeSource
                    anchors.fill: parent
                    sourceItem: root.target
                    // Only the band itself is copied, never the whole view.
                    sourceRect: root.vertical
                        ? Qt.rect(0, endGradient.atStart ? 0 : Math.max(0, root.target.height - root.fadeSize), root.target.width, root.fadeSize)
                        : Qt.rect(endGradient.atStart ? 0 : Math.max(0, root.target.width - root.fadeSize), 0, root.fadeSize, root.target.height)
                    live: true
                    hideSource: false
                    visible: false
                }

                FastBlur {
                    id: edgeBlur
                    anchors.fill: parent
                    source: edgeSource
                    radius: root.fadeSize * root.blurStrength
                    visible: false
                }

                OpacityMask {
                    // Strongest against the edge and gone by the time the band
                    // ends, so the blur ramps in rather than switching on.
                    anchors.fill: parent
                    source: edgeBlur
                    maskSource: Rectangle {
                        width: Math.max(1, endGradient.width)
                        height: Math.max(1, endGradient.height)
                        color: "transparent"
                        gradient: Gradient {
                            orientation: root.vertical ? Gradient.Vertical : Gradient.Horizontal
                            GradientStop {
                                position: 0.0
                                color: endGradient.atStart ? "white" : "transparent"
                            }
                            GradientStop {
                                position: endGradient.midPosition
                                color: ColorUtils.transparentize("white", 0.45)
                            }
                            GradientStop {
                                position: 1.0
                                color: endGradient.atStart ? "transparent" : "white"
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            anchors.fill: parent
            color: "transparent"
            gradient: Gradient {
                orientation: root.vertical ? Gradient.Vertical : Gradient.Horizontal
                GradientStop {
                    position: 0.0
                    color: endGradient.atStart ? root.color : ColorUtils.transparentize(root.color)
                }
                GradientStop {
                    position: 1.0
                    color: endGradient.atStart ? ColorUtils.transparentize(root.color) : root.color
                }
            }
        }
    }
}
