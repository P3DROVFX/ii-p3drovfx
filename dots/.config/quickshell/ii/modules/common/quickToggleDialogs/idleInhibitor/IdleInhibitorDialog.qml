import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

WindowDialog {
    id: root
    backgroundWidth: 330

    readonly property var options: Config.options.idle

    // Value dialled in on the stepper. Starting it adds it to the chips above,
    // so a duration only has to be dialled once.
    property int customMinutes: 45

    component StepButton: RippleButton {
        id: stepButton
        property string buttonIcon

        implicitWidth: 48
        implicitHeight: 48
        buttonRadius: Appearance.rounding.full
        colBackground: Appearance.colors.colLayer2
        colBackgroundHover: Appearance.colors.colLayer2Hover
        colRipple: Appearance.colors.colLayer2Active

        contentItem: MaterialSymbol {
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: stepButton.buttonIcon
            iconSize: Appearance.font.pixelSize.larger
            color: stepButton.enabled ? Appearance.colors.colOnLayer2 : Appearance.m3colors.m3outline
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 4
        Layout.rightMargin: 4
        spacing: 0

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Keep awake")
            font.pixelSize: Appearance.font.pixelSize.larger
            font.weight: Font.Bold
            color: Appearance.colors.colOnLayer1
        }
    }

    // Current state, with the quick extend right next to it
    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 56
            radius: Appearance.rounding.full
            color: Idle.inhibit ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer2

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }

            RowLayout {
                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                    leftMargin: 16
                    rightMargin: 16
                }
                spacing: 12

                MaterialSymbol {
                    text: Idle.inhibit ? "kettle" : "coffee"
                    iconSize: Appearance.font.pixelSize.hugeass
                    fill: Idle.inhibit ? 1 : 0
                    color: Idle.inhibit ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Idle.timed ? Translation.tr("%1 left").arg(Idle.remainingText) : Idle.inhibit ? Translation.tr("On indefinitely") : Translation.tr("Off")
                    font.pixelSize: Appearance.font.pixelSize.large
                    elide: Text.ElideRight
                    color: Idle.inhibit ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
                }
            }
        }

        RippleButton {
            id: extendButton
            implicitWidth: 56
            implicitHeight: 56
            buttonRadius: Appearance.rounding.full
            enabled: Idle.timed
            colBackground: enabled ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
            colBackgroundHover: Appearance.colors.colPrimaryHover
            colRipple: Appearance.colors.colPrimaryActive
            onClicked: Idle.extendBy(Idle.extendMinutes)

            contentItem: StyledText {
                text: Translation.tr("+%1").arg(Idle.extendMinutes)
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                font.pixelSize: Appearance.font.pixelSize.small
                font.variableAxes: ({
                        "wght": 700
                    })
                color: extendButton.enabled ? Appearance.colors.colOnPrimary : Appearance.m3colors.m3outline
            }
        }
    }

    WindowDialogSectionHeader {
        text: Translation.tr("Duration")
    }

    // Recents plus indefinite, all on one row
    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: -12
        spacing: 4

        Item {
            Layout.fillWidth: true
        }

        Repeater {
            model: Idle.quickDurations

            delegate: SelectionGroupButton {
                required property int index
                required property var modelData
                leftmost: index === 0
                buttonText: Idle.formatMinutes(modelData)
                toggled: Idle.timed && Idle.sessionMinutes === modelData
                onClicked: Idle.inhibitFor(modelData)
            }
        }

        SelectionGroupButton {
            rightmost: true
            buttonIcon: "all_inclusive"
            toggled: Idle.inhibit && !Idle.timed
            onClicked: Idle.toggleInhibit(true)
        }

        Item {
            Layout.fillWidth: true
        }
    }

    // Manual timer: step either side of the dialled value, then commit it
    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 4
        spacing: 8

        StepButton {
            buttonIcon: "remove"
            enabled: root.customMinutes > 5
            onClicked: root.customMinutes = Idle.stepMinutes(root.customMinutes, -1)
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 48
            radius: Appearance.rounding.full
            color: Appearance.colors.colLayer2

            StyledText {
                anchors.centerIn: parent
                text: Idle.formatMinutes(root.customMinutes)
                font.pixelSize: Appearance.font.pixelSize.large
                font.variableAxes: ({
                        "wght": 700
                    })
                color: Appearance.colors.colOnLayer2
            }
        }

        StepButton {
            buttonIcon: "add"
            enabled: root.customMinutes < 1440
            onClicked: root.customMinutes = Idle.stepMinutes(root.customMinutes, 1)
        }
    }

    RippleButton {
        id: startButton
        Layout.fillWidth: true
        Layout.topMargin: 4
        implicitHeight: 48
        buttonRadius: Appearance.rounding.full
        colBackground: Appearance.colors.colPrimary
        colBackgroundHover: Appearance.colors.colPrimaryHover
        colRipple: Appearance.colors.colPrimaryActive
        onClicked: Idle.inhibitFor(root.customMinutes)

        contentItem: StyledText {
            text: Translation.tr("Start")
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            font.pixelSize: Appearance.font.pixelSize.large
            font.variableAxes: ({
                    "wght": 700
                })
            color: Appearance.colors.colOnPrimary
        }
    }

    // Footer actions
    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 8
        spacing: 12

        RippleButton {
            id: turnOffButton
            buttonRadius: Appearance.rounding.full
            colBackground: "transparent"
            colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
            colRipple: Appearance.colors.colSurfaceContainerHighestActive
            implicitHeight: 36
            implicitWidth: turnOffText.implicitWidth + 32
            enabled: Idle.inhibit
            onClicked: Idle.toggleInhibit(false)

            Rectangle {
                anchors.fill: parent
                color: "transparent"
                border.width: 1
                border.color: !turnOffButton.enabled ? Appearance.m3colors.m3outline : turnOffButton.hovered ? Appearance.colors.colOnSurface : Appearance.colors.colOutline
                radius: parent.buttonEffectiveRadius

                Behavior on border.color {
                    ColorAnimation {
                        duration: 150
                    }
                }
            }

            contentItem: StyledText {
                id: turnOffText
                text: Translation.tr("Turn off")
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                font.pixelSize: Appearance.font.pixelSize.small
                font.variableAxes: ({
                        "wght": 500
                    })
                color: !turnOffButton.enabled ? Appearance.m3colors.m3outline : turnOffButton.hovered ? Appearance.colors.colOnSurface : Appearance.colors.colOutline

                Behavior on color {
                    ColorAnimation {
                        duration: 150
                    }
                }
            }
        }

        Item {
            Layout.fillWidth: true
        }

        RippleButton {
            id: doneButton
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colPrimary
            colBackgroundHover: Appearance.colors.colPrimaryHover
            colRipple: Appearance.colors.colPrimaryActive
            implicitHeight: 36
            implicitWidth: doneText.implicitWidth + 48
            onClicked: root.dismiss()

            contentItem: StyledText {
                id: doneText
                text: Translation.tr("Done")
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                font.pixelSize: Appearance.font.pixelSize.small
                font.variableAxes: ({
                        "wght": 700
                    })
                color: Appearance.colors.colOnPrimary
            }
        }
    }
}
