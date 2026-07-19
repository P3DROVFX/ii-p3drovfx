import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: page
    forceWidth: false

    ContentSection {
        title: Translation.tr("Notifications")
        icon: "notifications"

        ConfigSpinBox {
            icon: "timer"
            text: Translation.tr("Timeout duration (ms)")
            value: Config.options.notifications.timeout
            from: 1000
            to: 10000
            stepSize: 500
            onValueChanged: {
                Config.options.notifications.timeout = value;
            }
        }

        ConfigSpinBox {
            icon: "zoom_in"
            text: Translation.tr("Notification size (%)")
            value: Config.options.notifications.zoomPercent
            from: 50
            to: 200
            stepSize: 10
            onValueChanged: {
                Config.options.notifications.zoomPercent = value;
            }
        }

        ConfigSwitch {
            buttonIcon: "desktop_windows"
            text: Translation.tr("Force specific monitor")
            checked: Config.options.notifications.monitor.enable
            onCheckedChanged: {
                Config.options.notifications.monitor.enable = checked;
            }
        }

        ConfigTextField {
            text: Translation.tr("Force monitor name")
            icon: "desktop_windows"
            visible: Config.options.notifications.monitor.enable
            placeholderText: Translation.tr("Monitor Name (e.g. eDP-1)")
            inputText: Config.options.notifications.monitor.name

            textField.onTextChanged: {
                if (textField.activeFocus) {
                    Config.options.notifications.monitor.name = textField.text;
                }
            }
        }

        ConfigSwitch {
            buttonIcon: "counter_2"
            text: Translation.tr("Show unread count")
            checked: Config.options.bar.indicators.notifications.showUnreadCount
            onCheckedChanged: {
                Config.options.bar.indicators.notifications.showUnreadCount = checked;
            }
        }

        ContentSubsection {
            title: Translation.tr("Notification indicator style")
            icon: "notifications"

            ConfigSelectionArray {
                currentValue: Config.options.bar.styles.notification
                onSelected: newValue => { Config.options.bar.styles.notification = newValue; }
                options: [
                    { displayName: Translation.tr("Default"),    icon: "style",     value: "default" },
                    { displayName: Translation.tr("Expressive"), icon: "fluid_med", value: "expressive" }
                ]
            }
        }

        ContentSubsection {
            title: Translation.tr("Notification position")
            icon: "place"

            ConfigSelectionArray {
                currentValue: Config.options.notifications.position
                onSelected: newValue => { Config.options.notifications.position = newValue; }
                options: [
                    { displayName: Translation.tr("Top Left"),     icon: "north_west", value: "top_left" },
                    { displayName: Translation.tr("Top Right"),    icon: "north_east", value: "top_right" },
                    { displayName: Translation.tr("Bottom Left"),  icon: "south_west", value: "bottom_left" },
                    { displayName: Translation.tr("Bottom Right"), icon: "south_east", value: "bottom_right" }
                ]
            }
        }
}
