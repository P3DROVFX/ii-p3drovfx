import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

ContentPage {
    id: root

    forceWidth: false

    ContentSection {
        icon: "battery_android_full"
        title: Translation.tr("Power & Battery Management")

        ConfigSpinBox {
            icon: "warning"
            text: Translation.tr("Low warning (%)")
            value: Config.options.battery.low
            from: 0
            to: 100
            stepSize: 5
            onValueChanged: {
                Config.options.battery.low = value;
            }
        }

        ConfigSpinBox {
            icon: "dangerous"
            text: Translation.tr("Critical warning (%)")
            value: Config.options.battery.critical
            from: 0
            to: 100
            stepSize: 5
            onValueChanged: {
                Config.options.battery.critical = value;
            }
        }

        ConfigSwitch {
            buttonIcon: "pause"
            text: Translation.tr("Automatic suspend")
            checked: Config.options.battery.automaticSuspend
            onCheckedChanged: {
                Config.options.battery.automaticSuspend = checked;
            }
            StyledToolTip {
                text: Translation.tr("Automatically suspends the system when battery is low")
            }
        }

        ConfigSpinBox {
            enabled: Config.options.battery.automaticSuspend
            icon: "mode_standby"
            text: Translation.tr("Suspend at (%)")
            value: Config.options.battery.suspend
            from: 0
            to: 100
            stepSize: 5
            onValueChanged: {
                Config.options.battery.suspend = value;
            }
        }

        ConfigSpinBox {
            icon: "charger"
            text: Translation.tr("Full battery warning (%)")
            value: Config.options.battery.full
            from: 0
            to: 101
            stepSize: 5
            onValueChanged: {
                Config.options.battery.full = value;
            }
        }
    }

    ContentSection {
        icon: "link"
        title: Translation.tr("Related settings")

        Flow {
            Layout.fillWidth: true
            spacing: 8

            RelatedChip {
                pageId: "bar"
                label: Translation.tr("Battery bar widget")
                sectionHighlight: Translation.tr("Widgets")
            }
        }
    }
}
