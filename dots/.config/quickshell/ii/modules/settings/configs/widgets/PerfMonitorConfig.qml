import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.overlay.perfMonitor
import qs.modules.settings.configs.colors
import qs.modules.settings.configs.lockscreen

// Performance HUD, built like the Lock Screen page (docs/design/settings-expressive.md):
//   1. the real HUD, live, over the current wallpaper, in the monitor's proportions
//   2. the Look pane: chips and sliders in two columns (one below 720 px)
//   3. one feature tile per block of the HUD, its metrics as chips on the tile
//   4. the frame-rate pane: MangoHud setup steps and the games it is wired into
//   5. names and the rare options, with the original components
Item {
    id: subPageRoot
    anchors.fill: parent

    property bool showBackButton: false
    signal goBack()

    readonly property var hud: Config.options.overlay.perfMonitor
    readonly property var mango: stats.mangohud

    function setOption(key, value) {
        if (Config.options.overlay.perfMonitor[key] !== value)
            Config.options.overlay.perfMonitor[key] = value;
    }

    // Live numbers for the preview, the device list, the setup steps and the
    // games list, only while the page is up and Settings is actually open (a
    // kept-alive Settings window keeps its pages, hidden, for a while).
    //
    // They start a beat after the page appears: the sampler and the two
    // status scripts are Python processes, and spawning them while the page
    // is still being built is what made opening it stutter.
    property bool settled: false
    PerfSampler {
        id: stats
        active: subPageRoot.visible && subPageRoot.settled && GlobalStates.settingsOpen
    }
    function refreshExternal() {
        stats.refreshMangoHud();
        stats.refreshGames();
    }
    Timer {
        id: settleTimer
        interval: 450
        running: subPageRoot.visible && GlobalStates.settingsOpen
        onTriggered: {
            subPageRoot.settled = true;
            subPageRoot.refreshExternal();
        }
    }
    onVisibleChanged: {
        if (!visible)
            subPageRoot.settled = false;
    }

    // Read by several bindings of the setup steps and the games list
    readonly property bool anyGameNeedsLayer: stats.games.some(g => g.needsLayer)
    readonly property bool anyGameEnabled: stats.games.some(g => g.enabled)

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

        // ── 1. The HUD, live, on the screen it will sit on ──────────────
        Item {
            id: hero
            Layout.fillWidth: true
            implicitHeight: hero.previewHeight

            readonly property var monitor: Quickshell.screens.find(s => s.name === Hyprland?.focusedMonitor?.name) ?? Quickshell.screens[0] ?? null
            readonly property real screenWidth: hero.monitor?.width ?? 1920
            readonly property real screenHeight: hero.monitor?.height ?? 1080
            readonly property real aspect: hero.screenWidth / Math.max(1, hero.screenHeight)
            // The whole row unless that is taller than a screenful; then centred
            readonly property int previewWidth: Math.round(Math.min(hero.width, 400 * hero.aspect))
            readonly property int previewHeight: Math.round(hero.previewWidth / hero.aspect)
            // The real HUD scaled like the screen, kept readable on a small page
            readonly property real hudScale: Math.max(0.55, hero.previewWidth / hero.screenWidth)
            readonly property string corner: subPageRoot.hud.anchor
            readonly property real margin: subPageRoot.hud.snapMargin * hero.hudScale

            ClippingRectangle {
                id: screenCard
                x: Math.round((hero.width - width) / 2)
                width: hero.previewWidth
                height: hero.previewHeight
                radius: Appearance.rounding.verylarge
                color: Appearance.colors.colLayer1

                ColorsWallpaperImage {
                    anchors.fill: parent
                    targetMode: "desktop"
                }

                PerfMonitorContent {
                    id: preview
                    preview: true
                    sampler: stats
                    transformOrigin: Item.TopLeft
                    scale: hero.hudScale
                    readonly property real shownWidth: width * scale
                    readonly property real shownHeight: height * scale
                    x: hero.corner.endsWith("Right") ? screenCard.width - preview.shownWidth - hero.margin
                        : hero.corner === "none" ? Math.round((screenCard.width - preview.shownWidth) / 2) : hero.margin
                    y: hero.corner.startsWith("bottom") ? screenCard.height - preview.shownHeight - hero.margin
                        : hero.corner === "none" ? Math.round((screenCard.height - preview.shownHeight) / 2) : hero.margin
                    Behavior on x {
                        enabled: !Appearance.reducedMotion
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                    Behavior on y {
                        enabled: !Appearance.reducedMotion
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                }

                // Status pills on the opposite side from the HUD
                Row {
                    y: hero.corner.startsWith("bottom") ? 16 : screenCard.height - height - 16
                    x: hero.corner.endsWith("Right") ? 16 : screenCard.width - width - 16
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
        }

        // ── 2. Look ─────────────────────────────────────────────────────
        Pane {
            id: lookPane
            Layout.fillWidth: true
            // Two columns of controls once the page is wide enough
            readonly property int columns: lookPane.width >= 720 ? 2 : 1
            symbol: "palette"
            title: Translation.tr("Look")
            subtitle: {
                const style = subPageRoot.hud.fpsOnly ? Translation.tr("FPS only")
                    : { "bars": Translation.tr("Bars"), "graph": Translation.tr("Graph"), "text": Translation.tr("Text only") }[subPageRoot.hud.style] ?? "";
                const palette = { "accent": Translation.tr("Accent"), "container": Translation.tr("Tonal"), "mono": Translation.tr("Monochrome") }[subPageRoot.hud.palette] ?? "";
                const corner = { "topLeft": Translation.tr("Top left"), "topRight": Translation.tr("Top right"),
                    "bottomLeft": Translation.tr("Bottom left"), "bottomRight": Translation.tr("Bottom right") }[subPageRoot.hud.anchor] ?? Translation.tr("Free");
                return `${style} · ${palette} · ${corner}`;
            }

            GridLayout {
                Layout.fillWidth: true
                columns: lookPane.columns
                columnSpacing: 28
                rowSpacing: 12
                uniformCellWidths: true

                ChipGroup {
                    caption: Translation.tr("Style")
                    ChoiceChip { key: "style"; value: "bars"; symbol: "view_day"; label: Translation.tr("Bars"); exclusiveOf: "fpsOnly" }
                    ChoiceChip { key: "style"; value: "graph"; symbol: "monitoring"; label: Translation.tr("Graph"); exclusiveOf: "fpsOnly" }
                    ChoiceChip { key: "style"; value: "text"; symbol: "notes"; label: Translation.tr("Text only"); exclusiveOf: "fpsOnly" }
                    ColorsChip {
                        symbol: "speed"
                        label: Translation.tr("FPS only")
                        chosen: subPageRoot.hud.fpsOnly
                        onClicked: subPageRoot.setOption("fpsOnly", !subPageRoot.hud.fpsOnly)
                    }
                }
                ChipGroup {
                    caption: Translation.tr("Colors")
                    ChoiceChip { key: "palette"; value: "accent"; symbol: "colors"; label: Translation.tr("Accent") }
                    ChoiceChip { key: "palette"; value: "container"; symbol: "gradient"; label: Translation.tr("Tonal") }
                    ChoiceChip { key: "palette"; value: "mono"; symbol: "contrast"; label: Translation.tr("Monochrome") }
                }
                ChipGroup {
                    caption: Translation.tr("Corner")
                    ChoiceChip { key: "anchor"; value: "topLeft"; symbol: "north_west"; label: Translation.tr("Top left") }
                    ChoiceChip { key: "anchor"; value: "topRight"; symbol: "north_east"; label: Translation.tr("Top right") }
                    ChoiceChip { key: "anchor"; value: "bottomLeft"; symbol: "south_west"; label: Translation.tr("Bottom left") }
                    ChoiceChip { key: "anchor"; value: "bottomRight"; symbol: "south_east"; label: Translation.tr("Bottom right") }
                    ChoiceChip { key: "anchor"; value: "none"; symbol: "open_with"; label: Translation.tr("Free") }
                }
                ChipGroup {
                    caption: Translation.tr("Options")
                    ToggleChip { key: "blur"; symbol: "blur_on"; label: Translation.tr("Blur behind") }
                    ToggleChip { key: "colorCodeFps"; symbol: "traffic"; label: Translation.tr("Color the FPS") }
                    ToggleChip { key: "uppercase"; symbol: "match_case"; label: Translation.tr("Uppercase") }
                    ToggleChip { key: "showIcons"; symbol: "category"; label: Translation.tr("Detail icons") }
                    ToggleChip { key: "monoNumbers"; symbol: "123"; label: Translation.tr("Mono numbers") }
                }
            }

            GridLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                columns: lookPane.columns
                columnSpacing: 28
                rowSpacing: 0
                uniformCellWidths: true

                LockSliderRow {
                    Layout.fillWidth: true
                    symbol: "zoom_in"
                    label: Translation.tr("Size")
                    activeShape: MaterialShape.Shape.Cookie12Sided
                    from: 0.6
                    to: 1.8
                    stepSize: 0.05
                    zeroText: "60%"
                    value: subPageRoot.hud.scale
                    onMoved: value => subPageRoot.setOption("scale", Math.round(value * 100) / 100)
                }
                LockSliderRow {
                    visible: subPageRoot.hud.style !== "text" && !subPageRoot.hud.fpsOnly
                    Layout.fillWidth: true
                    symbol: "width"
                    label: Translation.tr("Width")
                    activeShape: MaterialShape.Shape.Pill
                    from: 220
                    to: 420
                    stepSize: 10
                    format: v => `${Math.round(v)} px`
                    zeroText: "220 px"
                    value: subPageRoot.hud.width
                    onMoved: value => subPageRoot.setOption("width", Math.round(value))
                }
                LockSliderRow {
                    Layout.fillWidth: true
                    symbol: "opacity"
                    label: Translation.tr("Background")
                    activeShape: MaterialShape.Shape.Gem
                    from: 0
                    to: 1
                    stepSize: 0.05
                    zeroText: Translation.tr("None")
                    value: subPageRoot.hud.backgroundOpacity
                    onMoved: value => subPageRoot.setOption("backgroundOpacity", Math.round(value * 100) / 100)
                }
                LockSliderRow {
                    visible: subPageRoot.hud.anchor !== "none"
                    Layout.fillWidth: true
                    symbol: "padding"
                    label: Translation.tr("Distance from the edges")
                    activeShape: MaterialShape.Shape.Square
                    from: 0
                    to: 80
                    stepSize: 2
                    format: v => `${Math.round(v)} px`
                    zeroText: Translation.tr("Flush")
                    value: subPageRoot.hud.snapMargin
                    onMoved: value => subPageRoot.setOption("snapMargin", Math.round(value))
                }
            }
        }

        // ── 3. What it shows ────────────────────────────────────────────
        Loader {
            Layout.fillWidth: true
            Layout.topMargin: 4
            asynchronous: true
            sourceComponent: Component {
                AppSettingsSection {
                    title: Translation.tr("What it shows")
                    symbol: "dashboard_customize"
                    description: Translation.tr("Turn a block on with its switch, then pick its numbers. The HUD shrinks around what is on.")

                    Item {
                        id: tiles
                        Layout.fillWidth: true
                        readonly property real gap: 12
                        // 3 / 2 / 1 columns from a 300 px minimum; the last tile takes the rest of its row
                        readonly property int columns: tiles.width >= 300 * 3 + tiles.gap * 2 ? 3 : tiles.width >= 300 * 2 + tiles.gap ? 2 : 1
                        readonly property real tileWidth: Math.floor((tiles.width - tiles.gap * (tiles.columns - 1)) / tiles.columns)
                        readonly property int count: 7
                        readonly property real tileHeight: Math.max(fpsTile.implicitHeight, cpuTile.implicitHeight, memTile.implicitHeight,
                            gpuTile.implicitHeight, netTile.implicitHeight, batteryTile.implicitHeight, detailsTile.implicitHeight)
                        implicitHeight: Math.ceil(tiles.count / tiles.columns) * (tiles.tileHeight + tiles.gap) - tiles.gap

                        function cellX(i) {
                            return (i % tiles.columns) * (tiles.tileWidth + tiles.gap);
                        }
                        function cellY(i) {
                            return Math.floor(i / tiles.columns) * (tiles.tileHeight + tiles.gap);
                        }

                        HudTile {
                            id: fpsTile
                            x: tiles.cellX(0)
                            y: tiles.cellY(0)
                            width: tiles.tileWidth
                            height: tiles.tileHeight
                            key: "showFps"
                            symbol: "speed"
                            shapeOn: MaterialShape.Shape.Cookie12Sided
                            title: Translation.tr("Frame rate")
                            MetricChip { key: "showFpsAverage"; label: Translation.tr("Average") }
                            MetricChip { key: "showFpsLow1"; label: "1% low" }
                            MetricChip { key: "showFpsLow01"; label: "0.1% low" }
                            MetricChip { key: "showFrametime"; label: Translation.tr("Frame time") }
                            MetricChip { key: "showFrametimeGraph"; label: Translation.tr("Graph") }
                            MetricChip { key: "showStutter"; label: Translation.tr("Stutters") }
                            MetricChip { key: "showFpsCap"; label: Translation.tr("FPS cap") }
                        }
                        HudTile {
                            id: cpuTile
                            x: tiles.cellX(1)
                            y: tiles.cellY(1)
                            width: tiles.tileWidth
                            height: tiles.tileHeight
                            key: "showCpu"
                            symbol: "memory"
                            shapeOn: MaterialShape.Shape.Flower
                            title: Translation.tr("Processor")
                            MetricChip { key: "showCpuUsage"; label: Translation.tr("Usage") }
                            MetricChip { key: "showCpuTemp"; label: Translation.tr("Temperature") }
                            MetricChip { key: "showCpuClock"; label: Translation.tr("Frequency") }
                            MetricChip { key: "showCpuPower"; label: Translation.tr("Power") }
                        }
                        HudTile {
                            id: memTile
                            x: tiles.cellX(2)
                            y: tiles.cellY(2)
                            width: tiles.tileWidth
                            height: tiles.tileHeight
                            key: "showRam"
                            symbol: "memory_alt"
                            shapeOn: MaterialShape.Shape.SoftBurst
                            title: Translation.tr("Memory")
                            hint: Translation.tr("Inside the CPU tile, or on its own when the CPU is off")
                            MetricChip { key: "showSwap"; label: Translation.tr("Swap") }
                        }
                        HudTile {
                            id: gpuTile
                            x: tiles.cellX(3)
                            y: tiles.cellY(3)
                            width: tiles.tileWidth
                            height: tiles.tileHeight
                            key: "showGpu"
                            symbol: "developer_board"
                            shapeOn: MaterialShape.Shape.Clover4Leaf
                            title: Translation.tr("Graphics card")
                            MetricChip { key: "showGpuUsage"; label: Translation.tr("Usage") }
                            MetricChip { key: "showGpuTemp"; label: Translation.tr("Temperature") }
                            MetricChip { key: "showGpuClock"; label: Translation.tr("Frequency") }
                            MetricChip { key: "showGpuMemClock"; label: Translation.tr("Memory frequency") }
                            MetricChip { key: "showGpuPower"; label: Translation.tr("Power") }
                            MetricChip { key: "showGpuFan"; label: Translation.tr("Fan") }
                            MetricChip { key: "showVram"; label: "VRAM" }

                            // Which card, when there is more than one
                            Repeater {
                                model: stats.gpus.length > 1 ? stats.gpus : []
                                delegate: ColorsChip {
                                    required property var modelData
                                    symbol: modelData.discrete ? "developer_board" : "memory"
                                    label: modelData.name
                                    chosen: stats.selectedGpuId === modelData.id
                                    colContent: gpuTile.colContent
                                    colChosen: gpuTile.checked ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
                                    colOnChosen: gpuTile.checked ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                                    onClicked: subPageRoot.setOption("gpuDevice", modelData.id)
                                }
                            }
                        }
                        HudTile {
                            id: netTile
                            x: tiles.cellX(4)
                            y: tiles.cellY(4)
                            width: tiles.tileWidth
                            height: tiles.tileHeight
                            key: "showNetwork"
                            symbol: "network_ping"
                            shapeOn: MaterialShape.Shape.Pentagon
                            title: Translation.tr("Network")
                            hint: Translation.tr("Ping, shown big")
                            MetricChip { key: "showNetDown"; label: Translation.tr("Download") }
                            MetricChip { key: "showNetUp"; label: Translation.tr("Upload") }
                            MetricChip { key: "showNetJitter"; label: Translation.tr("Jitter") }
                            MetricChip { key: "showNetLoss"; label: Translation.tr("Packet loss") }
                        }
                        HudTile {
                            id: batteryTile
                            x: tiles.cellX(5)
                            y: tiles.cellY(5)
                            width: tiles.tileWidth
                            height: tiles.tileHeight
                            key: "showBattery"
                            symbol: "battery_horiz_075"
                            shapeOn: MaterialShape.Shape.Sunny
                            title: Translation.tr("Battery")
                            hint: Battery.available ? "" : Translation.tr("This computer has no battery")
                            MetricChip { key: "showBatteryEnergy"; label: Translation.tr("Charge (Wh)") }
                            MetricChip { key: "showBatteryPower"; label: Translation.tr("Power draw") }
                            MetricChip { key: "showBatteryTime"; label: Translation.tr("Time left") }
                        }
                        HudTile {
                            id: detailsTile
                            x: tiles.cellX(6)
                            y: tiles.cellY(6)
                            // The last tile takes what is left of its row
                            width: tiles.tileWidth * (tiles.columns - 6 % tiles.columns) + tiles.gap * (tiles.columns - 6 % tiles.columns - 1)
                            height: tiles.tileHeight
                            key: "showDetails"
                            symbol: "label"
                            shapeOn: MaterialShape.Shape.Cookie7Sided
                            title: Translation.tr("Details line")
                            MetricChip { key: "showProcess"; label: Translation.tr("Game name") }
                            MetricChip { key: "showResolution"; label: Translation.tr("Resolution") }
                            MetricChip { key: "showDriver"; label: Translation.tr("GPU driver") }
                            MetricChip { key: "showSessionTime"; label: Translation.tr("Session time") }
                            MetricChip { key: "showClock"; label: Translation.tr("Clock") }
                            MetricChip { key: "showPowerProfile"; label: Translation.tr("Power profile") }
                            MetricChip { key: "showGameMode"; label: "GameMode" }
                        }
                    }
                }
            }
        }

        // ── 4. Where the frame rate comes from ──────────────────────────
        Loader {
            Layout.fillWidth: true
            Layout.topMargin: 4
            asynchronous: true
            sourceComponent: Component {
                Pane {
                    symbol: "sports_esports"
                    shape: MaterialShape.Shape.Cookie12Sided
                    title: Translation.tr("Frame rate")
                    subtitle: stats.fpsActive ? Translation.tr("Receiving frames from %1").arg(String(stats.fps.process ?? ""))
                        : !subPageRoot.mango.installed ? Translation.tr("MangoHud is not installed")
                        : !subPageRoot.mango.configured ? Translation.tr("MangoHud is installed, logging is off")
                        : Translation.tr("Ready · start a game below or with MangoHud")

                    StyledText {
                        Layout.fillWidth: true
                        Layout.bottomMargin: 4
                        text: Translation.tr("Linux has no system-wide frame counter. MangoHud runs inside each game and writes its frame times to a log the HUD reads, so a game has to start with it.")
                        wrapMode: Text.WordWrap
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.small
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        SetupStep {
                            number: 1
                            first: true
                            done: subPageRoot.mango.installed
                            title: Translation.tr("Install MangoHud")
                            body: subPageRoot.mango.installed ? Translation.tr("MangoHud is installed.") : Translation.tr("Run this in a terminal, then check again:")
                            command: subPageRoot.mango.installed ? "" : (subPageRoot.mango.installCommand ?? "")
                            secondBody: subPageRoot.anyGameNeedsLayer ? Translation.tr("Flatpak games (Sober, Flatpak Steam…) need MangoHud's Flatpak layer too:") : ""
                            secondCommand: subPageRoot.anyGameNeedsLayer ? (subPageRoot.mango.flatpakInstallCommand ?? "") : ""

                            AppRowButton {
                                visible: !subPageRoot.mango.installed || subPageRoot.anyGameNeedsLayer
                                symbol: "refresh"
                                label: Translation.tr("Check again")
                                onClicked: subPageRoot.refreshExternal()
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
                                    return Translation.tr("Logging is on in %1.").arg(String(subPageRoot.mango.confPath));
                                return Translation.tr("Adds a small marked block to %1 so MangoHud logs frame times for the HUD. Your other MangoHud settings stay as they are.").arg(String(subPageRoot.mango.confPath));
                            }

                            AppRowButton {
                                enabled: !stats.mangoBusy
                                symbol: subPageRoot.mango.configured ? "refresh" : "build"
                                label: subPageRoot.mango.configured ? Translation.tr("Apply again") : Translation.tr("Set up")
                                onClicked: stats.setMangoHudLogging(true)
                            }
                            AppRowButton {
                                visible: subPageRoot.mango.configured
                                enabled: !stats.mangoBusy
                                danger: true
                                symbol: "delete"
                                label: Translation.tr("Remove")
                                onClicked: stats.setMangoHudLogging(false)
                            }
                        }

                        SetupStep {
                            number: 3
                            last: !subPageRoot.hud.showNetwork
                            done: subPageRoot.anyGameEnabled || stats.fpsActive
                            title: Translation.tr("Start your games with MangoHud")
                            body: stats.games.length > 0
                                ? Translation.tr("Turn it on for a game or launcher and the shell wires it in for you: Steam's entry, the Flatpak override for Sober, Prism Launcher's wrapper command. Play opens it with MangoHud right away.")
                                : Translation.tr("No games were found in your app list. Steam games can still use the launch option below; anything else, put mangohud before its command.")
                            command: "mangohud %command%"
                            commandCaption: Translation.tr("Steam launch option, per game")
                        }

                        // Only the Network block needs it, so it shows while that is on
                        SetupStep {
                            visible: subPageRoot.hud.showNetwork
                            number: 4
                            last: true
                            done: subPageRoot.mango.ping ?? true
                            title: Translation.tr("Install ping for the Network block")
                            body: (subPageRoot.mango.ping ?? true) ? Translation.tr("ping is installed.")
                                : Translation.tr("The Network block measures latency with ping. Run this in a terminal, then check again:")
                            command: (subPageRoot.mango.ping ?? true) ? "" : (subPageRoot.mango.pingInstallCommand ?? "")

                            AppRowButton {
                                visible: !(subPageRoot.mango.ping ?? true)
                                symbol: "refresh"
                                label: Translation.tr("Check again")
                                onClicked: subPageRoot.refreshExternal()
                            }
                        }
                    }

                    // The games MangoHud can be wired into
                    ColumnLayout {
                        visible: stats.games.length > 0
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        spacing: 2

                        Repeater {
                            model: stats.games
                            delegate: GameRow {
                                required property var modelData
                                required property int index
                                Layout.fillWidth: true
                                game: modelData
                                first: index === 0
                                last: index === stats.games.length - 1
                            }
                        }
                    }
                }
            }
        }

        // ── 5. Names and the rest ───────────────────────────────────────
        Loader {
            Layout.fillWidth: true
            Layout.topMargin: 4
            asynchronous: true
            sourceComponent: Component {
                ColumnLayout {
                    spacing: 12

                    ContentSection {
                        title: Translation.tr("Names")
                        icon: "title"
                        tooltip: Translation.tr("Leave a name empty to use the detected model.")

                        ConfigRow {
                            uniform: true
                            ConfigTextField {
                                Layout.fillWidth: true
                                text: Translation.tr("Title")
                                icon: "title"
                                placeholderText: Translation.tr("No title")
                                tooltip: Translation.tr("A heading over the HUD, like the device's name.")
                                inputText: subPageRoot.hud.title
                                textField.onEditingFinished: subPageRoot.setOption("title", textField.text)
                            }
                            ConfigTextField {
                                Layout.fillWidth: true
                                text: Translation.tr("Badge")
                                icon: "label"
                                placeholderText: Translation.tr("No badge")
                                tooltip: Translation.tr("A short word in a pill under the HUD, like \"Bench\".")
                                inputText: subPageRoot.hud.footerText
                                textField.onEditingFinished: subPageRoot.setOption("footerText", textField.text)
                            }
                        }
                        ConfigRow {
                            uniform: true
                            ConfigTextField {
                                Layout.fillWidth: true
                                text: Translation.tr("CPU name")
                                icon: "memory"
                                placeholderText: stats.cpuModel || "CPU"
                                inputText: subPageRoot.hud.cpuName
                                textField.onEditingFinished: subPageRoot.setOption("cpuName", textField.text)
                            }
                            ConfigTextField {
                                Layout.fillWidth: true
                                text: Translation.tr("GPU name")
                                icon: "developer_board"
                                placeholderText: stats.selectedGpu?.name ?? "GPU"
                                inputText: subPageRoot.hud.gpuName
                                textField.onEditingFinished: subPageRoot.setOption("gpuName", textField.text)
                            }
                        }
                    }

                    ContentSection {
                        title: Translation.tr("Advanced")
                        icon: "tune"

                        ContentSubsection {
                            title: Translation.tr("HUD refresh")
                            icon: "update"
                            tooltip: Translation.tr("How often the numbers change. Faster costs a little more CPU while the HUD is visible; nothing runs while it is hidden.")

                            ConfigSelectionArray {
                                currentValue: subPageRoot.hud.updateInterval
                                onSelected: newValue => subPageRoot.setOption("updateInterval", newValue)
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
                                    subPageRoot.setOption("mangohudLogInterval", newValue);
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
                                    subPageRoot.setOption("mangohudHideHud", checked);
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
                                onValueChanged: subPageRoot.setOption("hotTemp", value)
                                StyledToolTip {
                                    text: Translation.tr("Temperatures from here up turn red.")
                                }
                            }
                        }

                        ConfigRow {
                            uniform: true

                            ConfigSpinBox {
                                icon: "flag"
                                text: Translation.tr("Target FPS")
                                value: subPageRoot.hud.fpsTarget
                                from: 20
                                to: 540
                                stepSize: 5
                                onValueChanged: subPageRoot.setOption("fpsTarget", value)
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
                                onValueChanged: subPageRoot.setOption("statsWindow", value)
                                StyledToolTip {
                                    text: Translation.tr("How many seconds of frames the average and the lows are computed from.")
                                }
                            }
                        }

                        ConfigTextField {
                            Layout.fillWidth: true
                            text: Translation.tr("Ping target")
                            icon: "network_ping"
                            placeholderText: Translation.tr("Gateway")
                            tooltip: Translation.tr("A host or IP to ping for the Network block, like a game server. Empty pings your router, so nothing leaves your network.")
                            inputText: subPageRoot.hud.pingTarget
                            textField.onEditingFinished: subPageRoot.setOption("pingTarget", textField.text.trim())
                        }

                        NoticeBox {
                            Layout.fillWidth: true
                            materialIcon: "keyboard"
                            text: Translation.tr("Open it from the game overlay (Super+G) and pin it, or bind a key to the \"perfMonitorToggle\" shortcut. From a script: qs -c ii ipc call perfMonitor toggle.")
                        }
                    }
                }
            }
        }
    }

    // ── Components ──────────────────────────────────────────────────────

    // A slab on colLayer1 with a shape icon, a title and a line that says the
    // current value; its content stacks under the header.
    component Pane: Rectangle {
        id: pane
        property string symbol: ""
        property var shape: MaterialShape.Shape.Cookie9Sided
        property string title: ""
        property string subtitle: ""
        default property alias content: paneColumn.data
        readonly property int padding: 16

        radius: Appearance.rounding.verylarge
        color: Appearance.colors.colLayer1
        implicitHeight: paneColumn.implicitHeight + pane.padding * 2

        ColumnLayout {
            id: paneColumn
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: pane.padding
            }
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                Layout.bottomMargin: 2
                spacing: 12

                MaterialShapeWrappedMaterialSymbol {
                    text: pane.symbol
                    iconSize: 22
                    padding: 11
                    fill: 1
                    shape: pane.shape
                    color: Appearance.colors.colPrimaryContainer
                    colSymbol: Appearance.colors.colOnPrimaryContainer
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: pane.title
                        font.family: Appearance.font.family.title
                        font.variableAxes: Appearance.font.variableAxes.titleRounded
                        font.pixelSize: Appearance.font.pixelSize.huge
                        color: Appearance.colors.colOnLayer1
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: pane.subtitle
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }

    // A small caption over a wrapping row of chips.
    component ChipGroup: ColumnLayout {
        id: group
        property string caption: ""
        default property alias chips: chipFlow.data
        Layout.fillWidth: true
        spacing: 6

        StyledText {
            text: group.caption
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.Bold
            color: Appearance.colors.colSubtext
        }
        Flow {
            id: chipFlow
            Layout.fillWidth: true
            spacing: 6
        }
    }

    // One value of a string option; `exclusiveOf` names a bool that, when on,
    // means none of these is the current choice (FPS only over the styles).
    component ChoiceChip: ColorsChip {
        id: choice
        required property string key
        required property var value
        property string exclusiveOf: ""
        chosen: subPageRoot.hud[choice.key] === choice.value
            && (choice.exclusiveOf.length === 0 || !subPageRoot.hud[choice.exclusiveOf])
        onClicked: {
            if (choice.exclusiveOf.length > 0)
                subPageRoot.setOption(choice.exclusiveOf, false);
            subPageRoot.setOption(choice.key, choice.value);
        }
    }

    // A boolean option as a filter chip.
    component ToggleChip: ColorsChip {
        id: toggle
        required property string key
        chosen: subPageRoot.hud[toggle.key] ?? false
        onClicked: subPageRoot.setOption(toggle.key, !toggle.chosen)
    }

    // One block of the HUD: the tile follows the block's switch (primary
    // container and a morphing shape when on), its numbers are chips on it,
    // and the summary says what it currently shows.
    component HudTile: Rectangle {
        id: tile
        required property string key
        property string symbol: ""
        property var shapeOn: MaterialShape.Shape.Cookie9Sided
        property string title: ""
        property string hint: ""
        default property alias chips: tileFlow.data

        readonly property bool checked: subPageRoot.hud[tile.key] ?? false
        readonly property bool engaged: tileHover.hovered
        readonly property color colContent: tile.checked ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer1
        readonly property string summary: {
            if (!tile.checked)
                return Translation.tr("Hidden");
            const names = [];
            for (let i = 0; i < tileFlow.children.length; i++) {
                const chip = tileFlow.children[i];
                if (chip.metricKey !== undefined && chip.chosen)
                    names.push(chip.label);
            }
            return tile.hint.length > 0 && names.length === 0 ? tile.hint
                : names.length > 0 ? names.join(" · ") : Translation.tr("Shown");
        }

        implicitHeight: tileColumn.implicitHeight + 28
        radius: Appearance.rounding.verylarge
        color: tile.checked
            ? (tile.engaged ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colPrimaryContainer)
            : (tile.engaged ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1)
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        HoverHandler {
            id: tileHover
        }
        // Under the content, so the switch and the chips keep their own clicks
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: subPageRoot.setOption(tile.key, !tile.checked)
        }

        ColumnLayout {
            id: tileColumn
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 16
                topMargin: 14
                rightMargin: 14
            }
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                MaterialShapeWrappedMaterialSymbol {
                    text: tile.symbol
                    iconSize: 22
                    padding: 11
                    fill: tile.checked ? 1 : 0
                    shape: tile.checked ? tile.shapeOn : MaterialShape.Shape.Circle
                    color: tile.checked ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
                    colSymbol: tile.checked ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: tile.title
                        font.family: Appearance.font.family.title
                        font.variableAxes: Appearance.font.variableAxes.titleRounded
                        font.pixelSize: Appearance.font.pixelSize.larger
                        color: tile.colContent
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: tile.summary
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: tile.colContent
                        opacity: 0.8
                        elide: Text.ElideRight
                    }
                }
                StyledSwitch {
                    Layout.alignment: Qt.AlignVCenter
                    sizeScale: 0.85
                    checked: tile.checked
                    activeColor: Appearance.colors.colPrimary
                    activeThumbColor: Appearance.colors.colOnPrimary
                    inactiveColor: Appearance.colors.colSurfaceContainerHighest
                    onToggled: subPageRoot.setOption(tile.key, checked)
                }
            }

            Flow {
                id: tileFlow
                Layout.fillWidth: true
                Layout.topMargin: 10
                spacing: 6
                enabled: tile.checked
            }
        }
    }

    // A metric of a tile, chosen = primary on an active tile.
    component MetricChip: ColorsChip {
        id: metric
        required property string key
        readonly property string metricKey: metric.key
        readonly property var ownerTile: metric.parent?.parent?.parent ?? null
        chosen: subPageRoot.hud[metric.key] ?? false
        colContent: metric.ownerTile?.colContent ?? Appearance.colors.colOnSurfaceVariant
        colChosen: (metric.ownerTile?.checked ?? false) ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
        colOnChosen: (metric.ownerTile?.checked ?? false) ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
        onClicked: subPageRoot.setOption(metric.key, !metric.chosen)
    }

    // A game or launcher: its icon, how MangoHud gets in, and the actions.
    component GameRow: Rectangle {
        id: row
        required property var game
        property bool first: false
        property bool last: false

        readonly property bool busy: stats.gamesBusyId === row.game.id
        readonly property string error: stats.gamesErrorId === row.game.id ? stats.gamesError : ""
        readonly property string how: {
            switch (row.game.method) {
            case "steam":
                return Translation.tr("Every Vulkan and Proton game started from Steam");
            case "flatpak":
                return row.game.needsLayer ? Translation.tr("Flatpak · needs MangoHud's Flatpak layer (step 1)")
                    : Translation.tr("Flatpak · turned on with a Flatpak override");
            case "prism":
            case "prism-flatpak":
                return Translation.tr("Minecraft · Prism Launcher's wrapper command");
            case "guide":
                return Translation.tr("Turn on MangoHud in its own settings, per game");
            default:
                return Translation.tr("Its launcher entry starts it through mangohud");
            }
        }

        Layout.fillWidth: true
        implicitHeight: gameRow.implicitHeight + 16
        color: row.game.enabled ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer2
        topLeftRadius: row.first ? Appearance.rounding.large : Appearance.rounding.verysmall
        topRightRadius: row.first ? Appearance.rounding.large : Appearance.rounding.verysmall
        bottomLeftRadius: row.last ? Appearance.rounding.large : Appearance.rounding.verysmall
        bottomRightRadius: row.last ? Appearance.rounding.large : Appearance.rounding.verysmall
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        RowLayout {
            id: gameRow
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                leftMargin: 16
                rightMargin: 12
            }
            spacing: 12

            IconImage {
                implicitSize: 32
                source: Quickshell.iconPath(row.game.icon, "applications-games")
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: row.game.name
                    elide: Text.ElideRight
                    color: row.game.enabled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
                    font {
                        family: Appearance.font.family.title
                        variableAxes: Appearance.font.variableAxes.titleRounded
                        pixelSize: Appearance.font.pixelSize.normal
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    text: row.error === "prism-running" ? Translation.tr("Close Prism Launcher first: it rewrites its settings when it quits.")
                        : row.error.length > 0 ? Translation.tr("That did not work. Check the shell log (qs log -c ii).")
                        : row.how
                    wrapMode: Text.WordWrap
                    color: row.error.length > 0 ? Appearance.colors.colError
                        : row.game.enabled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }
            }
            AppRowButton {
                visible: row.game.method !== "guide"
                enabled: !row.busy
                symbol: row.game.enabled ? "check" : "add"
                label: row.game.enabled ? Translation.tr("FPS on") : Translation.tr("Turn on FPS")
                tooltip: row.game.enabled ? Translation.tr("Turn MangoHud off for this one") : ""
                onClicked: stats.setGameFps(row.game.id, !row.game.enabled)
            }
            AppRowButton {
                enabled: !row.busy
                symbol: "play_arrow"
                label: Translation.tr("Play")
                onClicked: stats.launchGame(row.game.id)
            }
        }
    }

    // Opaque pill on the preview, like the Colors & Themes status chips.
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
