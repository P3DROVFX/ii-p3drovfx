pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Settings -> Hyprland -> Shortcuts.
 *
 * Every keyboard shortcut, grouped the way the cheatsheet groups them, each showing which file
 * it came from. A shortcut can be changed wherever it was written: the compositor's own files
 * are never edited, so replacing a stock shortcut writes a release of that key followed by a new
 * bind into the block at the end of custom/keybinds.lua, which loads afterwards.
 *
 * The programs shortcuts open live on the neighbouring Default apps tab. Keeping the shortcut
 * browser focused on keys makes both pages shorter and easier to scan.
 */
ContentPage {
    id: tab

    forceWidth: false

    property string rawQuery: ""
    property bool showEverything: false

    readonly property string query: tab.rawQuery.trim().toLowerCase()
    readonly property bool searching: tab.query !== ""

    /// Where the shortcuts live, what the shell's own buttons open, and the switch that adds the
    /// unnamed binds to the list are all things you go looking for. They are behind the switch
    /// in the corner; the list and the search box are not.
    readonly property bool advanced: Config.options.hyprland.advancedSettings

    /// Whether one row is on screen right now. The list itself is grouped once from every row
    /// and rows hide instead of being torn down: rebuilding a hundred delegates per keystroke
    /// was most of what typing in the search box used to cost.
    function shows(row: var): bool {
        if (!tab.showEverything && !HyprlandBinds.isListed(row)) return false;
        return HyprlandBinds.matches(row, tab.query);
    }

    readonly property var allRows: HyprlandBinds.listed.concat(HyprlandBinds.unnamed)
    readonly property int shownCount: tab.allRows.filter(row => tab.shows(row)).length

    readonly property var groups: HyprlandBinds.grouped(tab.allRows)

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

    function edit(row: var) {
        HyprlandBinds.beginEdit(row);
        tab.openSubPage(Qt.resolvedUrl("HyprBindEditorPage.qml"));
    }

    function addShortcut() {
        HyprlandBinds.beginNew();
        tab.openSubPage(Qt.resolvedUrl("HyprBindEditorPage.qml"));
    }

    /// Something elsewhere in the shell asked for a shortcut - a routine's trigger, so far. The
    /// draft is already filled in; all this has to do is show it.
    function takePendingEditor() {
        if (!HyprlandBinds.takePendingEditor())
            return;
        tab.openSubPage(Qt.resolvedUrl("HyprBindEditorPage.qml"));
    }

    // Deferred: openSubPage walks up the parent chain, and on the first frame of a tab that has
    // only just been loaded there is not yet a chain to walk.
    Component.onCompleted: Qt.callLater(tab.takePendingEditor)

    // A second request arrives while this tab is already built, so it never reaches the line above.
    Connections {
        target: HyprlandBinds
        function onPendingEditorChanged() {
            tab.takePendingEditor();
        }
    }

    // ── Finding one ───────────────────────────────────────────────────────────
    ContentSection {
        title: Translation.tr("Shortcuts")
        icon: "keyboard_command_key"

        StyledText {
            Layout.fillWidth: true
            visible: !HyprlandBinds.ready
            text: Translation.tr("Reading the config files…")
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
        }

        MaterialTextField {
            Layout.fillWidth: true
            placeholderText: Translation.tr("Search by name, key or command")
            onTextChanged: tab.rawQuery = text
        }

        HyprToggle {
            visible: tab.advanced
            buttonIcon: "visibility"
            text: Translation.tr("Show the ones with no name")
            switchOn: tab.showEverything
            onRequested: wanted => tab.showEverything = wanted
        }

        HyprOptionNote {
            notes: {
                const out = [];
                for (const missing of HyprlandBinds.missingEssentials)
                    out.push({
                        "icon": "warning",
                        "always": true,
                        "text": Translation.tr("Nothing on this keyboard can %1. Add a shortcut for it before you need one.")
                            .arg(String(missing.label).toLowerCase())
                    });
                if (HyprlandBinds.unnamed.length > 0 && !tab.showEverything)
                    out.push({ "icon": "visibility_off", "text": Translation.tr("%1 more keys are bound without a name. They are the duplicates and fallbacks the config uses, and they still work.")
                        .arg(HyprlandBinds.unnamed.length) });
                if (HyprlandBinds.unreadable.length > 0)
                    out.push({ "icon": "code", "text": Translation.tr("%1 lines build their key in a loop, so this page cannot tell which keys they are. They are left alone.")
                        .arg(HyprlandBinds.unreadable.length) });
                if (HyprlandBinds.unexplainedLive > 0)
                    out.push({ "icon": "help", "text": Translation.tr("Hyprland reports %1 more keys bound than the files here account for — those are the ones from the loops above, and anything a plugin added.")
                        .arg(HyprlandBinds.unexplainedLive) });
                return out;
            }
        }
    }

    /**
     * The list, one group at a time.
     *
     * A stock config binds around a hundred and fifty keys. Every one of them used to be a
     * button with its own ripple, highlight overlay, scroll animation and row of key chips,
     * built the instant the tab was opened - which is why the tab took seconds to appear and
     * then scrolled for a screen and a half per category.
     *
     * A group is now a heading with a count, and its rows are built when it is opened. Typing
     * in the search box opens the groups that have a hit and closes them again when the box is
     * cleared, so searching still reaches everything without any of it being built up front.
     */
    Repeater {
        model: tab.groups

        delegate: ContentSection {
            id: group

            required property var modelData

            readonly property int shownCount: group.modelData.rows.filter(row => tab.shows(row)).length

            visible: group.shownCount > 0
            collapsible: true
            expanded: false
            // The count is in the heading because a collapsed section shows nothing else, and
            // "how many shortcuts are in here" is the only thing worth knowing before opening it.
            title: Translation.tr("%1 · %2").arg(group.modelData.name).arg(group.shownCount)
            icon: {
                const known = { "Shell": "widgets", "Window": "web_asset", "Workspace": "space_dashboard",
                    "Workspaces": "space_dashboard", "Utilities": "build", "Apps": "apps",
                    "App": "apps", "Media": "music_note", "Session": "power_settings_new",
                    "Screen": "monitor", "Misc": "more_horiz", "User": "person" };
                return known[group.modelData.name] ?? "keyboard";
            }

            // A search is a request to see the answer, not to be told which drawer it is in.
            Connections {
                target: tab
                function onSearchingChanged() {
                    group.expanded = tab.searching && group.shownCount > 0;
                }
            }

            Loader {
                Layout.fillWidth: true
                active: group.expanded
                visible: active
                asynchronous: true

                sourceComponent: ColumnLayout {
                    spacing: 4

                    Repeater {
                        model: group.modelData.rows

                        delegate: HyprShortcutRow {
                            required property var modelData

                            visible: tab.shows(modelData)
                            row: modelData
                            onOpenSubPage: tab.edit(modelData)
                        }
                    }
                }
            }
        }
    }

    ContentSection {
        title: Translation.tr("Add")
        icon: "add"

        HyprNavRow {
            buttonIcon: "add"
            text: Translation.tr("Make a shortcut")
            value: Translation.tr("Goes in custom/keybinds.lua")
            onOpenSubPage: tab.addShortcut()
        }

        StyledText {
            Layout.fillWidth: true
            visible: tab.query !== "" && tab.shownCount === 0
            text: Translation.tr("Nothing matches \"%1\".").arg(tab.rawQuery.trim())
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
        }
    }

    // ── Where it all lives ────────────────────────────────────────────────────
    ContentSection {
        visible: tab.advanced
        title: Translation.tr("Where shortcuts live")
        icon: "folder"

        Repeater {
            model: tab.advanced ? HyprlandBinds.parsedFiles : []

            delegate: HyprNavRow {
                required property var modelData

                enabled: false
                buttonIcon: modelData.file.startsWith("custom/") ? "edit_note" : "inventory"
                text: modelData.file
                value: modelData.readable
                    ? Translation.tr("%1 lines").arg(modelData.binds.length)
                    : Translation.tr("Not readable")
            }
        }

        HyprOptionNote {
            notes: [
                { "icon": "lock", "text": Translation.tr("hyprland/keybinds.lua is replaced on every update, so it is never edited from here. Changes go into the block at the end of custom/keybinds.lua, which loads last and wins.") },
                { "icon": "swap_horiz", "text": Translation.tr("Binding a key that is already bound registers both, and both fire. Every shortcut written here therefore releases its key first.") }
            ]
        }
    }

    // ── Related ───────────────────────────────────────────────────────────────
    ContentSection {
        title: Translation.tr("Related settings")
        icon: "link"

        Flow {
            Layout.fillWidth: true
            spacing: 6

            RelatedChip {
                pageId: "cheatSheet"
                label: Translation.tr("Cheatsheet")
            }

            RelatedChip {
                pageId: "modes"
                label: Translation.tr("Modes & Routines")
            }

            RelatedChip {
                pageId: "tiling"
                label: Translation.tr("Window tiling")
            }
        }
    }
}
