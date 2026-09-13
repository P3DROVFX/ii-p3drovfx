pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

/**
 * The keyboard on the desk, as its own firmware describes it.
 *
 * `scripts/typing/vial_keyboard.py` reads the physical layout and the keymap
 * straight off a Vial board over raw HID, so a split, staggered, rotated board
 * draws itself and its layers come back labelled without a single measurement
 * being written down here. Nothing is polled: the read is a one-shot, taken
 * when a surface that shows the keyboard asks for it.
 *
 * Which layer is *live* on the keyboard cannot be read while Vial is locked,
 * and the lock is lost every time the board loses power, so this deliberately
 * does not try. `activeLayer` is the layer the person is looking at.
 */
Singleton {
    id: root

    property bool available: false
    property bool loading: false
    property bool loadedOnce: false
    property string errorMessage: ""

    property string name: ""
    property var snapshot: ({})
    property int layerCount: 0
    /** Board size in key units, for scaling the preview to the space it has. */
    property real unitWidth: 0
    property real unitHeight: 0
    /** Geometry per key: matrix position, unit x/y/w/h and rotation. */
    property var keys: []
    /** `layers[i][k]` is the label, typed character and inheritance of key k. */
    property var layers: []

    property int activeLayer: 0

    readonly property bool ready: root.available && root.keys.length > 0
    signal readFinished(bool success)

    function labelsFor(layer: int): var {
        return root.layers[layer] ?? [];
    }

    /** The labels on screen, clamped so a stale index cannot empty the board. */
    readonly property var activeLabels: root.labelsFor(Math.max(0, Math.min(root.activeLayer, root.layerCount - 1)))

    function setLayer(layer: int): void {
        if (layer < 0 || layer >= root.layerCount)
            return;
        root.activeLayer = layer;
    }

    /**
     * Reads the keyboard, unless it has already been read.
     *
     * Surfaces call this when they appear rather than on start: a person who
     * never opens the typing test should not have their keyboard interrogated.
     */
    function ensureLoaded(): void {
        if (root.loading)
            return;
        // A read that found nothing is worth trying again — the keyboard may
        // simply not have been plugged in yet. A read that worked is kept.
        if (root.loadedOnce && root.available)
            return;
        root.refresh();
    }

    /** Re-reads from scratch, for a board that was plugged in or remapped. */
    function refresh(): void {
        if (root.loading)
            return;
        root.loading = true;
        reader.running = true;
    }

    function applyResult(data): void {
        root.snapshot = data;
        root.available = data?.available === true;
        root.errorMessage = data?.error ?? "";
        if (!root.available) {
            root.keys = [];
            root.layers = [];
            root.layerCount = 0;
            return;
        }
        root.name = data.name ?? "";
        root.layerCount = data.layerCount ?? 0;
        root.unitWidth = data.width ?? 0;
        root.unitHeight = data.height ?? 0;
        root.keys = data.keys ?? [];
        root.layers = data.layers ?? [];
        if (root.activeLayer >= root.layerCount)
            root.activeLayer = 0;
    }

    Process {
        id: reader
        command: ["python3", `${Directories.scriptPath}/typing/vial_keyboard.py`]
        environment: ({
                LANG: "C",
                LC_ALL: "C"
            })

        // The helper reports a missing keyboard as JSON on stdout and exits
        // non-zero, so the exit code alone is not the failure signal.
        stdout: StdioCollector {
            onStreamFinished: {
                root.loading = false;
                root.loadedOnce = true;
                try {
                    root.applyResult(JSON.parse(text));
                } catch (error) {
                    root.available = false;
                    root.errorMessage = "could not read the keyboard";
                }
                root.readFinished(root.available);
            }
        }

        stderr: StdioCollector {
            onStreamFinished: if (text.length > 0) console.log(`[VialKeyboard] ${text.trim()}`)
        }
    }
}
