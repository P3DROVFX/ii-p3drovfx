import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell

WindowDialog {
    id: root
    backgroundHeight: 600

    Component.onCompleted: {
        TailscaleService.refresh()
        if (Config.options.tailscale.enableDiagnostics)
            TailscaleService.refreshDiagnostics()
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 4
        Layout.rightMargin: 4
        spacing: 0
        
        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Tailscale Mesh")
            font.pixelSize: Appearance.font.pixelSize.larger
            font.weight: Font.Bold
            color: Appearance.colors.colOnLayer1
        }

        StyledSwitch {
            checked: TailscaleService.active
            onToggled: {
                TailscaleService.toggleTailscale()
            }
        }
    }

    TailscaleDialogContent {
        Layout.fillWidth: true
        Layout.fillHeight: true
    }

    // Footer actions
    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 8
        spacing: 12

        RippleButton {
            id: detailsBtn
            buttonRadius: Appearance.rounding.full
            colBackground: "transparent"
            colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
            colRipple: Appearance.colors.colSurfaceContainerHighestActive
            implicitHeight: 36
            implicitWidth: detailsText.implicitWidth + 32
            Rectangle {
                anchors.fill: parent
                color: "transparent"
                border.width: 1
                border.color: detailsBtn.hovered ? Appearance.colors.colOnSurface : Appearance.colors.colOutline
                radius: parent.buttonEffectiveRadius
                Behavior on border.color {
                    ColorAnimation { duration: 150 }
                }
            }


            contentItem: StyledText {
                id: detailsText
                text: Translation.tr("Details")
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                font.pixelSize: Appearance.font.pixelSize.small
                font.variableAxes: ({ "wght": 500 })
                color: detailsBtn.hovered ? Appearance.colors.colOnSurface : Appearance.colors.colOutline
                Behavior on color { ColorAnimation { duration: 150 } }
            }
            onClicked: {
                GlobalStates.openSettingsPage("privacy")
                root.dismiss()
            }
        }

        Item {
            Layout.fillWidth: true
        }

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
                font.variableAxes: ({ "wght": 700 })
                color: Appearance.colors.colOnPrimary
            }
            onClicked: root.dismiss()
        }
    }
}
