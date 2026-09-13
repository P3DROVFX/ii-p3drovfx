import QtQuick
import qs.services
import ".."

/**
 * A system figure is above `above` (or below `below`): CPU / GPU load and
 * memory, swap and disk use in percent, CPU / GPU temperature in °C.
 * 5 units of hysteresis so a value hovering on the line does not flap.
 */
ModeCondition {
    id: root
    readonly property string metric: root.params?.metric ?? "cpuUsage"
    readonly property var above: root.params?.above ?? null
    readonly property var below: root.params?.below ?? null
    readonly property real hysteresis: 5

    readonly property real value: {
        switch (root.metric) {
        case "cpuUsage":
            return ResourceUsage.cpuUsage * 100;
        case "cpuTemp":
            return ResourceUsage.cpuTemp;
        case "gpuUsage":
            return ResourceUsage.gpuUsage * 100;
        case "gpuTemp":
            return ResourceUsage.gpuTemp;
        case "memory":
            return ResourceUsage.memoryUsedPercentage * 100;
        case "swap":
            return ResourceUsage.swapUsedPercentage * 100;
        case "disk":
            return ResourceUsage.diskUsedPercentage * 100;
        }
        return 0;
    }
    readonly property string unit: root.metric.endsWith("Temp") ? "°C" : "%"

    property bool over: false
    function reevaluate() {
        const v = root.value;
        if (root.above !== null) {
            const line = Number(root.above);
            root.over = root.over ? v > line - root.hysteresis : v > line;
            return;
        }
        if (root.below !== null) {
            const line = Number(root.below);
            root.over = root.over ? v < line + root.hysteresis : v < line;
            return;
        }
        root.over = false;
    }
    onValueChanged: root.reevaluate()
    onAboveChanged: root.reevaluate()
    onBelowChanged: root.reevaluate()
    Component.onCompleted: root.reevaluate()

    satisfied: root.over
    reason: `${Math.round(root.value)} ${root.unit}`
}
