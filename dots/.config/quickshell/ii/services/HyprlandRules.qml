pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.functions

/**
 * The rule half of Settings -> Hyprland: what Hyprland will accept, what this page has written,
 * and what any of it currently matches.
 *
 * Everything about a rule that is not drawing lives here. The tab and both of its sub-pages read
 * the same model, which is also how a sub-page knows what it was opened for: ConfigSubPageHost
 * loads a URL and nothing else, so the thing being edited has to sit somewhere both ends can see.
 *
 * The vocabularies below were read out of the running compositor rather than off a wiki page.
 * A function can never be a valid value for any field, so `hl.window_rule({ f = print })` answers
 * with either "unknown field" or that field's real type - and adds nothing to the config either
 * way. Everything in `windowEffects`, `layerEffects` and `workspaceEffects` came back from
 * Hyprland 0.56.2 that way; anything it did not recognise is not in the lists.
 */
Singleton {
    id: root

    // ------------------------------------------------------------------ vocabulary

    /**
     * The fields `hl.window_rule` accepts, with the type it wants and the words a person would
     * use for it. `type` picks the editor: bool, int, float, string, enum, vec2, gradient.
     * `common: true` is the shortlist an app card offers before you go looking for the rest.
     */
    readonly property var windowEffects: [
        { "key": "float", "type": "bool", "icon": "picture_in_picture",
          "label": Translation.tr("Always float"), "common": true },
        { "key": "tile", "type": "bool", "icon": "grid_view",
          "label": Translation.tr("Always tile"), "common": true },
        { "key": "center", "type": "bool", "icon": "center_focus_weak",
          "label": Translation.tr("Open centred"), "common": true },
        { "key": "pin", "type": "bool", "icon": "push_pin",
          "label": Translation.tr("Pin to every workspace") },
        { "key": "fullscreen", "type": "bool", "icon": "fullscreen",
          "label": Translation.tr("Open fullscreen") },
        { "key": "maximize", "type": "bool", "icon": "crop_free",
          "label": Translation.tr("Open maximised") },
        { "key": "pseudo", "type": "bool", "icon": "aspect_ratio",
          "label": Translation.tr("Pseudo-tile") },
        { "key": "size", "type": "vec2", "icon": "resize", "common": true,
          "label": Translation.tr("Size"), "placeholder": "(monitor_w*0.5)",
          "hint": Translation.tr("Pixels, a percentage, or an expression like (monitor_w*0.5).") },
        { "key": "move", "type": "vec2", "icon": "drag_pan", "common": true,
          "label": Translation.tr("Position"), "placeholder": "(monitor_w*0.25)",
          "hint": Translation.tr("Where the window opens. Only applies to floating windows.") },
        { "key": "min_size", "type": "vec2", "icon": "compress", "label": Translation.tr("Smallest size") },
        { "key": "max_size", "type": "vec2", "icon": "expand", "label": Translation.tr("Largest size") },
        { "key": "no_max_size", "type": "bool", "icon": "expand_content",
          "label": Translation.tr("Ignore the app's own maximum size") },
        { "key": "opacity", "type": "string", "icon": "opacity", "common": true,
          "label": Translation.tr("Opacity"), "placeholder": "0.9",
          "hint": Translation.tr("One number for every state, or \"active inactive fullscreen\". Add \"override\" after a number to ignore the global opacity.") },
        { "key": "rounding", "type": "int", "icon": "rounded_corner",
          "label": Translation.tr("Corner radius"), "min": 0, "max": 20 },
        { "key": "rounding_power", "type": "float", "icon": "line_curve",
          "label": Translation.tr("Corner shape"), "min": 1, "max": 10, "step": 0.1 },
        { "key": "border_size", "type": "int", "icon": "border_outer",
          "label": Translation.tr("Border width"), "min": 0, "max": 20 },
        { "key": "border_color", "type": "gradient", "icon": "palette",
          "label": Translation.tr("Border colour"), "placeholder": "rgba(ff0000ff)" },
        { "key": "no_shadow", "type": "bool", "icon": "deblur", "label": Translation.tr("No shadow") },
        { "key": "no_blur", "type": "bool", "icon": "blur_off",
          "label": Translation.tr("No blur behind it"), "common": true },
        { "key": "no_dim", "type": "bool", "icon": "brightness_high", "label": Translation.tr("Never dimmed") },
        { "key": "dim_around", "type": "bool", "icon": "brightness_low",
          "label": Translation.tr("Dim everything behind it") },
        { "key": "xray", "type": "bool", "icon": "layers",
          "label": Translation.tr("Blur the wallpaper, not the windows behind") },
        { "key": "opaque", "type": "bool", "icon": "square", "label": Translation.tr("Force fully opaque") },
        { "key": "nearest_neighbor", "type": "bool", "icon": "grain",
          "label": Translation.tr("Scale without smoothing") },
        { "key": "no_anim", "type": "bool", "icon": "animation",
          "label": Translation.tr("No open or close animation"), "common": true },
        { "key": "animation", "type": "string", "icon": "movie",
          "label": Translation.tr("Animation style"), "placeholder": "slide" },
        { "key": "workspace", "type": "string", "icon": "space_dashboard", "common": true,
          "label": Translation.tr("Send to workspace"), "placeholder": "3",
          "hint": Translation.tr("A number, a name, or \"special:magic\". Add \" silent\" to send it there without following it.") },
        { "key": "monitor", "type": "string", "icon": "monitor",
          "label": Translation.tr("Open on screen"), "placeholder": "eDP-1" },
        { "key": "group", "type": "string", "icon": "tab", "label": Translation.tr("Grouping"),
          "placeholder": "set",
          "hint": Translation.tr("\"set\" makes it a group, \"lock\" locks it, \"barred\" keeps it out of groups.") },
        { "key": "tag", "type": "string", "icon": "label", "label": Translation.tr("Tag"),
          "placeholder": "media",
          "hint": Translation.tr("Names this window so other rules can match it by tag.") },
        { "key": "content", "type": "enum", "icon": "smart_display", "label": Translation.tr("Content type"),
          "values": ["none", "photo", "video", "game"] },
        { "key": "idle_inhibit", "type": "enum", "icon": "bedtime_off", "common": true,
          "label": Translation.tr("Keep the screen awake"), "values": ["none", "always", "focus", "fullscreen"],
          "hint": Translation.tr("\"focus\" while the window is focused, \"fullscreen\" while it is fullscreen.") },
        { "key": "no_focus", "type": "bool", "icon": "block", "label": Translation.tr("Can never take focus") },
        { "key": "no_initial_focus", "type": "bool", "icon": "filter_center_focus",
          "label": Translation.tr("Do not focus it when it opens") },
        { "key": "stay_focused", "type": "bool", "icon": "adjust", "label": Translation.tr("Keep focus on it") },
        { "key": "no_follow_mouse", "type": "bool", "icon": "mouse",
          "label": Translation.tr("Focus does not follow the pointer here") },
        { "key": "allows_input", "type": "bool", "icon": "touch_app",
          "label": Translation.tr("Accepts input even when it says it does not") },
        { "key": "decorate", "type": "bool", "icon": "wallpaper", "label": Translation.tr("Draw decorations") },
        { "key": "immediate", "type": "bool", "icon": "bolt", "common": true,
          "label": Translation.tr("Allow tearing"),
          "hint": Translation.tr("Lets frames reach the screen mid-refresh. Lower latency in games, visible tearing everywhere else.") },
        { "key": "render_unfocused", "type": "bool", "icon": "visibility",
          "label": Translation.tr("Keep drawing while hidden") },
        { "key": "persistent_size", "type": "bool", "icon": "save",
          "label": Translation.tr("Remember its size") },
        { "key": "no_screen_share", "type": "bool", "icon": "screenshot_monitor",
          "label": Translation.tr("Hide from screen sharing") },
        { "key": "no_shortcuts_inhibit", "type": "bool", "icon": "keyboard_lock",
          "label": Translation.tr("Never let it swallow shortcuts") },
        { "key": "no_vrr", "type": "bool", "icon": "refresh", "label": Translation.tr("No variable refresh rate") },
        { "key": "no_auto_hdr", "type": "bool", "icon": "hdr_auto", "label": Translation.tr("No automatic HDR") },
        { "key": "force_rgbx", "type": "bool", "icon": "invert_colors",
          "label": Translation.tr("Ignore its transparency channel") },
        { "key": "sync_fullscreen", "type": "bool", "icon": "sync",
          "label": Translation.tr("Match its own idea of fullscreen") },
        { "key": "keep_aspect_ratio", "type": "bool", "icon": "aspect_ratio",
          "label": Translation.tr("Keep its aspect ratio") },
        { "key": "suppress_event", "type": "enum", "icon": "notifications_off",
          "label": Translation.tr("Ignore requests to"),
          "values": ["fullscreen", "maximize", "activate", "activatefocus", "fullscreenoutput"] },
        { "key": "no_close_for", "type": "int", "icon": "timer",
          "label": Translation.tr("Refuse to close for (ms)"), "min": 0, "max": 60000, "step": 100 },
        { "key": "scrolling_width", "type": "float", "icon": "width_normal",
          "label": Translation.tr("Width in the scrolling layout"), "min": 0, "max": 1, "step": 0.05 },
        { "key": "tonemap", "type": "string", "icon": "tonality", "label": Translation.tr("Tone mapping") },
        { "key": "confine_pointer", "type": "bool", "icon": "highlight_alt",
          "label": Translation.tr("Trap the pointer inside it") },
        { "key": "scroll_mouse", "type": "float", "icon": "mouse",
          "label": Translation.tr("Mouse scroll speed here"), "min": 0.01, "max": 10, "step": 0.1 },
        { "key": "scroll_touchpad", "type": "float", "icon": "touchpad_mouse",
          "label": Translation.tr("Touchpad scroll speed here"), "min": 0.01, "max": 10, "step": 0.1 }
    ]

    readonly property var layerEffects: [
        { "key": "blur", "type": "bool", "icon": "blur_on", "label": Translation.tr("Blur behind it") },
        { "key": "blur_popups", "type": "bool", "icon": "blur_circular",
          "label": Translation.tr("Blur behind its popups") },
        { "key": "ignore_alpha", "type": "float", "icon": "opacity",
          "label": Translation.tr("Skip blur below this opacity"), "min": 0, "max": 1, "step": 0.01 },
        { "key": "xray", "type": "bool", "icon": "layers",
          "label": Translation.tr("Blur the wallpaper, not the windows behind") },
        { "key": "dim_around", "type": "bool", "icon": "brightness_low",
          "label": Translation.tr("Dim everything behind it") },
        { "key": "no_anim", "type": "bool", "icon": "animation", "label": Translation.tr("No animation") },
        { "key": "animation", "type": "string", "icon": "movie",
          "label": Translation.tr("Animation style"), "placeholder": "slide left" },
        { "key": "order", "type": "int", "icon": "swap_vert",
          "label": Translation.tr("Stacking order"), "min": -20, "max": 20 },
        { "key": "above_lock", "type": "int", "icon": "lock_open",
          "label": Translation.tr("Draw over the lock screen"), "min": 0, "max": 2 },
        { "key": "no_screen_share", "type": "bool", "icon": "screenshot_monitor",
          "label": Translation.tr("Hide from screen sharing") }
    ]

    readonly property var workspaceEffects: [
        { "key": "monitor", "type": "string", "icon": "monitor",
          "label": Translation.tr("Always on screen"), "placeholder": "eDP-1" },
        { "key": "default", "type": "bool", "icon": "star",
          "label": Translation.tr("Default workspace for that screen") },
        { "key": "persistent", "type": "bool", "icon": "push_pin",
          "label": Translation.tr("Keep it even when empty") },
        { "key": "default_name", "type": "string", "icon": "label",
          "label": Translation.tr("Name"), "placeholder": "Mail" },
        { "key": "gaps_in", "type": "int", "icon": "space_bar",
          "label": Translation.tr("Gaps between windows"), "min": 0, "max": 60 },
        { "key": "gaps_out", "type": "int", "icon": "border_outer",
          "label": Translation.tr("Gaps around the edge"), "min": 0, "max": 100 },
        { "key": "float_gaps", "type": "int", "icon": "picture_in_picture",
          "label": Translation.tr("Gaps for floating windows"), "min": 0, "max": 100 },
        { "key": "border_size", "type": "int", "icon": "border_outer",
          "label": Translation.tr("Border width"), "min": 0, "max": 20 },
        { "key": "no_border", "type": "bool", "icon": "border_clear", "label": Translation.tr("No borders") },
        { "key": "no_rounding", "type": "bool", "icon": "square", "label": Translation.tr("Square corners") },
        { "key": "no_shadow", "type": "bool", "icon": "deblur", "label": Translation.tr("No shadows") },
        { "key": "decorate", "type": "bool", "icon": "wallpaper", "label": Translation.tr("Draw decorations") },
        { "key": "layout", "type": "string", "icon": "dashboard",
          "label": Translation.tr("Tiling engine here"), "placeholder": "master" },
        { "key": "animation", "type": "string", "icon": "movie", "label": Translation.tr("Animation style") },
        { "key": "on_created_empty", "type": "string", "icon": "terminal",
          "label": Translation.tr("Run this when it is created empty"), "placeholder": "kitty" }
    ]

    /**
     * How a window rule chooses its windows. Unlike the effect names above, Hyprland does not
     * check these when the Lua runs - a typo here is only noticed when the rule quietly never
     * fires, which is exactly what the match preview is for.
     */
    readonly property var windowMatchFields: [
        { "key": "class", "type": "regex", "icon": "widgets", "label": Translation.tr("Window class"),
          "placeholder": "^(firefox)$" },
        { "key": "title", "type": "regex", "icon": "title", "label": Translation.tr("Title"),
          "placeholder": "^(Picture-in-Picture)$" },
        { "key": "initial_class", "type": "regex", "icon": "restart_alt",
          "label": Translation.tr("Class it opened with"), "placeholder": "^(firefox)$" },
        { "key": "initial_title", "type": "regex", "icon": "history",
          "label": Translation.tr("Title it opened with") },
        { "key": "tag", "type": "regex", "icon": "label", "label": Translation.tr("Tag"),
          "placeholder": "media" },
        { "key": "workspace", "type": "regex", "icon": "space_dashboard",
          "label": Translation.tr("On workspace"), "placeholder": "3" },
        { "key": "xwayland", "type": "tri", "icon": "grid_goldenratio", "label": Translation.tr("Runs on XWayland") },
        { "key": "floating", "type": "tri", "icon": "picture_in_picture", "label": Translation.tr("Floating") },
        { "key": "fullscreen", "type": "tri", "icon": "fullscreen", "label": Translation.tr("Fullscreen") },
        { "key": "pinned", "type": "tri", "icon": "push_pin", "label": Translation.tr("Pinned") }
    ]

    function effectsFor(kind: string): var {
        if (kind === "layerrule") return root.layerEffects;
        if (kind === "workspacerule") return root.workspaceEffects;
        return root.windowEffects;
    }

    function effectInfo(kind: string, key: string): var {
        return root.effectsFor(kind).find(effect => effect.key === key) ?? null;
    }

    // ------------------------------------------------------------ the managed model

    /// Rules this page owns, in the order they will be written. Ids carry the section that owns
    /// them - `app:`, `win:`, `layer:`, `ws:` - so four lists can share one file and one kind.
    function managedOfKind(kind: string, prefix: string): var {
        const out = [];
        for (const entry of HyprlandGui.rulesEntries) {
            if (entry.kind !== kind || typeof entry.id !== "string") continue;
            if (!entry.id.startsWith(prefix)) continue;
            out.push({ "id": entry.id, "name": entry.id.slice(prefix.length), "spec": entry.spec ?? {} });
        }
        return out;
    }

    readonly property var apps: HyprlandGui.ready ? root.managedOfKind("windowrule", "app:") : []
    readonly property var rawWindowRules: HyprlandGui.ready ? root.managedOfKind("windowrule", "win:") : []
    readonly property var layerRules: HyprlandGui.ready ? root.managedOfKind("layerrule", "layer:") : []
    readonly property var workspaceRules: HyprlandGui.ready ? root.managedOfKind("workspacerule", "ws:") : []

    property var _memo: ({})

    /// The same lists as ids only, kept by identity while the set is unchanged. The tab's
    /// Repeaters run on these, so editing one rule redraws that rule's card and no other -
    /// a toggle used to tear down and rebuild every card in the section.
    readonly property var appIds: ObjectUtils.keep(root._memo, "appIds",
        root.apps.map(rule => rule.id))
    readonly property var rawWindowRuleIds: ObjectUtils.keep(root._memo, "rawWindowRuleIds",
        root.rawWindowRules.map(rule => rule.id))
    readonly property var layerRuleIds: ObjectUtils.keep(root._memo, "layerRuleIds",
        root.layerRules.map(rule => rule.id))
    readonly property var workspaceRuleIds: ObjectUtils.keep(root._memo, "workspaceRuleIds",
        root.workspaceRules.map(rule => rule.id))

    /// Hand-written `hl.*_rule` calls above the fence. Listed, never edited: a rule the page did
    /// not write has an order and a shape it does not control.
    readonly property var inheritedRules: {
        const file = HyprlandGui.files["rules"];
        if (!file) return [];
        return Array.from(file.unmanaged ?? [])
            .filter(entry => ["windowrule", "layerrule", "workspacerule"].includes(entry.kind))
            .map(entry => ({ "kind": entry.kind, "spec": entry.spec ?? {}, "line": entry.line ?? 0 }));
    }

    function find(kind: string, id: string): var {
        const entry = HyprlandGui.rulesEntries
            .find(candidate => candidate.kind === kind && candidate.id === id);
        return entry ? (entry.spec ?? {}) : null;
    }

    /**
     * Effects only - what is left of a spec once its selector and meta fields are taken out.
     * A workspace rule's `workspace` is which workspace it is about; a window rule's `workspace`
     * is where the window gets sent. Same word, opposite side of the rule.
     */
    function effectsOf(kind: string, spec: var): var {
        const out = {};
        for (const key of Object.keys(spec ?? {})) {
            if (key === "match" || key === "name" || key === "enabled") continue;
            if (kind === "workspacerule" && key === "workspace") continue;
            out[key] = spec[key];
        }
        return out;
    }

    // ------------------------------------------------------------------- writing

    function save(kind: string, id: string, spec: var) {
        HyprlandGui.setRule(kind, id, spec);
    }

    function remove(kind: string, id: string) {
        HyprlandGui.removeRule(kind, id);
    }

    /// Set or clear one effect on an existing rule, leaving its match alone.
    function putEffect(kind: string, id: string, key: string, value: var) {
        const spec = root.find(kind, id);
        if (spec === null) return;
        const next = Object.assign({}, spec);
        if (value === undefined || value === null) delete next[key];
        else next[key] = value;
        root.save(kind, id, next);
    }

    /// An id nothing else in this file is using. Rule ids end up in a comment tag, so they stay
    /// short and boring rather than carrying the whole pattern.
    function freeId(kind: string, prefix: string): string {
        const taken = root.managedOfKind(kind, prefix).map(rule => rule.id);
        for (let index = 1; index < 1000; index++) {
            const candidate = `${prefix}${index}`;
            if (!taken.includes(candidate)) return candidate;
        }
        return `${prefix}${taken.length + 1}`;
    }

    /// Ids may only contain what a tag comment can carry back unchanged.
    function slug(text: string): string {
        const cleaned = String(text ?? "").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
        return cleaned === "" ? "app" : cleaned.slice(0, 40);
    }

    function appId(cls: string): string {
        return `app:${root.slug(cls)}`;
    }

    /// The pattern the stock rules use: anchored, and the class taken literally.
    function exactPattern(text: string): string {
        return `^(${String(text ?? "").replace(/[.*+?^${}()|[\]\\]/g, "\\$&")})$`;
    }

    /// The class back out of a pattern this page wrote, for labelling a card.
    function patternLabel(pattern: string): string {
        const text = String(pattern ?? "");
        const exact = text.match(/^\^\((.*)\)\$$/);
        return exact ? exact[1].replace(/\\(.)/g, "$1") : text;
    }

    // ----------------------------------------------------------- one-line summaries

    /// What a rule selects, in the shortest form that is still unambiguous.
    function matchSummary(kind: string, spec: var): string {
        if (kind === "workspacerule") {
            const workspace = String(spec?.workspace ?? "");
            return workspace === "" ? Translation.tr("No workspace chosen") : workspace;
        }
        const match = spec?.match ?? {};
        const parts = Object.keys(match).map(key => `${key} ${match[key]}`);
        return parts.length === 0 ? Translation.tr("Everything") : parts.join("  ·  ");
    }

    /// What it does, for the row you tap to open it.
    function effectSummary(kind: string, spec: var): string {
        const effects = root.effectsOf(kind, spec);
        const keys = Object.keys(effects);
        if (keys.length === 0) return Translation.tr("Does nothing yet");
        return keys.map(key => effects[key] === true ? key : `${key} ${effects[key]}`).join(", ");
    }

    // ----------------------------------------------------------- naming an app

    /// Window class -> desktop entry, built once instead of scanned per card. Apps are indexed
    /// under both their declared startup class and their desktop id, because plenty of them set
    /// neither to the class they actually map with.
    readonly property var appsByClass: {
        const map = {};
        for (const entry of Array.from(AppSearch.list ?? [])) {
            const startup = String(entry.startupClass ?? "").toLowerCase();
            const id = String(entry.id ?? "").replace(/\.desktop$/, "").toLowerCase();
            if (startup !== "" && map[startup] === undefined) map[startup] = entry;
            if (id !== "" && map[id] === undefined) map[id] = entry;
        }
        return map;
    }

    function appEntry(cls: string): var {
        return root.appsByClass[String(cls ?? "").toLowerCase()] ?? null;
    }

    /// What to call a rule in a list: the app's own name when we can find it, the class otherwise.
    function appLabel(cls: string): string {
        const entry = root.appEntry(cls);
        return entry?.name ?? String(cls ?? "");
    }

    // ------------------------------------------------------------- match preview

    readonly property var windowFields: ({
        "class": "class",
        "title": "title",
        "initial_class": "initialClass",
        "initial_title": "initialTitle",
        "xwayland": "xwayland",
        "floating": "floating",
        "fullscreen": "fullscreen",
        "pinned": "pinned",
        "content": "contentType",
        "xdg_tag": "xdgTag"
    })

    readonly property var derivedFields: ["workspace", "tag", "monitor"]

    function knownMatchField(key: string): bool {
        return root.derivedFields.includes(key) || root.windowFields[key] !== undefined;
    }

    function windowValue(window: var, key: string): var {
        if (key === "workspace") return String(window?.workspace?.name ?? "");
        if (key === "tag") return Array.from(window?.tags ?? []).join(" ");
        if (key === "monitor") return String(window?.monitor ?? "");
        return window?.[root.windowFields[key]];
    }

    function compile(pattern: string): var {
        try {
            return new RegExp(String(pattern));
        } catch (error) {
            return null;
        }
    }

    function sameFlag(have: var, want: var): bool {
        const asNumber = value => value === true ? 1 : (value === false ? 0 : Number(value));
        return asNumber(have) === asNumber(want);
    }

    /**
     * Which open windows a match table catches, and what could not be answered.
     *
     * This is JavaScript's regex engine, not Hyprland's, and it knows only the fields listed
     * above - so it is a preview, not a promise. It catches the mistake people actually make
     * (a pattern that does not match what they meant) rather than proving the rule will fire.
     */
    function matchReport(match: var): var {
        const keys = Object.keys(match ?? {}).filter(key => {
            const value = match[key];
            return value !== undefined && value !== null && value !== "";
        });
        const unknown = [];
        const broken = [];
        for (const key of keys) {
            if (!root.knownMatchField(key)) unknown.push(key);
            else if (typeof match[key] === "string" && root.compile(match[key]) === null) broken.push(key);
        }
        const usable = keys.filter(key => !unknown.includes(key) && !broken.includes(key));
        // Nothing usable to filter on means nothing can be claimed. Running the filter anyway
        // would pass every window through and report the whole desktop as a match, which is the
        // most misleading answer available.
        const windows = usable.length === 0 ? [] : Array.from(HyprlandData.windowList).filter(window => {
            for (const key of usable) {
                const want = match[key];
                const have = root.windowValue(window, key);
                if (typeof want === "string") {
                    const regex = root.compile(want);
                    if (!regex.test(String(have ?? ""))) return false;
                } else if (!root.sameFlag(have, want)) {
                    return false;
                }
            }
            return true;
        });
        return {
            "windows": windows,
            "unknown": unknown,
            "broken": broken,
            "empty": keys.length === 0,
            "usable": usable.length,
            "partial": usable.length !== keys.length
        };
    }

    // -------------------------------------------------------------- live surfaces

    /// Namespaces currently on screen, from `hyprctl layers -j`, deduplicated across monitors.
    readonly property var liveNamespaces: {
        const seen = {};
        const layers = HyprlandData.layers ?? {};
        for (const monitor of Object.keys(layers)) {
            const levels = layers[monitor]?.levels ?? {};
            for (const level of Object.keys(levels))
                for (const surface of Array.from(levels[level] ?? []))
                    if (surface?.namespace) seen[surface.namespace] = true;
        }
        return Object.keys(seen).sort();
    }

    /**
     * hyprland/lib/init.lua writes a monitor rule for workspaces 1 to 100 on every start, whether
     * the workspace map is on or off. It is required before custom/rules.lua, so a monitor chosen
     * here still wins - but a workspace in that range is being written to from two places, and
     * the page should say so rather than let it look like a page bug later.
     */
    function workspaceIsMapped(name: string): bool {
        const number = Number(String(name ?? "").trim());
        return isFinite(number) && Math.floor(number) === number && number >= 1 && number <= 100;
    }

    // ----------------------------------------------------------- the editing target

    /// What the rule editor sub-page is currently on. Set before opening it.
    property string editKind: "windowrule"
    property string editId: ""

    function beginEdit(kind: string, id: string) {
        root.editKind = kind;
        root.editId = id;
    }
}
