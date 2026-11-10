pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Widgets
import qs.modules.common
import qs.modules.common.widgets

/**
 * `card` variant of the Sculpt Bluetooth widget — a pass from a wallet app.
 *
 * The card's "brand" is set behind everything in wide black type, far larger
 * than the card, and cropped by it: the device's name, or the charge when the
 * name is hidden. In front sit a scalloped seal carrying the device's glyph and
 * the battery, small and exact. Several devices add a row of dots under it.
 */
Item {
    id: root

    property bool vertical: false
    property real thickness: 32
    property bool hovered: false
    property BarWidgetPalette tones
    property string deviceName: ""
    property string glyph: "bluetooth"
    property bool hasBattery: false
    property real battery: 0
    property bool showName: true
    property int deviceCount: 1
    property int deviceIndex: 0

    readonly property string percent: Math.round(root.battery * 100) + "%"
    readonly property string brand: root.showName || !root.hasBattery
        ? (root.deviceName.split(" ")[0] || root.deviceName)
        : root.percent
    readonly property real badgeSize: root.thickness - 8

    // Long enough for a good stretch of the brand to show, never the whole of it.
    readonly property real horizontalLength: Math.max(
        front.implicitWidth + 16,
        Math.min(Math.round(root.thickness * 4.6), Math.max(Math.round(root.thickness * 3.4), Math.round(brandText.implicitWidth * 0.7))))

    implicitWidth: root.vertical ? root.thickness : root.horizontalLength
    implicitHeight: root.vertical ? Math.round(root.thickness * 2.2) : root.thickness

    ClippingRectangle {
        id: card
        anchors.fill: parent
        radius: Appearance.rounding.scale === 0 ? 0 : Math.round(root.thickness * 0.3)
        color: root.hovered ? root.tones.colBackgroundHover : root.tones.colBackground

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(card)
        }

        // ── The brand, cropped ──────────────────────────────────────────────
        StyledText {
            id: brandText
            text: root.brand
            color: root.tones.colOnBackground
            opacity: 0.3
            font.family: Appearance.font.family.main
            font.pixelSize: Math.round(root.thickness * 1.25)
            font.letterSpacing: -1
            font.variableAxes: ({
                "wght": 900,
                "wdth": 125,
                "ROND": 0
            })
            transformOrigin: Item.TopLeft
            rotation: root.vertical ? 90 : 0
            // Starts under the badge's right half and drops below the bottom
            // edge, so the card cuts the letters across their middle.
            // The baseline sits just past the far edge, so the card keeps the
            // upper two thirds of the capitals.
            readonly property real baselineAt: Math.round(root.thickness * 1.12)
            x: root.vertical ? Math.round(brandText.baselineOffset - (brandText.baselineAt - card.width)) : Math.round(root.badgeSize * 0.6)
            y: root.vertical ? Math.round(root.badgeSize * 0.6) : brandText.baselineAt - Math.round(brandText.baselineOffset)
        }

        // ── In front: badge, battery, dots ──────────────────────────────────
        Grid {
            id: front
            x: root.vertical ? Math.round((card.width - width) / 2) : 4
            y: root.vertical ? 4 : Math.round((card.height - height) / 2)
            columns: root.vertical ? 1 : 2
            columnSpacing: 7
            rowSpacing: 5
            horizontalItemAlignment: Grid.AlignHCenter
            verticalItemAlignment: Grid.AlignVCenter

            MaterialShape {
                implicitSize: root.badgeSize
                shape: MaterialShape.Shape.Cookie12Sided
                color: root.tones.colBackgroundVariant

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.glyph
                    fill: 1
                    iconSize: Math.round(root.badgeSize * 0.52)
                    color: root.tones.colOnBackgroundVariant
                }
            }

            Column {
                spacing: 2

                StyledText {
                    anchors.horizontalCenter: root.vertical ? parent.horizontalCenter : undefined
                    visible: root.hasBattery
                    text: root.vertical ? Math.round(root.battery * 100) : root.percent
                    color: root.tones.colOnBackground
                    font.family: Appearance.font.family.main
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.variableAxes: ({
                        "wght": 760,
                        "wdth": 100,
                        "ROND": 100
                    })
                    font.features: ({
                        "tnum": 1
                    })
                }

                Row {
                    anchors.horizontalCenter: root.vertical ? parent.horizontalCenter : undefined
                    visible: root.deviceCount > 1
                    spacing: 3

                    Repeater {
                        model: root.deviceCount
                        delegate: Rectangle {
                            required property int index
                            width: index === root.deviceIndex ? 8 : 4
                            height: 4
                            radius: 2
                            color: root.tones.colOnBackground
                            opacity: index === root.deviceIndex ? 1 : 0.45
                            Behavior on width {
                                animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(parent)
                            }
                        }
                    }
                }
            }
        }
    }
}
