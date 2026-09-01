pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.services
import qs.modules.common.functions

/**
 * The keystrokes shown on screen, for screen recordings and demos.
 *
 * Wayland hands no client the global key stream, so the keys come from a small
 * evdev reader (`scripts/videos/keypress_monitor.py`) that this service starts
 * and stops. The process only exists while the overlay is actually visible —
 * there is no daemon sitting around reading the keyboard, and nothing is ever
 * written to disk.
 *
 * The reader is told which xkb layout is loaded rather than guessing, and is
 * restarted when the layout changes, because evdev reports physical keys: on
 * AZERTY the key a US table calls `A` really types `q`.
 *
 * Two switches turn it on, and either is enough: `manualEnabled` is the quick
 * toggle, meant for demos with no recording involved, and `recordingEnabled` is
 * the per-recording override offered in the recording indicator. The override is
 * re-seeded from the persistent setting every time a recording starts, so
 * turning it on for one clip never leaks into the next one. It deliberately
 * lives here rather than in the state file, which `record.sh` rewrites once a
 * second and would clobber.
 *
 * What ends up on screen is a row of chips, each one a chord of keycaps: the
 * keys it is made of (`keysJson`), what it is (`kind`), how many times in a row
 * it was pressed (`count`), whether it is still being held (`held`) and a
 * counter the overlay watches to replay its press animation (`pulse`).
 */
Singleton {
    id: root

    // ── Switches ──────────────────────────────────────────────────────────
    /** Quick toggle / IPC: keystrokes shown regardless of any recording. */
    property bool manualEnabled: false
    /** This recording only, seeded from the persistent setting on each start. */
    property bool recordingEnabled: false

    readonly property bool recordingActive: (Persistent.states?.screenRecord?.active ?? false)
    readonly property bool visible: root.manualEnabled || (root.recordingActive && root.recordingEnabled)

    readonly property var opts: Config.options?.screenRecord?.keypress ?? null
    readonly property bool showWhileRecording: root.opts?.showWhileRecording ?? false
    readonly property int hideDelayMs: root.opts?.hideDelayMs ?? 2500
    readonly property int maxKeys: root.opts?.maxKeys ?? 5
    readonly property bool showMouseButtons: root.opts?.showMouseButtons ?? false
    readonly property bool onlyShortcuts: root.opts?.onlyShortcuts ?? false
    readonly property bool mergeTyping: root.opts?.mergeTyping ?? true

    // Pressing the same thing again this soon reads as one repeated action
    // (`Ctrl+Z` ×3) rather than three separate ones.
    readonly property int repeatWindowMs: 650
    // Longer than this and a typed word stops being readable at a glance.
    readonly property int maxWordLength: 24

    /** True once the reader has confirmed it can see a keyboard. */
    property bool ready: false
    /** Set when the reader cannot run at all, so the settings page can say why. */
    property string lastError: ""
    /** False when python-xkbcommon is missing and labels assume a US layout. */
    property bool layoutAware: true

    readonly property string monitorScript: FileUtils.trimFileProtocol(`${Directories.scriptPath}/videos/keypress_monitor.py`)

    // Hyprland reports the layouts as one comma-joined option, so the active
    // variant is whatever sits at the active layout's index. QML list properties
    // are not JS arrays, hence the copies.
    readonly property int layoutIndex: {
        const codes = Array.from(HyprlandXkb.layoutCodes ?? []);
        if (codes.length <= 1) return 0;
        const index = codes.indexOf(HyprlandXkb.currentLayoutCode);
        return index >= 0 ? index : 0;
    }
    readonly property string layoutCode: Array.from(HyprlandXkb.layoutCodes ?? [])[root.layoutIndex] ?? "us"
    readonly property string layoutVariant: Array.from(HyprlandXkb.layoutVariants ?? [])[root.layoutIndex] ?? ""

    /** Chips currently on screen, oldest first. */
    ListModel {
        id: chipModel
    }
    readonly property ListModel chips: chipModel

    function toggleManual() {
        root.manualEnabled = !root.manualEnabled;
    }

    function toggleForRecording() {
        root.recordingEnabled = !root.recordingEnabled;
    }

    // ── Recording lifecycle ───────────────────────────────────────────────
    // Seeding on the start edge rather than binding keeps the in-recording
    // toggle in charge once the user has touched it.
    onRecordingActiveChanged: {
        if (!root.recordingActive) {
            root.recordingEnabled = false;
            return;
        }
        if (!Config.ready) return;
        root.recordingEnabled = root.showWhileRecording;
    }

    // ── Reader process ────────────────────────────────────────────────────
    onLayoutCodeChanged: root.restartIfRunning()
    onLayoutVariantChanged: root.restartIfRunning()
    onShowMouseButtonsChanged: root.restartIfRunning()

    function restartIfRunning() {
        if (!monitorProcess.running) return;
        monitorProcess.running = false;
        // The release of anything held right now will go to the new reader,
        // which never saw the press; nothing may stay pressed down forever.
        root.releaseAll();
        restartTimer.restart();
    }

    Timer {
        id: restartTimer
        interval: 120
        onTriggered: if (root.visible) monitorProcess.running = true
    }

    // ── Chip model ────────────────────────────────────────────────────────
    function clear() {
        chipModel.clear();
    }

    /** Drops the "Ctrl" and "Shift" chips a combo has just made redundant. */
    function dropTrailingModifiers() {
        while (chipModel.count > 0 && chipModel.get(chipModel.count - 1).kind === "modifier")
            chipModel.remove(chipModel.count - 1);
    }

    function releaseAll() {
        const now = Date.now();
        for (let i = 0; i < chipModel.count; i++) {
            if (!chipModel.get(i).held) continue;
            chipModel.setProperty(i, "held", false);
            chipModel.setProperty(i, "expiresAt", now + root.hideDelayMs);
        }
    }

    /** The held modifier chip nearest the tail lets go; its clock starts now. */
    function releaseModifier(label) {
        const keysJson = JSON.stringify([label]);
        for (let i = chipModel.count - 1; i >= 0; i--) {
            const chip = chipModel.get(i);
            if (chip.kind !== "modifier" || !chip.held || chip.keysJson !== keysJson) continue;
            chipModel.setProperty(i, "held", false);
            chipModel.setProperty(i, "expiresAt", Date.now() + root.hideDelayMs);
            return;
        }
    }

    function pushChip(keys, kind, held, repeat) {
        const now = Date.now();
        const expiry = now + root.hideDelayMs;
        const keysJson = JSON.stringify(keys);
        const lastIndex = chipModel.count - 1;
        const last = lastIndex >= 0 ? chipModel.get(lastIndex) : null;

        // Typing glues onto the word being typed, as long as that chip is
        // still alive: a shortcut in between means a new word started.
        if (root.mergeTyping && kind === "text" && last && last.kind === "text" && last.expiresAt > now) {
            const word = JSON.parse(last.keysJson)[0];
            if (word.length < root.maxWordLength) {
                chipModel.setProperty(lastIndex, "keysJson", JSON.stringify([word + keys[0]]));
                chipModel.setProperty(lastIndex, "expiresAt", expiry);
                chipModel.setProperty(lastIndex, "pressedAt", now);
                chipModel.setProperty(lastIndex, "pulse", last.pulse + 1);
                return;
            }
        }

        // The same chord again, quickly or by auto-repeat, counts up on the
        // chip already there instead of lining up copies of it.
        const again = last && last.kind === kind && last.keysJson === keysJson
            && (repeat || now - last.pressedAt <= root.repeatWindowMs);
        if (again) {
            chipModel.setProperty(lastIndex, "count", last.count + 1);
            chipModel.setProperty(lastIndex, "held", held);
            chipModel.setProperty(lastIndex, "expiresAt", expiry);
            chipModel.setProperty(lastIndex, "pressedAt", now);
            chipModel.setProperty(lastIndex, "pulse", last.pulse + 1);
            return;
        }

        chipModel.append({
            "keysJson": keysJson,
            "kind": kind,
            "count": 1,
            "held": held,
            "pulse": 0,
            "pressedAt": now,
            "expiresAt": expiry
        });
        while (chipModel.count > root.maxKeys) chipModel.remove(0);
    }

    function handleEvent(event) {
        if (event.type === "ready") {
            root.ready = true;
            root.lastError = "";
            root.layoutAware = event.layoutAware !== false;
            return;
        }
        if (event.type === "error") {
            root.ready = false;
            root.lastError = event.message ?? "";
            console.warn("[KeypressService]", event.message);
            return;
        }
        if (event.type === "note") {
            if (String(event.message ?? "").includes("xkbcommon")) root.layoutAware = false;
            return;
        }
        if (event.type === "release") {
            root.releaseModifier(event.label);
            return;
        }
        if (event.type !== "key") return;

        if (event.kind === "mouse" && !root.showMouseButtons) return;
        if (root.onlyShortcuts && event.kind !== "shortcut") return;

        const repeat = event.repeat === true;

        // A modifier on its own is shown held down until it is let go; it is
        // what the combo it turns out to be part of will replace.
        if (event.kind === "modifier") {
            root.pushChip([event.label], "modifier", true, false);
            return;
        }

        const mods = Array.from(event.modifiers ?? []);
        // A held modifier is shown while it is the only thing happening, then
        // gives way to the combo it turned out to be part of — "Ctrl" "Shift"
        // "Ctrl+Shift+P" says the same thing three times.
        if (mods.length > 0) root.dropTrailingModifiers();

        // A combo is never merged into a word, and neither is a named key: a
        // chip reading "Space" beats an invisible gap in the middle of one.
        if (mods.length === 0 && event.kind === "text") {
            // A held letter fills the word chip in well under a second; the
            // editor shows the flood already, the overlay need not.
            if (repeat && root.mergeTyping) return;
            root.pushChip([event.label], "text", false, repeat);
            return;
        }

        const kind = event.kind === "mouse" ? "mouse" : "key";
        root.pushChip(mods.concat([event.label]), kind, false, repeat);
    }

    function handleChunk(chunk) {
        // A single read can carry several lines glued together, so never test
        // the payload as if it were one line.
        chunk.split("\n").forEach(line => {
            const trimmed = line.trim();
            if (trimmed.length === 0) return;
            try {
                root.handleEvent(JSON.parse(trimmed));
            } catch (e) {
                console.warn("[KeypressService] unparseable line:", trimmed);
            }
        });
    }

    onVisibleChanged: {
        if (root.visible) {
            monitorProcess.running = true;
            return;
        }
        monitorProcess.running = false;
        root.clear();
        root.ready = false;
    }

    Process {
        id: monitorProcess
        command: {
            const args = ["python3", root.monitorScript, "--layout", root.layoutCode || "us", "--repeats"];
            if (root.layoutVariant.length > 0) args.push("--variant", root.layoutVariant);
            if (root.showMouseButtons) args.push("--mouse");
            return args;
        }

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => root.handleChunk(data)
        }

        stderr: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                const message = String(data).trim();
                if (message.length > 0) console.warn("[KeypressService]", message);
            }
        }

        onExited: (exitCode, exitStatus) => {
            root.ready = false;
            root.releaseAll();
            if (root.visible && exitCode !== 0 && root.lastError.length === 0)
                root.lastError = Translation.tr("Keystroke reader stopped unexpectedly");
        }
    }

    // Chips expire themselves; sweeping on one timer rather than one timer per
    // chip keeps the model cheap no matter how fast the user types. A held
    // chip never expires, and does not shield the chips behind it either.
    Timer {
        running: root.visible && chipModel.count > 0
        interval: 200
        repeat: true
        onTriggered: {
            const now = Date.now();
            for (let i = chipModel.count - 1; i >= 0; i--) {
                const chip = chipModel.get(i);
                if (!chip.held && chip.expiresAt <= now) chipModel.remove(i);
            }
        }
    }

    IpcHandler {
        target: "keypress"

        function toggle(): string {
            root.toggleManual();
            return root.manualEnabled ? "shown" : "hidden";
        }

        // Named enable/disable rather than show/hide: `qs ipc call <target> show`
        // is swallowed by the CLI's own `ipc show` subcommand and never reaches
        // the handler.
        function enable(): string {
            root.manualEnabled = true;
            return "shown";
        }

        function disable(): string {
            root.manualEnabled = false;
            return "hidden";
        }
    }
}
