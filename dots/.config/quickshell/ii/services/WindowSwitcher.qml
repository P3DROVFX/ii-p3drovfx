pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.modules.common

/**
 * Alt+Tab: the window list, its order, the selection, and committing or cancelling it.
 *
 * Both faces of the switcher - the Dynamic Island's icon row and the floating panel of
 * thumbnails - are views on this one object. They read `entries` and `selectedIndex`, and
 * call `select()`/`activate()` for the pointer; every key arrives here.
 *
 * ## Keys
 *
 * Hyprland matches binds before any surface sees a key, and taking keyboard focus to hear
 * Alt come up would take it away from the window being switched *from* on every tap (and
 * would lose the release outright while the surface is still being built). So the switcher
 * never holds the keyboard. Alt+Tab is a bind whose Lua function enters a submap in the same
 * compositor call - no round trip the release could overtake - and inside the submap Tab,
 * Shift+Tab, the arrows, Q, Enter and Escape are binds too, with a catch-all swallowing the
 * rest so nothing typed mid-switch lands in the window being left. Each one reaches this object
 * as a global shortcut, in order. Pointer input is not affected: hover and click still work.
 *
 * Alt coming up is the subtle one. Hyprland matches a release against the submap the key was
 * *pressed* in, and Alt went down before the submap was entered, so the release bind lives in
 * the root submap (transparent, so nothing else loses the key) and acts only while ours is
 * current. Both it and Escape leave the submap inside the compositor before telling the shell,
 * so a shell that died mid-switch can never strand the keyboard in it.
 *
 * The binds are put on at runtime rather than written into keybinds.lua: they come and go
 * with the setting, and an Alt+Tab the user bound themselves is left alone (`conflict`).
 */
Singleton {
    id: root

    readonly property var options: Config.options?.windowSwitcher ?? null
    readonly property bool enabled: Config.ready && root.options?.enable === true
    readonly property bool includeOtherWorkspaces: root.options?.includeOtherWorkspaces ?? true

    /// Shown this long after Alt+Tab; a release before then switches without any UI at all.
    readonly property int quickTapMs: 150

    // ------------------------------------------------------------------ state

    /// Between Alt+Tab and the release: the submap is engaged and a snapshot exists.
    property bool active: false
    /// The UI is on screen (after `quickTapMs`).
    property bool shown: false
    /// The windows, most recently used first. Plain objects; see `entryFor`.
    property var entries: []
    property int selectedIndex: 0
    readonly property var selectedEntry: root.entries[root.selectedIndex] ?? null
    readonly property int count: root.entries.length
    /// Where it opened: the monitor holding the keyboard at Alt+Tab.
    property string screenName: ""
    /// "island" or "panel", frozen at open so a setting changing mid-switch cannot swap faces.
    property string presenter: "panel"
    /// The panel's columns, for Up/Down. 0 (the island's single row) makes them Left/Right.
    property int columns: 0
    /// Bumped on every open, so a view can restart its entrance even if it never unloaded.
    property int openSerial: 0

    /// An Alt+Tab bind that is not ours is in the way; the switcher stays unbound.
    property bool conflict: false

    // ------------------------------------------------------------------ the model

    function normalisedAddress(raw): string {
        const text = String(raw ?? "").trim();
        if (text.length === 0)
            return "";
        return text.startsWith("0x") ? text : `0x${text}`;
    }

    function toplevelsByAddress(): var {
        const map = {};
        for (const toplevel of (ToplevelManager.toplevels?.values ?? [])) {
            const address = root.normalisedAddress(toplevel?.HyprlandToplevel?.address);
            if (address.length > 0)
                map[address] = toplevel;
        }
        return map;
    }

    function entryFor(client, toplevels): var {
        const address = root.normalisedAddress(client.address);
        const workspace = client.workspace ?? {};
        return {
            "address": address,
            "toplevel": toplevels[address] ?? null,
            "appClass": String(client.class || client.initialClass || ""),
            "title": String(client.title || client.initialTitle || ""),
            "workspaceId": Number(workspace.id ?? 0),
            "workspaceName": String(workspace.name ?? ""),
            "special": Number(workspace.id ?? 0) < 0,
            "monitor": Number(client.monitor ?? -1),
            "width": Math.max(1, Number(client.size?.[0] ?? 16)),
            "height": Math.max(1, Number(client.size?.[1] ?? 9)),
            "fullscreen": Number(client.fullscreen ?? 0) > 0,
            "focusOrder": Number(client.focusHistoryID ?? 9999)
        };
    }

    function wanted(client): bool {
        if (!client || client.mapped === false)
            return false;
        const workspaceId = Number(client.workspace?.id ?? NaN);
        // -1 is "no workspace": a window being torn down, or not placed yet.
        if (!isFinite(workspaceId) || workspaceId === -1)
            return false;
        if (root.includeOtherWorkspaces)
            return true;
        return HyprlandData.visibleWorkspaceIds.some(id => id === workspaceId);
    }

    /**
     * The order, most recently used first.
     *
     * `focusHistoryID` is Hyprland's own focus stack, but HyprlandData refreshes it with a
     * `hyprctl clients` round trip after each focus change, so a second Alt+Tab straight after
     * the first would still see the old order and send you back where you started. The active
     * window, though, comes off the event socket the moment it changes - so it goes first, and
     * the stale stack orders the rest, which is right for any number of quick re-taps.
     */
    function snapshot(): var {
        const toplevels = root.toplevelsByAddress();
        const list = (HyprlandData.windowList ?? []).filter(client => root.wanted(client))
            .map(client => root.entryFor(client, toplevels));
        list.sort((a, b) => a.focusOrder - b.focusOrder);
        const active = root.normalisedAddress(Hyprland.activeToplevel?.address);
        const at = list.findIndex(entry => entry.address === active);
        if (at > 0)
            list.unshift(list.splice(at, 1)[0]);
        return list;
    }

    /**
     * A window list that changed under an open switcher. Order and selection stay put: a
     * switcher reshuffling while you aim at it is worse than a slightly stale one. Windows
     * that went away leave, new ones join at the end, titles follow.
     */
    function reconcile(): void {
        if (!root.active)
            return;
        const toplevels = root.toplevelsByAddress();
        const clients = {};
        for (const client of (HyprlandData.windowList ?? [])) {
            if (root.wanted(client))
                clients[root.normalisedAddress(client.address)] = client;
        }
        const selected = root.selectedEntry?.address ?? "";
        const kept = [];
        for (const entry of root.entries) {
            const client = clients[entry.address];
            if (!client)
                continue;
            kept.push(root.entryFor(client, toplevels));
            delete clients[entry.address];
        }
        for (const address in clients)
            kept.push(root.entryFor(clients[address], toplevels));
        root.replaceEntries(kept, selected);
    }

    function removeAddress(address: string): void {
        if (!root.active)
            return;
        const selected = root.selectedEntry?.address ?? "";
        root.replaceEntries(root.entries.filter(entry => entry.address !== address), selected);
    }

    function replaceEntries(list: var, selectedAddress: string): void {
        const oldIndex = root.selectedIndex;
        root.entries = list;
        if (list.length === 0) {
            root.selectedIndex = 0;
            // Nothing left to switch to. The submap stays until Alt comes up (it would anyway,
            // and leaving it here would hand the held Tab to a window), but the UI goes.
            root.shown = false;
            showTimer.stop();
            return;
        }
        const at = list.findIndex(entry => entry.address === selectedAddress);
        // The selected window closed: its neighbour moves up into the same slot.
        root.selectedIndex = at >= 0 ? at : Math.min(oldIndex, list.length - 1);
    }

    // ------------------------------------------------------------------ actions

    function open(direction: int): void {
        const list = root.snapshot();
        root.screenName = Hyprland.focusedMonitor?.name ?? "";
        root.presenter = GlobalStates.islandOwnsWindowSwitcher ? "island" : "panel";
        root.entries = list;
        root.selectedIndex = list.length < 2 ? 0 : (direction > 0 ? 1 : list.length - 1);
        root.pointerOrigin = null;
        root.pointerLive = false;
        root.openSerial++;
        root.active = true;
        if (list.length > 0)
            showTimer.restart();
    }

    function step(delta: int): void {
        if (!root.active) {
            root.open(delta >= 0 ? 1 : -1);
            return;
        }
        const n = root.entries.length;
        if (n === 0)
            return;
        root.selectedIndex = ((root.selectedIndex + delta) % n + n) % n;
    }

    function stepRow(delta: int): void {
        // The panel's last grid can outlive it; the island is always one row.
        const columns = root.presenter === "panel" ? root.columns : 0;
        if (columns <= 0 || root.entries.length <= columns) {
            root.step(delta);
            return;
        }
        const n = root.entries.length;
        const next = root.selectedIndex + delta * columns;
        // Off the grid vertically: wrap to the same column on the other edge.
        if (next >= n)
            root.selectedIndex = root.selectedIndex % columns;
        else if (next < 0) {
            const column = root.selectedIndex % columns;
            const lastRowStart = Math.floor((n - 1) / columns) * columns;
            root.selectedIndex = Math.min(n - 1, lastRowStart + column);
        } else
            root.selectedIndex = next;
    }

    /// Pointer hover. Only while the UI is up: an armed, invisible switcher has nothing to hover.
    function select(index: int): void {
        if (root.shown && index >= 0 && index < root.entries.length)
            root.selectedIndex = index;
    }

    property var pointerOrigin: null
    property bool pointerLive: false

    /**
     * Hover selects - once the pointer has actually moved. The switcher opens under wherever
     * the cursor happens to rest, and a card appearing under it (or sliding under it when a
     * window closes) is not the user pointing at anything. `scenePos` is in window coordinates.
     */
    function hover(index: int, scenePos: point): void {
        if (!root.shown)
            return;
        if (!root.pointerLive) {
            if (!root.pointerOrigin) {
                root.pointerOrigin = scenePos;
                return;
            }
            if (Math.abs(scenePos.x - root.pointerOrigin.x) + Math.abs(scenePos.y - root.pointerOrigin.y) < 4)
                return;
            root.pointerLive = true;
        }
        root.select(index);
    }

    /// A click: commit to that window. Alt is still down, so the shell leaves the submap itself.
    function activate(index: int): void {
        if (!root.active || index < 0 || index >= root.entries.length)
            return;
        root.selectedIndex = index;
        root.leaveSubmap();
        root.commit();
    }

    function commit(): void {
        if (!root.active)
            return;
        const entry = root.selectedEntry;
        root.finish();
        if (!entry)
            return;
        const current = root.normalisedAddress(Hyprland.activeToplevel?.address);
        // Focusing a window on a hidden special workspace pulls that workspace over the screen,
        // and one on another workspace switches there - both done by Hyprland's own focus.
        if (entry.address !== current || entry.special)
            Hyprland.dispatch(`hl.dsp.focus({ window = "address:${entry.address}" })`);
    }

    function cancel(): void {
        root.finish();
    }

    /// Q: ask the selected window to close. It leaves the list when it really goes - an app
    /// asking "save changes?" stays, as it should.
    function closeSelected(): void {
        const entry = root.selectedEntry;
        if (root.shown && entry)
            Hyprland.dispatch(`hl.dsp.window.close({ window = "address:${entry.address}" })`);
    }

    function finish(): void {
        // Set before anything closes, so a view picking an animation for the way out sees it.
        if (root.active) {
            root.settling = true;
            settleTimer.restart();
        }
        showTimer.stop();
        root.active = false;
        root.shown = false;
    }

    /// Just closed: the faces are animating back. Lets a view keep the switcher's timing.
    property bool settling: false

    Timer {
        id: settleTimer
        interval: Appearance.animation.elementMoveFast.duration + 100
        onTriggered: root.settling = false
    }

    /// Leave our submap - and only ours, so a Virtual Machine submap is never reset under someone.
    function leaveSubmap(): void {
        Quickshell.execDetached(["hyprctl", "eval",
            `if hl.get_current_submap() == "${root.submapName}" then hl.dispatch(hl.dsp.submap("reset")) end`]);
    }

    Timer {
        id: showTimer
        interval: root.quickTapMs
        onTriggered: {
            if (root.active && root.entries.length > 0)
                root.shown = true;
        }
    }

    Connections {
        target: HyprlandData
        enabled: root.active
        function onWindowListChanged() {
            root.reconcile();
        }
    }

    Connections {
        target: Hyprland
        enabled: root.active
        function onRawEvent(event) {
            // Straight off the event socket: the card goes before `hyprctl clients` returns.
            if (event.name === "closewindow")
                root.removeAddress(root.normalisedAddress(event.data));
        }
    }

    Connections {
        target: GlobalStates
        function onScreenLockedChanged() {
            if (GlobalStates.screenLocked && root.active) {
                root.leaveSubmap();
                root.cancel();
            }
        }
    }

    // ------------------------------------------------------------------ shortcuts

    readonly property var shortcutNames: ["Next", "Prev", "Commit", "Cancel", "Close", "Left", "Right", "Up", "Down"]

    function handle(name: string): void {
        switch (name) {
        case "Next": root.step(1); break;
        case "Prev": root.step(-1); break;
        case "Commit": root.commit(); break;
        case "Cancel": root.cancel(); break;
        case "Close": root.closeSelected(); break;
        case "Left": if (root.active) root.step(-1); break;
        case "Right": if (root.active) root.step(1); break;
        case "Up": if (root.active) root.stepRow(-1); break;
        case "Down": if (root.active) root.stepRow(1); break;
        }
    }

    Instantiator {
        model: root.enabled ? root.shortcutNames : []
        delegate: GlobalShortcut {
            required property string modelData
            name: `windowSwitcher${modelData}`
            // Not Translation.tr: a GlobalShortcut cannot change once created.
            description: `Window switcher: ${modelData}`
            onPressed: root.handle(modelData)
            // A global dispatched from inside a release bind (Alt coming up) arrives as a
            // release, with no press before it. Commit and Cancel only ever run once each
            // way: both do nothing on a closed switcher.
            onReleased: {
                if (modelData === "Commit" || modelData === "Cancel")
                    root.handle(modelData);
            }
        }
    }

    // ------------------------------------------------------------------ the binds

    readonly property string submapName: "__ii_window_switcher"
    readonly property string bindDescription: "Shell: Window switcher"
    readonly property string bindDescriptionBack: "Shell: Window switcher (backwards)"

    /**
     * Everything that only has to exist once per config generation. A reload wipes binds,
     * submaps and Lua globals alike, so the global is the "already defined" flag - defining the
     * submap twice would stack a second copy of every bind in it.
     *
     * Q is bound as ALT + Q rather than with `ignore_mods`: type-to-search unbinds the bare
     * letters as it arms and disarms, and `hl.unbind` reaches into every submap. Alt is down
     * for as long as the submap is current anyway.
     */
    readonly property string defineChunk: `
if not __ii_window_switcher then
  __ii_window_switcher = true
  local S = "${root.submapName}"
  local function g(n) hl.dispatch(hl.dsp.global("quickshell:windowSwitcher" .. n)) end
  local function finish(n) return function()
    if hl.get_current_submap() == S then hl.dispatch(hl.dsp.submap("reset")); g(n) end
  end end
  for _, k in ipairs({ "ALT_L", "ALT_R" }) do
    hl.bind(k, finish("Commit"), { release = true, ignore_mods = true, transparent = true, description = S })
  end
  hl.define_submap(S, function()
    for _, k in ipairs({ "ALT_L", "ALT_R" }) do hl.bind(k, finish("Commit"), { release = true, ignore_mods = true }) end
    hl.bind("Escape", finish("Cancel"), { ignore_mods = true })
    hl.bind("Return", finish("Commit"), { ignore_mods = true })
    hl.bind("ALT + Q", function() g("Close") end)
    for _, k in ipairs({ "Left", "Right", "Up", "Down" }) do
      hl.bind(k, function() g(k) end, { ignore_mods = true, repeating = true })
    end
    hl.bind("catchall", function() end, { ignore_mods = true })
  end)
end`

    /**
     * The Alt+Tab entry binds, and the submap's own Tab binds with them: `hl.unbind` takes a
     * combination out of every submap at once, so whatever clears the entry also clears the
     * submap's Tab, and the two are only ever put back together. `define_submap` on an
     * existing submap adds to it.
     */
    function entryChunk(on: bool): string {
        const S = root.submapName;
        let chunk = `pcall(hl.unbind, "ALT + Tab") pcall(hl.unbind, "ALT + SHIFT + Tab")`;
        if (on) {
            chunk += `
hl.bind("ALT + Tab", function() hl.dispatch(hl.dsp.submap("${S}")); hl.dispatch(hl.dsp.global("quickshell:windowSwitcherNext")) end, { description = "${root.bindDescription}" })
hl.bind("ALT + SHIFT + Tab", function() hl.dispatch(hl.dsp.submap("${S}")); hl.dispatch(hl.dsp.global("quickshell:windowSwitcherPrev")) end, { description = "${root.bindDescriptionBack}" })
hl.define_submap("${S}", function()
  hl.bind("ALT + Tab", function() hl.dispatch(hl.dsp.global("quickshell:windowSwitcherNext")) end, { repeating = true })
  hl.bind("ALT + SHIFT + Tab", function() hl.dispatch(hl.dsp.global("quickshell:windowSwitcherPrev")) end, { repeating = true })
end)`;
        }
        return chunk;
    }

    /// Whether the root submap's Alt+Tab binds are ours, someone else's, or absent.
    function entryOwnership(binds: var): string {
        let state = "none";
        for (const bind of binds) {
            if (String(bind.submap ?? "") !== "" || String(bind.key ?? "").toLowerCase() !== "tab")
                continue;
            // ALT is 8, SHIFT 1.
            if (bind.modmask !== 8 && bind.modmask !== 9)
                continue;
            const ours = bind.description === root.bindDescription
                || bind.description === root.bindDescriptionBack;
            if (!ours)
                return "theirs";
            state = "ours";
        }
        return state;
    }

    /// Wanted on/off, applied once the current binds have been read.
    property bool pendingOn: false
    /// A read-then-write is in flight; another request waits for it rather than cutting it
    /// short (a killed `hyprctl binds` hands the collector half a JSON document).
    property bool applyBusy: false
    property bool applyQueued: false

    function apply(): void {
        if (root.applyBusy) {
            root.applyQueued = true;
            return;
        }
        root.applyBusy = true;
        root.pendingOn = root.enabled;
        bindsProc.running = true;
    }

    function applyDone(): void {
        root.applyBusy = false;
        if (root.applyQueued) {
            root.applyQueued = false;
            root.apply();
        }
    }

    Process {
        id: bindsProc
        command: ["hyprctl", "binds", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                let ownership = "none";
                try {
                    ownership = root.entryOwnership(JSON.parse(text));
                } catch (error) {
                    console.warn("[WindowSwitcher] cannot read hyprctl binds:", error);
                    root.applyDone();
                    return;
                }
                root.conflict = ownership === "theirs";
                if (root.conflict) {
                    console.info("[WindowSwitcher] Alt+Tab is bound by the user's config; leaving it alone.");
                    root.applyDone();
                    return;
                }
                if (!root.pendingOn && ownership === "none") {
                    root.applyDone();
                    return;
                }
                // Rewritten even when already ours: it restores the submap's Tab binds if
                // anything unbound Alt+Tab in the meantime.
                const chunk = root.pendingOn ? `${root.defineChunk}\n${root.entryChunk(true)}` : root.entryChunk(false);
                evalProc.command = ["hyprctl", "eval", chunk];
                evalProc.running = true;
            }
        }
    }

    Process {
        id: evalProc
        stdout: StdioCollector {
            onStreamFinished: {
                const reply = text.trim();
                if (reply.length > 0 && reply !== "ok")
                    console.warn("[WindowSwitcher] hyprctl eval:", reply);
            }
        }
        onExited: root.applyDone()
    }

    onEnabledChanged: {
        if (!root.enabled && root.active) {
            root.leaveSubmap();
            root.cancel();
        }
        root.apply();
    }
    Component.onCompleted: root.apply()

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            // A reload takes our binds, the submap and the guard with it.
            if (event.name === "configreloaded")
                reapplyTimer.restart();
        }
    }

    /// One write is several `configreloaded` events; settle before reading the binds back.
    Timer {
        id: reapplyTimer
        interval: 300
        onTriggered: root.apply()
    }
}
