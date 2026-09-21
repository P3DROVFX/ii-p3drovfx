pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions

/**
 * Everything a bar workspace widget knows about Hyprland, for one screen.
 *
 * Every style draws from one of these instead of keeping its own copy. It is
 * all bindings on purpose: the styles used to fill their state from signal
 * handlers, and a widget created after the signal had fired (the bar is
 * rebuilt whenever it hides) sat on empty state until the next Hyprland event.
 *
 * Derived arrays and maps go through `ObjectUtils.keep`, so a recompute that
 * lands on the same content hands back the same object. A Repeater whose model
 * is a fresh array rebuilds every delegate, and the window list changes on
 * every title update.
 */
QtObject {
    id: model

    required property var screen

    // Window data is only built for styles that draw it.
    property bool trackWindows: false
    property bool includeFloating: true
    // Windows kept per workspace, leftmost first. `windowCounts` is never capped.
    property int windowLimit: 3

    readonly property var cfg: Config.options.bar.workspaces
    readonly property int shown: Math.max(1, model.cfg.shown)
    readonly property bool dynamic: model.cfg.dynamicWorkspaces

    // ── Monitor ───────────────────────────────────────────────────────────
    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(model.screen)
    readonly property var monitorData: HyprlandData.monitors.find(mon => mon.name === model.monitor?.name) ?? null
    readonly property int monitorIndex: {
        const idx = HyprlandData.monitors.findIndex(mon => mon.name === model.monitor?.name);
        return Math.max(0, idx);
    }
    readonly property bool scratchpadOpen: !!model.monitorData?.specialWorkspace?.name

    // ── The range of workspace ids this bar owns ──────────────────────────
    // With a workspace map, each monitor owns the ids after its own entry and
    // up to the next monitor's; the last one owns everything after its start.
    readonly property bool useMap: model.cfg.useWorkspaceMap
    readonly property int offset: {
        if (!model.useMap)
            return 0;
        return model.cfg.workspaceMap[model.monitorIndex] ?? model.monitorIndex * model.shown;
    }
    readonly property int rangeStart: model.offset + 1
    // Inclusive; -1 when unbounded.
    readonly property int rangeEnd: model.useMap ? (model.cfg.workspaceMap[model.monitorIndex + 1] ?? -1) : -1

    function inRange(id) {
        return id >= model.rangeStart && (model.rangeEnd < 0 || id <= model.rangeEnd);
    }

    readonly property int activeId: model.monitor?.activeWorkspace?.id ?? model.rangeStart

    // First id of the page of `size` that holds the active workspace.
    function pageStart(size) {
        let active = Math.max(model.activeId, model.rangeStart);
        if (model.rangeEnd >= 0)
            active = Math.min(active, model.rangeEnd);
        return Math.floor((active - model.rangeStart) / size) * size + model.rangeStart;
    }

    readonly property int pageStartId: model.pageStart(model.shown)

    // ── Which workspaces are on show ──────────────────────────────────────
    // Fixed: the page of `shown` ids around the active one. Dynamic: every
    // workspace that exists in range, plus the active one.
    readonly property var visibleIds: {
        if (!model.dynamic)
            return ObjectUtils.keep(model._memo, "visibleIds",
                Array.from({ length: model.shown }, (_, i) => model.pageStartId + i));

        const ids = [];
        for (const id of HyprlandData.workspaceIds) {
            if (id >= 1 && model.inRange(id) && !ids.includes(id))
                ids.push(id);
        }
        if (model.inRange(model.activeId) && !ids.includes(model.activeId))
            ids.push(model.activeId);
        ids.sort((a, b) => a - b);
        return ObjectUtils.keep(model._memo, "visibleIds", ids);
    }

    readonly property int activeIndex: model.visibleIds.indexOf(model.activeId)

    // A workspace exists in Hyprland only while something holds it open.
    // Read from the `hyprctl workspaces` dump, not `Hyprland.workspaces`: that
    // list keeps workspaces Hyprland has already destroyed (a compaction empties
    // several at once) and leaves ids at -1 for workspaces it only knows by name.
    readonly property var occupied: {
        const ids = {};
        for (const id of HyprlandData.workspaceIds)
            ids[id] = true;
        return ObjectUtils.keep(model._memo, "occupied", ids);
    }

    // ── Windows ───────────────────────────────────────────────────────────
    // workspace id -> [{ icon }], leftmost first, at most `windowLimit`.
    readonly property var windows: model._windowData.windows
    // workspace id -> window count.
    readonly property var windowCounts: model._windowData.counts

    readonly property var _windowData: {
        if (!model.trackWindows)
            return model._emptyWindowData;

        // Re-resolve every icon when the icon theme regenerates.
        void TaskbarApps.iconThemeRevision;

        const monitorId = model.monitorData?.id;
        const list = HyprlandData.windowList.filter(win => win.monitor === monitorId
            && (win.workspace?.id ?? 0) >= 1
            && (model.includeFloating || !win.floating));
        list.sort((a, b) => a.at[0] - b.at[0] || a.at[1] - b.at[1]);

        const iconByClass = {};
        const windows = {};
        const counts = {};
        for (const win of list) {
            const wsId = win.workspace.id;
            counts[wsId] = (counts[wsId] ?? 0) + 1;
            if (!windows[wsId])
                windows[wsId] = [];
            if (windows[wsId].length >= model.windowLimit)
                continue;
            if (!(win.class in iconByClass))
                iconByClass[win.class] = Quickshell.iconPath(AppSearch.guessIcon(win.class), "image-missing");
            windows[wsId].push({ "icon": iconByClass[win.class] });
        }
        // Per workspace, so a window moving on one workspace leaves the
        // others' icon rows alone.
        for (const wsId in windows)
            windows[wsId] = ObjectUtils.keep(model._memo, "windows:" + wsId, windows[wsId]);

        return {
            "windows": ObjectUtils.keep(model._memo, "windows", windows),
            "counts": ObjectUtils.keep(model._memo, "counts", counts)
        };
    }

    readonly property var _emptyWindowData: ({ "windows": {}, "counts": {} })
    property var _memo: ({})

    // ── Labels ────────────────────────────────────────────────────────────
    function labelFor(id) {
        const map = model.cfg?.numberMap ?? [];
        return String(map[id - 1] || id);
    }

    // Numbers show while Super is held (after a short delay) or always.
    property bool _superHeldLongEnough: false
    readonly property bool numbersByInteraction: model._superHeldLongEnough
        && !GlobalStates.screenLocked
        && !GlobalStates.workspaceRestoreInProgress
    readonly property bool showNumbers: !GlobalStates.screenLocked
        && !GlobalStates.workspaceRestoreInProgress
        && (model.cfg.alwaysShowNumbers || model._superHeldLongEnough)

    property Timer _numbersTimer: Timer {
        interval: model.cfg.showNumberDelay ?? 100
        onTriggered: model._superHeldLongEnough = true
    }

    property Connections _superWatcher: Connections {
        target: GlobalStates

        function onSuperDownChanged() {
            if (!Config.options.bar.autoHide.showWhenPressingSuper.enable)
                return;
            if (GlobalStates.superDown) {
                model._numbersTimer.restart();
                return;
            }
            model._numbersTimer.stop();
            model._superHeldLongEnough = false;
        }

        function onSuperReleaseMightTriggerChanged() {
            model._numbersTimer.stop();
        }
    }

    // ── Random active-indicator shape ─────────────────────────────────────
    readonly property list<string> shapes: ["Circle", "Square", "Slanted", "Arch", "Arrow", "SemiCircle",
        "Oval", "Pill", "Triangle", "Diamond", "ClamShell", "Pentagon", "Gem", "Sunny", "VerySunny",
        "Cookie4Sided", "Cookie6Sided", "Cookie7Sided", "Cookie9Sided", "Cookie12Sided", "Ghostish",
        "Clover4Leaf", "Clover8Leaf", "Burst", "SoftBurst", "Flower", "Puffy", "PuffyDiamond",
        "PixelCircle", "Bun", "Heart"]
    readonly property bool useRandomShape: model.cfg.useRandomShapeForActiveIndicator
    property string randomShape: "Circle"
    property real randomRotation: 0

    onActiveIdChanged: {
        if (!model.useRandomShape)
            return;
        let next = model.randomShape;
        while (next === model.randomShape)
            next = model.shapes[Math.floor(Math.random() * model.shapes.length)];
        model.randomShape = next;
        model.randomRotation += 90;
    }

    // ── Actions ───────────────────────────────────────────────────────────
    function focus(id) {
        Hyprland.dispatch("hl.dsp.focus({ workspace = '" + id + "' })");
    }

    // Wheel down moves forward, staying inside this bar's range. The target is
    // absolute on purpose: one notch can arrive as several wheel events, and a
    // relative `r+1` per event skipped a workspace for each extra one.
    function scroll(angleDelta) {
        if (angleDelta === 0)
            return;
        const forward = angleDelta < 0;
        const next = model.activeId + (forward ? 1 : -1);
        if (next >= 1 && model.inRange(next))
            model.focus(next);
    }

    function toggleScratchpad() {
        Hyprland.dispatch(`hl.dsp.workspace.toggle_special("special")`);
    }
}
