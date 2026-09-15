pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.services

/**
 * Type-to-search: with nothing on screen to type into, the first printable key opens the
 * launcher and lands in its search field, the way KRunner does.
 *
 * Hyprland matches keybinds before the key reaches any surface, so no Quickshell surface can
 * get in front of them - a layer surface only receives a key that no bind claimed. The only
 * lever is therefore a real bind per key, registered while nothing has keyboard focus and
 * taken away again the moment something does. Ordinary binds rather than a submap: a submap
 * would also suppress every shortcut the user already has, and an empty workspace is exactly
 * where Super + T still has to work.
 *
 * The binds point at global shortcuts rather than `exec`, so the first keystroke costs a
 * signal rather than a process launch.
 */
Singleton {
    id: root

    readonly property var options: Config.options?.launcher?.typeToSearch ?? null
    readonly property bool enabled: Config.ready && root.options?.enable === true
    readonly property string keySet: String(root.options?.keys ?? "all")
    readonly property string trigger: String(root.options?.trigger ?? "emptyWorkspace")

    // ------------------------------------------------------------------ the keys

    /**
     * keysym -> the character it types. Binds are matched on the keysym the active layout
     * produces, so the letters are layout-independent; the punctuation list carries the
     * unshifted top row of AZERTY and friends alongside the QWERTY one, which is why an
     * AZERTY keyboard arms on & and é rather than on nothing at all.
     *
     * Digits and punctuation are bound unshifted only. SHIFT + 1 is "!" on one layout and
     * "1" on another, and inserting the wrong character is worse than not arming.
     */
    readonly property var letterEntries: "abcdefghijklmnopqrstuvwxyz".split("")
        .map(letter => ({ "name": `typeToSearch_${letter}`, "keysym": letter, "character": letter, "shifted": true }))

    readonly property var digitEntries: "1234567890".split("")
        .map(digit => ({ "name": `typeToSearch_digit${digit}`, "keysym": digit, "character": digit, "shifted": false }))

    readonly property var punctuationTable: [
        ["minus", "-"], ["equal", "="], ["bracketleft", "["], ["bracketright", "]"],
        ["backslash", "\\"], ["semicolon", ";"], ["apostrophe", "'"], ["grave", "`"],
        ["comma", ","], ["period", "."], ["slash", "/"],
        // Unshifted on AZERTY and other Latin layouts, where the digit row types these instead.
        ["ampersand", "&"], ["eacute", "é"], ["quotedbl", "\""], ["parenleft", "("],
        ["egrave", "è"], ["ccedilla", "ç"], ["agrave", "à"], ["ugrave", "ù"],
        ["dollar", "$"], ["asterisk", "*"], ["exclam", "!"], ["colon", ":"],
        ["underscore", "_"], ["less", "<"]
    ]
    readonly property var punctuationEntries: root.punctuationTable
        .map(pair => ({ "name": `typeToSearch_${pair[0]}`, "keysym": pair[0], "character": pair[1], "shifted": false }))

    /// Every key the service can ever claim, whatever the key set is set to. A sweep has to
    /// take away what some earlier instance bound, and that instance's key set is not knowable.
    readonly property var allEntries: root.letterEntries.concat(root.digitEntries, root.punctuationEntries)

    readonly property var entries: {
        if (root.keySet === "letters")
            return root.letterEntries;
        if (root.keySet === "alphanumeric")
            return root.letterEntries.concat(root.digitEntries);
        return root.allEntries;
    }

    /// Every shortcut this service owns, so the shortcut browser can drop them from its list.
    readonly property string namePrefix: "typeToSearch_"

    // ------------------------------------------------------------------ when it arms

    /// Whether the workspace on the monitor being typed at holds no windows at all. With a
    /// second screen that is the monitor the cursor is over, not the desktop as a whole.
    readonly property bool workspaceEmpty: {
        const workspaceId = Number(HyprlandData.activeWorkspace?.id ?? NaN);
        if (!isFinite(workspaceId))
            return false;
        return !Array.from(HyprlandData.windowList ?? [])
            .some(window => Number(window?.workspace?.id ?? NaN) === workspaceId);
    }

    /**
     * Whether the keyboard belongs to a window the user can actually see.
     *
     * Hyprland keeps keyboard focus on windows that are no longer on screen - a window on the
     * other monitor while the cursor is over an empty desktop here, or a window just sent away
     * with a silent move. Asking "is anything focused anywhere" therefore never came true with
     * a second screen plugged in, and came true forever after Super + Alt + a number: two
     * different reports of the feature doing nothing at all.
     *
     * A window on a workspace this monitor is showing is the one in front of the user, and a
     * scratchpad on a special workspace is one of those.
     */
    readonly property bool focusedWindowOnScreen: {
        if (!ToplevelManager.activeToplevel)
            return false;
        // A window that cannot be placed is taken to own the keys: not arming is the safe half.
        return HyprlandData.toplevelOnScreen(ToplevelManager.activeToplevel);
    }

    /**
     * Shell surfaces take keyboard focus through layer-shell, which leaves no focused
     * toplevel behind - so without this every one of them would look like an empty desktop
     * and have its keystrokes stolen. A scratchpad counts too: its window is focused while
     * the workspace under it is genuinely empty.
     */
    readonly property bool shellSurfaceFocused: GlobalStates.overviewOpen
        || GlobalStates.searchOpen || GlobalStates.cheatsheetOpen || GlobalStates.sessionOpen
        || GlobalStates.screenLocked || GlobalStates.usageOpen || GlobalStates.modesOpen
        || GlobalStates.oskOpen || GlobalStates.overlayOpen || GlobalStates.settingsOpen
        || GlobalStates.dashboardPanelOpen || GlobalStates.policiesPanelOpen
        || GlobalStates.scratchpadOpen

    readonly property bool armed: root.enabled && !PanelFamily.isTablet
        && !root.focusedWindowOnScreen && !root.shellSurfaceFocused
        && (root.trigger === "noFocusedWindow" || root.workspaceEmpty)

    // ------------------------------------------------------------------ typing

    /// The start menu clears the query as it opens, so the Waffle seed has to land after it.
    property string pendingWaffleQuery: ""

    /**
     * Unbinding is a round trip through hyprctl, so a fast typist lands more keys while the
     * binds are still registered. A bind consumes the key - it never reached the search field
     * either - so those keys are appended here rather than dropped.
     *
     * Which half they are appended to matters. Until the launcher has read the opening query
     * it is still sitting in `activeSearchQuery`, and the read overwrites the field wholesale:
     * appending to `LauncherSearch.query` in that window writes into the half that is about to
     * be thrown away, which is what turned a fast "firefox" into "fx".
     */
    function typeCharacter(character: string): void {
        const text = String(character ?? "");
        if (text.length === 0)
            return;

        if (PanelFamily.isWaffle) {
            if (!GlobalStates.searchOpen) {
                root.pendingWaffleQuery = text;
                root.openedByTyping = true;
                root.typedQuerySeen = false;
                GlobalStates.searchOpen = true;
                Qt.callLater(() => {
                    if (root.pendingWaffleQuery.length === 0)
                        return;
                    LauncherSearch.query = root.pendingWaffleQuery;
                    root.pendingWaffleQuery = "";
                });
                return;
            }
            if (root.pendingWaffleQuery.length > 0)
                root.pendingWaffleQuery += text;
            else
                LauncherSearch.query = LauncherSearch.query + text;
            return;
        }

        if (GlobalStates.overviewOpen) {
            if (GlobalStates.activeSearchQuery.length > 0)
                GlobalStates.activeSearchQuery += text;
            else
                LauncherSearch.query = LauncherSearch.query + text;
            return;
        }

        // The same channel the prefix shortcuts use: it survives the launcher's lazy load,
        // and it is what stops Overview from clearing the query as it opens.
        GlobalStates.activeSearchQuery = text;
        // Before the open, not after: opening disarms synchronously, and a flag set afterwards
        // arrives one statement too late to stop the unbind.
        root.handingOff = true;
        handoffTimer.restart();
        root.openedByTyping = true;
        root.typedQuerySeen = false;
        GlobalStates.openSearch();
    }

    // ------------------------------------------------------------------ closing again

    /**
     * A launcher that let itself in when the desktop was typed on should let itself out when
     * the query it came in with is deleted - there was no deliberate "open the launcher"
     * gesture to undo. One opened from Super stays open on an empty query, which is what that
     * gesture asked for.
     */
    property bool openedByTyping: false
    /// Only after a query has actually been in the field does deleting it mean anything: the
    /// field is momentarily empty on the way in, before the opening character is read.
    property bool typedQuerySeen: false

    readonly property bool launcherOpen: PanelFamily.isWaffle ? GlobalStates.searchOpen : GlobalStates.overviewOpen

    onLauncherOpenChanged: {
        if (root.launcherOpen)
            return;
        root.openedByTyping = false;
        root.typedQuerySeen = false;
    }

    Connections {
        target: LauncherSearch
        function onQueryChanged() {
            if (!root.openedByTyping || !root.launcherOpen)
                return;
            if (LauncherSearch.query.length > 0) {
                root.typedQuerySeen = true;
                return;
            }
            // A panel or the AI surface owns the field and empties it on the way in. Closing
            // there would take the launcher away from under a panel the user just opened.
            if (!root.typedQuerySeen || GlobalStates.searchPanelActive)
                return;
            if (PanelFamily.isWaffle)
                GlobalStates.searchOpen = false;
            else
                GlobalStates.overviewOpen = false;
        }
    }

    /**
     * The launcher's surface takes keyboard focus a beat after it is asked to open, and a key
     * pressed in between reaches nothing at all: the bind is gone, and there is no focus for
     * the compositor to deliver to. Typing "firefox" at speed arrived as "fox" for exactly
     * that reason.
     *
     * So the binds stay on across the handover instead. While they do, a key is claimed by the
     * bind rather than by the search field, and `typeCharacter` appends it - the same character
     * either way, so which side wins the race stops mattering.
     */
    property bool handingOff: false

    Timer {
        id: handoffTimer
        interval: 450
        onTriggered: {
            root.handingOff = false;
            if (!root.armed)
                root.applyBinds(false);
        }
    }

    Instantiator {
        model: root.enabled ? root.entries : []
        delegate: GlobalShortcut {
            required property var modelData
            name: modelData.name
            // Deliberately not Translation.tr: a GlobalShortcut cannot be modified once
            // created, and a translated binding re-evaluates when the catalogue loads. These
            // never reach the shortcut browser anyway - HyprlandBinds filters them out.
            description: `Type-to-search: ${modelData.character}`
            onPressed: root.typeCharacter(modelData.character)
        }
    }

    // ------------------------------------------------------------------ the binds

    function bindStatements(on: bool): string {
        const lines = [];
        for (const entry of root.entries) {
            const combos = entry.shifted ? [entry.keysym, `SHIFT + ${entry.keysym}`] : [entry.keysym];
            for (const combo of combos) {
                // hl.unbind is undocumented and throws on a key it does not know, which would
                // abandon the rest of the batch. Every call is therefore its own pcall.
                lines.push(`pcall(hl.unbind, "${combo}")`);
                if (on)
                    lines.push(`pcall(hl.bind, "${combo}", hl.dsp.global("quickshell:${entry.name}"))`);
            }
        }
        return lines.join(" ");
    }

    /// What the last write put on the compositor, so a disarm knows what to take away even
    /// after the key set changed underneath it.
    property var appliedEntries: []

    function applyBinds(on: bool): void {
        const statements = on ? root.bindStatements(true) : root.releaseStatements();
        if (statements.length === 0)
            return;
        root.appliedEntries = on ? root.entries : [];
        Quickshell.execDetached(["hyprctl", "eval", statements]);
    }

    function releaseStatementsFor(entries: var): string {
        const lines = [];
        for (const entry of entries) {
            const combos = entry.shifted ? [entry.keysym, `SHIFT + ${entry.keysym}`] : [entry.keysym];
            for (const combo of combos)
                lines.push(`pcall(hl.unbind, "${combo}")`);
        }
        return lines.join(" ");
    }

    function releaseStatements(): string {
        return root.releaseStatementsFor(root.appliedEntries);
    }

    /**
     * A shell that was killed rather than shut down never gets to take its binds away, and a
     * bare-key bind with no shortcut left behind it still swallows the key: after `qs kill`
     * while armed, every letter is dead compositor-wide until something arms and disarms
     * again. So every key this service could ever have claimed is released once at startup,
     * before the first arm - which is also the only way a stranded set gets cleaned up.
     *
     * Only when the feature is on. Sweeping unconditionally would take away a bare-key bind
     * belonging to someone who never enabled it.
     */
    property bool sweepStarted: false
    property bool sweepDone: false

    Process {
        id: sweepProc
        onExited: root.sweepDone = true
    }

    function sweepStaleBinds(): void {
        if (!root.enabled || root.sweepStarted)
            return;
        root.sweepStarted = true;
        sweepProc.command = ["hyprctl", "eval", root.releaseStatementsFor(root.allEntries)];
        sweepProc.running = true;
    }

    onEnabledChanged: root.sweepStaleBinds()
    Component.onCompleted: root.sweepStaleBinds()

    /**
     * Arming waits: the window list is refreshed asynchronously, so the instant after a
     * window closes several of these predicates are still mid-flight. Disarming never waits -
     * a bind that outlives its condition eats a keystroke meant for an application.
     */
    Timer {
        id: armTimer
        interval: 250
        onTriggered: {
            if (!root.armed)
                return;
            // The sweep is a separate hyprctl call with no ordering against this one. Landing
            // it second would take away the binds that were just put on.
            if (!root.sweepDone) {
                armTimer.restart();
                return;
            }
            root.applyBinds(true);
        }
    }

    /// The key set can change under a live arm. Take the old binds away by the list that was
    /// actually written, then let the timer put the new one on.
    onEntriesChanged: {
        if (!root.armed)
            return;
        root.applyBinds(false);
        armTimer.restart();
    }

    onArmedChanged: {
        if (root.armed) {
            handoffTimer.stop();
            root.handingOff = false;
            armTimer.restart();
            return;
        }
        armTimer.stop();
        // Mid-handover the binds are the only thing still catching keys. The timer takes them
        // away once the launcher can catch its own.
        if (!root.handingOff)
            root.applyBinds(false);
    }

    /// Runtime binds are config state: a reload throws every one of them away without saying so.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name !== "configreloaded")
                return;
            root.appliedEntries = [];
            if (root.armed)
                armTimer.restart();
        }
    }

    Component.onDestruction: {
        if (root.appliedEntries.length > 0)
            Quickshell.execDetached(["hyprctl", "eval", root.releaseStatements()]);
    }
}
