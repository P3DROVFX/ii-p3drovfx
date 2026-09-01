pragma Singleton

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

/**
 * The animation specs the shell pushes into Hyprland, and one thing it needs to read back.
 *
 * Everything here is written with `hyprctl eval`, which is deliberate: these are the shell's
 * own presentation, re-asserted after every reload, and they must never end up in a config
 * file where they would outlive the setting that produced them. Settings -> Hyprland is the
 * other direction - it writes files, and it owns everything that is a Hyprland setting rather
 * than a shell one.
 */
Singleton {
    id: root

    function changeAnimationSpec(leaf, enabled, speed, curve, style) {
        const allowedLeaves = [
            "global", "windows", "windowsIn", "windowsOut", "windowsMove",
            "fadeIn", "fadeOut", "fadeSwitch", "fadeShadow", "fadeDim", "fadeLayers",
            "fadeLayersIn", "fadeLayersOut", "layers", "layersIn", "layersOut",
            "workspaces", "workspacesIn", "workspacesOut", "specialWorkspace",
            "specialWorkspaceIn", "specialWorkspaceOut", "border", "borderangle",
            "zoomFactor", "fadePopups", "fadePopupsIn", "fadePopupsOut"
        ];
        if (typeof leaf !== "string" || !allowedLeaves.includes(leaf)) {
            console.error("[HyprlandSettings] Invalid animation leaf:", leaf);
            return;
        }
        const isEnabled = Boolean(enabled);
        const numSpeed = Number(speed);
        if (isNaN(numSpeed) || numSpeed <= 0 || numSpeed > 50) {
            console.error("[HyprlandSettings] Invalid animation speed:", speed);
            return;
        }
        if (curve && /[^a-zA-Z0-9_-]/.test(String(curve))) {
            console.error("[HyprlandSettings] Unsafe characters in curve name:", curve);
            return;
        }
        if (style && /[^a-zA-Z0-9_% ]/.test(String(style))) {
            console.error("[HyprlandSettings] Unsafe characters in animation style:", style);
            return;
        }

        let luaExpr = "hl.animation({ leaf = '" + leaf + "', enabled = " + (isEnabled ? "true" : "false") + ", speed = " + numSpeed.toFixed(2);
        if (curve && String(curve).trim() !== "") {
            luaExpr += ", bezier = '" + String(curve).trim() + "'";
        }
        if (style && String(style).trim() !== "") {
            luaExpr += ", style = '" + String(style).trim() + "'";
        }
        luaExpr += " })";

        Quickshell.execDetached(["hyprctl", "eval", luaExpr]);
    }

    function updateAppLaunchAnimation(enabled, startPercent, speed, curve) {
        const isEnabled = enabled !== false;
        const percent = Math.max(5, Math.min(100, Math.round(Number(startPercent) || 20)));
        const animSpeed = Math.max(0.5, Math.min(20, Number(speed) || 3.2));
        const animCurve = (typeof curve === "string" && curve.trim() !== "") ? curve.trim() : "iiAppOpen";

        const inStyle = isEnabled ? ("popin " + percent + "%") : "popin 100%";
        const outPercent = Math.min(90, Math.round(percent + (100 - percent) * 0.5));
        const outStyle = isEnabled ? ("popin " + outPercent + "%") : "popin 100%";
        changeAnimationSpec("windowsIn", isEnabled, animSpeed, animCurve, inStyle);
        changeAnimationSpec("fadeIn", isEnabled, animSpeed, animCurve, "");
        changeAnimationSpec("windowsOut", isEnabled, animSpeed, animCurve, outStyle);
        changeAnimationSpec("fadeOut", isEnabled, animSpeed, animCurve, "");
    }

    function changeAnimation(animName, style) {
        changeAnimationSpec(animName, true, 7, "menu_decel", style);
    }

    /**
     * Mirrors Hyprland's tiling engine into the stored state.
     *
     * Half a dozen widgets - the wallpaper, the workspace strip, the overview, the search drop -
     * lay themselves out differently under the scrolling layout, and they all read it from here
     * rather than asking the compositor themselves. Nothing had written it since the CLI that
     * used to do so stopped existing, so every one of them had been reading the default.
     */
    Process {
        id: layoutProbe
        command: ["hyprctl", "getoption", "general:layout", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (!Persistent.ready) return;
                let layout = "";
                try {
                    layout = String(JSON.parse(text)?.str ?? "").trim();
                } catch (e) {
                    return;
                }
                // An empty answer means hyprctl failed, not that there is no layout. Keeping the
                // last known one is better than telling everything the layout just changed.
                if (layout === "" || Persistent.states.hyprland.layout === layout) return;
                Persistent.states.hyprland.layout = layout;
            }
        }
    }

    // One config write produces a handful of reload events; re-reading on each would run hyprctl
    // six times for one change.
    Timer {
        id: layoutDebounce
        interval: 300
        onTriggered: layoutProbe.running = true
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name !== "configreloaded") return;
            layoutDebounce.restart();
        }
    }

    // Persistent loads asynchronously, and on a cold start it is usually still reading when this
    // singleton is built - the first probe would then have nowhere to put its answer.
    Connections {
        target: Persistent
        function onReadyChanged() {
            if (Persistent.ready) layoutDebounce.restart();
        }
    }

    Component.onCompleted: layoutDebounce.restart()
}
