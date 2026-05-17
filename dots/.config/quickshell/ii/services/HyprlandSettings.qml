pragma Singleton

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import qs

Singleton {
    id: root

    readonly property string hyprlandConfigPath: Directories.home.replace("file://", "") + "/.local/share/ii-vynx/hyprland.conf"

    Process {
        id: configWriter
        property string pendingCommand: ""

        command: ["bash", "-c", pendingCommand]

        onExited: function (exitCode) {
            if (exitCode !== 0) {
                console.error("[HyprlandSettings] changeKey failed, exitCode:", exitCode);
            }
        }
    }

    function changeKey(key, value) {
        if (configWriter.running) {
            console.warn("[HyprlandConfig] Writer busy, skipping");
            return;
        }

        if (/['"\\`$|&;]/.test(String(value)) || /['"\\`$|&;]/.test(String(key))) {
            console.error("[HyprlandConfig] Unsafe characters rejected:", key, value);
            return;
        }

        const tmpPath = "/tmp/hypr_config_write.tmp";
        const path = root.hyprlandConfigPath;
        let sedCmd = "";

        if (key.includes(":")) {
            const parts = key.split(":");
            const section = parts[0].trim();
            const field = parts[1].trim();

            sedCmd = `sed -E '/^${section}[[:space:]]*[{]/,/^[}]/ s|^([[:space:]]*${field}[[:space:]]*=[[:space:]]*).*|\\1${value}|' '${path}' > '${tmpPath}' && mv '${tmpPath}' '${path}'`;
        } else {
            sedCmd = `sed -E 's|^([[:space:]]*${key}[[:space:]]*=[[:space:]]*).*|\\1${value}|' '${path}' > '${tmpPath}' && mv '${tmpPath}' '${path}'`;
        }

        //console.log("[HyprlandSettings] Running command:", sedCmd)
        configWriter.pendingCommand = sedCmd;
        configWriter.startDetached();
    }

    function setLayout(layout) {
        if (layout !== "default" && layout !== "scrolling" && layout !== "dwindle" && layout !== "monocle" && layout !== "master")
            return;
        // console.log("[HyprlandSettings] Setting layout to", layout)
        changeKey("general:layout", layout);
        Persistent.states.hyprland.layout = layout;
    }

    function setRounding(rounding) {
        changeKey("decoration:rounding", rounding);
    }
}
