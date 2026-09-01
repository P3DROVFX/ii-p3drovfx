pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions

/**
 * Every keyboard shortcut Hyprland has, where it comes from, and what it would take to change it.
 *
 * `hyprctl binds -j` cannot answer the first question on a Lua config: every bind reports
 * `dispatcher: "__lua"` and an integer, so the compositor knows which key is taken and nothing
 * at all about what it does. The source files are therefore the truth about meaning, and
 * hyprctl is the truth about which keys are really registered. Both are read, and where they
 * disagree the page says so instead of picking one.
 *
 * Shortcuts are also additive: binding a key that is already bound registers both, and both
 * fire. Anything written from here is therefore written as a release followed by a bind, which
 * is the same pattern a hand-written custom/keybinds.lua ends up using.
 */
Singleton {
    id: root

    readonly property string parserPath: Quickshell.shellPath("scripts/hyprland/get_keybinds.py")
    readonly property string hyprDir: FileUtils.trimFileProtocol(`${Directories.config}/hypr`)
    readonly property string stockBindFile: `${root.hyprDir}/hyprland/keybinds.lua`
    readonly property string customBindFile: `${root.hyprDir}/custom/keybinds.lua`
    readonly property string stockVariableFile: `${root.hyprDir}/hyprland/variables.lua`

    property bool ready: false
    /// Every bind and unbind statement the two keybind files contain, in load order.
    property var parsed: []
    property var parsedFiles: []
    /// `hyprctl binds -j`: what is registered right now.
    property var live: []
    /// The shell's own global shortcuts, which is the list a bind can point `hl.dsp.global` at.
    property var globals: []
    /// Hand-written app variables in hyprland/variables.lua, the defaults a custom one replaces.
    property var stockVariables: ({})
    /// candidate command -> whether `command -v` finds it. Filled by the chain editor.
    property var available: ({})

    // ------------------------------------------------------------------ key combos

    readonly property var modAliases: ({
        "SHIFT": "SHIFT", "CAPS": "CAPS", "CAPSLOCK": "CAPS",
        "CTRL": "CTRL", "CONTROL": "CTRL",
        "ALT": "ALT", "MOD1": "ALT", "MOD2": "MOD2", "MOD3": "MOD3",
        "SUPER": "SUPER", "WIN": "SUPER", "LOGO": "SUPER", "MOD4": "SUPER", "MOD5": "MOD5"
    })
    readonly property var modBits: ({
        "SHIFT": 1, "CAPS": 2, "CTRL": 4, "ALT": 8, "MOD2": 16, "MOD3": 32, "SUPER": 64, "MOD5": 128
    })
    /// The order modifiers are written in, which is the order they are read out loud.
    readonly property var modOrder: ["CTRL", "SUPER", "ALT", "SHIFT", "CAPS", "MOD2", "MOD3", "MOD5"]
    readonly property var modLabels: ({
        "CTRL": "Ctrl", "SUPER": "Super", "ALT": "Alt", "SHIFT": "Shift", "CAPS": "Caps",
        "MOD2": "Mod2", "MOD3": "Mod3", "MOD5": "Mod5"
    })

    /// "SUPER + SHIFT + A" -> { mods: ["SUPER","SHIFT"], key: "A" }. A word that is not a
    /// modifier ends the run and is taken as the key, plus signs and all: quietly dropping it
    /// would turn a malformed combo into a plausible wrong one.
    function splitCombo(text: string): var {
        const parts = String(text ?? "").split("+").map(part => part.trim()).filter(part => part !== "");
        if (parts.length === 0) return { "mods": [], "key": "" };
        const mods = [];
        for (let index = 0; index < parts.length - 1; index++) {
            const name = root.modAliases[parts[index].toUpperCase()];
            if (name === undefined)
                return { "mods": root.sortMods(mods), "key": parts.slice(index).join("+") };
            if (!mods.includes(name)) mods.push(name);
        }
        return { "mods": root.sortMods(mods), "key": parts[parts.length - 1] };
    }

    function sortMods(mods: var): var {
        return Array.from(mods ?? []).slice().sort((a, b) => root.modOrder.indexOf(a) - root.modOrder.indexOf(b));
    }

    function modmaskOf(mods: var): int {
        let mask = 0;
        for (const mod of Array.from(mods ?? [])) mask |= (root.modBits[mod] ?? 0);
        return mask;
    }

    /// What two binds must share to be on the same key. Case folded, because Hyprland matches
    /// key names case-insensitively and stock writes Page_down where custom writes Page_Down.
    function canonical(mods: var, key: string): string {
        const sorted = root.sortMods(mods);
        return `${sorted.join("+")}${sorted.length > 0 ? "+" : ""}${String(key ?? "").toLowerCase()}`;
    }

    function comboOf(text: string): string {
        const parts = root.splitCombo(text);
        return root.canonical(parts.mods, parts.key);
    }

    /// The combo as Hyprland wants it written.
    function comboSource(mods: var, key: string): string {
        const sorted = root.sortMods(mods);
        return sorted.concat([String(key ?? "")]).filter(part => part !== "").join(" + ");
    }

    /// The combo as a person reads it.
    function comboLabel(mods: var, key: string): string {
        const named = root.sortMods(mods).map(mod => root.modLabels[mod] ?? mod);
        return named.concat([root.keyLabel(key)]).filter(part => part !== "").join(" + ");
    }

    readonly property var keyLabels: ({
        "Return": "Enter", "KP_Enter": "Numpad Enter", "Escape": "Esc", "Prior": "Page Up",
        "Next": "Page Down", "Page_Up": "Page Up", "Page_Down": "Page Down", "Print": "Print Screen",
        "Delete": "Delete", "BackSpace": "Backspace", "Slash": "/", "Backslash": "\\",
        "Period": ".", "Comma": ",", "Semicolon": ";", "Apostrophe": "'", "Minus": "-",
        "Equal": "=", "Space": "Space", "Tab": "Tab", "grave": "`", "bracketleft": "[",
        "bracketright": "]", "colon": ":", "KP_Divide": "Numpad /", "KP_Multiply": "Numpad *",
        "KP_Add": "Numpad +", "KP_Subtract": "Numpad -", "mouse_up": "Scroll up",
        "mouse_down": "Scroll down", "SUPER_L": "Super (left)", "SUPER_R": "Super (right)"
    })

    function keyLabel(key: string): string {
        const text = String(key ?? "");
        if (root.keyLabels[text] !== undefined) return root.keyLabels[text];
        if (/^mouse:\d+$/.test(text)) {
            const button = { "272": "Left click", "273": "Right click", "274": "Middle click",
                "275": "Back button", "276": "Forward button" }[text.slice(6)];
            return button ?? Translation.tr("Mouse button %1").arg(text.slice(6));
        }
        if (/^code:\d+$/.test(text)) return Translation.tr("Key code %1").arg(text.slice(5));
        if (/^XF86/.test(text)) return text.slice(4).replace(/([a-z])([A-Z])/g, "$1 $2");
        return text;
    }

    // ------------------------------------------------------------------- what a bind does

    /**
     * The actions the editor can build, as data. `template` is the Lua that gets written, with
     * %1 standing for the one thing a person fills in; matching an existing bind back to an
     * entry is the same template read the other way, so a shortcut written here reopens on the
     * control it was made with rather than as raw Lua.
     */
    readonly property var actionCatalogue: [
        { "id": "global", "icon": "widgets", "label": Translation.tr("Shell action"),
          "template": "hl.dsp.global(\"%1\")", "param": "global",
          "hint": Translation.tr("Something this shell does: a panel, the overview, a screenshot.") },
        { "id": "exec", "icon": "terminal", "label": Translation.tr("Run a command"),
          "template": "hl.dsp.exec_cmd(\"%1\")", "param": "command",
          "hint": Translation.tr("Runs through the shell, so pipes and && work.") },
        { "id": "closeWindow", "icon": "close", "label": Translation.tr("Close the window"),
          "template": "hl.dsp.window.close()" },
        { "id": "killWindow", "icon": "dangerous", "label": Translation.tr("Force the window to quit"),
          "template": "hl.dsp.exec_cmd(\"hyprctl kill\")" },
        { "id": "floatWindow", "icon": "picture_in_picture",
          "label": Translation.tr("Float or tile the window"),
          "template": "hl.dsp.window.float({ action = \"toggle\" })" },
        { "id": "fullscreen", "icon": "fullscreen", "label": Translation.tr("Fullscreen"),
          "template": "hl.dsp.window.fullscreen({ mode = \"fullscreen\", action = \"toggle\" })" },
        { "id": "maximize", "icon": "crop_square", "label": Translation.tr("Maximise"),
          "template": "hl.dsp.window.fullscreen({ mode = \"maximized\", action = \"toggle\" })" },
        { "id": "pinWindow", "icon": "push_pin", "label": Translation.tr("Pin to every workspace"),
          "template": "hl.dsp.window.pin()" },
        { "id": "centerWindow", "icon": "center_focus_weak", "label": Translation.tr("Centre the window"),
          "template": "hl.dsp.window.center()" },
        { "id": "focusDir", "icon": "open_with", "label": Translation.tr("Focus the window…"),
          "template": "hl.dsp.focus({ direction = \"%1\" })", "param": "direction" },
        { "id": "moveDir", "icon": "drag_pan", "label": Translation.tr("Move the window…"),
          "template": "hl.dsp.window.move({ direction = \"%1\" })", "param": "direction" },
        { "id": "swapDir", "icon": "swap_horiz", "label": Translation.tr("Swap with the window…"),
          "template": "hl.dsp.window.swap({ direction = \"%1\" })", "param": "direction" },
        { "id": "focusWorkspace", "icon": "space_dashboard", "label": Translation.tr("Go to workspace"),
          "template": "hl.dsp.focus({ workspace = \"%1\" })", "param": "workspace",
          "hint": Translation.tr("A number, or +1 / -1 for the next and previous one, or r+1 / r-1 to stay on this screen.") },
        { "id": "sendWorkspace", "icon": "move_down", "label": Translation.tr("Send the window to workspace"),
          "template": "hl.dsp.window.move({ workspace = \"%1\" })", "param": "workspace" },
        { "id": "sendWorkspaceSilent", "icon": "move_down",
          "label": Translation.tr("Send the window to workspace, and stay here"),
          "template": "hl.dsp.window.move({ workspace = \"%1\", silent = true })", "param": "workspace" },
        { "id": "scratchpad", "icon": "inventory_2", "label": Translation.tr("Toggle the scratchpad"),
          "template": "hl.dsp.workspace.toggle_special(\"special\")" },
        { "id": "splitRatio", "icon": "splitscreen", "label": Translation.tr("Change the split ratio"),
          "template": "hl.dsp.layout(\"splitratio %1\")", "param": "text",
          "hint": Translation.tr("+0.1 makes the focused window bigger, -0.1 smaller.") },
        { "id": "groupToggle", "icon": "tab_group", "label": Translation.tr("Group or ungroup the window"),
          "template": "hl.dsp.group.toggle()" },
        { "id": "groupNext", "icon": "tab", "label": Translation.tr("Next tab in the group"),
          "template": "hl.dsp.group.next()" },
        { "id": "groupPrev", "icon": "tab", "label": Translation.tr("Previous tab in the group"),
          "template": "hl.dsp.group.prev()" },
        { "id": "submap", "icon": "layers", "label": Translation.tr("Enter a key mode"),
          "template": "hl.dsp.submap(\"%1\")", "param": "text",
          "hint": Translation.tr("While a mode is on, only its own shortcuts work. \"reset\" leaves it.") },
        { "id": "dpms", "icon": "monitor", "label": Translation.tr("Turn the screens off"),
          "template": "hl.dsp.dpms(\"off\")" },
        { "id": "exit", "icon": "logout", "label": Translation.tr("Log out of Hyprland"),
          "template": "hl.dsp.exit()" },
        { "id": "pass", "icon": "arrow_forward", "label": Translation.tr("Do nothing (pass it through)"),
          "template": "hl.dsp.no_op()" }
    ]

    readonly property var directions: [
        { "value": "l", "label": Translation.tr("to the left") },
        { "value": "r", "label": Translation.tr("to the right") },
        { "value": "u", "label": Translation.tr("above") },
        { "value": "d", "label": Translation.tr("below") }
    ]

    function catalogueEntry(id: string): var {
        return root.actionCatalogue.find(entry => entry.id === id) ?? null;
    }

    /// Whitespace inside a call is not meaningful, and a bind written across three lines has to
    /// compare equal to the same call written on one.
    function normaliseLua(text: string): string {
        return String(text ?? "").replace(/\s+/g, " ").trim();
    }

    function escapeRegex(text: string): string {
        return String(text ?? "").replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    }

    /// Which catalogue entry an existing action was written with, and what was filled into it.
    function readAction(raw: string): var {
        const text = root.normaliseLua(raw);
        if (text === "") return { "id": "", "value": "", "raw": "" };
        // Fixed actions are tried first. "Force the window to quit" is a particular exec_cmd,
        // and the wildcard in "Run a command" would otherwise swallow it and show a shortcut
        // made from a button as a hand-typed command.
        for (const entry of root.actionCatalogue)
            if (entry.param === undefined && root.normaliseLua(entry.template) === text)
                return { "id": entry.id, "value": "", "raw": raw };
        for (const entry of root.actionCatalogue) {
            if (entry.param === undefined) continue;
            const template = root.normaliseLua(entry.template);
            const pattern = new RegExp("^" + root.escapeRegex(template).replace("%1", "(.*)") + "$");
            const found = text.match(pattern);
            if (found) return { "id": entry.id, "value": found[1], "raw": raw };
        }
        return { "id": "", "value": "", "raw": raw };
    }

    function buildAction(id: string, value: string): string {
        const entry = root.catalogueEntry(id);
        if (entry === null) return String(value ?? "");
        if (entry.param === undefined) return entry.template;
        return entry.template.replace("%1", String(value ?? ""));
    }

    /// name -> what the shell says that global shortcut does.
    readonly property var globalDescriptions: {
        const map = {};
        for (const shortcut of Array.from(root.globals ?? []))
            if (shortcut?.name) map[shortcut.name] = shortcut.description ?? "";
        return map;
    }

    /// One line of plain language for what a bind does, whatever it was written as.
    function actionSummary(raw: string): string {
        const text = root.normaliseLua(raw);
        if (text === "") return "";
        if (text.startsWith("function")) return Translation.tr("A block of Lua in the config file");
        const read = root.readAction(text);
        const entry = read.id === "" ? null : root.catalogueEntry(read.id);
        if (entry === null) return text;
        if (entry.id === "global") {
            const described = root.globalDescriptions[read.value];
            return described && described !== "" ? described : read.value;
        }
        if (entry.id === "exec") return Translation.tr("Runs %1").arg(read.value);
        if (entry.param === "direction") {
            const direction = root.directions.find(item => item.value === read.value);
            return `${entry.label} ${direction ? direction.label : read.value}`;
        }
        if (entry.param === undefined) return entry.label;
        return `${entry.label}: ${read.value}`;
    }

    // ------------------------------------------------------------------- the merged list

    /// Rows for the block this page owns, taken from the pending state rather than the file so
    /// an unsaved edit is on screen immediately.
    property var _memo: ({})

    readonly property var managedRows: {
        const out = [];
        for (const entry of HyprlandGui.keybindEntries) {
            if (entry.kind !== "bind" && entry.kind !== "unbind") continue;
            const parts = root.splitCombo(entry.key ?? "");
            const action = (entry.dispatcher && typeof entry.dispatcher === "object")
                ? (entry.dispatcher.__raw ?? "") : String(entry.dispatcher ?? "");
            const opts = entry.opts ?? {};
            out.push({
                "kind": entry.kind, "id": entry.id ?? entry.key, "combo": entry.key ?? "",
                "mods": parts.mods, "key": parts.key,
                "canonical": root.canonical(parts.mods, parts.key),
                "modmask": root.modmaskOf(parts.mods), "resolved": true, "managed": true,
                "action": action, "opts": opts,
                "description": String(opts.description ?? ""),
                "file": "custom/keybinds.lua", "line": 0, "section": "", "submap": "",
                "hidden": false, "complex": false, "releases": false, "alias": null,
                "rowId": `managed:${entry.id ?? entry.key}`
            });
        }
        return out;
    }

    /**
     * Everything hand-written, in the order Hyprland reads it. The managed block is dropped here
     * and re-added from the pending state instead, so it is never counted twice.
     *
     * Two ids are attached. `id` is the key, which is what a managed entry is filed under - it
     * answers "has this page taken this key over". `rowId` is the line, which answers "which of
     * the three binds on this key am I looking at"; a config can and does bind one key more than
     * once, so the two questions have different answers.
     */
    readonly property var handWritten: {
        const out = [];
        for (const entry of Array.from(root.parsed)) {
            if (entry.managed) continue;
            const row = Object.assign({}, entry);
            row.id = entry.resolved ? root.canonical(entry.mods, entry.key) : "";
            row.rowId = `${entry.file}:${entry.line}:${entry.key}`;
            out.push(row);
        }
        // Kept by identity: a save rewrites only the managed block, so the hand-written rows
        // come back equal and everything derived from them stays put.
        return ObjectUtils.keep(root._memo, "handWritten", out);
    }

    /**
     * What is actually bound, after every release has been applied.
     *
     * Hyprland's unbind removes what is already registered, so a file is read top to bottom:
     * a bind adds, an unbind takes away everything before it on that key, and a release-then-bind
     * does both. Lines whose key is built in a loop cannot be resolved and are carried through
     * untouched rather than guessed at.
     */
    readonly property var effective: root.resolveOrder(root.handWritten.concat(root.managedRows))

    function resolveOrder(rows: var): var {
        const out = [];
        for (const row of rows) {
            if (row.kind === "unbind") {
                if (!row.resolved) continue;
                for (let index = out.length - 1; index >= 0; index--)
                    if (out[index].canonical === row.canonical) out.splice(index, 1);
                continue;
            }
            if (row.resolved && row.releases)
                for (let index = out.length - 1; index >= 0; index--)
                    if (out[index].canonical === row.canonical) out.splice(index, 1);
            out.push(row);
        }
        return out;
    }

    /// Only the shortcuts a person would look for: named, on a key this page can read, and not
    /// inside a key mode. The rest are behind the tab's own "show everything" switch.
    readonly property var listed: root.effective.filter(row =>
        row.resolved && !row.hidden && row.description !== "")

    readonly property var unnamed: root.effective.filter(row =>
        row.resolved && (row.hidden || row.description === ""))

    readonly property var unreadable: root.effective.filter(row => !row.resolved)

    /// canonical -> how many binds are registered on it right now.
    readonly property var liveCounts: root.countByCombo(root.live)

    function countByCombo(binds: var): var {
        const map = {};
        for (const bind of Array.from(binds ?? [])) {
            const key = root.canonical(root.modsFromMask(bind.modmask ?? 0), bind.key ?? "");
            map[key] = (map[key] ?? 0) + 1;
        }
        return map;
    }

    function modsFromMask(mask: int): var {
        const out = [];
        for (const name of Object.keys(root.modBits))
            if ((mask & root.modBits[name]) !== 0) out.push(name);
        return root.sortMods(out);
    }

    /// The other shortcuts sitting on the same key. Two binds on one key both fire, which is
    /// sometimes deliberate (the stock config pairs a shell action with a fallback command) and
    /// sometimes an accident, so they are shown rather than judged.
    function othersOn(row: var): var {
        return root.effective.filter(other => other !== row && other.resolved
            && other.kind === "bind" && other.canonical === row.canonical);
    }

    /// Live binds whose key no readable source line accounts for: loops, generated binds, and
    /// anything a plugin registered.
    readonly property int unexplainedLive: {
        const known = {};
        for (const row of root.effective)
            if (row.resolved && row.kind === "bind") known[row.canonical] = true;
        let count = 0;
        for (const combo of Object.keys(root.liveCounts))
            if (!known[combo]) count += root.liveCounts[combo];
        return count;
    }

    // -------------------------------------------------------------------- categories

    /// The word before the colon in a description is the group the cheatsheet already uses.
    function categoryOf(row: var): string {
        const description = String(row?.description ?? "");
        const colon = description.indexOf(":");
        if (colon > 0) return description.slice(0, colon).trim();
        return String(row?.section ?? "") || Translation.tr("Other");
    }

    function titleOf(row: var): string {
        const description = String(row?.description ?? "");
        const colon = description.indexOf(":");
        if (colon > 0) return description.slice(colon + 1).trim();
        if (description !== "") return description;
        return root.actionSummary(row?.action ?? "");
    }

    /// Groups in the order they first appear, so the list reads like the file rather than
    /// like an alphabet.
    function grouped(rows: var): var {
        const order = [];
        const buckets = {};
        for (const row of Array.from(rows ?? [])) {
            const name = root.categoryOf(row);
            if (buckets[name] === undefined) {
                buckets[name] = [];
                order.push(name);
            }
            buckets[name].push(row);
        }
        return order.map(name => ({ "name": name, "rows": buckets[name] }));
    }

    /// rowId -> everything `matches` searches, lowercased. Filled lazily and dropped whenever
    /// the rows, the shell's global list or the language move: building one summary runs a
    /// dozen regular expressions, and the search box asks about every row on every keystroke.
    property var _searchCache: ({})

    function _searchText(row: var): string {
        const id = String(row.rowId ?? "");
        const held = root._searchCache[id];
        if (held !== undefined) return held;
        const text = [String(row.description ?? ""), root.comboLabel(row.mods, row.key),
            String(row.combo ?? ""), root.actionSummary(row.action ?? "")].join("\n").toLowerCase();
        if (id !== "") root._searchCache[id] = text;
        return text;
    }

    onEffectiveChanged: root._searchCache = ({})
    onGlobalsChanged: root._searchCache = ({})

    Connections {
        target: Translation

        function onLanguageCodeChanged() {
            root._searchCache = ({});
        }
    }

    function matches(row: var, query: string): bool {
        if (query === "") return true;
        return root._searchText(row).indexOf(query.toLowerCase()) >= 0;
    }

    /// A row the list shows without "show everything": named, readable, not inside a key mode.
    function isListed(row: var): bool {
        return row.resolved === true && row.hidden !== true && String(row.description ?? "") !== "";
    }

    // ---------------------------------------------------------------------- essentials

    /**
     * A set of shortcuts with no way to open a terminal, and no way to reach the session menu,
     * can only be repaired from a TTY. Both are checked against what is really bound, not
     * against what this page wrote, so a stock bind counts.
     */
    readonly property var essentials: [
        { "id": "terminal", "icon": "terminal", "label": Translation.tr("Open a terminal"),
          "test": /exec_cmd\(\s*terminal\b|\b(kitty|foot|alacritty|wezterm|konsole|ghostty|kgx|xterm)\b/ },
        { "id": "session", "icon": "power_settings_new", "label": Translation.tr("Reach the session menu"),
          "test": /quickshell:sessionToggle|wlogout|systemctl poweroff|loginctl (poweroff|terminate)/ }
    ]

    function essentialCovered(id: string): bool {
        const essential = root.essentials.find(item => item.id === id);
        if (!essential) return true;
        return root.effective.some(row => row.kind === "bind" && essential.test.test(String(row.action ?? "")));
    }

    readonly property var missingEssentials: root.essentials.filter(item => !root.essentialCovered(item.id))

    /// The shortcut bound to a global by that name, or null. Anything in the shell that can be
    /// reached by a global - a routine's trigger, so far - asks this before offering to bind it,
    /// so it can say "change the key" rather than quietly making a second one.
    function boundToGlobal(name: string): var {
        const wanted = String(name ?? "").trim();
        if (wanted === "") return null;
        return root.effective.find(row => {
            if (row.kind !== "bind" || !row.resolved) return false;
            const read = root.readAction(row.action ?? "");
            return read.id === "global" && String(read.value ?? "").trim() === wanted;
        }) ?? null;
    }

    /// True when this row is the only thing standing between the user and a keyboard they
    /// cannot rescue. The editor refuses to delete one of these.
    function isLastEssential(row: var): bool {
        if (!row || row.kind !== "bind") return false;
        for (const essential of root.essentials) {
            if (!essential.test.test(String(row.action ?? ""))) continue;
            const others = root.effective.filter(other => other !== row && other.kind === "bind"
                && essential.test.test(String(other.action ?? "")));
            if (others.length === 0) return true;
        }
        return false;
    }

    // ------------------------------------------------------------------------ writing

    /// A bind's id is its key, so editing one twice replaces it instead of stacking up.
    function bindId(mods: var, key: string): string {
        return root.canonical(mods, key);
    }

    function managedBind(id: string): var {
        return root.managedRows.find(row => row.kind === "bind" && row.id === id) ?? null;
    }

    /**
     * Write one shortcut: release whatever holds the key, then bind it.
     *
     * Both lines are removed and re-added rather than edited in place, because the release has
     * to come out of the file above the bind and entries are written in the order they were
     * added. `pcall` around the release is what makes it safe on a key nothing had bound.
     */
    function saveBind(id: string, combo: string, action: string, opts: var) {
        const cleaned = {};
        for (const key of Object.keys(opts ?? {}))
            if (opts[key] !== undefined && opts[key] !== false && opts[key] !== "")
                cleaned[key] = opts[key];
        HyprlandGui.batch(() => {
            HyprlandGui.removeBind(id);
            HyprlandGui.removeUnbind(id);
            HyprlandGui.setUnbind(combo, id);
            HyprlandGui.setBind(id, {
                "key": combo,
                "dispatcher": { "__raw": action },
                "opts": cleaned
            });
        });
    }

    function removeBind(id: string) {
        HyprlandGui.batch(() => {
            HyprlandGui.removeBind(id);
            HyprlandGui.removeUnbind(id);
        });
    }

    /// Take a shortcut away without putting anything in its place. Only meaningful for a bind
    /// that came from a file this page must not edit, which is why it writes a release alone.
    function releaseOnly(id: string, combo: string) {
        HyprlandGui.batch(() => {
            HyprlandGui.removeBind(id);
            HyprlandGui.removeUnbind(id);
            HyprlandGui.setUnbind(combo, id);
        });
    }

    function isReleased(id: string): bool {
        return root.managedRows.some(row => row.kind === "unbind" && row.id === id)
            && !root.managedRows.some(row => row.kind === "bind" && row.id === id);
    }

    // ------------------------------------------------------------------- default apps

    /**
     * The app each shortcut opens. hyprland/variables.lua sets these as plain Lua globals and
     * hyprland/keybinds.lua reads them while it builds the binds, so they are shortcuts settings
     * even though they are not binds.
     */
    readonly property var appVariables: [
        { "name": "terminal", "icon": "terminal", "label": Translation.tr("Terminal") },
        { "name": "browser", "icon": "language", "label": Translation.tr("Browser") },
        { "name": "fileManager", "icon": "folder", "label": Translation.tr("File manager") },
        { "name": "codeEditor", "icon": "code", "label": Translation.tr("Code editor") },
        { "name": "textEditor", "icon": "edit_note", "label": Translation.tr("Text editor") },
        { "name": "officeSoftware", "icon": "description", "label": Translation.tr("Office suite") },
        { "name": "taskManager", "icon": "monitoring", "label": Translation.tr("Task manager") },
        { "name": "volumeMixer", "icon": "volume_up", "label": Translation.tr("Volume mixer") },
        { "name": "settingsApp", "icon": "settings", "label": Translation.tr("System settings") }
    ]

    readonly property string launcher: "launch_first_available.sh"

    /**
     * The submap the shortcut editor parks Hyprland in while it is listening for a key. It has
     * to exist as a real submap with a real bind for Hyprland to accept it, so it turns up in
     * `hyprctl binds` - and it is not a shortcut anybody set, so it is dropped from the live
     * list below rather than shown as one.
     */
    readonly property string captureSubmap: "__quickshell_key_capture"
    /// Whether that submap exists right now. Defining it again would stack another copy of its
    /// bind onto the last, and a reload takes the whole thing away.
    property bool captureSubmapDefined: false

    /// Where a variable's value comes from now: this page, a hand-written custom file, or stock.
    function appSource(name: string): string {
        if (HyprlandGui.managedGlobals.hasOwnProperty(name)) return "managed";
        if (HyprlandGui.inheritedGlobals[name] !== undefined) return "custom";
        if (root.stockVariables[name] !== undefined) return "stock";
        return "";
    }

    function appValue(name: string): string {
        if (HyprlandGui.managedGlobals.hasOwnProperty(name))
            return String(HyprlandGui.managedGlobals[name] ?? "");
        const inherited = HyprlandGui.inheritedGlobals[name];
        if (inherited !== undefined) return String(inherited.value ?? "");
        return String(root.stockVariables[name] ?? "");
    }

    /**
     * Split "…/launch_first_available.sh 'kitty -1' 'foot'" into the candidates it tries in
     * order, keeping whatever came before the script so an environment prefix survives a
     * round trip.
     */
    function readChain(value: string): var {
        const text = String(value ?? "");
        const at = text.indexOf(root.launcher);
        if (at < 0) return { "chain": false, "prefix": "", "candidates": [], "plain": text };
        const head = text.slice(0, at + root.launcher.length);
        const tail = text.slice(at + root.launcher.length);
        const candidates = [];
        const pattern = /'((?:[^']|'\\'')*)'|"([^"]*)"|(\S+)/g;
        let found = pattern.exec(tail);
        while (found !== null) {
            const raw = found[1] ?? found[2] ?? found[3];
            candidates.push(found[1] !== undefined ? raw.replace(/'\\''/g, "'") : raw);
            found = pattern.exec(tail);
        }
        return { "chain": true, "prefix": head, "candidates": candidates, "plain": text };
    }

    function writeChain(prefix: string, candidates: var): string {
        const quoted = Array.from(candidates ?? [])
            // A hole in the list would otherwise be written as the literal word "undefined",
            // which is a command, and one that does not exist.
            .filter(candidate => typeof candidate === "string" || typeof candidate === "number")
            .map(candidate => String(candidate).trim())
            .filter(candidate => candidate !== "")
            .map(candidate => `'${candidate.replace(/'/g, "'\\''")}'`);
        return [String(prefix)].concat(quoted).join(" ");
    }

    /// What launch_first_available.sh itself tests: the first word of the candidate, because
    /// that is what it feeds to `command -v` before running the whole line.
    function probeWord(candidate: string): string {
        return String(candidate ?? "").trim().split(/\s+/)[0] ?? "";
    }

    function candidateAvailable(candidate: string): var {
        const word = root.probeWord(candidate);
        return word === "" ? null : (root.available[word] ?? null);
    }

    /// The candidate that would actually run, which is the first installed one.
    function winningCandidate(candidates: var): string {
        for (const candidate of Array.from(candidates ?? []))
            if (root.candidateAvailable(candidate) === true) return candidate;
        return "";
    }

    /// Which app variable the chain editor is on, for the same reason editId exists.
    property string editApp: ""

    function beginEditApp(name: string) {
        root.editApp = name;
    }

    function appEntry(name: string): var {
        return root.appVariables.find(variable => variable.name === name)
            ?? ({ "name": name, "icon": "apps", "label": name });
    }

    function saveApp(name: string, value: string) {
        HyprlandGui.setGlobal(name, value);
    }

    function resetApp(name: string) {
        HyprlandGui.removeGlobal(name);
    }

    /// Ask the shell which of the candidates exist. One process for the whole page: nine
    /// variables with a dozen fallbacks each is over a hundred lookups.
    function probeAll() {
        const words = {};
        for (const variable of root.appVariables)
            for (const candidate of root.readChain(root.appValue(variable.name)).candidates)
                words[root.probeWord(candidate)] = true;
        const list = Object.keys(words).filter(word => /^[A-Za-z0-9_.\/+-]+$/.test(word));
        if (list.length === 0) return;
        if (probeProc.running) {
            probeTimer.restart();
            return;
        }
        probeProc.command = ["bash", "-c",
            `for c in ${list.join(" ")}; do command -v "$c" >/dev/null 2>&1 && echo "ok $c" || echo "no $c"; done`];
        probeProc.running = true;
    }

    // --------------------------------------------------------------- the editing target

    /// What the shortcut editor is currently on. ConfigSubPageHost opens a URL and passes
    /// nothing, so the target has to sit where both ends can see it.
    property string editId: ""
    /// The particular line being edited, which is not the same question as which key it is on.
    property string editRowId: ""

    /**
     * The row the editor is on, as it stands now.
     *
     * After a save the original line is gone - it was replaced by a managed one - so the lookup
     * falls back to whatever this page now owns on that key. Without that, saving would make the
     * editor think the shortcut had been deleted.
     */
    readonly property var editing: root.effective.find(row => row.rowId === root.editRowId)
        ?? root.effective.find(row => row.kind === "bind" && row.managed && row.id === root.editId)
        ?? null
    /// True while the editor is making a shortcut that does not exist yet, which is the only
    /// time leaving without saving should throw the draft away.
    property bool editIsNew: false
    property var draft: ({})

    function beginEdit(row: var) {
        const read = root.readAction(row?.action ?? "");
        root.editId = row?.id ?? "";
        root.editRowId = row?.rowId ?? "";
        root.editIsNew = false;
        root.draft = {
            "id": row?.id ?? "",
            "mods": Array.from(row?.mods ?? []),
            "key": row?.key ?? "",
            "actionId": read.id,
            "actionValue": read.value,
            "actionRaw": read.raw,
            "description": String(row?.description ?? ""),
            "opts": Object.assign({}, row?.opts ?? {}),
            "wasManaged": row?.managed === true,
            "fromFile": String(row?.file ?? ""),
            "fromLine": row?.line ?? 0
        };
    }

    function beginNew() {
        root.editId = "";
        root.editRowId = "";
        root.editIsNew = true;
        root.draft = {
            "id": "", "mods": [], "key": "", "actionId": "global", "actionValue": "",
            "actionRaw": "", "description": "", "opts": {}, "wasManaged": false,
            "fromFile": "", "fromLine": 0
        };
    }

    /// Set when something outside Settings has asked for the editor to open on a draft it has
    /// already filled in. The Shortcuts tab reads it whenever it next exists, which is usually
    /// after the settings window has finished building - so this waits rather than being
    /// delivered.
    property bool pendingEditor: false

    /**
     * Starts a shortcut for `actionValue` and opens the editor on it.
     *
     * Everything a routine, a mode or a widget could want a key for is an action this editor
     * already knows, so the only thing they have to say is which one and what to call it.
     */
    function requestNewBind(actionId: string, actionValue: string, description: string) {
        // The tab first. Landing on it closes whatever sub-page was open, which would take the
        // editor down with it if the request had already opened one.
        HyprlandGui.openTab("shortcuts");
        root.beginNew();
        root.putDraft("actionId", String(actionId ?? "global"));
        root.putDraft("actionValue", String(actionValue ?? ""));
        root.putDraft("description", String(description ?? ""));
        root.pendingEditor = true;
    }

    /// Same, for a key that already exists. Offering "make one" when there is one already is how
    /// a second bind on the same action gets made, and both would fire.
    function requestEditBind(row: var) {
        if (!row) return;
        HyprlandGui.openTab("shortcuts");
        root.beginEdit(row);
        root.pendingEditor = true;
    }

    /// Reads the request and forgets it, so returning to the tab later does not reopen it.
    function takePendingEditor(): bool {
        if (!root.pendingEditor) return false;
        root.pendingEditor = false;
        return true;
    }

    function putDraft(key: string, value: var) {
        const next = Object.assign({}, root.draft);
        next[key] = value;
        root.draft = next;
    }

    function putDraftOption(key: string, value: var) {
        const opts = Object.assign({}, root.draft.opts ?? {});
        if (value === undefined || value === false) delete opts[key];
        else opts[key] = value;
        root.putDraft("opts", opts);
    }

    /// Everything wrong with the draft, in the order a person would fix it.
    readonly property var draftProblems: {
        const out = [];
        const draft = root.draft ?? {};
        if (!draft.key || String(draft.key).trim() === "")
            out.push(Translation.tr("Choose a key."));
        const action = root.buildAction(draft.actionId ?? "", draft.actionValue ?? "");
        if (root.normaliseLua(action) === "")
            out.push(Translation.tr("Choose what it should do."));
        const entry = root.catalogueEntry(draft.actionId ?? "");
        if (entry && entry.param !== undefined && String(draft.actionValue ?? "").trim() === "")
            out.push(Translation.tr("Fill in what this action needs."));
        // Hyprland refuses these pairings ("flags e is mutually exclusive with r and o", "flags c
        // and g are mutually exclusive") - and does it silently, with no config error: the bind
        // simply never registers. Saying so here is the only warning anyone gets.
        const opts = draft.opts ?? {};
        if (opts.repeating === true && (opts.release === true || opts.long_press === true))
            out.push(Translation.tr("Repeat while held cannot be combined with firing when the key is let go or on a long press. Hyprland would drop the shortcut."));
        if (opts.click === true && opts.drag === true)
            out.push(Translation.tr("A mouse shortcut fires either on the click or while dragging, not both."));
        return out;
    }

    function commitDraft() {
        if (root.draftProblems.length > 0) return false;
        const draft = root.draft;
        const combo = root.comboSource(draft.mods, draft.key);
        const id = root.bindId(draft.mods, draft.key);
        const opts = Object.assign({}, draft.opts ?? {});
        if (String(draft.description ?? "").trim() !== "") opts.description = draft.description.trim();
        else delete opts.description;
        HyprlandGui.batch(() => {
            // Moving a shortcut to a different key leaves the old release behind otherwise.
            if (draft.id && draft.id !== id) root.removeBind(draft.id);
            root.saveBind(id, combo, root.buildAction(draft.actionId, draft.actionValue), opts);
        });
        root.editId = id;
        root.editRowId = `managed:${id}`;
        root.editIsNew = false;
        return true;
    }

    // ------------------------------------------------------------------------ reading

    function refresh() {
        root.stale = false;
        if (!parseProc.running) parseProc.running = true;
        if (!liveProc.running) liveProc.running = true;
        if (!globalsProc.running) globalsProc.running = true;
        if (!stockProc.running) stockProc.running = true;
    }

    /**
     * Re-parsing costs four processes, so it happens when someone is reading rather than on
     * every reload for the rest of the session. The Shortcuts tab holds the page open; a
     * routine's trigger form asks for itself with ensureFresh().
     */
    property bool stale: false

    function ensureFresh() {
        if (root.stale || !root.ready) root.refresh();
    }

    Component.onCompleted: root.refresh()

    Connections {
        target: HyprlandGui
        function onWatchingChanged() {
            if (HyprlandGui.watching) root.ensureFresh();
        }
    }

    Connections {
        target: HyprlandGui

        // HyprlandGui has already gathered the burst one write produces into a single report,
        // so there is nothing left to debounce here. A reload it caused itself only matters if
        // it wrote one of the two files this parser reads.
        function onReloaded(own, targets) {
            // A reload rebuilds every bind, so whatever the key editor defined is gone with them.
            root.captureSubmapDefined = false;
            if (own && targets.keybinds !== true && targets.variables !== true) return;
            root.stale = true;
            if (HyprlandGui.watching) root.refresh();
        }
    }

    Process {
        id: parseProc
        command: [root.parserPath, "--flat", "--path", root.stockBindFile, "--path", root.customBindFile]
        stdout: StdioCollector {
            onStreamFinished: {
                let parsed;
                try {
                    parsed = JSON.parse(text);
                } catch (error) {
                    console.warn("[HyprlandBinds] cannot parse keybind files:", error);
                    return;
                }
                // Replaced only on change, so a re-parse that found the same files does not
                // rebuild the shortcut list and everything hanging off it.
                const files = parsed.files ?? [];
                if (ObjectUtils.canon(files) !== ObjectUtils.canon(root.parsedFiles))
                    root.parsedFiles = files;
                const binds = parsed.binds ?? [];
                if (ObjectUtils.canon(binds) !== ObjectUtils.canon(root.parsed))
                    root.parsed = binds;
                root.ready = true;
                probeTimer.restart();
            }
        }
    }

    Process {
        id: liveProc
        command: ["hyprctl", "binds", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const live = JSON.parse(text)
                        .filter(bind => bind.submap !== root.captureSubmap);
                    if (ObjectUtils.canon(live) !== ObjectUtils.canon(root.live)) root.live = live;
                } catch (error) {
                    console.warn("[HyprlandBinds] cannot parse hyprctl binds:", error);
                }
            }
        }
    }

    Process {
        id: globalsProc
        command: ["hyprctl", "globalshortcuts", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const globals = JSON.parse(text);
                    if (ObjectUtils.canon(globals) !== ObjectUtils.canon(root.globals))
                        root.globals = globals;
                } catch (error) {
                    root.globals = [];
                }
            }
        }
    }

    Process {
        id: stockProc
        command: [HyprlandGui.scriptPath, "read", "--file", root.stockVariableFile]
        stdout: StdioCollector {
            onStreamFinished: {
                let parsed;
                try {
                    parsed = JSON.parse(text);
                } catch (error) {
                    return;
                }
                const map = {};
                for (const entry of Array.from(parsed.unmanaged ?? []))
                    if (entry.kind === "global" && entry.name) map[entry.name] = entry.value;
                if (ObjectUtils.canon(map) !== ObjectUtils.canon(root.stockVariables))
                    root.stockVariables = map;
                probeTimer.restart();
            }
        }
    }

    Timer {
        id: probeTimer
        interval: 250
        onTriggered: root.probeAll()
    }

    Process {
        id: probeProc
        stdout: StdioCollector {
            onStreamFinished: {
                const map = Object.assign({}, root.available);
                let changed = false;
                for (const line of String(text).split("\n")) {
                    const parts = line.trim().split(" ");
                    if (parts.length !== 2) continue;
                    const found = parts[0] === "ok";
                    if (map[parts[1]] === found) continue;
                    map[parts[1]] = found;
                    changed = true;
                }
                // Almost every probe finds exactly what the last one did. Assigning the map
                // anyway would rebuild every row that reads it, for no news.
                if (changed) root.available = map;
            }
        }
    }
}
