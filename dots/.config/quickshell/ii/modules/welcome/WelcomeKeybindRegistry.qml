pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs
import qs.modules.common
import qs.services

/**
 * Welcome-facing keybind metadata. Descriptions come from the parsed Hyprland
 * keybind source; this registry never stores a guessed key combination.
 */
QtObject {
    id: root

    /**
     * Each action lists its candidate descriptions in order of preference.
     * `Shell: Open search only` ships commented out — it is disabled by
     * default so it cannot fight a game — so an action matching only that one
     * resolved to nothing on a fresh install, and the Welcome advertised the
     * shell's most-used shortcut as unassigned. The Super tap is the fallback
     * because it is the one that is always there.
     */
    readonly property var everydayActions: [{
        "id": "launcher",
        "labelKey": "Search",
        "icon": "search",
        "matchers": ["Shell: Open search only", "Shell: Toggle search"]
    }, {
        "id": "dashboard",
        "labelKey": "Dashboard",
        "icon": "side_navigation",
        "matchers": ["Shell: Toggle right sidebar"]
    }, {
        "id": "overview",
        "labelKey": "Overview",
        "icon": "grid_view",
        "matchers": ["Shell: Toggle overview"]
    }, {
        "id": "cheatsheet",
        "labelKey": "All shortcuts",
        "icon": "help",
        "matchers": ["Shell: Toggle cheatsheet"]
    }]

    readonly property var exploreActions: [{
        "id": "terminal",
        "labelKey": "Terminal",
        "icon": "terminal",
        "matchers": ["App: Terminal"]
    }, {
        "id": "settings",
        "labelKey": "Settings",
        "icon": "settings",
        "matchers": ["App: Settings app"]
    }, {
        "id": "ai",
        "labelKey": "AI sidebar",
        "icon": "neurology",
        "matchers": ["Shell: Toggle left sidebar"]
    }, {
        "id": "closeWindow",
        "labelKey": "Close window",
        "icon": "close",
        "matchers": ["Window: Close"]
    }, {
        "id": "screenshot",
        "labelKey": "Screen snip",
        "icon": "screenshot_region",
        "matchers": ["Utilities: Screen snip"]
    }, {
        "id": "wallpaper",
        "labelKey": "Wallpaper picker",
        "icon": "wallpaper",
        "matchers": ["Shell: Toggle wallpaper selector"]
    }, {
        "id": "keyboardLayout",
        "labelKey": "Switch keyboard layout",
        "icon": "keyboard",
        "matchers": ["Switch keyboard layout"]
    }, {
        "id": "session",
        "labelKey": "Session menu",
        "icon": "power_settings_new",
        "matchers": ["Shell: Toggle session menu"]
    }]

    readonly property var actions: [...everydayActions, ...exploreActions]

    // ── What the reader has actually tried ────────────────────────────────
    //
    // The shortcuts step lists four keys, and a list is something you read
    // rather than something you learn. Every one of them opens a surface the
    // shell already publishes a flag for, so pressing the key is observable
    // without asking the reader to prove anything: the card just ticks.
    //
    // Nothing gates on this. It is a record of what happened, not a gate — a
    // step that refuses to advance until you perform is a step that traps
    // someone whose keyboard has a different layout than the one assumed.
    //
    // Lives on the singleton rather than on the page so walking back and
    // forth through the flow does not erase it; cleared when the Welcome
    // closes, because it is about this sitting.
    property var performedActions: ({})

    function markPerformed(actionId: string): void {
        if (root.performedActions[actionId])
            return;
        const next = Object.assign({}, root.performedActions);
        next[actionId] = true;
        root.performedActions = next;
    }

    function hasPerformed(actionId: string): bool {
        return root.performedActions[actionId] === true;
    }

    function resetPerformed(): void {
        root.performedActions = ({});
    }

    readonly property int performedEverydayCount: root.everydayActions
        .filter(action => root.hasPerformed(action.id)).length

    // Search and Overview are the same surface told apart by one flag, which
    // is why they are read here rather than each card watching its own.
    readonly property Connections watcher: Connections {
        target: GlobalStates

        function onOverviewOpenChanged() {
            if (!GlobalStates.overviewOpen)
                return;
            root.markPerformed(GlobalStates.searchOnlyMode ? "launcher" : "overview");
        }

        function onDashboardPanelOpenChanged() {
            if (GlobalStates.dashboardPanelOpen)
                root.markPerformed("dashboard");
        }

        function onCheatsheetOpenChanged() {
            if (GlobalStates.cheatsheetOpen)
                root.markPerformed("cheatsheet");
        }

        function onSettingsOpenChanged() {
            if (GlobalStates.settingsOpen)
                root.markPerformed("settings");
        }

        function onWelcomeOpenChanged() {
            if (!GlobalStates.welcomeOpen)
                root.resetPerformed();
        }
    }

    function flatten(nodes, output): void {
        for (const node of nodes ?? []) {
            output.push(...(node.keybinds ?? []));
            root.flatten(node.children, output);
        }
    }

    function parseUnbinds(nodes, output): void {
        for (const node of nodes ?? []) {
            output.push(...(node.unbinds ?? []));
            root.parseUnbinds(node.children, output);
        }
    }

    function sameBinding(a, b): bool {
        if (!a || !b || a.key !== b.key)
            return false;
        const aMods = a.mods ?? [];
        const bMods = b.mods ?? [];
        if (aMods.length !== bMods.length)
            return false;
        for (let i = 0; i < aMods.length; i++) {
            if (aMods[i] !== bMods[i])
                return false;
        }
        return true;
    }

    function rawKeybindFor(action): var {
        const bindings = [];
        root.flatten(HyprlandKeybinds.defaultKeybinds.children, bindings);
        root.flatten(HyprlandKeybinds.userKeybinds.children, bindings);

        const unbinds = [];
        if (Config.options.cheatsheet.filterUnbinds) {
            root.parseUnbinds(HyprlandKeybinds.userKeybinds.children, unbinds);
            unbinds.push(...(HyprlandKeybinds.userKeybinds.unbinds ?? []));
        }

        for (const matcher of action.matchers ?? []) {
            let result = null;
            for (const binding of bindings) {
                if (binding.comment !== matcher)
                    continue;
                if (unbinds.some(unbind => root.sameBinding(unbind, binding)))
                    continue;
                result = binding;
            }
            if (result)
                return result;
        }
        return null;
    }

    /** Every parsed keybind that carries a description, across both files. */
    readonly property int describedKeybindCount: {
        const bindings = [];
        root.flatten(HyprlandKeybinds.defaultKeybinds.children, bindings);
        root.flatten(HyprlandKeybinds.userKeybinds.children, bindings);
        return bindings.filter(binding => String(binding.comment ?? "").length > 0).length;
    }

    function displayKey(key: string): string {
        const map = {
            "SUPER": Config.options.cheatsheet.superKey || "Super",
            "Super": Config.options.cheatsheet.superKey || "Super",
            "CTRL": "Ctrl",
            "ALT": "Alt",
            "SHIFT": "Shift",
            "Slash": "/",
            "Hash": "#",
            "Return": "Enter",
            "Space": "Space",
            "Tab": "Tab",
            "Period": "."
        };
        return map[key] ?? key;
    }

    /**
     * Run the action a card stands for, by dispatching the binding the card is
     * already showing.
     *
     * Every card used to open the cheatsheet, which made the four keycaps
     * decorative: the one thing a card could not do was the thing it was
     * about. Going through the parsed binding rather than through a lookup of
     * our own means a rebound key does here exactly what it does on the
     * keyboard, and the checkmark lights up the same way for a click as for a
     * press — the flags it watches do not care which one arrived.
     *
     * Returns false when the action resolves to nothing, so the caller can
     * fall back rather than swallow the click.
     */
    function trigger(actionId: string): bool {
        const action = root.actions.find(item => item.id === actionId);
        const binding = action ? root.rawKeybindFor(action) : null;
        if (!binding)
            return false;
        return HyprlandKeybinds.dispatchBinding(binding);
    }

    function keysFor(actionId: string): list<string> {
        const action = root.actions.find(item => item.id === actionId);
        const binding = action ? root.rawKeybindFor(action) : null;
        if (!binding)
            return [];
        const result = [];
        for (const modifier of binding.mods ?? [])
            result.push(root.displayKey(modifier));
        // A tap on Super arrives as its own key alongside the SUPER modifier,
        // spelled by the parser in whatever case the config used. Printing it
        // would render the shortcut as "Super + SUPER_L".
        if (binding.key && !/^super_[lr]$/i.test(binding.key))
            result.push(root.displayKey(binding.key));
        return result;
    }
}
