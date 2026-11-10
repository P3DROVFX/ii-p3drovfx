import QtQuick
import qs.modules.common.widgets

/**
 * A Material shape that stays sharp under the dock lens. MaterialShape is a
 * Canvas painted at its own size; this paints it `renderScale` times larger
 * and draws it scaled back down, so up to that magnification the lens shows
 * real pixels instead of a stretched texture. Morphs between shapes as
 * MaterialShape does.
 *
 * The scaled-down canvas is drawn through a mipmapped texture: a plain `scale`
 * samples a 2-3x larger texture bilinearly and leaves its edges jagged at rest.
 */
Item {
    id: root

    property var shape: MaterialShape.Shape.Circle
    // Or by name ("Cookie9Sided"…), as settings store it; wins over `shape`.
    property string shapeName: ""
    property color color: "transparent"
    property real renderScale: 1
    property real implicitSize: 0

    implicitWidth: root.implicitSize
    implicitHeight: root.implicitSize

    readonly property real _scale: Math.max(1, Math.min(3, root.renderScale))
    readonly property bool _oversampled: root._scale > 1

    MaterialShape {
        id: canvas
        width: root.width * root._scale
        height: root.height * root._scale
        shape: root.shapeName.length > 0 ? (canvas.shapeMap[root.shapeName] ?? root.shape) : root.shape
        color: root.color
    }

    ShaderEffectSource {
        anchors.fill: parent
        visible: root._oversampled
        sourceItem: root._oversampled ? canvas : null
        hideSource: root._oversampled
        mipmap: true
        smooth: true
    }
}
