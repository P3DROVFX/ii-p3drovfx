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
        spacing: 4
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
            text: {
                const fromStr = Config.options?.light?.darkMode?.from ?? "18:00";
                const toStr = Config.options?.light?.darkMode?.to ?? "06:00";
                const fromH = Number(fromStr.split(":")[0]);
                const fromM = Number(fromStr.split(":")[1]);
                const toH = Number(toStr.split(":")[0]);
                const toM = Number(toStr.split(":")[1]);

                const startTime = new Date();
                startTime.setHours(fromH, fromM, 0, 0);
                const endTime = new Date();
                endTime.setHours(toH, toM, 0, 0);

                const format = Config.options?.time.format ?? "hh:mm";
                const startStr = Qt.locale().toString(startTime, format);
                const endStr = Qt.locale().toString(endTime, format);
                return Translation.tr("Auto Dark Mode (%1 - %2)").arg(startStr).arg(endStr);
            }
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
