pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.services
import QtQuick
import Quickshell

// Facade over the shell's own GPU monitor (services/ResourceUsage.qml), speaking
// yunhai's GpuUsage geometry so the Akebono family's resource widgets can keep their
// iGPU/dGPU wording without bringing the plugin's SysMon into it.
//
// Only the monitored GPU is real data; the companion card is reported unavailable.
Singleton {
    id: root

    readonly property bool dGpuAvailable: ResourceUsage.gpuVendor !== "unknown" && ResourceUsage.gpuUsage >= 0
    readonly property string dGpuName: Config.options?.resources?.gpu?.dgpuName || ResourceUsage.gpuModel || "dGPU"
    readonly property string dGpuVendor: ResourceUsage.gpuVendor
    readonly property double dGpuUsage: ResourceUsage.gpuUsage
    readonly property double dGpuVramUsedGB: 0
    readonly property double dGpuVramTotalGB: 0
    readonly property double dGpuTemperature: ResourceUsage.gpuTemp
    readonly property double dGpuFanRpm: 0
    readonly property double dGpuFanUsage: 0
    readonly property double dGpuPower: ResourceUsage.gpuPowerW
    readonly property double dGpuPowerLimit: 0
    property list<real> dGpuUsageHistory: []
    readonly property string maxAvailableDGpuString: "\n" + root.dGpuName

    readonly property bool iGpuAvailable: false
    readonly property string iGpuName: Config.options?.resources?.gpu?.igpuName || "iGPU"
    readonly property string iGpuVendor: ""
    readonly property double iGpuUsage: 0
    readonly property double iGpuVramUsedGB: 0
    readonly property double iGpuVramTotalGB: 0
    readonly property double iGpuTemperature: 0
    property list<real> iGpuUsageHistory: []
    readonly property string maxAvailableIGpuString: "\n" + root.iGpuName

    readonly property int historyLength: Config?.options?.resources?.historyLength ?? 60

    Connections {
        target: ResourceUsage
        function onGpuSampled(value) {
            const h = [...root.dGpuUsageHistory, value];
            if (h.length > root.historyLength)
                h.shift();
            root.dGpuUsageHistory = h;
        }
    }
}