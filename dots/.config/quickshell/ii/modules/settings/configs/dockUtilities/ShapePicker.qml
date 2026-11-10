import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * Pick a Material shape by name: every shape drawn as itself. The chosen one
 * stands on a filled plate in primary; the rest are quiet outlines of colour
 * on the pane. Emits `picked(name)`.
 */
Flow {
    id: picker

    property string current: ""
    property real cell: 52
    signal picked(string name)

    readonly property var names: ["Circle", "Square", "Slanted", "Arch", "Fan", "Arrow", "SemiCircle",
        "Oval", "Pill", "Triangle", "Diamond", "ClamShell", "Pentagon", "Gem", "Sunny", "VerySunny",
        "Cookie4Sided", "Cookie6Sided", "Cookie7Sided", "Cookie9Sided", "Cookie12Sided", "Ghostish",
        "Clover4Leaf", "Clover8Leaf", "Burst", "SoftBurst", "Boom", "SoftBoom", "Flower", "Puffy",
        "PuffyDiamond", "Bun", "Heart"]

    spacing: 6

    Repeater {
        model: picker.names
        delegate: RippleButton {
            id: option
            required property string modelData
            readonly property bool chosen: picker.current === option.modelData
            implicitWidth: picker.cell
            implicitHeight: picker.cell
            buttonRadius: Appearance.rounding.normal
            colBackground: option.chosen ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer2
            colBackgroundHover: option.chosen ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer2Hover
            colRipple: Appearance.colors.colLayer2Active
            onClicked: picker.picked(option.modelData)

            contentItem: Item {
                MaterialShape {
                    anchors.centerIn: parent
                    implicitSize: Math.round(picker.cell * 0.62)
                    shapeString: option.modelData
                    color: option.chosen ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
                    opacity: option.chosen ? 1 : 0.7
                }
            }

            StyledToolTip {
                text: option.modelData.replace(/([a-z])([A-Z0-9])/g, "$1 $2")
            }
        }
    }
}
