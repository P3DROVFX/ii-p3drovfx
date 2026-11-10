pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * `bars` variant of the Sculpt system monitor — a fitness app's week chart.
 *
 * A pill on the family colour holding one rounded bar per metric, its
 * initial under it. The busiest metric's bar is drawn in full ink and wears a
 * sunburst on top, and that metric is read out beside the chart: its number large in the rounded title face, its name in
 * a slanted caption under it; past its threshold that readout sits on an
 * error-container chip. Drawn horizontally; a vertical bar turns it as a whole.
 */
Item {
    id: root

    property real thickness: 32
    property BarWidgetPalette tones
    property bool hovered: false
    property var keys: []
    property var metricFor: function (key) { return null; }

    readonly property real barHeight: root.thickness - 15
    readonly property string topKey: {
        let best = "";
        let bestValue = -1;
        for (const key of root.keys) {
            const value = root.metricFor(key)?.value ?? 0;
            if (value > bestValue) {
                bestValue = value;
                best = key;
            }
        }
        return best;
    }
    readonly property var busiest: root.metricFor(root.topKey) ?? ({})

    readonly property color ink: root.tones.colOnBackground

    // A warning chip at the end takes the pill's end padding for its own.
    readonly property bool warned: root.busiest.warn ?? false
    // The pill's round end needs more room than a flat padding before the chart.
    readonly property real lead: Math.round(root.thickness * 0.45)
    implicitWidth: row.implicitWidth + root.lead + (root.warned ? 4 : 12)
    implicitHeight: root.thickness

    Rectangle {
        id: pill
        anchors.fill: parent
        radius: Appearance.rounding.scale === 0 ? 0 : height / 2
        color: root.hovered ? root.tones.colBackgroundHover : root.tones.colBackground
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(pill)
        }
    }

    Row {
        id: row
        x: root.lead
        anchors.verticalCenter: parent.verticalCenter
        spacing: 7

        Row {
            id: chart
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3

            Repeater {
                model: root.keys

                delegate: Column {
                    id: column
                    required property string modelData
                    readonly property var m: root.metricFor(column.modelData) ?? ({})
                    readonly property bool highlighted: column.modelData === root.topKey

                    spacing: 1

                    Item {
                        width: 7
                        height: root.barHeight

                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: ColorUtils.transparentize(root.ink, 0.82)
                        }

                        Rectangle {
                            id: fill
                            anchors.bottom: parent.bottom
                            width: parent.width
                            property real level: Math.max(width, (column.m.value ?? 0) * parent.height)
                            Behavior on level {
                                enabled: !Appearance.reducedMotion
                                animation: Appearance.animation.elementMove.numberAnimation.createObject(fill)
                            }
                            height: fill.level
                            radius: width / 2
                            color: column.highlighted ? root.ink : ColorUtils.transparentize(root.ink, 0.5)
                            Behavior on color {
                                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(fill)
                            }
                        }

                        MaterialShape {
                            visible: column.highlighted
                            implicitSize: 11
                            shape: MaterialShape.Shape.Sunny
                            color: fill.color
                            x: (parent.width - width) / 2
                            y: Math.max(-3, parent.height - fill.height - height / 2 - 1)
                        }
                    }

                    StyledText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: String(column.m.label ?? "?").charAt(0).toUpperCase()
                        color: root.ink
                        opacity: column.highlighted ? 1 : 0.6
                        font.family: Appearance.font.family.main
                        font.pixelSize: 7
                        font.variableAxes: ({
                            "wght": 800,
                            "wdth": 100,
                            "ROND": 100
                        })
                    }
                }
            }
        }

        // The readout; over its threshold it sits on an error-container chip.
        Item {
            anchors.verticalCenter: parent.verticalCenter
            implicitWidth: readout.implicitWidth + (root.warned ? 16 : 0)
            implicitHeight: root.warned ? root.thickness - 4 : readout.implicitHeight

            Rectangle {
                anchors.fill: parent
                visible: root.warned
                radius: Appearance.rounding.scale === 0 ? 0 : height / 2
                color: Appearance.colors.colErrorContainer
            }

            Column {
                id: readout
                anchors.centerIn: parent
                spacing: -4

                Row {
                    StyledText {
                        id: topNumber
                        text: root.busiest.text ?? "--"
                        color: root.busiest.warn ? Appearance.colors.colOnErrorContainer : root.ink
                        font.family: Appearance.font.family.title
                        font.pixelSize: Math.round(root.thickness * 0.5)
                        font.variableAxes: ({
                            "wght": 800,
                            "ROND": 100
                        })
                        font.features: ({
                            "tnum": 1
                        })
                    }
                    StyledText {
                        anchors.baseline: topNumber.baseline
                        text: root.busiest.unit ?? ""
                        color: root.busiest.warn ? Appearance.colors.colOnErrorContainer : root.ink
                        opacity: 0.75
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.Black
                    }
                }

                StyledText {
                    text: Translation.tr("%1 · busiest").arg(String(root.busiest.label ?? ""))
                    color: root.busiest.warn ? Appearance.colors.colOnErrorContainer : root.ink
                    opacity: 0.72
                    font.family: Appearance.font.family.main
                    font.pixelSize: 9
                    font.variableAxes: ({
                        "wght": 420,
                        "wdth": 100,
                        "slnt": -10,
                        "ROND": 100
                    })
                }
            }
        }
    }
}
