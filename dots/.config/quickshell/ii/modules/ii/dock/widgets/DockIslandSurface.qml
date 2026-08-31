import QtQuick
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root

    property bool active: false
    property string islandKind: "single"
    property string dockPosition: "bottom"
    property real cornerRadius: Appearance.rounding.windowRounding + 12
    property color surfaceColor: Appearance.colors.colLayer0

    readonly property bool geometryReady: width > 0 && height > 0

    // Keep the delegate alive while its geometry settles so a mode toggle can
    // fade the surface cleanly without leaving a stale 1x1 capsule behind.
    visible: geometryReady || opacity > 0.01
    opacity: active && geometryReady ? 1.0 : 0.0

    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(root)
    }

    StyledRectangularShadow {
        target: surface
        visible: root.visible && root.opacity > 0.01
        z: -1
    }

    Rectangle {
        id: surface
        anchors.fill: parent
        color: root.surfaceColor
        radius: root.cornerRadius
        antialiasing: true
    }
}
