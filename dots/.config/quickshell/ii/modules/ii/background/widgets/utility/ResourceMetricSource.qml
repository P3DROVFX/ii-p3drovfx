import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/*
 * The metrics the Resource Columns and Resource Tiles widgets can show, in the
 * order the user picked them, and the sampling they need. ResourceUsage only
 * samples disk, temperature, swap and GPU while someone asks; this item holds
 * exactly the requests its keys need, and only while `active`.
 */
Item {
    id: root

    // Picked keys, in order; unknown keys are dropped.
    property var keys: []
    property bool active: true

    readonly property var catalog: ["cpu", "ram", "swap", "disk", "gpu", "cpuTemp", "gpuTemp", "battery"]
    readonly property var items: {
        const picked = (root.keys ?? []).filter((key, i, all) => root.catalog.indexOf(key) !== -1 && all.indexOf(key) === i);
        return picked.length > 0 ? picked : ["cpu"];
    }

    // A load past this reads as "hot": warning colour and the loud shape.
    readonly property real hotThreshold: 0.85

    function label(key) {
        switch (key) {
        case "cpu": return Translation.tr("CPU");
        case "ram": return Translation.tr("RAM");
        case "swap": return Translation.tr("Swap");
        case "disk": return Translation.tr("Disk");
        case "gpu": return Translation.tr("GPU");
        case "cpuTemp": return Translation.tr("CPU temp");
        case "gpuTemp": return Translation.tr("GPU temp");
        case "battery": return Translation.tr("Battery");
        }
        return key;
    }

    function icon(key) {
        switch (key) {
        case "cpu": return "memory";
        case "ram": return "memory_alt";
        case "swap": return "swap_horiz";
        case "disk": return "hard_drive";
        case "gpu": return "developer_board";
        case "cpuTemp": return "device_thermostat";
        case "gpuTemp": return "thermostat";
        case "battery": return Battery.isPluggedIn ? "battery_charging_full" : "battery_full";
        }
        return "monitoring";
    }

    // One resting shape per metric, so a row of them does not read as identical dots.
    function shape(key) {
        switch (key) {
        case "cpu": return MaterialShape.Shape.Cookie9Sided;
        case "ram": return MaterialShape.Shape.Clover4Leaf;
        case "swap": return MaterialShape.Shape.Pill;
        case "disk": return MaterialShape.Shape.Cookie6Sided;
        case "gpu": return MaterialShape.Shape.Gem;
        case "cpuTemp": return MaterialShape.Shape.Sunny;
        case "gpuTemp": return MaterialShape.Shape.Flower;
        case "battery": return MaterialShape.Shape.Bun;
        }
        return MaterialShape.Shape.Circle;
    }

    // 0..1. Temperatures map 0-100 °C.
    function value(key) {
        let v = 0;
        switch (key) {
        case "cpu": v = ResourceUsage.cpuUsage; break;
        case "ram": v = ResourceUsage.memoryUsedPercentage; break;
        case "swap": v = ResourceUsage.swapUsedPercentage; break;
        case "disk": v = ResourceUsage.diskUsedPercentage; break;
        case "gpu": v = ResourceUsage.gpuUsage; break;
        case "cpuTemp": v = ResourceUsage.cpuTemp / 100; break;
        case "gpuTemp": v = ResourceUsage.gpuTemp / 100; break;
        case "battery": v = Battery.percentage; break;
        }
        return Number.isFinite(v) ? Math.max(0, Math.min(1, v)) : 0;
    }

    // Battery is "hot" when it runs low, everything else when it runs high.
    function isHot(key) {
        if (key === "battery")
            return !Battery.isPluggedIn && root.value(key) <= 0.15;
        return root.value(key) >= root.hotThreshold;
    }

    function isTemperature(key) {
        return key === "cpuTemp" || key === "gpuTemp";
    }

    // The number itself, without its unit.
    function figure(key) {
        if (key === "cpuTemp")
            return String(Math.round(ResourceUsage.cpuTemp));
        if (key === "gpuTemp")
            return String(Math.round(ResourceUsage.gpuTemp));
        return String(Math.round(root.value(key) * 100));
    }

    function unit(key) {
        return root.isTemperature(key) ? "°" : "%";
    }

    function gb(kb) {
        return (kb / (1024 * 1024)).toFixed(1);
    }

    // A second line that adds something the figure does not say.
    function detail(key) {
        switch (key) {
        case "cpu":
            return ResourceUsage.cpuTemp > 0 ? Translation.tr("%1 °C").arg(Math.round(ResourceUsage.cpuTemp)) : Translation.tr("Processor");
        case "ram":
            return Translation.tr("%1 / %2 GB").arg(root.gb(ResourceUsage.memoryUsed)).arg(root.gb(ResourceUsage.memoryTotal));
        case "swap":
            return Translation.tr("%1 / %2 GB").arg(root.gb(ResourceUsage.swapUsed)).arg(root.gb(ResourceUsage.swapTotal));
        case "disk":
            return Translation.tr("%1 / %2 GB").arg(Math.round(ResourceUsage.diskUsed / (1024 * 1024 * 1024))).arg(Math.round(ResourceUsage.diskTotal / (1024 * 1024 * 1024)));
        case "gpu":
            return ResourceUsage.gpuTemp > 0 ? Translation.tr("%1 °C").arg(Math.round(ResourceUsage.gpuTemp)) : Translation.tr("Graphics");
        case "cpuTemp":
            return Translation.tr("Processor");
        case "gpuTemp":
            return Translation.tr("Graphics");
        case "battery":
            return Battery.isCharging ? Translation.tr("Charging") : (Battery.isPluggedIn ? Translation.tr("Plugged in") : Translation.tr("On battery"));
        }
        return "";
    }

    // ── Sampling requests ──
    readonly property bool wantTemperature: root.active && root.items.some(k => k === "cpu" || k === "cpuTemp")
    readonly property bool wantDisk: root.active && root.items.indexOf("disk") !== -1
    readonly property bool wantSwap: root.active && root.items.indexOf("swap") !== -1
    readonly property bool wantGpu: root.active && root.items.some(k => k === "gpu" || k === "gpuTemp")
    property bool _temperature: false
    property bool _disk: false
    property bool _swap: false
    property bool _gpu: false

    function sync() {
        if (root._temperature !== root.wantTemperature) {
            ResourceUsage.requestMetric("temperature", root.wantTemperature);
            root._temperature = root.wantTemperature;
        }
        if (root._disk !== root.wantDisk) {
            ResourceUsage.requestMetric("disk", root.wantDisk);
            root._disk = root.wantDisk;
        }
        if (root._swap !== root.wantSwap) {
            ResourceUsage.requestMetric("swap", root.wantSwap);
            root._swap = root.wantSwap;
        }
        if (root._gpu !== root.wantGpu) {
            ResourceUsage.requestGpuMonitoring(root.wantGpu);
            root._gpu = root.wantGpu;
        }
    }

    onWantTemperatureChanged: root.sync()
    onWantDiskChanged: root.sync()
    onWantSwapChanged: root.sync()
    onWantGpuChanged: root.sync()
    Component.onCompleted: root.sync()
    Component.onDestruction: {
        if (root._temperature)
            ResourceUsage.requestMetric("temperature", false);
        if (root._disk)
            ResourceUsage.requestMetric("disk", false);
        if (root._swap)
            ResourceUsage.requestMetric("swap", false);
        if (root._gpu)
            ResourceUsage.requestGpuMonitoring(false);
    }
}
