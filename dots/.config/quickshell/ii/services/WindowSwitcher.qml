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
 * Both faces of the switcher - the Dynamic Island's cover flow and the floating panel of
 * thumbnails - are views on this one object, and so is the peek (WindowSwitcherPeek). They
 * read `entries` and `selectedIndex`, and call `activate()`/`closeAt()` for the pointer;
 * every key arrives here.
 *
 * Typing with Alt held searches: `entries` is the snapshot (`allEntries`) filtered by
 * `query`. Holding still on one selection for `peekDelayMs` peeks at it - the window is drawn
 * over a dimmed screen where it really is - and a release while peeking switches with the
 * compositor's animations off, so the workspace does not slide in behind the peeked window.
 *
 * ## Keys
 *
 * Hyprland matches binds before any surface sees a key, and taking keyboard focus to hear
 * Alt come up would take it away from the window being switched *from* on every tap (and
 * would lose the release outright while the surface is still being built). So the switcher
 * never holds the keyboard. Alt+Tab is a bind whose Lua function enters a submap in the same
 * compositor call - no round trip the release could overtake - and inside the submap Tab,
 * Shift+Tab, the arrows, the letters and digits, Backspace, Delete, Enter and Escape are binds
 * too, with a catch-all swallowing the rest so nothing typed mid-switch lands in the window
 * being left. Each one reaches this object as a global shortcut, in order. Pointer input is
 * not affected: click still works.
 *
 * Alt coming up is the subtle one. Hyprland matches a release against the submap the key was
 * *pressed* in, and Alt went down before the submap was entered, so the release bind lives in
 * the root submap (transparent, so nothing else loses the key) and acts only while ours is
 * current. It leaves the submap inside the compositor before telling the shell, so a shell
 * that died mid-switch can never strand the keyboard in it past the release.
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

    // ------------------------------------------------------------------ search

    /// Alt+letter on the desktop opens the switcher already searching (off: only inside it).
    readonly property bool searchAnywhere: root.options?.searchAnywhere ?? false
    /// The keys that type into the search, with Alt held. Shift does not change them.
    readonly property var searchKeys: "abcdefghijklmnopqrstuvwxyz0123456789".split("").concat(["space"])
    /// Letters the user's own config binds with Alt, so search-anywhere leaves them be.
    property var searchConflicts: []
    /// What has been typed since Alt+Tab. `entries` is `allEntries` filtered by it.
    property string query: ""
    /// Every window in the snapshot, most recently used first, whatever the query.
    property var allEntries: []

    // ------------------------------------------------------------------ peek

    /// How long one selection is held before the screen peeks at it; 0 never peeks.
    readonly property int peekDelayMs: Math.max(0, root.options?.peekDelayMs ?? 600)
    /// Peeking: once it starts, every selection after it is peeked at straight away.
    property bool peeking: false
    /// The window the peek shows. Kept after the switcher closes, for the peek's fade-out.
    property var peekEntry: null
    readonly property string selectedAddress: root.selectedEntry?.address ?? ""

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
            "x": Number(client.at?.[0] ?? 0),
            "y": Number(client.at?.[1] ?? 0),
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
        const selected = root.selectedAddress;
        const kept = [];
        for (const entry of root.allEntries) {
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
        root.replaceEntries(root.allEntries.filter(entry => entry.address !== address), root.selectedAddress);
    }

    /// `all` becomes the window list; what is shown is that list under the current query.
    function replaceEntries(all: var, selectedAddress: string): void {
        const oldIndex = root.selectedIndex;
        const list = root.filtered(all);
        root.allEntries = all;
        root.entries = list;
        if (all.length === 0) {
            root.selectedIndex = 0;
            // Nothing left to switch to. The submap stays until Alt comes up (it would anyway,
            // and leaving it here would hand the held Tab to a window), but the UI goes.
            root.shown = false;
            showTimer.stop();
            return;
        }
        if (list.length === 0) {
            // A query nothing matches: the UI stays, saying so, until it is edited.
            root.selectedIndex = 0;
            return;
        }
        const at = list.findIndex(entry => entry.address === selectedAddress);
        // The selected window closed: its neighbour moves up into the same slot.
        root.selectedIndex = at >= 0 ? at : Math.min(oldIndex, list.length - 1);
    }

    /**
     * The windows matching the query, best first. A word of the app name or title that
     * starts with the query beats the query appearing anywhere, which beats its letters
     * merely appearing in order; inside each tier the most recently used comes first.
     */
    function filtered(list: var): var {
        const query = root.query.trim().toLowerCase();
        if (query.length === 0)
            return list.slice();
        const tiers = [[], [], []];
        for (const entry of list) {
            const text = `${entry.appClass} ${entry.toplevel?.title || entry.title}`.toLowerCase();
            if (text.split(/[\s\-_.:/|·—]+/).some(word => word.startsWith(query)))
                tiers[0].push(entry);
            else if (text.includes(query))
                tiers[1].push(entry);
            else if (root.inOrder(query.replace(/\s+/g, ""), text))
                tiers[2].push(entry);
        }
        return tiers[0].concat(tiers[1], tiers[2]);
    }

    function inOrder(needle: string, haystack: string): bool {
        let at = 0;
        for (const ch of needle) {
            at = haystack.indexOf(ch, at);
            if (at < 0)
                return false;
            at++;
        }
        return needle.length > 0;
    }

    /// A new query: the best match is selected; clearing it returns to the window you were on.
    function setQuery(text: string): void {
        const before = root.selectedAddress;
        root.query = text;
        const list = root.filtered(root.allEntries);
        root.entries = list;
        if (text.length > 0 || list.length === 0) {
            root.selectedIndex = 0;
        } else {
            const at = list.findIndex(entry => entry.address === before);
            root.selectedIndex = at >= 0 ? at : Math.min(1, list.length - 1);
        }
        // Typing means looking: no quick-tap grace for a search.
        if (root.active && !root.shown && root.allEntries.length > 0) {
            showTimer.stop();
            root.shown = true;
        }
    }

    /// One key typed with Alt held. On the desktop (search-anywhere) it opens the switcher.
    function typeKey(key: string): void {
        const ch = key === "space" ? " " : key;
        if (!root.active) {
            root.open(1);
            if (!root.active)
                return;
        }
        root.setQuery(root.query + ch);
    }

    function backspace(): void {
        if (root.active && root.query.length > 0)
            root.setQuery(root.query.slice(0, -1));
    }

    /// Escape clears a search first, and only then closes the switcher.
    function escapeKey(): void {
        if (!root.active)
            return;
        if (root.query.length > 0) {
            root.setQuery("");
            return;
        }
        root.leaveSubmap();
        root.cancel();
    }

    // ------------------------------------------------------------------ actions

    function open(direction: int): void {
        const list = root.snapshot();
        root.screenName = Hyprland.focusedMonitor?.name ?? "";
        root.presenter = GlobalStates.islandOwnsWindowSwitcher ? "island" : "panel";
        root.query = "";
        root.allEntries = list;
        root.entries = list.slice();
        root.selectedIndex = list.length < 2 ? 0 : (direction > 0 ? 1 : list.length - 1);
        root.pointerOrigin = null;
        root.pointerLive = false;
        root.peeking = false;
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
        const peeked = root.peeking;
        root.finish();
        if (!entry)
            return;
        const current = root.normalisedAddress(Hyprland.activeToplevel?.address);
        // Focusing a window on a hidden special workspace pulls that workspace over the screen,
        // and one on another workspace switches there - both done by Hyprland's own focus.
        if (entry.address === current && !entry.special)
            return;
        const focus = root.focusChunk(entry);
        if (!peeked) {
            Quickshell.execDetached(["hyprctl", "eval", focus]);
            return;
        }
        // The peek already showed the window where it lives: arrive there without the
        // workspace sliding in behind it. Animations go off for this one switch and come back
        // as they were; the peek fades out over the result.
        Quickshell.execDetached(["hyprctl", "eval", `if __ii_alt_tab_animations == nil then
  __ii_alt_tab_animations = hl.get_config("animations.enabled")
end
hl.config({ animations = { enabled = false } })
${focus}`]);
        animationsTimer.restart();
    }

    /**
     * Focus the window, and with focus-follows-mouse bring the pointer into it.
     *
     * Otherwise focus goes straight back to whatever window the pointer rests on: the
     * island (or panel) the pointer was over shrinks away from under it, Hyprland sees the
     * pointer land on a window and refocuses it. That was a click on a cover "selecting"
     * the window instead of switching to it. A pointer already inside the window stays put.
     */
    function focusChunk(entry: var): string {
        const x0 = Math.round(entry.x);
        const y0 = Math.round(entry.y);
        const x1 = Math.round(entry.x + entry.width);
        const y1 = Math.round(entry.y + entry.height);
        return `hl.dispatch(hl.dsp.focus({ window = "address:${entry.address}" }))
if hl.get_config("input.follow_mouse") == 1 then
  local p = hl.get_cursor_pos()
  if p and (p.x < ${x0} or p.x >= ${x1} or p.y < ${y0} or p.y >= ${y1}) then
    hl.dispatch(hl.dsp.cursor.move({ x = ${Math.round((x0 + x1) / 2)}, y = ${Math.round((y0 + y1) / 2)} }))
  end
end`;
    }

    /// Puts animations back after an instant switch. Its own call, so the switch has landed.
    function restoreAnimations(): void {
        Quickshell.execDetached(["hyprctl", "eval", `if __ii_alt_tab_animations ~= nil then
  hl.config({ animations = { enabled = __ii_alt_tab_animations } })
  __ii_alt_tab_animations = nil
end`]);
    }

    Timer {
        id: animationsTimer
        interval: 150
        onTriggered: root.restoreAnimations()
    }

    function cancel(): void {
        root.finish();
    }

    /// Delete, the × on a card, or a middle click: ask a window to close. It leaves the list
    /// when it really goes - an app asking "save changes?" stays, as it should.
    function closeAt(index: int): void {
        const entry = root.entries[index] ?? null;
        if (root.shown && entry)
            Hyprland.dispatch(`hl.dsp.window.close({ window = "address:${entry.address}" })`);
    }

    function closeSelected(): void {
        root.closeAt(root.selectedIndex);
    }

    function finish(): void {
        // Set before anything closes, so a view picking an animation for the way out sees it.
        if (root.active) {
            root.settling = true;
            settleTimer.restart();
        }
        showTimer.stop();
        peekTimer.stop();
        root.peeking = false;
        root.active = false;
        root.shown = false;
    }

    /**
     * Just closed: the faces are animating back. Lets a view keep the switcher's timing. As
     * long as the island's large-face morph (NotchIsland), which is what it is waiting on.
     */
    property bool settling: false

    Timer {
        id: settleTimer
        interval: Math.round(420 * Appearance.animMultiplier) + 100
        onTriggered: root.settling = false
    }

    /// Holding still on a selection, with the switcher up, starts the peek.
    Timer {
        id: peekTimer
        interval: Math.max(1, root.peekDelayMs)
        onTriggered: {
            if (root.active && root.shown && root.selectedEntry && root.peekDelayMs > 0) {
                root.peekEntry = root.selectedEntry;
                root.peeking = true;
            }
        }
    }

    function armPeek(): void {
        if (root.peeking) {
            if (root.selectedEntry)
                root.peekEntry = root.selectedEntry;
            return;
        }
        if (root.active && root.shown && root.peekDelayMs > 0 && root.selectedEntry)
            peekTimer.restart();
        else
            peekTimer.stop();
    }

    onSelectedAddressChanged: root.armPeek()
    onShownChanged: root.armPeek()
    // A title or a move: the peek follows the window it shows.
    onSelectedEntryChanged: {
        if (root.peeking && root.selectedEntry)
            root.peekEntry = root.selectedEntry;
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

    readonly property var shortcutNames: ["Next", "Prev", "Commit", "Cancel", "Escape", "Close", "Backspace",
        "Left", "Right", "Up", "Down"].concat(root.searchKeys.map(key => `Key_${key}`))

    function handle(name: string): void {
        if (name.startsWith("Key_")) {
            root.typeKey(name.slice(4));
            return;
        }
        switch (name) {
        case "Next": root.step(1); break;
        case "Prev": root.step(-1); break;
        case "Commit": root.commit(); break;
        case "Cancel": root.cancel(); break;
        case "Escape": root.escapeKey(); break;
        case "Close": root.closeSelected(); break;
        case "Backspace": root.backspace(); break;
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

    /**
     * The submap. Renamed from `__ii_window_switcher` when typing arrived: a session that
     * still holds the old one (it lives until Hyprland reloads its config) keeps it as an
     * unused leftover instead of getting a second copy of every key stacked into it.
     */
    readonly property string submapName: "__ii_alt_tab"
    readonly property string bindDescription: "Shell: Window switcher"
    readonly property string bindDescriptionBack: "Shell: Window switcher (backwards)"

    /// The Lua that types one search key from inside the submap.
    function searchKeyBind(key: string): string {
        return `hl.bind("ALT + ${key}", function() hl.dispatch(hl.dsp.global("quickshell:windowSwitcherKey_${key}")) end, { repeating = true })`;
    }

    /**
     * Everything that only has to exist once per config generation. A reload wipes binds,
     * submaps and Lua globals alike, so the global is the "already defined" flag - defining the
     * submap twice would stack a second copy of every bind in it.
     *
     * The search keys are bound with Alt (and Alt+Shift) spelled out rather than with
     * `ignore_mods`: type-to-search unbinds the bare letters as it arms and disarms, and
     * `hl.unbind` reaches into every submap. Alt is down for as long as the submap is current
     * anyway. Escape goes to the shell without leaving the submap, because it only closes the
     * switcher when there is no search to clear; Alt coming up still always leaves.
     */
    readonly property string defineChunk: `
if not __ii_alt_tab then
  __ii_alt_tab = true
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
    hl.bind("Escape", function() g("Escape") end, { ignore_mods = true })
    hl.bind("Return", finish("Commit"), { ignore_mods = true })
    hl.bind("Delete", function() g("Close") end, { ignore_mods = true })
    hl.bind("BackSpace", function() g("Backspace") end, { ignore_mods = true, repeating = true })
    for _, k in ipairs({ "Left", "Right", "Up", "Down" }) do
      hl.bind(k, function() g(k) end, { ignore_mods = true, repeating = true })
    end
    for _, k in ipairs({ ${root.searchKeys.map(key => `"${key}"`).join(", ")} }) do
      hl.bind("ALT + " .. k, function() g("Key_" .. k) end, { repeating = true })
      hl.bind("ALT + SHIFT + " .. k, function() g("Key_" .. k) end, { repeating = true })
    end
    hl.bind("catchall", function() end, { ignore_mods = true })
  end)
end`

    /**
     * Search-anywhere: Alt+key on the desktop enters the submap and types. Only keys nobody
     * else binds with Alt get one, and turning it off takes away only ours. Taking one away
     * (`hl.unbind`) also takes the submap's Alt+key, so that is put straight back.
     */
    function searchChunk(on: bool, ownership: var): string {
        const S = root.submapName;
        const lines = [];
        for (const key of root.searchKeys) {
            const owner = ownership[key] ?? "none";
            if (on && owner === "none") {
                lines.push(`hl.bind("ALT + ${key}", function() hl.dispatch(hl.dsp.submap("${S}")); hl.dispatch(hl.dsp.global("quickshell:windowSwitcherKey_${key}")) end, { description = "${S}" })`);
            } else if (!on && owner === "ours") {
                lines.push(`pcall(hl.unbind, "ALT + ${key}")`);
                lines.push(`hl.define_submap("${S}", function() ${root.searchKeyBind(key)} end)`);
            }
        }
        return lines.join("\n");
    }

    /// For each search key, whether the root submap's Alt+key is ours, someone else's, or free.
    function searchOwnership(binds: var): var {
        const owners = {};
        for (const bind of binds) {
            if (String(bind.submap ?? "") !== "" || bind.modmask !== 8)
                continue;
            const key = String(bind.key ?? "").toLowerCase();
            if (!root.searchKeys.includes(key))
                continue;
            const ours = bind.description === root.submapName;
            owners[key] = ours && owners[key] !== "theirs" ? "ours" : "theirs";
        }
        return owners;
    }

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
    property bool pendingSearch: false
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
        root.pendingSearch = root.searchAnywhere;
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
                let binds = [];
                try {
                    binds = JSON.parse(text);
                } catch (error) {
                    console.warn("[WindowSwitcher] cannot read hyprctl binds:", error);
                    root.applyDone();
                    return;
                }
                const ownership = root.entryOwnership(binds);
                const searchOwners = root.searchOwnership(binds);
                root.searchConflicts = root.searchKeys.filter(key => searchOwners[key] === "theirs");
                root.conflict = ownership === "theirs";
                if (root.conflict) {
                    console.info("[WindowSwitcher] Alt+Tab is bound by the user's config; leaving it alone.");
                    root.applyDone();
                    return;
                }
                const searchOurs = root.searchKeys.some(key => searchOwners[key] === "ours");
                if (!root.pendingOn && ownership === "none" && !searchOurs) {
                    root.applyDone();
                    return;
                }
                // Rewritten even when already ours: it restores the submap's Tab binds if
                // anything unbound Alt+Tab in the meantime.
                const chunk = root.pendingOn
                    ? `${root.defineChunk}\n${root.entryChunk(true)}\n${root.searchChunk(root.pendingSearch, searchOwners)}`
                    : `${root.entryChunk(false)}\n${root.searchChunk(false, searchOwners)}`;
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
    onSearchAnywhereChanged: root.apply()
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
