import QtQuick
import QtQuick.Shapes

Item {
    id: root

    enum CornerEnum { TopLeft, TopRight, BottomLeft, BottomRight }
    property var corner: RoundCorner.CornerEnum.TopLeft
    property alias leftVisualMargin: shape.anchors.leftMargin
    property alias topVisualMargin: shape.anchors.topMargin
    property alias rightVisualMargin: shape.anchors.rightMargin
    property alias bottomVisualMargin: shape.anchors.bottomMargin

    property int implicitSize: 25
    property color color: "#000000"

    implicitWidth: implicitSize
    implicitHeight: implicitSize

    property bool isTopLeft: corner === RoundCorner.CornerEnum.TopLeft
    property bool isBottomLeft: corner === RoundCorner.CornerEnum.BottomLeft
    property bool isTopRight: corner === RoundCorner.CornerEnum.TopRight
    property bool isBottomRight: corner === RoundCorner.CornerEnum.BottomRight
    property bool isTop: isTopLeft || isTopRight
    property bool isBottom: isBottomLeft || isBottomRight
    property bool isLeft: isTopLeft || isBottomLeft
    property bool isRight: isTopRight || isBottomRight

    property bool extendHorizontal: false
    property bool extendVertical: false

    readonly property int offsetX: (extendHorizontal && isLeft) ? 1 : 0
    readonly property int offsetY: (extendVertical && isTop) ? 1 : 0

    Shape {
        id: shape
        width: parent.width + (extendHorizontal ? 1 : 0)
        height: parent.height + (extendVertical ? 1 : 0)
        antialiasing: true
        anchors {
            top: root.isTop ? parent.top : undefined
            bottom: root.isBottom ? parent.bottom : undefined
            left: root.isLeft ? parent.left : undefined
            right: root.isRight ? parent.right : undefined

            topMargin: (extendVertical && root.isTop) ? -1 : 0
            bottomMargin: (extendVertical && root.isBottom) ? -1 : 0
            leftMargin: (extendHorizontal && root.isLeft) ? -1 : 0
            rightMargin: (extendHorizontal && root.isRight) ? -1 : 0
        }
        layer.enabled: true
        layer.smooth: true
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            id: shapePath
            strokeWidth: 0
            fillColor: root.color
            pathHints: ShapePath.PathSolid & ShapePath.PathNonIntersecting

            startX: switch (root.corner) {
                case RoundCorner.CornerEnum.TopLeft:
                case RoundCorner.CornerEnum.BottomLeft: return 0;
                case RoundCorner.CornerEnum.TopRight:
                case RoundCorner.CornerEnum.BottomRight: return root.implicitSize + (extendHorizontal ? 1 : 0);
            }
            startY: switch (root.corner) {
                case RoundCorner.CornerEnum.TopLeft:
                case RoundCorner.CornerEnum.TopRight: return 0;
                case RoundCorner.CornerEnum.BottomLeft:
                case RoundCorner.CornerEnum.BottomRight: return root.implicitSize + (extendVertical ? 1 : 0);
            }
            PathAngleArc {
                moveToStart: false
                centerX: (isLeft ? root.implicitSize : 0) + offsetX
                centerY: (isTop ? root.implicitSize : 0) + offsetY
                radiusX: root.implicitSize
                radiusY: root.implicitSize
                startAngle: switch (root.corner) {
                    case RoundCorner.CornerEnum.TopLeft: return 180;
                    case RoundCorner.CornerEnum.TopRight: return -90;
                    case RoundCorner.CornerEnum.BottomLeft: return 90;
                    case RoundCorner.CornerEnum.BottomRight: return 0;
                }
                sweepAngle: 90
            }
            PathLine {
                x: shapePath.startX
                y: shapePath.startY
            }
        }
    }

}
