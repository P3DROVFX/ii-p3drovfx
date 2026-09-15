pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

Singleton {
    id: root

    property bool active: false

    readonly property var overrides: {
        const opts = Config.options.gameMode;
        const settings = {};
        if (opts.disableAnimations)
            settings["animations:enabled"] = 0;
        if (opts.disableShadows)
            settings["decoration:shadow:enabled"] = 0;
        if (opts.disableBlur)
            settings["decoration:blur:enabled"] = 0;
        if (opts.removeGaps) {
            settings["general:gaps_in"] = 0;
            settings["general:gaps_out"] = 0;
        }
        if (opts.setBorderSize)
            settings["general:border_size"] = opts.borderSize;
        if (opts.disableRounding)
            settings["decoration:rounding"] = 0;
        if (opts.enableTearing)
            settings["general:allow_tearing"] = 1;
        return settings;
    }

    function toggle() {
        root.setActive(!root.active);
    }

    function setActive(active: bool) {
        root.active = active;
        if (active) {
            HyprlandConfig.setMany(root.overrides);
        } else {
            HyprlandConfig.resetMany(Object.keys(root.overrides));
        }
    }

    Process {
        id: fetchState
        running: true
        command: ["bash", "-c", `grep -q '^hl\\.config(' "${HyprlandConfig.shellOverridesPath}"`]
        onExited: exitCode => {
            root.active = exitCode === 0;
        }
    }

    Connections {
        target: HyprlandConfig
        function onReloaded() {
            fetchState.running = true;
        }
    }
}
