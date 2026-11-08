import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/** Power → Keep awake: how long it lasts, the timers it offers and the expiry warning. */
ContentPage {
    id: root
    forceWidth: false
    property bool showBackButton: false
    signal goBack()

    ConfigSubPageHeader {
        visible: root.showBackButton
        title: Translation.tr("Keep awake")
        onBack: root.goBack()
    }

    ContentSection {
        icon: "coffee"
        title: Translation.tr("Keep awake")

        ContentSubsection {
            title: Translation.tr("Remember Keep awake")
            icon: "coffee"
            tooltip: Translation.tr("Restores the Keep awake toggle after a restart. A forgotten inhibitor can keep the system from sleeping, so this is limited to the current session by default.")
            Layout.fillWidth: true

            ConfigSelectionArray {
                currentValue: Config.options.idle.persistInhibit
                onSelected: newValue => Config.options.idle.persistInhibit = newValue
                options: [
                    { "displayName": Translation.tr("Never"), "icon": "block", "value": "never" },
                    { "displayName": Translation.tr("Until reboot"), "icon": "restart_alt", "value": "session" },
                    { "displayName": Translation.tr("Always"), "icon": "all_inclusive", "value": "always" }
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
            onCheckedChanged: Config.options.idle.notifyOnExpiry = checked
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
            onValueChanged: Config.options.idle.warnLeadSec = value
        }

        ConfigSpinBox {
            icon: "more_time"
            text: Translation.tr("Extend button adds (min)")
            value: Config.options.idle.extendMinutes
            from: 1
            to: 120
            stepSize: 5
            onValueChanged: Config.options.idle.extendMinutes = value
        }
    }
}
