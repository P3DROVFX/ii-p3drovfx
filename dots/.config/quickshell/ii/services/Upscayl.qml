pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Headless wallpaper upscaling through Upscayl's own engine (`upscayl-bin`, shipped
 * inside the app next to its models), so nothing has to open the Electron UI.
 *
 * switchwall.sh finds a wallpaper smaller than the largest monitor and sends a
 * notification; its "Upscale" action calls `qs -c ii ipc call upscayl prompt …`,
 * which opens the corner popup (modules/ii/upscaylPopup). The popup picks scale and
 * model, `start()` runs the engine, progress comes from its "NN.NN%" stderr lines,
 * and the result goes back through Wallpapers.select* for the same target.
 */
Singleton {
    id: root

    // ── request (from switchwall.sh) ──
    property bool popupOpen: false
    // Keeps the window alive while the card plays its leave animation after popupOpen drops.
    property bool popupVisible: false
    property string inputPath: ""
    property string target: "desktop" // desktop | lockscreen | lightmode
    property int imageWidth: 0
    property int imageHeight: 0
    property int screenWidth: 0
    property int screenHeight: 0

    // ── engine discovery ──
    property bool probing: false
    property string binPath: ""
    property string modelsDir: ""
    property list<string> models: []
    readonly property bool available: binPath.length > 0 && modelsDir.length > 0 && models.length > 0

    // ── choice ──
    property int scale: autoScale
    property string model: ""
    // Smallest factor that covers the largest monitor; the engine only does 2–4.
    readonly property int autoScale: {
        if (imageWidth <= 0 || imageHeight <= 0 || screenWidth <= 0 || screenHeight <= 0)
            return 4;
        const need = Math.max(screenWidth / imageWidth, screenHeight / imageHeight);
        return Math.max(2, Math.min(4, Math.ceil(need - 0.001)));
    }

    // ── run ──
    property string phase: "setup" // setup | running | done | error
    property real progress: 0
    property string errorText: ""
    property string outputPath: ""
    property bool backgrounded: false // popup closed while running: notify when done

    readonly property string fileName: FileUtils.fileNameForPath(inputPath)

    function modelLabel(name) {
        const known = {
            "upscayl-standard-4x": Translation.tr("Standard"),
            "upscayl-lite-4x": Translation.tr("Lite"),
            "high-fidelity-4x": Translation.tr("High fidelity"),
            "digital-art-4x": Translation.tr("Digital art"),
            "remacri-4x": "Remacri",
            "ultramix-balanced-4x": "Ultramix",
            "ultrasharp-4x": "UltraSharp"
        };
        if (known[name]) return known[name];
        return name.replace(/-\d+x$/, "").replace(/[-_]+/g, " ");
    }

    function prompt(path, target, imageWidth, imageHeight, screenWidth, screenHeight) {
        if (root.phase === "running") {
            root.backgrounded = false;
            root.popupVisible = true;
            root.popupOpen = true;
            return;
        }
        root.inputPath = FileUtils.trimFileProtocol(path);
        root.target = ["desktop", "lockscreen", "lightmode"].includes(target) ? target : "desktop";
        root.imageWidth = imageWidth;
        root.imageHeight = imageHeight;
        root.screenWidth = screenWidth;
        root.screenHeight = screenHeight;
        root.scale = Qt.binding(() => root.autoScale);
        root.phase = "setup";
        root.progress = 0;
        root.errorText = "";
        root.outputPath = "";
        root.backgrounded = false;
        root.popupVisible = true;
        root.popupOpen = true;
        root.probe();
    }

    function probe() {
        root.binPath = "";
        root.modelsDir = "";
        root.models = [];
        root._probeModels = [];
        root.probing = true;
        probeProc.running = false;
        probeProc.running = true;
    }

    function outputFor(path, scale) {
        const dot = path.lastIndexOf(".");
        const slash = path.lastIndexOf("/");
        const stem = dot > slash ? path.slice(0, dot) : path;
        const ext = dot > slash ? path.slice(dot + 1).toLowerCase() : "png";
        const keep = ext === "jpeg" ? "jpg" : (["png", "jpg", "webp"].includes(ext) ? ext : "png");
        return `${stem}-upscaled-${scale}x.${keep}`;
    }

    function start() {
        if (!root.available || root.phase === "running" || root.inputPath.length === 0)
            return;
        if (!root.models.includes(root.model))
            root.model = root.models[0];
        Config.options.background.upscaylModel = root.model;
        root.outputPath = root.outputFor(root.inputPath, root.scale);
        root.progress = 0;
        root.errorText = "";
        root.phase = "running";
        runProc.lastLines = [];
        runProc.running = true;
    }

    function cancel() {
        if (root.phase === "running") {
            root._cancelled = true;
            runProc.running = false;
        }
        root.close();
    }

    // Closing while it runs keeps the job going; the result still applies.
    function close() {
        if (root.phase === "running")
            root.backgrounded = true;
        root.popupOpen = false;
    }

    function applyResult() {
        switch (root.target) {
        case "lockscreen": Wallpapers.selectLockscreen(root.outputPath); break;
        case "lightmode": Wallpapers.selectLightmode(root.outputPath); break;
        default: Wallpapers.select(root.outputPath); break;
        }
    }

    property bool _cancelled: false
    property list<string> _probeModels: []

    // Upscayl ships upscayl-bin + models inside the app; packages put it in a few places.
    Process {
        id: probeProc
        command: ["bash", "-c", `
            for b in "$(command -v upscayl-bin 2>/dev/null)" \\
                     /opt/Upscayl/resources/bin/upscayl-bin /opt/upscayl/resources/bin/upscayl-bin \\
                     /opt/upscayl/bin/upscayl-bin /usr/lib/upscayl/resources/bin/upscayl-bin \\
                     /usr/lib/upscayl/bin/upscayl-bin /usr/share/upscayl/resources/bin/upscayl-bin \\
                     "$(dirname "$(readlink -f "$(command -v upscayl 2>/dev/null)" 2>/dev/null)" 2>/dev/null)/resources/bin/upscayl-bin"; do
                [ -n "$b" ] && [ -x "$b" ] || continue
                d="$(dirname "$b")"
                for m in "$d/../models" "$d/../resources/models" "$d/models" /usr/share/upscayl/models; do
                    if ls "$m"/*.param >/dev/null 2>&1; then
                        echo "BIN $b"; echo "MODELS $(readlink -f "$m")"
                        for p in "$m"/*.param; do n="\${p##*/}"; echo "MODEL \${n%.param}"; done
                        exit 0
                    fi
                done
            done
            exit 1`]
        stdout: SplitParser {
            onRead: line => {
                if (line.startsWith("BIN ")) root.binPath = line.slice(4);
                else if (line.startsWith("MODELS ")) root.modelsDir = line.slice(7);
                else if (line.startsWith("MODEL ")) root._probeModels.push(line.slice(6));
            }
        }
        onExited: (exitCode, exitStatus) => {
            root.probing = false;
            const order = ["upscayl-standard-4x", "upscayl-lite-4x", "high-fidelity-4x", "digital-art-4x",
                           "ultrasharp-4x", "remacri-4x", "ultramix-balanced-4x"];
            root.models = root._probeModels.slice().sort((a, b) => {
                const ia = order.indexOf(a), ib = order.indexOf(b);
                return (ia < 0 ? 99 : ia) - (ib < 0 ? 99 : ib) || a.localeCompare(b);
            });
            if (!root.available) {
                root.phase = "error";
                root.errorText = Translation.tr("Upscayl's engine wasn't found. Install Upscayl (upscayl-bin on Arch) and try again.");
                return;
            }
            const saved = Config.options.background.upscaylModel;
            root.model = root.models.includes(saved) ? saved : root.models[0];
        }
    }

    Process {
        id: runProc
        property list<string> lastLines: []
        command: ["bash", "-c", `out="$2"; tmp="\${out%.*}.part.\${out##*.}"
            "$1" -i "$3" -o "$tmp" -m "$4" -n "$5" -s "$6" -f "\${out##*.}" || { rm -f "$tmp"; exit 1; }
            [ -s "$tmp" ] && mv -f "$tmp" "$out"`,
            "upscayl", root.binPath, root.outputPath, root.inputPath, root.modelsDir, root.model, String(root.scale)]
        stderr: SplitParser {
            onRead: line => {
                const m = line.match(/(\d+(?:\.\d+)?)%/);
                if (m) {
                    root.progress = Math.min(1, parseFloat(m[1]) / 100);
                } else if (line.trim().length > 0) {
                    runProc.lastLines = runProc.lastLines.concat([line.trim()]).slice(-2);
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (root._cancelled) {
                root._cancelled = false;
                root.phase = "setup";
                root.progress = 0;
                Quickshell.execDetached(["bash", "-c", `rm -f "\${1%.*}.part.\${1##*.}"`, "rm", root.outputPath]);
                return;
            }
            if (exitCode !== 0) {
                root.phase = "error";
                root.errorText = runProc.lastLines.length > 0 ? runProc.lastLines.join(" · ")
                    : Translation.tr("Upscayl stopped with code %1").arg(exitCode);
                if (root.backgrounded)
                    Quickshell.execDetached(["notify-send", "-a", "Wallpaper switcher", "-u", "critical",
                        Translation.tr("Upscale failed"), root.errorText]);
                return;
            }
            root.progress = 1;
            root.phase = "done";
            root.applyResult();
            if (root.backgrounded) {
                Quickshell.execDetached(["notify-send", "-a", "Wallpaper switcher",
                    Translation.tr("Wallpaper upscaled"), FileUtils.fileNameForPath(root.outputPath)]);
                root.backgrounded = false;
            } else {
                closeTimer.restart();
            }
        }
    }

    // The finished card stays a beat so "done" reads, then leaves.
    Timer {
        id: closeTimer
        interval: 1400
        onTriggered: if (root.phase === "done") root.popupOpen = false
    }

    IpcHandler {
        target: "upscayl"

        function prompt(path: string, target: string, imageWidth: int, imageHeight: int, screenWidth: int, screenHeight: int): void {
            root.prompt(path, target, imageWidth, imageHeight, screenWidth, screenHeight);
        }

        function close(): void {
            root.close();
        }
    }
}
