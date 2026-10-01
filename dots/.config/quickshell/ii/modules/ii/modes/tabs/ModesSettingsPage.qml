pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import qs.modules.ii.modes

/**
 * The app's own settings: where the active mode shows, automatic ends, the presets, game
 * detection and the stored data. Automatic starts and loading the app stay in Settings →
 * Modes & Routines. Writes go straight to Config, so the bar, the island and the lock
 * screen follow the moment a value changes.
 */
Rectangle {
    id: root

    property bool compact: false
    /// Two columns of sections once the page can hold them, as the clock's settings do.
    property bool wide: false
    /// The settled width (the live one animates with the rail); the page opens no sheet.
    property real layoutWidth: root.width

    readonly property var opts: Config.options.modes
    readonly property real padding: root.compact ? ClockStyle.pagePadding : ClockStyle.pagePaddingWide
    readonly property real contentWidth: Math.max(0, Math.min(root.layoutWidth - root.padding * 2,
        root.wide ? 1240 : ClockStyle.sheetMaxWidth * 1.3))
    property string seededText: ""
    property bool confirmClear: false

    readonly property var barEntry: root.findBarEntry()
    readonly property bool barVisible: (root.barEntry && root.barEntry.entry && root.barEntry.entry.visible !== undefined)
        ? root.barEntry.entry.visible : false

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

    // The layout lists are stored, not derived: the whole array is rewritten so the
    // JsonAdapter sees the change.
    function setBarVisible(on: bool): void {
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

    function restorePresets(): void {
        const added = Modes.seedPresets();
        root.seededText = added.length === 0 ? Translation.tr("All presets are already there")
            : Translation.tr("Added: %1").arg(added.map(id => {
                const m = Modes.modeById(id);
                return (m && m.name) ? m.name : id;
            }).join(", "));
    }

    color: ClockStyle.colBackground

    component Toggle: StyledSwitch {
        property var target
        property string key
        checked: Boolean(target?.[key])
        checkable: false
        onClicked: target[key] = !target[key]
    }

    StyledFlickable {
        id: flick
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: column.implicitHeight + ClockStyle.gapHuge * 2

        GridLayout {
            id: column
            x: Math.max(root.padding, (flick.width - width) / 2)
            y: ClockStyle.gapSmall
            width: root.contentWidth
            columns: root.wide ? 2 : 1
            columnSpacing: ClockStyle.gapHuge
            rowSpacing: ClockStyle.gapHuge
            uniformCellWidths: true

            // ── Where the active mode shows ─────────────────────────────
            ClockSettingsSection {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                title: Translation.tr("Where the active mode shows")
                symbol: "campaign"

                ClockSettingsRow {
                    first: true
                    symbol: "space_bar"
                    title: Translation.tr("Pill in the bar")
                    description: Translation.tr("The same widget as in the bar layout editor: takes no room while nothing is on. Left-click opens this app, right-click ends the mode")
                    clickable: true
                    onClicked: root.setBarVisible(!root.barVisible)

                    StyledSwitch {
                        checked: root.barVisible
                        checkable: false
                        onClicked: root.setBarVisible(!root.barVisible)
                    }
                }

                ClockSettingsRow {
                    symbol: "lock"
                    title: Translation.tr("Pill on the lock screen")
                    clickable: true
                    onClicked: root.opts.lockPill = !root.opts.lockPill

                    Toggle {
                        target: root.opts
                        key: "lockPill"
                    }
                }

                ClockSettingsRow {
                    last: true
                    symbol: "notifications_active"
                    title: Translation.tr("When a mode starts or ends")
                    description: Config.options.bar.floatingNotch.enable || Config.options.bar.floatingNotch.centerInBar
                        ? Translation.tr("Drawn by the dynamic island for three seconds. Each mode and routine chooses its own start and end banner.")
                        : Translation.tr("A small top-centre pill for three seconds; the dynamic island takes over when it is enabled. Each mode and routine chooses its own start and end banner.")

                    ClockChip {
                        label: Translation.tr("Brief banner")
                        selected: root.opts.flash !== "off"
                        onClicked: root.opts.flash = "auto"
                    }

                    ClockChip {
                        label: Translation.tr("Nothing")
                        selected: root.opts.flash === "off"
                        onClicked: root.opts.flash = "off"
                    }
                }
            }

            // ── Automatic ends ──────────────────────────────────────────
            ClockSettingsSection {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                title: Translation.tr("Automatic ends")
                symbol: "timer"

                ClockSettingsRow {
                    first: true
                    last: true
                    symbol: "hourglass_bottom"
                    title: Translation.tr("Grace period")
                    description: Translation.tr("How long an app, player or device condition must stay false before its mode ends on its own, so an app restart or a track change does not flap it. Schedules, battery, lid and the like end a mode at once")

                    ClockStepper {
                        value: root.opts.graceSec
                        from: 0
                        to: 600
                        stepSize: 5
                        format: value => Translation.tr("%1 s").arg(value)
                        onMoved: value => root.opts.graceSec = value
                    }
                }
            }

            // ── Presets ─────────────────────────────────────────────────
            ClockSettingsSection {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                title: Translation.tr("Presets")
                symbol: "inventory_2"

                ClockSettingsRow {
                    first: true
                    last: true
                    symbol: "restore"
                    title: Translation.tr("Restore missing presets")
                    description: root.seededText.length > 0 ? root.seededText
                        : Translation.tr("The built-in modes (Sleep, Work, Focus, Gaming, Theater, Presentation, Relax) are ordinary entries once added: edit or delete them freely. This puts back any you removed, without touching the ones still there.")

                    ClockButton {
                        variant: "tonal"
                        symbol: "restore"
                        label: Translation.tr("Restore")
                        onClicked: root.restorePresets()
                    }
                }
            }

            // ── Game detection ──────────────────────────────────────────
            ClockSettingsSection {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                title: Translation.tr("Game detection")
                symbol: "sports_esports"

                ClockSettingsRow {
                    first: true
                    symbol: "rocket_launch"
                    title: Translation.tr("Windows from game launchers")
                    description: Translation.tr("Steam, Heroic, Lutris, Bottles, Prism Launcher and fullscreen Windows executables. Feeds the \"A game is running / focused\" condition")
                    clickable: true
                    onClicked: root.opts.game.useLauncherClasses = !root.opts.game.useLauncherClasses

                    Toggle {
                        target: root.opts.game
                        key: "useLauncherClasses"
                    }
                }

                ClockSettingsRow {
                    symbol: "category"
                    title: Translation.tr("Apps filed under Games")
                    description: Translation.tr("Any window whose desktop entry has the Game category")
                    clickable: true
                    onClicked: root.opts.game.useDesktopCategory = !root.opts.game.useDesktopCategory

                    Toggle {
                        target: root.opts.game
                        key: "useDesktopCategory"
                    }
                }

                ClockSettingsRow {
                    symbol: "memory"
                    title: Translation.tr("Fullscreen window keeping the GPU busy")
                    description: Translation.tr("Catches games nothing else recognises. Also catches a fullscreen video that decodes on the GPU — raise the threshold if that happens")
                    clickable: true
                    onClicked: root.opts.game.useGpuHeuristic = !root.opts.game.useGpuHeuristic

                    Toggle {
                        target: root.opts.game
                        key: "useGpuHeuristic"
                    }
                }

                ClockSettingsRow {
                    symbol: "speed"
                    title: Translation.tr("GPU above")
                    enabled: root.opts.game.useGpuHeuristic
                    opacity: enabled ? 1 : 0.5

                    ClockStepper {
                        value: root.opts.game.gpuThreshold
                        from: 10
                        to: 100
                        stepSize: 5
                        format: value => `${value} %`
                        onMoved: value => root.opts.game.gpuThreshold = value
                    }
                }

                ClockSettingsRow {
                    symbol: "timelapse"
                    title: Translation.tr("For at least")
                    enabled: root.opts.game.useGpuHeuristic
                    opacity: enabled ? 1 : 0.5

                    ClockStepper {
                        value: root.opts.game.holdSec
                        from: 5
                        to: 300
                        stepSize: 5
                        format: value => Translation.tr("%1 s").arg(value)
                        onMoved: value => root.opts.game.holdSec = value
                    }
                }

                // Always a game: the chips need the row's full width, so they sit under
                // its title rather than in the control slot.
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: gameColumn.implicitHeight + ClockStyle.gapLarge * 2
                    color: ClockStyle.colPane
                    topLeftRadius: ClockStyle.radiusSmall / 2
                    topRightRadius: ClockStyle.radiusSmall / 2
                    bottomLeftRadius: ClockStyle.radiusLarge
                    bottomRightRadius: ClockStyle.radiusLarge

                    ColumnLayout {
                        id: gameColumn
                        anchors {
                            left: parent.left
                            right: parent.right
                            top: parent.top
                            leftMargin: ClockStyle.cardPadding
                            rightMargin: ClockStyle.gapLarge
                            topMargin: ClockStyle.gapLarge
                        }
                        spacing: ClockStyle.gap

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: ClockStyle.gapLarge

                            MaterialSymbol {
                                text: "playlist_add"
                                iconSize: ClockStyle.iconNormal
                                color: ClockStyle.colOnSurfaceVariant
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                StyledText {
                                    Layout.fillWidth: true
                                    text: Translation.tr("Always a game")
                                    wrapMode: Text.WordWrap
                                    font.pixelSize: ClockStyle.textNormal + 1
                                    color: ClockStyle.colOnSurface
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: Translation.tr("Window classes treated as games no matter what. Pick offers the windows open now.")
                                    wrapMode: Text.WordWrap
                                    font.pixelSize: ClockStyle.textSmall
                                    color: ClockStyle.colSubtext
                                }
                            }
                        }

                        ChipInput {
                            Layout.fillWidth: true
                            Layout.leftMargin: ClockStyle.iconNormal + ClockStyle.gapLarge
                            values: root.opts.game.extraClasses
                            placeholder: Translation.tr("Window class")
                            suggestions: ModeUi.windowSuggestions()
                            onChanged: list => root.opts.game.extraClasses = list
                        }

                        StyledText {
                            Layout.fillWidth: true
                            Layout.leftMargin: ClockStyle.iconNormal + ClockStyle.gapLarge
                            wrapMode: Text.WordWrap
                            font.pixelSize: ClockStyle.textSmall
                            color: GameDetector.gameRunning ? ClockStyle.colPrimary : ClockStyle.colSubtext
                            text: GameDetector.gameRunning
                                ? Translation.tr("Detected now: %1").arg(GameDetector.reason)
                                : Translation.tr("No game detected right now.")
                        }
                    }
                }
            }

            // ── Data ────────────────────────────────────────────────────
            ClockSettingsSection {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                title: Translation.tr("Data")
                symbol: "database"

                ClockSettingsRow {
                    first: true
                    symbol: "history"
                    title: Translation.tr("Activity")
                    description: {
                        if (root.confirmClear)
                            return Translation.tr("Every entry in the Activity tab is forgotten. Modes and routines are not touched.");
                        const n = Modes.history.length;
                        const count = n === 1 ? Translation.tr("1 entry") : Translation.tr("%1 entries").arg(n);
                        return Translation.tr("%1 in the Activity tab. The newest 200 are kept.").arg(count);
                    }

                    // Confirmed in place: a settings row has no sheet to open.
                    ClockButton {
                        visible: !root.confirmClear
                        variant: "tonal"
                        danger: true
                        symbol: "delete_sweep"
                        label: Translation.tr("Clear")
                        enabled: Modes.history.length > 0
                        opacity: enabled ? 1 : 0.5
                        onClicked: root.confirmClear = true
                    }

                    ClockButton {
                        visible: root.confirmClear
                        variant: "text"
                        label: Translation.tr("Cancel")
                        onClicked: root.confirmClear = false
                    }

                    ClockButton {
                        visible: root.confirmClear
                        variant: "filled"
                        danger: true
                        symbol: "delete_sweep"
                        label: Translation.tr("Clear")
                        onClicked: {
                            Modes.clearHistory();
                            root.confirmClear = false;
                        }
                    }
                }

                ClockSettingsRow {
                    symbol: "folder_open"
                    title: Translation.tr("Where it lives")
                    description: Translation.tr("Modes and routines are saved in config.json under \"modes\", so a config backup carries them. What is running and the activity log are state, kept separately and restored after a restart.")
                }

                ClockSettingsRow {
                    last: true
                    symbol: "keyboard"
                    title: Translation.tr("Keybinds")
                    description: Translation.tr("Super+Y opens this app. Bind the shortcuts modesToggle, modesOpen and modesClose, or call \"qs -c ii ipc call modes toggle\". Automatic starts are switched on and off in Settings → Modes & Routines.")
                }
            }
        }
    }
}
