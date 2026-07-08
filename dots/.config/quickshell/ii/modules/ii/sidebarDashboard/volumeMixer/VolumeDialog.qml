pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire

WindowDialog {
    id: root
    property bool isSink: true
    backgroundHeight: 600

    VolumeDialogContent {
        isSink: root.isSink
        Layout.fillWidth: true
        Layout.fillHeight: true
    }

    WindowDialogButtonRow {
        Layout.leftMargin: 0
        Layout.rightMargin: 0
        Layout.bottomMargin: -8
        // Details button with only a border and no fill
        RippleButton {
            id: detailsBtn
            buttonRadius: Appearance.rounding.full
            colBackground: "transparent"
            colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.1)
            colRipple: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.2)
            implicitHeight: 36
            implicitWidth: detailsText.implicitWidth + 48

            Rectangle {
                anchors.fill: parent
                color: "transparent"
                border.width: 1
                border.color: Appearance.colors.colPrimary
                radius: parent.buttonEffectiveRadius

                Behavior on radius {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }

            contentItem: StyledText {
                id: detailsText
                text: Translation.tr("Details")
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                font.pixelSize: Appearance.font.pixelSize.small
                font.variableAxes: ({
                        "wght": 700
                    })
                color: Appearance.colors.colPrimary
            }
            onClicked: {
                Quickshell.execDetached(["bash", "-c", `${Config.options.apps.volumeMixer}`]);
                GlobalStates.sidebarRightOpen = false;
            }
        }

        Item {
            Layout.fillWidth: true
        }

        // Done button with fill
        RippleButton {
            id: doneBtn
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colPrimary
            colBackgroundHover: Appearance.colors.colPrimaryHover
            colRipple: Appearance.colors.colPrimaryActive
            implicitHeight: 36
            implicitWidth: doneText.implicitWidth + 48

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
            onClicked: root.dismiss()
        }
    }
}
