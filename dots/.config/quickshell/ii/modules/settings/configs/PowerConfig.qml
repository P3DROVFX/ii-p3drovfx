import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.settings.configs.widgets

ContentPage {
    id: root

    forceWidth: false

    ContentSection {
        icon: "battery_android_full"
        title: Translation.tr("Power & Battery Management")

        BatteryOverview {
            Layout.fillWidth: true
            Layout.bottomMargin: 16
        }

        BatteryUsageChart {
            Layout.fillWidth: true
            Layout.bottomMargin: 16
        }

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

        ContentSubsection {
            title: Translation.tr("Remember Keep awake")
            icon: "coffee"
            tooltip: Translation.tr("Restores the Keep awake toggle after a restart. A forgotten inhibitor can keep the system from sleeping, so this is limited to the current session by default.")
            Layout.fillWidth: true

            ConfigSelectionArray {
                currentValue: Config.options.idle.persistInhibit
                onSelected: newValue => {
                    Config.options.idle.persistInhibit = newValue;
                }
                options: [
                    {
                        "displayName": Translation.tr("Never"),
                        "icon": "block",
                        "value": "never"
                    },
                    {
                        "displayName": Translation.tr("Until reboot"),
                        "icon": "restart_alt",
                        "value": "session"
                    },
                    {
                        "displayName": Translation.tr("Always"),
                        "icon": "all_inclusive",
                        "value": "always"
                    }
                ]
            }
        }

        ContentSubsection {
            title: Translation.tr("Keep awake timers")
            icon: "hourglass_top"
            tooltip: Translation.tr("Right-clicking the Keep awake toggle offers these durations, and a timed session turns itself off when the time is up. The list keeps itself up to date: dial a duration the toggle doesn't offer yet and it takes the place of the oldest one.")
            Layout.fillWidth: true

            ConfigRow {
                Layout.fillWidth: true

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Offered durations: %1").arg(Idle.quickDurations.map(minutes => Idle.formatMinutes(minutes)).join(", "))
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.Wrap
                }

                RippleButtonWithIcon {
                    materialIcon: "restart_alt"
                    mainText: Translation.tr("Reset")
                    onClicked: Idle.resetDurations()
                }
            }
        }

        ConfigSwitch {
            buttonIcon: "notifications_active"
            text: Translation.tr("Warn before a timer ends")
            checked: Config.options.idle.notifyOnExpiry
            onCheckedChanged: {
                Config.options.idle.notifyOnExpiry = checked;
            }
            StyledToolTip {
                text: Translation.tr("Sends a notification shortly before the system is allowed to sleep again, with a button to add more time")
            }
        }

        ConfigSpinBox {
            enabled: Config.options.idle.notifyOnExpiry
            icon: "timer"
            text: Translation.tr("Warn this long before (s)")
            value: Config.options.idle.warnLeadSec
            from: 0
            to: 600
            stepSize: 15
            onValueChanged: {
                Config.options.idle.warnLeadSec = value;
            }
        }

        ConfigSpinBox {
            icon: "more_time"
            text: Translation.tr("Extend button adds (min)")
            value: Config.options.idle.extendMinutes
            from: 1
            to: 120
            stepSize: 5
            onValueChanged: {
                Config.options.idle.extendMinutes = value;
            }
        }
    }

    BatteryChargingSection {}

    ContentSection {
        icon: "keyboard"
        title: Translation.tr("Keyboard Backlight")
        visible: KeyboardBacklight.available

        ConfigSwitch {
            buttonIcon: "bedtime"
            text: Translation.tr("Turn off when idle")
            checked: Config.options.light.keyboardBacklight.autoOff
            onCheckedChanged: {
                Config.options.light.keyboardBacklight.autoOff = checked;
            }
            StyledToolTip {
                text: Translation.tr("Switches the backlight off after a period without keyboard or pointer input, then restores your level on the next input. Idle inhibitors are ignored, so it still applies during video playback.")
            }
        }

        ConfigSpinBox {
            enabled: Config.options.light.keyboardBacklight.autoOff
            icon: "timer"
            text: Translation.tr("Turn off after (s)")
            value: Config.options.light.keyboardBacklight.timeout
            from: 5
            to: 900
            stepSize: 5
            onValueChanged: {
                Config.options.light.keyboardBacklight.timeout = value;
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
