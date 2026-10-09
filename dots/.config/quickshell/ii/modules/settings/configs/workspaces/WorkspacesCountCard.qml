pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * A number setting as a card: its value in big condensed digits between a − and a +,
 * and the number drawn under it — as many dots as the value ("dots") or a bar filled to
 * its place in the range ("bar") — so the value reads before it is counted.
 */
Rectangle {
    id: root

    readonly property real padding: 18
    readonly property real iconSize: 20
    readonly property real iconPadding: 9
    readonly property real buttonSize: 40
    readonly property real digitsSize: 44
    readonly property real dotSize: 8
    readonly property real dotGap: 4
    readonly property real dotRowsReserved: 2
    readonly property real barHeight: 8
    readonly property var axesDigits: ({ "wght": 760, "wdth": 40, "ROND": 100 })
    readonly property real disabledOpacity: 0.5

    property string symbol: ""
    property var shape: MaterialShape.Shape.Cookie9Sided
    property string title: ""
    property string hint: ""
    property string unit: ""
    property int value: 0
    property int from: 0
    property int to: 100
    property int stepSize: 1
    /** "dots" | "bar" */
    property string visual: "dots"
    /** 0 → 1 of dots drawn as rounded squares instead of circles. */
    property real dotRoundness: 0.5

    signal moved(int value)

    readonly property bool engaged: cardHover.hovered
    readonly property real fraction: root.to > root.from ? (root.value - root.from) / (root.to - root.from) : 0

    function step(direction) {
        const next = Math.max(root.from, Math.min(root.to, root.value + direction * root.stepSize));
        if (next !== root.value)
            root.moved(next);
    }

    implicitHeight: column.implicitHeight + root.padding * 2
    radius: Appearance.rounding.verylarge
    color: root.engaged ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1
    opacity: root.enabled ? 1 : root.disabledOpacity
    Behavior on color {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
    }

    HoverHandler {
        id: cardHover
    }

    ColumnLayout {
        id: column
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: root.padding
        }
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            MaterialShapeWrappedMaterialSymbol {
                text: root.symbol
                iconSize: root.iconSize
                padding: root.iconPadding
                fill: root.engaged ? 1 : 0
                shape: root.engaged ? root.shape : MaterialShape.Shape.Circle
                color: root.engaged ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
                colSymbol: root.engaged ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: root.title
                    font.family: Appearance.font.family.title
                    font.variableAxes: Appearance.font.variableAxes.titleRounded
                    font.pixelSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnLayer1
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.hint
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            StepButton {
                symbol: "remove"
                enabled: root.enabled && root.value > root.from
                onClicked: root.step(-1)
            }

            Item {
                Layout.fillWidth: true
                implicitHeight: digits.implicitHeight

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 4

                    StyledText {
                        id: digits
                        text: String(root.value)
                        font.family: Appearance.font.family.main
                        font.pixelSize: root.digitsSize
                        font.variableAxes: root.axesDigits
                        color: Appearance.colors.colPrimary
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignBottom
                        Layout.bottomMargin: 8
                        visible: root.unit.length > 0
                        text: root.unit
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.Bold
                        color: Appearance.colors.colSubtext
                    }
                }
            }

            StepButton {
                symbol: "add"
                enabled: root.enabled && root.value < root.to
                onClicked: root.step(1)
            }
        }

        Item {
            id: visualBand
            Layout.fillWidth: true
            implicitHeight: root.visual === "bar" ? root.barHeight
                : root.dotRowsReserved * root.dotSize + (root.dotRowsReserved - 1) * root.dotGap
            clip: true

            Rectangle {
                visible: root.visual === "bar"
                anchors.fill: parent
                radius: height / 2
                color: Appearance.colors.colLayer2

                Rectangle {
                    width: Math.max(parent.height, parent.width * root.fraction)
                    height: parent.height
                    radius: height / 2
                    color: Appearance.colors.colPrimary
                    Behavior on width {
                        enabled: !Appearance.reducedMotion
                        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                    }
                }
            }

            Flow {
                visible: root.visual === "dots"
                width: parent.width
                spacing: root.dotGap

                Repeater {
                    model: root.visual === "dots" ? root.value : 0
                    delegate: Rectangle {
                        id: dot
                        width: root.dotSize
                        height: root.dotSize
                        radius: root.dotSize * root.dotRoundness
                        color: Appearance.colors.colPrimary
                        opacity: 0
                        Component.onCompleted: dot.opacity = 1
                        Behavior on opacity {
                            enabled: !Appearance.reducedMotion
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                    }
                }
            }
        }
    }

    component StepButton: RippleButton {
        id: button

        required property string symbol

        implicitWidth: root.buttonSize
        implicitHeight: root.buttonSize
        buttonRadius: height / 2
        buttonRadiusPressed: Appearance.rounding.small
        colBackground: Appearance.colors.colSecondaryContainer
        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
        colRipple: Appearance.colors.colSecondaryContainerActive
        opacity: button.enabled ? 1 : root.disabledOpacity

        contentItem: Item {
            MaterialSymbol {
                anchors.centerIn: parent
                text: button.symbol
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnSecondaryContainer
            }
        }
    }
}
