pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * One size in big condensed digits, with − / + beside it and a segmented gauge under it
 * (one segment per two pixels of the range, lit up to the value). The wheel over the card
 * steps it too. Digits thicken while the value is being changed.
 */
Rectangle {
    id: root

    readonly property real padding: 18
    readonly property real digitsSize: 52
    readonly property real stepperSize: 40
    readonly property real stepperGap: 3
    readonly property real gaugeHeight: 6
    readonly property real gaugeGap: 3
    readonly property int gaugeStep: 2

    property string caption: ""
    property string symbol: "height"
    property int value: 40
    property int from: 30
    property int to: 50
    property string unit: "px"

    signal moved(int value)

    property real boldness: ((root.minus?.down ?? false) || (root.plus?.down ?? false) || wheelHot.running) ? 1 : 0
    Behavior on boldness {
        enabled: !Appearance.reducedMotion
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    implicitHeight: column.implicitHeight + root.padding * 2
    radius: Appearance.rounding.verylarge
    color: cardHover.hovered ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1
    Behavior on color {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
    }

    function step(delta) {
        const next = Math.max(root.from, Math.min(root.to, root.value + delta));
        if (next !== root.value)
            root.moved(next);
    }

    HoverHandler {
        id: cardHover
    }
    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
            root.step(event.angleDelta.y > 0 ? 1 : -1);
            wheelHot.restart();
        }
    }
    Timer {
        id: wheelHot
        interval: 400
    }

    ColumnLayout {
        id: column
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: root.padding
        }
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            MaterialSymbol {
                text: root.symbol
                iconSize: 15
                color: Appearance.colors.colOnSurfaceVariant
            }
            StyledText {
                Layout.fillWidth: true
                text: root.caption
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.weight: Font.Bold
                font.letterSpacing: 1.2
                font.capitalization: Font.AllUppercase
                color: Appearance.colors.colOnSurfaceVariant
                elide: Text.ElideRight
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 4

            StyledText {
                Layout.alignment: Qt.AlignBaseline
                text: root.value
                font.family: Appearance.font.family.main
                font.pixelSize: Math.round(root.digitsSize)
                font.variableAxes: ({ "wght": Appearance.font.variableAxes.blend(620, 780, root.boldness), "wdth": Appearance.font.variableAxes.blend(34, 44, root.boldness), "ROND": 100 })
                color: Appearance.colors.colPrimary
            }
            StyledText {
                Layout.alignment: Qt.AlignBaseline
                text: root.unit
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                color: Appearance.colors.colSubtext
            }
            Item {
                Layout.fillWidth: true
            }

            // − / + as a connected pair.
            Row {
                Layout.alignment: Qt.AlignVCenter
                spacing: root.stepperGap

                Repeater {
                    model: 2
                    delegate: RippleButton {
                        id: stepper
                        required property int index
                        readonly property bool first: stepper.index === 0
                        readonly property bool atLimit: stepper.first ? root.value <= root.from : root.value >= root.to
                        implicitWidth: root.stepperSize + 6
                        implicitHeight: root.stepperSize
                        enabled: !stepper.atLimit
                        opacity: enabled ? 1 : 0.4
                        topLeftRadius: stepper.first || stepper.down ? height / 2 : Appearance.rounding.verysmall
                        bottomLeftRadius: stepper.first || stepper.down ? height / 2 : Appearance.rounding.verysmall
                        topRightRadius: !stepper.first || stepper.down ? height / 2 : Appearance.rounding.verysmall
                        bottomRightRadius: !stepper.first || stepper.down ? height / 2 : Appearance.rounding.verysmall
                        colBackground: Appearance.colors.colSecondaryContainer
                        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                        colRipple: Appearance.colors.colSecondaryContainerActive
                        onClicked: root.step(stepper.first ? -1 : 1)
                        Component.onCompleted: {
                            if (stepper.first) root.minus = stepper; else root.plus = stepper;
                        }
                        contentItem: Item {
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: stepper.first ? "remove" : "add"
                                iconSize: 20
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                        }
                    }
                }
            }
        }

        // The range as a gauge: lit up to the value.
        Row {
            id: gauge
            Layout.fillWidth: true
            spacing: root.gaugeGap
            readonly property int count: Math.floor((root.to - root.from) / root.gaugeStep) + 1
            readonly property real segment: (width - root.gaugeGap * (gauge.count - 1)) / gauge.count

            Repeater {
                model: gauge.count
                delegate: Rectangle {
                    required property int index
                    readonly property bool lit: root.from + index * root.gaugeStep <= root.value
                    width: gauge.segment
                    height: root.gaugeHeight
                    radius: height / 2
                    color: lit ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                }
            }
        }
    }

    property var minus: null
    property var plus: null
}
