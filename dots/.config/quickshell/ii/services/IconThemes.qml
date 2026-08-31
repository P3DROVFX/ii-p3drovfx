pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions

/**
 * Icon themes on disk, and the one in use.
 *
 * Two jobs that share a directory. The older one is DynamicTheme: a recolored copy of a base
 * theme the shell generates to match the wallpaper, rebuilt by applyTheme(). The newer one is
 * the plain pack picker: `packs` lists every real icon theme installed, and applyPack() makes
 * one the desktop's theme everywhere at once - or, when themed icons are on, makes it the base
 * that gets recolored instead.
 */
Singleton {
    id: root

    property var availableThemes: []

    /// [{ name, dir, title, inherits, hasApps }] - themes whose index.theme declares icon
    /// directories. Pure cursor themes declare none, and belong to the cursor page instead.
    property var packs: []
    property bool packsReady: false
    /// What gsettings currently says, quotes stripped. "DynamicTheme" while themed icons own it.
    property string systemPack: ""

    readonly property bool themed: Config.options.appearance.icons.enableThemed

    /// The pack the desktop is effectively drawn with: the recolor base when themed icons are
    /// on, otherwise whatever the system setting names.
    readonly property string currentPack: {
        if (root.themed) return String(Config.options.appearance.iconTheme || "");
        if (root.systemPack !== "" && root.systemPack !== "DynamicTheme") return root.systemPack;
        return String(Config.options.appearance.iconTheme || "");
    }

    function packEntry(name: string): var {
        return root.packs.find(pack => pack.name === name) ?? null;
    }

    function refresh() {
        listThemesProcess.running = true;
    }

    /// The walk reads every icon directory on the machine, so it runs when something that
    /// lists the packs opens, not on a schedule.
    function refreshPacks() {
        if (!packListProcess.running) packListProcess.running = true;
        if (!packProbeProcess.running) packProbeProcess.running = true;
    }

    Process {
        id: listThemesProcess
        command: ["bash", "-c", "ls -d /usr/share/icons/*/ ~/.local/share/icons/*/ ~/.icons/*/ 2>/dev/null | xargs -n1 basename | sort -u"]

        stdout: StdioCollector {
            id: themeCollector
            onStreamFinished: {
                let themes = themeCollector.text.split("\n").map(t => t.trim()).filter(t => t && t !== "hicolor" && t !== "default" && t !== "DynamicTheme");

                // Remove duplicates
                root.availableThemes = [...new Set(themes)];
            }
        }
    }

    property bool reloadOnFinish: false
    /// Theme name to write into the toolkit settings once the recolor process finishes.
    property string pendingPushName: ""

    function applyTheme(reload = false, base = "") {
        root.reloadOnFinish = reload;
        const command = ["python3", Directories.scriptPath + "/colors/recolor_icons.py", "--force"];
        // The base is passed explicitly because the Config write that stored it is debounced:
        // the script would otherwise read the previous base back off the disk.
        if (base !== "") command.push("--base", base);
        applyProcess.command = command;
        applyProcess.running = true;
    }

    Process {
        id: applyProcess
        // Explicit apply always regenerates, even when colors/theme look unchanged
        command: ["python3", Directories.scriptPath + "/colors/recolor_icons.py", "--force"]

        onExited: (exitCode, exitStatus) => {
            const push = root.pendingPushName;
            root.pendingPushName = "";
            if (exitCode !== 0) {
                console.warn("[IconThemes] recoloring failed, exit", exitCode);
                return;
            }
            if (push !== "") root._pushName(push);
            if (root.reloadOnFinish) Quickshell.reload();
        }
    }

    // ------------------------------------------------------------------- the pack picker

    /**
     * Make a pack the desktop's icon theme.
     *
     * The pick is always stored as the recolor base, so turning themed icons on later starts
     * from it. With themed icons on, the recolor script reruns from the new base and, once the
     * rebuild lands, every copy of the setting is pointed at DynamicTheme - kdeglobals and the
     * GTK inis can be left on some older theme, and then nothing on screen would follow. With
     * them off,
     * the pack itself is written to the same places. Either way KIconLoader is signalled so
     * running apps, this shell included, drop their cached theme.
     */
    function applyPack(name: string) {
        const pack = String(name ?? "").trim();
        if (pack === "") return;
        Config.options.appearance.iconTheme = pack;
        if (root.themed) {
            // The repoint at DynamicTheme waits for the rebuild: repointing KIconLoader
            // while the directory is being swapped and its caches rewritten had it read
            // half-written files, which is a shell crash (bad_alloc), not just a miss.
            root.pendingPushName = "DynamicTheme";
            root.applyTheme(false, pack);
            return;
        }
        root._pushName(pack);
    }

    /**
     * Flip wallpaper recoloring on or off, applied on the spot: on rebuilds the recolored
     * copy from the stored base and points the desktop at it, off points the desktop back
     * at the base pack itself.
     */
    function setThemed(on: bool) {
        if (Config.options.appearance.icons.enableThemed === on) return;
        Config.options.appearance.icons.enableThemed = on;
        const base = String(Config.options.appearance.iconTheme || "").trim();
        if (base === "") return;
        if (on) {
            root.pendingPushName = "DynamicTheme";
            root.applyTheme(false, base);
            return;
        }
        root.pendingPushName = "";
        root._pushName(base);
    }

    /// Write one theme name into every copy of the setting a toolkit reads, and tell running
    /// apps to drop their cached theme.
    function _pushName(name: string) {
        packApplyProcess.command = ["bash", "-c", root._applyPackScript, "icon-pack", name];
        packApplyProcess.running = true;
    }

    readonly property string _applyPackScript: `
        pack="$1"
        gsettings set org.gnome.desktop.interface icon-theme "$pack" || true
        if command -v kwriteconfig6 >/dev/null 2>&1; then
            kwriteconfig6 --file kdeglobals --group Icons --key Theme "$pack"
        fi
        set_ini() {
            file="$1"
            mkdir -p "\${file%/*}"
            [ -f "$file" ] || printf '[Settings]\\n' > "$file"
            grep -v '^gtk-icon-theme-name=' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
            printf 'gtk-icon-theme-name=%s\\n' "$pack" >> "$file"
        }
        conf="\${XDG_CONFIG_HOME:-$HOME/.config}"
        set_ini "$conf/gtk-3.0/settings.ini"
        set_ini "$conf/gtk-4.0/settings.ini"
        if command -v xsettingsd >/dev/null 2>&1 && [ -n "\${DISPLAY:-}" ]; then
            xconf="$conf/xsettingsd/xsettingsd.conf"
            mkdir -p "\${xconf%/*}"
            touch "$xconf"
            grep -v '^Net/IconThemeName ' "$xconf" > "$xconf.tmp" && mv "$xconf.tmp" "$xconf"
            printf 'Net/IconThemeName "%s"\\n' "$pack" >> "$xconf"
            if pgrep -x xsettingsd >/dev/null 2>&1; then
                pkill -HUP -x xsettingsd || true
            else
                setsid -f xsettingsd >/dev/null 2>&1 || true
            fi
        fi
        for group in 0 1 2 3 4 5 6; do
            dbus-send --session --type=signal /KIconLoader \\
                org.kde.KIconLoader.iconChanged "int32:$group" || true
        done
    `

    Process {
        id: packApplyProcess
        onExited: (code, status) => {
            if (code !== 0) console.warn("[IconThemes] applying the icon pack failed, exit", code);
            // Same invalidation the DynamicTheme watcher does: icon bindings re-resolve once.
            TaskbarApps.iconThemeRevision = 1 - TaskbarApps.iconThemeRevision;
            packProbeProcess.running = true;
        }
    }

    Process {
        id: packProbeProcess
        command: ["bash", "-c", "gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null | tr -d \"'\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const value = String(text).trim();
                if (value !== root.systemPack) root.systemPack = value;
            }
        }
    }

    /**
     * Icon packs on disk, in the order icon lookup searches - ~/.icons, the data home, then
     * /usr/share/icons - so the first pack of a given name is the one that would be used. A
     * directory qualifies by an index.theme that declares Directories=; a theme that only
     * ships cursors does not, and is skipped.
     */
    Process {
        id: packListProcess
        command: ["bash", "-c", `
            emit() {
                dir="$1"
                [ -d "$dir" ] || return 0
                for path in "$dir"/*/; do
                    [ -d "$path" ] || continue
                    name=$(basename "$path")
                    case "$name" in hicolor|default|locolor|DynamicTheme) continue ;; esac
                    index="$path/index.theme"
                    [ -f "$index" ] || continue
                    dirs=$(sed -n 's/^[[:space:]]*Directories[[:space:]]*=[[:space:]]*//p' "$index" | head -n1)
                    [ -n "$dirs" ] || continue
                    apps=0
                    case "$dirs" in *[Aa]pps*) apps=1 ;; esac
                    if [ "$apps" = "0" ] && [ -d "$path/cursors" ]; then continue; fi
                    title=$(sed -n 's/^[[:space:]]*Name[[:space:]]*=[[:space:]]*//p' "$index" | head -n1)
                    inherits=$(sed -n 's/^[[:space:]]*Inherits[[:space:]]*=[[:space:]]*//p' "$index" | head -n1)
                    printf '%s\\t%s\\t%s\\t%s\\t%s\\n' "$name" "$dir" "$title" "$inherits" "$apps"
                done
            }
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
                    if (parts.length < 5) continue;
                    const name = parts[0];
                    if (seen[name]) continue;
                    seen[name] = true;
                    out.push({
                        "name": name,
                        "dir": parts[1],
                        "title": parts[2] !== "" ? parts[2] : name,
                        "inherits": parts[3],
                        "hasApps": parts[4] === "1"
                    });
                }
                const sorted = out.sort((left, right) => left.title.localeCompare(right.title));
                if (ObjectUtils.canon(sorted) !== ObjectUtils.canon(root.packs)) root.packs = sorted;
                root.packsReady = true;
            }
        }
    }

    FileView {
        path: Directories.home + "/.local/share/icons/DynamicTheme.colhash"
        watchChanges: true
        onFileChanged: {
            // DynamicTheme is atomically replaced before the hash is written.
            // A single bounded toggle is enough to invalidate icon bindings without
            // making sourceSize grow after every theme change.
            TaskbarApps.iconThemeRevision = 1 - TaskbarApps.iconThemeRevision;
        }
    }

    Component.onCompleted: refresh()
}
