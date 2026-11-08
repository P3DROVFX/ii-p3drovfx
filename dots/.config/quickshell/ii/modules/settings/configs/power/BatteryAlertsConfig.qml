import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/** Power → Battery alerts: the warning levels and the automatic suspend, as plain options. */
ContentPage {
    id: root
    forceWidth: false
    property bool showBackButton: false
    signal goBack()

    ConfigSubPageHeader {
        visible: root.showBackButton
        title: Translation.tr("Battery alerts")
        onBack: root.goBack()
    }

    ContentSection {
        icon: "notifications_active"
        title: Translation.tr("Warnings")

        ConfigSpinBox {
            icon: "warning"
            text: Translation.tr("Low warning (%)")
            value: Config.options.battery.low
            from: 0
            to: 100
            stepSize: 5
            onValueChanged: Config.options.battery.low = value
        }

        ConfigSpinBox {
            icon: "dangerous"
            text: Translation.tr("Critical warning (%)")
            value: Config.options.battery.critical
            from: 0
            to: 100
            stepSize: 5
            onValueChanged: Config.options.battery.critical = value
        }

        ConfigSpinBox {
            icon: "charger"
            text: Translation.tr("Full battery warning (%)")
            value: Config.options.battery.full
            from: 0
            to: 101
            stepSize: 5
            onValueChanged: Config.options.battery.full = value
            StyledToolTip {
                text: Translation.tr("101 never warns: the firmware charge limit or 100 % ends the charge instead")
            }
        }

        ConfigSwitch {
            buttonIcon: "battery_status_good"
            text: Translation.tr("Announce when charging finishes")
            checked: Config.options.battery.notifyCharged ?? true
            onCheckedChanged: Config.options.battery.notifyCharged = checked
            StyledToolTip {
                text: Translation.tr("One notification per charge, whether it ends at 100 %, at the firmware charge limit, or at the level set above.")
            }
        }
    }

    ContentSection {
        icon: "mode_standby"
        title: Translation.tr("Automatic suspend")

        ConfigSwitch {
            buttonIcon: "pause"
            text: Translation.tr("Suspend when the battery runs low")
            checked: Config.options.battery.automaticSuspend
            onCheckedChanged: Config.options.battery.automaticSuspend = checked
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
            onValueChanged: Config.options.battery.suspend = value
        }

        ConfigSpinBox {
            enabled: Config.options.battery.automaticSuspend
            icon: "timer"
            text: Translation.tr("Warn before suspending (s)")
            value: Config.options.battery.suspendWarningSeconds ?? 30
            from: 0
            to: 300
            stepSize: 5
            onValueChanged: Config.options.battery.suspendWarningSeconds = value
            StyledToolTip {
                text: Translation.tr("A cancellable warning before the automatic suspend. 0 suspends without warning.")
            }
        }
    }
}
