pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland

// Window actions stay declarative so the Search panel can filter, annotate and
// execute the same command without carrying a parallel switch statement.
Singleton {
    id: root

    readonly property var actions: [
        { id: "move.left", name: qsTr("Move left"), category: "tiling", icon: "arrow_back", keywords: ["left", "esquerda", "move"], keyHint: ["SUPER", "SHIFT", "←"], expression: target => `hl.dsp.window.move({ direction = "l", window = "address:${target}" })` },
        { id: "move.right", name: qsTr("Move right"), category: "tiling", icon: "arrow_forward", keywords: ["right", "direita", "move"], keyHint: ["SUPER", "SHIFT", "→"], expression: target => `hl.dsp.window.move({ direction = "r", window = "address:${target}" })` },
        { id: "move.up", name: qsTr("Move up"), category: "tiling", icon: "arrow_upward", keywords: ["up", "cima", "move"], keyHint: ["SUPER", "SHIFT", "↑"], expression: target => `hl.dsp.window.move({ direction = "u", window = "address:${target}" })` },
        { id: "move.down", name: qsTr("Move down"), category: "tiling", icon: "arrow_downward", keywords: ["down", "baixo", "move"], keyHint: ["SUPER", "SHIFT", "↓"], expression: target => `hl.dsp.window.move({ direction = "d", window = "address:${target}" })` },
        { id: "maximize", name: qsTr("Toggle maximize"), category: "window", icon: "fullscreen", keywords: ["maximize", "maximizar"], keyHint: ["SUPER", "D"], expression: target => `hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle", window = "address:${target}" })` },
        { id: "fullscreen", name: qsTr("Toggle fullscreen"), category: "window", icon: "fullscreen", keywords: ["fullscreen", "tela cheia"], keyHint: ["SUPER", "F"], expression: target => `hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle", window = "address:${target}" })` },
        { id: "float", name: qsTr("Float or tile"), category: "window", icon: "picture_in_picture", keywords: ["float", "floating", "flutuar", "tile"], keyHint: ["SUPER", "ALT", "Space"], expression: target => `hl.dsp.window.float({ action = "toggle", window = "address:${target}" })` },
        { id: "pin", name: qsTr("Toggle pin"), category: "window", icon: "keep", keywords: ["pin", "fixar"], keyHint: ["SUPER", "P"], expression: target => `hl.dsp.window.pin({ window = "address:${target}" })` },
        { id: "workspace.next", name: qsTr("Move to next workspace"), category: "workspace", icon: "arrow_forward", keywords: ["workspace", "next", "próximo", "mover"], keyHint: ["SUPER", "SHIFT", "PgDn"], expression: target => `hl.dsp.window.move({ workspace = "+1", follow = false, window = "address:${target}" })` },
        { id: "workspace.previous", name: qsTr("Move to previous workspace"), category: "workspace", icon: "arrow_back", keywords: ["workspace", "previous", "anterior", "mover"], keyHint: ["SUPER", "SHIFT", "PgUp"], expression: target => `hl.dsp.window.move({ workspace = "-1", follow = false, window = "address:${target}" })` },
        { id: "workspace.special", name: qsTr("Move to scratchpad"), category: "workspace", icon: "dashboard", keywords: ["workspace", "scratchpad", "special", "mover"], keyHint: [], expression: target => `hl.dsp.window.move({ workspace = "special:special", follow = false, window = "address:${target}" })` },
        { id: "monitor.left", name: qsTr("Move to left monitor"), category: "monitor", icon: "desktop_windows", keywords: ["monitor", "left", "esquerda", "mover"], keyHint: [], expression: target => `hl.dsp.window.move({ monitor = "l", window = "address:${target}" })` },
        { id: "monitor.right", name: qsTr("Move to right monitor"), category: "monitor", icon: "desktop_windows", keywords: ["monitor", "right", "direita", "mover"], keyHint: [], expression: target => `hl.dsp.window.move({ monitor = "r", window = "address:${target}" })` }
    ]

    function validTarget(targetAddress) {
        return /^0x[0-9a-f]+$/i.test(String(targetAddress ?? ""));
    }

    function execute(action, targetAddress) {
        if (!action || !root.validTarget(targetAddress))
            return false;
        Hyprland.dispatch(action.expression(targetAddress));
        return true;
    }
}
