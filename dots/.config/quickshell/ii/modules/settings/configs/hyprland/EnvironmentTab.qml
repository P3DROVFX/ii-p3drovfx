pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Settings -> Hyprland -> Environment.
 *
 * Environment variables are the one part of the config nothing can read back: Hyprland exports
 * them as it loads, and no program can be asked what it was given afterwards. So this page never
 * claims to show a live value. It shows what the three files that set variables say, in the order
 * Hyprland reads them, and what a program started from now on would therefore get.
 *
 * The pointer sits at the top because it is the exception to everything else here - four ordinary
 * variables that also have a live path, so changing it is visible immediately instead of at the
 * next login.
 */
ContentPage {
    id: tab

    forceWidth: false

    /**
     * The pointer and the icon pack stay: they are things people change, and they are the two
     * settings on this tab that take effect at once. Everything else here is an environment
     * variable - it reaches the next program you open and nothing that is already running - so
     * presets, the raw variable list, what the shell set before this page and the explanation
     * of when any of it applies are all behind advanced mode.
     */
    readonly property bool advanced: Config.options.hyprland.advancedSettings

    readonly property var currentTheme: HyprlandEnv.themeEntry(HyprlandEnv.cursorTheme)

    function openSubPage(page: url) {
        let node = tab.parent;
        while (node) {
            if (typeof node.activeSubPage !== "undefined") {
                node.activeSubPage = page;
                return;
            }
            node = node.parent;
        }
    }

    function editVariable(name: string) {
        HyprlandEnv.beginEdit(name);
        tab.openSubPage(Qt.resolvedUrl("HyprEnvEditorPage.qml"));
    }

    function addVariable() {
        HyprlandEnv.beginNew();
        tab.openSubPage(Qt.resolvedUrl("HyprEnvEditorPage.qml"));
    }

    /// One variable, however it got there. Hand-written ones open the same editor, which writes a
    /// managed line below rather than changing the line itself.
    component VariableRow: HyprNavRow {
        required property var variable

        buttonIcon: variable.source === "managed" ? "edit" : "edit_note"
        text: variable.name
        value: variable.value === "" ? Translation.tr("Empty") : variable.value
        onOpenSubPage: tab.editVariable(variable.name)
    }

    // ── The pointer ───────────────────────────────────────────────────────────
    ContentSection {
        title: Translation.tr("Pointer")
        icon: "mouse"

        HyprNavRow {
            buttonIcon: "arrow_selector_tool"
            text: Translation.tr("Cursor theme")
            value: tab.currentTheme ? tab.currentTheme.title : HyprlandEnv.cursorTheme
            onOpenSubPage: tab.openSubPage(Qt.resolvedUrl("HyprCursorThemePage.qml"))
        }

        ConfigSpinBox {
            id: sizeBox

            /**
             * Same rule as every other control in this hub, and stricter, because writing here
             * also changes the pointer on screen: the value pushes in, and only a change made by
             * hand pushes back. Arming waits for the files to have been read, and a value that
             * differs only because this box clamped what it was given is not an edit.
             */
            property bool armed: false
            property real reported: NaN

            icon: "aspect_ratio"
            text: Translation.tr("Cursor size")
            from: 8
            to: 128
            stepSize: 4
            value: HyprlandEnv.cursorSize

            function clamped(size: real): real {
                return Math.min(sizeBox.to, Math.max(sizeBox.from, size));
            }

            onValueChanged: {
                if (!sizeBox.armed || sizeBox.value === HyprlandEnv.cursorSize) return;
                if (isFinite(sizeBox.reported) && sizeBox.value === sizeBox.clamped(sizeBox.reported))
                    return;
                HyprlandEnv.applyCursor(HyprlandEnv.cursorTheme, sizeBox.value);
            }

            Connections {
                target: HyprlandEnv

                function onCursorSizeChanged() {
                    sizeBox.reported = HyprlandEnv.cursorSize;
                    sizeBox.value = HyprlandEnv.cursorSize;
                }

                function onReadyChanged() {
                    sizeBox.arm();
                }
            }

            function arm() {
                if (sizeBox.armed || !HyprlandEnv.ready) return;
                sizeBox.reported = HyprlandEnv.cursorSize;
                Qt.callLater(() => sizeBox.armed = true);
            }

            Component.onCompleted: sizeBox.arm()
        }

        HyprNavRow {
            visible: HyprlandEnv.envSource("HYPRCURSOR_THEME") === "managed"
                || HyprlandEnv.envSource("XCURSOR_SIZE") === "managed"
            buttonIcon: "undo"
            text: Translation.tr("Undo what this page set")
            value: Translation.tr("Back to the config file")
            onOpenSubPage: HyprlandEnv.resetCursor()
        }

        HyprOptionNote {
            notes: {
                const out = [{ "icon": "bolt", "text": Translation.tr("The pointer is the one thing here that changes at once: the compositor is told directly, and every other copy of the setting follows - GTK, KDE apps, the X11 fallback Steam reads, flatpaks. The four variables are written as well, so it survives a reboot.") }];
                if (HyprlandEnv.cursorSplit)
                    out.push({ "icon": "warning", "always": true, "text": Translation.tr("Hyprland is drawing %1 while X11 windows get %2. Picking a theme here sets both.")
                        .arg(HyprlandEnv.envValue("HYPRCURSOR_THEME")).arg(HyprlandEnv.envValue("XCURSOR_THEME")) });
                if (HyprlandEnv.gtkOutOfStep)
                    out.push({ "icon": "sync_problem", "always": true, "text": Translation.tr("GTK apps are still using %1. Choosing a theme here brings them into line.")
                        .arg(String(HyprlandEnv.probe.gtkTheme ?? "")) });
                if (tab.currentTheme && !tab.currentTheme.hypr)
                    out.push({ "icon": "info", "text": Translation.tr("%1 has no hyprcursor version, so Hyprland falls back to the X11 one. It works, and it does not scale as cleanly.")
                        .arg(tab.currentTheme.title) });
                return out;
            }
        }
    }

    // ── Icons ─────────────────────────────────────────────────────────────────
    ContentSection {
        title: Translation.tr("Icons")
        icon: "apps"

        Component.onCompleted: IconThemes.refreshPacks()

        HyprNavRow {
            buttonIcon: "category"
            text: Translation.tr("Icon pack")
            value: {
                const entry = IconThemes.packEntry(IconThemes.currentPack);
                const label = entry ? entry.title : IconThemes.currentPack;
                return IconThemes.themed ? Translation.tr("%1 · recolored").arg(label) : label;
            }
            onOpenSubPage: tab.openSubPage(Qt.resolvedUrl("HyprIconPackPage.qml"))
        }

        HyprOptionNote {
            notes: [
                { "icon": "info", "text": Translation.tr("Not a Hyprland setting - the copies live with GTK, KDE and gsettings - but it sits here next to the pointer, which is set the same everywhere-at-once way.") }
            ]
        }
    }

    // ── Desktop portal ───────────────────────────────────────────────────────
    ContentSection {
        title: Translation.tr("Desktop portal")
        icon: "hub"

        Component.onCompleted: XdgDesktopPortal.refresh()

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Choose the desktop backend used by XDG file choosers and other portal-aware applications. Hyprland remains the screen-sharing backend.")
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
            wrapMode: Text.WordWrap
        }

        ContentSubsection {
            title: Translation.tr("File chooser backend")
            icon: "folder_open"

            ConfigSelectionArray {
                Layout.fillWidth: true
                enabled: XdgDesktopPortal.ready && !XdgDesktopPortal.writing
                    && !XdgDesktopPortal.restarting
                currentValue: XdgDesktopPortal.selectedBackend
                options: XdgDesktopPortal.portalOptions
                onSelected: value => XdgDesktopPortal.setBackend(String(value))
            }
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: XdgDesktopPortal.errorMessage !== ""
            materialIcon: "error"
            text: XdgDesktopPortal.errorMessage
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: XdgDesktopPortal.statusMessage !== ""
            materialIcon: "check_circle"
            text: XdgDesktopPortal.statusMessage
        }

        HyprOptionNote {
            notes: [{ "icon": "restart_alt", "text": Translation.tr("Changing this restarts xdg-desktop-portal so new dialogs use the selection immediately. A dialog already open keeps its current backend.") }]
        }
    }

    // ── The honest part ───────────────────────────────────────────────────────
    ContentSection {
        visible: tab.advanced
        title: Translation.tr("When the rest of this takes effect")
        icon: "schedule"

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Everything below is handed to a program when it starts, and never afterwards. A change here reaches something you open next; it does not reach anything already running, which on a desktop is nearly everything. Logging out and back in is the only way to be sure the whole session has it.")
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
            wrapMode: Text.WordWrap
        }

        HyprOptionNote {
            notes: [
                { "icon": "search_off", "text": Translation.tr("Nothing can be asked what a variable currently is, so this page never guesses. It reads the files, in the order Hyprland loads them, and shows what the next program will be given.") },
                { "icon": "layers", "text": Translation.tr("hyprland/env.lua runs first and is replaced on every update. This page writes into the block at the end of custom/env.lua, which runs after it and wins.") }
            ]
        }
    }

    // ── Presets ───────────────────────────────────────────────────────────────
    ContentSection {
        visible: tab.advanced
        title: Translation.tr("Presets")
        icon: "widgets"

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Sets of variables that only make sense together. Choosing one writes all of them and clears the ones the others used, so switching cannot leave half of the old setting behind.")
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
            wrapMode: Text.WordWrap
        }

        Repeater {
            model: tab.advanced ? HyprlandEnv.presets : []

            delegate: ContentSubsection {
                id: presetGroup

                required property var modelData

                readonly property var state: HyprlandEnv.presetState(presetGroup.modelData.id)
                /// A preset for hardware this machine does not have is shown, because a config is
                /// carried between machines, but it does not pretend to be useful here.
                readonly property bool irrelevant: {
                    const detects = String(presetGroup.modelData.detects ?? "");
                    return detects !== "" && HyprlandEnv.probe[detects] === false;
                }

                title: presetGroup.modelData.label
                icon: presetGroup.modelData.icon

                StyledText {
                    Layout.fillWidth: true
                    text: presetGroup.modelData.detail
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.WordWrap
                }

                ConfigSelectionArray {
                    currentValue: presetGroup.state.variant
                    options: Array.from(presetGroup.modelData.variants).map(variant => ({
                        "displayName": HyprlandEnv.variantMissing(variant)
                            ? Translation.tr("%1 — not installed").arg(variant.label) : variant.label,
                        "value": variant.id
                    }))
                    onSelected: newValue => HyprlandEnv.applyPreset(presetGroup.modelData.id, newValue)
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: {
                        const lines = [];
                        if (presetGroup.state.variant === "")
                            lines.push(Translation.tr("These variables are set to something this page does not recognise. Choosing an option below replaces them."));
                        for (const conflict of presetGroup.state.elsewhere)
                            lines.push(conflict.source === "upstream"
                                ? Translation.tr("%1 comes from hyprland/env.lua. Setting it here overrides that.").arg(conflict.name)
                                : Translation.tr("%1 is written by hand at custom/env.lua line %2. Setting it here adds a line below that one, which wins.")
                                    .arg(conflict.name).arg(conflict.line));
                        const blanked = HyprlandEnv.blankedNames(presetGroup.modelData.id);
                        if (blanked.length > 0)
                            lines.push(Translation.tr("A config file cannot unset a variable, so turning this off writes %1 as empty rather than removing it. Every program here reads that as off.")
                                .arg(blanked.join(", ")));
                        if (presetGroup.irrelevant)
                            lines.push(Translation.tr("No card of this kind was found on this machine, so nothing here would change anything."));
                        if (presetGroup.modelData.note !== undefined)
                            lines.push(presetGroup.modelData.note);
                        return lines.join("\n");
                    }
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.WordWrap
                }
            }
        }
    }

    // ── Everything else ───────────────────────────────────────────────────────
    ContentSection {
        visible: tab.advanced
        title: Translation.tr("Variables")
        icon: "code"

        StyledText {
            Layout.fillWidth: true
            text: HyprlandEnv.claimedCount > 0
                ? Translation.tr("Everything custom/env.lua sets that the sections above do not already have a control for. %1 more are handled up there.")
                    .arg(HyprlandEnv.claimedCount)
                : Translation.tr("Everything custom/env.lua sets.")
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
            wrapMode: Text.WordWrap
        }

        Repeater {
            model: tab.advanced ? HyprlandEnv.otherVariables : []

            delegate: VariableRow {
                required property var modelData

                variable: modelData
            }
        }

        HyprNavRow {
            buttonIcon: "add"
            text: Translation.tr("Add a variable")
            value: Translation.tr("Goes in custom/env.lua")
            onOpenSubPage: tab.addVariable()
        }

        HyprOptionNote {
            notes: {
                const out = [];
                const hand = HyprlandEnv.otherVariables.filter(row => row.source === "hand");
                if (hand.length > 0)
                    out.push({ "icon": "edit_note", "text": Translation.tr("%1 of these were written by hand. Changing one leaves its line alone and adds one below it, which runs afterwards.")
                        .arg(hand.length) });
                const blanked = HyprlandEnv.otherVariables.filter(row => row.value === "");
                if (blanked.length > 0)
                    out.push({ "icon": "backspace", "text": Translation.tr("%1 are set to nothing. A config file cannot unset a variable, so that is what turning one off looks like.")
                        .arg(blanked.length) });
                return out;
            }
        }
    }

    // ── What is already set ───────────────────────────────────────────────────
    ContentSection {
        visible: tab.advanced
        title: Translation.tr("Set before this page")
        icon: "inventory"

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("hyprland/env.lua, which the shell ships and every update replaces. Listed so you can see what a variable of the same name here would be replacing.")
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
            wrapMode: Text.WordWrap
        }

        Repeater {
            model: tab.advanced ? HyprlandEnv.upstream : []

            delegate: HyprNavRow {
                required property var modelData

                enabled: false
                buttonIcon: modelData.unresolved ? "function" : "inventory"
                text: modelData.unresolved ? Translation.tr("Built in code, line %1").arg(modelData.line)
                    : modelData.name
                value: modelData.unresolved
                    ? Translation.tr("Not readable")
                    : (HyprlandEnv.plainValue(modelData.value) || Translation.tr("Empty"))
            }
        }

        HyprOptionNote {
            notes: {
                const out = [];
                const replaced = HyprlandEnv.upstream.filter(entry =>
                    entry.name !== "" && HyprlandGui.managedEnv[entry.name] !== undefined);
                if (replaced.length > 0)
                    out.push({ "icon": "swap_horiz", "text": Translation.tr("This page replaces %1 of them.")
                        .arg(replaced.length) });
                if (HyprlandEnv.late.length > 0)
                    out.push({ "icon": "layers", "text": Translation.tr("%1 more are set later still, by hyprland/variables.lua, which loads through the keybind file. A variable of one of those names cannot be changed from here.")
                        .arg(HyprlandEnv.late.length) });
                return out;
            }
        }
    }

    // ── Related ───────────────────────────────────────────────────────────────
    ContentSection {
        visible: tab.advanced
        title: Translation.tr("Related settings")
        icon: "link"

        Flow {
            Layout.fillWidth: true
            spacing: 6

            RelatedChip {
                pageId: "displays"
                label: Translation.tr("Displays")
            }

            RelatedChip {
                pageId: "languageTime"
                label: Translation.tr("Language & Time")
            }

            RelatedChip {
                pageId: "interfaceFonts"
                label: Translation.tr("Interface & Fonts")
            }
        }
    }
}
