pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common
import qs.modules.common.widgets

/**
 * `media` variant of the Sculpt utility buttons — laid out like player controls.
 *
 * The middle button is the hero: a wide rounded square on the vivid tone, the
 * play button of the group. Its neighbours are smaller soft circles, so the row
 * has a centre of weight instead of a line of equals. A latched toggle among the
 * neighbours fills with the vivid tone; the hero, already vivid, rounds into a
 * full pill when it latches. Corners answer the pointer, never the size.
 */
Item {
    id: root

    property bool vertical: false
    property real thickness: 32
    property BarWidgetPalette tones
    property UtilButtonActions actionSet
    property var actions: []

    readonly property int heroIndex: Math.floor((root.actions.length - 1) / 2)
    readonly property real heroLength: Math.round(root.thickness * 1.55)
    readonly property real sideSize: root.thickness - 4
    readonly property bool sharp: Appearance.rounding.scale === 0

    implicitWidth: root.vertical ? root.thickness : row.implicitWidth
    implicitHeight: root.vertical ? row.implicitHeight : root.thickness

    Grid {
        id: row
        anchors.centerIn: parent
        columns: root.vertical ? 1 : Math.max(1, root.actions.length)
        spacing: 4
        horizontalItemAlignment: Grid.AlignHCenter
        verticalItemAlignment: Grid.AlignVCenter

        Repeater {
            model: root.actions

            delegate: Rectangle {
                id: button
                required property int index
                required property string modelData

                readonly property bool hero: button.index === root.heroIndex
                readonly property bool active: root.actionSet.activeFor(button.modelData)
                readonly property bool hovered: press.containsMouse
                readonly property real shortSide: button.hero ? root.thickness : root.sideSize

                readonly property real corner: {
                    if (root.sharp)
                        return 0;
                    if (!button.hero)
                        return button.shortSide / 2;
                    if (press.pressed)
                        return root.thickness * 0.22;
                    if (button.active)
                        return root.thickness / 2;
                    return button.hovered ? root.thickness * 0.42 : root.thickness * 0.32;
                }
                property real animatedCorner: button.corner
                Behavior on animatedCorner {
                    enabled: !Appearance.reducedMotion
                    animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(button)
                }

                width: root.vertical ? button.shortSide : (button.hero ? root.heroLength : button.shortSide)
                height: root.vertical ? (button.hero ? root.heroLength : button.shortSide) : button.shortSide
                radius: button.animatedCorner
                color: (button.hero || button.active)
                    ? (button.hovered ? root.tones.colBackgroundHover : root.tones.colBackground)
                    : (button.hovered ? root.tones.colBackgroundVariantHover : root.tones.colBackgroundVariant)
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(button)
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.actionSet.iconFor(button.modelData)
                    iconSize: Math.round(root.thickness * (button.hero ? 0.62 : 0.5))
                    fill: button.active || button.hero ? 1 : 0
                    color: (button.hero || button.active) ? root.tones.colOnBackground : root.tones.colOnBackgroundVariant
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
