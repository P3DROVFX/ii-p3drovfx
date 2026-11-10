pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

/**
 * What the translator surfaces share: the language table, the language pair, a small
 * result cache and text-to-speech. Each surface keeps its own `TranslatorSession` for
 * the text it is translating.
 *
 * Languages are kept as codes ("pt-BR"); older configs and the settings pickers store
 * endonyms ("Português Brasileiro"), which `find()` resolves just the same.
 */
Singleton {
    id: root

    readonly property string helperPath: `${Directories.scriptPath}/translator/translator.py`
    readonly property var translatorConfig: Config.options.language.translator
    readonly property string engine: root.translatorConfig.engine || "auto"
    /// The reader's language ("pt-BR"), for the dictionary's part-of-speech labels.
    readonly property string hostLanguage: (Translation.languageCode || "en").replace("_", "-")

    // ── Languages ───────────────────────────────────────────────────────────
    /// [{ code, name, endonym }], sorted by endonym; empty until loaded.
    property var languages: []
    /// False once the helper reports that translate-shell is not installed.
    property bool available: true
    property var byKey: ({})

    function ensureLanguages() {
        if (root.languages.length === 0 && !languagesProc.running)
            languagesProc.running = true;
    }

    function find(lang: string): var {
        if (!lang)
            return null;
        return root.byKey[lang.toLowerCase()] ?? null;
    }

    function codeOf(lang: string): string {
        if (!lang || lang === "auto")
            return "auto";
        return root.find(lang)?.code ?? lang;
    }

    function displayName(lang: string): string {
        if (!lang || lang === "auto")
            return Translation.tr("Detect language");
        return root.find(lang)?.endonym ?? lang;
    }

    /// The English name, shown under endonyms the reader may not know.
    function englishName(lang: string): string {
        if (!lang || lang === "auto")
            return "";
        return root.find(lang)?.name ?? "";
    }

    function sameLanguage(a: string, b: string): bool {
        return root.codeOf(a).toLowerCase() === root.codeOf(b).toLowerCase();
    }

    Process {
        id: languagesProc
        command: ["python3", root.helperPath, "languages"]
        stdout: StdioCollector {
            onStreamFinished: {
                let rows = [];
                try {
                    rows = JSON.parse(this.text);
                } catch (e) {
                    rows = [];
                }
                if (!Array.isArray(rows)) {
                    if (rows?.error === "missing-trans")
                        root.available = false;
                    return;
                }
                rows.sort((a, b) => a.endonym.localeCompare(b.endonym));
                const keys = {};
                for (const row of rows) {
                    // Codes win over names, so "pt" never resolves to a language called "PT".
                    for (const name of [row.endonym, row.name]) {
                        if (keys[name.toLowerCase()] === undefined)
                            keys[name.toLowerCase()] = row;
                    }
                }
                for (const row of rows)
                    keys[row.code.toLowerCase()] = row;
                root.byKey = keys;
                root.languages = rows;
            }
        }
    }

    // ── Language pair ───────────────────────────────────────────────────────
    // Defaults from Settings win at start; after that, the session's own choices.
    // Choices are bindings over config until the user picks, so a config that loads
    // after this singleton still lands.
    property string chosenSource: ""
    property string chosenTarget: ""

    readonly property string sourceLanguage: {
        if (root.chosenSource !== "")
            return root.chosenSource;
        const def = root.translatorConfig.defaultSourceLanguage;
        if (def && def !== "auto")
            return def;
        return root.translatorConfig.sourceLanguage || "auto";
    }
    readonly property string targetLanguage: {
        if (root.chosenTarget !== "")
            return root.chosenTarget;
        const def = root.translatorConfig.defaultTargetLanguage;
        if (def && def !== "auto")
            return def;
        const last = root.translatorConfig.targetLanguage;
        return last && last !== "auto" ? last : "en";
    }

    /// Swaps so far: swap shapes and ornaments turn with it, never unwinding.
    property int swapTurns: 0

    function setSource(lang: string) {
        root.chosenSource = lang;
        root.translatorConfig.sourceLanguage = lang;
    }

    function setTarget(lang: string) {
        if (!lang || lang === "auto")
            return;
        root.chosenTarget = lang;
        root.translatorConfig.targetLanguage = lang;
    }

    /**
     * Swaps the pair. "Detect language" cannot become the target, so the language
     * that was detected takes its place; without one the swap is refused.
     * Returns whether anything changed.
     */
    function swap(detected: string): bool {
        let source = root.sourceLanguage;
        if (source === "auto") {
            if (!detected)
                return false;
            source = detected;
        }
        const target = root.targetLanguage;
        root.swapTurns++;
        root.setSource(target);
        root.setTarget(source);
        return true;
    }

    // ── Result cache ────────────────────────────────────────────────────────
    // Swapping back and forth or retyping a word answers at once.
    property var cache: ({})
    property var cacheOrder: []
    readonly property int cacheSize: 60

    function cached(key: string): var {
        return root.cache[key] ?? null;
    }

    function remember(key: string, value: var) {
        if (root.cache[key] === undefined) {
            root.cacheOrder.push(key);
            if (root.cacheOrder.length > root.cacheSize)
                delete root.cache[root.cacheOrder.shift()];
        }
        root.cache[key] = value;
    }

    // ── Speech ──────────────────────────────────────────────────────────────
    /// The key of what is being read aloud ("source:<text>", "target:<text>"…).
    property string speakingKey: ""
    property string pendingSpeakKey: ""
    /// The key that last failed, cleared after a moment so the button recovers.
    property string failedSpeakKey: ""
    property var speakRequest: null

    function isSpeaking(key: string): bool {
        return root.speakingKey === key;
    }

    function speak(key: string, text: string, lang: string) {
        const code = root.codeOf(lang);
        if (!text || text.trim().length === 0 || code === "auto")
            return;
        if (root.speakingKey === key) {
            root.stopSpeaking();
            return;
        }
        root.failedSpeakKey = "";
        root.speakRequest = { key: key, command: ["python3", root.helperPath, "speak", code, text.trim()] };
        if (speakProc.running) {
            // Starts once the old player is gone (see onExited).
            speakProc.stopping = true;
            speakProc.running = false;
            return;
        }
        root.startSpeaking();
    }

    function startSpeaking() {
        const request = root.speakRequest;
        root.speakRequest = null;
        if (!request)
            return;
        root.speakingKey = request.key;
        speakProc.command = request.command;
        speakProc.running = true;
    }

    function stopSpeaking() {
        root.speakRequest = null;
        root.speakingKey = "";
        if (speakProc.running) {
            speakProc.stopping = true;
            speakProc.running = false;
        }
    }

    Process {
        id: speakProc
        /// Set when the shell kills it, so a stop is not mistaken for a failure.
        property bool stopping: false
        onExited: (exitCode, exitStatus) => {
            if (!speakProc.stopping && exitCode !== 0 && root.speakingKey !== "") {
                root.failedSpeakKey = root.speakingKey;
                failedTimer.restart();
            }
            speakProc.stopping = false;
            root.speakingKey = "";
            if (root.speakRequest)
                root.startSpeaking();
        }
    }

    Timer {
        id: failedTimer
        interval: 2400
        onTriggered: root.failedSpeakKey = ""
    }
}
