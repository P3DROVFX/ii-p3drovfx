import QtQuick
import qs.modules.common
import qs.modules.common.widgets

// Unified background for one "island" group in Hug style (barBackgroundStyle === 3).
// Connects to the screen edge with rect/concave/screen-rounded corners, instead of
// floating like the Float-style pill islands.
//
// Usage: anchor this item to the section it backs, set `edge` to the screen edge the
// bar is attached to, and `role` to first/middle/last along that edge.
Item {
    id: root

    property bool vertical: false
    property string edge: "top"      // "top" | "bottom" | "left" | "right"
    property string role: "first"    // "first" | "middle" | "last"
    property color fillColor: Appearance.colors.colLayer0
    property real outerRadius: Appearance.rounding.windowRounding
    property real screenCornerRadius: Appearance.rounding.screenRounding

    readonly property bool isFirst: root.role === "first"
    readonly property bool isLast:  root.role === "last"

    readonly property bool isEdgeTop: root.edge === "top"
    readonly property bool isEdgeBottom: root.edge === "bottom"
    readonly property bool isEdgeLeft: root.edge === "left"
    readonly property bool isEdgeRight: root.edge === "right"

    readonly property string firstSide: {
        if (root.isEdgeTop || root.isEdgeBottom) return "left";
        return "top";
    }
    readonly property string lastSide: {
        if (root.isEdgeTop || root.isEdgeBottom) return "right";
        return "bottom";
    }

    function isOuterCorner(corner) {
        const c = corner.toString().toLowerCase();
        if (c.includes(root.edge)) return false;                 // screen-edge side
        if (c.includes(firstSide) && !root.isFirst) return true; // faces previous group
        if (c.includes(lastSide)  && !root.isLast)  return true; // faces next group
        return false;                                            // outer physical corner
    }

    readonly property bool isVertical: root.isEdgeLeft || root.isEdgeRight

    readonly property real screenTopLeftRadius: 0
    readonly property real screenTopRightRadius: 0
    readonly property real screenBottomLeftRadius: 0
    readonly property real screenBottomRightRadius: 0

    Rectangle {
        anchors.fill: parent
        color: root.fillColor

        topLeftRadius:     root.screenTopLeftRadius     > 0 ? root.screenTopLeftRadius     : (root.isOuterCorner("topLeft")     ? root.outerRadius : 0)
        topRightRadius:    root.screenTopRightRadius    > 0 ? root.screenTopRightRadius    : (root.isOuterCorner("topRight")    ? root.outerRadius : 0)
        bottomLeftRadius:  root.screenBottomLeftRadius  > 0 ? root.screenBottomLeftRadius  : (root.isOuterCorner("bottomLeft")  ? root.outerRadius : 0)
        bottomRightRadius: root.screenBottomRightRadius > 0 ? root.screenBottomRightRadius : (root.isOuterCorner("bottomRight") ? root.outerRadius : 0)

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(root)
        }
    }

    // First-side concave corner: smooths the transition from screen edge to island side
    RoundCorner {
        id: firstCorner
        implicitSize: root.outerRadius
        color: root.fillColor
        extendHorizontal: false
        extendVertical: false

        corner: {
            if (root.isFirst) {
                if (root.isEdgeTop) return RoundCorner.CornerEnum.TopLeft;
                if (root.isEdgeBottom) return RoundCorner.CornerEnum.BottomLeft;
                if (root.isEdgeLeft) return RoundCorner.CornerEnum.TopLeft;
                return RoundCorner.CornerEnum.TopRight; // Right edge
            } else {
                if (root.isEdgeTop) return RoundCorner.CornerEnum.TopRight;
                if (root.isEdgeBottom) return RoundCorner.CornerEnum.BottomRight;
                if (root.isEdgeLeft) return RoundCorner.CornerEnum.BottomLeft;
                return RoundCorner.CornerEnum.BottomRight; // Right edge
            }
        }

        anchors {
            top: {
                if (root.isEdgeTop) return root.isFirst ? parent.bottom : parent.top;
                if (root.isEdgeBottom) return undefined;
                return root.isFirst ? parent.top : undefined; // Left and Right edges
            }
            bottom: {
                if (root.isEdgeTop) return undefined;
                if (root.isEdgeBottom) return root.isFirst ? parent.top : parent.bottom;
                return root.isFirst ? undefined : parent.top; // Left and Right edges
            }
            left: {
                if (root.isEdgeTop || root.isEdgeBottom) return root.isFirst ? parent.left : undefined;
                if (root.isEdgeLeft) return root.isFirst ? parent.right : parent.left;
                return undefined; // Right edge
            }
            right: {
                if (root.isEdgeTop || root.isEdgeBottom) return root.isFirst ? undefined : parent.left;
                if (root.isEdgeLeft) return undefined;
                return root.isFirst ? parent.left : parent.right; // Right edge
            }
        }

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(root)
        }
    }

    // Last-side concave corner: smooths the transition from screen edge to island side
    RoundCorner {
        id: lastCorner
        implicitSize: root.outerRadius
        color: root.fillColor
        extendHorizontal: false
        extendVertical: false

        corner: {
            if (root.isLast) {
                if (root.isEdgeTop) return RoundCorner.CornerEnum.TopRight;
                if (root.isEdgeBottom) return RoundCorner.CornerEnum.BottomRight;
                if (root.isEdgeLeft) return RoundCorner.CornerEnum.BottomLeft;
                return RoundCorner.CornerEnum.BottomRight; // Right edge
            } else {
                if (root.isEdgeTop) return RoundCorner.CornerEnum.TopLeft;
                if (root.isEdgeBottom) return RoundCorner.CornerEnum.BottomLeft;
                if (root.isEdgeLeft) return RoundCorner.CornerEnum.TopLeft;
                return RoundCorner.CornerEnum.TopRight; // Right edge
            }
        }

        anchors {
            top: {
                if (root.isEdgeTop) return root.isLast ? parent.bottom : parent.top;
                if (root.isEdgeBottom) return undefined;
                return root.isLast ? undefined : parent.bottom; // Left and Right edges
            }
            bottom: {
                if (root.isEdgeTop) return undefined;
                if (root.isEdgeBottom) return root.isLast ? parent.top : parent.bottom;
                return root.isLast ? parent.bottom : undefined; // Left and Right edges
            }
            left: {
                if (root.isEdgeTop || root.isEdgeBottom) return root.isLast ? undefined : parent.right;
                if (root.isEdgeLeft) return root.isLast ? parent.right : parent.left;
                return undefined; // Right edge
            }
            right: {
                if (root.isEdgeTop || root.isEdgeBottom) return root.isLast ? parent.right : undefined;
                if (root.isEdgeLeft) return undefined;
                return root.isLast ? parent.left : parent.right; // Right edge
            }
        }

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(root)
        }
    }
}
