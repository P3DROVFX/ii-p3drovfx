pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.services
import "themePreview/ThemePreviewLogic.js" as PreviewLogic

/**
 * Serves every colour swatch shown in Settings and in the Welcome from shared
 * file reads.
 *
 * Built-in and custom theme swatches share one queued FileView instead of a
 * FileView per delegate, and the wallpaper-derived schemes come from the
 * all-schemes cache that switchwall already writes on every wallpaper change.
 * Both paths replace one subprocess per swatch, which is what made the
 * Colors & Themes page stall on open.
 *
 * That cache does not exist on a first install, because nothing switches a
 * wallpaper until the user picks one. Two answers cover the gap: the previews
 * shipped in assets for the wallpaper the shell shows in the meantime, and -
 * for every other case - a single generation for the whole grid, replacing the
 * one-per-swatch fallback that would otherwise decode the same image eleven
 * times over.
 */
Singleton {
    id: root

    property var values: ({})

    // Only live swatches own preview data, including those in Welcome.
    property int consumers: 0

    function acquire() {
        root.consumers++;
    }

    function relinquish() {
        if (root.consumers > 0 && --root.consumers === 0)
            root.release();
    }

    // Written by generate_colors_material.py --all-previews, keyed by scheme
    // name ("scheme-tonal-spot", ...) with primary/primary_container/secondary/
    // tertiary. Tertiary is what the swatch shows third: secondary is just a
    // desaturated primary, so it hid the difference between e.g. Content and
    // Fidelity, whereas tertiary is where the schemes actually diverge.
    //
    // Two sources answer that question and the user's own file wins: the one a
    // wallpaper switch writes, and the pair shipped in assets that describes the
    // wallpaper the shell shows before the user has chosen one.
    property var userWallpaperPreviews: ({})
    property var seedWallpaperPreviews: ({})

    /// True while the shell is showing the wallpaper it ships with - the only
    /// case the seed describes, and the only case in which the state file is
    /// legitimately absent. Resolved the same way every other surface resolves
    /// it; see Wallpapers.effectiveWallpaperPath.
    readonly property bool defaultWallpaperActive: {
        const background = Config.options?.background;
        if (!background)
            return true;
        return !background.useWallpaperEngine && String(background.wallpaperPath ?? "") === "";
    }

    readonly property var wallpaperPreviews: PreviewLogic.resolvePreviews(
        root.userWallpaperPreviews, root.seedWallpaperPreviews, root.defaultWallpaperActive)

    readonly property bool wallpaperPreviewsReady: Object.keys(root.wallpaperPreviews).length > 0

    function wallpaperPreview(scheme) {
        const entry = root.wallpaperPreviews[scheme];
        if (!entry)
            return null;
        return {
            primary: entry.primary || "transparent",
            secondary: entry.primary_container || "transparent",
            tertiary: entry.tertiary || entry.secondary || "transparent"
        };
    }

    function _parseWallpaperPreviews() {
        if (root.consumers === 0)
            return;
        try {
            const raw = wallpaperPreviewFile.text().trim();
            root.userWallpaperPreviews = raw ? (JSON.parse(raw) ?? ({})) : ({});
        } catch (e) {
            root.userWallpaperPreviews = ({});
        }
    }

    function _parseSeedWallpaperPreviews() {
        try {
            const raw = seedPreviewFile.text().trim();
            root.seedWallpaperPreviews = raw ? (JSON.parse(raw) ?? ({})) : ({});
        } catch (e) {
            root.seedWallpaperPreviews = ({});
        }
    }

    Timer {
        id: wallpaperPreviewReadTimer
        interval: 50
        repeat: false
        onTriggered: root._parseWallpaperPreviews()
    }

    FileView {
        id: wallpaperPreviewFile
        path: root.consumers > 0 ? Qt.resolvedUrl(Directories.wallpaperPreviewColorsPath) : ""
        watchChanges: root.consumers > 0
        printErrors: false

        // reload() does not re-emit loadedChanged once loaded, so the refresh
        // has to read the file itself after the reload settles.
        onFileChanged: {
            if (root.consumers === 0)
                return;
            this.reload();
            wallpaperPreviewReadTimer.restart();
        }
        onLoadedChanged: {
            if (root.consumers > 0 && wallpaperPreviewFile.loaded)
                root._parseWallpaperPreviews();
        }
        onLoadFailed: root.userWallpaperPreviews = ({})
    }

    // The shipped previews for the wallpaper the shell shows until the user
    // picks one. Read only while it is the answer: once the user's own previews
    // exist, or the shell is showing a wallpaper of theirs, the seed has nothing
    // to say and the FileView is unloaded rather than kept watching a file that
    // cannot change at runtime.
    FileView {
        id: seedPreviewFile
        path: root.consumers > 0 && root.defaultWallpaperActive && Object.keys(root.userWallpaperPreviews).length === 0
            ? Qt.resolvedUrl(Appearance.m3colors.darkmode
                ? Directories.defaultPreviewColorsDarkPath
                : Directories.defaultPreviewColorsLightPath)
            : ""
        watchChanges: false
        printErrors: false

        onLoadedChanged: {
            if (root.consumers > 0 && seedPreviewFile.loaded)
                root._parseSeedWallpaperPreviews();
        }
        onLoadFailed: root.seedWallpaperPreviews = ({})
    }

    // ── Regenerating a missing file ─────────────────────────────────────────
    //
    // Reached only when the user's own previews are gone (installed before the
    // seed existed, state cleared, a switchwall run that failed) and the shell
    // is not on the shipped wallpaper. One process for the whole grid:
    // ColorPreviewButton's per-swatch fallback would open one per visible
    // scheme, staggered 20 ms apart, each decoding the same image.
    property bool generatingWallpaperPreviews: false
    /// "<mode>|<wallpaper>" of the last attempt. A failure degrades to the
    /// per-swatch fallback instead of asking for the same generation forever.
    property string generatedFor: ""

    signal wallpaperPreviewsGenerationFailed()

    function _previewMode() {
        const forced = Config.options?.appearance?.wallpaperTheming?.terminalGenerationProps?.forceDarkMode;
        return PreviewLogic.previewMode(forced, Appearance.m3colors.darkmode);
    }

    /// Mirrors the way switchwall.sh invokes the generator - venv activation,
    /// env sanitisation, termscheme - so this writes exactly the file a
    /// wallpaper switch would. The generator's
    /// `#!/usr/bin/env -S _/bin/sh_ -c_...` shebang is fragile enough that
    /// running the file directly is not worth relying on, and a PYTHONHOME or
    /// LD_LIBRARY_PATH inherited from the session breaks the venv.
    ///
    /// --termscheme is not optional: without it the generator reaches
    /// term_source_colors undefined and exits non-zero after writing the
    /// previews. --request-token/--request-value reuse switchwall's own
    /// stale-write guard, so a real switch starting while this runs moves the
    /// token past the value read here and the write is dropped.
    function _generationCommand(wallpaper, mode) {
        const script = `${Directories.scriptPath}/colors/generate_colors_material.py`;
        const termscheme = `${Directories.scriptPath}/colors/terminal/scheme-base.json`;
        const out = Directories.wallpaperPreviewColorsPath;
        const token = `${Directories.state}/user/generated/.preview_request_token`;
        return `unset LD_LIBRARY_PATH PYTHONHOME PYTHONPATH; `
            + `export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"; `
            + `venv="\${ILLOGICAL_IMPULSE_VIRTUAL_ENV:-\${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/.venv}"; `
            + `source "$(eval echo "$venv")/bin/activate" 2>/dev/null; `
            + `token=${PreviewLogic.shellQuote(token)}; tok=$(cat "$token" 2>/dev/null || echo 0); `
            + `exec python3 ${PreviewLogic.shellQuote(script)} --path ${PreviewLogic.shellQuote(wallpaper)} `
            + `--mode ${mode} --termscheme ${PreviewLogic.shellQuote(termscheme)} --blend_bg_fg `
            + `--all-previews ${PreviewLogic.shellQuote(out)} `
            + `--request-token "$token" --request-value "$tok" > /dev/null`;
    }

    /// Answers "is someone already handling the colours?". True when they are
    /// known, when a generation is in flight, or when one was just started - so
    /// a swatch falls back to its own process only when there is no other way.
    function ensureWallpaperPreviews() {
        if (root.consumers === 0)
            return false;
        const wallpaper = Wallpapers.effectiveWallpaperPath;
        const mode = root._previewMode();
        const decision = PreviewLogic.generationDecision({
            ready: root.wallpaperPreviewsReady,
            wallpaper: wallpaper,
            mode: mode,
            generatedFor: root.generatedFor,
            generating: root.generatingWallpaperPreviews
        });

        if (decision.start) {
            root.generatedFor = PreviewLogic.generationKey(mode, wallpaper);
            root.generatingWallpaperPreviews = true;
            generation.command = ["bash", "-c", root._generationCommand(wallpaper, mode)];
            generation.running = true;
        }

        return decision.handled;
    }

    Process {
        id: generation
        running: false

        stderr: StdioCollector {
            onStreamFinished: {
                const err = String(this.text).trim();
                if (err.length > 0)
                    console.warn("[ThemePreviewCache] preview generation stderr:", err);
            }
        }

        onExited: (code, status) => {
            if (root.consumers === 0)
                return;
            root.generatingWallpaperPreviews = false;

            if (code !== 0) {
                console.warn("[ThemePreviewCache] preview generation exited with code", code);
                // generatedFor stays set, so the swatches that were waiting try
                // again and this time reach their own process.
                root.wallpaperPreviewsGenerationFailed();
                return;
            }

            // reload() does not re-emit loadedChanged once loaded, so the
            // refresh reads the file itself after the reload settles.
            wallpaperPreviewFile.reload();
            wallpaperPreviewReadTimer.restart();
        }
    }

    property var pendingPaths: []
    property string currentPath: ""

    signal cacheChanged(string path)

    function get(path) {
        return path && root.values[path] ? root.values[path] : null;
    }

    function request(path) {
        if (root.consumers === 0 || !path || root.values[path])
            return;

        if (root.pendingPaths.indexOf(path) === -1)
            root.pendingPaths.push(path);

        if (root.currentPath === "")
            root.loadNext();
    }

    function loadNext() {
        if (root.currentPath !== "" || root.pendingPaths.length === 0)
            return;

        root.currentPath = root.pendingPaths.shift();
    }

    function finishCurrent() {
        root.currentPath = "";
        Qt.callLater(root.loadNext);
    }

    function release() {
        wallpaperPreviewReadTimer.stop();
        generation.running = false;
        root.generatingWallpaperPreviews = false;
        root.generatedFor = "";
        root.userWallpaperPreviews = ({});
        root.seedWallpaperPreviews = ({});
        root.pendingPaths = [];
        root.currentPath = "";
        root.values = ({});
    }

    FileView {
        id: themeFile
        path: root.currentPath
        watchChanges: false
        printErrors: false

        onLoaded: {
            if (root.currentPath === "")
                return;

            const pathLoaded = root.currentPath;
            try {
                const raw = themeFile.text().trim();
                const data = raw ? JSON.parse(raw) : null;
                if (data) {
                    root.values[pathLoaded] = {
                        primary: data.primary || "transparent",
                        secondary: data.primary_container || "transparent",
                        tertiary: data.tertiary || data.secondary || "transparent"
                    };
                    root.cacheChanged(pathLoaded);
                }
            } catch (e) {
                // A malformed optional theme must not stop the remaining queue.
            }
            root.finishCurrent();
        }

        onLoadFailed: root.finishCurrent()
    }
}
