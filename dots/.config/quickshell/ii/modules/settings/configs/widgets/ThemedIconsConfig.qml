import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: subPageRoot
    anchors.fill: parent

    property bool showBackButton: false
    signal goBack()

    ContentPage {
        id: page
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
                text: Translation.tr("Themed Icons")
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                color: Appearance.colors.colOnLayer0
            }
        }

        ContentSection {
            title: Translation.tr("Themed Icons Configuration")
            icon: "category"

            ConfigSwitch {
                buttonIcon: "magic_button"
                text: Translation.tr("Enable themed icons")
                checked: Config.options.appearance.icons.enableThemed
                onCheckedChanged: IconThemes.setThemed(checked)

                StyledToolTip {
                    text: Translation.tr("When enabled, uses the dynamic Matugen generated icon pack. Fallbacks to Tint Icons.")
                }
            }

            ContentSubsection {
                visible: Config.options.appearance.icons.enableThemed
                title: Translation.tr("Base icon theme")
                icon: "palette"
                Layout.fillWidth: true
                tooltip: Translation.tr("Select the base icon theme to be recolored by Matugen.\nRequires generating colors again to apply.")

                ConfigSelectionArray {
                    currentValue: Config.options.appearance.iconTheme
                    onSelected: (newValue) => {
                        Config.options.appearance.iconTheme = newValue;
                    }
                    options: IconThemes.availableThemes.map((theme) => {
                        return ({
                            "displayName": theme,
                            "value": theme,
                            "icon": "category"
                        });
                    })
                }
            }

            RippleButtonWithIcon {
                visible: Config.options.appearance.icons.enableThemed
                materialIcon: "magic_button"
                mainText: Translation.tr("Apply Theme")
                useDynamicRadius: true
                implicitHeight: 48
                Layout.fillWidth: true
                colBackground: Appearance.colors.colPrimaryContainer
                colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                colRipple: Appearance.colors.colPrimaryContainerActive
                colText: Appearance.colors.colOnPrimaryContainer
                onClicked: {
                    IconThemes.applyTheme(false);
                }
            }

            ConfigSwitch {
                buttonIcon: "restart_alt"
                text: Translation.tr("Auto restart Quickshell on theme change")
                checked: Config.options.appearance.wallpaperTheming.autoRestartQuickshell
                onCheckedChanged: {
                    Config.options.appearance.wallpaperTheming.autoRestartQuickshell = checked;
                }
            }
        }
    }
}
