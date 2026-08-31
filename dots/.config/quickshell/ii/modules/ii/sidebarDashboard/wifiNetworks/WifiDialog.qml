import qs
import qs.services
import qs.services.network
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell

WindowDialog {
    id: root
    // Dialogs may be hosted by surfaces other than the dashboard. Keep the
    // historical dashboard behaviour as the default, while allowing hosts such
    // as Welcome to opt out of sidebar-specific side effects.
    property bool closeOwningSidebarOnDetails: true
    property bool showDetailsAction: true

    signal detailsRequested()

    backgroundHeight: 600

    function prepareForOpen() {
        Network.enableWifi();
        Network.rescanWifi();
    }

    onShowChanged: {
        if (show)
            root.prepareForOpen();
    }

    // ── Header ────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 4
        Layout.rightMargin: 4
        spacing: 0

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Wi-Fi")
            font.pixelSize: Appearance.font.pixelSize.larger
            font.weight: Font.Bold
            color: Appearance.colors.colOnLayer1
        }

        StyledSwitch {
            checked: Network.wifiEnabled
            onToggled: Network.toggleWifi()
        }
    }

    // ── Content (scrollable) ──────────────────────────────
    WifiDialogContent {
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.topMargin: -4
    }

    // ── Bottom buttons ────────────────────────────────────
    WindowDialogButtonRow {
        Layout.leftMargin: 0
        Layout.rightMargin: 0
        Layout.bottomMargin: -8

        RippleButton {
            id: detailsBtn
            visible: root.showDetailsAction
            buttonRadius: Appearance.rounding.full
            colBackground: "transparent"
            colBackgroundHover: "transparent"
            colRipple: "transparent"
            implicitHeight: 36
            implicitWidth: detailsText.implicitWidth + 48

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
                font.variableAxes: ({"wght": 500})
                color: detailsBtn.hovered ? Appearance.colors.colOnSurface : Appearance.colors.colOutline
                Behavior on color { ColorAnimation { duration: 150 } }
            }
            onClicked: {
                GlobalStates.openSettingsPage("network", "", Network.ethernet ? "Ethernet ports" : "Wi-Fi");
                root.detailsRequested();
                if (root.closeOwningSidebarOnDetails)
                    GlobalStates.sidebarRightOpen = false;
            }
        }

        Item { Layout.fillWidth: true }

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
                font.variableAxes: ({"wght": 700})
                color: Appearance.colors.colOnPrimary
            }
            onClicked: root.dismiss()
        }
    }
}
