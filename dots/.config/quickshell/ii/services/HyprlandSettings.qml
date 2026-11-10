pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

/**
 * Shell animation previews and the specs persisted by Settings -> Windows.
 * Live eval provides immediate feedback; custom/general.lua preserves the saved
 * window preset across compositor reloads and sessions without a running shell.
 */
Singleton {
    id: root

    readonly property var allowedLeaves: [
        "global", "windows", "windowsIn", "windowsOut", "windowsMove",
        "fadeIn", "fadeOut", "fadeSwitch", "fadeShadow", "fadeDim", "fadeLayers",
        "fadeLayersIn", "fadeLayersOut", "layers", "layersIn", "layersOut",
        "workspaces", "workspacesIn", "workspacesOut", "specialWorkspace",
        "specialWorkspaceIn", "specialWorkspaceOut", "border", "borderangle",
        "zoomFactor", "fadePopups", "fadePopupsIn", "fadePopupsOut"
    ]

    /// Window open/close presets offered in Settings -> Windows.
    readonly property var appLaunchStyles: ["scale", "slide"]
    readonly property var slideDirections: ["bottom", "top", "left", "right"]

    /// One `hl.animation` statement, or "" when an argument is unsafe.
    function animationLua(leaf, enabled, speed, curve, style) {
        if (typeof leaf !== "string" || !root.allowedLeaves.includes(leaf)) {
            console.error("[HyprlandSettings] Invalid animation leaf:", leaf);
            return "";
        }
        const numSpeed = Number(speed);
        if (isNaN(numSpeed) || numSpeed <= 0 || numSpeed > 50) {
            console.error("[HyprlandSettings] Invalid animation speed:", speed);
            return "";
        }
        const curveName = curve ? String(curve).trim() : "";
        if (/[^a-zA-Z0-9_-]/.test(curveName)) {
            console.error("[HyprlandSettings] Unsafe characters in curve name:", curve);
            return "";
        }
        if (style && /[^a-zA-Z0-9_% ]/.test(String(style))) {
            console.error("[HyprlandSettings] Unsafe characters in animation style:", style);
            return "";
        }

        let luaExpr = "hl.animation({ leaf = '" + leaf + "', enabled = " + (enabled ? "true" : "false") + ", speed = " + numSpeed.toFixed(2);
        if (curveName !== "")
            luaExpr += ", bezier = '" + curveName + "'";
        if (style && String(style).trim() !== "")
            luaExpr += ", style = '" + String(style).trim() + "'";
        return luaExpr + " })";
    }

    function changeAnimationSpec(leaf, enabled, speed, curve, style) {
        const luaExpr = root.animationLua(leaf, Boolean(enabled), speed, curve, style);
        if (luaExpr !== "")
            Quickshell.execDetached(["hyprctl", "eval", luaExpr]);
    }

    function bezierLua(name, x0, y0, x1, y1) {
        return "hl.curve('" + name + "', { type = 'bezier', points = { {" + x0 + ", " + y0 + "}, {" + x1 + ", " + y1 + "} } })";
    }

    property var _pendingLaunchAnimation: null

    /// Sliders report every step while dragged; only the value they settle on is sent.
    function updateAppLaunchAnimation(anim) {
        root._pendingLaunchAnimation = anim;
        launchAnimationDebounce.restart();
    }

    Timer {
        id: launchAnimationDebounce
        interval: 120
        onTriggered: root.pushAppLaunchAnimation(root._pendingLaunchAnimation)
    }

    /**
     * Beziers only, on purpose. Hyprland 0.56 has spring curves, but when a window's goal
     * changes mid-animation - which dwindle does while a new tile settles - hyprutils only
     * rescales the spring's velocity for plain numbers. Position and size are vectors, so they
     * keep the old velocity and swing sideways. A bezier restarts cleanly from where it is.
     */
    function appLaunchEntries(anim) {
        if (!anim || typeof anim !== "object")
            return [];
        const isEnabled = anim.enable !== false;
        const style = root.appLaunchStyles.includes(anim.style) ? anim.style : "scale";
        const percent = Math.max(5, Math.min(95, Math.round(Number(anim.startPercent) || 20)));
        // Hyprland's speed is the duration in tenths of a second.
        const speed = Math.max(1, Math.min(10, Number(anim.speed) || 4));
        const direction = root.slideDirections.includes(anim.slideDirection) ? anim.slideDirection : "";

        // Curves first: an animation naming a curve Hyprland does not know yet is rejected,
        // and separate hyprctl calls give no ordering guarantee, so it all goes in one chunk.
        const entries = [
            root.curveEntry("iiAppOpen", 0.22, 1, 0.36, 1),
            root.curveEntry("iiAppSlide", 0.3, 0.7, 0.1, 1),
            root.curveEntry("iiAppClose", 0.32, 0.72, 0, 1),
            root.curveEntry("iiAppFade", 0.2, 0.6, 0.35, 1)
        ];

        const openCurve = style === "slide" ? "iiAppSlide" : "iiAppOpen";
        // The slide needs a moment longer to cover its distance.
        const openSpeed = style === "slide" ? speed * 1.12 : speed;
        // Slides fade in quicker, so the travel is seen rather than hidden behind transparency.
        const fadeInSpeed = style === "slide" ? speed * 0.5 : speed * 0.7;
        const openStyle = style === "slide" ? ("slide " + direction).trim() : ("popin " + percent + "%");
        const outPercent = Math.min(90, Math.round(percent + (100 - percent) * 0.5));
        const closeStyle = style === "slide" ? ("slide " + direction).trim() : ("popin " + outPercent + "%");

        if (isEnabled) {
            entries.push(root.animationEntry("windowsIn", true, openSpeed, openCurve, openStyle));
            entries.push(root.animationEntry("fadeIn", true, fadeInSpeed, "iiAppFade", ""));
            entries.push(root.animationEntry("windowsOut", true, speed * 0.65, "iiAppClose", closeStyle));
            entries.push(root.animationEntry("fadeOut", true, speed * 0.65, "iiAppClose", ""));
            entries.push(root.animationEntry("windowsMove", true, speed, "iiAppOpen", "slide"));
        } else {
            entries.push(root.animationEntry("windowsIn", false, speed, "iiAppOpen", "popin 100%"));
            entries.push(root.animationEntry("fadeIn", false, speed, "iiAppOpen", ""));
            entries.push(root.animationEntry("windowsOut", false, speed, "iiAppOpen", "popin 100%"));
            entries.push(root.animationEntry("fadeOut", false, speed, "iiAppOpen", ""));
            entries.push(root.animationEntry("windowsMove", true, 3, "emphasizedDecel", "slide"));
        }
        return entries;
    }

    function curveEntry(name, x0, y0, x1, y1) {
        return { kind: "curve", id: name, name: name,
            spec: { type: "bezier", points: [[x0, y0], [x1, y1]] } };
    }

    function animationEntry(leaf, enabled, speed, curve, style) {
        const spec = { leaf: leaf, enabled: enabled, speed: Number(speed.toFixed(2)), bezier: curve };
        if (style) spec.style = style;
        return { kind: "animation", id: leaf, spec: spec };
    }

    function pushAppLaunchAnimation(anim) {
        const entries = root.appLaunchEntries(anim);
        if (entries.length === 0) return;
        const lua = entries.map(entry => {
            const spec = entry.spec;
            if (entry.kind === "curve")
                return root.bezierLua(entry.name, spec.points[0][0], spec.points[0][1], spec.points[1][0], spec.points[1][1]);
            return root.animationLua(spec.leaf, spec.enabled, spec.speed, spec.bezier, spec.style);
        });

        if (lua.includes(""))
            return;
        root._launchAnimationLua = lua.join("; ");
        if (launchAnimationProc.running) {
            root._launchAnimationQueued = true;
            return;
        }
        launchAnimationProc.command = ["hyprctl", "eval", root._launchAnimationLua];
        launchAnimationProc.running = true;
    }

    property string _launchAnimationLua: ""
    property bool _launchAnimationQueued: false

    // Not execDetached: Hyprland answers anything but "ok" with the reason, and a rejected
    // chunk otherwise leaves the old animations in place with nothing in the log.
    Process {
        id: launchAnimationProc
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim() !== "ok")
                    console.error("[HyprlandSettings] Window animation push rejected:", text.trim(), "\n", launchAnimationProc.command[2]);
            }
        }
        onExited: {
            if (!root._launchAnimationQueued)
                return;
            root._launchAnimationQueued = false;
            launchAnimationProc.command = ["hyprctl", "eval", root._launchAnimationLua];
            launchAnimationProc.running = true;
        }
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
            // Keep an unsaved preview active through unrelated reloads. Saved presets also
            // live in custom/general.lua, so restoring them no longer needs this event.
            if (Config.ready)
                root.updateAppLaunchAnimation(Config.options.appearance.appLaunchAnimation);
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
