pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * Compact shortcut label shared by personal pages and the editor preview.
 *
 * The entire chord lives in one capsule, matching the default Hyprland cards.
 * Tokens are still parsed so Nerd Font glyphs can coexist with monospace text,
 * but individual keys never become competing shapes.
 */
Rectangle {
    id: root

    property string shortcutText: ""
    property real maximumWidth: 9999
    property bool compact: false
    // Matches Hyprland's combined (splitButtons=false) key chip: a quiet
    // surface capsule with the regular on-surface label.
    property color capsuleColor: Appearance.colors.colSurfaceContainerLow
    property color textColor: Appearance.colors.colOnSurface

    readonly property var macSymbolMap: ({
        "Ctrl": "󰘴",
        "Alt": "󰘵",
        "Shift": "󰘶",
        "Space": "󱁐",
        "Tab": "↹",
        "Equal": "󰇼",
        "Minus": "",
        "Print": "",
        "BackSpace": "󰭜",
        "Delete": "⌦",
        "Return": "󰌑",
        "Period": ".",
        "Escape": "⎋"
    })
    readonly property var functionSymbolMap: ({
        "F1": "󱊫",
        "F2": "󱊬",
        "F3": "󱊭",
        "F4": "󱊮",
        "F5": "󱊯",
        "F6": "󱊰",
        "F7": "󱊱",
        "F8": "󱊲",
        "F9": "󱊳",
        "F10": "󱊴",
        "F11": "󱊵",
        "F12": "󱊶"
    })
    readonly property var mouseSymbolMap: ({
        "mouse_up": "󱕐",
        "mouse_down": "󱕑",
        "mouse:272": "L󰍽",
        "mouse:273": "R󰍽",
        "Scroll ↑/↓": "󱕒",
        "Page_↑/↓": "⇞/⇟"
    })
    readonly property var substitutions: {
        const superKey = Config.options.cheatsheet.superKey;
        const macSymbols = Config.options.cheatsheet.useMacSymbol ? root.macSymbolMap : {};
        const functionSymbols = Config.options.cheatsheet.useFnSymbol ? root.functionSymbolMap : {};
        const mouseSymbols = Config.options.cheatsheet.useMouseSymbol ? root.mouseSymbolMap : {};
        return Object.assign({
            "SUPER": superKey,
            "Super": superKey,
            "super": superKey,
            "SUPER_L": "L" + superKey,
            "Super_L": "L" + superKey,
            "super_l": "L" + superKey,
            "SUPER_R": "R" + superKey,
            "Super_R": "R" + superKey,
            "super_r": "R" + superKey,
            "mouse_up": "Scroll ↓",
            "mouse_down": "Scroll ↑",
            "mouse:272": "LMB",
            "mouse:273": "RMB",
            "mouse:275": "MouseBack",
            "Slash": "/",
            "Hash": "#",
            "Return": "Enter"
        }, macSymbols, functionSymbols, mouseSymbols);
    }
    readonly property var parts: root.parseParts(root.shortcutText)
    readonly property real contentWidth: chordRow.implicitWidth + (root.compact ? 16 : 20)

    implicitWidth: Math.min(root.maximumWidth, root.contentWidth)
    implicitHeight: root.compact ? 28 : 32
    radius: Appearance.rounding.small
    color: root.capsuleColor
    clip: root.contentWidth > width
    Accessible.role: Accessible.StaticText
    Accessible.name: KeybindTokenizer.spokenDescription(root.shortcutText) || root.shortcutText

    function isSymbolToken(token): bool {
        const clean = String(token ?? "");
        return clean.toLowerCase().startsWith("super")
            || (Config.options.cheatsheet.useMacSymbol && Object.prototype.hasOwnProperty.call(root.macSymbolMap, clean))
            || (Config.options.cheatsheet.useFnSymbol && Object.prototype.hasOwnProperty.call(root.functionSymbolMap, clean))
            || (Config.options.cheatsheet.useMouseSymbol && Object.prototype.hasOwnProperty.call(root.mouseSymbolMap, clean));
    }

    function displayToken(token): var {
        const clean = String(token ?? "").trim();
        let matched = clean;
        if (!Object.prototype.hasOwnProperty.call(root.substitutions, matched)) {
            const lower = clean.toLowerCase();
            matched = Object.keys(root.substitutions).find(candidate => candidate.toLowerCase() === lower) ?? "";
        }
        return {
            display: matched ? root.substitutions[matched] : clean,
            icon: matched ? root.isSymbolToken(matched) : false
        };
    }

    function parseParts(value): var {
        const raw = String(value ?? "").trim();
        if (!raw)
            return [];
        return raw.split(/(\s*\/\s*|\s*\+\s*|\s+)/).filter(part => part.length > 0).map(part => {
            if (/^\s+$/.test(part))
                return { display: " ", icon: false };
            const clean = part.trim();
            if (clean === "+" || clean === "/")
                return { display: " " + clean + " ", icon: false };
            return root.displayToken(clean);
        });
    }

    Row {
        id: chordRow
        anchors.centerIn: parent
        spacing: 0

        Repeater {
            model: root.parts

            delegate: StyledText {
                required property var modelData
                anchors.verticalCenter: chordRow.verticalCenter
                text: modelData.display
                font.family: modelData.icon ? Appearance.font.family.iconNerd : Appearance.font.family.monospace
                font.pixelSize: Config.options.cheatsheet.fontSize.key
                font.weight: Font.Bold
                color: root.textColor
            }
        }
    }
}
