import QtQuick
import qs.modules.common.widgets

/**
 * A Material shape that stays sharp under the dock lens. MaterialShape is a
 * Canvas painted at its own size; this paints it `renderScale` times larger
 * and draws it scaled back down, so up to that magnification the lens shows
 * real pixels instead of a stretched texture. Morphs between shapes as
 * MaterialShape does.
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

    MaterialShape {
        id: canvas
        width: root.width * root._scale
        height: root.height * root._scale
        scale: 1 / root._scale
        transformOrigin: Item.TopLeft
        shape: root.shapeName.length > 0 ? (canvas.shapeMap[root.shapeName] ?? root.shape) : root.shape
        color: root.color
    }
}
