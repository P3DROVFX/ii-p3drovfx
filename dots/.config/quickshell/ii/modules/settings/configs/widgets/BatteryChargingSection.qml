import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Charge-limit readout plus the settings that decide what the shell says when charging ends and
 * what it does when the battery runs out. Shared by the Power page and its core-settings twin.
 */
ContentSection {
    id: root

    icon: "battery_profile"
    title: Translation.tr("Charging & warnings")
    visible: Battery.available

    readonly property string limitHeadline: {
        if (!Battery.chargeLimitResolved)
            return Translation.tr("This machine does not expose a charge limit");
        if (!Battery.chargeLimitActive)
            return Translation.tr("No charge limit — charges to 100 %");
        if (Battery.chargeLimitReached)
            return Translation.tr("Holding at %1 %").arg(Battery.chargeLimit);
        return Translation.tr("Charging stops at %1 %").arg(Battery.chargeLimit);
    }

    readonly property string limitDetail: {
        if (!Battery.chargeLimitResolved)
            return Translation.tr("Set one with your vendor's tool or TLP and it will be picked up here.");
        if (!Battery.chargeLimitActive)
            return Translation.tr("Read from the kernel, not from UPower, which keeps stale values.");
        if (Battery.chargeLimitStart > 0)
            return Translation.tr("Charging resumes below %1 %, so the level drifting down while plugged in is normal.").arg(Battery.chargeLimitStart);
        return Translation.tr("Firmware waits a few points before topping up, so the level drifting down while plugged in is normal.");
    }

    ContentSubsection {
        title: Translation.tr("Firmware charge limit")
        icon: "battery_profile"
        tooltip: Translation.tr("Read from /sys/class/power_supply. The shell only reports it; changing it is your vendor tool's or TLP's job.")
        Layout.fillWidth: true

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            MaterialSymbol {
                text: Battery.chargeLimitActive ? "battery_profile" : "battery_full"
                iconSize: Appearance.font.pixelSize.huge
                color: Battery.chargeLimitActive ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                Layout.alignment: Qt.AlignTop
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                StyledText {
                    Layout.fillWidth: true
                    text: root.limitHeadline
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                    wrapMode: Text.Wrap
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.limitDetail
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.Wrap
                }
            }
        }
    }

    ConfigSwitch {
        buttonIcon: "battery_status_good"
        text: Translation.tr("Announce when charging finishes")
        checked: Config.options.battery.notifyCharged ?? true
        onCheckedChanged: {
            Config.options.battery.notifyCharged = checked;
        }
        StyledToolTip {
            text: Translation.tr("One notification per charge, whether it ends at 100 %, at the firmware charge limit, or at the level set below.")
        }
    }

    ConfigSpinBox {
        enabled: Config.options.battery.automaticSuspend
        icon: "timer"
        text: Translation.tr("Warn before suspending (s)")
        value: Config.options.battery.suspendWarningSeconds ?? 30
        from: 0
        to: 300
        stepSize: 5
        onValueChanged: {
            Config.options.battery.suspendWarningSeconds = value;
        }
        StyledToolTip {
            text: Translation.tr("A cancellable warning before the automatic suspend. 0 suspends without warning.")
        }
    }
}
