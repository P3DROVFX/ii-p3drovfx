pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.modules.common
import "windowSwitcher/WindowSwitcherLogic.js" as Logic

/**
 * Alt+Tab: the window list, its order, the selection, and committing or cancelling it.
 *
 * Both faces of the switcher - the Dynamic Island's cover flow and the floating panel of
 * thumbnails - are views on this one object, and so is the peek (WindowSwitcherPeek). They
 * read `entries` and `selectedIndex`, and call `activate()`/`closeAt()` for the pointer;
 * every key arrives here. What can be decided without QML (order, filters, search, moving
 * the selection) lives in WindowSwitcherLogic.js, where the tests reach it.
 *
 * Typing with Alt held searches: `entries` is the snapshot (`allEntries`) filtered by
 * `query`. Releasing Alt with a search typed keeps the switcher open (`released`) so the
 * search can go on with Alt up; Enter or a click switches, Escape cancels. Holding still on
 * one selection for `peekDelayMs` peeks at it - the window is drawn where it really is, over
 * its workspace's wallpaper - and a release while peeking switches with the compositor's
 * animations off, so the workspace does not slide in behind the peeked window.
 *
 * ## Keys
 *
 * Hyprland matches binds before any surface sees a key, and taking keyboard focus to hear
 * Alt come up would take it away from the window being switched *from* on every tap (and
 * would lose the release outright while the surface is still being built). So the switcher
 * never holds the keyboard. Alt+Tab is a bind whose Lua function enters a submap in the same
 * compositor call - no round trip the release could overtake - and inside the submap Tab,
 * Shift+Tab, the arrows, Home/End, the letters and digits, Backspace, Delete, Enter and
 * Escape are binds too, with a catch-all swallowing the rest so nothing typed mid-switch
 * lands in the window being left. Each one reaches this object as a global shortcut, in
 * order. Pointer input is not affected: click still works.
 *
 * Alt coming up is the subtle one. Hyprland matches a release against the submap the key was
 * *pressed* in, and Alt went down before the submap was entered, so the release bind lives in
 * the root submap (transparent, so nothing else loses the key) and acts only while ours is
 * current. It decides inside the compositor: nothing typed, it leaves the submap and commits;
 * a search typed, it moves to the typing submap. The binds count what has been typed
 * themselves (`__ii_alt_tab_q`), so a release straight after a key can never race the shell.
 * Escape and Enter in the typing submap leave it inside the compositor too, so a shell that
 * died mid-switch can never strand the keyboard there - and a shell that starts finds and
 * undoes anything one before it left behind (`restoreChunk`).
 *
 * The binds are put on at runtime rather than written into keybinds.lua: they come and go
 * with the setting, and an Alt+Tab the user bound themselves is left alone (`conflict`).
 */
Singleton {
    id: root

    readonly property var options: Config.options?.windowSwitcher ?? null
    readonly property bool enabled: Config.ready && root.options?.enable === true
    readonly property bool includeOtherWorkspaces: root.options?.includeOtherWorkspaces ?? true
    /// Only the windows on the monitor Alt+Tab was pressed on.
    readonly property bool currentMonitorOnly: root.options?.currentMonitorOnly ?? false
    /// Peek at the whole destination workspace, not the lone window.
    readonly property bool peekWholeWorkspace: root.options?.peekWholeWorkspace ?? false
    /// The one-line key reminder under the switcher.
    readonly property bool showKeyHints: root.options?.showKeyHints ?? true

    /// Shown this long after Alt+Tab; a release before then switches without any UI at all.
    readonly property int quickTapMs: 150

    // ------------------------------------------------------------------ state

    /// Between Alt+Tab and the release (or Enter): the submap is engaged and a snapshot exists.
    property bool active: false
    /// The UI is on screen (after `quickTapMs`).
    property bool shown: false
    /// Alt came up with a search typed: the switcher stays, in the typing submap.
    property bool released: false
    /// The windows, most recently used first. Plain objects; see Logic.entryFor.
    property var entries: []
    property int selectedIndex: 0
    readonly property var selectedEntry: root.entries[root.selectedIndex] ?? null
    readonly property int count: root.entries.length
    /// Where it opened: the monitor holding the keyboard at Alt+Tab.
    property string screenName: ""
    /// The workspace on screen there at Alt+Tab; covers on any other say where they are.
    property int workspaceAtOpen: 0
    /// "island" or "panel", frozen at open so a setting changing mid-switch cannot swap faces.
    property string presenter: "panel"
    /// The panel's columns, for Up/Down. 0 (the island's single row) makes them Left/Right.
    property int columns: 0
    /// Bumped on every open, so a view can restart its entrance even if it never unloaded.
    property int openSerial: 0
    /// Which windows this switch is about, frozen at open: see Logic.wanted.
    property var filter: ({})
    /// Alt+` (the key over Tab): only this app's windows. "" for every app.
    property string appFilter: ""
    property string appFilterName: ""
    /**
     * The focused window as Hyprland last announced it: "" on an empty workspace, which
     * `Hyprland.activeToplevel` never says (it keeps the window you left). null until the
     * first focus change, when `activeToplevel` is all there is.
     */
    property var focusedAddress: null
    readonly property string currentAddress: root.focusedAddress !== null ? root.focusedAddress
        : Logic.normalisedAddress(Hyprland.activeToplevel?.address)

    /// An Alt+Tab bind that is not ours is in the way; the switcher stays unbound.
    property bool conflict: false
    /// Alt+` is the user's own: same-app switching stays unbound, Alt+Tab is unaffected.
    property bool sameAppConflict: false

    // ------------------------------------------------------------------ search

    /// Alt+letter on the desktop opens the switcher already searching (off: only inside it).
    readonly property bool searchAnywhere: root.options?.searchAnywhere ?? false
    /// The keys that type into the search, by keysym, with Alt held. Shift does not change them.
    readonly property var searchKeys: "abcdefghijklmnopqrstuvwxyz".split("").concat(["space"])
    /**
     * The digits, by key position (code:10 is the 1 key, code:19 the 0) so that they are the
     * top row on any layout - AZERTY's 1 is Shift+&. With nothing typed, 1-9 jump to that
     * window; once a search is going, they type.
     */
    readonly property var digitKeys: "1234567890".split("")
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
    /// Counting down to a peek: the views show it filling up.
    readonly property bool peekArming: peekTimer.running
    /**
     * The window the peek shows. Kept after the switcher closes, for the peek's fade-out.
     * null while peeking at nothing: a search that matches no window.
     */
    property var peekEntry: null
    /// A release after a peek, switching to this window: the peek holds until it has focus.
    /// Set before the switcher closes; "" when nothing moves (cancel, or already there).
    property string landingAddress: ""
    readonly property string selectedAddress: root.selectedEntry?.address ?? ""

    // ------------------------------------------------------------------ the model

    function appName(appClass: string): string {
        return String(TaskbarApps.getCachedDesktopEntry(appClass)?.name ?? "");
    }

    function toplevelsByAddress(): var {
        const map = {};
        for (const toplevel of (ToplevelManager.toplevels?.values ?? [])) {
            const address = Logic.normalisedAddress(toplevel?.HyprlandToplevel?.address);
            if (address.length > 0)
                map[address] = toplevel;
        }
        return map;
    }

    /// Every window on one workspace, for the peek at a whole workspace. Bindings calling it follow the window list.
    function workspaceEntries(workspaceId: int): var {
        const toplevels = root.toplevelsByAddress();
        return (HyprlandData.windowList ?? [])
            .filter(client => client && client.mapped !== false && client.hidden !== true
                && Number(client.workspace?.id ?? NaN) === workspaceId)
            .map(client => Logic.entryFor(client, toplevels, root.appName));
    }

    /// The regular workspace a monitor shows - what a special workspace is drawn over.
    function monitorWorkspace(monitorId: int): int {
        const monitor = (HyprlandData.monitors ?? []).find(m => Number(m?.id) === monitorId);
        return Number(monitor?.activeWorkspace?.id ?? 0);
    }

    function makeFilter(): var {
        return {
            "includeOtherWorkspaces": root.includeOtherWorkspaces,
            "visibleWorkspaceIds": HyprlandData.visibleWorkspaceIds,
            "monitor": root.currentMonitorOnly ? Number(Hyprland.focusedMonitor?.id ?? -1) : -1,
            "appClass": root.appFilter
        };
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
        return Logic.snapshot(HyprlandData.windowList, root.toplevelsByAddress(), root.filter,
            root.currentAddress, root.appName);
    }

    /**
     * A window list that changed under an open switcher. Order and selection stay put: a
     * switcher reshuffling while you aim at it is worse than a slightly stale one. Windows
     * that went away leave, new ones join at the end, titles follow.
     */
    function reconcile(): void {
        if (!root.active)
            return;
        const kept = Logic.reconcile(root.allEntries, HyprlandData.windowList, root.toplevelsByAddress(),
            Object.assign({}, root.filter, { "visibleWorkspaceIds": HyprlandData.visibleWorkspaceIds }), root.appName);
        root.replaceEntries(kept, root.selectedAddress);
    }

    function removeAddress(address: string): void {
        if (!root.active)
            return;
        root.replaceEntries(root.allEntries.filter(entry => entry.address !== address), root.selectedAddress);
    }

    /// `all` becomes the window list; what is shown is that list under the current query.
    function replaceEntries(all: var, selectedAddress: string): void {
        const oldIndex = root.selectedIndex;
        const list = Logic.filtered(all, root.query);
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

    /// A new query: the best match is selected; clearing it returns to the window you were on.
    function setQuery(text: string): void {
        const before = root.selectedAddress;
        root.query = text;
        const list = Logic.filtered(root.allEntries, text);
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

    /// One key typed. On the desktop (search-anywhere) it opens the switcher.
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

    /**
     * Escape with a search typed: the binds have already counted it cleared, and the switcher
     * stays. With none, they leave the submap themselves and send Cancel instead - this only
     * gets there if the shell and the binds disagree about the query.
     */
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

    /// Alt came up with a search typed: the binds moved to the typing submap; stay open.
    function releaseKey(): void {
        if (!root.active)
            return;
        if (root.query.length === 0) {
            // The binds counted a search the shell never saw: switch as a release would.
            root.leaveSubmap();
            root.commit();
            return;
        }
        root.released = true;
    }

    // ------------------------------------------------------------------ actions

    function open(direction: int): void {
        root.filter = root.makeFilter();
        const list = root.snapshot();
        root.screenName = Hyprland.focusedMonitor?.name ?? "";
        root.workspaceAtOpen = Number(Hyprland.focusedMonitor?.activeWorkspace?.id ?? 0);
        root.presenter = GlobalStates.islandOwnsWindowSwitcher ? "island" : "panel";
        root.query = "";
        root.released = false;
        root.allEntries = list;
        root.entries = list.slice();
        // Tab skips the window you are in. On an empty workspace there is none to skip, and
        // the first window is the one you just left.
        const first = list.length > 0 && list[0].address === root.currentAddress ? 1 : 0;
        root.selectedIndex = list.length <= first ? 0 : (direction > 0 ? first : list.length - 1);
        root.pointerOrigin = null;
        root.pointerLive = false;
        root.peeking = false;
        root.peekEntry = null;
        root.landingAddress = "";
        // Windows re-tiled by a bar or a scale change send no event, and the peek draws each
        // one where the list says it is: fresh geometry arrives through reconcile().
        HyprlandData.updateWindowList();
        root.openSerial++;
        root.active = true;
        if (list.length > 0)
            showTimer.restart();
    }

    /// Alt+Tab (and Alt+Shift+Tab) from the desktop: every app's windows.
    function openAll(direction: int): void {
        root.appFilter = "";
        root.appFilterName = "";
        root.open(direction);
    }

    /**
     * Alt+`: the focused app's windows only. Inside an open switcher the first press narrows it
     * to the selected window's app, and each one after steps through them.
     */
    function sameApp(delta: int): void {
        if (root.active && root.appFilter !== "") {
            root.step(delta);
            return;
        }
        const address = root.active ? root.selectedAddress : root.currentAddress;
        const client = (HyprlandData.windowList ?? []).find(c => Logic.normalisedAddress(c.address) === address);
        const appClass = String(client?.class || client?.initialClass || "");
        if (appClass === "") {
            // Nothing focused to match: an ordinary switch.
            if (!root.active)
                root.openAll(delta);
            else
                root.step(delta);
            return;
        }
        root.appFilter = appClass;
        root.appFilterName = root.appName(appClass) || appClass;
        if (!root.active) {
            root.open(delta);
            return;
        }
        // Narrowed in place: the window it was taken from leads, and the next one is selected.
        root.filter = Object.assign({}, root.filter, { "appClass": appClass });
        const from = root.selectedAddress;
        const list = root.snapshot();
        const at = list.findIndex(entry => entry.address === from);
        if (at > 0)
            list.unshift(list.splice(at, 1)[0]);
        root.replaceEntries(list, from);
        root.step(delta);
    }

    function step(delta: int): void {
        if (!root.active) {
            root.openAll(delta >= 0 ? 1 : -1);
            return;
        }
        root.selectedIndex = Logic.stepIndex(root.selectedIndex, delta, root.entries.length);
    }

    function stepRow(delta: int): void {
        // The panel's last grid can outlive it; the island is always one row.
        const columns = root.presenter === "panel" ? root.columns : 0;
        root.selectedIndex = Logic.stepRow(root.selectedIndex, delta, root.entries.length, columns);
    }

    function selectFirst(): void {
        if (root.active && root.entries.length > 0)
            root.selectedIndex = 0;
    }

    function selectLast(): void {
        if (root.active && root.entries.length > 0)
            root.selectedIndex = root.entries.length - 1;
    }

    /// Alt+1…9 with nothing typed: select window N; the release switches to it.
    function jump(digit: string): void {
        if (!root.active)
            return;
        const at = Logic.jumpIndex(digit, root.entries.length);
        if (at >= 0)
            root.selectedIndex = at;
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

    /// A click: commit to that window. The shell leaves the submap itself.
    function activate(index: int): void {
        if (!root.active || index < 0 || index >= root.entries.length)
            return;
        root.selectedIndex = index;
        root.leaveSubmap();
        root.commit();
    }

    /// A click outside the switcher while it waits with Alt up: let it go.
    function dismiss(): void {
        if (!root.active)
            return;
        root.leaveSubmap();
        root.cancel();
    }

    function commit(): void {
        if (!root.active)
            return;
        const entry = root.selectedEntry;
        const peeked = root.peeking && root.peekEntry !== null;
        const current = root.currentAddress;
        root.landingAddress = peeked && entry && entry.address !== current ? entry.address : "";
        root.finish();
        if (!entry)
            return;
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
        // as they were - on a compositor timer, so a shell that dies right now cannot leave
        // them off; the peek fades out over the result.
        Quickshell.execDetached(["hyprctl", "eval", `if __ii_alt_tab_animations == nil then
  __ii_alt_tab_animations = hl.get_config("animations.enabled")
end
hl.config({ animations = { enabled = false } })
${focus}
__ii_alt_tab_timer = hl.timer(function()
  ${root.restoreAnimationsLua}
end, { timeout = ${root.instantSwitchMs}, type = "oneshot" })`]);
    }

    /// How long animations stay off after a peeked switch, so the switch has landed.
    readonly property int instantSwitchMs: 150
    readonly property string restoreAnimationsLua: `if __ii_alt_tab_animations ~= nil then
    hl.config({ animations = { enabled = __ii_alt_tab_animations } })
    __ii_alt_tab_animations = nil
  end`

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

    /**
     * What a shell that died mid-switch can leave behind in the compositor: the keyboard in one
     * of our submaps, animations off. Run once as the service starts; on a clean start there is
     * nothing to find. (A config reload clears both as well - and the shell starting usually
     * brings one.)
     */
    readonly property string restoreChunk: `do
  local s = hl.get_current_submap()
  if s == "${root.submapName}" or s == "${root.typingSubmapName}" then hl.dispatch(hl.dsp.submap("reset")) end
  ${root.restoreAnimationsLua}
end`

    /**
     * The windows the peek has undimmed right now, one address a line (WindowSwitcherPeek).
     * A file, not a Lua global: a set_prop outlives a config reload, a Lua global does not,
     * and the shell starting reloads the config. Per session, so in the runtime directory.
     */
    readonly property string undimRecordPath: `${Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"}/ii-alt-tab-undimmed`

    /// Lua giving every window in `text` (the record) its own no_dim back.
    function redimChunk(text: string): string {
        return String(text ?? "").split("\n").map(line => Logic.normalisedAddress(line))
            .filter(address => /^0x[0-9a-fA-F]+$/.test(address))
            .map(address => `pcall(hl.dispatch, hl.dsp.window.set_prop({ window = "address:${address}", prop = "no_dim", value = "unset" }))`)
            .join("\n");
    }

    /// Windows a dead shell's peek left undimmed get their dim back; the record goes.
    Process {
        id: redimProc
        command: ["sh", "-c", 'cat "$0" 2>/dev/null; rm -f "$0"', root.undimRecordPath]
        stdout: StdioCollector {
            onStreamFinished: {
                const chunk = root.redimChunk(text);
                if (chunk.length > 0)
                    Quickshell.execDetached(["hyprctl", "eval", chunk]);
            }
        }
    }

    function cancel(): void {
        root.landingAddress = "";
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
        root.released = false;
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

    /// Once peeking, the peek follows the selection - to nothing at all when a search matches no window.
    function armPeek(): void {
        if (root.peeking) {
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
        if (root.peeking)
            root.peekEntry = root.selectedEntry;
    }

    /// Leave our submaps - and only ours, so a Virtual Machine submap is never reset under someone.
    function leaveSubmap(): void {
        Quickshell.execDetached(["hyprctl", "eval", `local s = hl.get_current_submap()
if s == "${root.submapName}" or s == "${root.typingSubmapName}" then hl.dispatch(hl.dsp.submap("reset")) end`]);
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
                root.removeAddress(Logic.normalisedAddress(event.data));
        }
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "activewindowv2")
                root.focusedAddress = Logic.normalisedAddress(event.data);
        }
    }

    // Until the first focus change Quickshell knows no active window at all (a fresh start
    // would Tab to the window you are in), so ask once.
    Process {
        id: focusSeed
        running: true
        command: ["hyprctl", "-j", "activewindow"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.focusedAddress !== null)
                    return;
                try {
                    root.focusedAddress = Logic.normalisedAddress(JSON.parse(text)?.address);
                } catch (e) {
                    // Not JSON: leave it to the events.
                }
            }
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

    readonly property var shortcutNames: ["Next", "Prev", "Commit", "Cancel", "Escape", "Release", "Close",
        "Backspace", "Left", "Right", "Up", "Down", "Home", "End", "SameNext", "SamePrev"]
        .concat(root.searchKeys.concat(root.digitKeys).map(key => `Key_${key}`))
        .concat(root.digitKeys.filter(key => key !== "0").map(key => `Jump_${key}`))

    function handle(name: string): void {
        if (name.startsWith("Key_")) {
            root.typeKey(name.slice(4));
            return;
        }
        if (name.startsWith("Jump_")) {
            root.jump(name.slice(5));
            return;
        }
        switch (name) {
        case "Next": root.step(1); break;
        case "Prev": root.step(-1); break;
        case "Commit": root.commit(); break;
        case "Cancel": root.cancel(); break;
        case "Escape": root.escapeKey(); break;
        case "Release": root.releaseKey(); break;
        case "Close": root.closeSelected(); break;
        case "Backspace": root.backspace(); break;
        case "Left": if (root.active) root.step(-1); break;
        case "Right": if (root.active) root.step(1); break;
        case "Up": if (root.active) root.stepRow(-1); break;
        case "Down": if (root.active) root.stepRow(1); break;
        case "Home": root.selectFirst(); break;
        case "End": root.selectLast(); break;
        case "SameNext": root.sameApp(1); break;
        case "SamePrev": root.sameApp(-1); break;
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
            // release, with no press before it. Commit, Cancel and Release only ever run once
            // each way: all three do nothing on a switcher they have already handled.
            onReleased: {
                if (modelData === "Commit" || modelData === "Cancel" || modelData === "Release")
                    root.handle(modelData);
            }
        }
    }

    // ------------------------------------------------------------------ the binds

    /**
     * The submaps: Alt held, and the search going on after Alt came up. Both renamed from
     * `__ii_alt_tab` when the typing submap arrived (and that from `__ii_window_switcher` when
     * typing did): a session still holding an old one (it lives until Hyprland reloads its
     * config) keeps it as an unused leftover instead of getting a second copy of every key
     * stacked into it. HyprlandBinds hides everything named with the `__ii_alt_tab` prefix.
     */
    readonly property string submapName: "__ii_alt_tab_hold"
    readonly property string typingSubmapName: "__ii_alt_tab_typing"
    readonly property string bindTag: "__ii_alt_tab"
    readonly property string bindDescription: "Shell: Window switcher"
    readonly property string bindDescriptionBack: "Shell: Window switcher (backwards)"
    readonly property string bindDescriptionSame: "Shell: Window switcher, this app"
    readonly property string bindDescriptionSameBack: "Shell: Window switcher, this app (backwards)"
    /// The key over Tab, by position: ` on QWERTY, ² on AZERTY.
    readonly property string sameAppKey: "code:49"

    /// The Lua that types one search key from inside the hold submap.
    function searchKeyBind(key: string): string {
        return `hl.bind("ALT + ${key}", function() __ii_alt_tab_key("${key}") end, { repeating = true })`;
    }

    /**
     * Everything that only has to exist once per config generation. A reload wipes binds,
     * submaps and Lua globals alike, so the global is the "already defined" flag - defining a
     * submap twice would stack a second copy of every bind in it.
     *
     * The hold submap's letters are bound with Alt (and Alt+Shift) spelled out rather than
     * with `ignore_mods`: type-to-search unbinds the bare letters as it arms and disarms, and
     * `hl.unbind` reaches into every submap. Alt is down for as long as that submap is current
     * anyway. The typing submap has to take bare letters, so it binds them afresh each time it
     * is entered (`__ii_alt_tab_typing_keys`), and type-to-search stays disarmed while the
     * switcher is open. Digits go by key position, which nothing else unbinds.
     *
     * `__ii_alt_tab_q` counts what has been typed: a letter adds one, Backspace takes one
     * away, Escape clears it. Alt coming up reads it to pick between switching and staying.
     */
    readonly property string defineChunk: `
if __ii_alt_tab_v ~= 2 then
  __ii_alt_tab_v = 2
  __ii_alt_tab_q = 0
  local S, T = "${root.submapName}", "${root.typingSubmapName}"
  local function g(n) hl.dispatch(hl.dsp.global("quickshell:windowSwitcher" .. n)) end
  local function ours() local s = hl.get_current_submap(); return s == S or s == T end
  local function finish(n) return function()
    if ours() then hl.dispatch(hl.dsp.submap("reset")); g(n) end
  end end
  function __ii_alt_tab_key(k) __ii_alt_tab_q = __ii_alt_tab_q + 1; g("Key_" .. k) end
  local function digit(d) return function()
    if __ii_alt_tab_q > 0 or d == "0" then __ii_alt_tab_key(d) else g("Jump_" .. d) end
  end end
  local function back() if __ii_alt_tab_q > 0 then __ii_alt_tab_q = __ii_alt_tab_q - 1 end; g("Backspace") end
  local function escape()
    if __ii_alt_tab_q > 0 and hl.get_current_submap() == S then __ii_alt_tab_q = 0; g("Escape")
    else finish("Cancel")() end
  end
  local letters = { ${root.searchKeys.map(key => `"${key}"`).join(", ")} }
  local digits = { ${root.digitKeys.map((key, i) => `{ "${key}", ${10 + i} }`).join(", ")} }
  function __ii_alt_tab_typing_keys()
    for _, k in ipairs(letters) do pcall(hl.unbind, k); pcall(hl.unbind, "SHIFT + " .. k) end
    hl.define_submap(T, function()
      for _, k in ipairs(letters) do
        hl.bind(k, function() __ii_alt_tab_key(k) end, { repeating = true })
        hl.bind("SHIFT + " .. k, function() __ii_alt_tab_key(k) end, { repeating = true })
      end
    end)
  end
  -- Alt up: switch - unless a search is typed, which then goes on with Alt up.
  local function release()
    if hl.get_current_submap() ~= S then return end
    if __ii_alt_tab_q > 0 then
      __ii_alt_tab_typing_keys()
      hl.dispatch(hl.dsp.submap(T)); g("Release")
    else
      hl.dispatch(hl.dsp.submap("reset")); g("Commit")
    end
  end
  for _, k in ipairs({ "ALT_L", "ALT_R" }) do
    hl.bind(k, release, { release = true, ignore_mods = true, transparent = true, description = "${root.bindTag}" })
  end
  local function common()
    hl.bind("Return", finish("Commit"), { ignore_mods = true })
    hl.bind("KP_Enter", finish("Commit"), { ignore_mods = true })
    hl.bind("Delete", function() g("Close") end, { ignore_mods = true })
    hl.bind("BackSpace", back, { ignore_mods = true, repeating = true })
    for _, k in ipairs({ "Left", "Right", "Up", "Down" }) do
      hl.bind(k, function() g(k) end, { ignore_mods = true, repeating = true })
    end
    hl.bind("Home", function() g("Home") end, { ignore_mods = true })
    hl.bind("End", function() g("End") end, { ignore_mods = true })
  end
  hl.define_submap(S, function()
    for _, k in ipairs({ "ALT_L", "ALT_R" }) do hl.bind(k, release, { release = true, ignore_mods = true }) end
    hl.bind("Escape", escape, { ignore_mods = true })
    common()
    for _, k in ipairs(letters) do
      hl.bind("ALT + " .. k, function() __ii_alt_tab_key(k) end, { repeating = true })
      hl.bind("ALT + SHIFT + " .. k, function() __ii_alt_tab_key(k) end, { repeating = true })
    end
    for _, d in ipairs(digits) do
      hl.bind("ALT + code:" .. d[2], digit(d[1]), { repeating = true })
      hl.bind("ALT + SHIFT + code:" .. d[2], digit(d[1]), { repeating = true })
    end
    hl.bind("catchall", function() end, { ignore_mods = true })
  end)
  hl.define_submap(T, function()
    hl.bind("Escape", finish("Cancel"), { ignore_mods = true })
    common()
    hl.bind("Tab", function() g("Next") end, { repeating = true })
    hl.bind("SHIFT + Tab", function() g("Prev") end, { repeating = true })
    for _, d in ipairs(digits) do
      hl.bind("code:" .. d[2], digit(d[1]), { repeating = true })
      hl.bind("SHIFT + code:" .. d[2], digit(d[1]), { repeating = true })
    end
    hl.bind("catchall", function() end, { ignore_mods = true })
  end)
end`

    /**
     * Search-anywhere: Alt+letter on the desktop enters the submap and types. Only keys nobody
     * else binds with Alt get one, and turning it off takes away only ours. Taking one away
     * (`hl.unbind`) also takes the submap's Alt+key, so that is put straight back. Never the
     * digits: Alt+1…9 only jump inside an open switcher.
     */
    function searchChunk(on: bool, ownership: var): string {
        const S = root.submapName;
        const lines = [];
        for (const key of root.searchKeys) {
            const owner = ownership[key] ?? "none";
            if (on && owner === "none") {
                lines.push(`hl.bind("ALT + ${key}", function() hl.dispatch(hl.dsp.submap("${S}")); __ii_alt_tab_q = 0; __ii_alt_tab_key("${key}") end, { description = "${root.bindTag}" })`);
            } else if (!on && owner === "ours") {
                lines.push(`pcall(hl.unbind, "ALT + ${key}")`);
                lines.push(`hl.define_submap("${S}", function() ${root.searchKeyBind(key)} end)`);
            }
        }
        return lines.join("\n");
    }

    function ourDescription(description: var): bool {
        return String(description ?? "").startsWith(root.bindTag);
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
            const ours = root.ourDescription(bind.description);
            owners[key] = ours && owners[key] !== "theirs" ? "ours" : "theirs";
        }
        return owners;
    }

    /**
     * The Alt+Tab (and Alt+`) entry binds, and the submaps' own copies with them:
     * `hl.unbind` takes a combination out of every submap at once, so whatever clears the
     * entry also clears the submaps', and they are only ever put back together.
     * `define_submap` on an existing submap adds to it. Alt+` is left alone when it is the
     * user's (`sameAppConflict`, read before this is built).
     */
    function entryChunk(on: bool, sameOn: bool): string {
        const S = root.submapName;
        const T = root.typingSubmapName;
        const K = root.sameAppKey;
        let chunk = `pcall(hl.unbind, "ALT + Tab") pcall(hl.unbind, "ALT + SHIFT + Tab")`;
        if (!root.sameAppConflict)
            chunk += ` pcall(hl.unbind, "ALT + ${K}") pcall(hl.unbind, "ALT + SHIFT + ${K}")`;
        const enter = name => `function() hl.dispatch(hl.dsp.submap("${S}")); __ii_alt_tab_q = 0; hl.dispatch(hl.dsp.global("quickshell:windowSwitcher${name}")) end`;
        const inside = name => `function() hl.dispatch(hl.dsp.global("quickshell:windowSwitcher${name}")) end`;
        if (on) {
            chunk += `
hl.bind("ALT + Tab", ${enter("Next")}, { description = "${root.bindDescription}" })
hl.bind("ALT + SHIFT + Tab", ${enter("Prev")}, { description = "${root.bindDescriptionBack}" })
for _, m in ipairs({ "${S}", "${T}" }) do
  hl.define_submap(m, function()
    hl.bind("ALT + Tab", ${inside("Next")}, { repeating = true })
    hl.bind("ALT + SHIFT + Tab", ${inside("Prev")}, { repeating = true })
  end)
end`;
        }
        if (on && sameOn) {
            chunk += `
hl.bind("ALT + ${K}", ${enter("SameNext")}, { description = "${root.bindDescriptionSame}" })
hl.bind("ALT + SHIFT + ${K}", ${enter("SamePrev")}, { description = "${root.bindDescriptionSameBack}" })
hl.define_submap("${S}", function()
  hl.bind("ALT + ${K}", ${inside("SameNext")}, { repeating = true })
  hl.bind("ALT + SHIFT + ${K}", ${inside("SamePrev")}, { repeating = true })
end)`;
        }
        return chunk;
    }

    /// Whether the root submap's Alt+Tab binds are ours, someone else's, or absent.
    function entryOwnership(binds: var): string {
        return root.comboOwnership(binds, bind => String(bind.key ?? "").toLowerCase() === "tab",
            [root.bindDescription, root.bindDescriptionBack]);
    }

    /// The same for Alt+` - by key position, or by the keysym it makes on the common layouts.
    function sameAppOwnership(binds: var): string {
        return root.comboOwnership(binds,
            bind => Number(bind.keycode ?? 0) === 49 || ["grave", "twosuperior", "dead_grave"].includes(String(bind.key ?? "")),
            [root.bindDescriptionSame, root.bindDescriptionSameBack]);
    }

    function comboOwnership(binds: var, matches: var, descriptions: var): string {
        let state = "none";
        for (const bind of binds) {
            if (String(bind.submap ?? "") !== "" || !matches(bind))
                continue;
            // ALT is 8, SHIFT 1.
            if (bind.modmask !== 8 && bind.modmask !== 9)
                continue;
            if (!descriptions.includes(bind.description))
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
                const sameOwnership = root.sameAppOwnership(binds);
                const searchOwners = root.searchOwnership(binds);
                root.searchConflicts = root.searchKeys.filter(key => searchOwners[key] === "theirs");
                root.conflict = ownership === "theirs";
                root.sameAppConflict = sameOwnership === "theirs";
                if (root.conflict) {
                    console.info("[WindowSwitcher] Alt+Tab is bound by the user's config; leaving it alone.");
                    root.applyDone();
                    return;
                }
                const searchOurs = root.searchKeys.some(key => searchOwners[key] === "ours");
                if (!root.pendingOn && ownership === "none" && sameOwnership !== "ours" && !searchOurs) {
                    root.applyDone();
                    return;
                }
                // Rewritten even when already ours: it restores the submap's Tab binds if
                // anything unbound Alt+Tab in the meantime.
                const sameOn = !root.sameAppConflict;
                const chunk = root.pendingOn
                    ? `${root.defineChunk}\n${root.entryChunk(true, sameOn)}\n${root.searchChunk(root.pendingSearch, searchOwners)}`
                    : `${root.entryChunk(false, false)}\n${root.searchChunk(false, searchOwners)}`;
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
    Component.onCompleted: {
        Quickshell.execDetached(["hyprctl", "eval", root.restoreChunk]);
        redimProc.running = true;
        root.apply();
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            // A reload takes our binds, the submaps and the guard with it.
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
