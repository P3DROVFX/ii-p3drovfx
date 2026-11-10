pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * `squeeze` variant of Sculpt timer — time you can see running out.
 *
 * Tall digits straight on the bar whose width axis *is* the time left: a fresh
 * timer is set wide, the last seconds squeezed narrow (snapped steps, see
 * `variableAxes.blend` — one new face per step, not per second). Each readout
 * keeps the footprint of its widest setting, so nothing beside it moves while
 * it squeezes — the room it gives up opens behind the digits. A break is set
 * slanted, a paused timer hairline; a stopwatch has no end, so it keeps a
 * middle width and its hundredths ride small beside it.
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
        spacing: 10

        Repeater {
            model: root.keys

            delegate: Item {
                id: readout
                required property string modelData
                readonly property var e: root.entryFor(readout.modelData) ?? ({})
                readonly property bool hovered: press.containsMouse

                readonly property real squeeze: readout.e.remaining >= 0 ? readout.e.remaining : 0.5
                readonly property int pixelSize: Math.round(root.thickness * 0.92)

                implicitWidth: glyph.implicitWidth + 3 + widest.implicitWidth + (minor.visible ? minor.implicitWidth : 0) + 6
                implicitHeight: root.thickness

                Rectangle {
                    anchors.fill: parent
                    radius: Appearance.rounding.scale === 0 ? 0 : height / 2
                    color: ColorUtils.transparentize(root.tones.colBare, 0.92)
                    opacity: readout.hovered ? 1 : 0
                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(parent)
                    }
                }

                MaterialSymbol {
                    id: glyph
                    x: 3
                    anchors.verticalCenter: parent.verticalCenter
                    text: readout.e.icon ?? "timer"
                    fill: 1
                    iconSize: Math.round(root.thickness * 0.44)
                    color: root.tones.colBareAccent
                }

                // The widest setting, for the footprint only.
                StyledText {
                    id: widest
                    visible: false
                    text: readout.e.text ?? ""
                    font.family: Appearance.font.family.main
                    font.pixelSize: readout.pixelSize
                    font.variableAxes: ({
                        "wght": 760,
                        "wdth": 130,
                        "ROND": 100
                    })
                    font.features: ({
                        "tnum": 1
                    })
                }

                StyledText {
                    id: digits
                    x: glyph.x + glyph.width + 3
                    anchors.verticalCenter: parent.verticalCenter
                    text: readout.e.text ?? ""
                    color: root.tones.colBare
                    opacity: readout.e.paused ? 0.6 : 1
                    font.family: Appearance.font.family.main
                    font.pixelSize: readout.pixelSize
                    font.variableAxes: ({
                        "wght": readout.e.paused ? 250 : 760,
                        "wdth": Appearance.font.variableAxes.blend(25, 130, readout.squeeze),
                        "slnt": readout.e.relaxed ? -10 : 0,
                        "ROND": 100
                    })
                    font.features: ({
                        "tnum": 1
                    })
                }

                StyledText {
                    id: minor
                    visible: (readout.e.minor ?? "").length > 0
                    x: digits.x + digits.implicitWidth + 1
                    anchors.baseline: digits.baseline
                    text: readout.e.minor ?? ""
                    color: root.tones.colBareAccent
                    font.family: Appearance.font.family.main
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.variableAxes: ({
                        "wght": 700,
                        "wdth": 100,
                        "ROND": 100
                    })
                    font.features: ({
                        "tnum": 1
                    })
                }

                MouseArea {
                    id: press
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.triggered(readout.modelData)
                }

                StyledToolTip {
                    text: readout.e.label ?? ""
                    alternativeVisibleCondition: readout.hovered
                    extraVisibleCondition: false
                    requireOverlay: false
                }
            }
        }
    }
}
