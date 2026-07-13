import QtQuick
import qs
import qs.modules.common
import qs.modules.common.widgets

MaterialShape {
    id: root

    property bool toggled: !GlobalStates.sidebarRightOpen
    property bool vertical: false

    readonly property var circularShapes: [
        MaterialShape.Shape.Circle,
        MaterialShape.Shape.Cookie6Sided,
        MaterialShape.Shape.Cookie7Sided,
        MaterialShape.Shape.Cookie9Sided,
        MaterialShape.Shape.Cookie12Sided,
        MaterialShape.Shape.Clover8Leaf,
        MaterialShape.Shape.Flower,
        MaterialShape.Shape.Sunny,
        MaterialShape.Shape.SoftBurst,
        MaterialShape.Shape.SoftBoom
    ]

    implicitSize: (vertical ? Appearance.sizes.verticalBarWidth : Appearance.sizes.baseBarHeight) - 15
    color: toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colSecondaryContainerHover

    Component.onCompleted: {
        var idx = Math.floor(Math.random() * circularShapes.length);
        root.shape = circularShapes[idx];
    }
}
