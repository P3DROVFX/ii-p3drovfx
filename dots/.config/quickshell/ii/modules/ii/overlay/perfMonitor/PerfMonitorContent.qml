pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/*
 * The performance HUD itself, RivaTuner style: FPS on top, then one block per
 * device (CPU + RAM, GPU + VRAM, battery) and a footer with the game, its
 * resolution and the driver. Every line is a toggle in
 * Config.options.overlay.perfMonitor and the card collapses around what is on.
 *
 * Styles: "bars" (usage as a labelled progress bar), "graph" (usage history),
 * "text" (one compact line per device). `fpsOnly` shrinks it to the frame rate.
 *
 * Also drawn by the Settings page as its live preview (`preview: true`), which
 * fills in example frame numbers while no game is logging.
 */
Rectangle {
    id: root

    property bool preview: false
    // Whether this HUD needs live numbers (held while it is on screen).
    property bool monitoring: true

    readonly property var cfg: Config.options.overlay.perfMonitor
    readonly property real s: Math.max(0.5, root.cfg.scale)
    readonly property string hudStyle: root.cfg.style
    readonly property bool textStyle: root.hudStyle === "text"
    readonly property bool graphStyle: root.hudStyle === "graph"
    readonly property real pad: Math.round((root.textStyle ? Appearance.rounding.verysmall : Appearance.rounding.small) * root.s)
    readonly property real gap: Math.round(Appearance.rounding.unsharpenmore * root.s)

    // Every size is a token scaled by the HUD's own scale, rounded so text
    // does not re-rasterise at fractional sizes.
    function px(token) {
        return Math.round(token * root.s);
    }
    readonly property var fontPx: Appearance.font.pixelSize
    readonly property var digitAxes: ({ "wght": 760, "wdth": 40, "ROND": 100 })
    readonly property var valueAxes: ({ "wght": 650 })

    implicitWidth: root.cfg.fpsOnly ? fpsOnlyRow.implicitWidth + root.pad * 2
        : root.textStyle ? column.implicitWidth + root.pad * 2
        : Math.round(root.cfg.width * root.s)
    implicitHeight: (root.cfg.fpsOnly ? fpsOnlyRow.implicitHeight : column.implicitHeight) + root.pad * 2
    radius: Math.round(Appearance.rounding.normal * root.s)
    // Semi-transparent and never blurred: the overlay layer has no blur rule.
    color: ColorUtils.transparentize(Appearance.m3colors.m3surfaceContainerLowest, 1 - root.cfg.backgroundOpacity)

    // ------------------------------------------------------------ sampling

    property bool _held: false
    function syncHold() {
        if (root.monitoring === root._held)
            return;
        if (root.monitoring)
            PerformanceStats.acquire();
        else
            PerformanceStats.release();
        root._held = root.monitoring;
    }
    onMonitoringChanged: syncHold()
    Component.onCompleted: syncHold()
    Component.onDestruction: {
        if (root._held)
            PerformanceStats.release();
    }

    // ------------------------------------------------------------ data

    readonly property var exampleFps: ({
        "active": true,
        "process": "Cyberpunk2077",
        "fps": 144,
        "avg": 138,
        "low1": 97,
        "low01": 71,
        "frametime": 6.9,
        "frametimes": [6.9, 7.1, 6.8, 7.4, 6.9, 7.0, 9.8, 7.2, 6.9, 6.8, 7.1, 7.0, 6.7, 7.3, 12.4, 7.1, 6.9, 7.0, 6.8, 7.2, 7.0, 6.9, 7.1, 7.5, 6.8, 7.0, 7.2, 6.9, 10.3, 7.0, 6.8, 7.1],
        "elapsed": 390
    })
    readonly property var fpsData: (root.preview && !PerformanceStats.fpsActive) ? root.exampleFps : PerformanceStats.fps
    readonly property bool hasFps: root.fpsData?.active ?? false

    readonly property var cpuData: PerformanceStats.cpu
    readonly property var ramData: PerformanceStats.ram
    readonly property var gpuData: PerformanceStats.gpu
    readonly property var gpuInfo: PerformanceStats.selectedGpu

    function fmtInt(value) {
        return (value === undefined || value === null || isNaN(value)) ? "--" : String(Math.round(value));
    }
    function fmtPct(value) {
        return (value === undefined || value === null || isNaN(value)) ? "--%" : `${Math.round(value * 100)}%`;
    }
    function fmtGb(bytes) {
        return (bytes / (1024 * 1024 * 1024)).toFixed(1);
    }
    function fmtWatts(watts) {
        return watts >= 10 ? watts.toFixed(0) : watts.toFixed(1);
    }
    function fmtMs(ms) {
        return (ms ?? 0).toFixed(1);
    }
    function fmtDuration(seconds) {
        if (seconds === undefined || seconds === null || seconds < 0)
            return "";
        const h = Math.floor(seconds / 3600);
        const m = Math.floor(seconds % 3600 / 60);
        const sec = Math.floor(seconds % 60);
        return `${h}:${String(m).padStart(2, "0")}:${String(sec).padStart(2, "0")}`;
    }
    function fmtRemaining(seconds) {
        if (!(seconds > 0))
            return "";
        const h = Math.floor(seconds / 3600);
        const m = Math.round(seconds % 3600 / 60);
        return h > 0 ? `${h}h ${m}m` : `${m}m`;
    }
    function memText(used, total, suffix) {
        if (!(total > 0))
            return suffix;
        return `${root.fmtGb(used)} / ${root.fmtGb(total)} GB ${suffix}`.trim();
    }

    // ------------------------------------------------------------ colours

    // One hue family per device: accent fills the usage bar, soft the memory bar.
    //   accent    — primary (CPU), tertiary (GPU), secondary (battery)
    //   container — the same families, on their containers
    //   mono      — surface tones only
    function tone(kind) {
        const c = Appearance.colors;
        if (root.cfg.palette === "mono") {
            return {
                "accent": c.colOnSurface,
                "onAccent": Appearance.m3colors.m3surfaceContainerLowest,
                "soft": c.colSurfaceContainerHighest,
                "onSoft": c.colOnSurface,
                "label": c.colOnSurface
            };
        }
        const family = kind === "gpu" ? [c.colTertiary, c.colOnTertiary, c.colTertiaryContainer, c.colOnTertiaryContainer]
            : kind === "battery" ? [c.colSecondary, c.colOnSecondary, c.colSecondaryContainer, c.colOnSecondaryContainer]
            : [c.colPrimary, c.colOnPrimary, c.colPrimaryContainer, c.colOnPrimaryContainer];
        if (root.cfg.palette === "container") {
            return {
                "accent": family[2],
                "onAccent": family[3],
                "soft": ColorUtils.mix(family[2], c.colSurfaceContainerHighest, 0.45),
                "onSoft": family[3],
                "label": family[0]
            };
        }
        return {
            "accent": family[0],
            "onAccent": family[1],
            "soft": family[2],
            "onSoft": family[3],
            "label": family[0]
        };
    }
    readonly property var cpuTone: root.tone("cpu")
    readonly property var gpuTone: root.tone("gpu")
    readonly property var batteryTone: root.tone("battery")

    readonly property color colText: Appearance.colors.colOnSurface
    readonly property color colDim: Appearance.colors.colOnSurfaceVariant
    readonly property color colHot: Appearance.colors.colError

    function fpsColor(value) {
        if (!root.cfg.colorCodeFps || !(value > 0))
            return root.colText;
        const target = Math.max(1, root.cfg.fpsTarget);
        if (value >= target * 0.95)
            return root.cfg.palette === "mono" ? root.colText : Appearance.colors.colPrimary;
        if (value >= target * 0.5)
            return Appearance.colors.colTertiary;
        return root.colHot;
    }

    // ------------------------------------------------------------ rows

    readonly property var cpuStats: {
        const c = root.cpuData ?? {};
        const out = [];
        if (root.cfg.showCpuTemp && c.temp !== undefined)
            out.push({ "value": root.fmtInt(c.temp), "unit": "°C", "hot": c.temp >= root.cfg.hotTemp, "icon": "thermostat" });
        if (root.cfg.showCpuClock && c.clock !== undefined)
            out.push({ "value": root.fmtInt(c.clock), "unit": "MHz", "icon": "speed" });
        if (root.cfg.showCpuPower && PerformanceStats.cpuPower !== null && PerformanceStats.cpuPower !== undefined)
            out.push({ "value": root.fmtWatts(PerformanceStats.cpuPower), "unit": "W", "icon": "bolt" });
        if (root.cfg.showSwap && (root.ramData?.swapTotal ?? 0) > 0)
            out.push({ "value": root.fmtGb(root.ramData.swapUsed), "unit": "GB swap", "icon": "swap_horiz" });
        return out;
    }

    readonly property var gpuStats: {
        const g = root.gpuData ?? {};
        const out = [];
        if (root.cfg.showGpuTemp && g.temp !== undefined)
            out.push({ "value": root.fmtInt(g.temp), "unit": "°C", "hot": g.temp >= root.cfg.hotTemp, "icon": "thermostat" });
        if (root.cfg.showGpuClock && g.clock !== undefined)
            out.push({ "value": root.fmtInt(g.clock), "unit": "MHz", "icon": "speed" });
        if (root.cfg.showGpuMemClock && g.memClock !== undefined)
            out.push({ "value": root.fmtInt(g.memClock), "unit": "MHz mem", "icon": "memory" });
        if (root.cfg.showGpuPower && PerformanceStats.gpuPower !== null && PerformanceStats.gpuPower !== undefined)
            out.push({ "value": root.fmtWatts(PerformanceStats.gpuPower), "unit": "W", "icon": "bolt" });
        if (root.cfg.showGpuFan && g.fan !== undefined)
            out.push({ "value": root.fmtInt(g.fan), "unit": "% fan", "icon": "mode_fan" });
        return out;
    }

    readonly property bool batteryShown: root.cfg.showBattery && Battery.available
    readonly property real batteryEnergy: Battery.device?.energy ?? 0
    readonly property var batteryStats: {
        const out = [];
        if (root.cfg.showBatteryPower && Battery.energyRate > 0)
            out.push({ "value": root.fmtWatts(Battery.energyRate), "unit": "W", "icon": "bolt" });
        if (root.cfg.showBatteryTime) {
            const left = root.fmtRemaining(Battery.isCharging ? Battery.timeToFull : Battery.timeToEmpty);
            if (left.length > 0)
                out.push({ "value": left, "unit": Battery.isCharging ? Translation.tr("to full") : Translation.tr("left"), "icon": "schedule" });
        }
        return out;
    }

    readonly property var gameWindow: GameDetector.focusedWindow
    readonly property string resolution: {
        const w = root.gameWindow;
        if (!w?.size || !(root.hasFps || GameDetector.gameFocused))
            return root.preview ? "2560×1440" : "";
        const monitor = HyprlandData.monitors.find(m => m.id === w.monitor);
        const scale = monitor?.scale ?? 1;
        return `${Math.round(w.size[0] * scale)}×${Math.round(w.size[1] * scale)}`;
    }
    readonly property string driverText: {
        const fromLog = root.hasFps ? (root.fpsData?.driver ?? "") : "";
        if (fromLog.length > 0)
            return fromLog;
        const info = root.gpuInfo;
        if (!info)
            return "";
        if (info.driverVersion)
            return Translation.tr("Driver %1").arg(String(info.driverVersion));
        return info.driver ?? "";
    }
    readonly property var footerItems: {
        const out = [];
        if (root.cfg.showProcess && root.hasFps && root.fpsData.process)
            out.push(root.fpsData.process);
        if (root.cfg.showResolution && root.resolution.length > 0)
            out.push(root.resolution);
        if (root.cfg.showDriver && root.driverText.length > 0)
            out.push(root.driverText);
        if (root.cfg.showSessionTime && root.hasFps && root.fpsData.elapsed !== null && root.fpsData.elapsed !== undefined)
            out.push(root.fmtDuration(root.fpsData.elapsed));
        if (root.cfg.showClock)
            out.push(DateTime.time);
        return out;
    }

    readonly property string cpuLabel: root.cfg.cpuName.length > 0 ? root.cfg.cpuName
        : root.textStyle ? "CPU" : (PerformanceStats.cpuModel || "CPU")
    readonly property string gpuLabel: root.cfg.gpuName.length > 0 ? root.cfg.gpuName
        : root.textStyle ? "GPU" : (root.gpuInfo?.name ?? "GPU")
    readonly property string batteryLabel: {
        const withEnergy = root.cfg.showBatteryEnergy && root.batteryEnergy > 0;
        if (root.textStyle)
            return withEnergy ? `BAT ${root.batteryEnergy.toFixed(0)} Wh` : "BAT";
        return withEnergy ? Translation.tr("Battery · %1 Wh").arg(root.batteryEnergy.toFixed(0)) : Translation.tr("Battery");
    }

    readonly property bool cpuShown: root.cfg.showCpu
    readonly property bool gpuShown: root.cfg.showGpu && (root.gpuInfo !== null || !PerformanceStats.ready)
    // RAM rides under the CPU block; on its own when the CPU block is off.
    readonly property bool ramStandalone: root.cfg.showRam && !root.cpuShown

    readonly property list<real> frametimes: root.hasFps ? (root.fpsData.frametimes ?? []) : []
    readonly property real frametimeCeiling: {
        // Twice the target frame time, or the worst spike if it is taller.
        let ceiling = 2000 / Math.max(1, root.cfg.fpsTarget);
        for (const v of root.frametimes)
            ceiling = Math.max(ceiling, v * 1.1);
        return ceiling;
    }

    // ------------------------------------------------------------ FPS-only

    RowLayout {
        id: fpsOnlyRow
        visible: root.cfg.fpsOnly
        anchors.centerIn: parent
        spacing: root.gap

        StyledText {
            Layout.alignment: Qt.AlignVCenter
            text: root.hasFps ? root.fmtInt(root.fpsData.fps) : "--"
            color: root.fpsColor(root.fpsData?.fps)
            font {
                family: Appearance.font.family.main
                variableAxes: root.digitAxes
                pixelSize: root.px(root.fontPx.huge * 1.5)
            }
        }
        ColumnLayout {
            Layout.alignment: Qt.AlignVCenter
            spacing: 0

            StyledText {
                text: "FPS"
                color: root.colDim
                font {
                    family: Appearance.font.family.title
                    variableAxes: Appearance.font.variableAxes.titleRounded
                    pixelSize: root.px(root.fontPx.smaller)
                }
            }
            StyledText {
                visible: root.cfg.showFpsLow1
                text: `1% ${root.hasFps ? root.fmtInt(root.fpsData.low1) : "--"}`
                color: root.colDim
                font {
                    family: Appearance.font.family.numbers
                    pixelSize: root.px(root.fontPx.smallest)
                }
            }
        }
    }

    // ------------------------------------------------------------ full HUD

    ColumnLayout {
        id: column
        visible: !root.cfg.fpsOnly
        anchors {
            left: parent.left
            right: root.textStyle ? undefined : parent.right
            top: parent.top
            margins: root.pad
        }
        spacing: root.textStyle ? root.px(2) : root.gap

        // Title
        StyledText {
            visible: root.cfg.title.length > 0
            Layout.fillWidth: !root.textStyle
            horizontalAlignment: root.textStyle ? Text.AlignLeft : Text.AlignHCenter
            text: root.cfg.title
            color: root.colText
            elide: Text.ElideRight
            font {
                family: Appearance.font.family.title
                variableAxes: Appearance.font.variableAxes.titleRounded
                pixelSize: root.px(root.textStyle ? root.fontPx.small : root.fontPx.larger)
                capitalization: root.cfg.uppercase ? Font.AllUppercase : Font.MixedCase
            }
        }

        // FPS block (bars / graph)
        ColumnLayout {
            visible: root.cfg.showFps && !root.textStyle
            Layout.fillWidth: true
            spacing: root.px(2)

            RowLayout {
                Layout.fillWidth: true
                spacing: root.gap

                StyledText {
                    Layout.alignment: Qt.AlignVCenter
                    text: "FPS"
                    color: root.colText
                    font {
                        family: Appearance.font.family.title
                        variableAxes: Appearance.font.variableAxes.titleRounded
                        pixelSize: root.px(root.fontPx.larger)
                    }
                }
                // The one number this HUD is about, in expressive digits
                StyledText {
                    Layout.alignment: Qt.AlignVCenter
                    text: root.hasFps ? root.fmtInt(root.fpsData.fps) : "--"
                    color: root.fpsColor(root.fpsData?.fps)
                    font {
                        family: Appearance.font.family.main
                        variableAxes: root.digitAxes
                        pixelSize: root.px(root.fontPx.huge * 1.9)
                    }
                }
                Item {
                    Layout.fillWidth: true
                }
                ColumnLayout {
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 0

                    FpsFigure {
                        shown: root.cfg.showFpsAverage
                        label: Translation.tr("Avg")
                        value: root.hasFps ? root.fmtInt(root.fpsData.avg) : "--"
                    }
                    FpsFigure {
                        shown: root.cfg.showFpsLow1
                        label: "1% low"
                        value: root.hasFps ? root.fmtInt(root.fpsData.low1) : "--"
                    }
                    FpsFigure {
                        shown: root.cfg.showFpsLow01
                        label: "0.1% low"
                        value: root.hasFps ? root.fmtInt(root.fpsData.low01) : "--"
                    }
                    FpsFigure {
                        shown: root.cfg.showFrametime && !root.cfg.showFrametimeGraph
                        label: Translation.tr("Frame")
                        value: root.hasFps ? `${root.fmtMs(root.fpsData.frametime)} ms` : "--"
                    }
                }
            }

            // Frame-time graph: spikes are stutters
            RowLayout {
                visible: root.cfg.showFrametimeGraph
                Layout.fillWidth: true
                spacing: root.gap

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: root.px(root.fontPx.huge * 1.3)
                    radius: Math.round(Appearance.rounding.verysmall * root.s)
                    color: ColorUtils.transparentize(root.cpuTone.accent, 0.88)

                    Graph {
                        anchors.fill: parent
                        anchors.margins: root.px(2)
                        values: root.frametimes.map(v => Math.min(1, v / root.frametimeCeiling))
                        points: Math.max(2, values.length)
                        color: root.cpuTone.label
                        fillOpacity: 0.25
                        alignment: Graph.Alignment.Right
                    }
                }
                ColumnLayout {
                    visible: root.cfg.showFrametime
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 0

                    StyledText {
                        Layout.alignment: Qt.AlignRight
                        text: root.hasFps ? root.fmtMs(root.fpsData.frametime) : "--"
                        color: root.colText
                        font {
                            family: Appearance.font.family.numbers
                            variableAxes: root.valueAxes
                            pixelSize: root.px(root.fontPx.small)
                        }
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignRight
                        text: "ms"
                        color: root.colDim
                        font {
                            pixelSize: root.px(root.fontPx.smallest)
                            capitalization: root.cfg.uppercase ? Font.AllUppercase : Font.MixedCase
                        }
                    }
                }
            }
        }

        // FPS line (text)
        TextLine {
            visible: root.cfg.showFps && root.textStyle
            label: "FPS"
            labelColor: root.cpuTone.label
            leadValue: root.hasFps ? root.fmtInt(root.fpsData.fps) : "--"
            leadColor: root.fpsColor(root.fpsData?.fps)
            leadSize: root.fontPx.larger
            stats: {
                const out = [];
                if (root.cfg.showFpsAverage)
                    out.push({ "value": root.hasFps ? root.fmtInt(root.fpsData.avg) : "--", "unit": Translation.tr("avg") });
                if (root.cfg.showFpsLow1)
                    out.push({ "value": root.hasFps ? root.fmtInt(root.fpsData.low1) : "--", "unit": "1%" });
                if (root.cfg.showFpsLow01)
                    out.push({ "value": root.hasFps ? root.fmtInt(root.fpsData.low01) : "--", "unit": "0.1%" });
                if (root.cfg.showFrametime)
                    out.push({ "value": root.hasFps ? root.fmtMs(root.fpsData.frametime) : "--", "unit": "ms" });
                return out;
            }
        }

        // CPU (+ RAM)
        DeviceBlock {
            visible: root.cpuShown
            label: root.cpuLabel
            deviceTone: root.cpuTone
            showUsage: root.cfg.showCpuUsage
            usage: root.cpuData?.usage ?? -1
            history: PerformanceStats.cpuHistory
            stats: root.cpuStats
            memShown: root.cfg.showRam
            memSuffix: "RAM"
            memUsed: root.ramData?.used ?? 0
            memTotal: root.ramData?.total ?? 0
        }

        // RAM on its own
        DeviceBlock {
            visible: root.ramStandalone
            label: root.textStyle ? "RAM" : root.memText(root.ramData?.used ?? 0, root.ramData?.total ?? 0, "RAM")
            deviceTone: root.cpuTone
            showUsage: true
            usage: (root.ramData?.total ?? 0) > 0 ? root.ramData.used / root.ramData.total : -1
            history: PerformanceStats.ramHistory
            stats: root.cfg.showSwap && (root.ramData?.swapTotal ?? 0) > 0
                ? [{ "value": root.fmtGb(root.ramData.swapUsed), "unit": "GB swap", "icon": "swap_horiz" }] : []
        }

        // GPU (+ VRAM)
        DeviceBlock {
            visible: root.gpuShown
            label: root.gpuLabel
            deviceTone: root.gpuTone
            showUsage: root.cfg.showGpuUsage
            usage: PerformanceStats.gpuSuspended ? 0 : (root.gpuData?.usage ?? -1)
            usageText: PerformanceStats.gpuSuspended ? Translation.tr("Sleeping") : ""
            history: PerformanceStats.gpuHistory
            stats: PerformanceStats.gpuSuspended ? [] : root.gpuStats
            memShown: root.cfg.showVram && (root.gpuData?.vramTotal ?? 0) > 0
            memSuffix: "VRAM"
            memUsed: root.gpuData?.vramUsed ?? 0
            memTotal: root.gpuData?.vramTotal ?? 0
            // Click through the GPUs while the overlay is open
            cycleEnabled: GlobalStates.overlayOpen && !root.preview && PerformanceStats.gpus.length > 1
            onCycleRequested: PerformanceStats.cycleGpu()
        }

        // Battery
        DeviceBlock {
            visible: root.batteryShown
            label: root.batteryLabel
            icon: Battery.isCharging ? "bolt" : ""
            deviceTone: root.batteryTone
            showUsage: true
            usage: Battery.percentage
            history: []
            forceBars: true
            stats: root.batteryStats
        }

        // Footer
        Flow {
            visible: root.footerItems.length > 0
            Layout.fillWidth: !root.textStyle
            Layout.topMargin: root.textStyle ? 0 : root.px(2)
            spacing: root.gap

            Repeater {
                model: root.footerItems
                delegate: StyledText {
                    required property string modelData
                    text: modelData
                    color: root.colDim
                    font {
                        family: Appearance.font.family.numbers
                        pixelSize: root.px(root.fontPx.smaller)
                        capitalization: root.cfg.uppercase ? Font.AllUppercase : Font.MixedCase
                    }
                }
            }
        }

        // Badge
        Rectangle {
            visible: root.cfg.footerText.length > 0
            Layout.alignment: root.textStyle ? Qt.AlignLeft : Qt.AlignHCenter
            Layout.topMargin: root.px(2)
            implicitWidth: badgeText.implicitWidth + root.pad * 2
            implicitHeight: badgeText.implicitHeight + root.gap
            radius: Math.min(height / 2, Appearance.rounding.large)
            color: root.cpuTone.accent

            StyledText {
                id: badgeText
                anchors.centerIn: parent
                text: root.cfg.footerText
                color: root.cpuTone.onAccent
                font {
                    family: Appearance.font.family.title
                    variableAxes: Appearance.font.variableAxes.titleRounded
                    pixelSize: root.px(root.fontPx.normal)
                    capitalization: root.cfg.uppercase ? Font.AllUppercase : Font.MixedCase
                }
            }
        }
    }

    // ------------------------------------------------------------ components

    // Caption + value to the right of the FPS number (avg, 1% low…).
    component FpsFigure: RowLayout {
        id: figure
        required property bool shown
        required property string label
        required property string value
        visible: figure.shown
        spacing: root.gap

        StyledText {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignBaseline
            horizontalAlignment: Text.AlignRight
            text: figure.label
            color: root.colDim
            font {
                pixelSize: root.px(root.fontPx.smallest)
                weight: Font.Bold
                capitalization: root.cfg.uppercase ? Font.AllUppercase : Font.MixedCase
            }
        }
        StyledText {
            Layout.alignment: Qt.AlignBaseline
            Layout.minimumWidth: root.px(root.fontPx.normal * 1.8)
            horizontalAlignment: Text.AlignRight
            text: figure.value
            color: root.colText
            font {
                family: Appearance.font.family.numbers
                variableAxes: root.valueAxes
                pixelSize: root.px(root.fontPx.normal)
            }
        }
    }

    // A device: usage bar/graph/line, its memory, then temperature, clocks, power.
    component DeviceBlock: ColumnLayout {
        id: block
        required property string label
        required property var deviceTone
        required property bool showUsage
        required property real usage
        required property list<real> history
        required property var stats
        property string usageText: ""
        property string icon: ""
        property bool forceBars: false
        property bool memShown: false
        property string memSuffix: ""
        property real memUsed: 0
        property real memTotal: 0
        property bool cycleEnabled: false
        signal cycleRequested()

        readonly property string pctText: block.usageText.length > 0 ? block.usageText
            : block.usage >= 0 ? root.fmtPct(block.usage) : "--%"
        readonly property real memFrac: block.memTotal > 0 ? block.memUsed / block.memTotal : 0
        readonly property bool asGraph: root.graphStyle && !block.forceBars

        Layout.fillWidth: !root.textStyle
        spacing: root.textStyle ? root.px(2) : root.px(4)

        // text style
        TextLine {
            visible: root.textStyle
            label: block.label
            labelColor: block.deviceTone.label
            leadValue: block.showUsage ? block.pctText : ""
            leadColor: root.colText
            stats: block.stats
        }
        TextLine {
            visible: root.textStyle && block.memShown
            label: block.memSuffix
            labelColor: block.deviceTone.label
            leadValue: block.memTotal > 0 ? `${root.fmtGb(block.memUsed)} GB` : "--"
            leadColor: root.colText
            stats: [{ "value": root.fmtPct(block.memFrac), "unit": "" }]
        }

        // bars style: the header bar carries the name and the usage
        LabeledBar {
            visible: !root.textStyle && !block.asGraph
            implicitHeight: root.px(root.fontPx.small * 1.9)
            frac: block.showUsage ? Math.max(0, block.usage) : 0
            fillColor: block.deviceTone.accent
            onFillColor: block.deviceTone.onAccent
            trackColor: ColorUtils.transparentize(block.deviceTone.accent, 0.8)
            leftText: block.label
            rightText: block.showUsage ? block.pctText : ""
            icon: block.icon
            fontSize: root.px(root.fontPx.small)
            emphasized: true

            MouseArea {
                anchors.fill: parent
                enabled: block.cycleEnabled
                visible: enabled
                cursorShape: Qt.PointingHandCursor
                onClicked: block.cycleRequested()
            }
        }

        // graph style: name row, then the usage history
        RowLayout {
            visible: !root.textStyle && block.asGraph
            Layout.fillWidth: true
            spacing: root.gap

            MaterialSymbol {
                visible: block.icon.length > 0
                text: block.icon
                iconSize: root.px(root.fontPx.small)
                fill: 1
                color: block.deviceTone.label
            }
            StyledText {
                Layout.fillWidth: true
                text: block.label
                elide: Text.ElideRight
                color: block.deviceTone.label
                font {
                    family: Appearance.font.family.title
                    variableAxes: Appearance.font.variableAxes.titleRounded
                    pixelSize: root.px(root.fontPx.small)
                    capitalization: root.cfg.uppercase ? Font.AllUppercase : Font.MixedCase
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: block.cycleEnabled
                    visible: enabled
                    cursorShape: Qt.PointingHandCursor
                    onClicked: block.cycleRequested()
                }
            }
            StyledText {
                visible: block.showUsage
                text: block.pctText
                color: root.colText
                font {
                    family: Appearance.font.family.numbers
                    variableAxes: root.valueAxes
                    pixelSize: root.px(root.fontPx.small)
                }
            }
        }
        Rectangle {
            visible: !root.textStyle && block.asGraph && block.showUsage
            Layout.fillWidth: true
            implicitHeight: root.px(root.fontPx.huge * 1.4)
            radius: Math.round(Appearance.rounding.verysmall * root.s)
            color: ColorUtils.transparentize(block.deviceTone.accent, 0.88)

            Graph {
                anchors.fill: parent
                anchors.margins: root.px(2)
                values: block.history
                points: PerformanceStats.historyLength
                color: block.deviceTone.label
                fillOpacity: 0.3
                alignment: Graph.Alignment.Right
            }
        }

        // memory bar
        LabeledBar {
            visible: !root.textStyle && block.memShown
            implicitHeight: root.px(root.fontPx.smaller * 1.6)
            frac: block.memFrac
            fillColor: block.deviceTone.soft
            onFillColor: block.deviceTone.onSoft
            trackColor: ColorUtils.transparentize(block.deviceTone.soft, 0.7)
            leftText: root.memText(block.memUsed, block.memTotal, block.memSuffix)
            rightText: root.fmtPct(block.memFrac)
            fontSize: root.px(root.fontPx.smaller)
        }

        // temperature, clocks, power
        RowLayout {
            visible: !root.textStyle && block.stats.length > 0
            Layout.fillWidth: true
            Layout.leftMargin: root.px(2)
            Layout.rightMargin: root.px(2)
            spacing: root.px(4)

            Repeater {
                model: block.stats
                // Spread across the row: first left, last right, the rest centred
                delegate: Item {
                    id: stat
                    required property var modelData
                    required property int index
                    readonly property color valueColor: stat.modelData.hot ? root.colHot : root.colText
                    Layout.fillWidth: true
                    implicitWidth: statRow.implicitWidth
                    implicitHeight: statRow.implicitHeight

                    RowLayout {
                        id: statRow
                        anchors.verticalCenter: parent.verticalCenter
                        x: stat.index === 0 ? 0
                            : stat.index === block.stats.length - 1 ? stat.width - width
                            : Math.round((stat.width - width) / 2)
                        spacing: root.px(2)

                        MaterialSymbol {
                            visible: root.cfg.showIcons && (stat.modelData.icon ?? "").length > 0
                            Layout.alignment: Qt.AlignVCenter
                            text: stat.modelData.icon ?? ""
                            iconSize: root.px(root.fontPx.smallie)
                            color: stat.modelData.hot ? root.colHot : block.deviceTone.label
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignBaseline
                            text: stat.modelData.value
                            color: stat.valueColor
                            font {
                                family: Appearance.font.family.numbers
                                variableAxes: root.valueAxes
                                pixelSize: root.px(root.fontPx.small)
                            }
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignBaseline
                            text: stat.modelData.unit
                            color: stat.modelData.hot ? root.colHot : root.colDim
                            font {
                                pixelSize: root.px(root.fontPx.smallest)
                                capitalization: root.cfg.uppercase ? Font.AllUppercase : Font.MixedCase
                            }
                        }
                    }
                }
            }
        }
    }

    // A progress bar with its label on it: the part of the text over the fill
    // switches to the fill's "on" colour. M3 expressive: rounded ends and a
    // small gap between the fill and the rest of the track.
    component LabeledBar: Item {
        id: bar
        property real frac: 0
        property color fillColor
        property color onFillColor
        property color trackColor
        property string leftText: ""
        property string rightText: ""
        property string icon: ""
        property real fontSize: Appearance.font.pixelSize.small
        property bool emphasized: false

        readonly property real barRadius: Math.min(bar.height / 2, Appearance.rounding.small * root.s)
        readonly property real fillWidth: bar.frac > 0.001
            ? Math.max(bar.barRadius * 2, Math.round(bar.width * Math.min(1, bar.frac))) : 0
        readonly property real gapWidth: bar.fillWidth > 0 && bar.fillWidth < bar.width ? root.px(3) : 0

        Layout.fillWidth: true

        Rectangle {
            x: fill.width + bar.gapWidth
            width: Math.max(0, bar.width - x)
            height: bar.height
            radius: bar.barRadius
            color: bar.trackColor
        }
        BarLabels {
            anchors.fill: parent
            owner: bar
            textColor: root.colText
        }
        Rectangle {
            id: fill
            width: bar.fillWidth
            height: bar.height
            radius: bar.barRadius
            color: bar.fillColor
            Behavior on width {
                enabled: !Appearance.reducedMotion
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }
        Item {
            width: fill.width
            height: bar.height
            clip: true

            BarLabels {
                width: bar.width
                height: bar.height
                owner: bar
                textColor: bar.onFillColor
            }
        }
    }

    component BarLabels: RowLayout {
        id: labels
        required property LabeledBar owner
        required property color textColor
        readonly property real inset: Math.max(root.px(8), labels.owner.barRadius * 0.8)
        spacing: root.px(4)

        MaterialSymbol {
            visible: labels.owner.icon.length > 0
            Layout.leftMargin: labels.inset
            text: labels.owner.icon
            iconSize: labels.owner.fontSize
            fill: 1
            color: labels.textColor
        }
        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: labels.owner.icon.length > 0 ? 0 : labels.inset
            text: labels.owner.leftText
            elide: Text.ElideRight
            color: labels.textColor
            font {
                family: labels.owner.emphasized ? Appearance.font.family.title : Appearance.font.family.main
                variableAxes: labels.owner.emphasized ? Appearance.font.variableAxes.titleRounded : Appearance.font.variableAxes.main
                pixelSize: labels.owner.fontSize
                capitalization: labels.owner.emphasized && root.cfg.uppercase ? Font.AllUppercase : Font.MixedCase
            }
        }
        StyledText {
            Layout.rightMargin: labels.inset
            text: labels.owner.rightText
            color: labels.textColor
            font {
                family: Appearance.font.family.numbers
                variableAxes: labels.owner.emphasized ? root.valueAxes : ({})
                pixelSize: labels.owner.fontSize
            }
        }
    }

    // One RivaTuner-style line: coloured label, lead value, then value/unit pairs.
    component TextLine: RowLayout {
        id: line
        required property string label
        required property color labelColor
        required property string leadValue
        required property color leadColor
        required property var stats
        property real leadSize: root.fontPx.smallie
        spacing: root.px(8)

        StyledText {
            Layout.alignment: Qt.AlignVCenter
            Layout.minimumWidth: root.px(root.fontPx.smallie * 3.4)
            text: line.label
            color: line.labelColor
            font {
                family: Appearance.font.family.title
                variableAxes: Appearance.font.variableAxes.titleRounded
                pixelSize: root.px(root.fontPx.smallie)
                capitalization: root.cfg.uppercase ? Font.AllUppercase : Font.MixedCase
            }
        }
        StyledText {
            visible: line.leadValue.length > 0
            Layout.alignment: Qt.AlignVCenter
            Layout.minimumWidth: root.px(root.fontPx.smallie * 2.6)
            horizontalAlignment: Text.AlignRight
            text: line.leadValue
            color: line.leadColor
            font {
                family: Appearance.font.family.numbers
                variableAxes: root.valueAxes
                pixelSize: root.px(line.leadSize)
            }
        }
        Repeater {
            model: line.stats
            delegate: RowLayout {
                id: pair
                required property var modelData
                Layout.alignment: Qt.AlignVCenter
                spacing: root.px(2)

                StyledText {
                    Layout.alignment: Qt.AlignBaseline
                    text: pair.modelData.value
                    color: pair.modelData.hot ? root.colHot : root.colText
                    font {
                        family: Appearance.font.family.numbers
                        variableAxes: root.valueAxes
                        pixelSize: root.px(root.fontPx.smallie)
                    }
                }
                StyledText {
                    visible: pair.modelData.unit.length > 0
                    Layout.alignment: Qt.AlignBaseline
                    text: pair.modelData.unit
                    color: pair.modelData.hot ? root.colHot : root.colDim
                    font {
                        pixelSize: root.px(root.fontPx.smallest)
                        capitalization: root.cfg.uppercase ? Font.AllUppercase : Font.MixedCase
                    }
                }
            }
        }
    }
}
