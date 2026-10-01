pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/*
 * The performance HUD, RivaTuner style. One tile per subject, all built the
 * same way:
 *
 *   [icon] Name ........................ 22%    header: name + main value
 *   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━  ─────────    progress line (or history graph)
 *   RAM  21.9 / 32.0 GB ................ 68%    memory line + thinner bar
 *   TEMP      CLOCK      POWER                  captions over values
 *   73 °C     4400 MHz   21 W
 *
 * No text ever sits inside a bar. FPS gets the hero tile on top. Every row is
 * a toggle in Config.options.overlay.perfMonitor and the card collapses around
 * what is on. Styles: "bars", "graph" (history instead of the line) and
 * "text" (one compact RivaTuner line per subject). `fpsOnly` shrinks it to
 * the frame rate.
 *
 * Also drawn by the Settings page as its live preview (`preview: true`),
 * which fills in example frame numbers while no game is logging.
 */
Rectangle {
    id: root

    required property PerfSampler sampler
    property bool preview: false

    readonly property var cfg: Config.options.overlay.perfMonitor
    readonly property real s: Math.max(0.5, root.cfg.scale)
    readonly property bool textStyle: root.cfg.style === "text"
    readonly property bool graphStyle: root.cfg.style === "graph"

    // Every size is a token scaled by the HUD's own scale, rounded so text
    // does not re-rasterise at fractional sizes.
    function px(value) {
        return Math.round(value * root.s);
    }
    readonly property var fontPx: Appearance.font.pixelSize
    readonly property real pad: root.px(Appearance.rounding.small)
    readonly property real gap: root.px(Appearance.rounding.verysmall)
    readonly property real tilePad: root.px(Appearance.rounding.small)
    readonly property real cardRadius: root.px(Appearance.rounding.large)
    readonly property real tileRadius: Math.max(0, root.cardRadius - root.pad)
    readonly property var digitAxes: ({ "wght": 760, "wdth": 40, "ROND": 100 })
    readonly property var valueAxes: ({ "wght": 650 })

    implicitWidth: root.cfg.fpsOnly ? fpsOnlyRow.implicitWidth + root.pad * 2
        : root.textStyle ? column.implicitWidth + root.pad * 2
        : Math.round(root.cfg.width * root.s)
    implicitHeight: (root.cfg.fpsOnly ? fpsOnlyRow.implicitHeight : column.implicitHeight) + root.pad * 2
    radius: root.cfg.fpsOnly ? Math.min(height / 2, root.cardRadius) : root.cardRadius
    // Semi-transparent and never blurred: the overlay layer has no blur rule.
    color: ColorUtils.transparentize(Appearance.m3colors.m3surfaceContainerLowest, 1 - root.cfg.backgroundOpacity)
    // Tiles step one surface up, fading with the card.
    readonly property color tileColor: ColorUtils.transparentize(Appearance.colors.colSurfaceContainerHigh,
        1 - Math.min(1, root.cfg.backgroundOpacity * 0.9))

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
    readonly property var fpsData: (root.preview && !root.sampler.fpsActive) ? root.exampleFps : root.sampler.fps
    readonly property bool hasFps: root.fpsData?.active ?? false

    readonly property var cpuData: root.sampler.cpu
    readonly property var ramData: root.sampler.ram
    readonly property var gpuData: root.sampler.gpu
    readonly property var gpuInfo: root.sampler.selectedGpu

    function known(value) {
        return value !== undefined && value !== null && !isNaN(value);
    }
    function fmtInt(value) {
        return root.known(value) ? String(Math.round(value)) : "–";
    }
    function fmtPct(value) {
        return root.known(value) && value >= 0 ? `${Math.round(value * 100)}%` : "–";
    }
    function fmtGb(bytes) {
        return (bytes / (1024 * 1024 * 1024)).toFixed(1);
    }
    function fmtWatts(watts) {
        return watts >= 10 ? watts.toFixed(0) : watts.toFixed(1);
    }
    function fmtMs(ms) {
        return root.known(ms) ? ms.toFixed(1) : "–";
    }
    function fmtDuration(seconds) {
        if (!root.known(seconds) || seconds < 0)
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
    function memValue(used, total) {
        return total > 0 ? `${root.fmtGb(used)} / ${root.fmtGb(total)} GB` : "–";
    }

    // ------------------------------------------------------------ colours

    // One hue family per subject:
    //   accent    — primary (CPU), tertiary (GPU), secondary (battery)
    //   container — the same families, on their containers
    //   mono      — surface tones only
    function tone(kind) {
        const c = Appearance.colors;
        if (root.cfg.palette === "mono") {
            return {
                "accent": c.colOnSurface,
                "label": c.colOnSurface,
                "soft": c.colOnSurfaceVariant,
                "track": ColorUtils.transparentize(c.colOnSurface, 0.82),
                "iconBg": ColorUtils.transparentize(c.colOnSurface, 0.88),
                "iconFg": c.colOnSurface
            };
        }
        const family = kind === "gpu" ? [c.colTertiary, c.colTertiaryContainer, c.colOnTertiaryContainer]
            : kind === "battery" ? [c.colSecondary, c.colSecondaryContainer, c.colOnSecondaryContainer]
            : [c.colPrimary, c.colPrimaryContainer, c.colOnPrimaryContainer];
        const container = root.cfg.palette === "container";
        return {
            "accent": container ? family[1] : family[0],
            // Text and lines keep the strong tone so they read on the card
            "label": family[0],
            "soft": container ? ColorUtils.mix(family[1], c.colOnSurface, 0.75) : ColorUtils.mix(family[0], c.colSurfaceContainerHighest, 0.55),
            "track": ColorUtils.transparentize(container ? family[1] : family[0], container ? 0.55 : 0.8),
            "iconBg": family[1],
            "iconFg": family[2]
        };
    }
    readonly property var cpuTone: root.tone("cpu")
    readonly property var gpuTone: root.tone("gpu")
    readonly property var batteryTone: root.tone("battery")

    readonly property color colText: Appearance.colors.colOnSurface
    readonly property color colDim: Appearance.colors.colOnSurfaceVariant
    readonly property color colHot: Appearance.colors.colError

    function fpsColor(value) {
        if (!root.cfg.colorCodeFps || !(value > 0) || root.cfg.palette === "mono")
            return root.colText;
        const target = Math.max(1, root.cfg.fpsTarget);
        if (value >= target * 0.95)
            return Appearance.colors.colPrimary;
        if (value >= target * 0.5)
            return Appearance.colors.colTertiary;
        return root.colHot;
    }

    // ------------------------------------------------------------ rows

    readonly property var cpuStats: {
        const c = root.cpuData ?? {};
        const out = [];
        if (root.cfg.showCpuTemp && c.temp !== undefined)
            out.push({ "caption": Translation.tr("Temp"), "value": root.fmtInt(c.temp), "unit": "°C", "hot": c.temp >= root.cfg.hotTemp });
        if (root.cfg.showCpuClock && c.clock !== undefined)
            out.push({ "caption": Translation.tr("Freq"), "value": root.fmtInt(c.clock), "unit": "MHz" });
        if (root.cfg.showCpuPower && root.known(root.sampler.cpuPower))
            out.push({ "caption": Translation.tr("Power"), "value": root.fmtWatts(root.sampler.cpuPower), "unit": "W" });
        if (root.cfg.showSwap && (root.ramData?.swapTotal ?? 0) > 0)
            out.push({ "caption": Translation.tr("Swap"), "value": root.fmtGb(root.ramData.swapUsed), "unit": "GB" });
        return out;
    }

    readonly property var gpuStats: {
        const g = root.gpuData ?? {};
        const out = [];
        if (root.sampler.gpuSuspended)
            return out;
        if (root.cfg.showGpuTemp && g.temp !== undefined)
            out.push({ "caption": Translation.tr("Temp"), "value": root.fmtInt(g.temp), "unit": "°C", "hot": g.temp >= root.cfg.hotTemp });
        if (root.cfg.showGpuClock && g.clock !== undefined)
            out.push({ "caption": Translation.tr("Freq"), "value": root.fmtInt(g.clock), "unit": "MHz" });
        if (root.cfg.showGpuMemClock && g.memClock !== undefined)
            out.push({ "caption": Translation.tr("Mem freq"), "value": root.fmtInt(g.memClock), "unit": "MHz" });
        if (root.cfg.showGpuPower && root.known(root.sampler.gpuPower))
            out.push({ "caption": Translation.tr("Power"), "value": root.fmtWatts(root.sampler.gpuPower), "unit": "W" });
        if (root.cfg.showGpuFan && g.fan !== undefined)
            out.push({ "caption": Translation.tr("Fan"), "value": root.fmtInt(g.fan), "unit": "%" });
        return out;
    }

    readonly property bool batteryShown: root.cfg.showBattery && Battery.available
    readonly property real batteryEnergy: Battery.device?.energy ?? 0
    readonly property var batteryStats: {
        const out = [];
        if (root.cfg.showBatteryEnergy && root.batteryEnergy > 0)
            out.push({ "caption": Translation.tr("Charge"), "value": root.batteryEnergy.toFixed(0), "unit": "Wh" });
        if (root.cfg.showBatteryPower && Battery.energyRate > 0)
            out.push({ "caption": Battery.isCharging ? Translation.tr("Charging") : Translation.tr("Power draw"), "value": root.fmtWatts(Battery.energyRate), "unit": "W" });
        if (root.cfg.showBatteryTime) {
            const left = root.fmtRemaining(Battery.isCharging ? Battery.timeToFull : Battery.timeToEmpty);
            if (left.length > 0)
                out.push({ "caption": Battery.isCharging ? Translation.tr("To full") : Translation.tr("Time left"), "value": left, "unit": "" });
        }
        return out;
    }

    readonly property var fpsFigures: {
        const out = [];
        if (root.cfg.showFpsAverage)
            out.push({ "caption": Translation.tr("Avg"), "value": root.hasFps ? root.fmtInt(root.fpsData.avg) : "–", "unit": "" });
        if (root.cfg.showFpsLow1)
            out.push({ "caption": "1% low", "value": root.hasFps ? root.fmtInt(root.fpsData.low1) : "–", "unit": "" });
        if (root.cfg.showFpsLow01)
            out.push({ "caption": "0.1% low", "value": root.hasFps ? root.fmtInt(root.fpsData.low01) : "–", "unit": "" });
        if (root.cfg.showFrametime && !root.cfg.showFrametimeGraph)
            out.push({ "caption": Translation.tr("Frame"), "value": root.hasFps ? root.fmtMs(root.fpsData.frametime) : "–", "unit": "ms" });
        return out;
    }

    readonly property var gameWindow: GameDetector.focusedWindow
    // The focused game's window title names it better than MangoHud's
    // process ("java" for Minecraft, "sober" for Roblox), and works without
    // MangoHud at all.
    readonly property string gameName: {
        if (GameDetector.gameFocused && root.gameWindow) {
            const name = (root.gameWindow.title || root.gameWindow.class || "").trim();
            if (name.length > 0)
                return name.length > 32 ? name.slice(0, 31) + "…" : name;
        }
        if (root.hasFps && root.fpsData.process)
            return root.fpsData.process;
        return "";
    }
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
        if (!(root.cfg.showDetails ?? true))
            return out;
        if (root.cfg.showProcess && root.gameName.length > 0)
            out.push({ "icon": "sports_esports", "text": root.gameName });
        if (root.cfg.showResolution && root.resolution.length > 0)
            out.push({ "icon": "aspect_ratio", "text": root.resolution });
        if (root.cfg.showDriver && root.driverText.length > 0)
            out.push({ "icon": "deployed_code", "text": root.driverText });
        if (root.cfg.showSessionTime && root.hasFps && root.known(root.fpsData.elapsed))
            out.push({ "icon": "timer", "text": root.fmtDuration(root.fpsData.elapsed) });
        if (root.cfg.showClock)
            out.push({ "icon": "schedule", "text": DateTime.time });
        return out;
    }

    readonly property string cpuLabel: (root.cfg.cpuName ?? "").length > 0 ? root.cfg.cpuName
        : root.textStyle ? "CPU" : (root.sampler.cpuModel || "CPU")
    readonly property string gpuLabel: (root.cfg.gpuName ?? "").length > 0 ? root.cfg.gpuName
        : root.textStyle ? "GPU" : (root.gpuInfo?.name || "GPU")

    readonly property bool cpuShown: root.cfg.showCpu
    readonly property bool gpuShown: root.cfg.showGpu && (root.gpuInfo !== null || !root.sampler.ready)
    // RAM rides in the CPU tile; on its own when the CPU is off.
    readonly property bool ramStandalone: root.cfg.showRam && !root.cpuShown

    readonly property var frametimes: root.hasFps ? (root.fpsData.frametimes ?? []) : []
    readonly property real frametimeCeiling: {
        // Twice the target frame time, or the worst spike if it is taller.
        let ceiling = 2000 / Math.max(1, root.cfg.fpsTarget);
        for (const v of root.frametimes)
            ceiling = Math.max(ceiling, v * 1.1);
        return ceiling;
    }

    // ------------------------------------------------------------ FPS only

    RowLayout {
        id: fpsOnlyRow
        visible: root.cfg.fpsOnly
        anchors.centerIn: parent
        spacing: root.gap

        StyledText {
            Layout.alignment: Qt.AlignVCenter
            text: root.hasFps ? root.fmtInt(root.fpsData.fps) : "–"
            color: root.fpsColor(root.fpsData?.fps)
            font {
                family: root.hasFps ? Appearance.font.family.main : Appearance.font.family.numbers
                variableAxes: root.hasFps ? root.digitAxes : ({})
                pixelSize: root.px(root.fontPx.huge * 1.5)
            }
        }
        ColumnLayout {
            Layout.alignment: Qt.AlignVCenter
            spacing: 0

            Caption {
                text: "FPS"
            }
            StyledText {
                visible: root.cfg.showFpsLow1
                text: `1% ${root.hasFps ? root.fmtInt(root.fpsData.low1) : "–"}`
                color: root.colDim
                font {
                    family: Appearance.font.family.numbers
                    pixelSize: root.px(root.fontPx.smaller)
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
        spacing: root.textStyle ? root.px(4) : root.gap

        // Title
        StyledText {
            visible: root.cfg.title.length > 0
            Layout.fillWidth: !root.textStyle
            Layout.topMargin: root.textStyle ? 0 : root.px(2)
            Layout.bottomMargin: root.textStyle ? root.px(2) : root.px(4)
            horizontalAlignment: root.textStyle ? Text.AlignLeft : Text.AlignHCenter
            text: root.cfg.title
            color: root.colText
            elide: Text.ElideRight
            font {
                family: Appearance.font.family.title
                variableAxes: Appearance.font.variableAxes.titleRounded
                pixelSize: root.px(root.textStyle ? root.fontPx.normal : root.fontPx.larger)
                capitalization: root.cfg.uppercase ? Font.AllUppercase : Font.MixedCase
            }
        }

        // ── FPS hero tile ───────────────────────────────────────────
        Tile {
            visible: root.cfg.showFps && !root.textStyle

            RowLayout {
                Layout.fillWidth: true
                spacing: root.gap

                ColumnLayout {
                    Layout.alignment: Qt.AlignBottom
                    spacing: 0

                    Caption {
                        text: "FPS"
                    }
                    StyledText {
                        text: root.hasFps ? root.fmtInt(root.fpsData.fps) : "–"
                        color: root.hasFps ? root.fpsColor(root.fpsData.fps) : root.colDim
                        font {
                            family: root.hasFps ? Appearance.font.family.main : Appearance.font.family.numbers
                            variableAxes: root.hasFps ? root.digitAxes : ({})
                            pixelSize: root.px(root.fontPx.huge * 2)
                        }
                    }
                }
                Item {
                    Layout.fillWidth: true
                }
                Repeater {
                    model: root.fpsFigures
                    delegate: Figure {
                        required property var modelData
                        Layout.alignment: Qt.AlignBottom
                        Layout.bottomMargin: root.px(4)
                        caption: modelData.caption
                        value: modelData.value
                        unit: modelData.unit
                        alignRight: true
                    }
                }
            }

            // Frame-time graph: spikes are stutters
            RowLayout {
                visible: root.cfg.showFrametimeGraph
                Layout.fillWidth: true
                spacing: root.gap

                HistoryGraph {
                    Layout.fillWidth: true
                    values: root.frametimes.map(v => Math.min(1, v / root.frametimeCeiling))
                    points: Math.max(2, root.frametimes.length)
                    lineColor: root.cpuTone.label
                    trackColor: root.cpuTone.track
                }
                Figure {
                    visible: root.cfg.showFrametime
                    Layout.alignment: Qt.AlignVCenter
                    caption: Translation.tr("Frame")
                    value: root.hasFps ? root.fmtMs(root.fpsData.frametime) : "–"
                    unit: "ms"
                    alignRight: true
                }
            }
        }

        TextLine {
            visible: root.cfg.showFps && root.textStyle
            label: "FPS"
            labelColor: root.cpuTone.label
            leadValue: root.hasFps ? root.fmtInt(root.fpsData.fps) : "–"
            leadColor: root.fpsColor(root.fpsData?.fps)
            leadSize: root.fontPx.larger
            stats: {
                const out = root.fpsFigures.slice();
                if (root.cfg.showFrametime && root.cfg.showFrametimeGraph)
                    out.push({ "caption": "", "value": root.hasFps ? root.fmtMs(root.fpsData.frametime) : "–", "unit": "ms" });
                return out;
            }
        }

        // ── Devices ─────────────────────────────────────────────────
        DeviceTile {
            visible: root.cpuShown
            icon: "memory"
            label: root.cpuLabel
            textLabel: "CPU"
            deviceTone: root.cpuTone
            showUsage: root.cfg.showCpuUsage
            usage: root.cpuData?.usage ?? -1
            history: root.sampler.cpuHistory
            stats: root.cpuStats
            memShown: root.cfg.showRam
            memLabel: "RAM"
            memUsed: root.ramData?.used ?? 0
            memTotal: root.ramData?.total ?? 0
        }

        DeviceTile {
            visible: root.ramStandalone
            icon: "memory_alt"
            label: "RAM"
            textLabel: "RAM"
            detail: root.memValue(root.ramData?.used ?? 0, root.ramData?.total ?? 0)
            deviceTone: root.cpuTone
            showUsage: true
            usage: (root.ramData?.total ?? 0) > 0 ? root.ramData.used / root.ramData.total : -1
            history: root.sampler.ramHistory
            stats: root.cfg.showSwap && (root.ramData?.swapTotal ?? 0) > 0
                ? [{ "caption": Translation.tr("Swap"), "value": root.fmtGb(root.ramData.swapUsed), "unit": "GB" }] : []
        }

        DeviceTile {
            visible: root.gpuShown
            icon: "developer_board"
            label: root.gpuLabel
            textLabel: "GPU"
            deviceTone: root.gpuTone
            showUsage: root.cfg.showGpuUsage
            usage: root.sampler.gpuSuspended ? 0 : (root.gpuData?.usage ?? -1)
            usageText: root.sampler.gpuSuspended ? Translation.tr("Sleeping") : ""
            history: root.sampler.gpuHistory
            stats: root.gpuStats
            memShown: root.cfg.showVram && (root.gpuData?.vramTotal ?? 0) > 0
            memLabel: "VRAM"
            memUsed: root.gpuData?.vramUsed ?? 0
            memTotal: root.gpuData?.vramTotal ?? 0
            // Click through the GPUs while the overlay is open
            cycleEnabled: GlobalStates.overlayOpen && !root.preview && root.sampler.gpus.length > 1
            onCycleRequested: root.sampler.cycleGpu()
        }

        DeviceTile {
            visible: root.batteryShown
            icon: Battery.isCharging ? "battery_charging_full" : "battery_horiz_075"
            label: Translation.tr("Battery")
            textLabel: "BAT"
            deviceTone: root.batteryTone
            showUsage: true
            usage: Battery.percentage
            history: []
            forceLine: true
            stats: root.batteryStats
        }

        // ── Footer ──────────────────────────────────────────────────
        StyledText {
            visible: root.textStyle && root.footerItems.length > 0
            Layout.topMargin: root.px(2)
            text: root.footerItems.map(item => item.text).join("  ·  ")
            color: root.colDim
            font {
                family: Appearance.font.family.numbers
                pixelSize: root.px(root.fontPx.smaller)
                capitalization: root.cfg.uppercase ? Font.AllUppercase : Font.MixedCase
            }
        }
        Flow {
            visible: !root.textStyle && root.footerItems.length > 0
            Layout.fillWidth: true
            Layout.topMargin: root.px(2)
            spacing: root.px(6)

            Repeater {
                model: root.footerItems
                delegate: Rectangle {
                    id: chip
                    required property var modelData
                    implicitWidth: chipRow.implicitWidth + root.px(16)
                    implicitHeight: chipRow.implicitHeight + root.px(8)
                    radius: Math.min(height / 2, Appearance.rounding.full)
                    color: root.tileColor

                    RowLayout {
                        id: chipRow
                        anchors.centerIn: parent
                        spacing: root.px(4)

                        MaterialSymbol {
                            visible: root.cfg.showIcons
                            text: chip.modelData.icon
                            iconSize: root.px(root.fontPx.small)
                            color: root.colDim
                        }
                        StyledText {
                            text: chip.modelData.text
                            color: root.colDim
                            font {
                                family: Appearance.font.family.numbers
                                pixelSize: root.px(root.fontPx.smaller)
                                capitalization: root.cfg.uppercase ? Font.AllUppercase : Font.MixedCase
                            }
                        }
                    }
                }
            }
        }

        // Badge
        Rectangle {
            visible: root.cfg.footerText.length > 0
            Layout.alignment: root.textStyle ? Qt.AlignLeft : Qt.AlignHCenter
            Layout.topMargin: root.px(2)
            implicitWidth: badgeText.implicitWidth + root.px(28)
            implicitHeight: badgeText.implicitHeight + root.px(10)
            radius: Math.min(height / 2, Appearance.rounding.full)
            color: root.cpuTone.accent

            StyledText {
                id: badgeText
                anchors.centerIn: parent
                text: root.cfg.footerText
                color: root.cfg.palette === "container" ? Appearance.colors.colOnPrimaryContainer
                    : root.cfg.palette === "mono" ? Appearance.m3colors.m3surfaceContainerLowest
                    : Appearance.colors.colOnPrimary
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

    // A surface one step up the ladder that holds one subject.
    component Tile: Rectangle {
        id: tile
        default property alias content: tileColumn.data
        property real padding: root.tilePad
        Layout.fillWidth: true
        implicitWidth: tileColumn.implicitWidth + tile.padding * 2
        implicitHeight: tileColumn.implicitHeight + tile.padding * 2
        radius: root.tileRadius
        color: root.tileColor

        ColumnLayout {
            id: tileColumn
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: tile.padding
            }
            spacing: root.px(6)
        }
    }

    // Small bold caption over a value.
    component Caption: StyledText {
        color: root.colDim
        font {
            pixelSize: root.px(root.fontPx.smallest)
            weight: Font.Bold
            capitalization: root.cfg.uppercase ? Font.AllUppercase : Font.MixedCase
        }
    }

    // Caption over value + unit.
    component Figure: ColumnLayout {
        id: figure
        property string caption: ""
        property string value: ""
        property string unit: ""
        property bool hot: false
        property bool alignRight: false
        spacing: 0

        Caption {
            visible: figure.caption.length > 0
            Layout.alignment: figure.alignRight ? Qt.AlignRight : Qt.AlignLeft
            text: figure.caption
        }
        RowLayout {
            Layout.alignment: figure.alignRight ? Qt.AlignRight : Qt.AlignLeft
            spacing: root.px(2)

            StyledText {
                Layout.alignment: Qt.AlignBaseline
                text: figure.value
                color: figure.hot ? root.colHot : root.colText
                font {
                    family: Appearance.font.family.numbers
                    variableAxes: root.valueAxes
                    pixelSize: root.px(root.fontPx.normal)
                }
            }
            StyledText {
                visible: figure.unit.length > 0
                Layout.alignment: Qt.AlignBaseline
                text: figure.unit
                color: figure.hot ? root.colHot : root.colDim
                font.pixelSize: root.px(root.fontPx.smaller)
            }
        }
    }

    // M3 expressive linear progress: rounded ends, a gap before the track.
    component ProgressLine: Item {
        id: line
        property real frac: 0
        property color fillColor
        property color trackColor
        Layout.fillWidth: true
        implicitHeight: root.px(6)

        readonly property real fillWidth: line.frac > 0.001 ? Math.max(line.height, Math.round(line.width * Math.min(1, line.frac))) : 0
        readonly property real gapWidth: line.fillWidth > 0 && line.fillWidth < line.width ? root.px(4) : 0

        Rectangle {
            x: fill.width + line.gapWidth
            width: Math.max(0, line.width - x)
            height: line.height
            radius: height / 2
            color: line.trackColor
        }
        Rectangle {
            id: fill
            width: line.fillWidth
            height: line.height
            radius: height / 2
            color: line.fillColor
            Behavior on width {
                enabled: !Appearance.reducedMotion
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }
    }

    // History as a filled line on a tinted strip.
    component HistoryGraph: Rectangle {
        id: graph
        property var values: []
        property int points: 2
        property color lineColor
        property color trackColor
        implicitHeight: root.px(Appearance.rounding.large * 1.4)
        radius: root.px(Appearance.rounding.verysmall)
        color: graph.trackColor

        Graph {
            anchors.fill: parent
            anchors.margins: root.px(2)
            values: graph.values
            points: graph.points
            color: graph.lineColor
            fillOpacity: 0.3
            alignment: Graph.Alignment.Right
        }
    }

    // One subject: header, bar or graph, memory, figures.
    component DeviceTile: Tile {
        id: device
        required property string icon
        required property string label
        required property string textLabel
        required property var deviceTone
        required property bool showUsage
        required property real usage
        required property var history
        required property var stats
        property string detail: ""
        property string usageText: ""
        property bool forceLine: false
        property bool memShown: false
        property string memLabel: ""
        property real memUsed: 0
        property real memTotal: 0
        property bool cycleEnabled: false
        signal cycleRequested()

        readonly property string mainValue: device.usageText.length > 0 ? device.usageText : root.fmtPct(device.usage)
        readonly property bool hasValue: device.usageText.length === 0 && device.usage >= 0
        readonly property real memFrac: device.memTotal > 0 ? device.memUsed / device.memTotal : 0
        readonly property bool asGraph: root.graphStyle && !device.forceLine

        // text style draws no surface
        color: root.textStyle ? "transparent" : root.tileColor
        padding: root.textStyle ? 0 : root.tilePad
        Layout.fillWidth: !root.textStyle

        // ── text style ──
        ColumnLayout {
            id: textColumn
            visible: root.textStyle
            spacing: root.px(4)

            TextLine {
                label: device.textLabel
                labelColor: device.deviceTone.label
                leadValue: device.showUsage ? device.mainValue : ""
                leadColor: root.colText
                stats: device.detail.length > 0 ? [{ "caption": "", "value": device.detail, "unit": "" }].concat(device.stats) : device.stats
            }
            TextLine {
                visible: device.memShown
                label: device.memLabel
                labelColor: device.deviceTone.label
                leadValue: root.fmtPct(device.memFrac)
                leadColor: root.colText
                stats: [{ "caption": "", "value": root.memValue(device.memUsed, device.memTotal), "unit": "" }]
            }
        }

        // ── bars / graph ──
        RowLayout {
            id: header
            visible: !root.textStyle
            Layout.fillWidth: true
            spacing: root.gap

            Rectangle {
                implicitWidth: root.px(28)
                implicitHeight: root.px(28)
                radius: Math.min(width / 2, Appearance.rounding.full)
                color: device.deviceTone.iconBg

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: device.icon
                    iconSize: root.px(root.fontPx.normal)
                    fill: 1
                    color: device.deviceTone.iconFg
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: device.label
                    elide: Text.ElideRight
                    color: root.colText
                    font {
                        family: Appearance.font.family.title
                        variableAxes: Appearance.font.variableAxes.titleRounded
                        pixelSize: root.px(root.fontPx.small)
                        capitalization: root.cfg.uppercase ? Font.AllUppercase : Font.MixedCase
                    }
                }
                StyledText {
                    visible: device.detail.length > 0
                    text: device.detail
                    color: root.colDim
                    font {
                        family: Appearance.font.family.numbers
                        pixelSize: root.px(root.fontPx.smaller)
                    }
                }
            }
            StyledText {
                visible: device.showUsage
                text: device.mainValue
                color: device.hasValue ? device.deviceTone.label : root.colDim
                font {
                    family: device.hasValue ? Appearance.font.family.main : Appearance.font.family.numbers
                    variableAxes: device.hasValue ? root.digitAxes : ({})
                    pixelSize: root.px(device.usageText.length > 0 ? root.fontPx.normal : root.fontPx.huge)
                }
            }

            // Click the header to switch GPUs (overlay open only)
            TapHandler {
                enabled: device.cycleEnabled
                onTapped: device.cycleRequested()
            }
            HoverHandler {
                enabled: device.cycleEnabled
                cursorShape: Qt.PointingHandCursor
            }
        }

        ProgressLine {
            id: usageBar
            visible: !root.textStyle && device.showUsage && !device.asGraph
            frac: Math.max(0, device.usage)
            fillColor: device.deviceTone.accent
            trackColor: device.deviceTone.track
        }
        HistoryGraph {
            id: usageGraph
            visible: !root.textStyle && device.showUsage && device.asGraph
            Layout.fillWidth: true
            values: device.history
            points: root.sampler.historyLength
            lineColor: device.deviceTone.label
            trackColor: device.deviceTone.track
        }

        // memory line
        ColumnLayout {
            id: memBlock
            visible: !root.textStyle && device.memShown
            Layout.fillWidth: true
            Layout.topMargin: root.px(2)
            spacing: root.px(4)

            RowLayout {
                Layout.fillWidth: true
                spacing: root.gap

                Caption {
                    text: device.memLabel
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.memValue(device.memUsed, device.memTotal)
                    color: root.colText
                    font {
                        family: Appearance.font.family.numbers
                        pixelSize: root.px(root.fontPx.smaller)
                    }
                }
                StyledText {
                    text: root.fmtPct(device.memFrac)
                    color: root.colDim
                    font {
                        family: Appearance.font.family.numbers
                        pixelSize: root.px(root.fontPx.smaller)
                    }
                }
            }
            ProgressLine {
                implicitHeight: root.px(4)
                frac: device.memFrac
                fillColor: device.deviceTone.soft
                trackColor: device.deviceTone.track
            }
        }

        // figures, spread across the tile
        RowLayout {
            id: statsRow
            visible: !root.textStyle && device.stats.length > 0
            Layout.fillWidth: true
            Layout.topMargin: root.px(2)
            spacing: root.gap

            Repeater {
                model: device.stats
                delegate: Item {
                    id: cell
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    implicitWidth: cellFigure.implicitWidth
                    implicitHeight: cellFigure.implicitHeight

                    Figure {
                        id: cellFigure
                        readonly property bool last: cell.index === device.stats.length - 1 && cell.index > 0
                        x: last ? cell.width - width : cell.index === 0 ? 0 : Math.round((cell.width - width) / 2)
                        caption: cell.modelData.caption
                        value: cell.modelData.value
                        unit: cell.modelData.unit
                        hot: cell.modelData.hot ?? false
                        alignRight: last
                    }
                }
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
        property real leadSize: root.fontPx.small
        spacing: root.px(10)

        StyledText {
            Layout.alignment: Qt.AlignVCenter
            Layout.minimumWidth: root.px(root.fontPx.small * 3)
            text: line.label
            color: line.labelColor
            font {
                family: Appearance.font.family.title
                variableAxes: Appearance.font.variableAxes.titleRounded
                pixelSize: root.px(root.fontPx.small)
                capitalization: root.cfg.uppercase ? Font.AllUppercase : Font.MixedCase
            }
        }
        StyledText {
            visible: line.leadValue.length > 0
            Layout.alignment: Qt.AlignVCenter
            Layout.minimumWidth: root.px(root.fontPx.small * 2.6)
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
                spacing: root.px(3)

                StyledText {
                    Layout.alignment: Qt.AlignBaseline
                    text: pair.modelData.value
                    color: pair.modelData.hot ? root.colHot : root.colText
                    font {
                        family: Appearance.font.family.numbers
                        variableAxes: root.valueAxes
                        pixelSize: root.px(root.fontPx.small)
                    }
                }
                StyledText {
                    visible: text.length > 0
                    Layout.alignment: Qt.AlignBaseline
                    text: pair.modelData.unit || (pair.modelData.caption ?? "")
                    color: pair.modelData.hot ? root.colHot : root.colDim
                    font.pixelSize: root.px(root.fontPx.smaller)
                }
            }
        }
    }
}
