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

/**
 * Translator tab, on the `trans` command line tool (scripts/translator/translator.py).
 *
 * Material 3 Expressive, after the Clock app: a connected language bar (two tiles hinged
 * by a scalloped swap shape), the source pane, the translation as the hero pane that
 * takes the hue of its state, and — for words — a dictionary pane. The panes stack in
 * the sidebar and sit side by side when the sidebar is extended.
 */
Item {
    id: root

    // Sizes
    property real padding: Appearance.rounding.small
    /// Side-by-side panes once there is room for two readable columns.
    readonly property bool wide: root.width >= 600

    // Widgets
    property var inputField: sourceCard.textArea

    readonly property bool hasInput: session.hasInput
    readonly property bool showDictionary: session.hasDictionary && !session.error

    // States
    property bool showLanguageSelector: false
    property bool languageSelectorTarget: false // true for target language, false for source language

    /// The source tile names the detected language while "Detect language" is on.
    readonly property string sourceTileName: TranslatorService.sourceLanguage === "auto" && session.detected
        ? TranslatorService.displayName(session.detected)
        : TranslatorService.displayName(TranslatorService.sourceLanguage)

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

    /// Swaps the languages and, like every translator, the texts with them.
    function swapLanguages() {
        const translation = session.translation;
        if (!TranslatorService.swap(session.detected))
            return;
        if (translation.length > 0 && !session.busy) {
            root.inputField.text = translation;
            root.inputField.cursorPosition = root.inputField.length;
        }
    }

    function speakSource() {
        TranslatorService.speak("sidebar:source", session.trimmed, session.effectiveSource);
    }

    function speakTranslation() {
        TranslatorService.speak("sidebar:target", session.translation, session.targetCode);
    }

    function lookUp(word: string) {
        root.inputField.text = word;
        root.inputField.cursorPosition = root.inputField.length;
        root.inputField.forceActiveFocus();
    }

    Component.onCompleted: TranslatorService.ensureLanguages()

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

    TranslatorSession {
        id: session
        text: sourceCard.textArea.text
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
                caption: TranslatorService.sourceLanguage === "auto" && session.detected ? Translation.tr("Detected") : Translation.tr("From")
                language: root.sourceTileName
                onClicked: root.showLanguageSelectorDialog(false)
            }

            TranslatorSwapButton {
                id: swapButton
                Layout.alignment: Qt.AlignVCenter
                turns: TranslatorService.swapTurns
                enabled: TranslatorService.sourceLanguage !== "auto" || session.detected.length > 0
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
                language: TranslatorService.displayName(TranslatorService.targetLanguage)
                onClicked: root.showLanguageSelectorDialog(true)
            }
        }

        // ── Panes ───────────────────────────────────────────────────────
        // Narrow: source, translation, dictionary stacked. Wide: source over the
        // dictionary on the left, the translation as a tall hero on the right.
        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: root.wide ? 2 : 1
            rowSpacing: ClockStyle.gapSmall
            columnSpacing: ClockStyle.gapSmall

            TranslatorSourceCard {
                id: sourceCard
                Layout.row: 0
                Layout.column: 0
                Layout.rowSpan: root.wide && !root.showDictionary ? 2 : 1
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 1
                Layout.preferredHeight: 1
                Layout.horizontalStretchFactor: 1
                Layout.verticalStretchFactor: root.wide ? 1 : 4
                textSize: root.textSizeFor(textArea.text.length)
                sourceName: root.sourceTileName
                phonetic: session.sourceTransliteration
                correction: session.correction
                canSpeak: root.hasInput && session.effectiveSource.length > 0
                speaking: TranslatorService.speakingKey === "sidebar:source"
                speakFailed: TranslatorService.failedSpeakKey === "sidebar:source"
                onSwapRequested: root.swapLanguages()
                onSpeakRequested: root.speakSource()
            }

            TranslatorResultCard {
                id: resultCard
                Layout.row: root.wide ? 0 : 1
                Layout.column: root.wide ? 1 : 0
                Layout.rowSpan: root.wide ? 2 : 1
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 1
                Layout.preferredHeight: 1
                Layout.horizontalStretchFactor: 1
                Layout.verticalStretchFactor: root.wide ? 1 : 5
                text: session.translation
                transliteration: session.transliteration
                alternatives: session.alternatives
                dictionary: session.dictionary
                error: root.hasInput ? session.error : ""
                targetName: TranslatorService.displayName(TranslatorService.targetLanguage)
                busy: session.busy
                textSize: root.textSizeFor(session.translation.length)
                turns: TranslatorService.swapTurns
                canSpeak: true
                speaking: TranslatorService.speakingKey === "sidebar:target"
                speakFailed: TranslatorService.failedSpeakKey === "sidebar:target"
                onSpeakRequested: root.speakTranslation()
                onRetryRequested: session.retry()
            }

            TranslatorDictionaryCard {
                id: dictionaryCard
                Layout.row: root.wide ? 1 : 2
                Layout.column: 0
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 1
                Layout.preferredHeight: 1
                Layout.horizontalStretchFactor: 1
                Layout.verticalStretchFactor: root.wide ? 1 : 5
                visible: root.showDictionary
                headword: session.trimmed
                phonetic: session.sourceTransliteration
                languageName: TranslatorService.displayName(session.effectiveSource)
                definitions: session.definitions
                examples: session.examples
                synonyms: session.synonyms
                onLookupRequested: word => root.lookUp(word)
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
            forTarget: root.languageSelectorTarget
            current: root.languageSelectorTarget ? TranslatorService.targetLanguage : TranslatorService.sourceLanguage
            detected: session.detected
            onDismissed: root.showLanguageSelector = false
            onPicked: language => {
                root.showLanguageSelector = false;
                if (root.languageSelectorTarget)
                    TranslatorService.setTarget(language);
                else
                    TranslatorService.setSource(language);
            }
        }
    }
}
