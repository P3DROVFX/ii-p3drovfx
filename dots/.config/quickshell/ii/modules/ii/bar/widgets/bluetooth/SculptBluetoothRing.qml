pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.bar.widgets.sculpt

/**
 * `ring` variant of the Sculpt Bluetooth widget — the charge, drawn twice.
 *
 * Straight on the bar, no surface: a wavy progress ring around the device's
 * glyph, then the percentage in tall, very condensed digits. The digits' weight
 * *is* the charge — a full battery is set black, an empty one hairline — so the
 * number reads before it is read. Low charge turns both to the error colour.
 */
Item {
    id: root

    property bool vertical: false
    property real thickness: 32
    property bool hovered: false
    property BarWidgetPalette tones
    property bool low: false
    property string deviceName: ""
    property string glyph: "bluetooth"
    property bool hasBattery: false
    property real battery: 0
    property int deviceCount: 1

    readonly property color colInk: root.low ? Appearance.colors.colError : root.tones.colBare
    readonly property color colRing: root.low ? Appearance.colors.colError : root.tones.colBareAccent

    implicitWidth: root.vertical ? root.thickness : layout.implicitWidth
    implicitHeight: root.vertical ? layout.implicitHeight : root.thickness

    Rectangle {
        anchors.fill: parent
        anchors.margins: -2
        radius: Math.min(width, height) / 2
        color: ColorUtils.transparentize(root.tones.colBare, 0.92)
        opacity: root.hovered ? 1 : 0
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(parent)
        }
    }

    Grid {
        id: layout
        anchors.centerIn: parent
        columns: root.vertical ? 1 : 2
        columnSpacing: 4
        rowSpacing: 2
        horizontalItemAlignment: Grid.AlignHCenter
        verticalItemAlignment: Grid.AlignVCenter

        Item {
            implicitWidth: root.thickness
            implicitHeight: root.thickness

            SculptWavyRing {
                anchors.fill: parent
                visible: root.hasBattery
                value: root.battery
                thickness: 2.5
                waves: 9
                maxAmplitude: 1.2
                colIndicator: root.colRing
                colTrack: ColorUtils.transparentize(root.colInk, 0.78)
            }

            Rectangle {
                anchors.centerIn: parent
                visible: !root.hasBattery
                width: root.thickness - 4
                height: width
                radius: width / 2
                color: root.tones.colBackgroundVariant
            }

            MaterialSymbol {
                anchors.centerIn: parent
                text: root.glyph
                fill: 1
                iconSize: Math.round(root.thickness * 0.44)
                color: root.hasBattery ? root.colInk : root.tones.colOnBackgroundVariant
            }

            // Several devices: their count, tucked on the ring.
            Rectangle {
                visible: root.deviceCount > 1
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                width: 12
                height: 12
                radius: 6
                color: root.tones.colBackground

                StyledText {
                    anchors.centerIn: parent
                    text: root.deviceCount
                    color: root.tones.colOnBackground
                    font.pixelSize: 8
                    font.weight: Font.Black
                }
            }
        }

        Item {
            implicitWidth: root.hasBattery ? digits.implicitWidth + (root.vertical ? 0 : percentSign.implicitWidth) : nameText.implicitWidth
            implicitHeight: root.hasBattery ? digits.implicitHeight : nameText.implicitHeight

            StyledText {
                id: digits
                visible: root.hasBattery
                text: Math.round(root.battery * 100)
                color: root.colInk
                font.family: Appearance.font.family.main
                font.pixelSize: Math.round(root.thickness * (root.vertical ? 0.66 : 0.98))
                font.variableAxes: ({
                    "wght": Appearance.font.variableAxes.blend(220, 900, root.battery),
                    "wdth": 25,
                    "ROND": 100
                })
                font.features: ({
                    "tnum": 1
                })
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(digits)
                }
            }

            // Set high, like a currency sign: it qualifies the number, it is
            // not part of it.
            StyledText {
                id: percentSign
                visible: root.hasBattery && !root.vertical
                anchors.left: digits.right
                anchors.top: digits.top
                anchors.topMargin: Math.round(digits.height * 0.2)
                text: "%"
                color: root.colInk
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.weight: Font.Black
            }

            StyledText {
                id: nameText
                visible: !root.hasBattery
                width: Math.min(implicitWidth, root.vertical ? root.thickness : 96)
                text: root.vertical ? root.deviceName.slice(0, 2).toUpperCase() : root.deviceName
                elide: Text.ElideRight
                color: root.colInk
                font.family: Appearance.font.family.title
                font.variableAxes: Appearance.font.variableAxes.titleRounded
                font.pixelSize: Appearance.font.pixelSize.smaller
            }
        }
    }
}
