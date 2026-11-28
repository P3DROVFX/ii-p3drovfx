import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../.."
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.settings.configs.colors
import qs.modules.settings.configs.overlays
import qs.services

/**
 * Apps & Overlays. The shell's own apps (Notes, Clock, EasyEffects, Live Draw, App usage,
 * Modes & Routines) as a shelf of app cards — load switch, shortcut, Open — and the
 * on-screen overlays as a grouped list whose rows lead into sub-pages, where the long tail
 * of OSD, keyboard, game overlay and HUD options now lives.
 */
Item {
    id: overlaysConfigRoot

    property alias contentY: page.contentY
    property alias activeSubPage: subPageOverlay.activeSubPage

    function open(url) {
        overlaysConfigRoot.activeSubPage = Qt.resolvedUrl(url);
    }

    readonly property bool modesAvailable: ["ii", "waffle"].includes(PanelFamily.current)

    // Super + Y is bound in the Hyprland config, which the shell's update never touches
    property bool modesKeybindFound: true
    Process {
        running: overlaysConfigRoot.modesAvailable
        command: ["grep", "-rqsF", "quickshell:modesToggle", `${FileUtils.trimFileProtocol(Directories.config)}/hypr`]
        onExited: (code, status) => overlaysConfigRoot.modesKeybindFound = (code === 0)
    }

    ContentPage {
        id: page
        anchors.fill: parent
        forceWidth: false
        opacity: subPageOverlay.slideProgress
        visible: opacity > 0

        // ── intro ──
        ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 4
            spacing: 0

            readonly property int loaded: [shelf.notes, shelf.clock, shelf.easyEffects, shelf.liveDraw, shelf.usage, shelf.modes, shelf.email]
                .filter(card => card.visible && card.checked).length
            readonly property int total: overlaysConfigRoot.modesAvailable ? 7 : 6

            StyledText {
                text: Translation.tr("Apps")
                font.family: Appearance.font.family.title
                font.variableAxes: Appearance.font.variableAxes.titleRounded
                font.pixelSize: Appearance.font.pixelSize.huge + 8
                color: Appearance.colors.colOnLayer0
            }
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("%1 of %2 loaded. An app that is off frees its memory; its shortcut and toggles stop opening it.").arg(parent.loaded).arg(parent.total)
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                wrapMode: Text.WordWrap
            }
        }

        // ── the shelf ──
        Grid {
            id: shelf
            Layout.fillWidth: true
            spacing: 12
            readonly property int count: overlaysConfigRoot.modesAvailable ? 7 : 6
            readonly property int maxCols: Math.max(1, Math.floor((width + spacing) / (290 + spacing)))
            columns: Math.min(maxCols, 3)
            readonly property real cardWidth: (width - spacing * (columns - 1)) / columns
            readonly property int cardHeight: 240

            property alias notes: notesCard
            property alias clock: clockCard
            property alias easyEffects: eeCard
            property alias liveDraw: drawCard
            property alias usage: usageCard
            property alias modes: modesCard
            property alias email: emailCard

            AppCard {
                id: notesCard
                width: shelf.cardWidth
                height: shelf.cardHeight
                accent: "primary"
                symbol: "note_stack"
                shape: MaterialShape.Shape.Cookie9Sided
                title: Translation.tr("Notes")
                summary: Translation.tr("Markdown notes, drawings and cloud backup. Editor and paper options are inside the app.")
                keys: ["Super", "Alt", "N"]
                checked: Config.options.notes?.enable ?? true
                onToggled: value => { if (Config.ready && Config.options.notes) Config.options.notes.enable = value; }
                onOpenRequested: GlobalStates.openNotes()
            }

            AppCard {
                id: clockCard
                width: shelf.cardWidth
                height: shelf.cardHeight
                accent: "secondary"
                symbol: "alarm"
                shape: MaterialShape.Shape.Sunny
                title: Translation.tr("Clock")
                summary: Translation.tr("Alarms, world clock, timers, stopwatch and pomodoro. They keep running when it is closed.")
                keys: ["Super", "Alt", "T"]
                checked: Config.options.clockApp?.enable ?? true
                onToggled: value => { if (Config.ready && Config.options.clockApp) Config.options.clockApp.enable = value; }
                onOpenRequested: GlobalStates.openClockApp("")
            }

            AppCard {
                id: eeCard
                width: shelf.cardWidth
                height: shelf.cardHeight
                accent: "tertiary"
                symbol: "graphic_eq"
                shape: MaterialShape.Shape.Clover4Leaf
                title: Translation.tr("EasyEffects")
                summary: EasyEffects.available
                    ? Translation.tr("Presets, the effect chain and per-device defaults in one window.")
                    : Translation.tr("EasyEffects isn't installed.")
                keys: ["Super", "Ctrl", "E"]
                canOpen: EasyEffects.available
                checked: Config.options.easyEffects?.appEnable ?? true
                onToggled: value => { if (Config.ready && Config.options.easyEffects) Config.options.easyEffects.appEnable = value; }
                onOpenRequested: GlobalStates.openEasyEffectsApp("")

                ColorsChip {
                    visible: EasyEffects.bothInstalled
                    symbol: "deployed_code"
                    label: EasyEffects.preferFlatpak ? Translation.tr("Flatpak %1").arg(EasyEffects.flatpakMajor) : Translation.tr("Package %1").arg(EasyEffects.nativeMajor)
                    chosen: EasyEffects.preferFlatpak
                    colContent: eeCard.colOnPlate
                    colChosen: eeCard.colStrong
                    colOnChosen: eeCard.colOnStrong
                    onClicked: EasyEffects.setPreferFlatpak(!EasyEffects.preferFlatpak)
                    StyledToolTip {
                        text: Translation.tr("Both builds are installed. Switching restarts EasyEffects if it is running.")
                    }
                }
            }

            AppCard {
                id: drawCard
                width: shelf.cardWidth
                height: shelf.cardHeight
                accent: "primary"
                symbol: "draw"
                shape: MaterialShape.Shape.Flower
                title: Translation.tr("Live Draw")
                summary: Translation.tr("Annotate the screen over every app; each drawing stays on its workspace. Pen options are in its toolbar.")
                keys: ["Super", "Alt", "D"]
                checked: Config.options.liveDraw?.enable ?? true
                onToggled: value => {
                    if (!Config.ready || !Config.options.liveDraw || Config.options.liveDraw.enable === value)
                        return;
                    if (!value) {
                        LiveDraw.close();
                        LiveDraw.clearAll();
                    }
                    Config.options.liveDraw.enable = value;
                }
                onOpenRequested: {
                    GlobalStates.settingsOpen = false;
                    LiveDraw.open();
                }
            }

            AppCard {
                id: usageCard
                width: shelf.cardWidth
                height: shelf.cardHeight
                accent: "secondary"
                symbol: "bar_chart"
                shape: MaterialShape.Shape.Cookie12Sided
                title: Translation.tr("App usage")
                summary: Config.options.appStats.enable
                    ? Translation.tr("Recording screen time, network and battery. Views and retention live in the app.")
                    : Translation.tr("Not recording. The history already kept stays.")
                keys: ["Super", "U"]
                checked: Config.options.appStats.overlayEnabled
                onToggled: value => Config.options.appStats.overlayEnabled = value
                onOpenRequested: GlobalStates.openUsageApp("")

                ColorsChip {
                    symbol: "monitoring"
                    label: Translation.tr("Collect stats")
                    chosen: Config.options.appStats.enable
                    colContent: usageCard.colOnPlate
                    colChosen: usageCard.colStrong
                    colOnChosen: usageCard.colOnStrong
                    onClicked: Config.options.appStats.enable = !Config.options.appStats.enable
                    StyledToolTip {
                        text: Translation.tr("Turning this off stops the sampler but keeps the history already recorded")
                    }
                }
            }

            AppCard {
                id: modesCard
                visible: overlaysConfigRoot.modesAvailable
                width: shelf.cardWidth
                height: shelf.cardHeight
                accent: "tertiary"
                symbol: "tune"
                shape: MaterialShape.Shape.SoftBurst
                title: Translation.tr("Modes & Routines")
                summary: {
                    const line = Translation.tr("%1 mode(s) and %2 routine(s).").arg(Modes.modes.length).arg(Modes.routines.length);
                    return Modes.active
                        ? line + " " + Translation.tr("%1 is on right now.").arg(Modes.activeMode?.name ?? "")
                        : line + " " + Translation.tr("Nothing is on right now.");
                }
                warning: checked && !overlaysConfigRoot.modesKeybindFound
                    ? Translation.tr("Hyprland has no binding for Super + Y. Re-run the setup with --hypr or bind quickshell:modesToggle.")
                    : ""
                keys: ["Super", "Y"]
                checked: Config.options.modes.overlayEnabled
                onToggled: value => Config.options.modes.overlayEnabled = value
                onOpenRequested: GlobalStates.openModesApp("")

                ColorsChip {
                    symbol: "autoplay"
                    label: Translation.tr("Automatic starts")
                    chosen: Config.options.modes.enable
                    colContent: modesCard.colOnPlate
                    colChosen: modesCard.colStrong
                    colOnChosen: modesCard.colOnStrong
                    onClicked: Config.options.modes.enable = !Config.options.modes.enable
                    StyledToolTip {
                        text: Translation.tr("Off: conditions are ignored everywhere. Modes and routines still work when you start them yourself")
                    }
                }
            }

            AppCard {
                id: emailCard
                width: shelf.cardWidth
                height: shelf.cardHeight
                accent: "primary"
                symbol: "mail"
                shape: MaterialShape.Shape.Flower
                title: Translation.tr("Email")
                summary: EmailService.authenticated
                    ? Translation.tr("Standalone Gmail client (%1). Runs in its own process and frees all RAM on close.").arg(EmailService.userEmail)
                    : Translation.tr("Standalone Gmail client. Runs in its own process and frees all RAM on close.")
                keys: {
                    const bind = HyprlandBinds.effective.find(row => row.kind === "bind"
                        && String(row.action ?? "").includes("quickshell:emailOpen"));
                    if (!bind)
                        return [];
                    const mods = Array.from(bind.mods ?? []).map(m => m.charAt(0) + m.slice(1).toLowerCase());
                    return mods.concat([String(bind.key ?? "").toUpperCase()]).filter(Boolean);
                }
                checked: Config.options.emailApp?.enable ?? true
                onToggled: value => {
                    if (Config.ready && Config.options.emailApp)
                        Config.options.emailApp.enable = value;
                }
                onOpenRequested: GlobalStates.openEmailApp("")

                ColorsChip {
                    readonly property bool isFloating: Config.options.emailApp?.openFloating ?? true
                    symbol: isFloating ? "picture_in_picture_alt" : "grid_view"
                    label: isFloating ? Translation.tr("Floating") : Translation.tr("Tiling")
                    chosen: isFloating
                    colContent: emailCard.colOnPlate
                    colChosen: emailCard.colStrong
                    colOnChosen: emailCard.colOnStrong
                    onClicked: {
                        if (Config.ready && Config.options.emailApp)
                            Config.options.emailApp.openFloating = !isFloating;
                    }
                    StyledToolTip {
                        text: Translation.tr("Toggle whether Email opens as a centered floating window (Cheatsheet size) or tiled.")
                    }
                }

                ColorsChip {
                    readonly property bool hasShortcut: emailCard.keys.length > 0
                    symbol: "keyboard"
                    label: hasShortcut ? Translation.tr("Shortcut") : Translation.tr("Set shortcut")
                    chosen: hasShortcut
                    colContent: emailCard.colOnPlate
                    colChosen: emailCard.colStrong
                    colOnChosen: emailCard.colOnStrong
                    onClicked: {
                        HyprlandGui.openTab("shortcuts");
                        GlobalStates.openSettingsPage("hyprland");
                    }
                    StyledToolTip {
                        text: Translation.tr("Open Hyprland Shortcuts to enable or edit the Email keybind.")
                    }
                }
            }

            AppCard {
                id: calendarCard
                width: shelf.cardWidth
                height: shelf.cardHeight
                accent: "secondary"
                symbol: "calendar_month"
                shape: MaterialShape.Shape.Cookie12Sided
                title: Translation.tr("Calendar")
                summary: CalendarService.khalAvailable
                    ? Translation.tr("Standalone calendar app (%1 calendars). Runs in its own process and frees all RAM on close.").arg(CalendarService.calendars.length)
                    : Translation.tr("Standalone calendar app. Runs in its own process and frees all RAM on close.")
                keys: {
                    const bind = HyprlandBinds.effective.find(row => row.kind === "bind"
                        && String(row.action ?? "").includes("quickshell:calendarOpen"));
                    if (!bind)
                        return [];
                    const mods = Array.from(bind.mods ?? []).map(m => m.charAt(0) + m.slice(1).toLowerCase());
                    return mods.concat([String(bind.key ?? "").toUpperCase()]).filter(Boolean);
                }
                checked: Config.options.calendarApp?.enable ?? true
                onToggled: value => {
                    if (Config.ready && Config.options.calendarApp)
                        Config.options.calendarApp.enable = value;
                }
                onOpenRequested: GlobalStates.openCalendarApp("")

                ColorsChip {
                    readonly property bool isFloating: Config.options.calendarApp?.openFloating ?? true
                    symbol: isFloating ? "picture_in_picture_alt" : "grid_view"
                    label: isFloating ? Translation.tr("Floating") : Translation.tr("Tiling")
                    chosen: isFloating
                    colContent: calendarCard.colOnPlate
                    colChosen: calendarCard.colStrong
                    colOnChosen: calendarCard.colOnStrong
                    onClicked: {
                        if (Config.ready && Config.options.calendarApp)
                            Config.options.calendarApp.openFloating = !isFloating;
                    }
                    StyledToolTip {
                        text: Translation.tr("Toggle whether Calendar opens as a centered floating window (Cheatsheet size) or tiled.")
                    }
                }

                ColorsChip {
                    readonly property bool hasShortcut: calendarCard.keys.length > 0
                    symbol: "keyboard"
                    label: hasShortcut ? Translation.tr("Shortcut") : Translation.tr("Set shortcut")
                    chosen: hasShortcut
                    colContent: calendarCard.colOnPlate
                    colChosen: calendarCard.colStrong
                    colOnChosen: calendarCard.colOnStrong
                    onClicked: {
                        HyprlandGui.openTab("shortcuts");
                        GlobalStates.openSettingsPage("hyprland");
                    }
                    StyledToolTip {
                        text: Translation.tr("Open Hyprland Shortcuts to enable or edit the Calendar keybind.")
                    }
                }
            }

            AppCard {
                id: galleryCard
                width: shelf.cardWidth
                height: shelf.cardHeight
                accent: "tertiary"
                symbol: "photo_library"
                shape: MaterialShape.Shape.Cookie9Sided
                title: Translation.tr("Gallery")
                summary: Translation.tr("Standalone photo & video gallery with Albums and ii tools Phone Gallery. Runs in its own process and frees all RAM on close.")
                keys: {
                    const bind = HyprlandBinds.effective.find(row => row.kind === "bind"
                        && String(row.action ?? "").includes("quickshell:galleryOpen"));
                    if (!bind)
                        return [];
                    const mods = Array.from(bind.mods ?? []).map(m => m.charAt(0) + m.slice(1).toLowerCase());
                    return mods.concat([String(bind.key ?? "").toUpperCase()]).filter(Boolean);
                }
                checked: Config.options.galleryApp?.enable ?? true
                onToggled: value => {
                    if (Config.ready && Config.options.galleryApp)
                        Config.options.galleryApp.enable = value;
                }
                onOpenRequested: GlobalStates.openGalleryApp("")

                ColorsChip {
                    readonly property bool isFloating: Config.options.galleryApp?.openFloating ?? true
                    symbol: isFloating ? "picture_in_picture_alt" : "grid_view"
                    label: isFloating ? Translation.tr("Floating") : Translation.tr("Tiling")
                    chosen: isFloating
                    colContent: galleryCard.colOnPlate
                    colChosen: galleryCard.colStrong
                    colOnChosen: galleryCard.colOnStrong
                    onClicked: {
                        if (Config.ready && Config.options.galleryApp)
                            Config.options.galleryApp.openFloating = !isFloating;
                    }
                    StyledToolTip {
                        text: Translation.tr("Toggle whether Gallery opens as a centered floating window (1240×780) or tiled.")
                    }
                }

                ColorsChip {
                    readonly property bool hasShortcut: galleryCard.keys.length > 0
                    symbol: "keyboard"
                    label: hasShortcut ? Translation.tr("Shortcut") : Translation.tr("Set shortcut")
                    chosen: hasShortcut
                    colContent: galleryCard.colOnPlate
                    colChosen: galleryCard.colStrong
                    colOnChosen: galleryCard.colOnStrong
                    onClicked: {
                        HyprlandGui.openTab("shortcuts");
                        GlobalStates.openSettingsPage("hyprland");
                    }
                    StyledToolTip {
                        text: Translation.tr("Open Hyprland Shortcuts to enable or edit the Gallery keybind.")
                    }
                }
            }
        }

        // ── on screen ──
        ColumnLayout {
            Layout.fillWidth: true
            Layout.topMargin: 20
            Layout.leftMargin: 4
            spacing: 0
            StyledText {
                text: Translation.tr("On screen")
                font.family: Appearance.font.family.title
                font.variableAxes: Appearance.font.variableAxes.titleRounded
                font.pixelSize: Appearance.font.pixelSize.huge + 8
                color: Appearance.colors.colOnLayer0
            }
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("What draws over your apps and games. Each one opens into its own options.")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                wrapMode: Text.WordWrap
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 3

            OverlayNavRow {
                first: true
                symbol: "desktop_windows"
                shape: MaterialShape.Shape.Cookie7Sided
                title: Translation.tr("On-screen display")
                summary: {
                    if (Config.options.sidebar.sidebarStyle === "connect")
                        return Translation.tr("Connect mode draws its own OSD");
                    if (!Config.options.osd.enable)
                        return Translation.tr("Off");
                    const styles = { "default": Translation.tr("Android"), "minimalist": Translation.tr("Minimal"),
                                     "material": Translation.tr("Material"), "tuner": Translation.tr("Tuner") };
                    return Translation.tr("%1 style · %2 s").arg(styles[Config.options.osd.style ?? "default"] ?? "").arg(((Config.options.osd.timeout ?? 3000) / 1000).toFixed(1));
                }
                hasSwitch: true
                checked: Config.options.osd.enable
                onToggled: value => Config.options.osd.enable = value
                onOpenRequested: overlaysConfigRoot.open("overlays/OsdConfig.qml")
            }

            OverlayNavRow {
                symbol: "keyboard"
                shape: MaterialShape.Shape.Pill
                title: Translation.tr("On-screen keyboard")
                summary: {
                    const style = (Config.options.osk.style ?? "deck") === "deck" ? Translation.tr("Deck") : Translation.tr("Classic");
                    const auto = Config.options.osk.autoShow.enable ? Translation.tr("shows on touch") : Translation.tr("Super + K");
                    return `${style} · ${auto}`;
                }
                hasSwitch: true
                checked: GlobalStates.oskOpen
                onToggled: value => GlobalStates.oskOpen = value
                onOpenRequested: overlaysConfigRoot.open("overlays/KeyboardConfig.qml")
            }

            OverlayNavRow {
                symbol: "sports_esports"
                shape: MaterialShape.Shape.Clover4Leaf
                title: Translation.tr("Game overlay")
                summary: Translation.tr("Crosshair, media, notes, Discord voice and floating image")
                onOpenRequested: overlaysConfigRoot.open("widgets/GameOverlayConfig.qml")
            }

            OverlayNavRow {
                symbol: "auto_awesome"
                shape: MaterialShape.Shape.Sunny
                title: Translation.tr("Wallpaper upscaling")
                summary: Config.options.background.upscaylPrompt
                    ? Translation.tr("Offers Upscayl when a wallpaper is smaller than your screen")
                    : Translation.tr("Off: low-resolution wallpapers are applied without asking")
                hasOpen: false
                hasSwitch: true
                checked: Config.options.background.upscaylPrompt
                onToggled: value => Config.options.background.upscaylPrompt = value
            }

            OverlayNavRow {
                last: true
                symbol: "speed"
                shape: MaterialShape.Shape.SoftBurst
                title: Translation.tr("Performance HUD")
                summary: Translation.tr("FPS, 1% low, CPU, GPU, RAM, VRAM and battery over your games")
                onOpenRequested: overlaysConfigRoot.open("widgets/PerfMonitorConfig.qml")
            }
        }
    }

    ConfigSubPageHost {
        id: subPageOverlay
        anchors.fill: parent
        z: 10
    }
}
