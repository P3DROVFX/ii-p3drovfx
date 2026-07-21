pragma Singleton

import qs.services
import qs.modules.common
import Quickshell
import Quickshell.Services.UPower
import QtQuick
import Quickshell.Io

Singleton {
    id: root
    property bool available: UPower.displayDevice.isLaptopBattery
    property var chargeState: UPower.displayDevice.state
    property bool isCharging: chargeState == UPowerDeviceState.Charging
    property bool isPluggedIn: isCharging || chargeState == UPowerDeviceState.PendingCharge || chargeState == UPowerDeviceState.Full
    property real percentage: UPower.displayDevice?.percentage ?? 1
    readonly property bool allowAutomaticSuspend: Config.options.battery.automaticSuspend

    property bool isLow: available && (percentage <= Config.options.battery.low / 100)
    property bool isCritical: available && (percentage <= Config.options.battery.critical / 100)
    property bool isSuspending: available && (percentage <= Config.options.battery.suspend / 100)
    property bool isFull: available && (percentage >= Config.options.battery.full / 100)

    property bool isLowAndNotCharging: isLow && !isCharging
    property bool isCriticalAndNotCharging: isCritical && !isCharging
    property bool isSuspendingAndNotCharging: allowAutomaticSuspend && isSuspending && !isCharging
    property bool isFullAndCharging: isFull && isCharging

    property real energyRate: UPower.displayDevice.changeRate
    property real timeToEmpty: UPower.displayDevice.timeToEmpty
    property real timeToFull: UPower.displayDevice.timeToFull

    property real health: (function() {
        const devList = UPower.devices.values;
        for (let i = 0; i < devList.length; ++i) {
            const dev = devList[i];
            if (dev.isLaptopBattery && dev.healthSupported) {
                const health = dev.healthPercentage;
                if (health === 0) {
                    return 0.01;
                } else if (health < 1) {
                    return health * 100;
                } else {
                    return health;
                }
            }
        }
        return 0;
    })()

    property string batteryNativePath: {
        const devList = UPower.devices.values;
        for (let i = 0; i < devList.length; ++i) {
            const dev = devList[i];
            if (dev.isLaptopBattery) {
                return dev.nativePath;
            }
        }
        return "";
    }

    property int cycles: -1

    // Charge limit: standard kernel ABI first, then known vendor-specific locations (TLP-style)
    readonly property var chargeLimitCandidates: {
        const paths = [];
        if (batteryNativePath) {
            paths.push({ path: `/sys/class/power_supply/${batteryNativePath}/charge_control_end_threshold`, type: "plain" });
            paths.push({ path: `/sys/devices/platform/smapi/${batteryNativePath}/stop_charge_thresh`, type: "plain" });
        }
        paths.push({ path: "/sys/devices/platform/huawei-wmi/charge_control_thresholds", type: "last" });
        paths.push({ path: "/sys/devices/platform/lg-laptop/battery_care_limit", type: "plain" });
        paths.push({ path: "/sys/devices/platform/sony-laptop/battery_care_limiter", type: "plain" });
        paths.push({ path: "/sys/devices/platform/samsung/battery_life_extender", type: "bool80" });
        return paths;
    }
    property int chargeLimitCandidateIndex: 0
    property int chargeLimit: 100 // 0 or 100 = no limit
    readonly property bool chargeLimitActive: available && chargeLimit > 0 && chargeLimit < 100

    // At the limit the firmware reports Discharging/PendingCharge at ~0W even though AC is plugged in,
    // so the AC line (UPower.onBattery) is the reliable signal, not the battery state
    readonly property bool chargeLimitReached: chargeLimitActive && !UPower.onBattery
        && !isCharging && (percentage * 100 >= chargeLimit - 1)

    // Time until the effective full point (charge limit if active, otherwise UPower's estimate)
    readonly property real timeToFullEffective: {
        if (!chargeLimitActive) return timeToFull;
        const dev = UPower.displayDevice;
        const rate = Math.abs(dev.changeRate);
        if (dev.energyCapacity > 0 && rate > 0.01) {
            const remaining = dev.energyCapacity * (chargeLimit / 100) - dev.energy;
            return Math.max(0, remaining / rate * 3600);
        }
        if (percentage < 1 && timeToFull > 0) {
            return timeToFull * Math.max(0, chargeLimit / 100 - percentage) / (1 - percentage);
        }
        return 0;
    }

    function parseChargeLimit(content, type) {
        if (type === "bool80") return content === "1" ? 80 : 100;
        const parts = content.split(/\s+/);
        const val = parseInt(type === "last" ? parts[parts.length - 1] : parts[0], 10);
        if (isNaN(val) || val <= 0) return 100;
        return Math.min(val, 100);
    }

    FileView {
        id: chargeLimitFile
        path: root.chargeLimitCandidates[root.chargeLimitCandidateIndex]?.path ?? ""
        onLoaded: {
            const candidate = root.chargeLimitCandidates[root.chargeLimitCandidateIndex];
            root.chargeLimit = root.parseChargeLimit(text().trim(), candidate.type);
        }
        onLoadFailed: {
            if (root.chargeLimitCandidateIndex < root.chargeLimitCandidates.length - 1) {
                root.chargeLimitCandidateIndex++;
            } else {
                root.chargeLimit = 100;
            }
        }
    }

    FileView {
        id: cycleCountFile
        path: root.batteryNativePath ? `/sys/class/power_supply/${root.batteryNativePath}/cycle_count` : ""
        onLoaded: {
            const content = text().trim();
            const val = parseInt(content, 10);
            if (!isNaN(val)) {
                root.cycles = val;
            } else {
                root.cycles = -1;
            }
        }
        onLoadFailed: {
            root.cycles = -1;
        }
    }

    onBatteryNativePathChanged: {
        cycleCountFile.reload();
        root.chargeLimitCandidateIndex = 0;
        chargeLimitFile.reload();
    }

    onChargeStateChanged: {
        cycleCountFile.reload();
        root.chargeLimitCandidateIndex = 0;
        chargeLimitFile.reload();
    }

    onIsLowAndNotChargingChanged: {
        if (!root.available || !isLowAndNotCharging) return;
        Quickshell.execDetached([
            "notify-send", 
            Translation.tr("Low battery"), 
            Translation.tr("Consider plugging in your device"), 
            "-u", "critical",
            "-a", "Shell",
            "--hint=int:transient:1",
            "--hint=boolean:suppress-sound:true",
        ])

        SoundService.playEvent("battery", ["battery-low", "dialog-warning"]);
    }

    onIsCriticalAndNotChargingChanged: {
        if (!root.available || !isCriticalAndNotCharging) return;
        Quickshell.execDetached([
            "notify-send", 
            Translation.tr("Critically low battery"), 
            Translation.tr("Please charge!\nAutomatic suspend triggers at %1%").arg(Config.options.battery.suspend), 
            "-u", "critical",
            "-a", "Shell",
            "--hint=int:transient:1",
            "--hint=boolean:suppress-sound:true",
        ]);

        SoundService.playEvent("battery", ["battery-caution", "suspend-error", "dialog-error"]);
    }

    onIsSuspendingAndNotChargingChanged: {
        if (root.available && isSuspendingAndNotCharging) {
            Quickshell.execDetached(["bash", "-c", `systemctl suspend || loginctl suspend`]);
        }
    }

    onIsFullAndChargingChanged: {
        if (!root.available || !isFullAndCharging) return;
        Quickshell.execDetached([
            "notify-send",
            Translation.tr("Battery full"),
            Translation.tr("Please unplug the charger"),
            "-a", "Shell",
            "--hint=int:transient:1",
            "--hint=boolean:suppress-sound:true",
        ]);

        SoundService.playEvent("battery", ["battery-full", "complete", "dialog-information"]);
    }

    onIsPluggedInChanged: {
        if (!root.available) return;
        if (isPluggedIn) {
            SoundService.playEvent("battery", "power-plug");
        } else {
            SoundService.playEvent("battery", "power-unplug");
        }
    }
}
