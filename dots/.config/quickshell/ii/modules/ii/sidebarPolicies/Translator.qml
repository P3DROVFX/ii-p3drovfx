import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.clock.components
import qs.modules.ii.sidebarPolicies.translator
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

/**
 * Translator tab, on the `trans` command line tool.
 *
 * Material 3 Expressive, after the Clock app: a connected language bar (two tiles hinged
 * by a scalloped swap shape), the source pane, and the translation as the hero pane that
 * takes the hue of its state. The panes stack in the sidebar and sit side by side when
 * the sidebar is extended.
 */
Item {
    id: root

    // Sizes
    property real padding: Appearance.rounding.small
    /// Side-by-side panes once there is room for two readable columns.
    readonly property bool wide: root.width >= 600

    // Widgets
    property var inputField: sourceCard.textArea

    // Widget variables
    property string translatedText: ""
    property string secondTranslatedText: ""
    property list<string> languages: []
    /// Swaps so far: the swap shape and the hero's ornament turn with it, never unwinding.
    property int swapTurns: 0

    // Options
    property string targetLanguage: {
        let def = Config.options.language.translator.defaultTargetLanguage;
        if (def && def !== "" && def !== "auto") return def;
        return Config.options.language.translator.targetLanguage || "pt";
    }
    property string sourceLanguage: {
        let def = Config.options.language.translator.defaultSourceLanguage;
        if (def && def !== "" && def !== "auto") return def;
        return Config.options.language.translator.sourceLanguage || "auto";
    }
    property string hostLanguage: targetLanguage

    readonly property bool hasInput: root.inputField.text.trim().length > 0
    readonly property bool busy: root.hasInput && (translateTimer.running || translateProc.running)

    // States
    property bool showLanguageSelector: false
    property bool languageSelectorTarget: false // true for target language, false for source language

    function languageName(lang: string): string {
        return lang === "auto" ? Translation.tr("Detect language") : lang;
    }

    /// Big while the text is a phrase, stepping down as it grows into a paragraph.
    function textSizeFor(length: int): int {
        if (length <= 48)
            return Appearance.font.pixelSize.huge + 6;
        if (length <= 160)
            return Appearance.font.pixelSize.huge;
        return Appearance.font.pixelSize.large;
    }

    function showLanguageSelectorDialog(isTargetLang: bool) {
        root.languageSelectorTarget = isTargetLang;
        root.showLanguageSelector = true;
    }

    function swapLanguages() {
        root.swapTurns++;
        let temp = root.sourceLanguage;
        root.sourceLanguage = root.targetLanguage;
        root.targetLanguage = temp;
        if (root.hasInput)
            translateTimer.restart();
    }

    onFocusChanged: focus => {
        if (focus)
            root.inputField.forceActiveFocus();
    }

    onShowLanguageSelectorChanged: {
        if (showLanguageSelector) return;
        // The dialog's search field held focus while open and is destroyed with
        // it; give focus back to the input so typing and the shortcuts survive
        // a language selection.
        if (GlobalStates.sidebarLeftOpen) Qt.callLater(() => root.inputField.forceActiveFocus());
    }

    Keys.priority: Keys.AfterItem
    Keys.onPressed: event => {
        // "Type / to translate": jump straight back into the input from
        // anywhere in the tab, so the whole flow is keyboard-only.
        if (event.key === Qt.Key_Slash && event.modifiers === Qt.NoModifier
                && !root.showLanguageSelector && !root.inputField.activeFocus) {
            root.inputField.forceActiveFocus();
            event.accepted = true;
            return;
        }
        if ((event.modifiers & Qt.ControlModifier) !== 0
                && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
            root.swapLanguages();
            event.accepted = true;
        }
    }
    onTargetLanguageChanged: {
        translateProc.canTransliterate = true
    }

    Timer {
        id: translateTimer
        interval: Config.options.sidebar.translator.delay
        repeat: false
        onTriggered: () => {
            if (root.hasInput) {
                translateProc.running = false;
                translateProc.buffer = ""; // Clear the buffer
                translateProc.running = true; // Restart the process
            } else {
                root.translatedText = "";
                root.secondTranslatedText = "";
            }
        }
    }

    Process {
        id: translateProc
        property bool canTransliterate: true
        property string buffer: ""
        function buildTarget() {
            const s = StringUtils.shellSingleQuoteEscape
            const tgt = s(root.targetLanguage)
            // If transliteration detected, return `language+@language`; else `language`
            return canTransliterate ? `${tgt}+@${tgt}` : tgt
        }
        command: {
            const s = StringUtils.shellSingleQuoteEscape
            const src = s(root.sourceLanguage)
            const tgt = buildTarget()
            const inp = s(root.inputField.text.trim())

            return ["bash", "-c",
                `trans -brief -no-bidi -source '${src}' -target '${tgt}' '${inp}'`
            ]
        }
        stdout: SplitParser {
            onRead: d => translateProc.buffer += d + "\n"
        }
        // The previous translation stays until the new one lands, so the hero pane
        // does not flash back to its empty state on every keystroke.
        onStarted: buffer = ""
        onExited: () => {
            if (!root.hasInput) {
                root.translatedText = "";
                root.secondTranslatedText = "";
                return;
            }
            // Split output in half, first half is translation
            const lines = buffer.trim().split(/\r?\n/).filter(Boolean)
            if (!lines.length) return
            const mid = lines.length >> 1
            const tr = lines.slice(0, mid).join("\n").trim()
            const tl = lines.slice(mid).join("\n").trim()
            root.translatedText = tr
            // If second half is unique, it is the transliteration
            const hasSecond = tl.length > 0 && tl !== tr
            translateProc.canTransliterate = hasSecond
            root.secondTranslatedText = hasSecond ? tl : ""
        }
    }

    Process {
        id: getLanguagesProc
        command: ["trans", "-list-languages", "-no-bidi"]
        property list<string> bufferList: ["auto"]
        running: true
        stdout: SplitParser {
            onRead: data => {
                getLanguagesProc.bufferList.push(data.trim());
            }
        }
        onExited: (exitCode, exitStatus) => {
            let langs = getLanguagesProc.bufferList.filter(lang => lang.trim().length > 0 && lang !== "auto").sort((a, b) => a.localeCompare(b));
            langs.unshift("auto");
            root.languages = langs;
            getLanguagesProc.bufferList = [];
        }
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: root.padding
        }
        spacing: ClockStyle.gapSmall

        // ── Language bar ────────────────────────────────────────────────
        RowLayout {
            id: languageBar
            Layout.fillWidth: true
            // The tiles fill the row's height to match each other; without this the
            // row would inherit that and swallow the panes' space.
            Layout.fillHeight: false
            spacing: ClockStyle.gapTiny

            TranslatorLanguageTile {
                id: sourceTile
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 0
                Layout.minimumWidth: 0
                caption: Translation.tr("From")
                language: root.languageName(root.sourceLanguage)
                onClicked: root.showLanguageSelectorDialog(false)
            }

            TranslatorSwapButton {
                id: swapButton
                Layout.alignment: Qt.AlignVCenter
                turns: root.swapTurns
                tooltip: Translation.tr("Swap languages (Ctrl+Enter)")
                onClicked: root.swapLanguages()
            }

            TranslatorLanguageTile {
                id: targetTile
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 0
                Layout.minimumWidth: 0
                caption: Translation.tr("To")
                language: root.languageName(root.targetLanguage)
                onClicked: root.showLanguageSelectorDialog(true)
            }
        }

        // ── Panes ───────────────────────────────────────────────────────
        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: root.wide ? 2 : 1
            rowSpacing: ClockStyle.gapSmall
            columnSpacing: ClockStyle.gapSmall

            TranslatorSourceCard {
                id: sourceCard
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 1
                Layout.preferredHeight: 1
                Layout.horizontalStretchFactor: 1
                Layout.verticalStretchFactor: root.wide ? 1 : 4
                textSize: root.textSizeFor(textArea.text.length)
                sourceName: root.languageName(root.sourceLanguage)
                onSwapRequested: root.swapLanguages()
                onInputChanged: translateTimer.restart()
            }

            TranslatorResultCard {
                id: resultCard
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 1
                Layout.preferredHeight: 1
                Layout.horizontalStretchFactor: 1
                Layout.verticalStretchFactor: root.wide ? 1 : 5
                text: root.translatedText
                transliteration: root.secondTranslatedText
                targetName: root.languageName(root.targetLanguage)
                busy: root.busy
                textSize: root.textSizeFor(root.translatedText.length)
                turns: root.swapTurns
            }
        }
    }

    StaggeredEntrance { target: languageBar; index: 0; step: ClockStyle.staggerStep }
    StaggeredEntrance { target: sourceCard; index: 1; step: ClockStyle.staggerStep }
    StaggeredEntrance { target: resultCard; index: 2; step: ClockStyle.staggerStep }

    Loader {
        anchors.fill: parent
        active: root.showLanguageSelector
        visible: root.showLanguageSelector
        z: 9999
        sourceComponent: TranslatorLanguageSheet {
            languages: root.languages
            forTarget: root.languageSelectorTarget
            current: root.languageSelectorTarget ? root.targetLanguage : root.sourceLanguage
            onDismissed: root.showLanguageSelector = false
            onPicked: language => {
                root.showLanguageSelector = false;
                if (root.languageSelectorTarget) {
                    root.targetLanguage = language;
                    Config.options.language.translator.targetLanguage = language; // Save to config
                } else {
                    root.sourceLanguage = language;
                    Config.options.language.translator.sourceLanguage = language; // Save to config
                }
                translateTimer.restart(); // Restart translation after language change
            }
        }
    }
}
