pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import qs.services
import qs.modules.common

/**
 * One translator surface's translation: debounced, cached, and never out of order.
 *
 * Feed it `text`; it translates with the shared language pair and exposes the helper's
 * whole answer (`result`: translation, transliterations, detected language, spelling
 * correction, alternatives, dictionary, synonyms, definitions, examples). The previous
 * result stays until the new one lands, so panes never flash back to empty while typing.
 */
Item {
    id: root
    visible: false

    property string text: ""

    readonly property string trimmed: root.text.trim()
    readonly property bool hasInput: root.trimmed.length > 0
    readonly property string sourceCode: TranslatorService.codeOf(TranslatorService.sourceLanguage)
    readonly property string targetCode: TranslatorService.codeOf(TranslatorService.targetLanguage)
    readonly property string requestKey: [TranslatorService.engine, TranslatorService.hostLanguage, root.sourceCode, root.targetCode, root.trimmed].join("\u0001")

    property var result: null
    /// "" when fine; otherwise the helper's error ("missing-trans", "timeout", …).
    property string error: ""
    property bool pending: false

    readonly property bool busy: root.hasInput && (debounce.running || proc.running || root.pending)
    readonly property string translation: root.hasInput ? (root.result?.translation ?? "") : ""
    readonly property string transliteration: root.hasInput ? (root.result?.transliteration ?? "") : ""
    readonly property string sourceTransliteration: root.hasInput ? (root.result?.sourceTransliteration ?? "") : ""
    /// The language Google detected, as a code; only meaningful with "Detect language".
    readonly property string detected: root.hasInput ? (root.result?.detected ?? "") : ""
    readonly property string correction: root.hasInput ? (root.result?.correction ?? "") : ""
    readonly property var alternatives: root.hasInput ? (root.result?.alternatives ?? []) : []
    readonly property var dictionary: root.hasInput ? (root.result?.dictionary ?? []) : []
    readonly property var synonyms: root.hasInput ? (root.result?.synonyms ?? []) : []
    readonly property var definitions: root.hasInput ? (root.result?.definitions ?? []) : []
    readonly property var examples: root.hasInput ? (root.result?.examples ?? []) : []
    readonly property bool hasDictionary: root.synonyms.length > 0 || root.definitions.length > 0 || root.examples.length > 0

    /// The language the text is in: the chosen one, or the detected one.
    readonly property string effectiveSource: root.sourceCode === "auto" ? root.detected : root.sourceCode

    onRequestKeyChanged: root.schedule()

    function schedule() {
        if (!root.hasInput) {
            debounce.stop();
            root.result = null;
            root.error = "";
            return;
        }
        const hit = TranslatorService.cached(root.requestKey);
        if (hit) {
            debounce.stop();
            root.result = hit;
            root.error = "";
            return;
        }
        debounce.restart();
    }

    function retry() {
        root.error = "";
        root.start();
    }

    function start() {
        if (!root.hasInput)
            return;
        if (proc.running) {
            // One request at a time; the newest text goes next (see onExited).
            root.pending = true;
            return;
        }
        root.pending = false;
        proc.key = root.requestKey;
        proc.command = ["python3", TranslatorService.helperPath, "translate", TranslatorService.engine, root.sourceCode, root.targetCode, TranslatorService.hostLanguage, root.trimmed];
        proc.running = true;
    }

    Timer {
        id: debounce
        interval: Config.options.sidebar.translator.delay ?? 300
        onTriggered: root.start()
    }

    Process {
        id: proc
        property string key: ""
        property string output: ""
        // The output stream and the exit arrive in either order; settle on the later.
        property bool streamDone: false
        property bool exitDone: false

        onStarted: {
            proc.output = "";
            proc.streamDone = false;
            proc.exitDone = false;
        }
        stdout: StdioCollector {
            onStreamFinished: {
                proc.output = this.text;
                proc.streamDone = true;
                proc.settle();
            }
        }
        onExited: (exitCode, exitStatus) => {
            proc.exitDone = true;
            proc.settle();
        }

        function settle() {
            if (!proc.streamDone || !proc.exitDone)
                return;
            proc.streamDone = false;
            proc.exitDone = false;
            let parsed = null;
            try {
                parsed = JSON.parse(proc.output);
            } catch (e) {
                parsed = null;
            }
            if (parsed?.ok)
                TranslatorService.remember(proc.key, parsed);
            if (proc.key === root.requestKey) {
                if (parsed?.ok) {
                    root.result = parsed;
                    root.error = "";
                } else {
                    root.error = parsed?.error ?? "no-result";
                    if (root.error === "missing-trans")
                        TranslatorService.available = false;
                }
            }
            if (root.pending)
                Qt.callLater(root.start);
        }
    }
}
