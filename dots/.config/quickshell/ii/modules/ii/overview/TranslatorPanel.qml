pragma ComponentBehavior: Bound

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
 * The sidebar's translator, laid out for the overview's wide panel: the same language
 * bar, source pane, hero translation and dictionary, side by side instead of stacked.
 *
 * The search field is the input — the source pane mirrors it — so everything else is
 * reached by shortcut: Enter copies, Ctrl+Enter swaps, Ctrl+S reads the translation
 * aloud, Ctrl+V pastes, Shift+Del clears; Down walks into the language bar.
 */
Item {
    id: root
    // Every motion in the overview and its panels answers to one switch:
    // Settings -> Overview -> Animation style -> None.
    readonly property bool animationsDisabled: Config.options.overview.animationStyle === "none"
    property string searchQuery: ""

    readonly property int panelWidth: Config.options.search.clipboard.panelWidth ?? 860
    implicitWidth: panelWidth
    implicitHeight: scaffold.implicitHeight

    // Signals for parent communication
    signal requestSetSearchQuery(string query)
    signal requestFocusSearchInput()

    property bool showLanguageSelector: false
    property bool languageSelectorTarget: false // true for target, false for source

    // Keyboard focus in the language bar:
    // -1 = search field (default), 0 = source tile, 1 = swap, 2 = target tile.
    property int focusedControlIndex: -1

    readonly property bool hasInput: session.hasInput
    readonly property bool showDictionary: session.hasDictionary && !session.error
    readonly property string sourceTileName: TranslatorService.sourceLanguage === "auto" && session.detected
        ? TranslatorService.displayName(session.detected)
        : TranslatorService.displayName(TranslatorService.sourceLanguage)

    function textSizeFor(length: int): int {
        if (length <= 48)
            return Appearance.font.pixelSize.huge + 6;
        if (length <= 160)
            return Appearance.font.pixelSize.huge;
        return Appearance.font.pixelSize.large;
    }

    function showLanguageSelectorDialog(isTargetLang) {
        root.languageSelectorTarget = isTargetLang;
        root.showLanguageSelector = true;
    }

    /// Swaps the languages and, like every translator, the texts with them.
    function swapLanguages() {
        const translation = session.translation;
        if (!TranslatorService.swap(session.detected))
            return;
        if (translation.length > 0 && !session.busy)
            root.requestSetSearchQuery(translation);
    }

    function pasteFromClipboard() {
        const clipboardText = Quickshell.clipboardText;
        if (clipboardText)
            root.requestSetSearchQuery(clipboardText);
    }

    function clearInput() {
        root.requestSetSearchQuery("");
    }

    function copyTranslation() {
        if (session.translation.length > 0)
            resultCard.copy(session.translation);
    }

    function speakTranslation() {
        TranslatorService.speak("overview:target", session.translation, session.targetCode);
    }

    function speakSource() {
        TranslatorService.speak("overview:source", session.trimmed, session.effectiveSource);
    }

    function navigateDown() {
        if (root.focusedControlIndex === -1)
            root.focusedControlIndex = 0;
    }

    function navigateUp() {
        if (root.focusedControlIndex !== -1)
            root.focusInput();
    }

    function navigateLeft() {
        if (root.focusedControlIndex > 0)
            root.focusedControlIndex--;
    }

    function navigateRight() {
        if (root.focusedControlIndex >= 0 && root.focusedControlIndex < 2)
            root.focusedControlIndex++;
    }

    function activateSelected() {
        if (root.focusedControlIndex === 0)
            root.showLanguageSelectorDialog(false);
        else if (root.focusedControlIndex === 1)
            root.swapLanguages();
        else if (root.focusedControlIndex === 2)
            root.showLanguageSelectorDialog(true);
        else
            root.copyTranslation();
    }

    function focusInput() {
        root.focusedControlIndex = -1;
        root.requestFocusSearchInput();
    }

    // Global panel shortcuts (SearchBar dispatches these by name whenever
    // this panel is active — see the "secondary"/"save"/"paste"/"delete"
    // keybinds in Config.options.search.keybindings). Plain Enter already
    // reaches copyTranslation() through activateSelected().
    function secondaryActivateSelected(): bool {
        root.swapLanguages();
        return true;
    }

    function saveSelected(): bool {
        root.speakTranslation();
        return true;
    }

    function copySelected(): bool {
        root.copyTranslation();
        return true;
    }

    function pasteClipboard(): bool {
        root.pasteFromClipboard();
        return true;
    }

    function deleteSelected(): bool {
        root.clearInput();
        return true;
    }

    onSearchQueryChanged: root.focusedControlIndex = -1

    onShowLanguageSelectorChanged: {
        // The sheet's search field held focus; hand it back to the search field.
        if (!root.showLanguageSelector)
            Qt.callLater(root.requestFocusSearchInput);
    }

    Component.onCompleted: TranslatorService.ensureLanguages()
    Component.onDestruction: {
        if (TranslatorService.speakingKey.startsWith("overview:"))
            TranslatorService.stopSpeaking();
    }

    TranslatorSession {
        id: session
        text: root.searchQuery
    }

    SearchPanelScaffold {
        id: scaffold
        anchors.fill: parent
        minimumContentHeight: 520
        primaryHint: ({ label: Translation.tr("Copy"), actionId: "activate", keys: ["↵"] })
        hints: [
            { label: Translation.tr("Swap languages"), actionId: "secondary", keys: ["Ctrl", "↵"] },
            { label: Translation.tr("Listen"), actionId: "save", keys: ["Ctrl", "S"] },
            { label: Translation.tr("Paste"), actionId: "paste", keys: ["Ctrl", "V"] },
            { label: Translation.tr("Clear"), actionId: "delete", keys: ["⇧", "Del"] }
        ]

        ColumnLayout {
            id: content
            anchors.fill: parent
            spacing: ClockStyle.gapSmall
            // The sheet takes the panel; the panes step out of its way.
            opacity: root.showLanguageSelector ? 0 : 1
            visible: opacity > 0
            Behavior on opacity {
                enabled: !root.animationsDisabled
                animation: ClockStyle.motionFast.numberAnimation.createObject(this)
            }

            // ── Language bar ────────────────────────────────────────────
            RowLayout {
                id: languageBar
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: ClockStyle.gapTiny

                TranslatorLanguageTile {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 0
                    Layout.minimumWidth: 0
                    caption: TranslatorService.sourceLanguage === "auto" && session.detected ? Translation.tr("Detected") : Translation.tr("From")
                    language: root.sourceTileName
                    keyboardFocused: root.focusedControlIndex === 0
                    onClicked: {
                        root.focusedControlIndex = 0;
                        root.showLanguageSelectorDialog(false);
                    }
                }

                TranslatorSwapButton {
                    Layout.alignment: Qt.AlignVCenter
                    turns: TranslatorService.swapTurns
                    enabled: TranslatorService.sourceLanguage !== "auto" || session.detected.length > 0
                    keyboardFocused: root.focusedControlIndex === 1
                    tooltip: Translation.tr("Swap languages (Ctrl+Enter)")
                    onClicked: {
                        root.focusedControlIndex = 1;
                        root.swapLanguages();
                    }
                }

                TranslatorLanguageTile {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 0
                    Layout.minimumWidth: 0
                    caption: Translation.tr("To")
                    language: TranslatorService.displayName(TranslatorService.targetLanguage)
                    keyboardFocused: root.focusedControlIndex === 2
                    onClicked: {
                        root.focusedControlIndex = 2;
                        root.showLanguageSelectorDialog(true);
                    }
                }
            }

            // ── Panes ───────────────────────────────────────────────────
            // Source and translation share the row; the dictionary slides in from
            // the right when the text is a word. Its slot animates width and clips
            // while the card inside keeps its settled width, so it slides instead
            // of reflowing.
            RowLayout {
                id: panes
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: ClockStyle.gapSmall

                readonly property real dictionarySettledWidth: Math.round((panes.width - ClockStyle.gapSmall * 2) * 0.32)
                property real dictionaryProgress: root.showDictionary ? 1 : 0
                Behavior on dictionaryProgress {
                    enabled: !root.animationsDisabled
                    animation: ClockStyle.motionDefault.numberAnimation.createObject(this)
                }

                TranslatorSourceCard {
                    id: sourceCard
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 10
                    Layout.horizontalStretchFactor: 10
                    editable: false
                    externalText: root.searchQuery
                    textSize: root.textSizeFor(root.searchQuery.length)
                    sourceName: root.sourceTileName
                    phonetic: session.sourceTransliteration
                    correction: session.correction
                    canSpeak: root.hasInput && session.effectiveSource.length > 0
                    speaking: TranslatorService.speakingKey === "overview:source"
                    speakFailed: TranslatorService.failedSpeakKey === "overview:source"
                    onPasteRequested: root.pasteFromClipboard()
                    onClearRequested: root.clearInput()
                    onSpeakRequested: root.speakSource()
                    onCorrectionAccepted: text => root.requestSetSearchQuery(text)
                }

                TranslatorResultCard {
                    id: resultCard
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 12
                    Layout.horizontalStretchFactor: 12
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
                    speaking: TranslatorService.speakingKey === "overview:target"
                    speakFailed: TranslatorService.failedSpeakKey === "overview:target"
                    emptyHint: Translation.tr("Type in the search field — Enter copies the translation, Ctrl+S reads it aloud")
                    onSpeakRequested: root.speakTranslation()
                    onRetryRequested: session.retry()
                }

                Item {
                    id: dictionarySlot
                    Layout.fillHeight: true
                    Layout.preferredWidth: Math.round(panes.dictionarySettledWidth * panes.dictionaryProgress)
                    // The row's spacing would leave a gap for the closed slot.
                    Layout.leftMargin: -ClockStyle.gapSmall * (1 - panes.dictionaryProgress)
                    visible: panes.dictionaryProgress > 0
                    clip: true
                    opacity: panes.dictionaryProgress

                    TranslatorDictionaryCard {
                        anchors {
                            top: parent.top
                            bottom: parent.bottom
                            right: parent.right
                        }
                        width: panes.dictionarySettledWidth
                        headword: session.trimmed
                        phonetic: session.sourceTransliteration
                        languageName: TranslatorService.displayName(session.effectiveSource)
                        definitions: session.definitions
                        examples: session.examples
                        synonyms: session.synonyms
                        onLookupRequested: word => root.requestSetSearchQuery(word)
                    }
                }
            }
        }
    }

    Loader {
        anchors.fill: parent
        anchors.margins: scaffold.contentMargin
        active: root.showLanguageSelector
        visible: root.showLanguageSelector
        z: 9999
        sourceComponent: TranslatorLanguageSheet {
            colPage: "transparent"
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
