import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: root
    anchors.fill: parent
    property bool showBackButton: false
    signal goBack()

    ContentPage {
        anchors.fill: parent
        forceWidth: false

        RowLayout {
            visible: root.showBackButton
            spacing: Appearance.sizes.elevationMargin
            RippleButton {
                implicitWidth: Appearance.sizes.elevationMargin * 4
                implicitHeight: implicitWidth
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive
                onClicked: root.goBack()
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "arrow_back"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }
            StyledText {
                text: Translation.tr("Status Notches")
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                color: Appearance.colors.colOnLayer0
            }
        }

        ContentSection {
            icon: "sensors"
            title: Translation.tr("Status Notches")
            tooltip: Translation.tr("System indicators that appear inside the island when state changes.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                NotchCard {
                    buttonIcon: "tab"
                    text: Translation.tr("Workspaces Notch")
                    tooltip: Translation.tr("Toggle the workspaces notch notification on workspace changes")
                    masterEnabled: Config.options.bar.floatingNotch.enable || Config.options.bar.floatingNotch.centerInBar
                    notchEnabled: !Config.options.bar.floatingNotch.disableWorkspaces
                    onNotchToggled: (enabled) => {
                        Config.options.bar.floatingNotch.disableWorkspaces = !enabled;
                    }
                    heightLabel: Translation.tr("Workspaces contracted height")
                    contractedHeight: Config.options.bar.floatingNotch.heightWorkspaces
                    onContractedHeightEdited: (value) => {
                        Config.options.bar.floatingNotch.heightWorkspaces = value;
                    }
                }

                NotchCard {
                    buttonIcon: "keyboard"
                    text: Translation.tr("Keyboard Layout Notch")
                    tooltip: Translation.tr("Toggle the keyboard layout switcher notch notification on layout changes")
                    masterEnabled: Config.options.bar.floatingNotch.enable || Config.options.bar.floatingNotch.centerInBar
                    notchEnabled: !Config.options.bar.floatingNotch.disableKeyboard
                    onNotchToggled: (enabled) => {
                        Config.options.bar.floatingNotch.disableKeyboard = !enabled;
                    }
                    heightLabel: Translation.tr("Keyboard Layout contracted height")
                    contractedHeight: Config.options.bar.floatingNotch.heightKeyboard
                    onContractedHeightEdited: (value) => {
                        Config.options.bar.floatingNotch.heightKeyboard = value;
                    }
                }

                NotchCard {
                    buttonIcon: "wifi"
                    text: Translation.tr("Wi-Fi Notch")
                    tooltip: Translation.tr("Toggle the Wi-Fi status notch notification")
                    masterEnabled: Config.options.bar.floatingNotch.enable || Config.options.bar.floatingNotch.centerInBar
                    notchEnabled: !Config.options.bar.floatingNotch.disableWifi
                    onNotchToggled: (enabled) => {
                        Config.options.bar.floatingNotch.disableWifi = !enabled;
                    }
                    heightLabel: Translation.tr("Wi-Fi contracted height")
                    contractedHeight: Config.options.bar.floatingNotch.heightWifi
                    onContractedHeightEdited: (value) => {
                        Config.options.bar.floatingNotch.heightWifi = value;
                    }
                }

                NotchCard {
                    buttonIcon: "bluetooth"
                    text: Translation.tr("Bluetooth Notch")
                    tooltip: Translation.tr("Toggle the Bluetooth connection status notch notification")
                    masterEnabled: Config.options.bar.floatingNotch.enable || Config.options.bar.floatingNotch.centerInBar
                    notchEnabled: !Config.options.bar.floatingNotch.disableBluetooth
                    onNotchToggled: (enabled) => {
                        Config.options.bar.floatingNotch.disableBluetooth = !enabled;
                    }
                    heightLabel: Translation.tr("Bluetooth contracted height")
                    contractedHeight: Config.options.bar.floatingNotch.heightBluetooth
                    heightTo: 120
                    onContractedHeightEdited: (value) => {
                        Config.options.bar.floatingNotch.heightBluetooth = value;
                    }
                }

                NotchCard {
                    buttonIcon: "battery_charging_full"
                    text: Translation.tr("Battery Charging Notch")
                    tooltip: Translation.tr("Toggle the battery charging status notch (iOS-style)")
                    masterEnabled: Config.options.bar.floatingNotch.enable || Config.options.bar.floatingNotch.centerInBar
                    notchEnabled: !Config.options.bar.floatingNotch.disableBattery
                    onNotchToggled: (enabled) => {
                        Config.options.bar.floatingNotch.disableBattery = !enabled;
                    }
                    heightLabel: Translation.tr("Battery contracted height")
                    contractedHeight: Config.options.bar.floatingNotch.heightBattery
                    onContractedHeightEdited: (value) => {
                        Config.options.bar.floatingNotch.heightBattery = value;
                    }
                }
            }
        }
    }
}
