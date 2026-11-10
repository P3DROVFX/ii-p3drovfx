pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Widgets
import qs.modules.common
import qs.modules.common.widgets

/**
 * `trace` variant of the Sculpt system monitor — a ticker card per metric.
 *
 * Each metric is a card with its recent history drawn behind the number, the
 * trace cropped by the card's corners, so the card says both "now" (the number,
 * black and condensed) and "lately" (the shape behind it). Metrics without a
 * history (disk, temperature) keep a level instead: the card fills up to the
 * value. A caption in spaced capitals names the metric; past its threshold the
 * card moves to the error container.
 */
Item {
    id: root

    property bool vertical: false
    property real thickness: 32
    property BarWidgetPalette tones
    property bool hovered: false
    property var keys: []
    property var metricFor: function (key) { return null; }

    readonly property real margin: 10

    BarWidgetPalette {
        id: alertTones
        colorMode: "alert"
    }

    implicitWidth: root.vertical ? root.thickness : cards.implicitWidth
    implicitHeight: root.vertical ? cards.implicitHeight : root.thickness

    Grid {
        id: cards
        anchors.centerIn: parent
        columns: root.vertical ? 1 : Math.max(1, root.keys.length)
        spacing: 4

        Repeater {
            model: root.keys

            delegate: ClippingRectangle {
                id: card
                required property string modelData
                readonly property var m: root.metricFor(card.modelData) ?? ({})
                readonly property BarWidgetPalette cardTones: card.m.warn ? alertTones : root.tones
                readonly property var history: card.m.history ?? []

                // Sized from what it holds, with the same margin on both sides; a
                // floor keeps short readings wide enough for the trace to read.
                width: root.vertical ? root.thickness : Math.max(Math.round(root.thickness * 1.6), reading.implicitWidth + 2 * root.margin)
                height: root.vertical ? reading.implicitHeight + 12 : root.thickness
                radius: Appearance.rounding.scale === 0 ? 0 : Math.round(root.thickness * 0.3)
                color: root.hovered ? card.cardTones.colBackgroundHover : card.cardTones.colBackground
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(card)
                }

                // Lately: the history, or a level when there is none.
                Graph {
                    visible: card.history.length > 1
                    anchors.fill: parent
                    anchors.topMargin: Math.round(parent.height * 0.18)
                    values: card.history
                    points: Math.min(30, card.history.length)
                    alignment: Graph.Alignment.Right
                    color: card.cardTones.colOnBackground
                    fillOpacity: 0.35
                    opacity: 0.3
                    onColorChanged: requestPaint()
                }

                Rectangle {
                    visible: card.history.length <= 1
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: Math.round(parent.height * (card.m.value ?? 0))
                    color: card.cardTones.colOnBackground
                    opacity: 0.14
                    Behavior on height {
                        enabled: !Appearance.reducedMotion
                        animation: Appearance.animation.elementMove.numberAnimation.createObject(parent)
                    }
                }

                // Now.
                Grid {
                    id: reading
                    anchors.centerIn: parent
                    columns: root.vertical ? 1 : 2
                    columnSpacing: 4
                    rowSpacing: -2
                    horizontalItemAlignment: Grid.AlignHCenter
                    verticalItemAlignment: Grid.AlignVCenter

                    StyledText {
                        text: String(card.m.label ?? "").toUpperCase()
                        color: card.cardTones.colOnBackground
                        opacity: 0.8
                        font.family: Appearance.font.family.main
                        font.pixelSize: 8
                        font.letterSpacing: 0.8
                        font.variableAxes: ({
                            "wght": 800,
                            "wdth": 110,
                            "ROND": 0
                        })
                    }

                    StyledText {
                        text: (card.m.text ?? "--") + (root.vertical ? "" : (card.m.unit ?? ""))
                        color: card.cardTones.colOnBackground
                        font.family: Appearance.font.family.main
                        font.pixelSize: Math.round(root.thickness * (root.vertical ? 0.46 : 0.6))
                        font.variableAxes: ({
                            "wght": 900,
                            "wdth": 70,
                            "ROND": 100
                        })
                        font.features: ({
                            "tnum": 1
                        })
                    }
                }
            }
        }
    }
}
