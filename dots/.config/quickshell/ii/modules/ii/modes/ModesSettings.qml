pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * The manager's own settings, behind the gear beside its close button: presets,
 * where the active mode shows, automatic ends, game detection and the stored
 * data. Automatic starts and loading the manager stay in Settings → Modes & Routines.
 */
AppSettingsPage {
    id: root

    readonly property var opts: Config.options.modes
    property string seededText: ""
    property bool confirmClear: false

    readonly property var barEntry: root.findBarEntry()
    readonly property bool barVisible: (root.barEntry && root.barEntry.entry && root.barEntry.entry.visible !== undefined) ? root.barEntry.entry.visible : false

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
        const found = root.findBarEntry();
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

    title: Translation.tr("Modes & Routines settings")
    subtitle: Translation.tr("Where modes show, automatic ends and game detection")

    // ══ Primary column ══

    AppSettingsSection {
        title: Translation.tr("Where the active mode shows")
        symbol: "campaign"

        AppToggleRow {
            symbol: "space_bar"
            title: Translation.tr("Pill in the bar")
            help: Translation.tr("The same widget as in the bar layout editor: takes no room while nothing is on. "
                + "Left-click opens the manager, right-click ends the mode")
            checked: root.barVisible
            onToggled: value => {
                if (value !== root.barVisible)
                    root.setBarVisible(value);
            }
        }
        AppToggleRow {
            symbol: "lock"
            title: Translation.tr("Pill on the lock screen")
            checked: root.opts.lockPill
            onToggled: value => root.opts.lockPill = value
        }
        AppChoiceRow {
            symbol: "notifications_active"
            title: Translation.tr("When a mode starts or ends")
            description: Config.options.bar.floatingNotch.enable || Config.options.bar.floatingNotch.centerInBar
                ? Translation.tr("Drawn by the dynamic island for three seconds. Each mode and routine "
                    + "chooses its own start and end banner.")
                : Translation.tr("A small top-centre pill for three seconds; the dynamic island takes over "
                    + "when it is enabled. Each mode and routine chooses its own start and end banner.")
            currentValue: root.opts.flash
            onSelected: value => root.opts.flash = value
            options: [
                { "label": Translation.tr("Brief banner"), "value": "auto" },
                { "label": Translation.tr("Nothing"), "value": "off" }
            ]
        }
    }

    AppSettingsSection {
        title: Translation.tr("Automatic ends")
        symbol: "timer"

        AppStepperRow {
            symbol: "hourglass_bottom"
            title: Translation.tr("Grace period (seconds)")
            help: Translation.tr("How long an app, player or device condition must stay false before its "
                + "mode ends on its own, so an app restart or a track change does not flap it. "
                + "Schedules, battery, lid and the like end a mode at once")
            value: root.opts.graceSec
            from: 0
            to: 600
            stepSize: 5
            onMoved: value => root.opts.graceSec = value
        }
    }

    AppSettingsSection {
        title: Translation.tr("Presets")
        symbol: "inventory_2"

        AppSettingRow {
            symbol: "restore"
            title: Translation.tr("Restore missing presets")
            description: root.seededText.length > 0 ? root.seededText
                : Translation.tr("The built-in modes (Sleep, Work, Focus, Gaming, Theater, Presentation, Relax) are "
                    + "ordinary entries once added: edit or delete them freely. This puts back any you removed, "
                    + "without touching the ones still there.")

            AppRowButton {
                symbol: "restore"
                label: Translation.tr("Restore")
                onClicked: {
                    const added = Modes.seedPresets();
                    root.seededText = added.length === 0 ? Translation.tr("All presets are already there")
                        : Translation.tr("Added: %1").arg(added.map(id => {
                            const m = Modes.modeById(id);
                            return (m && m.name) ? m.name : id;
                        }).join(", "));
                }
            }
        }
    }

    AppSettingsSection {
        title: Translation.tr("Data")
        symbol: "database"

        AppSettingRow {
            symbol: "history"
            title: Translation.tr("Activity")
            description: {
                if (root.confirmClear)
                    return Translation.tr("Every entry in the Activity tab is forgotten. Modes and routines are not touched.");
                const n = Modes.history.length;
                const count = n === 1 ? Translation.tr("1 entry") : Translation.tr("%1 entries").arg(n);
                return Translation.tr("%1 in the Activity tab. The newest 200 are kept.").arg(count);
            }

            // Clearing is confirmed in place rather than in a dialog over the overlay.
            AppRowButton {
                visible: !root.confirmClear
                symbol: "delete_sweep"
                label: Translation.tr("Clear activity")
                danger: true
                enabled: Modes.history.length > 0
                onClicked: root.confirmClear = true
            }
            AppRowButton {
                visible: root.confirmClear
                label: Translation.tr("Cancel")
                onClicked: root.confirmClear = false
            }
            AppRowButton {
                visible: root.confirmClear
                symbol: "delete_sweep"
                label: Translation.tr("Clear")
                danger: true
                filled: true
                onClicked: {
                    Modes.clearHistory();
                    root.confirmClear = false;
                }
            }
        }
        AppSettingRow {
            symbol: "folder_open"
            title: Translation.tr("Where it lives")
            description: Translation.tr("Modes and routines are saved in config.json under \"modes\", so a config "
                + "backup carries them. What is running and the activity log are state, kept separately "
                + "and restored after a restart.")
        }
    }

    // ══ Secondary column ══

    secondary: AppSettingsSection {
        title: Translation.tr("Game detection")
        symbol: "sports_esports"
        description: Translation.tr("Feeds the \"A game is running / focused\" condition")

        AppToggleRow {
            symbol: "rocket_launch"
            title: Translation.tr("Windows from game launchers")
            description: Translation.tr("Steam, Heroic, Lutris, Bottles, Prism Launcher and fullscreen Windows executables")
            checked: root.opts.game.useLauncherClasses
            onToggled: value => root.opts.game.useLauncherClasses = value
        }
        AppToggleRow {
            symbol: "category"
            title: Translation.tr("Apps filed under Games")
            description: Translation.tr("Any window whose desktop entry has the Game category")
            checked: root.opts.game.useDesktopCategory
            onToggled: value => root.opts.game.useDesktopCategory = value
        }
        AppToggleRow {
            symbol: "memory"
            title: Translation.tr("Fullscreen window keeping the GPU busy")
            description: Translation.tr("Catches games nothing else recognises. Also catches a fullscreen video "
                + "that decodes on the GPU — raise the threshold if that happens")
            checked: root.opts.game.useGpuHeuristic
            onToggled: value => root.opts.game.useGpuHeuristic = value
        }
        AppStepperRow {
            enabled: root.opts.game.useGpuHeuristic
            symbol: "speed"
            title: Translation.tr("GPU above (%)")
            value: root.opts.game.gpuThreshold
            from: 10
            to: 100
            stepSize: 5
            onMoved: value => root.opts.game.gpuThreshold = value
        }
        AppStepperRow {
            enabled: root.opts.game.useGpuHeuristic
            symbol: "timelapse"
            title: Translation.tr("For at least (seconds)")
            value: root.opts.game.holdSec
            from: 5
            to: 300
            stepSize: 5
            onMoved: value => root.opts.game.holdSec = value
        }
        AppSettingRow {
            symbol: "playlist_add"
            title: Translation.tr("Always a game")
            description: Translation.tr("Window classes treated as games no matter what. Pick picks from the windows open now.")

            below: [
                ChipInput {
                    Layout.fillWidth: true
                    values: root.opts.game.extraClasses
                    placeholder: Translation.tr("Window class")
                    suggestions: root.windowSuggestions()
                    onChanged: list => root.opts.game.extraClasses = list
                },
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: GameDetector.gameRunning ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                    text: GameDetector.gameRunning
                        ? Translation.tr("Detected now: %1").arg(GameDetector.reason)
                        : Translation.tr("No game detected right now.")
                }
            ]
        }
    }
}
