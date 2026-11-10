pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common
import qs.modules.common.widgets

/**
 * `pressure` variant of the Sculpt system monitor — type under load.
 *
 * One pill on the family colour. Every number in it is set by the load it
 * reports: idle is light and wide, busy is black and condensed, so the row's
 * texture says which part of the machine is working. Both axes move in snapped
 * steps (see `variableAxes.blend`); each number keeps the footprint of its own
 * digits at the widest setting, so the bar only moves when a value gains or
 * loses a digit, never as the load changes.
 *
 * Horizontally the caption sits beside its number, on one line, so the pill
 * stays a single row; vertically the caption tops a smaller number. A metric
 * past its threshold gets an error-container chip of its own inside the pill.
 */
Item {
    id: root

    property bool vertical: false
    property real thickness: 32
    property BarWidgetPalette tones
    property bool hovered: false
    property var keys: []
    property var metricFor: function (key) { return null; }

    readonly property int numberSize: Math.round(root.thickness * (root.vertical ? 0.42 : 0.56))
    readonly property real padding: root.vertical ? 4 : 10
    readonly property bool sharp: Appearance.rounding.scale === 0

    implicitWidth: root.vertical ? root.thickness : cells.implicitWidth + root.padding * 2
    implicitHeight: root.vertical ? cells.implicitHeight + 12 : root.thickness

    Rectangle {
        id: pill
        anchors.fill: parent
        radius: root.sharp ? 0 : (root.vertical ? Math.round(root.thickness * 0.4) : root.thickness / 2)
        color: root.hovered ? root.tones.colBackgroundHover : root.tones.colBackground
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(pill)
        }
    }

    Grid {
        id: cells
        anchors.centerIn: parent
        columns: root.vertical ? 1 : Math.max(1, root.keys.length)
        columnSpacing: 4
        rowSpacing: 4

        Repeater {
            model: root.keys

            delegate: Item {
                id: cell
                required property string modelData
                readonly property var m: root.metricFor(cell.modelData) ?? ({})
                readonly property bool warn: cell.m.warn ?? false
                readonly property color ink: cell.warn ? Appearance.colors.colOnErrorContainer : root.tones.colOnBackground

                implicitWidth: root.vertical ? root.thickness - 6 : layout.implicitWidth + 12
                implicitHeight: root.vertical ? layout.implicitHeight + 6 : root.thickness - 8

                Rectangle {
                    anchors.fill: parent
                    radius: root.sharp ? 0 : Math.min(width, height) / 2
                    color: Appearance.colors.colErrorContainer
                    opacity: cell.warn ? 1 : 0
                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(parent)
                    }
                }

                Grid {
                    id: layout
                    anchors.centerIn: parent
                    columns: root.vertical ? 1 : 2
                    columnSpacing: 3
                    rowSpacing: -2
                    horizontalItemAlignment: Grid.AlignHCenter
                    verticalItemAlignment: Grid.AlignVCenter

                    StyledText {
                        text: String(cell.m.label ?? "").toUpperCase()
                        color: cell.ink
                        opacity: 0.78
                        font.family: Appearance.font.family.main
                        font.pixelSize: root.vertical ? 7 : 8
                        font.letterSpacing: 0.8
                        font.variableAxes: ({
                            "wght": 800,
                            "wdth": 110,
                            "ROND": 0
                        })
                    }

                    Item {
                        implicitWidth: widest.implicitWidth + (root.vertical ? 0 : unit.implicitWidth + 1)
                        implicitHeight: number.implicitHeight

                        // The same digits at the widest setting, for the footprint only.
                        StyledText {
                            id: widest
                            visible: false
                            text: number.text
                            font.family: Appearance.font.family.main
                            font.pixelSize: root.numberSize
                            font.variableAxes: ({
                                "wght": 900,
                                "wdth": 112,
                                "ROND": 100
                            })
                            font.features: ({
                                "tnum": 1
                            })
                        }

                        StyledText {
                            id: number
                            anchors.left: root.vertical ? undefined : parent.left
                            anchors.horizontalCenter: root.vertical ? parent.horizontalCenter : undefined
                            text: cell.m.text ?? "--"
                            color: cell.ink
                            font.family: Appearance.font.family.main
                            font.pixelSize: root.numberSize
                            font.variableAxes: ({
                                "wght": Appearance.font.variableAxes.blend(280, 900, cell.m.value ?? 0),
                                "wdth": Appearance.font.variableAxes.blend(112, 35, cell.m.value ?? 0),
                                "ROND": 100
                            })
                            font.features: ({
                                "tnum": 1
                            })
                        }

                        StyledText {
                            id: unit
                            visible: !root.vertical
                            anchors.left: number.right
                            anchors.leftMargin: 1
                            anchors.top: number.top
                            anchors.topMargin: Math.round(number.height * 0.2)
                            text: cell.m.unit ?? ""
                            color: cell.ink
                            opacity: 0.75
                            font.family: Appearance.font.family.main
                            font.pixelSize: 9
                            font.weight: Font.Black
                        }
                    }

                }
            }
        }
    }
}
