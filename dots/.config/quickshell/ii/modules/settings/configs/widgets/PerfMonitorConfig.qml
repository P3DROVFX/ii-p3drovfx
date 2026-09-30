import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.overlay.perfMonitor

// Performance HUD: the live HUD over the wallpaper as the hero, then what it
// shows and how it looks, then where its frame rate comes from.
Item {
    id: subPageRoot
    anchors.fill: parent

    property bool showBackButton: false
    signal goBack()

    readonly property var hud: Config.options.overlay.perfMonitor

    ContentPage {
        id: page
        anchors.fill: parent
        forceWidth: false

        RowLayout {
            visible: subPageRoot.showBackButton
            spacing: 12

            RippleButton {
                implicitWidth: implicitHeight
                implicitHeight: 40
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive
                onClicked: subPageRoot.goBack()

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "arrow_back"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }

            StyledText {
                text: Translation.tr("Performance HUD")
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                color: Appearance.colors.colOnLayer0
            }
        }

        // ── Hero: the real HUD, live, over the wallpaper ────────────────
        Item {
            id: hero
            Layout.fillWidth: true
            implicitHeight: Math.max(Math.min(Math.max(width / 1.7, 220), 460), preview.height + 2 * 20 + 40)

            ClippingRectangle {
                anchors.fill: parent
                radius: Appearance.rounding.verylarge
                color: Appearance.colors.colLayer1

                Image {
                    anchors.fill: parent
                    source: {
                        const bg = Config.options.background;
                        const path = bg.thumbnailPath || bg.wallpaperPath;
                        return path ? `file://${FileUtils.trimFileProtocol(path)}` : "";
                    }
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                    sourceSize.width: 960
                }
            }

            PerfMonitorContent {
                id: preview
                preview: true
                monitoring: subPageRoot.visible
                x: 20
                y: 20
            }

            // Status pills, top-right
            Row {
                anchors {
                    top: parent.top
                    right: parent.right
                    margins: 16
                }
                spacing: 8
                layoutDirection: Qt.RightToLeft

                StatusPill {
                    icon: PerformanceStats.mangohud.configured ? "check_circle" : "info"
                    label: PerformanceStats.mangohud.configured ? Translation.tr("FPS from MangoHud")
                        : Translation.tr("FPS not set up")
                    highlighted: !PerformanceStats.mangohud.configured
                }
                StatusPill {
                    visible: PerformanceStats.selectedGpu !== null
                    icon: "developer_board"
                    label: PerformanceStats.selectedGpu?.name ?? ""
                }
            }
        }

        // ── Look ────────────────────────────────────────────────────────
        ContentSection {
            Layout.topMargin: 12
            title: Translation.tr("Look")
            icon: "palette"

            ContentSubsection {
                title: Translation.tr("Style")
                icon: "view_agenda"

                ConfigSelectionArray {
                    currentValue: subPageRoot.hud.style
                    onSelected: newValue => { Config.options.overlay.perfMonitor.style = newValue; }
                    options: [
                        { displayName: Translation.tr("Bars"), icon: "view_day", value: "bars" },
                        { displayName: Translation.tr("Graph"), icon: "monitoring", value: "graph" },
                        { displayName: Translation.tr("Text only"), icon: "notes", value: "text" }
                    ]
                }
            }

            ContentSubsection {
                title: Translation.tr("Colors")
                icon: "format_color_fill"

                ConfigSelectionArray {
                    currentValue: subPageRoot.hud.palette
                    onSelected: newValue => { Config.options.overlay.perfMonitor.palette = newValue; }
                    options: [
                        { displayName: Translation.tr("Accent"), icon: "colors", value: "accent" },
                        { displayName: Translation.tr("Tonal"), icon: "gradient", value: "container" },
                        { displayName: Translation.tr("Monochrome"), icon: "contrast", value: "mono" }
                    ]
                }
            }

            ConfigRow {
                uniform: true

                ConfigSwitch {
                    buttonIcon: "speed"
                    text: Translation.tr("FPS only")
                    checked: subPageRoot.hud.fpsOnly
                    onCheckedChanged: Config.options.overlay.perfMonitor.fpsOnly = checked
                    StyledToolTip {
                        text: Translation.tr("Shrink the HUD to a small frame-rate counter.")
                    }
                }
                ConfigSwitch {
                    buttonIcon: "traffic"
                    text: Translation.tr("Color the frame rate")
                    checked: subPageRoot.hud.colorCodeFps
                    onCheckedChanged: Config.options.overlay.perfMonitor.colorCodeFps = checked
                    StyledToolTip {
                        text: Translation.tr("Tint the FPS number by how close it is to the target frame rate.")
                    }
                }
            }

            ConfigRow {
                uniform: true

                ConfigSwitch {
                    buttonIcon: "match_case"
                    text: Translation.tr("Uppercase labels")
                    checked: subPageRoot.hud.uppercase
                    onCheckedChanged: Config.options.overlay.perfMonitor.uppercase = checked
                    StyledToolTip {
                        text: Translation.tr("Write names and units in capitals, like RivaTuner.")
                    }
                }
                ConfigSwitch {
                    buttonIcon: "category"
                    text: Translation.tr("Icons next to values")
                    checked: subPageRoot.hud.showIcons
                    onCheckedChanged: Config.options.overlay.perfMonitor.showIcons = checked
                    StyledToolTip {
                        text: Translation.tr("Show a small icon before temperature, clock and power.")
                    }
                }
            }

            ConfigSlider {
                buttonIcon: "zoom_in"
                text: Translation.tr("Size (%)")
                from: 60
                to: 180
                stepSize: 5
                value: Math.round(subPageRoot.hud.scale * 100)
                onValueChanged: Config.options.overlay.perfMonitor.scale = value / 100
            }

            ConfigSlider {
                visible: subPageRoot.hud.style !== "text" && !subPageRoot.hud.fpsOnly
                buttonIcon: "width"
                text: Translation.tr("Width")
                usePercentTooltip: false
                from: 200
                to: 400
                stepSize: 10
                value: subPageRoot.hud.width
                onValueChanged: Config.options.overlay.perfMonitor.width = value
            }

            ConfigSlider {
                buttonIcon: "opacity"
                text: Translation.tr("Background opacity (%)")
                from: 0
                to: 100
                stepSize: 5
                value: Math.round(subPageRoot.hud.backgroundOpacity * 100)
                onValueChanged: Config.options.overlay.perfMonitor.backgroundOpacity = value / 100
            }
        }

        // ── Names ───────────────────────────────────────────────────────
        ContentSection {
            Layout.topMargin: 12
            title: Translation.tr("Names")
            icon: "title"
            tooltip: Translation.tr("Leave a name empty to use the detected model.")

            ConfigTextField {
                Layout.fillWidth: true
                text: Translation.tr("Title")
                icon: "title"
                placeholderText: Translation.tr("No title")
                tooltip: Translation.tr("A heading over the HUD, like the device's name.")
                inputText: subPageRoot.hud.title
                textField.onEditingFinished: Config.options.overlay.perfMonitor.title = textField.text
            }
            ConfigTextField {
                Layout.fillWidth: true
                text: Translation.tr("Badge")
                icon: "label"
                placeholderText: Translation.tr("No badge")
                tooltip: Translation.tr("A short word in a pill under the HUD, like \"Bench\".")
                inputText: subPageRoot.hud.footerText
                textField.onEditingFinished: Config.options.overlay.perfMonitor.footerText = textField.text
            }
            ConfigTextField {
                Layout.fillWidth: true
                text: Translation.tr("CPU name")
                icon: "memory"
                placeholderText: PerformanceStats.cpuModel || "CPU"
                inputText: subPageRoot.hud.cpuName
                textField.onEditingFinished: Config.options.overlay.perfMonitor.cpuName = textField.text
            }
            ConfigTextField {
                Layout.fillWidth: true
                text: Translation.tr("GPU name")
                icon: "developer_board"
                placeholderText: PerformanceStats.selectedGpu?.name ?? "GPU"
                inputText: subPageRoot.hud.gpuName
                textField.onEditingFinished: Config.options.overlay.perfMonitor.gpuName = textField.text
            }
        }

        // ── Frame rate ──────────────────────────────────────────────────
        ContentSection {
            Layout.topMargin: 12
            title: Translation.tr("Frame rate")
            icon: "speed"

            ConfigRow {
                uniform: true
                HudSwitch { key: "showFps"; buttonIcon: "speed"; text: Translation.tr("FPS"); hint: Translation.tr("The frame rate, big, at the top.") }
                HudSwitch { key: "showFpsAverage"; buttonIcon: "functions"; text: Translation.tr("Average"); hint: Translation.tr("Average frame rate over the statistics window.") }
            }
            ConfigRow {
                uniform: true
                HudSwitch { key: "showFpsLow1"; buttonIcon: "trending_down"; text: Translation.tr("1% low"); hint: Translation.tr("The frame rate of the slowest 1% of frames: how bad the stutters get.") }
                HudSwitch { key: "showFpsLow01"; buttonIcon: "south"; text: Translation.tr("0.1% low"); hint: Translation.tr("The frame rate of the slowest 0.1% of frames.") }
            }
            ConfigRow {
                uniform: true
                HudSwitch { key: "showFrametime"; buttonIcon: "timer"; text: Translation.tr("Frame time"); hint: Translation.tr("How long the last frame took, in milliseconds.") }
                HudSwitch { key: "showFrametimeGraph"; buttonIcon: "show_chart"; text: Translation.tr("Frame-time graph"); hint: Translation.tr("A line of recent frame times. Spikes are stutters.") }
            }

            ConfigSpinBox {
                icon: "flag"
                text: Translation.tr("Target frame rate")
                value: subPageRoot.hud.fpsTarget
                from: 20
                to: 540
                stepSize: 5
                onValueChanged: Config.options.overlay.perfMonitor.fpsTarget = value
                StyledToolTip {
                    text: Translation.tr("Colors the FPS number and scales the frame-time graph.")
                }
            }
            ConfigSpinBox {
                icon: "history"
                text: Translation.tr("Statistics window (s)")
                value: subPageRoot.hud.statsWindow
                from: 5
                to: 600
                stepSize: 5
                onValueChanged: Config.options.overlay.perfMonitor.statsWindow = value
                StyledToolTip {
                    text: Translation.tr("How many seconds of frames the average and the lows are computed from.")
                }
            }
        }

        // ── CPU & memory ────────────────────────────────────────────────
        ContentSection {
            Layout.topMargin: 12
            title: Translation.tr("CPU and memory")
            icon: "memory"

            ConfigRow {
                uniform: true
                HudSwitch { key: "showCpu"; buttonIcon: "memory"; text: Translation.tr("CPU"); hint: Translation.tr("The processor block.") }
                HudSwitch { key: "showCpuUsage"; buttonIcon: "percent"; text: Translation.tr("Usage") }
            }
            ConfigRow {
                uniform: true
                HudSwitch { key: "showCpuTemp"; buttonIcon: "thermostat"; text: Translation.tr("Temperature") }
                HudSwitch { key: "showCpuClock"; buttonIcon: "speed"; text: Translation.tr("Clock") }
            }
            ConfigRow {
                uniform: true
                HudSwitch {
                    key: "showCpuPower"
                    buttonIcon: "bolt"
                    text: Translation.tr("Power")
                    hint: PerformanceStats.ready && !PerformanceStats.cpuHasPower
                        ? Translation.tr("This system does not let users read the CPU's power (RAPL is root-only). MangoHud's value is used while a game logs it.")
                        : Translation.tr("Package power draw.")
                }
                HudSwitch { key: "showRam"; buttonIcon: "memory_alt"; text: Translation.tr("RAM"); hint: Translation.tr("Used and total memory, as a bar.") }
            }
            ConfigRow {
                uniform: true
                HudSwitch { key: "showSwap"; buttonIcon: "swap_horiz"; text: Translation.tr("Swap") }
                ConfigSpinBox {
                    icon: "local_fire_department"
                    text: Translation.tr("Hot at (°C)")
                    value: subPageRoot.hud.hotTemp
                    from: 50
                    to: 110
                    stepSize: 1
                    onValueChanged: Config.options.overlay.perfMonitor.hotTemp = value
                    StyledToolTip {
                        text: Translation.tr("Temperatures from here up turn red.")
                    }
                }
            }
        }

        // ── GPU ─────────────────────────────────────────────────────────
        ContentSection {
            Layout.topMargin: 12
            title: Translation.tr("Graphics card")
            icon: "developer_board"

            ContentSubsection {
                visible: PerformanceStats.gpus.length > 0
                title: Translation.tr("Monitored GPU")
                icon: "swap_horiz"
                tooltip: Translation.tr("A sleeping discrete GPU is shown as sleeping, never woken up. While the overlay is open, click the GPU bar to switch.")

                ConfigSelectionArray {
                    currentValue: subPageRoot.hud.gpuDevice
                    onSelected: newValue => { Config.options.overlay.perfMonitor.gpuDevice = newValue; }
                    options: [{ displayName: Translation.tr("Automatic"), icon: "auto_awesome", value: "auto" }].concat(
                        PerformanceStats.gpus.map(g => ({
                            displayName: g.name,
                            icon: g.discrete ? "developer_board" : "memory",
                            value: g.id
                        })))
                }
            }

            ConfigRow {
                uniform: true
                HudSwitch { key: "showGpu"; buttonIcon: "developer_board"; text: Translation.tr("GPU"); hint: Translation.tr("The graphics card block.") }
                HudSwitch { key: "showGpuUsage"; buttonIcon: "percent"; text: Translation.tr("Usage") }
            }
            ConfigRow {
                uniform: true
                HudSwitch { key: "showGpuTemp"; buttonIcon: "thermostat"; text: Translation.tr("Temperature") }
                HudSwitch { key: "showGpuClock"; buttonIcon: "speed"; text: Translation.tr("Core clock") }
            }
            ConfigRow {
                uniform: true
                HudSwitch { key: "showGpuMemClock"; buttonIcon: "memory"; text: Translation.tr("Memory clock") }
                HudSwitch { key: "showGpuPower"; buttonIcon: "bolt"; text: Translation.tr("Power") }
            }
            ConfigRow {
                uniform: true
                HudSwitch { key: "showGpuFan"; buttonIcon: "mode_fan"; text: Translation.tr("Fan") }
                HudSwitch { key: "showVram"; buttonIcon: "sd_card"; text: Translation.tr("VRAM"); hint: Translation.tr("Used and total video memory, as a bar.") }
            }
        }

        // ── Battery & footer ────────────────────────────────────────────
        ContentSection {
            Layout.topMargin: 12
            title: Translation.tr("Battery and details")
            icon: "battery_horiz_075"

            ConfigRow {
                uniform: true
                HudSwitch { key: "showBattery"; buttonIcon: "battery_horiz_075"; text: Translation.tr("Battery"); hint: Translation.tr("Only on laptops.") }
                HudSwitch { key: "showBatteryEnergy"; buttonIcon: "battery_charging_full"; text: Translation.tr("Energy left (Wh)") }
            }
            ConfigRow {
                uniform: true
                HudSwitch { key: "showBatteryPower"; buttonIcon: "bolt"; text: Translation.tr("Power draw") }
                HudSwitch { key: "showBatteryTime"; buttonIcon: "schedule"; text: Translation.tr("Time left") }
            }
            ConfigRow {
                uniform: true
                HudSwitch { key: "showProcess"; buttonIcon: "sports_esports"; text: Translation.tr("Game name") }
                HudSwitch { key: "showResolution"; buttonIcon: "aspect_ratio"; text: Translation.tr("Resolution") }
            }
            ConfigRow {
                uniform: true
                HudSwitch { key: "showDriver"; buttonIcon: "deployed_code"; text: Translation.tr("Driver") }
                HudSwitch { key: "showSessionTime"; buttonIcon: "timer"; text: Translation.tr("Session time"); hint: Translation.tr("How long the game has been running.") }
            }
            ConfigRow {
                uniform: true
                HudSwitch { key: "showClock"; buttonIcon: "nest_clock_farsight_analog"; text: Translation.tr("Clock") }
                Item {
                    Layout.fillWidth: true
                }
            }
        }

        // ── Frame-rate source ───────────────────────────────────────────
        ContentSection {
            Layout.topMargin: 12
            title: Translation.tr("Frame-rate source")
            icon: "videogame_asset"
            tooltip: Translation.tr("Linux has no system-wide frame counter; the HUD reads the log MangoHud writes for each game.")

            NoticeBox {
                Layout.fillWidth: true
                materialIcon: PerformanceStats.mangohud.configured ? "check_circle" : "info"
                text: {
                    if (!PerformanceStats.mangohud.installed && !PerformanceStats.mangohud.configured)
                        return Translation.tr("MangoHud is not installed. Install it, set up logging here, then launch games with `mangohud %command%` (Steam) or MANGOHUD=1.");
                    if (!PerformanceStats.mangohud.configured)
                        return Translation.tr("Set up logging so MangoHud writes frame times where the HUD can read them. Games then need `mangohud %command%` (Steam) or MANGOHUD=1.");
                    return Translation.tr("MangoHud logs frame times for the HUD. Launch games with `mangohud %command%` (Steam) or MANGOHUD=1.");
                }

                RippleButtonWithIcon {
                    buttonRadius: Appearance.rounding.full
                    materialIcon: PerformanceStats.mangohud.configured ? "refresh" : "build"
                    mainText: PerformanceStats.mangohud.configured ? Translation.tr("Apply again") : Translation.tr("Set up logging")
                    onClicked: PerformanceStats.setMangoHudLogging(true)
                }
                RippleButtonWithIcon {
                    visible: PerformanceStats.mangohud.configured
                    buttonRadius: Appearance.rounding.full
                    materialIcon: "delete"
                    mainText: Translation.tr("Remove")
                    onClicked: PerformanceStats.setMangoHudLogging(false)
                }
            }

            ConfigSwitch {
                buttonIcon: "visibility_off"
                text: Translation.tr("Hide MangoHud's own HUD")
                checked: subPageRoot.hud.mangohudHideHud
                onCheckedChanged: {
                    if (Config.options.overlay.perfMonitor.mangohudHideHud === checked)
                        return;
                    Config.options.overlay.perfMonitor.mangohudHideHud = checked;
                    if (PerformanceStats.mangohud.configured)
                        PerformanceStats.setMangoHudLogging(true);
                }
                StyledToolTip {
                    text: Translation.tr("MangoHud keeps logging but draws nothing, so only this HUD shows.")
                }
            }

            ContentSubsection {
                title: Translation.tr("MangoHud log interval")
                icon: "timer"
                tooltip: Translation.tr("Shorter intervals make the 1% and 0.1% lows more precise and write bigger logs. Old logs are deleted after two days.")

                ConfigSelectionArray {
                    currentValue: subPageRoot.hud.mangohudLogInterval
                    onSelected: newValue => {
                        Config.options.overlay.perfMonitor.mangohudLogInterval = newValue;
                        if (PerformanceStats.mangohud.configured)
                            PerformanceStats.setMangoHudLogging(true);
                    }
                    options: [
                        { displayName: "16 ms", icon: "bolt", value: 16 },
                        { displayName: "50 ms", icon: "speed", value: 50 },
                        { displayName: "100 ms", icon: "eco", value: 100 }
                    ]
                }
            }

            ContentSubsection {
                title: Translation.tr("HUD refresh")
                icon: "update"
                tooltip: Translation.tr("How often the numbers change. Faster costs a little more CPU while the HUD is visible; nothing runs while it is hidden.")

                ConfigSelectionArray {
                    currentValue: subPageRoot.hud.updateInterval
                    onSelected: newValue => { Config.options.overlay.perfMonitor.updateInterval = newValue; }
                    options: [
                        { displayName: "250 ms", icon: "bolt", value: 250 },
                        { displayName: "500 ms", icon: "speed", value: 500 },
                        { displayName: "1 s", icon: "timer", value: 1000 },
                        { displayName: "2 s", icon: "eco", value: 2000 }
                    ]
                }
            }

            NoticeBox {
                Layout.fillWidth: true
                materialIcon: "keyboard"
                text: Translation.tr("Open it from the game overlay (Super+G) and pin it, or bind a key to the \"perfMonitorToggle\" shortcut. From a script: qs -c ii ipc call perfMonitor toggle.")
            }
        }
    }

    // A switch bound to one boolean of Config.options.overlay.perfMonitor.
    component HudSwitch: ConfigSwitch {
        id: hudSwitch
        required property string key
        property string hint: ""
        Layout.fillWidth: true
        checked: subPageRoot.hud[hudSwitch.key]
        onCheckedChanged: {
            if (Config.options.overlay.perfMonitor[hudSwitch.key] !== checked)
                Config.options.overlay.perfMonitor[hudSwitch.key] = checked;
        }
        StyledToolTip {
            extraVisibleCondition: hudSwitch.hint.length > 0
            text: hudSwitch.hint
        }
    }

    // Opaque pill on the hero, like the Colors & Themes status chips.
    component StatusPill: Rectangle {
        id: pill
        required property string icon
        required property string label
        property bool highlighted: false
        implicitHeight: 32
        implicitWidth: pillRow.implicitWidth + 24
        radius: Appearance.rounding.full
        color: pill.highlighted ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSurfaceContainerHigh

        RowLayout {
            id: pillRow
            anchors.centerIn: parent
            spacing: 6

            MaterialSymbol {
                text: pill.icon
                iconSize: Appearance.font.pixelSize.normal
                fill: 1
                color: pill.highlighted ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurface
            }
            StyledText {
                text: pill.label
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: pill.highlighted ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurface
            }
        }
    }
}
