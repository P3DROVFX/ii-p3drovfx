pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.models.hyprland
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Single owner of Hyprland's `decoration:screen_shader`.
 *
 * Shaders come from two places:
 *  - `hyprshade`, which owns the packaged set and scans $HYPRSHADE_SHADERS_DIR,
 *    ~/.config/hypr/shaders, ~/.config/hyprshade/shaders and /usr/share/hyprshade/shaders
 *  - the shell's own `assets/shaders` plus anything listed in
 *    `screenShader.extraShaderDirs`, scanned here so they still work without hyprshade
 *
 * The shader is applied by writing the option through `HyprlandConfig`, not with
 * `hyprctl keyword`. Keyword values are runtime-only and get dropped by the next
 * config reload — and this shell reloads Hyprland every time any other option
 * changes — so the shader would silently fall off mid-session. Writing it into the
 * config file instead also means it survives a reboot.
 */
Singleton {
    id: root

    // Shaders that sample the whole screen instead of just the current pixel need
    // damage tracking relaxed, or only the redrawn region gets the effect.
    readonly property list<string> fullDamageShaders: ["anti-flashbang"]

    readonly property string builtinShaderDir: FileUtils.trimFileProtocol(Quickshell.shellPath("assets/shaders"))

    // Declared rather than discovered: the built-ins ship with the shell, so they
    // must stay selectable even if the directory scan comes back empty.
    readonly property list<var> builtinShaders: [
        {
            name: "anti-flashbang",
            path: FileUtils.trimFileProtocol(Quickshell.shellPath("assets/shaders/anti-flashbang.glsl")),
            dir: root.builtinShaderDir,
            source: "local"
        }
    ]

    property bool hyprshadeAvailable: true
    property string errorMessage: ""
    property list<string> baseShaderPaths: []
    property bool baseShaderEnabled: false
    property bool optionReady: false
    property bool baseRefreshPending: false

    property list<var> hyprshadeShaders: []
    property list<var> scannedShaders: []

    readonly property bool loading: listProc.running || scanProc.running || resolveProc.running

    readonly property list<string> extraShaderDirs: Array.from(Config.options?.screenShader?.extraShaderDirs ?? [])
    // concat() on a QML list appends it as a single element, so normalise first
    readonly property list<string> localShaderDirs: [root.builtinShaderDir].concat(Array.from(root.extraShaderDirs))

    // Local shaders win over hyprshade's: a copy dropped into the shell should
    // override a packaged one of the same name, the way hyprshade's own
    // directory precedence works.
    readonly property list<var> shaders: {
        const merged = [];
        const seen = {};
        const push = entry => {
            if (seen[entry.name])
                return;
            seen[entry.name] = true;
            merged.push(entry);
        };
        Array.from(root.builtinShaders).forEach(push);
        Array.from(root.scannedShaders).forEach(push);
        Array.from(root.hyprshadeShaders).forEach(push);
        merged.sort((a, b) => a.name.localeCompare(b.name));
        return merged;
    }

    readonly property string activePath: {
        const raw = shaderOption.value;
        if (raw === undefined || raw === null)
            return "";
        const trimmed = String(raw).trim();
        return (trimmed.length === 0 || trimmed === "[[EMPTY]]") ? "" : trimmed;
    }
    readonly property bool baseShaderApplied: root.isBaseShaderPath(root.activePath)
    readonly property string activeName: root.activePath.length === 0 || root.baseShaderApplied ? "" : root.stripExtension(root.activePath.split("/").pop())
    readonly property bool active: root.activeName.length > 0
    readonly property bool baseShaderSuspended: root.baseShaderEnabled && root.active
    readonly property string statusText: root.active ? root.displayName(root.activeName) : Translation.tr("Off")

    // What a left click turns on: the last shader used, falling back to a sane
    // default the first time round.
    readonly property string defaultShaderName: {
        const list = Array.from(root.shaders);
        if (list.length === 0)
            return "";
        const preferred = list.find(shader => shader.name === "blue-light-filter");
        return (preferred ?? list[0]).name;
    }
    readonly property string lastUsedName: {
        const remembered = Config.options?.screenShader?.lastUsed ?? "";
        return (remembered.length > 0 && root.findShader(remembered)) ? remembered : root.defaultShaderName;
    }

    function stripExtension(fileName: string): string {
        return fileName.replace(/\.[^./]*$/, "");
    }

    function displayName(name: string): string {
        if (name.length === 0)
            return Translation.tr("Off");
        const spaced = name.replace(/[-_]+/g, " ").trim();
        return spaced.charAt(0).toUpperCase() + spaced.slice(1);
    }

    function iconFor(name: string): string {
        switch (name) {
        case "anti-flashbang":
            return "flash_off";
        case "blue-light-filter":
            return "bedtime";
        case "color-filter":
            return "tune";
        case "grayscale":
            return "filter_b_and_w";
        case "invert-colors":
            return "invert_colors";
        case "sepia":
            return "filter_vintage";
        case "vibrance":
            return "palette";
        default:
            return "tonality";
        }
    }

    function findShader(name: string): var {
        return Array.from(root.shaders).find(shader => shader.name === name) ?? null;
    }

    function isBaseShaderPath(path: string): bool {
        return path.length > 0 && Array.from(root.baseShaderPaths).indexOf(path) !== -1;
    }

    function setBaseShader(paths: var, enabled: bool): void {
        const previousPaths = Array.from(root.baseShaderPaths);
        const wasBaseApplied = root.activePath.length > 0 && previousPaths.indexOf(root.activePath) !== -1;
        const hadNoShader = root.activePath.length === 0;
        root.baseShaderPaths = Array.from(paths ?? []).filter(path => String(path).length > 0);
        root.baseShaderEnabled = enabled && root.baseShaderPaths.length > 0;

        if (!root.optionReady)
            return;
        if (root.active && !wasBaseApplied)
            return;
        if (!root.baseShaderEnabled) {
            if (wasBaseApplied || root.baseShaderApplied)
                HyprlandConfig.resetMany(["decoration:screen_shader", "debug:damage_tracking"]);
            return;
        }
        if (wasBaseApplied || root.baseShaderApplied) {
            root.refreshBaseShader();
            return;
        }
        if (hadNoShader)
            root._writeShader(root.baseShaderPaths[0], "");
    }

    function reconcileBaseShader(): void {
        if (!root.optionReady || root.active)
            return;
        if (root.baseShaderEnabled && !root.baseShaderApplied) {
            root._writeShader(root.baseShaderPaths[0], "");
        } else if (!root.baseShaderEnabled && root.baseShaderApplied) {
            HyprlandConfig.resetMany(["decoration:screen_shader", "debug:damage_tracking"]);
        }
    }

    function refreshBaseShader(): void {
        if (!root.baseShaderEnabled || !root.baseShaderApplied || root.baseShaderPaths.length < 2)
            return;
        if (baseRefreshProc.running || shaderOption.fetching) {
            root.baseRefreshPending = true;
            return;
        }

        // Always switch away from the currently compiled path. Both generated
        // files were just replaced atomically, so selecting the current path
        // again would not make Hyprland recompile its new contents.
        const avoidPath = root.activePath;
        const targetPath = Array.from(root.baseShaderPaths).find(path => path !== avoidPath) ?? root.baseShaderPaths[0];
        baseRefreshProc.targetPath = targetPath;
        baseRefreshProc.command = ["hyprctl", "keyword", "decoration:screen_shader", targetPath];
        baseRefreshProc.running = true;
    }

    function needsFullDamage(name: string): bool {
        return Array.from(root.fullDamageShaders).indexOf(name) !== -1;
    }

    function refresh(): void {
        root.errorMessage = "";
        listProc.running = false;
        listProc.running = true;
        scanProc.running = false;
        scanProc.running = true;
        shaderOption.fetch();
    }

    function apply(name: string): void {
        if (name.length === 0) {
            root.clear();
            return;
        }
        const shader = root.findShader(name);
        if (!shader) {
            root.errorMessage = Translation.tr("Couldn't find a shader named \"%1\".").arg(name);
            return;
        }
        root.errorMessage = "";
        if (Config.options?.screenShader)
            Config.options.screenShader.lastUsed = name;

        // Shaders we found ourselves already have an absolute path. hyprshade's
        // listing only gives a directory, and the file extension is up to the
        // author, so let hyprshade resolve it and read back where it landed.
        if (shader.path.length > 0) {
            root._writeShader(shader.path, name);
            return;
        }
        const escaped = StringUtils.shellSingleQuoteEscape(name);
        resolveProc.pendingName = name;
        resolveProc.command = ["bash", "-c", `hyprshade on '${escaped}' >/dev/null && hyprctl -j getoption decoration:screen_shader`];
        resolveProc.running = false;
        resolveProc.running = true;
    }

    function clear(): void {
        root.errorMessage = "";
        if (root.baseShaderEnabled && root.baseShaderPaths.length > 0)
            root._writeShader(root.baseShaderPaths[0], "");
        else
            HyprlandConfig.resetMany(["decoration:screen_shader", "debug:damage_tracking"]);
    }

    function toggle(): void {
        if (root.active)
            root.clear();
        else
            root.applyLastUsed();
    }

    function applyLastUsed(): void {
        const wanted = root.lastUsedName;
        if (wanted.length === 0) {
            root.errorMessage = Translation.tr("No shaders available.");
            return;
        }
        root.apply(wanted);
    }

    function _writeShader(path: string, name: string): void {
        if (root.needsFullDamage(name)) {
            HyprlandConfig.setMany({
                "decoration:screen_shader": path,
                "debug:damage_tracking": 1 // 1 = monitor only, stops the effect tearing per-region
            });
            return;
        }
        // Drop the relaxed damage tracking a previous full-screen shader left behind.
        HyprlandConfig.setMany({
            "decoration:screen_shader": path
        }, {
            removeMatching: ["damage_tracking"]
        });
    }

    function _parseHyprshadeList(text: string): void {
        // `hyprshade ls -l` prints "<marker> <name padded> <directory>"
        const parsed = [];
        const lines = String(text).split("\n");
        for (let i = 0; i < lines.length; i++) {
            const match = lines[i].match(/^([ *])\s+(\S+)\s+(\S.*?)\s*$/);
            if (!match)
                continue;
            parsed.push({
                name: match[2],
                path: "", // Resolved by hyprshade when applied
                dir: match[3],
                source: "hyprshade"
            });
        }
        root.hyprshadeShaders = parsed;
    }

    function _parseScannedList(text: string): void {
        const parsed = [];
        const lines = String(text).split("\n");
        for (let i = 0; i < lines.length; i++) {
            const path = lines[i].trim();
            if (path.length === 0)
                continue;
            const fileName = path.split("/").pop();
            parsed.push({
                name: root.stripExtension(fileName),
                path: path,
                dir: path.slice(0, path.length - fileName.length - 1),
                source: "local"
            });
        }
        root.scannedShaders = parsed;
    }

    Component.onCompleted: root.refresh()

    HyprlandConfigOption {
        id: shaderOption
        key: "decoration:screen_shader"
        onFetchingChanged: {
            if (shaderOption.fetching)
                return;
            root.optionReady = true;
            root.reconcileBaseShader();
            if (root.baseRefreshPending) {
                root.baseRefreshPending = false;
                Qt.callLater(root.refreshBaseShader);
            }
        }
    }

    Process {
        id: baseRefreshProc
        property string targetPath: ""
        onExited: {
            shaderOption.fetch();
        }
    }

    Process {
        id: listProc
        command: ["bash", "-c", "command -v hyprshade >/dev/null 2>&1 || exit 127; hyprshade ls -l"]
        stdout: StdioCollector {
            onStreamFinished: root._parseHyprshadeList(text)
        }
        onExited: exitCode => {
            root.hyprshadeAvailable = (exitCode !== 127);
        }
    }

    Process {
        id: scanProc
        command: {
            const dirs = Array.from(root.localShaderDirs).filter(dir => dir.length > 0).map(dir => `'${StringUtils.shellSingleQuoteEscape(dir)}'`).join(" ");
            return ["bash", "-c", `find ${dirs} -maxdepth 2 -type f \\( -name '*.glsl' -o -name '*.frag' \\) 2>/dev/null | sort`];
        }
        stdout: StdioCollector {
            onStreamFinished: root._parseScannedList(text)
        }
    }

    Process {
        id: resolveProc
        property string pendingName: ""
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const resolved = String(JSON.parse(text).str ?? "").trim();
                    if (resolved.length === 0 || resolved === "[[EMPTY]]")
                        throw new Error("no path");
                    root._writeShader(resolved, resolveProc.pendingName);
                } catch (e) {
                    root.errorMessage = Translation.tr("hyprshade couldn't apply \"%1\".").arg(resolveProc.pendingName);
                }
            }
        }
    }
}
