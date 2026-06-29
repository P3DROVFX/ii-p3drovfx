pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Item {
    id: root
    readonly property bool usePasswordChars: !PolkitService.flow?.responseVisible ?? true

    property bool animateIn: false
    Component.onCompleted: animateIn = true

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            root.closeGracefully()
        }
    }

    function submit() {
        if (PolkitService.interactionAvailable) {
            PolkitService.submit(inputField.text);
        }
    }

    function closeGracefully() {
        root.animateIn = false
        exitDelay.start()
    }

    Timer {
        id: exitDelay
        interval: 220
        onTriggered: PolkitService.cancel()
    }

    Connections {
        target: PolkitService
        function onInteractionAvailableChanged() {
            if (!PolkitService.interactionAvailable) return;
            inputField.text = "";
            inputField.forceActiveFocus();
        }
    }

    Rectangle {
        id: bg
        anchors.fill: parent
        color: Appearance.colors.colScrim
        opacity: root.animateIn ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
    }

    Rectangle {
        id: dialogCard
        anchors.centerIn: parent
        width: Appearance.sizes.mediaControlsWidth
        height: contentColumn.implicitHeight + Appearance.font.pixelSize.normal * 3
        radius: Appearance.rounding.verylarge
        color: Appearance.m3colors.m3surfaceContainerLow
        border.color: Appearance.colors.colLayer0Border
        border.width: 1

        opacity: root.animateIn ? 1 : 0
        scale: root.animateIn ? 1 : 0.85
        transform: Translate { y: root.animateIn ? 0 : Appearance.font.pixelSize.huge * 2 }


        Behavior on opacity { NumberAnimation { duration: root.animateIn ? 280 : 180; easing.type: Easing.OutCubic } }
        Behavior on scale {
            NumberAnimation {
                duration: root.animateIn ? 450 : 200
                easing {
                    type: Easing.OutBack
                    overshoot: 1.45
                }
            }
        }
        Behavior on transform {
            NumberAnimation {
                duration: root.animateIn ? 450 : 200
                easing {
                    type: Easing.OutBack
                    overshoot: 1.45
                }
            }
        }


        ColumnLayout {
            id: contentColumn
            anchors.fill: parent
            anchors.margins: Appearance.rounding.large
            spacing: Appearance.font.pixelSize.larger

            MaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                iconSize: Appearance.font.pixelSize.huge + Appearance.rounding.unsharpenmore
                text: "security"
                color: Appearance.colors.colSecondary

                scale: root.animateIn ? 1 : 0.4
                Behavior on scale { NumberAnimation { duration: 450; easing.type: Easing.OutBack; easing.overshoot: 1.6 } }
            }

            WindowDialogTitle {
                text: Translation.tr("Authentication")
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
            }

            WindowDialogParagraph {
                text: PolkitService.cleanMessage
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignLeft
                lineHeight: 1.2
            }

            Rectangle {
                id: inputContainer
                Layout.fillWidth: true
                implicitHeight: Appearance.font.pixelSize.huge * 2.5
                radius: implicitHeight / 2
                color: "transparent"
                border.color: inputField.activeFocus ? Appearance.colors.colSecondary : Appearance.colors.colOutline
                border.width: inputField.activeFocus ? Appearance.borderWidth : 1

                scale: inputField.activeFocus ? 1.02 : 1.0

                Behavior on border.color { ColorAnimation { duration: 180 } }
                Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack; easing.overshoot: 1.3 } }

                Item {
                    anchors.fill: parent
                    anchors.leftMargin: Appearance.font.pixelSize.normal * 1.25
                    anchors.rightMargin: Appearance.font.pixelSize.normal * 1.25

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.IBeamCursor
                        acceptedButtons: Qt.NoButton
                    }

                    StyledText {
                        text: PolkitService.cleanPrompt || "Enter password..."
                        color: Appearance.colors.colSubtext
                        visible: !inputField.text && !inputField.activeFocus
                        font.pixelSize: Appearance.font.pixelSize.normal
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    TextInput {
                        id: inputField
                        anchors.fill: parent
                        verticalAlignment: TextInput.AlignVCenter
                        focus: true
                        enabled: PolkitService.interactionAvailable
                        color: "transparent"
                        echoMode: TextInput.Normal
                        cursorVisible: false
                        cursorDelegate: Item {}
                        selectionColor: "transparent"
                        selectedTextColor: "transparent"
                        font.pixelSize: Appearance.font.pixelSize.normal
                        z: 2

                        onAccepted: root.submit()

                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Escape) {
                                root.closeGracefully()
                                event.accepted = true
                            }
                        }
                    }

                    StyledFlickable {
                        id: visualDisplay
                        anchors.fill: parent
                        z: 1
                        clip: true

                        // declared properties explicitly to fix the engine crash
                        property int length: inputField.text.length
                        property int selectionStart: inputField.selectionStart
                        property int selectionEnd: inputField.selectionEnd
                        property int cursorPosition: inputField.cursorPosition

                        property color color: Appearance.colors.colPrimary
                        property color selectedTextColor: Appearance.colors.colOnSecondaryContainer
                        property color selectionColor: Appearance.colors.colSecondaryContainer
                        property int charSize: Appearance.font.pixelSize.larger

                        contentWidth: dotsRow.implicitWidth
                        contentX: (Math.max(contentWidth - width, 0))
                        Behavior on contentX {
                            animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(visualDisplay)
                        }

                        Rectangle {
                            id: cursor
                            anchors {
                                verticalCenter: parent.verticalCenter
                                left: parent.left
                                leftMargin: visualDisplay.charSize * visualDisplay.cursorPosition
                            }
                            color: visualDisplay.color
                            implicitWidth: 2
                            implicitHeight: visualDisplay.charSize
                            visible: inputField.activeFocus
                            Behavior on anchors.leftMargin {
                                animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(cursor)
                            }
                        }

                        Row {
                            id: dotsRow
                            anchors {
                                left: parent.left
                                verticalCenter: parent.verticalCenter
                                leftMargin: -1
                            }
                            spacing: 0

                            Repeater {
                                model: ScriptModel {
                                    values: Array(visualDisplay.length)
                                }

                                delegate: Rectangle {
                                    id: charItem
                                    required property int index
                                    implicitWidth: visualDisplay.charSize
                                    implicitHeight: visualDisplay.charSize
                                    property bool selected: index >= visualDisplay.selectionStart && index < visualDisplay.selectionEnd

                                    color: ColorUtils.transparentize(visualDisplay.selectionColor, selected ? 0 : 1)

                                    MaterialShape {
                                        id: materialShape
                                        anchors.centerIn: parent

                                        property list<var> charShapes: [
                                            MaterialShape.Shape.Clover4Leaf,
                                            MaterialShape.Shape.Arrow,
                                            MaterialShape.Shape.Pill,
                                            MaterialShape.Shape.SoftBurst,
                                            MaterialShape.Shape.Diamond,
                                            MaterialShape.Shape.ClamShell,
                                            MaterialShape.Shape.Pentagon
                                        ]

                                        property int randomShapeIndex: Math.floor(Math.random() * charShapes.length)
                                        shape: charShapes[randomShapeIndex]

                                        color: charItem.selected ? visualDisplay.selectedTextColor : visualDisplay.color
                                        implicitSize: 0
                                        opacity: 0
                                        scale: 0.5

                                        Component.onCompleted: {
                                            appearAnim.start();
                                        }

                                        ParallelAnimation {
                                            id: appearAnim
                                            NumberAnimation {
                                                target: materialShape
                                                properties: "opacity"
                                                to: 1
                                                duration: 50
                                                easing.type: Appearance.animation.elementMoveFast.type
                                                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                                            }
                                            NumberAnimation {
                                                target: materialShape
                                                properties: "scale"
                                                to: 1
                                                duration: 220
                                                easing.type: Easing.BezierSpline
                                                easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
                                            }
                                            NumberAnimation {
                                                target: materialShape
                                                properties: "implicitSize"
                                                to: visualDisplay.charSize - 2
                                                easing.type: Easing.BezierSpline
                                                easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
                                            }
                                            ColorAnimation {
                                                target: materialShape
                                                properties: "color"
                                                from: Appearance.colors.colPrimary
                                                to: Appearance.colors.colOnLayer1
                                                duration: 1000
                                                easing.type: Appearance.animation.elementMoveFast.type
                                                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 6
                spacing: 12

                Item {
                    Layout.fillWidth: true
                }

                Rectangle {
                    id: cancelBtn
                    implicitWidth: cancelText.implicitWidth + Appearance.font.pixelSize.normal * 2
                    implicitHeight: cancelText.implicitHeight + Appearance.font.pixelSize.normal
                    radius: implicitHeight / 2
                    color: "transparent"
                    border.color: Appearance.colors.colSecondary
                    border.width: 1

                    scale: cancelMouse.pressed ? 0.92 : (cancelMouse.containsMouse ? 1.05 : 1.0)
                    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
                    Behavior on color { ColorAnimation { duration: 120 } }

                    StyledText {
                        id: cancelText
                        anchors.centerIn: parent
                        text: Translation.tr("Cancel")
                        color: Appearance.colors.colSecondary
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.Medium
                    }

                    MouseArea {
                        id: cancelMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.closeGracefully()
                        onEntered: cancelBtn.color = Qt.rgba(1, 1, 1, 0.08)
                        onExited: cancelBtn.color = "transparent"
                    }
                }

                Rectangle {
                    id: okBtn
                    implicitWidth: okText.implicitWidth + Appearance.font.pixelSize.normal * 5
                    implicitHeight: okText.implicitHeight + Appearance.font.pixelSize.normal
                    radius: implicitHeight / 2
                    color: PolkitService.interactionAvailable ? Appearance.colors.colSecondary : Qt.rgba(1, 1, 1, 0.1)

                    scale: okMouse.pressed ? 0.92 : (okMouse.containsMouse && PolkitService.interactionAvailable ? 1.05 : 1.0)
                    opacity: PolkitService.interactionAvailable ? (okMouse.containsMouse ? 0.9 : 1.0) : 0.5

                    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
                    Behavior on opacity { NumberAnimation { duration: 120 } }

                    StyledText {
                        id: okText
                        anchors.centerIn: parent
                        text: Translation.tr("OK")
                        color: Appearance.colors.colOnSecondary
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.Medium
                    }

                    MouseArea {
                        id: okMouse
                        anchors.fill: parent
                        enabled: PolkitService.interactionAvailable
                        hoverEnabled: true
                        cursorShape: PolkitService.interactionAvailable ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: root.submit()
                    }
                }
            }
        }
    }
}

