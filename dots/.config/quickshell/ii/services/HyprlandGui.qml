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
 * Backing store for Settings -> Hyprland.
 *
 * Owns the `quickshell:managed` region at the end of each ~/.config/hypr/custom/*.lua file,
 * through `scripts/hyprland/hyprgui.py`. Reads three layers for every key and keeps them apart:
 *
 *   effective  - what Hyprland is actually doing, from a batched `hyprctl getoption`
 *   managed    - what this page put in the region
 *   inherited  - what hand-written Lua above the region, or another custom file, set
 *
 * A fourth layer sits above all of them: hyprland/shellOverrides/main.lua loads last, so a line
 * in it shadows anything set here. Nothing on this side ever writes to that file; the transient
 * overrides that do - Modes, Game Mode, the screen shader - remove their own keys again when they
 * end. A key of ours still sitting in there is therefore a leftover, and saving clears it, so a
 * setting made on this page is the last word rather than a change that quietly does nothing.
 *
 * Nothing here reaches disk on its own. An edit is staged, `dirty` goes true, and the page's
 * Save button writes every staged file in one go; Rollback throws the staging away. Writing on
 * every keystroke meant the compositor reloaded mid-thought - a half-typed rule matched nothing,
 * a keybind existed for the moment it took to pick its second half - and there was no way back
 * from a change other than making the opposite one.
 *
 * Every derived map below is rebuilt by `_reindex()` and *replaced only when its content
 * changed*. Identity is the contract: a map that reads equal keeps its old object, a binding
 * that hands back the same object does not notify, and a Repeater whose model kept its identity
 * does not rebuild its delegates. When they were ordinary bindings, one staged edit handed six
 * pages of controls a fresh copy of everything, and the whole shell stuttered on every click.
 */
Singleton {
    id: root

    readonly property string scriptPath: Quickshell.shellPath("scripts/hyprland/hyprgui.py")
    readonly property string customDir: FileUtils.trimFileProtocol(`${Directories.config}/hypr/custom`)
    readonly property string shellOverridesPath: FileUtils.trimFileProtocol(
        `${Directories.config}/hypr/hyprland/shellOverrides/main.lua`)

    /// Which custom file each kind of entry belongs in. Order matches hyprland.lua's require order.
    readonly property var targetFiles: ({
        general: `${root.customDir}/general.lua`,
        rules: `${root.customDir}/rules.lua`,
        keybinds: `${root.customDir}/keybinds.lua`,
        env: `${root.customDir}/env.lua`,
        variables: `${root.customDir}/variables.lua`
    })
    /// The order hyprland.lua requires these files in. Later wins, so the maps below build in
    /// this order and let a later file overwrite an earlier one. variables.lua is the odd one:
    /// hyprland.lua never requires it, hyprland/keybinds.lua does, at its very top - which is
    /// exactly why the app names it holds still reach every bind built below them.
    readonly property var loadOrder: ["env", "variables", "general", "rules", "keybinds"]
    readonly property var targetForKind: ({
        config: "general",
        device: "general",
        windowrule: "rules",
        layerrule: "rules",
        workspacerule: "rules",
        bind: "keybinds",
        unbind: "keybinds",
        env: "env",
        global: "variables"
    })

    /// Keys Appearance.qml re-pushes with `hyprctl eval` after every reload. A file can't win
    /// against that, so the hub shows them read-only and points at the page that really owns them.
    readonly property var shellOwnedKeys: ({
        "general:gaps_in": "windows",
        "general:gaps_out": "windows",
        "general:border_size": "windows",
        "general:col.active_border": "appearance",
        "group:col.border_active": "appearance",
        "group:groupbar:col.active": "appearance",
        "decoration:rounding": "windows",
        "decoration:blur:size": "windows"
    })

    property bool ready: false
    property bool busy: false
    /// target name -> the `hyprgui.py read` result for that file
    property var files: ({})
    /// key -> { value, type, set } from hyprctl
    property var effective: ({})
    /// key -> { value, line } set by shellOverrides/main.lua, which loads after us
    property var shadowed: ({})
    /// Keys whose effective value the hub asks hyprctl about. Tabs add to this as they load.
    property var watchedKeys: []
    /// The same keys as an object, so watch() does not walk the list once per control.
    property var _watchedSet: ({})
    /// The files whose staged entries differ from what is on disk, and how many entries in
    /// them changed. What the Save button and the strip above it are reading. Assigned by
    /// `_reindex()`, and only when the answer changed.
    property var pending: ({ targets: [], count: 0 })

    readonly property bool dirty: root.pending.targets.length > 0
    property string lastError: ""
    /// Hyprland's own log, kept beside the one-line message rather than inside it.
    property string lastLog: ""
    /// Pages hold a subscription while they are on screen. The service re-reads after every
    /// Hyprland reload only while something is looking at it, instead of forever.
    property int subscribers: 0
    /// True while the hub is on screen. The other Hyprland services read this so that closing
    /// Settings really does stop the work: they each re-read on every reload, and a reload
    /// happens for all sorts of reasons that have nothing to do with this page.
    readonly property bool watching: root.subscribers > 0

    /*
     * Every map the page reads. Not bindings: `_reindex()` rebuilds them in one pass whenever
     * the staged or stored entries move, and each one is handed out again only if its content
     * changed. Ten independent bindings walked all five files each; one binding for all ten
     * replaced every map on every edit. This is the shape where neither happens.
     */

    /// key -> value, for every config key this page manages.
    property var managedConfig: ({})

    /// key -> { value, file, line, target, removable } for the last hand-written line that sets
    /// it. `removable` is false when the parser could not pin the assignment down, in which case
    /// the page offers no cleanup for it.
    property var inheritedConfig: ({})

    /// global name -> the value this page wrote for it.
    property var managedGlobals: ({})

    /// global name -> { value, file, line } for the last hand-written assignment of it.
    property var inheritedGlobals: ({})

    /// env name -> the value this page wrote for it.
    property var managedEnv: ({})

    /// env name -> { value, file, line } for the last hand-written hl.env above the region.
    /// Only custom/env.lua is read here; what hyprland/env.lua sets before it, and what
    /// hyprland/variables.lua sets after it, are the Environment tab's own business.
    property var inheritedEnv: ({})

    /// device name -> the spec this page wrote for it, for the per-device cards.
    property var managedDevices: ({})

    /// What the hub's health strip needs, in one place: how much this page owns, how old the
    /// safety net is, and which of our settings something else overrides after load.
    property var status: ({ managed: 0, unrecognised: 0, files: [], backupAt: 0, shadowed: [] })

    signal changed
    signal wrote(string target)
    signal writeFailed(string target, string message)
    /**
     * A settled config reload. `own` says this side caused it, and `targets` names the files it
     * wrote; everything else that re-parses Hyprland's config listens here rather than to the
     * raw event, so the burst one write produces is coalesced once instead of once per service.
     */
    signal reloaded(bool own, var targets)

    // ------------------------------------------------------------- getting here

    /// Which tab the page should show the next time it lands. A request, not a state: the page
    /// clears it as it reads it, so opening Settings by hand afterwards lands where it was left.
    ///
    /// Section titles were the only way in before this, and they are translated - a deep link
    /// from elsewhere in the shell would have gone to the wrong tab in every language but one.
    property string pendingTab: ""

    /**
     * Opens Settings on this page, at `tab`.
     *
     * Callable from anywhere in the shell, including surfaces that have no settings window to
     * talk to yet - the tab is left here and picked up whenever the page finally loads.
     */
    function openTab(tab: string) {
        root.pendingTab = String(tab ?? "");
        GlobalStates.openSettingsPage("hyprland", "", "");
    }

    /// Reads the request and forgets it. Called by the page as it lands.
    function takePendingTab(): string {
        const tab = root.pendingTab;
        root.pendingTab = "";
        return tab;
    }

    // ---------------------------------------------------------------- reading

    /// Called by a page that wants live data for as long as it is on screen.
    function attach() {
        root.subscribers += 1;
        if (root.subscribers === 1 && root.ready) root.refresh();
    }

    function detach() {
        root.subscribers = Math.max(0, root.subscribers - 1);
        // Diff callbacks are closures owned by the page that asked. With nobody left watching,
        // delivering them would only reach objects that are being torn down.
        if (root.subscribers === 0) root._diffQueue = [];
    }

    /**
     * Re-read every file the page owns, in one process.
     *
     * This used to walk the five custom files and shellOverrides one interpreter start at a
     * time - six processes and about 230 ms for a job the parser itself does in 25 ms. One
     * `read` with six `--file`s answers in 60 ms.
     */
    function refresh() {
        if (readProc.running) {
            root._refreshAgain = true;
            return;
        }
        root.busy = true;
        root._readTargets = Object.keys(root.targetFiles).concat(["_shellOverrides"]);
        const command = [root.scriptPath, "read"];
        for (const target of root._readTargets) {
            command.push("--file");
            command.push(target === "_shellOverrides" ? root.shellOverridesPath
                : root.targetFiles[target]);
        }
        readProc.command = command;
        readProc.running = true;
    }

    /// Merge `keys` into the watched set and fetch their effective values.
    function watch(keys: var) {
        const wanted = Array.from(keys ?? []).filter(key => root._validKey(key));
        const fresh = [];
        for (const key of wanted) {
            if (root._watchedSet[key] === true) continue;
            root._watchedSet[key] = true;
            fresh.push(key);
        }
        if (fresh.length === 0) return;
        // A page has dozens of controls and every one of them calls this as it is built, so
        // the membership test is a lookup rather than a walk of the list so far.
        root.watchedKeys = root.watchedKeys.concat(fresh);
        root.refreshEffective(fresh);
    }

    function refreshEffective(keys: var) {
        const wanted = Array.from(keys ?? root.watchedKeys).filter(key => root._validKey(key));
        if (wanted.length === 0) return;
        root._optionQueue = root._optionQueue.concat(wanted);
        // Coalesced: a page has dozens of controls and each one asks for its own key as it is
        // created, all within the same turn. One batch for the page beats one process per row.
        optionDebounce.restart();
    }

    // ------------------------------------------------------ value resolution

    function effectiveValue(key: string): var {
        const entry = root.effective[key];
        return entry === undefined ? undefined : entry.value;
    }

    function managedValue(key: string): var {
        return root.managedConfig[key];
    }

    /// What a hand-written line above the fence, or another custom file, sets this key to.
    function inheritedValue(key: string): var {
        return root.inheritedConfig[key] ?? null;
    }

    /// Everything a control needs to render itself honestly. For one-off reads; a control that
    /// stays on screen should bind the pieces it needs instead, so it only hears about the
    /// layer that actually moved.
    function resolve(key: string): var {
        const live = root.effective[key];
        return {
            key: key,
            effective: live === undefined ? undefined : live.value,
            type: live?.type ?? "",
            known: live !== undefined,
            managed: root.managedConfig[key],
            isManaged: root.managedConfig.hasOwnProperty(key),
            inherited: root.inheritedConfig[key] ?? null,
            shadowedBy: root.shadowed[key] ?? null,
            shellOwnedBy: root.shellOwnedKeys[key] ?? ""
        };
    }

    /// The value a control should show: what this page set, else what Hyprland reports.
    function displayValue(key: string, fallback: var): var {
        if (root.managedConfig.hasOwnProperty(key)) return root.managedConfig[key];
        const live = root.effective[key];
        return live === undefined ? fallback : live.value;
    }

    /// The managed block of one file exactly as it sits on disk, for the review dialog.
    function regionText(target: string): string {
        return root.files[target]?.regionText ?? "";
    }

    function shellOwned(key: string): string {
        return root.shellOwnedKeys[key] ?? "";
    }

    function isShadowed(key: string): bool {
        return root.shadowed[key] !== undefined;
    }

    /// Layer rules for quickshell's own namespaces are re-pushed by Appearance.qml after each reload.
    function shellOwnedNamespace(namespace: string): bool {
        return /^\^?\(?quickshell/.test(String(namespace ?? ""));
    }

    // --------------------------------------------------------------- writing

    function setKey(key: string, value: var) {
        if (root.shellOwned(key) !== "") {
            console.warn("[HyprlandGui] refusing to manage shell-owned key:", key);
            return;
        }
        root._upsert({ kind: "config", id: key, key: key, value: value });
    }

    /// Stop managing a key. What it goes back to is whatever a hand-written line above the
    /// block says, or the compositor's own default - either way, from the next save's reload.
    function resetKey(key: string) {
        root._remove("config", key);
    }

    /// The override this page wrote for one device, or null when it does not manage it.
    function deviceSpec(name: string): var {
        return root.managedDevices[name] ?? null;
    }

    function setDevice(id: string, spec: var) {
        root._upsert({ kind: "device", id: id, spec: spec });
    }

    function removeDevice(id: string) {
        root._remove("device", id);
    }

    /// A plain Lua global, which is how hyprland/variables.lua names the app each shortcut
    /// opens. Not a config key and not an env var: an ordinary assignment the binds read.
    function setGlobal(name: string, value: var) {
        root._upsert({ kind: "global", id: name, name: name, value: value });
    }
    function removeGlobal(name: string) {
        root._remove("global", name);
    }

    function setEnv(name: string, value: string) {
        root._upsert({ kind: "env", id: name, name: name, value: String(value) });
    }
    function removeEnv(name: string) {
        root._remove("env", name);
    }

    /**
     * Run `fn` with every edit it makes staged as one change.
     *
     * A shortcut is four edits, a cursor theme four, an environment preset up to nine - and
     * each one used to replace the staged state on its own, so every list reading it was
     * rebuilt once per call instead of once per gesture. Inside a batch the edits land in a
     * working copy; the maps above move once, at the end.
     */
    function batch(fn: var) {
        if (root._batchDepth === 0) {
            root._batchDesired = Object.assign({}, root._desired);
            root._batchDirty = false;
        }
        root._batchDepth += 1;
        try {
            fn();
        } finally {
            root._batchDepth -= 1;
        }
        if (root._batchDepth > 0) return;
        const staged = root._batchDesired;
        root._batchDesired = ({});
        if (!root._batchDirty) return;
        root._batchDirty = false;
        root._desired = staged;
        root._reindex();
        root.changed();
    }

    /// Every entry that will be written into one file, in the order it will be written. The
    /// rules page groups these into its own sections itself; nothing else needs the raw list.
    function entriesFor(target: string): var {
        return root._entriesFor(target);
    }

    /**
     * One property per file, for the services that only care about their own.
     *
     * These re-evaluate whenever anything changes, but they hand back the very same array when
     * their own file did not - and QML does not notify a var property that resolves to the same
     * object. So editing a keyboard setting no longer rebuilds the whole shortcut list, and the
     * page's lists stop flickering on every unrelated change.
     */
    readonly property var generalEntries: root._entriesFor("general")
    readonly property var rulesEntries: root._entriesFor("rules")
    readonly property var keybindEntries: root._entriesFor("keybinds")
    readonly property var envEntries: root._entriesFor("env")
    readonly property var variableEntries: root._entriesFor("variables")

    function setRule(kind: string, id: string, spec: var) {
        root._upsert({ kind: kind, id: id, spec: spec });
    }
    function removeRule(kind: string, id: string) {
        root._remove(kind, id);
    }

    function setBind(id: string, entry: var) {
        root._upsert(Object.assign({ kind: "bind", id: id }, entry));
    }
    function removeBind(id: string) {
        root._remove("bind", id);
    }

    /// `id` defaults to the key. The shortcut editor passes a canonical id instead, so a
    /// release and the bind it belongs to are found together whichever way the key is spelled.
    function setUnbind(key: string, id: string) {
        const chosen = (id === undefined || id === null || id === "") ? key : id;
        root._upsert({ kind: "unbind", id: chosen, key: key });
    }
    function removeUnbind(key: string) {
        root._remove("unbind", key);
    }

    /// Delete the hand-written line outside the block that also sets `key`. `callback(result)`
    /// gets hyprgui.py's answer - `diff` on a dry run, `error` when it refused.
    function dropInherited(key: string, dryRun: bool, callback: var) {
        const info = root.inheritedConfig[key];
        if (!info || !info.removable || !root._validKey(key) || dropProc.running) {
            if (callback) callback({ ok: false, error: "nothing to remove" });
            return;
        }
        dropProc.callback = callback;
        dropProc.dryRun = dryRun;
        dropProc.result = null;
        dropProc.command = [root.scriptPath, "drop-key", "--file", root.targetFiles[info.target],
            "--key", key, "--custom-dir", root.customDir].concat(dryRun ? ["--dry-run"] : []);
        dropProc.running = true;
    }

    /**
     * Keys this page manages that `hyprland/shellOverrides/main.lua` also sets.
     *
     * That file is loaded after every custom file, so its line always wins: the edit is saved,
     * the compositor keeps the old value, and the page looks like it silently refused. The keys
     * the shell deliberately re-asserts on every reload (gaps, rounding, the accent colours) are
     * left out - clearing one of those would only have it written straight back.
     */
    readonly property var shadowingKeys: {
        const out = [];
        for (const key of Object.keys(root.managedConfig))
            if (root.shadowed[key] !== undefined && root.shellOwnedKeys[key] === undefined)
                out.push(key);
        return out;
    }

    /// Take the shadowing lines out of shellOverrides so this page's own value is the last word.
    /// Called by every save, and offered on its own where a single row reports the conflict.
    function clearShadowing(keys: var) {
        const wanted = Array.from(keys ?? root.shadowingKeys)
            .filter(key => root._validKey(key) && root.shellOwnedKeys[key] === undefined);
        if (wanted.length === 0) return;
        HyprlandConfig.resetMany(wanted, null);
    }

    /// Write every staged file. Hyprland picks the change up from the reload each write causes.
    ///
    /// The shadowing lines go first: they are in a different file, written by a different tool,
    /// and leaving them there is the one way a successful save can still change nothing.
    function save() {
        root.clearShadowing(root._shadowingAfterSave());
        root._flush();
    }

    /// What would be shadowed once the staged edits are on disk - the keys already managed plus
    /// the ones this save is about to add.
    function _shadowingAfterSave(): var {
        const out = {};
        for (const key of root.shadowingKeys) out[key] = true;
        for (const target of Object.keys(root._desired))
            for (const entry of root._desired[target])
                if (entry.kind === "config" && entry.key && root.shadowed[entry.key] !== undefined
                    && root.shellOwnedKeys[entry.key] === undefined)
                    out[entry.key] = true;
        return Object.keys(out);
    }

    /// Throw the staged edits away and go back to what the files say.
    function rollback() {
        if (Object.keys(root._desired).length === 0) return;
        root._desired = ({});
        root.lastError = "";
        root._reindex();
        root.changed();
        root.refresh();
    }

    /// Remove the managed region from every file, leaving hand-written Lua alone.
    function stripAll() {
        root._desired = ({});
        root._reindex();
        root._writeQueue = Object.keys(root.targetFiles).map(
            target => ({ target: target, strip: true, sent: null, reloadTick: 0 }));
        root._drainWrites();
    }

    /// Ask for a unified diff of what `save()` would do to one target. `callback(target, diff)`.
    /// Queued: the review dialog asks about all four files in a row.
    function previewDiff(target: string, callback: var) {
        root._diffQueue = root._diffQueue.concat([{ target: target, callback: callback }]);
        root._drainDiffs();
    }

    // ------------------------------------------------------------- internals

    /// target -> array of entries, present only once that target has an unwritten edit
    property var _desired: ({})
    /// target -> the entries on disk, cleaned once when the read lands
    property var _stored: ({})
    /// target -> each stored entry serialised once, when it lands: `byId` answers how many
    /// entries a staged file changes, `seq` whether it would be written back identical. The
    /// stored side never mutates in place, so serialising it per comparison was pure waste.
    property var _storedIndex: ({})
    /// name -> what the last publish of that derived map serialised to.
    property var _published: ({})
    property int _batchDepth: 0
    property var _batchDesired: ({})
    property bool _batchDirty: false
    property var _readTargets: []
    property var _optionQueue: []
    property var _writeQueue: []
    property var _diffQueue: []
    property bool _optionBusy: false
    /// Values fetched this run, folded together and published once when the queue drains.
    property var _effectiveDraft: null
    property bool _awaitingReload: false
    property bool _refreshAgain: false
    property bool _rereadAfterWrite: false
    /// Bumped on every reload Hyprland reports, so a write can tell whether the reload it was
    /// waiting for has already been and gone.
    property int _reloadTick: 0
    /// The files this side wrote and has not yet seen the reload for, so the reload can be told
    /// apart from someone editing the config by hand.
    property var _selfWrites: ({})
    property double _selfWriteAt: 0

    function _validKey(key: string): bool {
        return /^[A-Za-z0-9_.:-]+$/.test(String(key ?? ""));
    }

    /**
     * The entries one file would be written with: the pending edit if there is one, else what
     * is on disk.
     *
     * The stored side is cleaned once, when the read lands, and handed out by reference
     * afterwards. Sharing is safe because nothing mutates an entry in place: `_upsert` and
     * `_remove` both build a new array and replace whole entries.
     */
    function _entriesFor(target: string): var {
        if (root._desired[target] !== undefined) return root._desired[target];
        return root._stored[target] ?? [];
    }

    /// The same view for code that is editing: inside a batch, edits build on each other
    /// through the working copy rather than on the state the batch started from.
    function _workingEntries(target: string): var {
        const staged = root._batchDepth > 0 ? root._batchDesired : root._desired;
        if (staged[target] !== undefined) return staged[target];
        return root._stored[target] ?? [];
    }

    /// The parser's entries with the bookkeeping it adds for the review dialog taken off, so
    /// what goes back out is exactly what would be written.
    function _cleanEntries(entries: var): var {
        return Array.from(entries ?? []).map(entry => {
            const copy = Object.assign({}, entry);
            delete copy.line;
            delete copy.managed;
            delete copy.unrecognised;
            return copy;
        });
    }

    /// The cleaned entries, unless the array already held for `target` says the same - then
    /// that one. One write reloads every file; without this, all five would look new to
    /// everything reading them even though four of them were not touched.
    function _keepStored(target: string, cleaned: var): var {
        const current = root._stored[target];
        if (current !== undefined && ObjectUtils.canon(current) === ObjectUtils.canon(cleaned))
            return current;
        return cleaned;
    }

    /// Replace the stored side, re-serialising only the targets whose array actually moved.
    function _replaceStored(stored: var) {
        for (const target of Object.keys(stored)) {
            if (stored[target] === root._stored[target]) continue;
            const byId = {};
            const seq = [];
            for (const entry of stored[target]) {
                const json = ObjectUtils.canon(entry);
                seq.push(json);
                if (entry.kind !== "raw") byId[`${entry.kind} ${entry.id}`] = json;
            }
            root._storedIndex[target] = { byId: byId, seq: seq };
        }
        root._stored = stored;
    }

    function _findManaged(kind: string, id: string): var {
        const target = root.targetForKind[kind];
        if (!target) return undefined;
        return root._entriesFor(target).find(entry => entry.kind === kind && entry.id === id);
    }

    function _upsert(entry: var) {
        const target = root.targetForKind[entry.kind];
        if (!target) {
            console.warn("[HyprlandGui] no file owns entry kind", entry.kind);
            return;
        }
        if (!root.ready) {
            console.warn("[HyprlandGui] ignoring edit before the managed regions were read:", entry.id);
            return;
        }
        const entries = Array.from(root._workingEntries(target));
        const index = entries.findIndex(existing => existing.kind === entry.kind && existing.id === entry.id);
        if (index >= 0) entries[index] = entry;
        else entries.push(entry);
        root._stage(target, entries);
    }

    function _remove(kind: string, id: string) {
        const target = root.targetForKind[kind];
        if (!target || !root.ready) return;
        const entries = root._workingEntries(target).filter(entry => !(entry.kind === kind && entry.id === id));
        root._stage(target, entries);
    }

    function _stage(target: string, entries: var) {
        if (root._batchDepth > 0) {
            root._batchDesired[target] = entries;
            root._batchDirty = true;
            return;
        }
        const staged = Object.assign({}, root._desired);
        staged[target] = entries;
        root._desired = staged;
        root._reindex();
        root.changed();
    }

    /**
     * Rebuild every derived map in one pass and publish the ones that changed.
     *
     * Called wherever `_desired`, `_stored`, `files` or `shadowed` move. Publishing goes
     * through a content comparison, so a device edit does not hand every env row a new map,
     * and a reload that changed nothing hands out nothing at all.
     */
    function _reindex() {
        const managedConfig = {};
        const managedGlobals = {};
        const managedEnv = {};
        const managedDevices = {};
        const inheritedConfig = {};
        const inheritedGlobals = {};
        const inheritedEnv = {};
        const regionFiles = [];
        const shadowedKeys = [];
        let managed = 0;
        let unrecognised = 0;
        let backupAt = 0;

        for (const target of root.loadOrder) {
            for (const entry of root._entriesFor(target)) {
                if (entry.kind === "raw") {
                    unrecognised += 1;
                    continue;
                }
                managed += 1;
                if (entry.kind === "config" && entry.key) {
                    managedConfig[entry.key] = entry.value;
                    if (root.shadowed[entry.key] !== undefined) shadowedKeys.push(entry.key);
                } else if (entry.kind === "global" && entry.name) {
                    managedGlobals[entry.name] = entry.value;
                } else if (entry.kind === "env" && entry.name) {
                    managedEnv[entry.name] = entry.value;
                } else if (entry.kind === "device" && entry.spec?.name) {
                    managedDevices[entry.spec.name] = entry.spec;
                }
            }

            const file = root.files[target];
            if (!file) continue;
            if (file.hasRegion) regionFiles.push(root.targetFiles[target].split("/").pop());
            const stamp = file.backup?.mtime ?? 0;
            if (stamp > backupAt) backupAt = stamp;

            const name = String(file.file ?? "").split("/").pop();
            for (const entry of (file.unmanaged ?? [])) {
                if (entry.kind === "config" && entry.key) {
                    inheritedConfig[entry.key] = {
                        value: entry.value,
                        line: entry.line ?? 0,
                        target: target,
                        file: name,
                        removable: (entry.span ?? null) !== null
                    };
                } else if (entry.kind === "global" && entry.name) {
                    inheritedGlobals[entry.name] = {
                        value: entry.value, line: entry.line ?? 0, target: target, file: name
                    };
                } else if (entry.kind === "env" && entry.name) {
                    inheritedEnv[entry.name] = {
                        value: entry.value, line: entry.line ?? 0, target: target, file: name
                    };
                }
            }
        }

        root._publish("managedConfig", managedConfig);
        root._publish("managedGlobals", managedGlobals);
        root._publish("managedEnv", managedEnv);
        root._publish("managedDevices", managedDevices);
        root._publish("inheritedConfig", inheritedConfig);
        root._publish("inheritedGlobals", inheritedGlobals);
        root._publish("inheritedEnv", inheritedEnv);
        root._publish("status", {
            managed: managed,
            unrecognised: unrecognised,
            files: regionFiles,
            backupAt: backupAt,
            shadowed: shadowedKeys
        });
        root._publish("pending", root._computePending());
    }

    /// Assign one derived map, only if its content moved since the last publish.
    function _publish(name: string, next: var) {
        const json = ObjectUtils.canon(next);
        if (root._published[name] === json) return;
        root._published[name] = json;
        root[name] = next;
    }

    function _computePending(): var {
        const targets = [];
        let count = 0;
        for (const target of Object.keys(root._desired)) {
            const diff = root._diffStaged(target);
            if (diff.same) continue;
            targets.push(target);
            count += diff.changed;
        }
        return { targets: targets, count: count };
    }

    /**
     * How one staged file differs from the file on disk: whether it would be written back
     * identical, and how many entries changed. The lines the parser could not identify are
     * left out of the count - this page never edits them, so a number that included them could
     * not be acted on - but they still count towards `same`, because an order change is one.
     */
    function _diffStaged(target: string): var {
        const desired = root._desired[target] ?? [];
        const stored = root._stored[target] ?? [];
        if (desired === stored) return { same: true, changed: 0 };
        const index = root._storedIndex[target] ?? { byId: {}, seq: [] };
        let same = desired.length === index.seq.length;
        const seen = {};
        let changed = 0;
        for (let i = 0; i < desired.length; i++) {
            const entry = desired[i];
            const json = ObjectUtils.canon(entry);
            if (same && index.seq[i] !== json) same = false;
            if (entry.kind === "raw") continue;
            const id = `${entry.kind} ${entry.id}`;
            seen[id] = true;
            if (index.byId[id] !== json) changed += 1;
        }
        for (const id of Object.keys(index.byId))
            if (seen[id] !== true) changed += 1;
        return { same: same, changed: changed };
    }

    function _flush() {
        const queued = {};
        for (const job of root._writeQueue) queued[job.target] = true;
        // A staged file that matches the disk again is not written; it is simply forgotten.
        const staged = Object.assign({}, root._desired);
        let dropped = false;
        for (const target of Object.keys(staged)) {
            if (root.pending.targets.includes(target)) continue;
            delete staged[target];
            dropped = true;
        }
        if (dropped) {
            root._desired = staged;
            root._reindex();
        }
        const targets = root.pending.targets.filter(target => queued[target] !== true);
        if (targets.length === 0) return;
        root._writeQueue = root._writeQueue.concat(
            targets.map(target => ({ target: target, strip: false, sent: null, reloadTick: 0 })));
        root._drainWrites();
    }

    // Reading -------------------------------------------------------------

    function _finishRead() {
        root.busy = false;
        root.ready = true;
        root.changed();
        if (!root._refreshAgain) return;
        root._refreshAgain = false;
        root.refresh();
    }

    /// Every file in one answer. Applied together, so no map is ever built from a mix of the
    /// file as it was and the file as it is - and by identity, so a reload that changed
    /// nothing notifies nobody.
    function _applyReadAll(results: var) {
        const files = Object.assign({}, root.files);
        const stored = Object.assign({}, root._stored);
        let filesChanged = false;
        for (let i = 0; i < root._readTargets.length; i++) {
            const target = root._readTargets[i];
            const result = results[i];
            if (!result) continue;
            if (target === "_shellOverrides") {
                const map = {};
                for (const entry of (result.unmanaged ?? [])) {
                    if (entry.kind !== "config") continue;
                    map[entry.key] = { value: entry.value, line: entry.line };
                }
                if (ObjectUtils.canon(map) !== ObjectUtils.canon(root.shadowed)) root.shadowed = map;
                continue;
            }
            const current = root.files[target];
            if (current === undefined || ObjectUtils.canon(current) !== ObjectUtils.canon(result)) {
                files[target] = result;
                filesChanged = true;
            }
            stored[target] = root._keepStored(target, root._cleanEntries(result.entries));
        }
        root._replaceStored(stored);
        if (filesChanged) root.files = files;
        root._reindex();
    }

    // Effective values ----------------------------------------------------

    /**
     * Ask hyprctl for the queued keys, in batches.
     *
     * The queue is emptied here rather than on completion, so the guard has to be a flag this
     * function sets itself. Trusting `optionProc.running` instead lost whole batches: several
     * controls watch in the same turn, the process has not reported itself as running yet, and
     * the second call takes its own chunk off the queue and overwrites the command with it. The
     * page then showed defaults for everything except the last control that asked.
     */
    function _drainOptions() {
        if (root._optionBusy || root._optionQueue.length === 0) return;
        const seen = {};
        const queue = root._optionQueue.filter(key => {
            if (seen[key] === true) return false;
            seen[key] = true;
            return true;
        });
        const chunk = queue.slice(0, 60);
        root._optionQueue = queue.slice(60);
        root._optionBusy = true;
        optionProc.command = ["hyprctl", "-j", "--batch",
            chunk.map(key => `getoption ${key}`).join(" ; ")];
        optionProc.running = true;
    }

    function _finishOptions() {
        root._optionBusy = false;
        if (root._optionQueue.length > 0) {
            root._drainOptions();
            return;
        }
        // Published once per run, and only when a value moved: re-reading every watched key
        // after a reload used to hand every control a new map even though nothing changed.
        if (root._effectiveDraft !== null) {
            root.effective = root._effectiveDraft;
            root._effectiveDraft = null;
        }
        root.changed();
    }

    /// hyprctl --batch answers with bare JSON objects separated by blank lines, not an array.
    function _parseBatch(text: string): var {
        const out = [];
        let depth = 0;
        let start = -1;
        for (let i = 0; i < text.length; i++) {
            const c = text[i];
            if (c === "{") {
                if (depth === 0) start = i;
                depth++;
            } else if (c === "}") {
                depth--;
                if (depth !== 0 || start < 0) continue;
                try {
                    out.push(JSON.parse(text.slice(start, i + 1)));
                } catch (e) {
                    // A malformed chunk should not cost us the rest of the batch.
                }
                start = -1;
            }
        }
        return out;
    }

    function _applyOptions(objects: var) {
        let draft = root._effectiveDraft;
        for (const object of objects) {
            if (!object.option) continue;
            const type = Object.keys(object).find(name => name !== "option" && name !== "set");
            let value = type ? object[type] : undefined;
            // hyprctl spells an unset string option "[[EMPTY]]". Controls want "".
            if (value === "[[EMPTY]]") value = "";
            const held = (draft ?? root.effective)[object.option];
            if (held !== undefined && held.type === (type ?? "") && held.set === (object.set === true)
                && ObjectUtils.canon(held.value) === ObjectUtils.canon(value)) continue;
            if (draft === null) draft = Object.assign({}, root.effective);
            draft[object.option] = {
                value: value,
                type: type ?? "",
                set: object.set === true
            };
        }
        root._effectiveDraft = draft;
    }

    // Writing -------------------------------------------------------------

    function _drainDiffs() {
        if (diffProc.running || root._diffQueue.length === 0) return;
        const job = root._diffQueue[0];
        diffProc.diff = "";
        diffProc.target = job.target;
        diffProc.payload = JSON.stringify({ version: 1, entries: root._entriesFor(job.target) });
        diffProc.command = [root.scriptPath, "write", "--file", root.targetFiles[job.target],
            "--json", "-", "--custom-dir", root.customDir, "--dry-run"];
        diffProc.stdinEnabled = true;
        diffProc.running = true;
    }

    function _finishDiff() {
        const job = root._diffQueue[0];
        root._diffQueue = root._diffQueue.slice(1);
        if (job?.callback) job.callback(diffProc.target, diffProc.diff);
        root._drainDiffs();
    }

    function _drainWrites() {
        if (writeProc.running || root._writeQueue.length === 0) return;
        root.busy = true;
        const job = root._writeQueue[0];
        writeProc.job = job;
        writeProc.result = null;
        root.lastError = "";
        job.reloadTick = root._reloadTick;
        if (job.strip) {
            job.sent = null;
            writeProc.payload = "";
            writeProc.command = [root.scriptPath, "strip", "--file", root.targetFiles[job.target],
                "--custom-dir", root.customDir];
            writeProc.stdinEnabled = false;
        } else {
            // Held by reference: every edit replaces the whole array, so if what is staged is
            // still this same array when the write comes back, nothing was edited meanwhile.
            job.sent = root._entriesFor(job.target);
            writeProc.payload = JSON.stringify({ version: 1, entries: job.sent });
            writeProc.command = [root.scriptPath, "write", "--file", root.targetFiles[job.target],
                "--json", "-", "--custom-dir", root.customDir];
            writeProc.stdinEnabled = true;
        }
        writeProc.running = true;
    }

    function _finishWrite() {
        root._afterWrite(writeProc.job, writeProc.exitCode === 0 ? writeProc.result : null);
        root._writeQueue = root._writeQueue.slice(1);
        if (root._writeQueue.length > 0) {
            root._drainWrites();
            return;
        }
        root.busy = false;
        // No re-read here. The write hands back what it wrote, and the reload it causes brings
        // a full one along a moment later; reading in between only meant every change was read
        // three times over.
        if (root._rereadAfterWrite) {
            root._rereadAfterWrite = false;
            root.refresh();
        }
    }

    function _afterWrite(job: var, result: var) {
        if (!result || result.ok !== true) {
            root.lastError = result?.error ?? writeProc.stderrText ?? "";
            if (root.lastError === "") root.lastError = "hyprgui.py failed";
            root.writeFailed(job.target, root.lastError);
            root._rereadAfterWrite = true;
            return;
        }

        // What the file now holds, from the write itself. Reading it back instead left a gap in
        // which this side still believed the old contents, and an edit made during that gap was
        // built on them - which silently threw away the change that had just been written. The
        // write hands back the same record a read would, so nothing here is a partial update
        // and the reload it causes needs no read at all.
        if (result.record !== undefined) {
            const written = root._cleanEntries(result.record.entries ?? []);
            // Preferred by identity: when the file came back exactly as staged, the staged
            // array becomes the stored one, and nothing reading this file hears a change it
            // did not itself make.
            const kept = (job.sent !== null
                && ObjectUtils.canon(job.sent) === ObjectUtils.canon(written))
                ? job.sent : root._keepStored(job.target, written);
            const stored = Object.assign({}, root._stored);
            stored[job.target] = kept;
            root._replaceStored(stored);
            const files = Object.assign({}, root.files);
            files[job.target] = result.record;
            root.files = files;
        } else {
            root._rereadAfterWrite = true;
        }

        const staged = Object.assign({}, root._desired);
        // Only drop the pending edit if it is still the one that was written. Anything staged
        // while the write was in flight is a newer edit and has to go out in its own write.
        const superseded = job.sent !== null && staged[job.target] !== job.sent;
        if (!superseded) delete staged[job.target];
        root._desired = staged;
        root._reindex();

        root.wrote(job.target);
        if (!result.changed) return;
        const marks = Object.assign({}, root._selfWrites);
        marks[job.target] = true;
        root._selfWrites = marks;
        root._selfWriteAt = Date.now();
        // A file Hyprland was not watching yet only loads after an explicit reload.
        if (result.created) Quickshell.execDetached(["hyprctl", "reload"]);
        // Hyprland watches the file, so it can be done reloading before this side has finished
        // tidying up after the write that caused it. Waiting for a reload that already happened
        // is how the page came to announce that Hyprland had not reloaded, two seconds after it
        // had - and the banner then stayed up.
        if (root._reloadTick !== job.reloadTick) return;
        root._awaitingReload = true;
        canaryTimer.target = job.target;
        canaryTimer.restart();
    }

    // Processes ------------------------------------------------------------

    Process {
        id: readProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root._applyReadAll(JSON.parse(text).files ?? []);
                } catch (e) {
                    console.error("[HyprlandGui] cannot parse the read:", e);
                }
            }
        }
        onExited: (code, status) => Qt.callLater(root._finishRead)
    }

    Timer {
        id: optionDebounce
        interval: 40
        onTriggered: root._drainOptions()
    }

    Process {
        id: optionProc
        stdout: StdioCollector {
            onStreamFinished: root._applyOptions(root._parseBatch(text))
        }
        onExited: (code, status) => Qt.callLater(root._finishOptions)
    }

    Process {
        id: writeProc
        property var job: null
        property string payload: ""
        property var result: null
        property string stderrText: ""
        property int exitCode: 0
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    writeProc.result = JSON.parse(text);
                } catch (e) {
                    writeProc.result = null;
                }
            }
        }
        stderr: StdioCollector {
            // Kept aside rather than reported. Anything at all on stderr - a deprecation
            // warning from the interpreter, say - used to turn the page's banner red and
            // leave it red, because nothing ever put it back.
            onStreamFinished: writeProc.stderrText = text.trim()
        }
        onRunningChanged: {
            if (!writeProc.running || !writeProc.stdinEnabled) return;
            writeProc.write(writeProc.payload);
            writeProc.stdinEnabled = false;
        }
        onExited: (code, status) => {
            writeProc.exitCode = code;
            // stdout may still be draining; finish on the next turn so the result is in.
            Qt.callLater(root._finishWrite);
        }
    }

    Process {
        id: diffProc
        property string target: ""
        property string payload: ""
        property string diff: ""
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    diffProc.diff = JSON.parse(text).diff ?? "";
                } catch (e) {
                    diffProc.diff = "";
                }
            }
        }
        onRunningChanged: {
            if (!diffProc.running || !diffProc.stdinEnabled) return;
            diffProc.write(diffProc.payload);
            diffProc.stdinEnabled = false;
        }
        // stdout may still be draining; hand the diff over on the next turn so it is in.
        onExited: (code, status) => Qt.callLater(root._finishDiff)
    }

    Process {
        id: dropProc
        property var callback: null
        property bool dryRun: false
        property var result: null
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    dropProc.result = JSON.parse(text);
                } catch (e) {
                    dropProc.result = null;
                }
            }
        }
        // stdout may still be draining; answer on the next turn so the result is in.
        onExited: (code, status) => Qt.callLater(() => {
            const result = dropProc.result ?? { ok: false, error: "hyprgui.py failed" };
            if (dropProc.callback) dropProc.callback(result);
            dropProc.callback = null;
            if (!dropProc.dryRun && result.ok) root.refresh();
        })
    }

    /// A write that never produces a reload means Hyprland rejected the file or is not
    /// watching it. Say so, with the log, instead of leaving the UI showing a value that
    /// never took effect.
    Timer {
        id: canaryTimer
        property string target: ""
        interval: 2500
        onTriggered: {
            if (!root._awaitingReload) return;
            root._awaitingReload = false;
            logProc.target = canaryTimer.target;
            logProc.running = true;
        }
    }

    Process {
        id: logProc
        property string target: ""
        command: ["hyprctl", "rollinglog", "--num", "30"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.lastError = "Hyprland did not reload after the write.";
                root.lastLog = text.trim();
                root.writeFailed(logProc.target, root.lastError + "\n" + root.lastLog);
            }
        }
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name !== "configreloaded") return;
            root._reloadTick += 1;
            root._awaitingReload = false;
            canaryTimer.stop();
            // The reload is the proof the last write took: whatever the previous one said,
            // it is no longer true.
            root.lastError = "";
            root.lastLog = "";
            reloadDebounce.restart();
        }
    }

    /// One config write produces a burst of configreloaded events. Answer once, after it settles.
    Timer {
        id: reloadDebounce
        interval: 250
        onTriggered: {
            // Ours if a write of ours is still waiting for its reload. Two seconds is far more
            // than the gap between the file landing and the burst ending, and the cost of
            // guessing wrong is one stale read that the next reload corrects.
            const own = root._selfWriteAt > 0 && Date.now() - root._selfWriteAt < 2000;
            const targets = root._selfWrites;
            root._selfWrites = ({});
            root._selfWriteAt = 0;
            root.reloaded(own, targets);
            if (root.subscribers === 0) return;
            // A reload this side caused changed nothing this side does not already hold: the
            // write handed back the file in full. Reading all five again on every click was
            // most of what made a setting feel slow to apply.
            if (!own) root.refresh();
            root.refreshEffective(root.watchedKeys);
        }
    }

    Component.onCompleted: root.refresh()
}
