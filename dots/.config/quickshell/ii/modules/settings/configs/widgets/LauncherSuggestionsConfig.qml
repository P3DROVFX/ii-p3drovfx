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
                text: Translation.tr("Idle Search Suggestions")
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                color: Appearance.colors.colOnLayer0
            }
        }

        ContentSection {
            icon: "auto_awesome"
            title: Translation.tr("Empty Query Suggestions")

            ConfigSwitch {
                buttonIcon: "auto_awesome"
                text: Translation.tr("Show suggestions when Search opens")
                checked: Config.options.search.suggestions.enable
                onCheckedChanged: {
                    Config.options.search.suggestions.enable = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Fills the normal Search results with apps, panels, toggles and more as soon as it opens — before you type anything")
                }
            }

            ConfigSwitch {
                visible: Config.options.search.suggestions.enable
                buttonIcon: "trending_up"
                text: Translation.tr("Show suggested strip")
                checked: Config.options.search.suggestions.showFrecency
                onCheckedChanged: Config.options.search.suggestions.showFrecency = checked
                StyledToolTip {
                    text: Translation.tr("A short strip of favorites and your most-used apps and panels, ranked by frequency and recency of use")
                }
            }

            ConfigSwitch {
                visible: Config.options.search.suggestions.enable
                buttonIcon: "apps"
                text: Translation.tr("Show applications section")
                checked: Config.options.search.suggestions.showApps
                onCheckedChanged: Config.options.search.suggestions.showApps = checked
            }

            ConfigSwitch {
                visible: Config.options.search.suggestions.enable
                buttonIcon: "toggle_on"
                text: Translation.tr("Show quick toggles section")
                checked: Config.options.search.suggestions.showToggles
                onCheckedChanged: Config.options.search.suggestions.showToggles = checked
            }

            ConfigSwitch {
                visible: Config.options.search.suggestions.enable
                buttonIcon: "terminal"
                text: Translation.tr("Show system commands section")
                checked: Config.options.search.suggestions.showCommands
                onCheckedChanged: Config.options.search.suggestions.showCommands = checked
            }

            ConfigSwitch {
                visible: Config.options.search.suggestions.enable
                buttonIcon: "widgets"
                text: Translation.tr("Show panels section")
                checked: Config.options.search.suggestions.showPanels
                onCheckedChanged: Config.options.search.suggestions.showPanels = checked
                StyledToolTip {
                    text: Translation.tr("Lists every built-in Search panel — Settings, Clipboard, Bluetooth and the rest")
                }
            }

            ConfigSwitch {
                visible: Config.options.search.suggestions.enable
                buttonIcon: "link"
                text: Translation.tr("Show quick links section")
                checked: Config.options.search.suggestions.showQuicklinks
                onCheckedChanged: Config.options.search.suggestions.showQuicklinks = checked
            }

            ConfigSwitch {
                visible: Config.options.search.suggestions.enable
                buttonIcon: "keyboard_command_key"
                text: Translation.tr("Show aliases section")
                checked: Config.options.search.suggestions.showAliases
                onCheckedChanged: Config.options.search.suggestions.showAliases = checked
            }

            ConfigSpinBox {
                visible: Config.options.search.suggestions.enable && Config.options.search.suggestions.showFrecency
                icon: "format_list_numbered"
                text: Translation.tr("Max items in the Suggestions strip")
                value: Config.options.search.suggestions.maxSuggestionsPerSection
                from: 2
                to: 10
                stepSize: 1
                onValueChanged: Config.options.search.suggestions.maxSuggestionsPerSection = value
                StyledToolTip {
                    text: Translation.tr("Only limits the top frecency-ranked strip. Every other section below lists everything it has.")
                }
            }
        }
    }
}
