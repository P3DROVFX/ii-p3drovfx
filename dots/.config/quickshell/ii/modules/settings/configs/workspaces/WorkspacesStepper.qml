pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * A count as a card: the number set large between two buttons, and a row of
 * ticks under it filling up to the value. Scrolling over the card steps it too.
 */
Rectangle {
    id: root

    property string symbol: ""
    property string title: ""
    property string summary: ""
    property int value: 1
    property int from: 1
    property int to: 10
    property int stepSize: 1
    property string note: ""

    readonly property real padding: 18
    readonly property real buttonSize: 40
    readonly property real valueSize: 40
    readonly property real tickHeight: 8
    readonly property real tickGap: 3
    readonly property int tickLimit: 20
    readonly property color colTickOn: Appearance.colors.colPrimary
    readonly property color colTickOff: Appearance.colors.colSecondaryContainer

    signal stepped(int value)

    function step(direction) {
        const next = Math.max(root.from, Math.min(root.to, root.value + direction * root.stepSize));
        if (next !== root.value)
            root.stepped(next);
    }

    implicitHeight: column.implicitHeight + root.padding * 2
    radius: Appearance.rounding.verylarge
    color: Appearance.colors.colLayer1
    opacity: root.enabled ? 1 : 0.55
    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    WheelHandler {
        enabled: root.enabled
        onWheel: event => root.step(event.angleDelta.y > 0 ? 1 : -1)
    }

    ColumnLayout {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: root.padding
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            MaterialShapeWrappedMaterialSymbol {
                text: root.symbol
                iconSize: 20
                padding: 9
                fill: 1
                shape: MaterialShape.Shape.Cookie7Sided
                color: Appearance.colors.colSecondaryContainer
                colSymbol: Appearance.colors.colOnSecondaryContainer
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    Layout.fillWidth: true
                    text: root.title
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.note !== "" ? root.note : root.summary
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.WordWrap
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            StepButton {
                symbol: "remove"
                enabled: root.value > root.from
                onClicked: root.step(-1)
            }

            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: root.value
                font.family: Appearance.font.family.title
                font.variableAxes: Appearance.font.variableAxes.titleRounded
                font.pixelSize: root.valueSize
                color: Appearance.colors.colOnLayer1
            }

            StepButton {
                symbol: "add"
                enabled: root.value < root.to
                onClicked: root.step(1)
            }
        }

        Row {
            id: ticks
            Layout.fillWidth: true
            spacing: root.tickGap
            readonly property int count: Math.min(root.tickLimit, root.to - root.from + 1)
            readonly property real tickWidth: (width - root.tickGap * (count - 1)) / Math.max(1, count)
            readonly property real filled: (root.value - root.from + 1) / (root.to - root.from + 1) * count

            Repeater {
                model: ticks.count
                delegate: Rectangle {
                    required property int index
                    readonly property bool on: index < Math.round(ticks.filled)
                    width: ticks.tickWidth
                    height: on ? root.tickHeight : root.tickHeight / 2
                    anchors.verticalCenter: parent.verticalCenter
                    radius: height / 2
                    color: on ? root.colTickOn : root.colTickOff
                    Behavior on height {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                }
            }
        }
    }

    component StepButton: RippleButton {
        id: button
        property string symbol: ""
        implicitWidth: root.buttonSize
        implicitHeight: root.buttonSize
        buttonRadius: root.buttonSize / 2
        buttonRadiusPressed: Appearance.rounding.small
        opacity: button.enabled ? 1 : 0.4
        colBackground: Appearance.colors.colSecondaryContainer
        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
        colRipple: Appearance.colors.colSecondaryContainerActive
        contentItem: MaterialSymbol {
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: button.symbol
            iconSize: 20
            color: Appearance.colors.colOnSecondaryContainer
        }
    }
}
