pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs
import qs.modules.common
import qs.modules.common.functions

/**
 * Touchpad gestures: the shell's half.
 *
 * The compositor owns the gestures. `hypr/hyprland/gestures.lua` registers them from a Lua
 * snapshot this service writes out of `interactions.touchpadGestures`, and it reads that
 * snapshot by itself at every config load - so the chosen layout is there before the shell
 * starts and stays there if the shell goes away. All this service does on that side is
 * rewrite the snapshot when the list changes and ask the compositor to read it again.
 *
 * Hyprland's own actions (workspace swipe, move, float...) are registered as native
 * gestures and never reach this file. The two kinds that do arrive here come as `custom`
 * events on the event socket, which costs no process per swipe:
 *
 *   iigesture,trigger,<action>,<direction>          a shell action, fired once
 *   iigesture,begin,<surface>,<direction>           a surface that follows the fingers...
 *   iigesture,update,<surface>,<travel>,<velocity>
 *   iigesture,end,<surface>,<cancelled>,<velocity>
 *   iigesture,applied,<version>,<source>,<result>   how the last reload went
 *
 * A surface that follows the fingers is opened for real when the swipe starts; what this
 * service holds back is only its reveal, through `GlobalStates.gestureDragSurface` and
 * `gestureDragProgress`. A surface that cannot be held right now - pinned, detached, or
 * another panel family's - still works: the gesture fires the plain action when it ends.
 */
Singleton {
    id: root

    readonly property var opts: Config.options?.interactions?.touchpadGestures ?? null
    readonly property bool enabled: root.opts?.enable ?? true
    readonly property int trackedDistance: Math.max(40, root.opts?.trackedDistance ?? 280)

    readonly property string snapshotPath:
        FileUtils.trimFileProtocol(`${Directories.state}/user/generated/touchpad_gestures.lua`)

    readonly property var directions: ["up", "down", "left", "right", "horizontal", "vertical", "swipe",
        "pinchin", "pinchout", "pinch"]
    readonly property var kinds: ["hyprland", "lua", "shell", "tracked", "command", "dispatch"]
    /// Hyprland's own gesture actions, and what their one optional argument means.
    readonly property var nativeActions: [
        { "id": "workspace", "name": "Switch workspace", "icon": "swap_horiz", "follows": true },
        { "id": "move", "name": "Move window", "icon": "drag_pan", "follows": true },
        { "id": "resize", "name": "Resize window", "icon": "open_in_full", "follows": true },
        { "id": "float", "name": "Float / tile window", "icon": "picture_in_picture", "follows": true,
          "modes": ["", "float", "tile"] },
        { "id": "fullscreen", "name": "Fullscreen window", "icon": "fullscreen", "follows": true,
          "modes": ["fullscreen", "maximize"] },
        { "id": "close", "name": "Close window", "icon": "close", "follows": true },
        { "id": "special", "name": "Special workspace", "icon": "inventory_2", "follows": true, "arg": "name" },
        { "id": "cursor_zoom", "name": "Zoom at cursor", "icon": "zoom_in", "follows": false, "arg": "zoom",
          "modes": ["", "mult", "live"] },
        { "id": "scroll_move", "name": "Scroll the layout", "icon": "swipe", "follows": true }
    ]
    /// Handlers gestures.lua offers by name (`ii_gestures.handlers`).
    readonly property var luaActions: [
        { "id": "scratchpadUp", "name": "Scratchpad: show / take window out", "icon": "inventory_2" },
        { "id": "scratchpadDown", "name": "Scratchpad: hide / send window in", "icon": "inventory_2" }
    ]
    /// TouchGestureActionRegistry ids whose surface can follow the fingers.
    readonly property var trackedSurfaces: ["overview", "sidebarLeft", "sidebarRight"]

    /// False once the compositor has answered that it has no `ii_gestures` - a Hyprland
    /// config older than this shell. Nothing takes effect then; the page says why.
    property bool supported: true
    /// "defaults", "snapshot" or "off": what the compositor last registered from.
    property string source: ""
    /// binding index -> why the compositor did not register it
    property var problems: ({})

    // ── The list ─────────────────────────────────────────────────────────────

    function normalise(raw: var): var {
        const direction = String(raw?.direction ?? "").toLowerCase();
        const kind = String(raw?.kind ?? "");
        const scale = Number(raw?.scale);
        return {
            "fingers": Math.max(2, Math.min(9, Math.round(Number(raw?.fingers) || 3))),
            "direction": root.directions.indexOf(direction) !== -1 ? direction : "up",
            "mods": root.modsString(root.modsList(raw?.mods)),
            "scale": isFinite(scale) && scale > 0 ? Math.max(0.1, Math.min(10, scale)) : 1,
            "kind": root.kinds.indexOf(kind) !== -1 ? kind : "hyprland",
            "action": String(raw?.action ?? ""),
            "arg": String(raw?.arg ?? ""),
            "mode": String(raw?.mode ?? "")
        };
    }

    property var _memo: ({})
    readonly property var bindings: ObjectUtils.keep(root._memo, "bindings",
        Array.from(root.opts?.bindings ?? []).map(raw => root.normalise(raw)))

    function setBindings(next: var): void {
        if (!root.opts)
            return;
        root.opts.bindings = Array.from(next).map(raw => root.normalise(raw));
    }

    /// The keys the page offers to hold, in the order they are written out.
    readonly property var modifierKeys: ["SUPER", "CTRL", "ALT", "SHIFT"]

    /// "shift super" -> ["SUPER", "SHIFT"]: known keys first in their usual order, then any other
    /// mask name Hyprland knows (MOD3, CAPS...) as it was written.
    function modsList(mods: var): var {
        const words = String(mods ?? "").toUpperCase().split(/[^A-Z0-9_]+/).filter(part => part.length > 0)
            .map(part => part === "CONTROL" ? "CTRL" : part);
        const known = root.modifierKeys.filter(key => words.indexOf(key) !== -1);
        const others = words.filter((word, i) => root.modifierKeys.indexOf(word) === -1 && words.indexOf(word) === i);
        return known.concat(others);
    }

    /// Hyprland matches each mask name anywhere in the string, so this is what keybinds.lua writes too.
    function modsString(list: var): string {
        return Array.from(list ?? []).join(" + ");
    }

    function modsKey(mods: string): string {
        return root.modsList(mods).slice().sort().join("+");
    }

    /// Same finger count, modifiers and direction: only one of them can ever fire.
    function slotKey(binding: var): string {
        return `${binding.fingers}|${root.modsKey(binding.mods)}|${binding.direction}`;
    }

    /// Index of an earlier binding on the same slot, or -1.
    function duplicateOf(index: int): int {
        const key = root.slotKey(root.bindings[index]);
        for (let i = 0; i < index; i++) {
            if (root.slotKey(root.bindings[i]) === key)
                return i;
        }
        return -1;
    }

    // Hyprland keeps the first gesture that covers a swipe and refuses a later, narrower
    // one. Registering one-direction gestures first, then an axis, then "any direction"
    // makes every combination that can coexist do so, whatever order the list is in.
    function _rank(direction: string): int {
        if (direction === "swipe")
            return 2;
        return (direction === "horizontal" || direction === "vertical" || direction === "pinch") ? 1 : 0;
    }

    /// Positions in `bindings`, in the order the compositor is given them.
    readonly property var order: {
        const indexes = root.bindings.map((binding, index) => index);
        indexes.sort((a, b) => (root._rank(root.bindings[a].direction) - root._rank(root.bindings[b].direction))
            || (a - b));
        return indexes;
    }

    // ── Snapshot ─────────────────────────────────────────────────────────────

    function luaString(value: string): string {
        const escaped = String(value).replace(/\\/g, "\\\\").replace(/"/g, "\\\"").replace(/\n/g, "\\n")
            .replace(/\r/g, "\\r").replace(/\0/g, "");
        return `"${escaped}"`;
    }

    function _luaEntry(binding: var): string {
        const fields = [`fingers = ${binding.fingers}`, `direction = ${root.luaString(binding.direction)}`,
            `kind = ${root.luaString(binding.kind)}`];
        if (binding.action.length > 0)
            fields.push(`action = ${root.luaString(binding.action)}`);
        if (binding.arg.length > 0)
            fields.push(`arg = ${root.luaString(binding.arg)}`);
        if (binding.mode.length > 0)
            fields.push(`mode = ${root.luaString(binding.mode)}`);
        if (binding.mods.length > 0)
            fields.push(`mods = ${root.luaString(binding.mods)}`);
        if (binding.scale !== 1)
            fields.push(`scale = ${binding.scale.toFixed(2)}`);
        return `    { ${fields.join(", ")} },`;
    }

    readonly property string snapshotText: {
        const lines = ["-- Written by the shell from interactions.touchpadGestures (Settings -> Touchpad gestures).",
            "-- Read by hypr/hyprland/gestures.lua. Edits here are overwritten.",
            `return { version = 1, enabled = ${root.enabled ? "true" : "false"}, bindings = {`];
        for (const index of root.order)
            lines.push(root._luaEntry(root.bindings[index]));
        lines.push("} }");
        return lines.join("\n") + "\n";
    }

    onSnapshotTextChanged: pushTimer.restart()
    Component.onCompleted: pushTimer.restart()

    // Config re-reads its own file shortly after each write; wait that out so a burst of
    // edits is one snapshot and one re-registration.
    Timer {
        id: pushTimer
        interval: 350
        onTriggered: root.push()
    }

    /// Bring the snapshot and the compositor in line with the list. Writes nothing and
    /// re-registers nothing when the snapshot on disk already says the same.
    function push(): void {
        if (!Config.ready || !root.opts) {
            pushTimer.restart();
            return;
        }
        if (syncProc.running) {
            syncProc.again = true;
            return;
        }
        syncProc.command = ["bash", "-c",
            'path="$1"; text="$2"\n'
            + 'if [ -f "$path" ] && printf %s "$text" | cmp -s - "$path"; then\n'
            + '    hyprctl eval "ii_gestures.report()"\n'
            + '    exit 0\n'
            + 'fi\n'
            + 'mkdir -p "$(dirname "$path")" && printf %s "$text" > "$path.tmp" && mv "$path.tmp" "$path" || exit 1\n'
            + 'hyprctl eval "ii_gestures.reload() ii_gestures.report()"\n',
            "touchpad-gestures", root.snapshotPath, root.snapshotText];
        syncProc.running = true;
    }

    /// Ask the compositor what it registered, without changing anything.
    function refreshStatus(): void {
        if (!syncProc.running)
            Quickshell.execDetached(["hyprctl", "eval", "ii_gestures.report()"]);
    }

    Process {
        id: syncProc

        property bool again: false

        stdout: StdioCollector {
            onStreamFinished: {
                const answer = text.trim();
                if (answer.length === 0)
                    return;
                // "ok" is hyprctl's whole answer; the result itself comes back as an event.
                root.supported = !answer.startsWith("error");
                if (!root.supported)
                    console.warn("[TouchpadGestures] The Hyprland config has no ii_gestures:", answer);
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0)
                console.warn("[TouchpadGestures] Could not write", root.snapshotPath);
            if (!syncProc.again)
                return;
            syncProc.again = false;
            pushTimer.restart();
        }
    }

    function _onApplied(parts: var): void {
        root.source = parts[3] ?? "";
        // The compositor numbers entries as it was given them; turn that back into
        // positions in the list the page shows.
        const result = parts.slice(4).join(",");
        const found = {};
        if (result !== "ok" && root.source === "snapshot") {
            for (const item of result.split(";")) {
                const colon = item.indexOf(":");
                const sent = parseInt(item.slice(0, colon)) - 1;
                if (colon > 0 && sent >= 0 && sent < root.order.length)
                    found[root.order[sent]] = item.slice(colon + 1);
            }
        }
        root.problems = found;
    }

    // ── Surfaces ─────────────────────────────────────────────────────────────

    /// The lock screen and the capture overlays own the whole screen; nothing should
    /// open underneath them because a hand brushed the touchpad.
    readonly property bool blocked: GlobalStates.screenLocked || GlobalStates.regionSelectorOpen
        || GlobalStates.screenshotOverlayOpen

    function focusedScreenName(): string {
        return Hyprland.focusedMonitor?.name ?? "";
    }

    function _isOpen(id: string): bool {
        switch (id) {
        case "sidebarLeft":
            return GlobalStates.sidebarLeftOpen;
        case "sidebarRight":
            return GlobalStates.sidebarRightOpen;
        case "overview":
            return GlobalStates.overviewOpen;
        }
        return false;
    }

    function _open(id: string, screenName: string): void {
        switch (id) {
        case "sidebarLeft":
            GlobalStates.openLeftSidebar(screenName);
            break;
        case "sidebarRight":
            GlobalStates.openRightSidebar(screenName);
            break;
        case "overview":
            GlobalStates.openOverview(screenName);
            break;
        }
    }

    function _close(id: string): void {
        switch (id) {
        case "sidebarLeft":
            GlobalStates.sidebarLeftOpen = false;
            break;
        case "sidebarRight":
            GlobalStates.sidebarRightOpen = false;
            break;
        case "overview":
            GlobalStates.closeOverview();
            break;
        }
    }

    /// The swipe that pulls a surface in. The opposite one pushes it back out.
    function _openDirection(id: string): string {
        const position = Config.options?.sidebar?.position ?? "default";
        switch (id) {
        case "sidebarLeft":
            return (position === "default" || position === "left") ? "right" : "left";
        case "sidebarRight":
            return (position === "default" || position === "right") ? "left" : "right";
        case "overview":
            return "up";
        }
        return "";
    }

    /// Whether the surface's reveal can be held part-way right now.
    function _canTrack(id: string): bool {
        if (!PanelFamily.isIi)
            return false;
        switch (id) {
        case "sidebarLeft":
            return !GlobalStates.policiesPinned && !GlobalStates.policiesDetached;
        case "sidebarRight":
            return true;
        case "overview":
            // The island morphs into search on its own springs; there is no reveal to hold.
            return !GlobalStates.overviewUsesAppDrawer && !GlobalStates.islandHostsSearch
                && !GlobalStates.islandOwnsSearch;
        }
        return false;
    }

    readonly property var _opposite: ({ "up": "down", "down": "up", "left": "right", "right": "left" })

    /**
     * An open surface that this swipe would push back where it came from.
     *
     * With the right sidebar out, a swipe to the right means "put that away" whatever the
     * swipe happens to be bound to - opening the left sidebar on top of it is never what
     * the hand meant.
     */
    function _surfaceToDismiss(direction: string): string {
        for (const id of root.dismissedBy(direction)) {
            if (root._isOpen(id))
                return id;
        }
        return "";
    }

    /// Surfaces that a shell gesture swiping this way puts away while they are open.
    function dismissedBy(direction: string): var {
        return root.trackedSurfaces.filter(id => root._opposite[root._openDirection(id)] === direction);
    }

    function _trigger(actionId: string, direction: string): void {
        if (root.blocked)
            return;
        const dismiss = root._surfaceToDismiss(direction);
        TouchGestureActionRegistry.trigger(dismiss.length > 0 ? dismiss : actionId, root.focusedScreenName());
    }

    // ── Following the fingers ────────────────────────────────────────────────

    /// The surface the fingers are moving right now, "" between gestures.
    property string activeSurface: ""
    property bool _activeClosing: false
    property bool _activeHeld: false
    property real _activeProgress: 0
    /// Past this much of the way, letting go finishes the move.
    readonly property real commitProgress: 0.4
    /// A flick this fast (touchpad px/s) finishes it from anywhere.
    readonly property real commitVelocity: 500

    function _begin(surfaceId: string, direction: string): void {
        root._end(true, 0);
        root._finishSettle();
        if (root.blocked)
            return;
        const dismiss = root._surfaceToDismiss(direction);
        const id = dismiss.length > 0 ? dismiss : surfaceId;

        root.activeSurface = id;
        root._activeProgress = 0;
        root._activeHeld = root._canTrack(id);
        staleTimer.restart();
        if (!root._activeHeld)
            return;

        // Hold the reveal first, open second: the surface's own animation must find
        // itself already overruled when its flag changes.
        root._activeClosing = root._isOpen(id);
        GlobalStates.gestureDragProgress = root._activeClosing ? 1 : 0;
        GlobalStates.gestureDragSurface = id;
        if (!root._activeClosing)
            root._open(id, root.focusedScreenName());
    }

    function _update(travel: real, velocity: real): void {
        if (root.activeSurface.length === 0)
            return;
        staleTimer.restart();
        root._activeProgress = Math.max(0, Math.min(1, travel / root.trackedDistance));
        if (root._activeHeld)
            GlobalStates.gestureDragProgress = root._activeClosing ? 1 - root._activeProgress : root._activeProgress;
    }

    function _end(cancelled: bool, velocity: real): void {
        const id = root.activeSurface;
        if (id.length === 0)
            return;
        staleTimer.stop();
        root.activeSurface = "";
        const commit = !cancelled && (velocity > root.commitVelocity
            || (root._activeProgress >= root.commitProgress && velocity > -root.commitVelocity));

        if (root._activeHeld) {
            root._settle((root._activeClosing ? !commit : commit) ? 1 : 0);
            return;
        }
        // Nothing here can hold this one part-way: it is a plain action after all.
        if (commit && !root.blocked)
            TouchGestureActionRegistry.trigger(id, root.focusedScreenName());
    }

    // The fingers have lifted: carry the surface the rest of the way, or back.
    property real _settleTarget: 0

    function _settle(target: real): void {
        root._settleTarget = target;
        const distance = Math.abs(target - GlobalStates.gestureDragProgress);
        if (Appearance.reducedMotion || distance < 0.001) {
            root._finishSettle();
            return;
        }
        settleAnimation.from = GlobalStates.gestureDragProgress;
        settleAnimation.to = target;
        settleAnimation.duration = Math.max(120, Math.round(340 * distance * Appearance.animMultiplier));
        settleAnimation.start();
    }

    /// Hand the surface back to its own clock, at the end it was settling toward.
    function _finishSettle(): void {
        settleAnimation.stop();
        const id = GlobalStates.gestureDragSurface;
        if (id.length === 0 || root.activeSurface.length > 0)
            return;
        GlobalStates.gestureDragProgress = root._settleTarget;
        // Flag before release: a surface let go while still flagged open would run its
        // opening animation from the closed position it was just brought to.
        if (root._settleTarget === 0)
            root._close(id);
        GlobalStates.gestureDragSurface = "";
    }

    NumberAnimation {
        id: settleAnimation
        target: GlobalStates
        property: "gestureDragProgress"
        easing.type: Easing.OutCubic
        onFinished: root._finishSettle()
    }

    onBlockedChanged: {
        if (root.blocked)
            root._end(true, 0);
    }

    // A gesture whose end never arrives (the compositor reloaded mid-swipe) must not
    // leave a surface hanging half open. Restarted by every update, so resting fingers
    // only lose the gesture after this long without moving at all.
    Timer {
        id: staleTimer
        interval: 5000
        onTriggered: root._end(true, 0)
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name !== "custom")
                return;
            const data = String(event.data);
            if (!data.startsWith("iigesture,"))
                return;
            const parts = data.split(",");
            switch (parts[1]) {
            case "trigger":
                root._trigger(parts[2] ?? "", parts[3] ?? "");
                break;
            case "begin":
                root._begin(parts[2] ?? "", parts[3] ?? "");
                break;
            case "update":
                root._update(Number(parts[3]) || 0, Number(parts[4]) || 0);
                break;
            case "end":
                root._end(parts[3] === "1", Number(parts[4]) || 0);
                break;
            case "applied":
                root._onApplied(parts);
                break;
            }
        }
    }
}
