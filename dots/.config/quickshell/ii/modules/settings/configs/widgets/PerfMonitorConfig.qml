import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.overlay.perfMonitor

// Performance HUD. Top to bottom: the live HUD over the wallpaper, the three
// steps that get a frame rate into it, where it sits and how it looks, then
// one section per thing it can show (frame rate, CPU, memory, GPU, battery,
// details line), names, and the advanced bits.
Item {
    id: subPageRoot
    anchors.fill: parent

    property bool showBackButton: false
    signal goBack()

    readonly property var hud: Config.options.overlay.perfMonitor
    readonly property var mango: stats.mangohud

    // Live numbers for the preview, the device list and the setup steps,
    // only while the page is up.
    PerfSampler {
        id: stats
        active: subPageRoot.visible
    }
    onVisibleChanged: {
        if (visible)
            stats.refreshMangoHud();
    }
    Component.onCompleted: stats.refreshMangoHud()

    // "Copied" feedback for the command chips
    property string copiedText: ""
    function copy(text) {
        Quickshell.clipboardText = text;
        subPageRoot.copiedText = text;
        copiedTimer.restart();
    }
    Timer {
        id: copiedTimer
        interval: 1600
        onTriggered: subPageRoot.copiedText = ""
    }

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
            implicitHeight: Math.max(Math.min(Math.max(width / 1.7, 240), 480), preview.height + 2 * heroMargin + 48)
            readonly property real heroMargin: 20
            readonly property string corner: subPageRoot.hud.anchor

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

            // Sits in the corner the HUD is snapped to
            PerfMonitorContent {
                id: preview
                preview: true
                sampler: stats
                x: hero.corner.endsWith("Right") ? hero.width - width - hero.heroMargin : hero.heroMargin
                y: hero.corner.startsWith("bottom") ? hero.height - height - hero.heroMargin : hero.heroMargin
                Behavior on x {
                    enabled: !Appearance.reducedMotion
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                Behavior on y {
                    enabled: !Appearance.reducedMotion
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }

            // Status pills, on the side the HUD is not
            Row {
                y: hero.corner.startsWith("bottom") ? 16 : hero.height - height - 16
                x: hero.corner.endsWith("Right") ? 16 : hero.width - width - 16
                spacing: 8

                StatusPill {
                    icon: stats.fpsActive ? "check_circle" : subPageRoot.mango.configured ? "hourglass_top" : "info"
                    label: stats.fpsActive ? Translation.tr("FPS from %1").arg(String(stats.fps.process ?? "MangoHud"))
                        : subPageRoot.mango.configured ? Translation.tr("Waiting for a game")
                        : Translation.tr("FPS not set up")
                    highlighted: !subPageRoot.mango.configured
                }
                StatusPill {
                    visible: stats.selectedGpu !== null
                    icon: "developer_board"
                    label: stats.selectedGpu?.name ?? ""
                }
            }
        }

        // ── Getting the frame rate ──────────────────────────────────────
        ContentSection {
            Layout.topMargin: 12
            title: Translation.tr("Show the frame rate")
            icon: "speed"
            tooltip: Translation.tr("Linux has no system-wide frame counter. MangoHud runs inside each game and writes its frame times to a log the HUD reads.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                SetupStep {
                    number: 1
                    first: true
                    done: subPageRoot.mango.installed
                    title: Translation.tr("Install MangoHud")
                    body: subPageRoot.mango.installed ? Translation.tr("MangoHud is installed.")
                        : subPageRoot.mango.installCommand ? Translation.tr("Run this in a terminal:")
                        : Translation.tr("Install the \"mangohud\" package from your distribution.")
                    command: subPageRoot.mango.installed ? "" : (subPageRoot.mango.installCommand ?? "")
                    secondBody: subPageRoot.mango.steamFlatpak && !subPageRoot.mango.flatpakLayer
                        ? Translation.tr("Steam is installed as a Flatpak, which needs its own copy:") : ""
                    secondCommand: subPageRoot.mango.steamFlatpak && !subPageRoot.mango.flatpakLayer
                        ? (subPageRoot.mango.flatpakInstallCommand ?? "") : ""

                    RippleButtonWithIcon {
                        visible: !subPageRoot.mango.installed
                        buttonRadius: Appearance.rounding.full
                        materialIcon: "refresh"
                        mainText: Translation.tr("Check again")
                        onClicked: stats.refreshMangoHud()
                    }
                }

                SetupStep {
                    number: 2
                    done: subPageRoot.mango.configured
                    title: Translation.tr("Let the HUD read MangoHud")
                    body: {
                        if (stats.mangoBusy)
                            return Translation.tr("Saving…");
                        if (stats.mangoMessage === "error")
                            return Translation.tr("Could not write the MangoHud config. Check the shell log (qs log -c ii).");
                        if (subPageRoot.mango.configured)
                            return Translation.tr("Logging is on in %1%2.").arg(String(subPageRoot.mango.confPath))
                                .arg(subPageRoot.mango.flatpakConfigured ? Translation.tr(" and in Flatpak Steam") : "");
                        if (stats.mangoMessage === "removed")
                            return Translation.tr("Logging removed from %1.").arg(String(subPageRoot.mango.confPath));
                        return Translation.tr("Adds a small marked block to %1 so MangoHud logs frame times for the HUD. Your other MangoHud settings stay as they are.").arg(String(subPageRoot.mango.confPath));
                    }

                    RippleButtonWithIcon {
                        enabled: !stats.mangoBusy
                        buttonRadius: Appearance.rounding.full
                        materialIcon: subPageRoot.mango.configured ? "refresh" : "build"
                        mainText: subPageRoot.mango.configured ? Translation.tr("Apply again") : Translation.tr("Set up")
                        onClicked: stats.setMangoHudLogging(true)
                    }
                    RippleButtonWithIcon {
                        visible: subPageRoot.mango.configured
                        enabled: !stats.mangoBusy
                        buttonRadius: Appearance.rounding.full
                        materialIcon: "delete"
                        mainText: Translation.tr("Remove")
                        onClicked: stats.setMangoHudLogging(false)
                    }
                }

                SetupStep {
                    number: 3
                    last: true
                    done: stats.fpsActive
                    title: Translation.tr("Start the game with MangoHud")
                    body: stats.fpsActive
                        ? Translation.tr("Receiving frames from %1.").arg(String(stats.fps.process ?? ""))
                        : Translation.tr("Steam: right-click the game › Properties › Launch options, and paste:")
                    command: stats.fpsActive ? "" : "mangohud %command%"
                    secondBody: stats.fpsActive ? ""
                        : Translation.tr("Lutris, Heroic and Bottles have a MangoHud switch in the game's settings. From a terminal, put mangohud before the game's command. The FPS shows up a second after the game starts.")
                }
            }
        }

        // ── Position ────────────────────────────────────────────────────
        ContentSection {
            Layout.topMargin: 12
            title: Translation.tr("Position")
            icon: "picture_in_picture"
            tooltip: Translation.tr("A corner keeps the HUD there as it grows or shrinks. Dragging it in the overlay frees it; the corner buttons on its title bar snap it back.")

            ContentSubsection {
                title: Translation.tr("Snap to")
                icon: "select_all"

                ConfigSelectionArray {
                    currentValue: subPageRoot.hud.anchor
                    onSelected: newValue => { Config.options.overlay.perfMonitor.anchor = newValue; }
                    options: [
                        { displayName: Translation.tr("Top left"), icon: "north_west", value: "topLeft" },
                        { displayName: Translation.tr("Top right"), icon: "north_east", value: "topRight" },
                        { displayName: Translation.tr("Bottom left"), icon: "south_west", value: "bottomLeft" },
                        { displayName: Translation.tr("Bottom right"), icon: "south_east", value: "bottomRight" },
                        { displayName: Translation.tr("Free"), icon: "open_with", value: "none" }
                    ]
                }
            }

            ConfigSlider {
                visible: subPageRoot.hud.anchor !== "none"
                buttonIcon: "padding"
                text: Translation.tr("Distance from the edges")
                usePercentTooltip: false
                from: 0
                to: 80
                stepSize: 2
                value: subPageRoot.hud.snapMargin
                onValueChanged: Config.options.overlay.perfMonitor.snapMargin = value
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
                    currentValue: subPageRoot.hud.fpsOnly ? "fpsOnly" : subPageRoot.hud.style
                    onSelected: newValue => {
                        Config.options.overlay.perfMonitor.fpsOnly = newValue === "fpsOnly";
                        if (newValue !== "fpsOnly")
                            Config.options.overlay.perfMonitor.style = newValue;
                    }
                    options: [
                        { displayName: Translation.tr("Bars"), icon: "view_day", value: "bars" },
                        { displayName: Translation.tr("Graph"), icon: "monitoring", value: "graph" },
                        { displayName: Translation.tr("Text only"), icon: "notes", value: "text" },
                        { displayName: Translation.tr("FPS only"), icon: "speed", value: "fpsOnly" }
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

            ConfigSlider {
                buttonIcon: "opacity"
                text: Translation.tr("Background opacity (%)")
                from: 0
                to: 100
                stepSize: 5
                value: Math.round(subPageRoot.hud.backgroundOpacity * 100)
                onValueChanged: Config.options.overlay.perfMonitor.backgroundOpacity = value / 100
            }

            ConfigRow {
                uniform: true

                HudSwitch {
                    key: "blur"
                    buttonIcon: "blur_on"
                    text: Translation.tr("Blur behind the HUD")
                    hint: Translation.tr("Hyprland blurs what is behind the card. Off keeps it a plain see-through card; while the HUD is on screen, other overlay widgets lose their blur too.")
                }
                HudSwitch {
                    key: "colorCodeFps"
                    buttonIcon: "traffic"
                    text: Translation.tr("Color the frame rate")
                    hint: Translation.tr("Tint the FPS number by how close it is to the target frame rate.")
                }
            }

            ConfigRow {
                uniform: true

                HudSwitch {
                    key: "uppercase"
                    buttonIcon: "match_case"
                    text: Translation.tr("Uppercase labels")
                    hint: Translation.tr("Write names and captions in capitals, like RivaTuner.")
                }
                HudSwitch {
                    key: "showIcons"
                    buttonIcon: "category"
                    text: Translation.tr("Icons on the details line")
                    hint: Translation.tr("Show a small icon in each chip of the details line.")
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
                from: 220
                to: 420
                stepSize: 10
                value: subPageRoot.hud.width
                onValueChanged: Config.options.overlay.perfMonitor.width = value
            }
        }

        // ── What it shows ───────────────────────────────────────────────
        ContentSection {
            Layout.topMargin: 12
            title: Translation.tr("Frame rate")
            icon: "speed"

            HudSwitch {
                key: "showFps"
                buttonIcon: "speed"
                text: Translation.tr("Show the frame rate")
                hint: Translation.tr("The FPS tile at the top of the HUD.")
            }
            ConfigRow {
                uniform: true
                enabled: subPageRoot.hud.showFps
                opacity: enabled ? 1 : 0.4
                HudSwitch { key: "showFpsAverage"; buttonIcon: "functions"; text: Translation.tr("Average"); hint: Translation.tr("Average frame rate over the statistics window.") }
                HudSwitch { key: "showFpsLow1"; buttonIcon: "trending_down"; text: Translation.tr("1% low"); hint: Translation.tr("The frame rate of the slowest 1% of frames: how bad the stutters get.") }
            }
            ConfigRow {
                uniform: true
                enabled: subPageRoot.hud.showFps
                opacity: enabled ? 1 : 0.4
                HudSwitch { key: "showFpsLow01"; buttonIcon: "south"; text: Translation.tr("0.1% low"); hint: Translation.tr("The frame rate of the slowest 0.1% of frames.") }
                HudSwitch { key: "showFrametime"; buttonIcon: "timer"; text: Translation.tr("Frame time"); hint: Translation.tr("How long the last frame took, in milliseconds.") }
            }
            ConfigRow {
                uniform: true
                enabled: subPageRoot.hud.showFps
                opacity: enabled ? 1 : 0.4
                HudSwitch { key: "showFrametimeGraph"; buttonIcon: "show_chart"; text: Translation.tr("Frame-time graph"); hint: Translation.tr("A line of recent frame times. Spikes are stutters.") }
                Item { Layout.fillWidth: true }
            }
            ConfigRow {
                uniform: true
                enabled: subPageRoot.hud.showFps
                opacity: enabled ? 1 : 0.4

                ConfigSpinBox {
                    icon: "flag"
                    text: Translation.tr("Target FPS")
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
        }

        ContentSection {
            Layout.topMargin: 12
            title: Translation.tr("Processor")
            icon: "memory"

            HudSwitch {
                key: "showCpu"
                buttonIcon: "memory"
                text: Translation.tr("Show the CPU")
            }
            ConfigRow {
                uniform: true
                enabled: subPageRoot.hud.showCpu
                opacity: enabled ? 1 : 0.4
                HudSwitch { key: "showCpuUsage"; buttonIcon: "percent"; text: Translation.tr("Usage") }
                HudSwitch { key: "showCpuTemp"; buttonIcon: "thermostat"; text: Translation.tr("Temperature") }
            }
            ConfigRow {
                uniform: true
                enabled: subPageRoot.hud.showCpu
                opacity: enabled ? 1 : 0.4
                HudSwitch { key: "showCpuClock"; buttonIcon: "speed"; text: Translation.tr("Frequency") }
                HudSwitch {
                    key: "showCpuPower"
                    buttonIcon: "bolt"
                    text: Translation.tr("Power")
                    hint: stats.ready && !stats.cpuHasPower
                        ? Translation.tr("This system does not let users read the CPU's power (RAPL is root-only). MangoHud's value is used while a game logs it.")
                        : Translation.tr("Package power draw.")
                }
            }
        }

        ContentSection {
            Layout.topMargin: 12
            title: Translation.tr("Memory")
            icon: "memory_alt"
            tooltip: Translation.tr("Shown inside the CPU tile, or on its own when the CPU is hidden.")

            ConfigRow {
                uniform: true
                HudSwitch { key: "showRam"; buttonIcon: "memory_alt"; text: Translation.tr("RAM"); hint: Translation.tr("Used and total memory.") }
                HudSwitch { key: "showSwap"; buttonIcon: "swap_horiz"; text: Translation.tr("Swap") }
            }
        }

        ContentSection {
            Layout.topMargin: 12
            title: Translation.tr("Graphics card")
            icon: "developer_board"

            ContentSubsection {
                visible: stats.gpus.length > 1
                title: Translation.tr("Monitored GPU")
                icon: "swap_horiz"
                tooltip: Translation.tr("A sleeping discrete GPU is shown as sleeping, never woken up. While the overlay is open, click the GPU's name on the HUD to switch.")

                ConfigSelectionArray {
                    currentValue: subPageRoot.hud.gpuDevice
                    onSelected: newValue => { Config.options.overlay.perfMonitor.gpuDevice = newValue; }
                    options: [{ displayName: Translation.tr("Automatic"), icon: "auto_awesome", value: "auto" }].concat(
                        stats.gpus.map(g => ({
                            displayName: g.name,
                            icon: g.discrete ? "developer_board" : "memory",
                            value: g.id
                        })))
                }
            }

            HudSwitch {
                key: "showGpu"
                buttonIcon: "developer_board"
                text: Translation.tr("Show the GPU")
            }
            ConfigRow {
                uniform: true
                enabled: subPageRoot.hud.showGpu
                opacity: enabled ? 1 : 0.4
                HudSwitch { key: "showGpuUsage"; buttonIcon: "percent"; text: Translation.tr("Usage") }
                HudSwitch { key: "showGpuTemp"; buttonIcon: "thermostat"; text: Translation.tr("Temperature") }
            }
            ConfigRow {
                uniform: true
                enabled: subPageRoot.hud.showGpu
                opacity: enabled ? 1 : 0.4
                HudSwitch { key: "showGpuClock"; buttonIcon: "speed"; text: Translation.tr("Core frequency") }
                HudSwitch { key: "showGpuMemClock"; buttonIcon: "memory"; text: Translation.tr("Memory frequency") }
            }
            ConfigRow {
                uniform: true
                enabled: subPageRoot.hud.showGpu
                opacity: enabled ? 1 : 0.4
                HudSwitch { key: "showGpuPower"; buttonIcon: "bolt"; text: Translation.tr("Power") }
                HudSwitch { key: "showGpuFan"; buttonIcon: "mode_fan"; text: Translation.tr("Fan") }
            }
            ConfigRow {
                uniform: true
                enabled: subPageRoot.hud.showGpu
                opacity: enabled ? 1 : 0.4
                HudSwitch { key: "showVram"; buttonIcon: "sd_card"; text: Translation.tr("VRAM"); hint: Translation.tr("Used and total video memory.") }
                Item { Layout.fillWidth: true }
            }
        }

        ContentSection {
            Layout.topMargin: 12
            title: Translation.tr("Battery")
            icon: "battery_horiz_075"
            tooltip: Translation.tr("Only on laptops.")

            HudSwitch {
                key: "showBattery"
                buttonIcon: "battery_horiz_075"
                text: Translation.tr("Show the battery")
            }
            ConfigRow {
                uniform: true
                enabled: subPageRoot.hud.showBattery
                opacity: enabled ? 1 : 0.4
                HudSwitch { key: "showBatteryEnergy"; buttonIcon: "battery_charging_full"; text: Translation.tr("Charge (Wh)") }
                HudSwitch { key: "showBatteryPower"; buttonIcon: "bolt"; text: Translation.tr("Power draw") }
            }
            ConfigRow {
                uniform: true
                enabled: subPageRoot.hud.showBattery
                opacity: enabled ? 1 : 0.4
                HudSwitch { key: "showBatteryTime"; buttonIcon: "schedule"; text: Translation.tr("Time left") }
                Item { Layout.fillWidth: true }
            }
        }

        ContentSection {
            Layout.topMargin: 12
            title: Translation.tr("Details line")
            icon: "label"
            tooltip: Translation.tr("The chips at the bottom of the HUD.")

            ConfigRow {
                uniform: true
                HudSwitch { key: "showProcess"; buttonIcon: "sports_esports"; text: Translation.tr("Game name") }
                HudSwitch { key: "showResolution"; buttonIcon: "aspect_ratio"; text: Translation.tr("Resolution") }
            }
            ConfigRow {
                uniform: true
                HudSwitch { key: "showDriver"; buttonIcon: "deployed_code"; text: Translation.tr("GPU driver") }
                HudSwitch { key: "showSessionTime"; buttonIcon: "timer"; text: Translation.tr("Session time"); hint: Translation.tr("How long the game has been running.") }
            }
            ConfigRow {
                uniform: true
                HudSwitch { key: "showClock"; buttonIcon: "schedule"; text: Translation.tr("Clock") }
                Item { Layout.fillWidth: true }
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
                placeholderText: stats.cpuModel || "CPU"
                inputText: subPageRoot.hud.cpuName
                textField.onEditingFinished: Config.options.overlay.perfMonitor.cpuName = textField.text
            }
            ConfigTextField {
                Layout.fillWidth: true
                text: Translation.tr("GPU name")
                icon: "developer_board"
                placeholderText: stats.selectedGpu?.name ?? "GPU"
                inputText: subPageRoot.hud.gpuName
                textField.onEditingFinished: Config.options.overlay.perfMonitor.gpuName = textField.text
            }
        }

        // ── Advanced ────────────────────────────────────────────────────
        ContentSection {
            Layout.topMargin: 12
            title: Translation.tr("Advanced")
            icon: "tune"

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

            ContentSubsection {
                title: Translation.tr("MangoHud log interval")
                icon: "timer"
                tooltip: Translation.tr("Shorter intervals make the 1% and 0.1% lows more precise and write bigger logs. Old logs are deleted after two days.")

                ConfigSelectionArray {
                    currentValue: subPageRoot.hud.mangohudLogInterval
                    onSelected: newValue => {
                        Config.options.overlay.perfMonitor.mangohudLogInterval = newValue;
                        if (subPageRoot.mango.configured)
                            stats.setMangoHudLogging(true);
                    }
                    options: [
                        { displayName: "16 ms", icon: "bolt", value: 16 },
                        { displayName: "50 ms", icon: "speed", value: 50 },
                        { displayName: "100 ms", icon: "eco", value: 100 }
                    ]
                }
            }

            ConfigRow {
                uniform: true

                ConfigSwitch {
                    buttonIcon: "visibility_off"
                    text: Translation.tr("Hide MangoHud's own HUD")
                    checked: subPageRoot.hud.mangohudHideHud
                    onCheckedChanged: {
                        if (Config.options.overlay.perfMonitor.mangohudHideHud === checked)
                            return;
                        Config.options.overlay.perfMonitor.mangohudHideHud = checked;
                        if (subPageRoot.mango.configured)
                            stats.setMangoHudLogging(true);
                    }
                    StyledToolTip {
                        text: Translation.tr("MangoHud keeps logging but draws nothing, so only this HUD shows.")
                    }
                }
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
        checked: subPageRoot.hud[hudSwitch.key] ?? false
        onCheckedChanged: {
            if (Config.options.overlay.perfMonitor[hudSwitch.key] !== checked)
                Config.options.overlay.perfMonitor[hudSwitch.key] = checked;
        }
        StyledToolTip {
            extraVisibleCondition: hudSwitch.hint.length > 0
            text: hudSwitch.hint
        }
    }

    // One step of the frame-rate setup: shape badge (number, or a check once
    // done), title, explanation, an optional command to copy, and actions.
    component SetupStep: Rectangle {
        id: step
        required property int number
        required property bool done
        required property string title
        property string body: ""
        property string command: ""
        property string secondBody: ""
        property string secondCommand: ""
        property bool first: false
        property bool last: false
        default property alias actions: actionRow.data

        Layout.fillWidth: true
        implicitHeight: stepRow.implicitHeight + 32
        color: Appearance.colors.colLayer2
        topLeftRadius: step.first ? Appearance.rounding.large : Appearance.rounding.verysmall
        topRightRadius: step.first ? Appearance.rounding.large : Appearance.rounding.verysmall
        bottomLeftRadius: step.last ? Appearance.rounding.large : Appearance.rounding.verysmall
        bottomRightRadius: step.last ? Appearance.rounding.large : Appearance.rounding.verysmall

        RowLayout {
            id: stepRow
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                margins: 16
            }
            spacing: 14

            MaterialShapeWrappedMaterialSymbol {
                Layout.alignment: Qt.AlignTop
                text: step.done ? "check" : ["looks_one", "looks_two", "looks_3"][step.number - 1] ?? "circle"
                shape: step.done ? MaterialShape.Shape.Cookie9Sided : MaterialShape.Shape.Circle
                iconSize: 20
                padding: 8
                color: step.done ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
                colSymbol: step.done ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                StyledText {
                    Layout.fillWidth: true
                    text: step.title
                    color: Appearance.colors.colOnLayer2
                    font {
                        family: Appearance.font.family.title
                        variableAxes: Appearance.font.variableAxes.titleRounded
                        pixelSize: Appearance.font.pixelSize.normal
                    }
                }
                StyledText {
                    visible: step.body.length > 0
                    Layout.fillWidth: true
                    text: step.body
                    wrapMode: Text.WordWrap
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.small
                }
                CommandChip {
                    visible: step.command.length > 0
                    command: step.command
                }
                StyledText {
                    visible: step.secondBody.length > 0
                    Layout.fillWidth: true
                    text: step.secondBody
                    wrapMode: Text.WordWrap
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.small
                }
                CommandChip {
                    visible: step.secondCommand.length > 0
                    command: step.secondCommand
                }
                RowLayout {
                    id: actionRow
                    visible: children.length > 0
                    spacing: 6
                }
            }
        }
    }

    // A command in a monospace pill with a copy button.
    component CommandChip: Rectangle {
        id: chip
        required property string command
        Layout.fillWidth: true
        implicitHeight: chipRow.implicitHeight + 12
        radius: Appearance.rounding.small
        color: Appearance.colors.colLayer3

        RowLayout {
            id: chipRow
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                leftMargin: 14
                rightMargin: 6
            }
            spacing: 8

            StyledText {
                Layout.fillWidth: true
                text: chip.command
                elide: Text.ElideRight
                color: Appearance.colors.colOnLayer3
                font {
                    family: Appearance.font.family.monospace
                    pixelSize: Appearance.font.pixelSize.small
                }
            }
            RippleButtonWithIcon {
                buttonRadius: Appearance.rounding.full
                materialIcon: subPageRoot.copiedText === chip.command ? "check" : "content_copy"
                mainText: subPageRoot.copiedText === chip.command ? Translation.tr("Copied") : Translation.tr("Copy")
                onClicked: subPageRoot.copy(chip.command)
            }
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
