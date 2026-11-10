import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root

    forceWidth: false

    signal goBack()

    // ── Back button row ───────────────────────────────────────────────────
    RowLayout {
        spacing: 12

        RippleButton {
            id: backButton
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
            text: Translation.tr("Bluetooth Devices Popup")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    ContentSection {
        icon: "style"
        title: Translation.tr("Style & Layout")

        ContentSubsection {
            title: Translation.tr("Visual style")
            icon: "bluetooth"
            ConfigSelectionArray {
                currentValue: Config.options.bar.styles.bluetooth === "default" ? "classic" : Config.options.bar.styles.bluetooth
                onSelected: newValue => {
                    Config.options.bar.styles.bluetooth = String(newValue);
                }
                options: [
                    { displayName: Translation.tr("Classic"),    icon: "style",     value: "classic" },
                    { displayName: Translation.tr("Expressive"), icon: "fluid_med", value: "expressive" },
                    { displayName: Translation.tr("Sculpt"),     icon: "shapes",    value: "sculpt" }
                ]
            }
        }

        ContentSubsection {
            title: Translation.tr("Popup style")
            icon: "style"
            tooltip: Translation.tr("Choose the layout for the Bluetooth devices popup in the bar")
            ConfigSelectionArray {
                currentValue: Config.options.bar.bluetoothDevicesLayout === "expressive" ? "expressive" : "classic"
                onSelected: newValue => {
                    Config.options.bar.bluetoothDevicesLayout = String(newValue);
                }
                options: [
                    { displayName: Translation.tr("Default"),    icon: "style",     value: "classic" },
                    { displayName: Translation.tr("Expressive"), icon: "fluid_med", value: "expressive" }
                ]
            }
        }

        ExpressiveColorModeSubsection {
            visible: Config.options.bar.styles.bluetooth === "expressive" || Config.options.bar.styles.bluetooth === "sculpt"
            currentValue: Config.options.bar.bluetooth.colorMode
            onSelected: newValue => Config.options.bar.bluetooth.colorMode = String(newValue)
        }

        ContentSubsection {
            visible: Config.options.bar.styles.bluetooth === "sculpt"
            title: Translation.tr("Sculpt variant")

            ConfigSelectionArray {
                currentValue: Config.options.bar.bluetooth.sculptVariant
                onSelected: newValue => Config.options.bar.bluetooth.sculptVariant = String(newValue)
                options: [
                    { displayName: Translation.tr("Card"), icon: "wallet", value: "card" },
                    { displayName: Translation.tr("Ring"), icon: "motion_photos_on", value: "ring" },
                    { displayName: Translation.tr("Badge"), icon: "verified", value: "badge" }
                ]
            }
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: Config.options.bar.styles.bluetooth === "sculpt" && Config.options.bar.bluetooth.sculptVariant === "card"
            materialIcon: "wallet"
            text: Translation.tr("A pass from a wallet app: the device's name set huge and cropped behind a scalloped seal and the battery.")
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: Config.options.bar.styles.bluetooth === "sculpt" && Config.options.bar.bluetooth.sculptVariant === "ring"
            materialIcon: "motion_photos_on"
            text: Translation.tr("The battery as a wavy ring around the device, and the percentage in tall digits whose weight follows the charge.")
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: Config.options.bar.styles.bluetooth === "sculpt" && Config.options.bar.bluetooth.sculptVariant === "badge"
            materialIcon: "verified"
            text: Translation.tr("The charge inside a scalloped cookie that changes shape as it drains, the device on a small disc over its corner, and the name beside it.")
        }

        ConfigSwitch {
            visible: Config.options.bar.styles.bluetooth === "sculpt" && (Config.options.bar.bluetooth.sculptVariant !== "ring")
            buttonIcon: "badge"
            text: Translation.tr("Show the device's name")
            checked: Config.options.bar.bluetooth.sculptShowName
            onCheckedChanged: Config.options.bar.bluetooth.sculptShowName = checked
            StyledToolTip {
                text: Translation.tr("Card: the name as the large cropped type (off = the charge). Badge: the name and status beside the cookie.")
            }
        }
    }
}
