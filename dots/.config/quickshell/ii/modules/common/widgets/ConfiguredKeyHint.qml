pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common
import qs.modules.common.widgets

KeyHint {
    id: root

    property string actionId: ""
    property var fallbackKeys: []

    function displayKey(key): string {
        switch (String(key).toLocaleLowerCase()) {
        case "enter":
        case "return":
            return "↵";
        case "up":
            return "↑";
        case "down":
            return "↓";
        case "left":
            return "←";
        case "right":
            return "→";
        case "delete":
            return "Del";
        case "space":
            return "Space";
        case "backspace":
            return "Backspace";
        case "home":
            return "Home";
        default:
            return String(key);
        }
    }

    function configuredKeys(): var {
        if (root.actionId.length === 0)
            return root.fallbackKeys;
        const bindings = Array.from(Config.options.search.keybindings || []);
        let binding = null;
        for (const item of bindings) {
            if (item && String(item.actionId || "") === root.actionId) {
                binding = item;
                break;
            }
        }
        const shortcut = binding ? String(binding.shortcut || "").trim() : "";
        if (shortcut.length === 0)
            return root.fallbackKeys;
        const displayed = [];
        for (const key of shortcut.split("+"))
            displayed.push(root.displayKey(key));
        return displayed;
    }

    keys: root.configuredKeys()
}
