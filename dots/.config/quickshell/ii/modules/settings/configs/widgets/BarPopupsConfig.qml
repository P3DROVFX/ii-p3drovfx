import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: subPageRoot
    anchors.fill: parent
    property bool showBackButton: false
    signal goBack()

    ContentPage {
        anchors.fill: parent
        forceWidth: false

        RowLayout {
            visible: subPageRoot.showBackButton
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
                onClicked: subPageRoot.goBack()
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "arrow_back"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }
            StyledText {
                text: Translation.tr("Floating popups")
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                color: Appearance.colors.colOnLayer0
            }
        }

        ContentSection {
            title: Translation.tr("Floating popup services")
            icon: "open_in_new"

            ConfigSwitch {
                buttonIcon: "visibility"
                text: Translation.tr("Enable floating popups")
                checked: Config.options.bar.tooltips.enablePopups
                property bool readyForToggle: false
                Component.onCompleted: readyForToggle = true
                onCheckedChanged: {
                    if (!readyForToggle || !Config.ready)
                        return;
                    Config.options.bar.tooltips.enablePopups = checked;
                }
            }
            ConfigSwitch {
                enabled: Config.options.bar.tooltips.enablePopups
                buttonIcon: "colorize"
                text: Translation.tr("Enable color picker floating popup")
                checked: Config.options.bar.tooltips.enableColorPickerPopup
                onCheckedChanged: Config.options.bar.tooltips.enableColorPickerPopup = checked
            }
            ConfigSwitch {
                enabled: Config.options.bar.tooltips.enablePopups
                buttonIcon: "bluetooth"
                text: Translation.tr("Enable Bluetooth connection floating popup")
                checked: Config.options.bar.tooltips.enableBluetoothConnectionPopup
                onCheckedChanged: Config.options.bar.tooltips.enableBluetoothConnectionPopup = checked
            }
            ConfigSwitch {
                enabled: Config.options.bar.tooltips.enablePopups
                buttonIcon: "keyboard"
                text: Translation.tr("Enable keyboard layout transition floating popup")
                checked: Config.options.bar.tooltips.enableKeyboardLayoutTransitionPopup
                onCheckedChanged: Config.options.bar.tooltips.enableKeyboardLayoutTransitionPopup = checked
            }
        }
    }
}
