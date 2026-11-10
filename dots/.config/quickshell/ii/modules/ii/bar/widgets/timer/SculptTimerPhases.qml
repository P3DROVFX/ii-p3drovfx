pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * `phases` variant of Sculpt timer — where you are in the cycle.
 *
 * Each readout is a card with three voices: the phase as a tiny display label
 * in wide black capitals (FOCUS, BREAK, the countdown's own name), under it a
 * segmented indicator, and beside them the time in the rounded title face. For
 * a pomodoro the indicator has one segment per pomodoro of the cycle — the ones
 * done are solid, the current one is wider and fills as it runs; anything else
 * gets a single segment that fills. A break turns the card to the other tone of
 * the pair.
 */
Item {
    id: root

    property real thickness: 32
    property BarWidgetPalette tones
    property var keys: []
    property var entryFor: function (key) { return null; }

    signal triggered(string key)

    implicitWidth: row.implicitWidth
    implicitHeight: root.thickness

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 5

        Repeater {
            model: root.keys

            delegate: Rectangle {
                id: readout
                required property string modelData
                readonly property var e: root.entryFor(readout.modelData) ?? ({})
                readonly property bool hovered: press.containsMouse
                readonly property bool relaxed: readout.e.relaxed ?? false
                readonly property color ink: readout.relaxed ? root.tones.colOnBackgroundVariant : root.tones.colOnBackground
                readonly property real segmentHeight: 4

                implicitWidth: content.implicitWidth + 22
                implicitHeight: root.thickness
                radius: Appearance.rounding.scale === 0 ? 0 : Math.round(root.thickness * 0.3)
                color: readout.relaxed
                    ? (readout.hovered ? root.tones.colBackgroundVariantHover : root.tones.colBackgroundVariant)
                    : (readout.hovered ? root.tones.colBackgroundHover : root.tones.colBackground)
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(readout)
                }

                Row {
                    id: content
                    anchors.centerIn: parent
                    spacing: 8

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 3

                        StyledText {
                            width: Math.min(implicitWidth, 84)
                            text: String(readout.e.label ?? "").toUpperCase()
                            elide: Text.ElideRight
                            color: readout.ink
                            font.family: Appearance.font.family.main
                            font.pixelSize: 9
                            font.letterSpacing: 0.8
                            font.variableAxes: ({
                                "wght": 900,
                                "wdth": 125,
                                "ROND": 0
                            })
                        }

                        Row {
                            spacing: 3

                            Repeater {
                                model: (readout.e.cycles ?? 0) > 0 ? readout.e.cycles : 1

                                delegate: Rectangle {
                                    id: segment
                                    required property int index
                                    readonly property bool single: (readout.e.cycles ?? 0) === 0
                                    readonly property bool done: !segment.single && segment.index < (readout.e.cycle ?? 0)
                                    readonly property bool current: segment.single || segment.index === (readout.e.cycle ?? 0)

                                    width: segment.single ? 34 : segment.current ? 16 : 5
                                    height: readout.segmentHeight
                                    radius: height / 2
                                    color: ColorUtils.transparentize(readout.ink, segment.done ? 0 : 0.7)
                                    Behavior on width {
                                        enabled: !Appearance.reducedMotion
                                        animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(segment)
                                    }

                                    Rectangle {
                                        visible: segment.current
                                        width: Math.round(segment.width * Math.max(0, Math.min(1, readout.e.elapsed ?? 0)))
                                        height: parent.height
                                        radius: parent.radius
                                        color: readout.ink
                                    }
                                }
                            }
                        }
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: (readout.e.text ?? "") + (readout.e.minor ?? "")
                        color: readout.ink
                        opacity: readout.e.paused ? 0.6 : 1
                        font.family: Appearance.font.family.title
                        font.pixelSize: Math.round(root.thickness * 0.56)
                        font.variableAxes: ({
                            "wght": readout.e.paused ? 450 : 800,
                            "ROND": 100
                        })
                        font.features: ({
                            "tnum": 1
                        })
                    }
                }

                MouseArea {
                    id: press
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.triggered(readout.modelData)
                }
            }
        }
    }
}
