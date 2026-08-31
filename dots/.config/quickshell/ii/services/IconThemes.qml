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
                root._finishStep();
                return;
            }
            if (root.reloadOnFinish) {
                Quickshell.reload();
                return;
            }
            // Still mid-sequence: the name is written once the rebuild it names is on disk.
            if (push !== "") {
                root._pushName(push);
                return;
            }
            root._finishStep();
        }
    }

    // --------------------------------------------------------------- one change at a time

    /// The pack asked for while another one was still being applied, if any. Only the newest
    /// is kept: the ones in between were never on screen and nobody is waiting for them.
    property var queuedRequest: null
    property bool applying: false

    /**
     * Put one icon change through, start to finish, and only then start the next.
     *
     * Applying is several steps - rebuild, write the name into four places, tell every running
     * app to drop its cached theme - and a Process that is already running ignores being asked
     * to run again. So a second pick made while the first was still going used to vanish, and
     * the desktop sat on the pack before the one that was last clicked. Now it queues, and the
     * icons on screen are invalidated once when the whole sequence ends rather than once per
     * step: the invalidation is a flip, so an even number of them leaves every icon showing
     * exactly what it showed before.
     */
    function _request(pack: string, recolor: bool) {
        root.queuedRequest = { "pack": pack, "recolor": recolor };
        if (root.applying) return;
        root._startNext();
    }

    function _startNext() {
        const request = root.queuedRequest;
        root.queuedRequest = null;
        if (!request) {
            root.applying = false;
            return;
        }
        root.applying = true;
        if (request.recolor) {
            // The repoint at DynamicTheme waits for the rebuild: repointing KIconLoader while
            // the directory is being swapped and its caches rewritten had it read half-written
            // files, which is a shell crash, not just a miss.
            root.pendingPushName = "DynamicTheme";
            root.applyTheme(false, request.pack);
            return;
        }
        root.pendingPushName = "";
        root._pushName(request.pack);
    }

    /// End of a sequence: the icons redraw once, and only then does anything queued behind it
    /// start. Every path through the apply ends here, including the failed ones.
    function _finishStep() {
        root.invalidateIcons();
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
        root._request(pack, root.themed);
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
        root._request(base, on);
    }

    /// Write one theme name into every copy of the setting a toolkit reads, and tell running
    /// apps to drop their cached theme. The script is shared with recolor_icons.py, which has
    /// to leave the same five copies agreeing when it rebuilds the recolored theme.
    function _pushName(name: string) {
        packApplyProcess.command = ["bash", Directories.scriptPath + "/colors/apply_icon_theme.sh", name];
        packApplyProcess.running = true;
    }

    /**
     * Tell every icon on screen to resolve itself again.
     *
     * Deliberately late: the signal above makes KIconLoader throw its parsed theme away and
     * read the new one, and the shell resolves icons on another thread. Asking for a screen
     * full of icons while that rebuild is in flight crashed the shell, so the redraw waits
     * for it to land instead of racing it.
     */
    function invalidateIcons() {
        invalidateTimer.restart();
    }

    Timer {
        id: invalidateTimer
        interval: 250
        onTriggered: {
            TaskbarApps.iconThemeRevision = 1 - TaskbarApps.iconThemeRevision;
            redrawGraceTimer.restart();
        }
    }

    /// The redraw above sends every icon on screen back through the icon loader, on another
    /// thread. The next pack rebuilds that loader, so it waits until the redraw it would have
    /// interrupted is over - which is also when the run stops counting as in progress, so a
    /// pick made during the redraw queues behind it instead of landing in the middle of it.
    Timer {
        id: redrawGraceTimer
        interval: 300
        onTriggered: root._startNext()
    }

    Process {
        id: packApplyProcess
        onExited: (code, status) => {
            if (code !== 0) console.warn("[IconThemes] applying the icon pack failed, exit", code);
            packProbeProcess.running = true;
            root._finishStep();
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
            // DynamicTheme is atomically replaced, and KIconLoader is told about it, before
            // the hash is written. A single bounded toggle is enough to invalidate icon
            // bindings without making sourceSize grow after every theme change - and while a
            // pack is being applied the rebuild is only the first step of it, so the redraw
            // is left to the end of the sequence rather than done twice.
            if (root.applying) return;
            root.invalidateIcons();
        }
    }

    Component.onCompleted: refresh()
}
