pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Simple polled resource usage service with RAM, Swap, and CPU usage.
 */
Singleton {
    id: root
	property real memoryTotal: 1
	property real memoryFree: 0
	property real memoryUsed: memoryTotal - memoryFree
    property real memoryUsedPercentage: memoryUsed / memoryTotal
    property real diskTotal: 1
    property real diskFree: 0
    property real diskUsed: 0
    property real diskUsedPercentage: diskTotal > 0 ? (diskUsed / diskTotal) : 0
    property real swapTotal: 1
	property real swapFree: 0
	property real swapUsed: swapTotal - swapFree
    property real swapUsedPercentage: swapTotal > 0 ? (swapUsed / swapTotal) : 0
    property real cpuUsage: 0
    property var previousCpuStats
    property real cpuTemp: 0
    property real cpuFreqMhz: 0
    property real gpuUsage: 0
    property real gpuPowerW: 0
    property real gpuTemp: 0

    property string cpuModel: "--"
    property string gpuModel: "--"

    property string maxAvailableMemoryString: kbToGbString(ResourceUsage.memoryTotal)
    property string maxAvailableSwapString: kbToGbString(ResourceUsage.swapTotal)
    property string maxAvailableCpuString: "--"

    readonly property int historyLength: Config?.options.resources.historyLength ?? 60
    property list<real> cpuUsageHistory: []
    property list<real> memoryUsageHistory: []
    property list<real> swapUsageHistory: []

    function kbToGbString(kb) {
        return (kb / (1024 * 1024)).toFixed(1) + " GB";
    }

    function updateMemoryUsageHistory() {
        memoryUsageHistory = [...memoryUsageHistory, memoryUsedPercentage]
        if (memoryUsageHistory.length > historyLength) {
            memoryUsageHistory.shift()
        }
    }
    function updateSwapUsageHistory() {
        swapUsageHistory = [...swapUsageHistory, swapUsedPercentage]
        if (swapUsageHistory.length > historyLength) {
            swapUsageHistory.shift()
        }
    }
    function updateCpuUsageHistory() {
        cpuUsageHistory = [...cpuUsageHistory, cpuUsage]
        if (cpuUsageHistory.length > historyLength) {
            cpuUsageHistory.shift()
        }
    }
    function updateHistories() {
        updateMemoryUsageHistory()
        updateSwapUsageHistory()
        updateCpuUsageHistory()
    }

	Timer {
		interval: 1
        running: true 
        repeat: true
		onTriggered: {
            // Reload files
            fileMeminfo.reload()
            fileStat.reload()

            // Parse memory and swap usage
            const textMeminfo = fileMeminfo.text()
            memoryTotal = Number(textMeminfo.match(/MemTotal: *(\d+)/)?.[1] ?? 1)
            memoryFree = Number(textMeminfo.match(/MemAvailable: *(\d+)/)?.[1] ?? 0)
            swapTotal = Number(textMeminfo.match(/SwapTotal: *(\d+)/)?.[1] ?? 1)
            swapFree = Number(textMeminfo.match(/SwapFree: *(\d+)/)?.[1] ?? 0)

            // Parse CPU usage
            const textStat = fileStat.text()
            const cpuLine = textStat.match(/^cpu\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)/)
            if (cpuLine) {
                const stats = cpuLine.slice(1).map(Number)
                const total = stats.reduce((a, b) => a + b, 0)
                const idle = stats[3]

                if (previousCpuStats) {
                    const totalDiff = total - previousCpuStats.total
                    const idleDiff = idle - previousCpuStats.idle
                    cpuUsage = totalDiff > 0 ? (1 - idleDiff / totalDiff) : 0
                }

                previousCpuStats = { total, idle }
            }

            root.updateHistories()
            interval = Config.options?.resources?.updateInterval ?? 3000
        }
	}

	FileView { id: fileMeminfo; path: "/proc/meminfo" }
    FileView { id: fileStat; path: "/proc/stat" }

    Process {
        id: findCpuMaxFreqProc
        command: ["bash", "-c", "LANG=C LC_ALL=C lscpu | grep 'CPU max MHz' | awk '{print $4}'"]
        running: true
        stdout: StdioCollector {
            id: outputCollector
            onStreamFinished: {
                root.maxAvailableCpuString = (parseFloat(outputCollector.text) / 1000).toFixed(0) + " GHz"
            }
        }
    }

    Process {
        id: cpuModelProc
        command: ["bash", "-c", "LANG=C LC_ALL=C grep -m1 'model name' /proc/cpuinfo | sed 's/model name\\s*:\\s*//'"]
        running: true
        stdout: StdioCollector {
            id: cpuModelCollector
            onStreamFinished: {
                const model = cpuModelCollector.text.trim()
                if (model.length > 0) root.cpuModel = model
            }
        }
    }

    Process {
        id: gpuModelProc
        command: ["bash", "-c", "nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null || (lspci | grep -i 'vga\\|3d\\|display' | head -1 | sed 's/.*: //')"]
        running: true
        stdout: StdioCollector {
            id: gpuModelCollector
            onStreamFinished: {
                const model = gpuModelCollector.text.trim()
                if (model.length > 0) root.gpuModel = model
            }
        }
    }

    Process {
        id: diskSpaceProc
        command: ["bash", "-c", "while true; do LANG=C LC_ALL=C df -B1 / | awk 'NR==2{print $2, $3, $4}'; sleep 5; done"]
        running: true
        stdout: SplitParser {
            onRead: data => {
                const parts = data.trim().split(/\s+/)
                if (parts.length >= 3) {
                    root.diskTotal = Number(parts[0])
                    root.diskUsed = Number(parts[1])
                    root.diskFree = Number(parts[2])
                }
            }
        }
    }

    Process {
        id: hardwareMonitorProc
        command: ["bash", "-c", 
            "while true; do " + 
            "cpu_freq=$(awk '/cpu MHz/ {s+=$4; n++} END {if(n>0) print int(s/n)}' /proc/cpuinfo); " +
            "cpu_temp=0; " +
            "for hw in /sys/class/hwmon/hwmon*; do " +
            "if [ -f \"$hw/name\" ]; then " +
            "name=$(cat \"$hw/name\" 2>/dev/null); " +
            "if [ \"$name\" = \"k10temp\" ] || [ \"$name\" = \"zenpower\" ] || [ \"$name\" = \"coretemp\" ]; then " +
            "for t_input in \"$hw\"/temp*_input; do " +
            "if [ -f \"$t_input\" ]; then " +
            "temp_val=$(cat \"$t_input\" 2>/dev/null); " +
            "if [ -n \"$temp_val\" ] && [ \"$temp_val\" -gt 0 ]; then " +
            "cpu_temp=\"$temp_val\"; " +
            "break 2; " +
            "fi; " +
            "fi; " +
            "done; " +
            "fi; " +
            "fi; " +
            "done; " +
            "if [ -z \"$cpu_temp\" ] || [ \"$cpu_temp\" -eq 0 ]; then " +
            "for tz in /sys/class/thermal/thermal_zone*; do " +
            "if [ -f \"$tz/type\" ] && [ -f \"$tz/temp\" ]; then " +
            "type=$(cat \"$tz/type\" 2>/dev/null); " +
            "if [ \"$type\" = \"x86_pkg_temp\" ] || [ \"$type\" = \"cpu-thermal\" ] || [ \"$type\" = \"cpu_thermal\" ] || [ \"$type\" = \"TCPU\" ] || [ \"$type\" = \"cpu\" ]; then " +
            "temp_val=$(cat \"$tz/temp\" 2>/dev/null); " +
            "if [ -n \"$temp_val\" ] && [ \"$temp_val\" -gt 0 ]; then " +
            "cpu_temp=\"$temp_val\"; " +
            "break; " +
            "fi; " +
            "fi; " +
            "fi; " +
            "done; " +
            "fi; " +
            "if [ -z \"$cpu_temp\" ] || [ \"$cpu_temp\" -eq 0 ]; then " +
            "for tz in /sys/class/thermal/thermal_zone*; do " +
            "if [ -f \"$tz/type\" ] && [ -f \"$tz/temp\" ]; then " +
            "type=$(cat \"$tz/type\" 2>/dev/null); " +
            "if [ \"$type\" = \"acpitz\" ]; then " +
            "temp_val=$(cat \"$tz/temp\" 2>/dev/null); " +
            "if [ -n \"$temp_val\" ] && [ \"$temp_val\" -gt 0 ]; then " +
            "cpu_temp=\"$temp_val\"; " +
            "break; " +
            "fi; " +
            "fi; " +
            "fi; " +
            "done; " +
            "fi; " +
            "gpu_stats=\"\"; " +
            "if command -v nvidia-smi >/dev/null 2>&1; then " +
            "gpu_stats=$(nvidia-smi --query-gpu=utilization.gpu,power.draw,temperature.gpu --format=csv,noheader,nounits 2>/dev/null); " +
            "fi; " +
            "if [ -z \"$gpu_stats\" ] || [ \"$gpu_stats\" = \"0, 0, 0\" ]; then " +
            "amd_path=\"\"; " +
            "for card in /sys/class/drm/card*/device; do " +
            "if [ -f \"$card/gpu_busy_percent\" ]; then " +
            "amd_path=\"$card\"; " +
            "break; " +
            "fi; " +
            "done; " +
            "if [ -n \"$amd_path\" ]; then " +
            "amd_usage=$(cat \"$amd_path/gpu_busy_percent\" 2>/dev/null || echo 0); " +
            "amd_temp=0; " +
            "for hwmon in \"$amd_path\"/hwmon/hwmon*/temp1_input; do " +
            "if [ -f \"$hwmon\" ]; then " +
            "raw_temp=$(cat \"$hwmon\" 2>/dev/null || echo 0); " +
            "amd_temp=$((raw_temp / 1000)); " +
            "break; " +
            "fi; " +
            "done; " +
            "amd_power=0; " +
            "for hwmon in \"$amd_path\"/hwmon/hwmon*/power1_average \"$amd_path\"/hwmon/hwmon*/power1_input; do " +
            "if [ -f \"$hwmon\" ]; then " +
            "raw_power=$(cat \"$hwmon\" 2>/dev/null || echo 0); " +
            "amd_power=$((raw_power / 1000000)); " +
            "break; " +
            "fi; " +
            "done; " +
            "gpu_stats=\"$amd_usage, $amd_power, $amd_temp\"; " +
            "fi; " +
            "fi; " +
            "if [ -z \"$gpu_stats\" ]; then " +
            "gpu_stats=\"0, 0, 0\"; " +
            "fi; " +
            "echo \"${cpu_freq:-0} ${cpu_temp:-0} $gpu_stats\"; " + 
            "sleep 3; done"
        ]
        running: true
        stdout: SplitParser {
            onRead: data => {
                const parts = data.trim().split(/[\s,]+/)
                if (parts.length >= 5) {
                    root.cpuFreqMhz = Number(parts[0])
                    root.cpuTemp = Number(parts[1]) / 1000
                    root.gpuUsage = Number(parts[2]) / 100
                    root.gpuPowerW = Number(parts[3])
                    root.gpuTemp = Number(parts[4])
                }
            }
        }
    }
}
