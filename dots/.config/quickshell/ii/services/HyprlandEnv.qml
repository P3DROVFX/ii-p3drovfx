pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions

/**
 * Environment variables Hyprland exports, and the pointer theme, which is four of them.
 *
 * An environment variable is not a setting: nothing can be asked what one currently is. Hyprland
 * calls setenv() as it reads the config, and glibc's setenv leaves /proc/<pid>/environ - the only
 * thing that could be read back - showing the values the compositor was launched with. So this
 * service does not try. It reads the three files that set variables, in the order Hyprland loads
 * them, and reports what the next program started will be given:
 *
 *   hyprland/env.lua         upstream, replaced on update, read-only here
 *   custom/env.lua           the managed region at its end is what this page writes
 *   hyprland/variables.lua   loaded later still, through hyprland/keybinds.lua
 *
 * The pointer is the exception in every direction. Its theme and size are environment variables,
 * but `hyprctl setcursor` applies them to the running compositor at once, and GTK keeps its own
 * copy in gsettings which has to be told separately. Setting it here does all three.
 */
Singleton {
    id: root

    readonly property string hyprDir: FileUtils.trimFileProtocol(`${Directories.config}/hypr`)
    /// Loaded before custom/env.lua. Anything it sets, a variable of the same name here replaces.
    readonly property string upstreamFile: `${root.hyprDir}/hyprland/env.lua`
    /// Loaded after, through hyprland/keybinds.lua. Anything it sets replaces ours instead.
    readonly property string lateFile: `${root.hyprDir}/hyprland/variables.lua`

    property bool ready: false
    /// [{ name, value, line, unresolved }] from hyprland/env.lua
    property var upstream: []
    /// The same from hyprland/variables.lua, which wins over this page
    property var late: []
    /// [{ name, title, dir, xcursor, hypr, shapes }]
    property var themes: []
    property bool themesReady: false
    /// What the probe found out about the machine: installed programs, the GTK cursor, the GPU
    property var probe: ({})

    // ----------------------------------------------------------------- the three layers

    /// Where a variable's value comes from, highest wins: this page, then a hand-written line in
    /// custom/env.lua, then hyprland/env.lua. "late" is the odd one out - it is not a source this
    /// page can beat, it is a file that beats it.
    function envSource(name: string): string {
        if (HyprlandGui.managedEnv[name] !== undefined) return "managed";
        if (HyprlandGui.inheritedEnv[name] !== undefined) return "hand";
        if (root.upstreamMap[name] !== undefined) return "upstream";
        return "";
    }

    function envValue(name: string): string {
        const managed = HyprlandGui.managedEnv[name];
        if (managed !== undefined) return String(managed);
        const hand = HyprlandGui.inheritedEnv[name];
        if (hand !== undefined) return root.plainValue(hand.value);
        const above = root.upstreamMap[name];
        if (above !== undefined) return root.plainValue(above.value);
        return "";
    }

    /// A Lua value the parser could not reduce to a literal - `home_dir .. "/x"` - comes back as
    /// { __raw }. Shown as the expression it is rather than as an empty string.
    function plainValue(value: var): string {
        if (value === undefined || value === null) return "";
        if (typeof value === "object" && value.__raw !== undefined) return String(value.__raw);
        return String(value);
    }

    readonly property var upstreamMap: {
        const map = {};
        for (const entry of Array.from(root.upstream))
            if (entry.name) map[entry.name] = entry;
        return map;
    }

    readonly property var lateMap: {
        const map = {};
        for (const entry of Array.from(root.late))
            if (entry.name) map[entry.name] = entry;
        return map;
    }

    /// True when something loaded after custom/env.lua sets this name too, in which case what
    /// this page writes never reaches a program.
    function overriddenLater(name: string): bool {
        return root.lateMap[name] !== undefined;
    }

    function setVariable(name: string, value: string) {
        if (!root.validName(name)) return;
        HyprlandGui.setEnv(name, String(value ?? ""));
    }

    function clearVariable(name: string) {
        HyprlandGui.removeEnv(name);
    }

    function validName(name: string): bool {
        return /^[A-Za-z_][A-Za-z0-9_]*$/.test(String(name ?? ""));
    }

    // ------------------------------------------------------------------------ the pointer

    readonly property var cursorVariables: ["HYPRCURSOR_THEME", "HYPRCURSOR_SIZE",
        "XCURSOR_THEME", "XCURSOR_SIZE"]

    /// hyprcursor and XCursor are told separately and can disagree. The hyprcursor name is the
    /// one Hyprland itself draws with, so it is the one shown.
    readonly property string cursorTheme:
        root.envValue("HYPRCURSOR_THEME") || root.envValue("XCURSOR_THEME")
        || String(root.probe.gtkTheme ?? "") || root.fallbackTheme

    readonly property int cursorSize: {
        const raw = root.envValue("HYPRCURSOR_SIZE") || root.envValue("XCURSOR_SIZE")
            || String(root.probe.gtkSize ?? "");
        const value = parseInt(raw, 10);
        return isNaN(value) || value <= 0 ? 24 : value;
    }

    /// What X11 falls back to when nothing is set: the Inherits line of /usr/share/icons/default.
    readonly property string fallbackTheme: String(root.probe.fallback ?? "")

    /// True when the two halves of the pointer disagree, which happens after editing only one of
    /// them by hand and leaves XWayland windows with a different cursor to everything else.
    readonly property bool cursorSplit: {
        const hypr = root.envValue("HYPRCURSOR_THEME");
        const x = root.envValue("XCURSOR_THEME");
        return hypr !== "" && x !== "" && hypr !== x;
    }

    /// True when GTK's own copy of the setting says something else, so GTK apps draw a different
    /// pointer to the rest of the desktop until it is told.
    readonly property bool gtkOutOfStep: {
        const gtk = String(root.probe.gtkTheme ?? "");
        return gtk !== "" && root.cursorTheme !== "" && gtk !== root.cursorTheme;
    }

    function themeEntry(name: string): var {
        return root.themes.find(theme => theme.name === name) ?? null;
    }

    /// Everything else on the machine that keeps its own copy of the pointer setting: GTK's ini
    /// files, KDE's kcminputrc, the X resource database, the X11 default theme that Steam and
    /// SDL games fall back to, a flatpak override for sandboxed apps, and - when xsettingsd is
    /// installed - the XSETTINGS keys running X11 apps re-read live. The last three blocks
    /// update the environments new programs inherit from - the compositor's own (files cannot:
    /// env.lua is read at launch only), the systemd user manager's and D-Bus activation's - so
    /// a program started from now on gets the new theme without a re-login. Programs already
    /// running, and children of an already-running terminal, keep the old value.
    readonly property string cursorSyncScript: `
        theme="$1"; size="$2"
        set_ini() {
            file="$1"
            mkdir -p "\${file%/*}"
            [ -f "$file" ] || printf '[Settings]\\n' > "$file"
            for pair in "gtk-cursor-theme-name=$theme" "gtk-cursor-theme-size=$size"; do
                key="\${pair%%=*}"
                grep -v "^$key=" "$file" > "$file.tmp" && mv "$file.tmp" "$file"
                printf '%s\\n' "$pair" >> "$file"
            done
        }
        conf="\${XDG_CONFIG_HOME:-$HOME/.config}"
        set_ini "$conf/gtk-3.0/settings.ini"
        set_ini "$conf/gtk-4.0/settings.ini"
        mkdir -p "$HOME/.icons/default"
        dest="$HOME/.icons/default/index.theme"
        printf '[Icon Theme]\\nName=Default\\nInherits=%s\\n' "$theme" > "$dest"
        if command -v kwriteconfig6 >/dev/null 2>&1; then
            kwriteconfig6 --file kcminputrc --group Mouse --key cursorTheme "$theme"
            kwriteconfig6 --file kcminputrc --group Mouse --key cursorSize "$size"
        fi
        if command -v xrdb >/dev/null 2>&1 && [ -n "\${DISPLAY:-}" ]; then
            printf 'Xcursor.theme: %s\\nXcursor.size: %s\\n' "$theme" "$size" | xrdb -merge
        fi
        if command -v flatpak >/dev/null 2>&1; then
            flatpak override --user --env=XCURSOR_THEME="$theme" --env=XCURSOR_SIZE="$size"
        fi
        if command -v xsettingsd >/dev/null 2>&1 && [ -n "\${DISPLAY:-}" ]; then
            xconf="$conf/xsettingsd/xsettingsd.conf"
            mkdir -p "\${xconf%/*}"
            touch "$xconf"
            grep -vE '^Gtk/CursorTheme(Name|Size) ' "$xconf" > "$xconf.tmp" && mv "$xconf.tmp" "$xconf"
            printf 'Gtk/CursorThemeName "%s"\\nGtk/CursorThemeSize %s\\n' "$theme" "$size" >> "$xconf"
            if pgrep -x xsettingsd >/dev/null 2>&1; then
                pkill -HUP -x xsettingsd || true
            else
                setsid -f xsettingsd >/dev/null 2>&1 || true
            fi
        fi
        if command -v hyprctl >/dev/null 2>&1; then
            hyprctl eval "hl.env([[XCURSOR_THEME]], [[$theme]])" >/dev/null || true
            hyprctl eval "hl.env([[XCURSOR_SIZE]], [[$size]])" >/dev/null || true
            hyprctl eval "hl.env([[HYPRCURSOR_THEME]], [[$theme]])" >/dev/null || true
            hyprctl eval "hl.env([[HYPRCURSOR_SIZE]], [[$size]])" >/dev/null || true
        fi
        if command -v systemctl >/dev/null 2>&1; then
            systemctl --user set-environment "XCURSOR_THEME=$theme" "XCURSOR_SIZE=$size" \\
                "HYPRCURSOR_THEME=$theme" "HYPRCURSOR_SIZE=$size" || true
        fi
        if command -v dbus-update-activation-environment >/dev/null 2>&1; then
            dbus-update-activation-environment --systemd "XCURSOR_THEME=$theme" \\
                "XCURSOR_SIZE=$size" "HYPRCURSOR_THEME=$theme" "HYPRCURSOR_SIZE=$size" || true
        fi
    `

    /**
     * Set the pointer everywhere at once.
     *
     * The four variables are what a program started later reads. `hyprctl setcursor` is what the
     * compositor draws with right now, and is the reason this is the one thing on the page that
     * does not need a re-login. gsettings is GTK's own copy, which nothing else updates. The
     * sync script then walks every other copy - GTK's ini files, KDE apps, the X11 fallback
     * that Steam reads, the X resource database, flatpaks - so no surface is left drawing its
     * own idea of the pointer.
     */
    function applyCursor(theme: string, size: int) {
        const name = String(theme ?? "").trim();
        const px = Math.max(1, Math.round(size));
        if (name === "") return;
        HyprlandGui.batch(() => {
            HyprlandGui.setEnv("HYPRCURSOR_THEME", name);
            HyprlandGui.setEnv("XCURSOR_THEME", name);
            HyprlandGui.setEnv("HYPRCURSOR_SIZE", String(px));
            HyprlandGui.setEnv("XCURSOR_SIZE", String(px));
        });
        root.runLater([
            ["hyprctl", "setcursor", name, String(px)],
            ["gsettings", "set", "org.gnome.desktop.interface", "cursor-theme", name],
            ["gsettings", "set", "org.gnome.desktop.interface", "cursor-size", String(px)],
            ["bash", "-c", root.cursorSyncScript, "cursor-sync", name, String(px)]
        ]);
    }

    function resetCursor() {
        HyprlandGui.batch(() => {
            for (const name of root.cursorVariables) HyprlandGui.removeEnv(name);
        });
    }

    // -------------------------------------------------------------------------- presets

    /**
     * Groups of variables that only make sense together.
     *
     * Each variant is the whole group: choosing one writes every variable it names and removes
     * every other variable the preset knows about, so switching from fcitx to ibus cannot leave
     * half of the old one behind. `needs` is a program that has to exist for the variant to do
     * anything, and `detects` is a probe key that has to be true for the preset to be relevant
     * at all - an NVIDIA preset on an Intel laptop is noise.
     */
    readonly property var presets: [
        {
            "id": "inputMethod",
            "icon": "keyboard_alt",
            "label": Translation.tr("Input method"),
            "detail": Translation.tr("For typing a language that needs one, such as Chinese, Japanese or Korean. Toolkits each read a different variable, which is why this is a group."),
            "variants": [
                { "id": "none", "label": Translation.tr("None"), "vars": ({}) },
                {
                    "id": "fcitx5", "label": Translation.tr("Fcitx 5"), "needs": "fcitx5",
                    // GLFW speaks only the ibus protocol, which fcitx also serves, so this one
                    // says ibus even under fcitx. Straight out of fcitx's own Wayland page.
                    "vars": ({ "QT_IM_MODULE": "fcitx", "XMODIFIERS": "@im=fcitx",
                        "SDL_IM_MODULE": "fcitx", "GLFW_IM_MODULE": "ibus",
                        "INPUT_METHOD": "fcitx" })
                },
                {
                    "id": "ibus", "label": Translation.tr("IBus"), "needs": "ibus",
                    "vars": ({ "QT_IM_MODULE": "ibus", "XMODIFIERS": "@im=ibus",
                        "SDL_IM_MODULE": "ibus", "GLFW_IM_MODULE": "ibus",
                        "INPUT_METHOD": "ibus" })
                }
            ]
        },
        {
            "id": "qtTheme",
            "icon": "palette",
            "label": Translation.tr("How Qt apps are themed"),
            "detail": Translation.tr("Which plugin Qt asks for colours, fonts and icons. The shell's own config sets this to the KDE one, which is what matches the rest of this desktop."),
            "variants": [
                { "id": "none", "label": Translation.tr("No plugin"), "vars": ({}) },
                { "id": "kde", "label": Translation.tr("KDE"), "vars": ({ "QT_QPA_PLATFORMTHEME": "kde" }) },
                { "id": "gtk3", "label": Translation.tr("Follow GTK"), "vars": ({ "QT_QPA_PLATFORMTHEME": "gtk3" }) },
                { "id": "qt6ct", "label": Translation.tr("qt6ct"), "needs": "qt6ct",
                    "vars": ({ "QT_QPA_PLATFORMTHEME": "qt6ct" }) }
            ]
        },
        {
            "id": "portals",
            "icon": "folder_open",
            "label": Translation.tr("Open and save dialogs"),
            "detail": Translation.tr("Makes GTK and Electron apps ask the desktop portal for a file chooser instead of drawing their own, so every app opens the same one."),
            "variants": [
                { "id": "none", "label": Translation.tr("Each app's own"), "vars": ({}) },
                { "id": "portal", "label": Translation.tr("The desktop's"),
                    "vars": ({ "GTK_USE_PORTAL": "1", "ELECTRON_USE_PORTAL": "1" }) }
            ]
        },
        {
            "id": "scaling",
            "icon": "zoom_in",
            "label": Translation.tr("Force app scaling"),
            "detail": Translation.tr("Wayland apps are already scaled by the compositor, per monitor, and this does not touch them. It is for XWayland windows and toolkits that ignore the compositor."),
            "variants": [
                { "id": "none", "label": Translation.tr("Off"), "vars": ({}) },
                { "id": "125", "label": "125%",
                    "vars": ({ "QT_SCALE_FACTOR": "1.25", "GDK_DPI_SCALE": "1.25" }) },
                { "id": "150", "label": "150%",
                    "vars": ({ "QT_SCALE_FACTOR": "1.5", "GDK_DPI_SCALE": "1.5" }) },
                { "id": "200", "label": "200%",
                    "vars": ({ "QT_SCALE_FACTOR": "2", "GDK_SCALE": "2" }) }
            ],
            "note": Translation.tr("GTK only scales its widgets by whole numbers, so below 200% only its text grows. Qt scales at any of them.")
        },
        {
            "id": "nvidia",
            "icon": "memory",
            "label": Translation.tr("NVIDIA graphics"),
            "detail": Translation.tr("The variables an NVIDIA card needs before hardware video decoding and OpenGL pick the right driver."),
            "detects": "nvidia",
            "variants": [
                { "id": "none", "label": Translation.tr("Off"), "vars": ({}) },
                {
                    "id": "on", "label": Translation.tr("On"),
                    "vars": ({ "LIBVA_DRIVER_NAME": "nvidia", "__GLX_VENDOR_LIBRARY_NAME": "nvidia",
                        "GBM_BACKEND": "nvidia-drm", "NVD_BACKEND": "direct" })
                }
            ]
        }
    ]

    function preset(id: string): var {
        return root.presets.find(entry => entry.id === id) ?? null;
    }

    /// Every variable name any variant of a preset touches.
    function presetNames(id: string): var {
        const entry = root.preset(id);
        if (!entry) return [];
        const names = {};
        for (const variant of entry.variants)
            for (const name of Object.keys(variant.vars ?? {})) names[name] = true;
        return Object.keys(names);
    }

    /**
     * Which variant is in force, and who put it there.
     *
     * `variant` is "" when the values match no variant at all, which is what a hand-edited
     * config looks like. `owned` is true only when this page wrote every one of them, and it is
     * the difference between a control that can be moved and one that would silently take over
     * a line someone wrote by hand.
     */
    function presetState(id: string): var {
        const entry = root.preset(id);
        if (!entry) return ({ "variant": "", "owned": false, "sources": [] });
        const names = root.presetNames(id);
        // A variable blanked to turn a preset off is set, and is off. Everything here therefore
        // asks what the value is, never whether a line exists.
        const active = names.filter(name => root.envValue(name) !== "");
        const foreign = active.filter(name => root.envSource(name) !== "managed");
        let match = "";
        for (const variant of entry.variants) {
            const wanted = variant.vars ?? {};
            const keys = Object.keys(wanted);
            if (keys.length === 0) continue;
            let all = true;
            for (const name of keys)
                if (root.envValue(name) !== wanted[name]) { all = false; break; }
            if (all) { match = variant.id; break; }
        }
        if (match === "" && active.length === 0) match = "none";
        return ({
            "variant": match,
            "owned": foreign.length === 0,
            /// The hand-written or upstream lines this preset is fighting with, by name.
            "elsewhere": foreign.map(name => ({ "name": name, "source": root.envSource(name),
                "line": HyprlandGui.inheritedEnv[name]?.line ?? (root.upstreamMap[name]?.line ?? 0) }))
        });
    }

    /// True when a file loaded before custom/env.lua's managed region also sets this name, so
    /// removing our line would not leave it unset.
    function setBelow(name: string): bool {
        return HyprlandGui.inheritedEnv[name] !== undefined || root.upstreamMap[name] !== undefined;
    }

    /// Names in a preset that this page is holding empty, which is what turning a group off
    /// looks like when a file below it sets the same variable.
    function blankedNames(id: string): var {
        return root.presetNames(id).filter(name =>
            HyprlandGui.managedEnv[name] === "" && root.setBelow(name));
    }

    /// A variant whose program is not installed still writes fine, and still does nothing.
    function variantMissing(variant: var): bool {
        const needs = String(variant?.needs ?? "");
        return needs !== "" && root.probe[needs] === false;
    }

    function applyPreset(id: string, variantId: string) {
        const entry = root.preset(id);
        if (!entry) return;
        const variant = entry.variants.find(item => item.id === variantId);
        if (!variant) return;
        const wanted = variant.vars ?? {};
        HyprlandGui.batch(() => {
            for (const name of root.presetNames(id)) {
                if (wanted[name] !== undefined) continue;
                // Nothing can unset an environment variable from a config file. Where a file
                // below this one sets the variable, dropping our line would hand it straight
                // back, so it is written empty instead - which every toolkit reads as off.
                if (root.setBelow(name)) HyprlandGui.setEnv(name, "");
                else HyprlandGui.removeEnv(name);
            }
            for (const name of Object.keys(wanted)) HyprlandGui.setEnv(name, wanted[name]);
        });
    }

    // ------------------------------------------------------------------- the free-form list

    /// Names the sections above already own, so the list underneath is only what is left.
    readonly property var claimedNames: {
        const claimed = {};
        for (const name of root.cursorVariables) claimed[name] = true;
        for (const entry of root.presets)
            for (const name of root.presetNames(entry.id)) claimed[name] = true;
        return claimed;
    }

    /**
     * Everything custom/env.lua sets, whether this page wrote it or a person did.
     *
     * Hand-written lines are listed alongside the managed ones rather than hidden: they are the
     * same file and the same effect, and the only difference the list draws is that editing one
     * writes a managed line that wins over it instead of changing it in place.
     */
    readonly property var variables: {
        const rows = [];
        const seen = {};
        for (const name of Object.keys(HyprlandGui.managedEnv)) {
            seen[name] = true;
            rows.push({ "name": name, "value": String(HyprlandGui.managedEnv[name]),
                "source": "managed", "line": 0, "claimed": root.claimedNames[name] === true });
        }
        for (const name of Object.keys(HyprlandGui.inheritedEnv)) {
            if (seen[name]) continue;
            seen[name] = true;
            const info = HyprlandGui.inheritedEnv[name];
            rows.push({ "name": name, "value": root.plainValue(info.value), "source": "hand",
                "line": info.line ?? 0, "claimed": root.claimedNames[name] === true });
        }
        return rows.sort((left, right) => left.name.localeCompare(right.name));
    }

    /// The ones the sections above do not already have a control for.
    readonly property var otherVariables: root.variables.filter(row => !row.claimed)
    readonly property int claimedCount: root.variables.length - root.otherVariables.length

    // --------------------------------------------------------------------- the editing target

    /// Which variable the editor sub-page is on. Empty name means it is making a new one.
    property string editName: ""
    property var draft: ({})
    /// Bumped every time the editor is pointed at something. The page fills its fields from this
    /// and not from the draft: the fields write the draft on every keystroke, so a field that
    /// also read it back would be its own input.
    property int editGeneration: 0

    function beginEdit(name: string) {
        const row = root.variables.find(entry => entry.name === name);
        root.editName = name;
        root.draft = ({ "name": name, "value": row ? row.value : root.envValue(name) });
        root.editGeneration += 1;
    }

    function beginNew() {
        root.editName = "";
        root.draft = ({ "name": "", "value": "" });
        root.editGeneration += 1;
    }

    function putDraft(key: string, value: var) {
        const next = Object.assign({}, root.draft);
        next[key] = value;
        root.draft = next;
    }

    readonly property var draftProblems: {
        const out = [];
        const name = String(root.draft.name ?? "").trim();
        if (name === "")
            out.push(Translation.tr("A variable needs a name."));
        else if (!root.validName(name))
            out.push(Translation.tr("A name can only use letters, digits and _, and cannot start with a digit."));
        else if (root.overriddenLater(name))
            out.push(Translation.tr("hyprland/variables.lua sets %1 after this file, so this would have no effect.").arg(name));
        return out;
    }

    function commitDraft(): bool {
        if (root.draftProblems.length > 0) return false;
        const name = String(root.draft.name ?? "").trim();
        if (root.editName !== "" && root.editName !== name) HyprlandGui.removeEnv(root.editName);
        HyprlandGui.setEnv(name, String(root.draft.value ?? ""));
        root.editName = name;
        return true;
    }

    // ------------------------------------------------------------------------------ reading

    function refresh() {
        root.stale = false;
        if (!upstreamProc.running) upstreamProc.running = true;
        if (!lateProc.running) lateProc.running = true;
        if (!root.themesReady) root.refreshThemes();
        if (!probeProc.running) probeProc.running = true;
    }

    /// The theme walk reads every icon directory on the machine, and nothing about a config
    /// reload changes what is installed - so it runs once, and again only when the picker
    /// that lists the themes is opened.
    function refreshThemes() {
        if (!themeProc.running) themeProc.running = true;
    }

    /**
     * Only the Environment tab reads any of this, and one of the four reads walks every cursor
     * theme directory on the machine. Doing that after every reload for the rest of the session
     * - and a reload happens whenever Modes, Game Mode or the theme changes anything - was work
     * nobody was waiting for.
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

        function onReloaded(own, targets) {
            if (own && targets.env !== true) return;
            root.stale = true;
            if (HyprlandGui.watching) root.refresh();
        }
    }

    function _readEnvList(text: string): var {
        let parsed;
        try {
            parsed = JSON.parse(text);
        } catch (error) {
            return [];
        }
        const out = [];
        for (const entry of Array.from(parsed.unmanaged ?? [])) {
            if (entry.kind !== "env") continue;
            out.push({
                "name": String(entry.name ?? ""),
                "value": entry.value,
                "line": entry.line ?? 0,
                "unresolved": entry.unresolved === true
            });
        }
        return out;
    }

    Process {
        id: upstreamProc
        command: [HyprlandGui.scriptPath, "read", "--file", root.upstreamFile]
        stdout: StdioCollector {
            onStreamFinished: {
                const list = root._readEnvList(text);
                if (ObjectUtils.canon(list) !== ObjectUtils.canon(root.upstream))
                    root.upstream = list;
                root.ready = true;
            }
        }
    }

    Process {
        id: lateProc
        command: [HyprlandGui.scriptPath, "read", "--file", root.lateFile]
        stdout: StdioCollector {
            onStreamFinished: {
                const list = root._readEnvList(text);
                if (ObjectUtils.canon(list) !== ObjectUtils.canon(root.late)) root.late = list;
            }
        }
    }

    /**
     * Cursor themes on disk.
     *
     * The search path is XCursor's, in its own order, so the first theme of a given name is the
     * one that would actually be used - Bibata-Modern-Classic exists three times over on this
     * machine and only the first counts. A directory qualifies by holding cursors/ (XCursor) or
     * hyprcursors/ (hyprcursor); most icon themes hold neither and are skipped.
     */
    Process {
        id: themeProc
        command: ["bash", "-c", `
            emit() {
                dir="$1"
                [ -d "$dir" ] || return 0
                for path in "$dir"/*/; do
                    [ -d "$path" ] || continue
                    name=$(basename "$path")
                    x=0; h=0; shapes=0
                    if [ -d "$path/cursors" ]; then
                        x=1
                        shapes=$(ls -1 "$path/cursors" 2>/dev/null | wc -l | tr -d ' ')
                    fi
                    [ -d "$path/hyprcursors" ] && h=1
                    [ "$x$h" = "00" ] && continue
                    title=""
                    for meta in "$path/cursor.theme" "$path/index.theme"; do
                        [ -f "$meta" ] || continue
                        title=$(sed -n 's/^[[:space:]]*Name[[:space:]]*=[[:space:]]*//p' "$meta" | head -n1)
                        [ -n "$title" ] && break
                    done
                    printf '%s\\t%s\\t%s\\t%s\\t%s\\t%s\\n' "$name" "$dir" "$x" "$h" "$shapes" "$title"
                done
            }
            old_ifs="$IFS"
            IFS=':'
            set -- $XCURSOR_PATH
            IFS="$old_ifs"
            for extra in "$@"; do emit "$extra"; done
            emit "$HOME/.icons"
            emit "\${XDG_DATA_HOME:-$HOME/.local/share}/icons"
            emit /usr/share/icons
        `]
        stdout: StdioCollector {
            onStreamFinished: {
                const seen = {};
                const out = [];
                for (const line of String(text).split("\n")) {
                    if (line.trim() === "") continue;
                    const parts = line.split("\t");
                    if (parts.length < 6) continue;
                    const name = parts[0];
                    if (seen[name]) continue;
                    seen[name] = true;
                    out.push({
                        "name": name,
                        "dir": parts[1],
                        "xcursor": parts[2] === "1",
                        "hypr": parts[3] === "1",
                        "shapes": parseInt(parts[4], 10) || 0,
                        "title": parts[5] !== "" ? parts[5] : name
                    });
                }
                const sorted = out.sort((left, right) => left.title.localeCompare(right.title));
                if (ObjectUtils.canon(sorted) !== ObjectUtils.canon(root.themes))
                    root.themes = sorted;
                root.themesReady = true;
            }
        }
    }

    /// One process for every yes-or-no question the page asks about the machine: which of the
    /// presets' programs exist, what GTK thinks the pointer is, whether there is an NVIDIA card,
    /// and what X11 falls back to when no theme is named.
    Process {
        id: probeProc
        command: ["bash", "-c", `
            for program in fcitx5 ibus qt6ct; do
                command -v "$program" >/dev/null 2>&1 && echo "$program=yes" || echo "$program=no"
            done
            [ -d /sys/module/nvidia ] && echo "nvidia=yes" || echo "nvidia=no"
            if command -v gsettings >/dev/null 2>&1; then
                theme=$(gsettings get org.gnome.desktop.interface cursor-theme 2>/dev/null \\
                    | tr -d \\"\\')
                echo "gtkTheme=$theme"
                echo "gtkSize=$(gsettings get org.gnome.desktop.interface cursor-size 2>/dev/null)"
            fi
            default_theme=/usr/share/icons/default/index.theme
            if [ -f "$default_theme" ]; then
                inherits=$(sed -n 's/^[[:space:]]*Inherits[[:space:]]*=[[:space:]]*//p' \\
                    "$default_theme" | head -n1)
                echo "fallback=$inherits"
            fi
        `]
        stdout: StdioCollector {
            onStreamFinished: {
                const map = {};
                for (const line of String(text).split("\n")) {
                    const at = line.indexOf("=");
                    if (at <= 0) continue;
                    const key = line.slice(0, at);
                    const value = line.slice(at + 1).trim();
                    map[key] = value === "yes" ? true : (value === "no" ? false : value);
                }
                if (ObjectUtils.canon(map) !== ObjectUtils.canon(root.probe)) root.probe = map;
            }
        }
    }

    // -------------------------------------------------------------------------- applying

    /// hyprctl and gsettings are three separate programs for one click. Queued rather than
    /// started together so a failure is attributable and nothing races on the same setting.
    property var _applyQueue: []

    function runLater(commands: var) {
        root._applyQueue = root._applyQueue.concat(Array.from(commands ?? []));
        root._drainApply();
    }

    function _drainApply() {
        if (applyProc.running || root._applyQueue.length === 0) return;
        const next = root._applyQueue[0];
        root._applyQueue = root._applyQueue.slice(1);
        applyProc.command = next;
        applyProc.running = true;
    }

    Process {
        id: applyProc
        onExited: (code, status) => {
            if (code !== 0) {
                const shown = applyProc.command[0] === "bash"
                    ? "bash script " + (applyProc.command[3] ?? "") : applyProc.command.join(" ");
                console.warn("[HyprlandEnv] failed:", shown, "exit", code);
            }
            root._drainApply();
        }
    }
}
