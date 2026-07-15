pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

// Polled resource usage service: RAM, Swap, CPU, Disk, GPU.
// - proc/stat, /proc/meminfo and CPU temperature read via FileView
//   in a single Timer tick - no bash forks.
// - Disk usage is sampled every `diskInterval` ms through a one-shot
//   Process (`df`) driven by a QML Timer.
// - GPU monitoring auto-detects vendor on boot; on hybrid systems the
//   monitored GPU can be forced via Config.options.resources.gpuPreference:
//   - NVIDIA = one-shot nvidia-smi triggered by a QML Timer.
//   - AMD    = sysfs gpu_busy_percent and hwmon temp1_input via
//              FileView (zero-cost, no fork).
//   - Intel  = per-client DRM fdinfo counters aggregated by a one-shot
//              bash+awk (xe: cycles/total-cycles, i915: engine ns);
//              usage is computed here from deltas between ticks.
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

	property bool gpuMonitoringEnabled: false
	onGpuMonitoringEnabledChanged: {
		if (!gpuMonitoringEnabled) {
			gpuUsage = 0
			gpuTemp = 0
			previousIntelGpuSample = null
		}
	}

    // ── GPU vendor detection ────────────────────────────────────────
    // Detected once on boot. Drives which subsystem we poll for stats.
    //   "nvidia" → nvidia-smi one-shot (Timer-driven)
    //   "amd"    → sysfs FileView (zero-cost, no fork)
    //   "intel"  → DRM fdinfo engine counters + coretemp/thermal_zone
    //   "unknown" → no monitoring
    property string gpuVendor: "unknown"

    // "auto" keeps the NVIDIA → AMD → Intel priority; anything else forces
    // that vendor's probe first (hybrid iGPU+dGPU systems), falling back to
    // the auto cascade if the preferred vendor isn't found.
    property string gpuPreference: Config.options?.resources?.gpuPreference ?? "auto"
    onGpuPreferenceChanged: {
        gpuModelProc.running = false
        gpuModelProc.running = true
    }

    // AMD sysfs paths (resolved once after vendor detection)
    property string amdUsagePath: ""      // /sys/class/drm/card*/device/gpu_busy_percent
    property string amdTempPath: ""       // /sys/class/drm/card*/device/hwmon/hwmon*/temp1_input

    FileView { id: amdUsageFileView }
    FileView { id: amdTempFileView }

    FileView { id: cpuTempFileView }
	property string cpuTempPath: ""

    Process {
        id: locateCpuTempPathProc
        command: ["bash", "-c", "for hw in /sys/class/hwmon/hwmon*; do if [ -f \"$hw/name\" ]; then name=$(cat \"$hw/name\" 2>/dev/null); if [ \"$name\" = \"k10temp\" ] || [ \"$name\" = \"zenpower\" ] || [ \"$name\" = \"coretemp\" ]; then for t_input in \"$hw\"/temp*_input; do if [ -f \"$t_input\" ]; then echo \"$t_input\"; exit 0; fi; done; fi; fi; done; for tz in /sys/class/thermal/thermal_zone*; do if [ -f \"$tz/type\" ] && [ -f \"$tz/temp\" ]; then type=$(cat \"$tz/type\" 2>/dev/null); if [ \"$type\" = \"x86_pkg_temp\" ] || [ \"$type\" = \"cpu-thermal\" ] || [ \"$type\" = \"cpu_thermal\" ] || [ \"$type\" = \"TCPU\" ] || [ \"$type\" = \"cpu\" ] || [ \"$type\" = \"acpitz\" ]; then echo \"$tz/temp\"; exit 0; fi; fi; done"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                root.cpuTempPath = text.trim()
                if (root.cpuTempPath) {
                    cpuTempFileView.path = root.cpuTempPath
                }
            }
        }
    }

    // ── CPU/RAM polling Timer (drives FileView reloads) ─────────────
    // No more `while true; do` bash loops. One QML Timer per subsystem,
    // reuses FileView instances that just reload files in-place.
	Timer {
        id: cpuRamTimer
		interval: 1
		running: true
		repeat: true
		onTriggered: {
			// Reload files
			fileMeminfo.reload()
			fileStat.reload()
			if (root.cpuTempPath) {
				cpuTempFileView.reload()
				const rawTemp = Number(cpuTempFileView.text().trim() || 0)
				root.cpuTemp = rawTemp > 1000 ? rawTemp / 1000 : rawTemp
			}

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

			// AMD GPU stats via sysfs (zero-cost, no fork)
			if (root.gpuVendor === "amd" && root.gpuMonitoringEnabled) {
				if (root.amdUsagePath) {
					amdUsageFileView.reload()
					const usage = Number(amdUsageFileView.text().trim() || 0)
					root.gpuUsage = usage / 100
				}
				if (root.amdTempPath) {
					amdTempFileView.reload()
					const rawTemp = Number(amdTempFileView.text().trim() || 0)
					root.gpuTemp = rawTemp > 1000 ? rawTemp / 1000 : rawTemp
				}
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

    // GPU model + vendor detection in one shot. Previously nvidia-smi was
    // called on every model fetch AND in an infinite loop. Now we run
    // nvidia-smi exactly once on boot; if present, vendor="nvidia".
    // Otherwise the path probe inside discovers AMD/Intel via sysfs/lspci.
    Process {
        id: gpuModelProc
        command: ["bash", "-c",
            "detect_nvidia() { " +
            "  if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1; then " +
            "    echo 'NVIDIA|'$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null); return 0; " +
            "  fi; return 1; " +
            "}; " +
            "detect_amd() { " +
            "  for card in /sys/class/drm/card*/device; do " +
            "    if [ -f \"$card/gpu_busy_percent\" ]; then " +
            "      model=$(cat \"$card/device\" 2>/dev/null || basename $(dirname \"$card\")); " +
            "      echo \"AMD|$model\"; return 0; " +
            "    fi; " +
            "  done; return 1; " +
            "}; " +
            "detect_intel() { " +
            "  model=$(lspci 2>/dev/null | grep -i 'vga\\|3d\\|display' | grep -i -m1 intel | sed 's/.*: //'); " +
            "  if [ -n \"$model\" ]; then echo \"INTEL|$model\"; return 0; fi; return 1; " +
            "}; " +
            "case \"$GPUPREF\" in " +
            "  nvidia) detect_nvidia && exit 0 ;; " +
            "  amd) detect_amd && exit 0 ;; " +
            "  intel) detect_intel && exit 0 ;; " +
            "esac; " +
            "detect_nvidia && exit 0; " +
            "detect_amd && exit 0; " +
            "model=$(lspci 2>/dev/null | grep -i -m1 'vga\\|3d\\|display' | sed 's/.*: //'); " +
            "if echo \"$model\" | grep -qi 'intel'; then " +
            "  echo \"INTEL|$model\"; " +
            "else " +
            "  echo \"UNKNOWN|$model\"; " +
            "fi"
        ]
        environment: ({
            GPUPREF: root.gpuPreference
        })
        running: true
        stdout: StdioCollector {
            id: gpuModelCollector
            onStreamFinished: {
                const line = gpuModelCollector.text.trim()
                if (line.length === 0) {
                    root.gpuVendor = "unknown"
                    return
                }
                const parts = line.split("|")
                const vendor = parts[0].toLowerCase()
                const model = parts[1] || ""
                root.gpuVendor = vendor === "nvidia" ? "nvidia"
                              : vendor === "amd" ? "amd"
                              : vendor === "intel" ? "intel"
                              : "unknown"
                if (model.length > 0) root.gpuModel = model

                if (root.gpuVendor === "amd") {
                    // Resolve AMD sysfs paths once for cheap FileView polling
                    amdPathResolveProc.running = true
                }
            }
        }
    }

    // One-shot bash to resolve AMD hwmon paths (can't be done from QML).
    Process {
        id: amdPathResolveProc
        command: ["bash", "-c",
            "for card in /sys/class/drm/card*/device; do " +
            "  if [ -f \"$card/gpu_busy_percent\" ]; then " +
            "    echo \"USAGE=$card/gpu_busy_percent\"; " +
            "    for hwmon in \"$card\"/hwmon/hwmon*/temp1_input; do " +
            "      if [ -f \"$hwmon\" ]; then " +
            "        echo \"TEMP=$hwmon\"; break; " +
            "      fi; " +
            "    done; " +
            "    exit 0; " +
            "  fi; " +
            "done"
        ]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n")
                lines.forEach(line => {
                    if (line.startsWith("USAGE=")) {
                        root.amdUsagePath = line.slice(7)
                        amdUsageFileView.path = root.amdUsagePath
                    } else if (line.startsWith("TEMP=")) {
                        root.amdTempPath = line.slice(5)
                        amdTempFileView.path = root.amdTempPath
                    }
                })
            }
        }
    }

    // ── Disk space polling — no more `while true; do df; sleep 5; done` ─
    // One-shot `df` invocation driven by a QML Timer. Each tick forks a
    // short-lived bash that dies immediately after parsing stdout (no
    // zombie sleep loop waiting on a SIGTERM that never comes).
    Process {
        id: diskSpaceProc
        command: ["bash", "-c", "LANG=C LC_ALL=C df -B1 / | awk 'NR==2{print $2, $3, $4}'"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split(/\s+/)
                if (parts.length >= 3) {
                    root.diskTotal = Number(parts[0])
                    root.diskUsed = Number(parts[1])
                    root.diskFree = Number(parts[2])
                }
            }
        }
    }

    Timer {
        id: diskSpaceTimer
        interval: 30000
        repeat: true
        running: true
        onTriggered: {
            diskSpaceProc.running = false
            diskSpaceProc.running = true
            interval = Config.options?.resources?.diskInterval ?? 30000
        }
    }

    // ── NVIDIA/Intel GPU polling — one-shot Process per tick ─────────
    // Previous incarnation: an infinite `while true; do nvidia-smi; sleep 3`
    // bash loop. Each loop tick blocked a slot in the bash memory budget
    // (~30ms exec + 5MB temp). Now: a QML Timer spawns a one-shot Process
    // every `gpuInterval` ms when monitoring is enabled. When disabled,
    // neither the Timer nor any fork runs.
    //
    // Intel has no nvidia-smi/gpu_busy_percent equivalent readable without
    // CAP_PERFMON, so usage comes from per-client DRM fdinfo counters
    // (what nvtop uses): the script dumps cumulative busy counters per
    // client and engine class, and parseIntelGpuSample() below turns the
    // delta between two ticks into a busy percentage. fdinfo files are
    // streamed through `cat` because fds vanish mid-scan all the time and
    // gawk aborts on files it can't open; every fdinfo file starts with a
    // "pos:" line, which serves as the per-file boundary in the stream.
    // Only same-user clients are readable, which on a desktop covers the
    // compositor and all apps.
    property var previousIntelGpuSample: null

    function parseIntelGpuSample(out) {
        let nowNs = 0
        let temp = 0
        let driver = ""
        const clients = {}
        for (const line of out.split("\n")) {
            const p = line.trim().split(/\s+/)
            if (p[0] === "NOW") nowNs = Number(p[1])
            else if (p[0] === "TEMP") temp = Number(p[1])
            else if (p[0] === "DRIVER") driver = p[1]
            else if (p[0] === "E") clients[p[1] + "/" + p[2]] = { cls: p[2], busy: Number(p[3]), total: Number(p[4]) }
        }
        gpuTemp = temp

        const prev = previousIntelGpuSample
        previousIntelGpuSample = { nowNs, clients }
        if (!prev) return

        // Busy ratio per engine class, summed over clients. xe exposes a GT
        // timestamp per class (drm-total-cycles); i915 only reports ns, so
        // wall-clock is the denominator. Clients whose counters went
        // backwards (respawned) are skipped and re-baselined next tick.
        let maxBusy = 0
        const classBusy = {}
        for (const key in clients) {
            if (!(key in prev.clients)) continue
            const db = clients[key].busy - prev.clients[key].busy
            const dt = driver === "xe" ? clients[key].total - prev.clients[key].total : nowNs - prev.nowNs
            if (db <= 0 || dt <= 0) continue
            const cls = clients[key].cls
            classBusy[cls] = (classBusy[cls] ?? 0) + db / dt
            maxBusy = Math.max(maxBusy, classBusy[cls])
        }
        gpuUsage = Math.min(1, maxBusy)
    }

    Process {
        id: gpuMonitorProc
        command: ["bash", "-c",
            "if [ \"$GPUVENDOR\" = \"nvidia\" ] && command -v nvidia-smi >/dev/null 2>&1; then " +
            "  nvidia-smi --query-gpu=utilization.gpu,temperature.gpu --format=csv,noheader,nounits 2>/dev/null; " +
            "elif [ \"$GPUVENDOR\" = \"intel\" ]; then " +
            "  temp=0; " +
            "  for hw in /sys/class/hwmon/hwmon*; do " +
            "    if [ -f \"$hw/name\" ]; then " +
            "      name=$(cat \"$hw/name\" 2>/dev/null); " +
            "      if [ \"$name\" = \"coretemp\" ] || [ \"$name\" = \"intel-pch\" ]; then " +
            "        if [ -f \"$hw/temp1_input\" ]; then x=$(cat \"$hw/temp1_input\" 2>/dev/null || echo 0); temp=$((x/1000)); break; fi; " +
            "      fi; " +
            "    fi; " +
            "  done; " +
            "  if [ \"$temp\" -eq 0 ]; then " +
            "    for tz in /sys/class/thermal/thermal_zone*; do " +
            "      type=$(cat \"$tz/type\" 2>/dev/null); " +
            "      if [ \"$type\" = \"x86_pkg_temp\" ] || [ \"$type\" = \"cpu_thermal\" ]; then " +
            "        x=$(cat \"$tz/temp\" 2>/dev/null || echo 0); temp=$((x/1000)); break; " +
            "      fi; " +
            "    done; " +
            "  fi; " +
            "  echo \"NOW $(date +%s%N)\"; " +
            "  echo \"TEMP $temp\"; " +
            "  cat /proc/[0-9]*/fdinfo/* 2>/dev/null | awk '" +
            "    function flush(   k) { " +
            "      if ((drv == \"xe\" || drv == \"i915\") && cid != \"\" && !(cid in seen)) { " +
            "        seen[cid] = 1; gdrv = drv; " +
            "        for (k in c) print \"E\", cid, k, c[k], t[k] + 0; " +
            "      } " +
            "      drv = \"\"; cid = \"\"; delete c; delete t; " +
            "    } " +
            "    /^pos:/ { flush() } " +
            "    $1 == \"drm-driver:\" { drv = $2 } " +
            "    $1 == \"drm-client-id:\" { cid = $2 } " +
            "    /^drm-cycles-/ { cls = substr($1, 12); sub(/:$/, \"\", cls); c[cls] += $2 } " +
            "    /^drm-total-cycles-/ { cls = substr($1, 18); sub(/:$/, \"\", cls); if ($2 > t[cls]) t[cls] = $2 } " +
            "    /^drm-engine-/ && $3 == \"ns\" && $1 !~ /capacity/ { cls = substr($1, 12); sub(/:$/, \"\", cls); c[cls] += $2 } " +
            "    END { flush(); if (gdrv != \"\") print \"DRIVER\", gdrv } " +
            "  '; " +
            "else " +
            "  echo \"0, 0\"; " +
            "fi"
        ]
        environment: ({
            GPUVENDOR: root.gpuVendor
        })
        running: false
        stdout: StdioCollector {
            id: gpuMonitorCollector
            onStreamFinished: {
                const out = gpuMonitorCollector.text.trim()
                if (out.length === 0) return
                if (root.gpuVendor === "intel") {
                    root.parseIntelGpuSample(out)
                    return
                }
                const parts = out.split(/[\s,]+/)
                if (parts.length >= 2) {
                    root.gpuUsage = Number(parts[0]) / 100
                    root.gpuTemp = Number(parts[1])
                }
            }
        }
        onExited: {
            // One-shot, nothing to do. The Timer will respawn us next tick.
        }
    }

    Timer {
        id: gpuMonitorTimer
        interval: 2000
        repeat: true
        running: root.gpuMonitoringEnabled && (root.gpuVendor === "nvidia" || root.gpuVendor === "intel")
        onTriggered: {
            if (!root.gpuMonitoringEnabled) return
            if (root.gpuVendor !== "nvidia" && root.gpuVendor !== "intel") return
            gpuMonitorProc.running = false
            gpuMonitorProc.running = true
            interval = Config.options?.resources?.gpuInterval ?? 3000
        }
    }
}
