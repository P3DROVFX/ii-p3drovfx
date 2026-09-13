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

    readonly property var options: Config.options.launcher.typeToSearch

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
                text: Translation.tr("Type to search")
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                color: Appearance.colors.colOnLayer0
            }
        }

        ContentSection {
            icon: "keyboard"
            title: Translation.tr("Type to search")
            tooltip: Translation.tr("Start typing with nothing focused and the launcher opens with what you typed already in it.")

            ConfigSwitch {
                buttonIcon: "keyboard"
                text: Translation.tr("Open the launcher when you start typing")
                checked: subPageRoot.options.enable
                onCheckedChanged: subPageRoot.options.enable = checked
                StyledToolTip {
                    text: Translation.tr("While this is waiting, those keys are registered as Hyprland shortcuts, so they reach nothing else. It only arms when no window has keyboard focus and no shell panel is open — never while you are typing in an application.")
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                visible: subPageRoot.options.enable
                spacing: Appearance.sizes.elevationMargin / 2

                ContentSubsectionLabel { text: Translation.tr("When it listens") }

                ConfigSelectionArray {
                    currentValue: subPageRoot.options.trigger
                    onSelected: newValue => subPageRoot.options.trigger = newValue
                    options: [
                        { displayName: Translation.tr("Empty workspace"), icon: "check_box_outline_blank", value: "emptyWorkspace" },
                        { displayName: Translation.tr("Nothing focused"), icon: "highlight_off", value: "noFocusedWindow" }
                    ]
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.leftMargin: 4
                    wrapMode: Text.WordWrap
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    text: subPageRoot.options.trigger === "noFocusedWindow"
                        ? Translation.tr("Also after clicking the desktop next to an open window.")
                        : Translation.tr("Only while the workspace you are on holds no windows at all.")
                }

                ContentSubsectionLabel { text: Translation.tr("Keys that open it") }

                ConfigSelectionArray {
                    currentValue: subPageRoot.options.keys
                    onSelected: newValue => subPageRoot.options.keys = newValue
                    options: [
                        { displayName: Translation.tr("Letters"), icon: "abc", value: "letters" },
                        { displayName: Translation.tr("Letters & digits"), icon: "pin", value: "alphanumeric" },
                        { displayName: Translation.tr("Everything printable"), icon: "keyboard_alt", value: "all" }
                    ]
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.leftMargin: 4
                    wrapMode: Text.WordWrap
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    text: Translation.tr("Letters follow your keyboard layout and always work. Digits are bound unshifted, so on AZERTY the number row types & é \" ( instead — those characters are covered by the last option.")
                }
            }
        }
    }
}
