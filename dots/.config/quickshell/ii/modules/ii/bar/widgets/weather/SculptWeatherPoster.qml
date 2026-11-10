pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * `poster` variant of Sculpt weather — the temperature as a poster numeral.
 *
 * Straight on the bar: the condition's icon, then the temperature as tall,
 * condensed digits whose weight is the warmth (hairline at -5 °C, black at
 * 35 °C; snapped steps, see `variableAxes.blend`), the degree sign set high in
 * the accent. Beside it two smaller voices: the condition slanted and light,
 * the city in spaced capitals.
 */
Item {
    id: root

    property bool vertical: false
    property real thickness: 32
    property BarWidgetPalette tones
    property bool hovered: false
    property url icon
    property string digits: "--"
    property real warmth: 0.5
    property string description: ""
    property string city: ""
    property bool showDetails: true

    readonly property bool detailed: root.showDetails && !root.vertical

    implicitWidth: root.vertical ? root.thickness : layout.implicitWidth + 4
    implicitHeight: root.vertical ? layout.implicitHeight + 4 : root.thickness

    Rectangle {
        anchors.fill: parent
        anchors.margins: -2
        radius: Appearance.rounding.scale === 0 ? 0 : Math.min(width, height) / 2
        color: ColorUtils.transparentize(root.tones.colBare, 0.92)
        opacity: root.hovered ? 1 : 0
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(parent)
        }
    }

    Grid {
        id: layout
        anchors.centerIn: parent
        columns: root.vertical ? 1 : 3
        columnSpacing: 5
        rowSpacing: 0
        horizontalItemAlignment: Grid.AlignHCenter
        verticalItemAlignment: Grid.AlignVCenter

        Image {
            source: root.icon
            sourceSize: Qt.size(Math.round(root.thickness * 0.56), Math.round(root.thickness * 0.56))
        }

        Item {
            implicitWidth: numeral.implicitWidth + (root.vertical ? 0 : degree.implicitWidth)
            implicitHeight: numeral.implicitHeight

            StyledText {
                id: numeral
                text: root.digits
                color: root.tones.colBare
                font.family: Appearance.font.family.main
                font.pixelSize: Math.round(root.thickness * (root.vertical ? 0.66 : 1.0))
                font.variableAxes: ({
                    "wght": Appearance.font.variableAxes.blend(200, 900, root.warmth),
                    "wdth": 30,
                    "ROND": 100
                })
                font.features: ({
                    "tnum": 1
                })
            }

            StyledText {
                id: degree
                visible: !root.vertical
                anchors.left: numeral.right
                anchors.top: numeral.top
                anchors.topMargin: Math.round(numeral.height * 0.16)
                text: "°"
                color: root.tones.colBareAccent
                font.family: Appearance.font.family.main
                font.pixelSize: Math.round(root.thickness * 0.5)
                font.variableAxes: ({
                    "wght": 800,
                    "ROND": 100
                })
            }
        }

        Column {
            visible: root.detailed
            spacing: 0

            StyledText {
                width: Math.min(implicitWidth, 110)
                text: root.description
                elide: Text.ElideRight
                color: root.tones.colBare
                font.family: Appearance.font.family.main
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.variableAxes: ({
                    "wght": 380,
                    "wdth": 100,
                    "slnt": -10,
                    "ROND": 100
                })
            }

            StyledText {
                width: Math.min(implicitWidth, 110)
                text: root.city.toUpperCase()
                elide: Text.ElideRight
                color: root.tones.colBareAccent
                font.family: Appearance.font.family.main
                font.pixelSize: 9
                font.letterSpacing: 1.2
                font.variableAxes: ({
                    "wght": 750,
                    "wdth": 115,
                    "ROND": 0
                })
            }
        }
    }
}
