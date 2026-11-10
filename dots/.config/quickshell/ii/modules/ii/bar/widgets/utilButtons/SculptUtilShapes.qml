pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common
import qs.modules.common.widgets

/**
 * `shapes` variant of the Sculpt utility buttons — one expressive shape each.
 *
 * Every action has a shape of its own (the snip a four-sided cookie, the colour
 * picker a clover, dark mode a sun…), so the row reads as a set of distinct
 * tools rather than a row of identical dots. Each shape has a partner it morphs
 * into: under the pointer it takes that shape on the soft tone; once a toggle
 * latches it keeps it and fills with the vivid tone. Morphs, never spins.
 */
Item {
    id: root

    property bool vertical: false
    property real thickness: 32
    property BarWidgetPalette tones
    property UtilButtonActions actionSet
    property var actions: []

    // [rest, on] per action.
    readonly property var shapePairs: ({
        "snip": [MaterialShape.Shape.Cookie4Sided, MaterialShape.Shape.Cookie6Sided],
        "colorPicker": [MaterialShape.Shape.Clover4Leaf, MaterialShape.Shape.Clover8Leaf],
        "record": [MaterialShape.Shape.Cookie12Sided, MaterialShape.Shape.Square],
        "recordPause": [MaterialShape.Shape.Pill, MaterialShape.Shape.Cookie4Sided],
        "liveDraw": [MaterialShape.Shape.Flower, MaterialShape.Shape.SoftBurst],
        "keyboard": [MaterialShape.Shape.Gem, MaterialShape.Shape.Pentagon],
        "wallpaper": [MaterialShape.Shape.Arch, MaterialShape.Shape.Puffy],
        "mic": [MaterialShape.Shape.Ghostish, MaterialShape.Shape.Cookie7Sided],
        "darkMode": [MaterialShape.Shape.Sunny, MaterialShape.Shape.VerySunny],
        "performance": [MaterialShape.Shape.SoftBoom, MaterialShape.Shape.Boom],
        "phoneMirror": [MaterialShape.Shape.Puffy, MaterialShape.Shape.PuffyDiamond]
    })

    implicitWidth: root.vertical ? root.thickness : row.implicitWidth
    implicitHeight: root.vertical ? row.implicitHeight : root.thickness

    Grid {
        id: row
        anchors.centerIn: parent
        columns: root.vertical ? 1 : Math.max(1, root.actions.length)
        spacing: 3

        Repeater {
            model: root.actions

            delegate: MaterialShape {
                id: button
                required property string modelData

                readonly property var pair: root.shapePairs[button.modelData] ?? [MaterialShape.Shape.Circle, MaterialShape.Shape.Cookie9Sided]
                readonly property bool active: root.actionSet.activeFor(button.modelData)
                readonly property bool hovered: press.containsMouse

                implicitSize: root.thickness
                shape: (button.active || button.hovered) ? button.pair[1] : button.pair[0]
                color: button.active
                    ? (button.hovered ? root.tones.colBackgroundHover : root.tones.colBackground)
                    : (button.hovered ? root.tones.colBackgroundVariantHover : root.tones.colBackgroundVariant)
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(button)
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.actionSet.iconFor(button.modelData)
                    iconSize: Math.round(root.thickness * 0.47)
                    fill: button.active ? 1 : 0
                    color: button.active ? root.tones.colOnBackground : root.tones.colOnBackgroundVariant
                }

                SculptUtilPress {
                    id: press
                    key: button.modelData
                    actionSet: root.actionSet
                }
            }
        }
    }
}
