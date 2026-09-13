import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.modes

/**
 * Settings for Modes & Routines. The definitions themselves are edited in
 * the manager (Super + Y); this page holds what sits around them: whether
 * automatic starts happen at all, where the active mode shows, how games
 * are recognised, and the stored data.
 */
ContentPage {
    id: page
    forceWidth: false

    readonly property var opts: Config.options.modes

    // The shortcut is bound in the Hyprland config, which the shell's own
    // update never touches — so it can be missing on an otherwise current
    // install and the overlay simply never opens.
    property bool keybindChecked: false
    property bool keybindFound: true
    property string seededText: ""

    readonly property var barEntry: page.findBarEntry()
    readonly property bool barVisible: (page.barEntry && page.barEntry.entry && page.barEntry.entry.visible !== undefined) ? page.barEntry.entry.visible : false

    function findBarEntry() {
        const layouts = Config.options.bar.layouts;
        for (const section of ["left", "center", "right"]) {
            const list = Array.from(layouts[section] ?? []);
            const index = list.findIndex(e => e && e.id === "mode_indicator");
            if (index !== -1)
                return { section: section, index: index, entry: list[index] };
        }
        return null;
    }

    // The layout lists are stored, not derived: the whole array is rewritten
    // so the JsonAdapter sees the change.
    function setBarVisible(on) {
        const found = page.findBarEntry();
        const section = (found && found.section) ? found.section : "left";
        const list = Array.from(Config.options.bar.layouts[section] ?? []).map(e => Object.assign({}, e));
        if (found) {
            list[found.index].visible = on;
        } else {
            const after = list.findIndex(e => e && e.id === "record_indicator");
            list.splice(after === -1 ? list.length : after + 1, 0, { centered: false, id: "mode_indicator", visible: on });
        }
        Config.options.bar.layouts[section] = list;
    }

    function windowSuggestions() {
        const seen = {};
        const out = [];
        for (const w of Array.from(HyprlandData.windowList ?? [])) {
            const cls = String(w.initialClass || w["class"] || "");
            if (!cls.length || seen[cls])
                continue;
            seen[cls] = true;
            out.push({ label: String(w.title || cls).slice(0, 40), value: cls });
        }
        return out;
    }

    Process {
        id: keybindProbe
        running: true
        // `hyprctl binds` shows "__lua" for every bind under the Lua config,
        // so the config text is read instead; -s keeps a missing dir quiet.
        command: ["grep", "-rqsF", "quickshell:modesToggle", `${FileUtils.trimFileProtocol(Directories.config)}/hypr`]
        onExited: (code, status) => {
            page.keybindFound = (code === 0);
            page.keybindChecked = true;
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 2

        WarningBox {
            Layout.fillWidth: true
            visible: page.opts.overlayEnabled && page.keybindChecked && !page.keybindFound
            materialIcon: "keyboard_off"
            text: Translation.tr("Hyprland has no binding for the manager, so Super + Y does nothing. "
                + "Re-run the setup script with --hypr to install the Hyprland config, "
                + "or bind quickshell:modesToggle yourself.")
        }

        KeyboardShortcutBox {
            Layout.fillWidth: true
            visible: page.opts.overlayEnabled
            text: Translation.tr("Open the Modes & Routines manager")
            keys: ["Super", "Y"]
        }

        NoticeBox {
            Layout.fillWidth: true
            materialIcon: "tune"
            text: {
                const modes = Modes.modes.length;
                const routines = Modes.routines.length;
                const line = Translation.tr("%1 mode(s) and %2 routine(s) set up.").arg(modes).arg(routines);
                if (Modes.active)
                    return line + " " + Translation.tr("%1 is on right now.").arg((Modes.activeMode && Modes.activeMode.name) ? Modes.activeMode.name : "");
                return line + " " + Translation.tr("Nothing is on right now.");
            }

            RippleButton {
                id: openButton
                implicitHeight: 34
                horizontalPadding: 16
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                colRipple: Appearance.colors.colPrimaryActive
                enabled: page.opts.overlayEnabled
                opacity: enabled ? 1 : 0.5
                onClicked: GlobalStates.modesOpen = true

                contentItem: StyledText {
                    text: Translation.tr("Open the manager")
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    color: Appearance.colors.colOnPrimary
                }
            }
        }
    }

    ContentSection {
        title: Translation.tr("General")
        icon: "tune"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            ConfigSwitch {
                buttonIcon: "autoplay"
                text: Translation.tr("Start and end things automatically")
                checked: page.opts.enable
                onCheckedChanged: {
                    Config.options.modes.enable = checked;
                }

                StyledToolTip {
                    text: Translation.tr("Off: conditions are ignored everywhere. Modes and routines still work "
                        + "when you start them yourself, and whatever is on stays on")
                }
            }

            ConfigSwitch {
                buttonIcon: "dashboard"
                text: Translation.tr("Load the manager overlay")
                checked: page.opts.overlayEnabled
                onCheckedChanged: {
                    Config.options.modes.overlayEnabled = checked;
                }

                StyledToolTip {
                    text: Translation.tr("Super + Y, the bar pill and the sidebar toggle all open it. "
                        + "Off saves a little memory; the engine keeps running")
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Presets")
            icon: "inventory_2"
            Layout.fillWidth: true

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                text: Translation.tr("The built-in modes (Sleep, Work, Focus, Gaming, Theater, Presentation, Relax) are "
                    + "ordinary entries once added: edit or delete them freely. This puts back any you removed, "
                    + "without touching the ones still there.")
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                RippleButton {
                    implicitHeight: 34
                    horizontalPadding: 16
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colLayer2
                    buttonText: Translation.tr("Restore missing presets")
                    onClicked: {
                        const added = Modes.seedPresets();
                        page.seededText = added.length === 0 ? Translation.tr("All presets are already there")
                            : Translation.tr("Added: %1").arg(added.map(id => {
                                const m = Modes.modeById(id);
                                return (m && m.name) ? m.name : id;
                            }).join(", "));
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: page.seededText.length > 0
                    text: page.seededText
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }

    ContentSection {
        title: Translation.tr("Where the active mode shows")
        icon: "campaign"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            ConfigSwitch {
                buttonIcon: "space_bar"
                text: Translation.tr("Pill in the bar")
                checked: page.barVisible
                onCheckedChanged: {
                    if (checked !== page.barVisible)
                        page.setBarVisible(checked);
                }

                StyledToolTip {
                    text: Translation.tr("The same widget as in the bar layout editor: takes no room while nothing is on. "
                        + "Left-click opens the manager, right-click ends the mode")
                }
            }

            ConfigSwitch {
                buttonIcon: "lock"
                text: Translation.tr("Pill on the lock screen")
                checked: page.opts.lockPill
                onCheckedChanged: {
                    Config.options.modes.lockPill = checked;
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("When a mode starts or ends")
            icon: "notifications_active"
            Layout.fillWidth: true

            ConfigSelectionArray {
                currentValue: page.opts.flash
                onSelected: newValue => {
                    Config.options.modes.flash = newValue;
                }
                options: [
                    {
                        "displayName": Translation.tr("Brief banner"),
                        "value": "auto"
                    },
                    {
                        "displayName": Translation.tr("Nothing"),
                        "value": "off"
                    }
                ]
            }

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                text: Config.options.bar.floatingNotch.enable || Config.options.bar.floatingNotch.centerInBar
                    ? Translation.tr("Drawn by the dynamic island for three seconds. Each mode and routine "
                        + "chooses its own start and end banner.")
                    : Translation.tr("A small top-centre pill for three seconds; the dynamic island takes over "
                        + "when it is enabled. Each mode and routine chooses its own start and end banner.")
            }
        }
    }

    ContentSection {
        title: Translation.tr("Automatic ends")
        icon: "timer"

        ConfigSpinBox {
            icon: "hourglass_bottom"
            text: Translation.tr("Grace period (seconds)")
            value: page.opts.graceSec
            from: 0
            to: 600
            stepSize: 5
            onValueChanged: {
                Config.options.modes.graceSec = value;
            }

            StyledToolTip {
                text: Translation.tr("How long a mode's conditions must stay false before it ends on its own, "
                    + "so a quick workspace switch or a brief alt-tab does not flap it")
            }
        }
    }

    ContentSection {
        title: Translation.tr("Game detection")
        icon: "sports_esports"
        tooltip: Translation.tr("Feeds the \"A game is running / focused\" condition")

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            ConfigSwitch {
                buttonIcon: "rocket_launch"
                text: Translation.tr("Windows from game launchers")
                checked: page.opts.game.useLauncherClasses
                onCheckedChanged: {
                    Config.options.modes.game.useLauncherClasses = checked;
                }

                StyledToolTip {
                    text: Translation.tr("Steam, Heroic, Lutris, Bottles, Prism Launcher and fullscreen Windows executables")
                }
            }

            ConfigSwitch {
                buttonIcon: "category"
                text: Translation.tr("Apps filed under Games")
                checked: page.opts.game.useDesktopCategory
                onCheckedChanged: {
                    Config.options.modes.game.useDesktopCategory = checked;
                }

                StyledToolTip {
                    text: Translation.tr("Any window whose desktop entry has the Game category")
                }
            }

            ConfigSwitch {
                buttonIcon: "memory"
                text: Translation.tr("Fullscreen window keeping the GPU busy")
                checked: page.opts.game.useGpuHeuristic
                onCheckedChanged: {
                    Config.options.modes.game.useGpuHeuristic = checked;
                }

                StyledToolTip {
                    text: Translation.tr("Catches games nothing else recognises. Also catches a fullscreen video "
                        + "that decodes on the GPU — raise the threshold if that happens")
                }
            }

            ConfigSpinBox {
                icon: "speed"
                text: Translation.tr("GPU above (%)")
                enabled: page.opts.game.useGpuHeuristic
                opacity: enabled ? 1 : 0.5
                value: page.opts.game.gpuThreshold
                from: 10
                to: 100
                stepSize: 5
                onValueChanged: {
                    Config.options.modes.game.gpuThreshold = value;
                }
            }

            ConfigSpinBox {
                icon: "timelapse"
                text: Translation.tr("For at least (seconds)")
                enabled: page.opts.game.useGpuHeuristic
                opacity: enabled ? 1 : 0.5
                value: page.opts.game.holdSec
                from: 5
                to: 300
                stepSize: 5
                onValueChanged: {
                    Config.options.modes.game.holdSec = value;
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Always a game")
            icon: "playlist_add"
            Layout.fillWidth: true

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                text: Translation.tr("Window classes treated as games no matter what. Pick picks from the windows open now.")
            }

            ChipInput {
                Layout.fillWidth: true
                values: page.opts.game.extraClasses
                placeholder: Translation.tr("Window class")
                suggestions: page.windowSuggestions()
                onChanged: list => Config.options.modes.game.extraClasses = list
            }

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: GameDetector.gameRunning ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                text: GameDetector.gameRunning
                    ? Translation.tr("Detected now: %1").arg(GameDetector.reason)
                    : Translation.tr("No game detected right now.")
            }
        }
    }

    ContentSection {
        title: Translation.tr("Data")
        icon: "database"

        ContentSubsection {
            title: Translation.tr("Activity")
            icon: "history"
            Layout.fillWidth: true

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                text: {
                    const n = Modes.history.length;
                    const count = n === 1 ? Translation.tr("1 entry") : Translation.tr("%1 entries").arg(n);
                    return Translation.tr("%1 in the Activity tab. The newest 200 are kept.").arg(count);
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                RippleButton {
                    implicitHeight: 34
                    horizontalPadding: 16
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colLayer2
                    buttonText: Translation.tr("Clear activity")
                    enabled: Modes.history.length > 0
                    opacity: enabled ? 1 : 0.5
                    onClicked: clearDialog.show = true
                }

                Item {
                    Layout.fillWidth: true
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Where it lives")
            icon: "folder_open"
            Layout.fillWidth: true

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                text: Translation.tr("Modes and routines are saved in config.json under \"modes\", so a config "
                    + "backup carries them. What is running and the activity log are state, kept separately "
                    + "and restored after a restart.")
            }
        }
    }

    WindowDialog {
        id: clearDialog
        parent: page.parent ? page.parent : page
        anchors.fill: parent
        show: false
        backgroundWidth: 360
        onDismiss: show = false
        z: 100000

        WindowDialogTitle {
            text: Translation.tr("Clear the activity log?")
        }

        WindowDialogParagraph {
            text: Translation.tr("Every entry in the Activity tab is forgotten. Modes and routines are not touched.")
        }

        WindowDialogButtonRow {
            DialogButton {
                buttonText: Translation.tr("Cancel")
                onClicked: clearDialog.show = false
            }
            DialogButton {
                buttonText: Translation.tr("Clear")
                onClicked: {
                    Modes.clearHistory();
                    clearDialog.show = false;
                }
            }
        }
    }
}
