pragma ComponentBehavior: Bound
import QtQuick
import Qt5Compat.GraphicalEffects
import qs.modules.common
import qs.modules.common.functions

// Frosted surface: a blurred crop of `backdrop` under a translucent tint.
// By default x/y map straight into the backdrop, so the glass must share its
// coordinate space (a sibling filling the same parent). Glass nested inside an
// animated container sets `backdropOffset` to its position in backdrop space.
//
// The crop is rendered at half resolution and blurred with a true gaussian.
// MultiEffect's large blur levels upsample into a visible square grid.
Item {
    id: root
    property Item backdrop: null
    property real radius: Appearance.rounding.verylarge
    property color color: ColorUtils.applyAlpha(Appearance.m3colors.m3scrim, 0.3)
    property real blurPadding: 48
    property real blurRadius: 22
    property point backdropOffset: Qt.point(x, y)

    Item {
        anchors.fill: parent
        visible: root.backdrop !== null && root.width > 0 && root.height > 0
        layer.enabled: visible
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: root.width
                height: root.height
                radius: root.radius
                antialiasing: true
            }
        }

        // Sampled with padding so the blur has real pixels at the edges
        // instead of fading into transparency.
        ShaderEffectSource {
            id: backdropCrop
            x: -root.blurPadding
            y: -root.blurPadding
            width: root.width + root.blurPadding * 2
            height: root.height + root.blurPadding * 2
            sourceItem: root.backdrop
            sourceRect: Qt.rect(root.backdropOffset.x - root.blurPadding, root.backdropOffset.y - root.blurPadding, width,
                                height)
            textureSize: Qt.size(Math.max(1, Math.round(width / 2)), Math.max(1, Math.round(height / 2)))
            smooth: true
            visible: false
        }
        GaussianBlur {
            anchors.fill: backdropCrop
            source: backdropCrop
            radius: root.blurRadius
            samples: root.blurRadius * 2 + 1
            transparentBorder: false
        }
    }
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: root.color
    }
}
