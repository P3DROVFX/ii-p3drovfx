pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
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
