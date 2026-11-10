pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common
import qs.modules.common.widgets

/**
 * `selector` variant of the Sculpt keyboard layout — a day selector of layouts.
 *
 * Every configured layout is a pill. The current one is wide, full height and
 * vivid, its code set bold; the others are shorter soft pills set light. A pill
 * under the pointer grows to full height, and a click on it switches straight
 * to that layout (the dispatcher asks `indexAt`). Switching hands the width and
 * the weight from one pill to the other.
 */
Item {
    id: root

    property bool vertical: false
    property real thickness: 32
    property BarWidgetPalette tones
    property var codes: []
    property int currentIndex: 0

    readonly property bool sharp: Appearance.rounding.scale === 0

    function indexAt(x: real, y: real): int {
        for (let i = 0; i < pills.count; i++) {
            const pill = pills.itemAt(i);
            if (pill && x >= pill.x && x <= pill.x + pill.width && y >= pill.y && y <= pill.y + pill.height)
                return i;
        }
        return -1;
    }

    implicitWidth: root.vertical ? root.thickness : row.implicitWidth
    implicitHeight: root.vertical ? row.implicitHeight : root.thickness

    Grid {
        id: row
        anchors.centerIn: parent
        columns: root.vertical ? 1 : Math.max(1, root.codes.length)
        spacing: 3
        horizontalItemAlignment: Grid.AlignHCenter
        verticalItemAlignment: Grid.AlignVCenter

        Repeater {
            id: pills
            model: root.codes

            delegate: Rectangle {
                id: pill
                required property int index
                required property string modelData

                readonly property bool current: pill.index === root.currentIndex
                readonly property bool hovered: hover.hovered

                property real weight: pill.current ? 1 : 0
                Behavior on weight {
                    enabled: !Appearance.reducedMotion
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(pill)
                }

                // Along the bar: the current pill is wider. Across it: the others
                // are shorter until the pointer reaches them.
                readonly property real along: label.implicitWidth + (pill.current ? 22 : 12)
                readonly property real across: pill.current || pill.hovered ? root.thickness : root.thickness - 8

                property real animatedAlong: root.vertical ? label.implicitHeight + (pill.current ? 14 : 8) : pill.along
                Behavior on animatedAlong {
                    enabled: !Appearance.reducedMotion
                    animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(pill)
                }
                property real animatedAcross: pill.across
                Behavior on animatedAcross {
                    enabled: !Appearance.reducedMotion
                    animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(pill)
                }

                width: root.vertical ? pill.animatedAcross : pill.animatedAlong
                height: root.vertical ? pill.animatedAlong : pill.animatedAcross
                radius: root.sharp ? 0 : Math.min(width, height) / 2
                color: pill.current
                    ? root.tones.colBackground
                    : (pill.hovered ? root.tones.colBackgroundVariantHover : root.tones.colBackgroundVariant)
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(pill)
                }

                HoverHandler {
                    id: hover
                }

                StyledText {
                    id: label
                    anchors.centerIn: parent
                    text: pill.modelData
                    color: pill.current ? root.tones.colOnBackground : root.tones.colOnBackgroundVariant
                    font.family: Appearance.font.family.main
                    font.pixelSize: Math.round(root.thickness * (pill.current ? 0.46 : 0.38))
                    font.variableAxes: ({
                        "wght": Appearance.font.variableAxes.blend(450, 850, pill.weight),
                        "wdth": 90,
                        "ROND": 100
                    })
                }
            }
        }
    }
}
