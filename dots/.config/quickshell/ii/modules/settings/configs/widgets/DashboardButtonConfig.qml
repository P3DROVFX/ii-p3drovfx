import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services


ContentPage {
    id: root
    forceWidth: false
    signal goBack()

    RowLayout {
        spacing: 12

        RippleButton {
            implicitWidth: implicitHeight
            implicitHeight: 40
            topLeftRadius: Appearance.rounding.full
            topRightRadius: Appearance.rounding.full
            bottomLeftRadius: Appearance.rounding.full
            bottomRightRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colRipple: Appearance.colors.colSecondaryContainerActive

            MaterialSymbol {
                anchors.centerIn: parent
                text: "arrow_back"
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnSecondaryContainer
            }

            onClicked: root.goBack()
        }

        StyledText {
            text: Translation.tr("Dashboard Panel Button")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    ContentSection {
        icon: "space_dashboard"
        title: Translation.tr("Visible Indicators")

        NoticeBox {
            Layout.fillWidth: true
            isFirst: true
            text: Translation.tr("Choose which quick status indicators appear inside the dashboard panel button on the bar.")
        }

        ConfigSwitch {
            buttonIcon: "volume_up"
            text: Translation.tr("Show Volume")
            checked: Config.options.bar.dashboardButton.showVolume
            onCheckedChanged: {
                Config.options.bar.dashboardButton.showVolume = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "mic"
            text: Translation.tr("Show Microphone")
            checked: Config.options.bar.dashboardButton.showMic
            onCheckedChanged: {
                Config.options.bar.dashboardButton.showMic = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "wifi"
            text: Translation.tr("Show Network")
            checked: Config.options.bar.dashboardButton.showNetwork
            onCheckedChanged: {
                Config.options.bar.dashboardButton.showNetwork = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "bluetooth"
            text: Translation.tr("Show Bluetooth")
            checked: Config.options.bar.dashboardButton.showBluetooth
            onCheckedChanged: {
                Config.options.bar.dashboardButton.showBluetooth = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "notifications"
            text: Translation.tr("Show Notifications")
            checked: Config.options.bar.dashboardButton.showNotifications
            onCheckedChanged: {
                Config.options.bar.dashboardButton.showNotifications = checked;
            }
        }
    }

    ShortcutBox {
        Layout.fillWidth: true
        text: Translation.tr("Looking for Sidebars & Panels settings?")
        value: Translation.tr("Sidebars & Panels")
        targetPageId: "sidebars"
        targetSectionTitle: Translation.tr("Sidebars & Panels")
        materialIcon: "side_navigation"
    }
}
