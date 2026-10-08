pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import "WorkspacesCatalog.js" as Catalog

/**
 * Every Material shape as a small swatch to pick from. The chosen one fills with
 * primary; pointing at one grows it and reports it as `tried`.
 */
Flow {
    id: root

    property string currentValue: "Circle"
    property color colChosen: Appearance.colors.colPrimary
    property color colRest: Appearance.colors.colSecondaryContainer

    readonly property real cellSize: 44
    readonly property real shapeRatio: 0.62
    readonly property real hoverGrow: 1.18
    readonly property real cellRadius: Appearance.rounding.normal

    property string tried: ""

    signal selected(string value)

    spacing: 6

    Repeater {
        model: Catalog.SHAPES

        delegate: RippleButton {
            id: cell
            required property string modelData
            readonly property bool chosen: root.currentValue === cell.modelData

            implicitWidth: root.cellSize
            implicitHeight: root.cellSize
            buttonRadius: cell.chosen ? root.cellSize / 2 : root.cellRadius
            colBackground: cell.chosen ? Appearance.colors.colPrimaryContainer : "transparent"
            colBackgroundHover: cell.chosen ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colLayer1Hover
            colRipple: Appearance.colors.colLayer1Active
            onClicked: root.selected(cell.modelData)
            onHoveredChanged: {
                if (cell.hovered)
                    root.tried = cell.modelData;
                else if (root.tried === cell.modelData)
                    root.tried = "";
            }

            StyledToolTip {
                text: cell.modelData
            }

            contentItem: Item {
                MaterialShape {
                    anchors.centerIn: parent
                    implicitSize: root.cellSize * root.shapeRatio
                    shapeString: cell.modelData
                    color: cell.chosen ? root.colChosen : root.colRest
                    scale: cell.hovered ? root.hoverGrow : 1
                    Behavior on scale {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                }
            }
        }
    }
}
