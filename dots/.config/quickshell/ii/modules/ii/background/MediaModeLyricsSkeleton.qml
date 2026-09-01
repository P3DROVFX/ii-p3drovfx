import QtQuick
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import qs.modules.common
import qs.modules.common.functions

// Placeholder shown while the providers are still being queried. Deliberately
// mirrors MediaModeLyrics row for row — same rhythm, same distance blur, same
// edge fade — so the real lyrics land into the shape the eye already tracked
// instead of replacing a spinner in the middle of an empty column.
Item {
    id: root

    clip: true

    property real largeFontSize: Appearance.font.pixelSize.hugeass * 1.5
    property color activeColor: Appearance.colors.colPrimary
    property real focusedFontSizeMultiplier: 1.42
    property real rowSpacingFactor: 0.78
    property real nearBlurRadius: 10
    property real farBlurRadius: 32
    property real minimumRowOpacity: 0.24
    property real rowOpacityFalloff: 0.34
    property real edgeFadeFraction: 0.16
    property int shimmerDuration: 1500

    readonly property int halfVisibleLines: 2
    readonly property int visibleLineCount: halfVisibleLines * 2 + 1
    readonly property real layoutFontSize: largeFontSize * focusedFontSizeMultiplier
    readonly property real rowHeight: Math.max(layoutFontSize * 1.32,
        height / visibleLineCount * rowSpacingFactor)
    readonly property real horizontalPadding: nearBlurRadius + Appearance.font.pixelSize.normal
    readonly property int blurMaximum: Math.max(2, Math.ceil(farBlurRadius))
    // Uneven, like real lyric lines rather than a stack of identical bars.
    readonly property var barWidthFactors: [0.54, 0.9, 0.72, 0.96, 0.62]

    property real shimmerPhase: 0

    function blurForDistance(distanceInRows) {
        const distance = Math.max(0, distanceInRows);
        if (distance <= 1)
            return root.nearBlurRadius * distance;
        if (distance <= 2)
            return root.nearBlurRadius
                + (root.farBlurRadius - root.nearBlurRadius) * (distance - 1);
        return root.farBlurRadius;
    }

    // Staggered so the highlight travels down the column instead of pulsing
    // every row in lockstep.
    function shimmerPhaseFor(index) {
        return (root.shimmerPhase + index * 0.08) % 1;
    }

    NumberAnimation on shimmerPhase {
        // The host keeps every lyrics state loaded to cross-fade between them,
        // so the shimmer must stop paying for itself while hidden.
        running: root.visible
        loops: Animation.Infinite
        from: 0
        to: 1
        duration: root.shimmerDuration
    }

    Item {
        id: skeletonColumn

        anchors.fill: parent
        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: skeletonColumn.width
                height: skeletonColumn.height
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: root.edgeFadeFraction; color: "black" }
                    GradientStop { position: 1.0 - root.edgeFadeFraction; color: "black" }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }
        }

        Repeater {
            model: root.visibleLineCount

            delegate: Item {
                id: skeletonRow

                required property int index
                readonly property int distanceInRows: Math.abs(index - root.halfVisibleLines)
                readonly property bool focused: distanceInRows === 0

                width: skeletonColumn.width
                height: root.rowHeight
                y: root.height / 2 - root.rowHeight / 2
                    + (index - root.halfVisibleLines) * root.rowHeight
                opacity: Math.max(root.minimumRowOpacity,
                    1 - distanceInRows * root.rowOpacityFalloff)

                Item {
                    anchors.fill: parent
                    layer.enabled: true
                    layer.smooth: true
                    layer.effect: MultiEffect {
                        blurEnabled: true
                        blurMax: root.blurMaximum
                        blur: Math.min(1,
                            root.blurForDistance(skeletonRow.distanceInRows) / root.blurMaximum)
                    }

                    Rectangle {
                        id: skeletonBar

                        readonly property real phase: root.shimmerPhaseFor(skeletonRow.index)
                        readonly property color baseColor: skeletonRow.focused
                            ? ColorUtils.transparentize(root.activeColor, 0.55)
                            : ColorUtils.transparentize(Appearance.colors.colSubtext, 0.7)
                        readonly property color shimmerColor: skeletonRow.focused
                            ? ColorUtils.transparentize(root.activeColor, 0.15)
                            : ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.55)

                        anchors.centerIn: parent
                        width: (parent.width - root.horizontalPadding * 2)
                            * root.barWidthFactors[skeletonRow.index % root.barWidthFactors.length]
                        height: root.layoutFontSize * (skeletonRow.focused ? 0.74 : 0.54)
                        radius: height / 2

                        // The sweep is the gradient itself, so it follows the
                        // pill's rounding instead of needing a clipped overlay.
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop {
                                position: Math.max(0, skeletonBar.phase - 0.2)
                                color: skeletonBar.baseColor
                            }
                            GradientStop {
                                position: skeletonBar.phase
                                color: skeletonBar.shimmerColor
                            }
                            GradientStop {
                                position: Math.min(1, skeletonBar.phase + 0.2)
                                color: skeletonBar.baseColor
                            }
                        }
                    }
                }
            }
        }
    }
}
