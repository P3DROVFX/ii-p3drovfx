pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import "WorkspaceShapes.js" as Shapes

/**
 * Every MaterialShape as a cell, columns stretched to fill the width. The chosen one
 * fills with the secondary container, rounds into a circle and draws its shape in
 * primary; the one under the pointer is named through `hoveredShape`.
 */
Item {
    id: root

    readonly property real gap: 8
    readonly property real minCell: 46
    readonly property real shapeRatio: 0.52

    property var shapes: Shapes.all
    property string currentValue: ""
    property string hoveredShape: ""

    signal selected(string value)

    readonly property int cols: Math.max(1, Math.floor((root.width + root.gap) / (root.minCell + root.gap)))
    readonly property real cell: Math.floor((root.width - root.gap * (root.cols - 1)) / root.cols)
    readonly property int rows: Math.ceil(root.shapes.length / root.cols)

    implicitHeight: root.rows * (root.cell + root.gap) - root.gap

    Flow {
        width: parent.width
        spacing: root.gap

        Repeater {
            model: root.shapes
            delegate: RippleButton {
                id: button

                required property string modelData
                readonly property bool chosen: root.currentValue === button.modelData

                width: root.cell
                height: root.cell
                toggled: button.chosen
                buttonRadius: button.chosen ? button.width / 2 : Appearance.rounding.small
                buttonRadiusPressed: Appearance.rounding.verysmall
                colBackground: Appearance.colors.colLayer2
                colBackgroundHover: Appearance.colors.colLayer2Hover
                colBackgroundActive: Appearance.colors.colLayer2Active
                colRipple: Appearance.colors.colLayer2Active
                colBackgroundToggled: Appearance.colors.colSecondaryContainer
                colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                colBackgroundToggledActive: Appearance.colors.colSecondaryContainerActive
                colRippleToggled: Appearance.colors.colSecondaryContainerActive
                onClicked: root.selected(button.modelData)
                onHoveredChanged: {
                    if (button.hovered)
                        root.hoveredShape = button.modelData;
                    else if (root.hoveredShape === button.modelData)
                        root.hoveredShape = "";
                }

                contentItem: Item {
                    MaterialShape {
                        anchors.centerIn: parent
                        width: Math.round(root.cell * root.shapeRatio)
                        height: width
                        shapeString: button.modelData
                        color: button.chosen ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                        Behavior on color {
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                        }
                    }
                }
            }
        }
    }
}
