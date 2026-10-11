import QtQuick
import "shapes"
import "shapes/material-shapes.js" as MaterialShapes

/**
 * A Material 3 shape by name. `shapes/` is the shell's rounded-polygon library
 * (end-4/rounded-polygon-qmljs, Apache-2.0), copied in from the shell's
 * submodule when the theme is installed.
 */
ShapeCanvas {
    id: root
    property string shape: "Circle"
    property real implicitSize: 0
    implicitWidth: implicitSize
    implicitHeight: implicitSize
    polygonIsNormalized: true

    roundedPolygon: {
        const getter = MaterialShapes["get" + root.shape];
        return typeof getter === "function" ? getter() : MaterialShapes.getCircle();
    }
}
