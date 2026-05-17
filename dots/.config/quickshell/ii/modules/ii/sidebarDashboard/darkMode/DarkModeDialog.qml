import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

WindowDialog {
    id: root
    backgroundHeight: 250

    WindowDialogTitle {
        text: Translation.tr("Appearance")
    }
    
    WindowDialogSectionHeader {
        text: Translation.tr("Dark Mode")
    }

    WindowDialogSeparator {
        Layout.topMargin: -22
        Layout.leftMargin: 0
        Layout.rightMargin: 0
    }

    Column {
        Layout.topMargin: -16
        Layout.fillWidth: true

        ConfigSwitch {
            anchors {
                left: parent.left
                right: parent.right
            }
            iconSize: Appearance.font.pixelSize.larger
            buttonIcon: "dark_mode"
            text: Translation.tr("Enable now")
            checked: Appearance.m3colors.darkmode
            onCheckedChanged: {
                if (checked !== Appearance.m3colors.darkmode) {
                    if (checked) {
                        Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--mode", "dark", "--noswitch"]);
                    } else {
                        Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--mode", "light", "--noswitch"]);
                    }
                }
            }
        }

        ConfigSwitch {
            anchors {
                left: parent.left
                right: parent.right
            }
            iconSize: Appearance.font.pixelSize.larger
            buttonIcon: "schedule"
            text: Translation.tr("Auto Dark Mode (18:00 - 06:00)")
            checked: Config.options.light.darkMode.automatic
            onCheckedChanged: {
                Config.options.light.darkMode.automatic = checked;
            }
        }
    }
    
    WindowDialogButtonRow {
        Layout.fillWidth: true

        Item {
            Layout.fillWidth: true
        }

        DialogButton {
            buttonText: Translation.tr("Done")
            onClicked: root.dismiss()
        }
    }
}
