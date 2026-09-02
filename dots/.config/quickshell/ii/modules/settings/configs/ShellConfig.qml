import QtQuick
import QtQuick.Layouts

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.panels.shellSwitcher

/**
 * Which shell this device runs.
 *
 * First page on purpose. Every other page configures surfaces that only exist in some
 * families — the Tablet page is listed for one of them, the Dock page is hidden from
 * another — so this is the setting that decides what the rest of Settings is even about.
 * Before it existed the choice was reachable only by IPC and by a keybind, which is to say
 * it was not reachable.
 */
Item {
    id: shellRoot
    anchors.fill: parent

    ContentPage {
        anchors.fill: parent
        forceWidth: false

        ContentSection {
            title: Translation.tr("Interface")
            icon: "swap_horiz"

            NoticeBox {
                Layout.fillWidth: true
                materialIcon: "info"
                text: Translation.tr("Switching rebuilds every panel on screen, which takes a moment. Your settings are kept: each family only decides which surfaces are drawn, and none of them rewrites what you have configured.")
            }

            // The same cards the full-screen chooser uses. One visual language for one
            // decision, whether it is made from Settings or from a gesture.
            Flow {
                Layout.fillWidth: true
                Layout.topMargin: 6
                spacing: 14

                Repeater {
                    model: PanelFamily.available

                    delegate: ShellFamilyCard {
                        id: familyCard
                        required property var modelData

                        family: familyCard.modelData
                        isCurrent: familyCard.modelData.id === PanelFamily.current
                        // No cascade here: a settings page is not an entrance, and a card
                        // that animates in every time the page is opened reads as a glitch.
                        shown: true

                        onClicked: PanelFamily.select(familyCard.modelData.id)
                    }
                }
            }
        }

        ContentSection {
            title: Translation.tr("Elsewhere")
            icon: "open_in_new"

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "swap_horiz"
                mainText: Translation.tr("Open the full-screen chooser")
                onClicked: GlobalStates.shellSwitcherOpen = true
            }

            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: 4
                text: PanelFamily.touchFirst
                    ? Translation.tr("Also on the notification shade's bottom row, and bindable as the \"Switch Shell\" gesture or the panelFamilyPicker shortcut. On the command line: qs -c ii ipc call panelFamily pick")
                    : Translation.tr("Bindable as the \"Switch Shell\" gesture or the panelFamilyPicker shortcut. On the command line: qs -c ii ipc call panelFamily pick")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                wrapMode: Text.Wrap
            }
        }
    }
}
