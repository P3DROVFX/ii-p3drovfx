pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * The whole Monkeytype-shaped typing test, minus any host chrome.
 *
 * Two surfaces show this: the Overview search panel and the cheatsheet page.
 * Keeping it in one component is what makes "the same test in both places"
 * true by construction instead of by two copies drifting apart — the hosts
 * only supply a frame, the hint bar and where the input focus comes from.
 *
 * It owns its own input: every keystroke here belongs to the test. Settings
 * and history are pages of this same surface rather than a trip to the
 * Settings window, because leaving the host would end the session.
 */
Item {
    id: root

    readonly property var options: Config.options.search.typingTest
    /** test, settings, history or stats. */
    property string page: "test"
    property bool personalBest: false
    /**
     * Tab points at the restart control and Enter presses it, the way
     * Monkeytype's quick-restart works. Kept as two steps by default because
     * Tab alone also walks the launcher's own controls; `quickRestart` collapses
     * it into one for people who expect the browser behaviour.
     */
    property bool restartArmed: false
    /** Extra breathing room at the sides; the stage is the hero here. */
    readonly property real stageMargin: Appearance.sizes.elevationMargin * 2.6

    /** Host chrome renders these; the surface decides what they say. */
    readonly property string statusText: TypingLanguages.errorText
    readonly property var primaryHint: ({ label: Translation.tr("Back"), keys: ["Esc"] })
    readonly property var hints: [
        { label: Translation.tr("Restart"), keys: ["Tab", "↵"] },
        { label: engine.mode === "zen" ? Translation.tr("Finish") : Translation.tr("Next test"), keys: ["Shift", "↵"] },
        { label: Translation.tr("Mode"), keys: ["Ctrl", "1-3"] },
        { label: Translation.tr("Length"), keys: ["Ctrl", "[", "]"] },
        { label: Translation.tr("Language"), keys: ["Ctrl", "L"] },
        { label: Translation.tr("History"), keys: ["Ctrl", "H"] },
        { label: Translation.tr("Stats"), keys: ["Ctrl", "S"] },
        { label: Translation.tr("Settings"), keys: ["Ctrl", ","] }
    ]

    function focusInput() {
        inputSink.forceActiveFocus();
        return true;
    }

    function handleEscape() {
        // A page over the test is what Escape closes first; only a plain test
        // hands Escape back to the host to leave the panel.
        if (root.page !== "test") {
            root.showPage("test");
            return true;
        }
        return false;
    }

    function showPage(target) {
        // A run left ticking behind a page would come back finished with a
        // time the user never spent typing, so opening one abandons it.
        if (target !== "test" && engine.isRunning)
            engine.reset(false);
        root.page = String(target);
        Qt.callLater(root.focusInput);
    }

    function togglePage(target) {
        root.showPage(root.page === target ? "test" : target);
    }

    function restart(reuseSeed) {
        root.restartArmed = false;
        root.showPage("test");
        engine.reset(Boolean(reuseSeed));
    }

    // The setters only write the preference. The engine re-rolls itself when a
    // structural parameter changes, so nothing here needs a second reset — and
    // a change made from the settings page must not throw the user back to the
    // test to see it applied.
    function setMode(value) {
        if (engine.isRunning)
            return;
        root.options.mode = String(value);
    }

    function setZenGuided(value) {
        if (engine.isRunning)
            return;
        root.options.zenGuided = Boolean(value);
    }

    function toggleZenGuided() {
        if (engine.isRunning)
            return;
        if (engine.mode !== "zen") {
            root.setZenGuided(true);
            root.setMode("zen");
            return;
        }
        root.setZenGuided(!root.options.zenGuided);
    }

    function setTime(value) {
        if (engine.isRunning)
            return;
        root.options.time = Number(value);
    }

    function setWords(value) {
        if (engine.isRunning)
            return;
        root.options.words = Number(value);
    }

    function setLanguage(value) {
        if (engine.isRunning)
            return;
        root.options.language = String(value);
        TypingLanguages.request(String(value));
    }

    function cycleLanguage() {
        const languages = TypingLanguages.languages;
        if (languages.length === 0)
            return;
        const current = languages.findIndex(language => language.id === TypingLanguages.currentPack?.id);
        root.setLanguage(languages[(current + 1 + languages.length) % languages.length].id);
    }

    /** Walks the preset row of the current mode; zen has none to walk. */
    function stepPreset(delta) {
        if (engine.isRunning || engine.mode === "zen")
            return;
        const presets = engine.mode === "time" ? [15, 30, 60, 120] : [10, 25, 50, 100];
        const current = engine.mode === "time"
            ? presets.indexOf(root.options.time) : presets.indexOf(root.options.words);
        const next = presets[(current + delta + presets.length) % presets.length];
        if (engine.mode === "time")
            root.setTime(next);
        else
            root.setWords(next);
    }

    function togglePunctuation() {
        if (engine.isRunning)
            return;
        root.options.punctuation = !root.options.punctuation;
    }

    function toggleNumbers() {
        if (engine.isRunning)
            return;
        root.options.numbers = !root.options.numbers;
    }

    /**
     * The panel's shortcut table, shared by the input sink and the panel root.
     *
     * The sink sees a key first, which is what lets `Ctrl+Backspace` mean
     * "erase the word" instead of TextInput's own word delete. Anything the
     * sink does not own bubbles to the root handler, so the shortcuts keep
     * working after a click has moved focus onto a switch or slider in the
     * settings page.
     */
    function handleShortcut(key, modifiers): bool {
        const control = (modifiers & Qt.ControlModifier) !== 0;
        const shift = (modifiers & Qt.ShiftModifier) !== 0;
        const enter = key === Qt.Key_Return || key === Qt.Key_Enter;

        if (control && key === Qt.Key_R)
            root.restart(false);
        else if (control && key === Qt.Key_Comma)
            root.togglePage("settings");
        else if (control && key === Qt.Key_H)
            root.togglePage("history");
        else if (control && key === Qt.Key_S)
            root.togglePage("stats");
        else if (control && key === Qt.Key_L)
            root.cycleLanguage();
        else if (control && key === Qt.Key_Backspace)
            root.eraseCurrentWord();
        else if (shift && enter) {
            if (engine.mode === "zen" && engine.isRunning)
                engine.finish();
            else
                root.restart(false);
        } else if (enter && (root.restartArmed || engine.isFinished))
            root.restart(false);
        else if (key === Qt.Key_Tab) {
            if (root.options.quickRestart)
                root.restart(false);
            else
                root.restartArmed = true;
        } else if (control && key >= Qt.Key_1 && key <= Qt.Key_3)
            root.setMode(["time", "words", "zen"][key - Qt.Key_1]);
        else if (control && (key === Qt.Key_BracketLeft || key === Qt.Key_BracketRight))
            root.stepPreset(key === Qt.Key_BracketRight ? 1 : -1);
        else if (control && key === Qt.Key_P)
            root.togglePunctuation();
        else if (control && key === Qt.Key_N)
            root.toggleNumbers();
        else if (control && key === Qt.Key_G)
            root.toggleZenGuided();
        else {
            // Anything else means the user moved on; the armed restart is not
            // allowed to sit there and swallow a later Enter.
            root.restartArmed = false;
            return false;
        }
        return true;
    }

    function eraseCurrentWord() {
        const textBeforeCursor = inputSink.text.slice(0, inputSink.cursorPosition);
        const textAfterCursor = inputSink.text.slice(inputSink.cursorPosition);
        const shortenedBeforeCursor = textBeforeCursor.replace(/\S+\s*$/, "");
        inputSink.text = shortenedBeforeCursor + textAfterCursor;
        inputSink.cursorPosition = shortenedBeforeCursor.length;
        engine.updateInput(inputSink.text);
    }

    Component.onCompleted: TypingLanguages.request(root.options.language)

    Keys.onPressed: event => {
        if (root.handleShortcut(event.key, event.modifiers))
            event.accepted = true;
    }

    TypingTestEngine {
        id: engine
        mode: root.options.mode
        zenGuided: root.options.zenGuided
        timeLimitSeconds: root.options.time
        wordLimit: root.options.words
        punctuation: root.options.punctuation
        numbers: root.options.numbers
        finishOnLastWord: root.options.finishOnLastWord
        languagePack: TypingLanguages.currentPack

        onCharTyped: (character, correct) => {
            sounds.playKey();
            if (!correct)
                sounds.playError();
            if (root.options.keyboard.enable)
                keyboard.flash(character);
        }
        onCharDeleted: sounds.playKey()

        // Persistence stays out of the engine: it announces the start, the
        // surface is what writes.
        onStarted: TypingHistory.registerStart()

        onFinished: {
            const result = engine.resultPayload();
            root.personalBest = TypingHistory.beatsBest(result) && result.mode !== "zen";
            TypingHistory.record(result);
        }
    }

    TypingSounds { id: sounds }

    Timer {
        interval: 100
        repeat: true
        running: engine.isRunning
        onTriggered: engine.tick()
    }

    Connections {
        target: engine
        function onResetRequested() {
            root.personalBest = false;
            root.restartArmed = false;
            inputSink.text = "";
            // Re-rolling from the settings page must not yank focus off the
            // control the user is still holding.
            if (root.page === "test")
                Qt.callLater(root.focusInput);
        }
    }

    Connections {
        target: TypingLanguages
        function onCurrentPackChanged() {
            if (TypingLanguages.currentPack?.id !== root.options.language)
                return;
            Qt.callLater(root.focusInput);
        }
    }

    Item {
        id: content
        anchors.fill: parent
        anchors.leftMargin: root.stageMargin
        anchors.rightMargin: root.stageMargin

        // ── The test ──────────────────────────────────────────────
        ColumnLayout {
            anchors.fill: parent
            visible: root.page === "test"
            spacing: 0

            TypingTestToolbar {
                Layout.fillWidth: true
                engine: engine
                settingsOpen: root.page === "settings"
                historyOpen: root.page === "history"
                statsOpen: root.page === "stats"
                onRequestMode: mode => root.setMode(mode)
                onRequestZenGuided: guided => root.setZenGuided(guided)
                onRequestTime: seconds => root.setTime(seconds)
                onRequestWords: count => root.setWords(count)
                onRequestTogglePunctuation: root.togglePunctuation()
                onRequestToggleNumbers: root.toggleNumbers()
                onRequestSettings: root.togglePage("settings")
                onRequestHistory: root.togglePage("history")
                onRequestStats: root.togglePage("stats")
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: 1
            }

            // ── Stage ─────────────────────────────────────────────
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: stageColumn.implicitHeight
                visible: !engine.isFinished

                ColumnLayout {
                    id: stageColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    spacing: Appearance.sizes.elevationMargin / 2

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.bottomMargin: 2
                        spacing: Appearance.sizes.elevationMargin

                        StyledText {
                            visible: !engine.zenGuided || engine.mode !== "zen"
                            text: engine.mode === "time"
                                ? String(Math.max(0, Math.ceil(engine.timeLimitSeconds - engine.elapsedSeconds))) + "s"
                                : (engine.mode === "words"
                                    ? String(engine.completedWords()) + "/" + String(engine.wordLimit)
                                    : String(Math.floor(engine.elapsedSeconds)) + "s")
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: Appearance.font.pixelSize.huge
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colPrimary
                        }

                        Item { Layout.fillWidth: true }

                        // The pack in use, right where the eye already is
                        // when a test starts — and one click to change it.
                        RippleButton {
                            implicitWidth: languageRow.implicitWidth + 22
                            implicitHeight: 30
                            buttonRadius: Appearance.rounding.full
                            enabled: !engine.isRunning
                            colBackground: "transparent"
                            colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
                            colRipple: Appearance.colors.colSurfaceContainerHighestActive
                            onClicked: root.cycleLanguage()

                            RowLayout {
                                id: languageRow
                                anchors.centerIn: parent
                                spacing: 5

                                MaterialSymbol {
                                    text: "language"
                                    iconSize: Appearance.font.pixelSize.normal
                                    color: Appearance.colors.colSubtext
                                }
                                StyledText {
                                    text: TypingLanguages.languageFor(TypingLanguages.currentPack?.id)?.label
                                        ?? TypingLanguages.currentPack?.name ?? Translation.tr("Language")
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colSubtext
                                }
                            }

                            StyledToolTip { text: Translation.tr("Change language (Ctrl+L)") }
                        }

                        Item { Layout.fillWidth: true }

                        StyledText {
                            visible: root.options.showLiveWpm && engine.isRunning
                            text: Translation.tr("%1 wpm").arg(String(Math.round(engine.wpm)))
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnSurfaceVariant
                        }
                        StyledText {
                            visible: root.options.showLiveAccuracy && engine.isRunning && engine.hasTarget
                            text: String(Math.round(engine.accuracy)) + "%"
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnSurfaceVariant
                        }
                    }

                    TypingWordViewport {
                        id: viewport
                        Layout.fillWidth: true
                        Layout.preferredHeight: implicitHeight
                        visible: engine.hasTarget && engine.state !== "loading"
                        engine: engine
                    }

                    StyledText {
                        Layout.fillWidth: true
                        Layout.preferredHeight: viewport.implicitHeight
                        visible: !engine.hasTarget
                        text: engine.inputText.length > 0 ? engine.inputText : Translation.tr("Start typing freely…")
                        wrapMode: Text.Wrap
                        verticalAlignment: Text.AlignTop
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: root.options.fontSize
                        font.weight: Font.Medium
                        color: engine.inputText.length > 0 ? Appearance.colors.colOnSurface : Appearance.colors.colSubtext
                    }

                    ColumnLayout {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredHeight: viewport.implicitHeight
                        visible: engine.state === "loading"
                        spacing: 6

                        Item { Layout.fillHeight: true }
                        MaterialLoadingIndicator {
                            Layout.alignment: Qt.AlignHCenter
                            implicitWidth: 30
                            implicitHeight: 30
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: Translation.tr("Loading language…")
                            color: Appearance.colors.colOnSurfaceVariant
                            font.pixelSize: Appearance.font.pixelSize.small
                        }
                        Item { Layout.fillHeight: true }
                    }
                }
            }

            // ── Result ────────────────────────────────────────────
            TypingResults {
                Layout.fillWidth: true
                Layout.preferredHeight: stageColumn.implicitHeight + Appearance.sizes.elevationMargin * 4
                visible: engine.isFinished
                engine: engine
                personalBest: root.personalBest
                onRestart: root.restart(false)
                onRepeat: root.restart(true)
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: 1
            }

            TypingKeyboardPreview {
                id: keyboard
                Layout.alignment: Qt.AlignHCenter
                Layout.bottomMargin: Appearance.sizes.elevationMargin
                visible: root.options.keyboard.enable && !engine.isFinished
                nextChar: engine.nextExpectedChar.toLowerCase()
                opacity: engine.isRunning ? 0.85 : 1
            }

            RippleButton {
                id: restartButton
                Layout.alignment: Qt.AlignHCenter
                Layout.bottomMargin: Appearance.sizes.elevationMargin / 2
                visible: !engine.isFinished
                implicitWidth: root.restartArmed ? armedContent.implicitWidth + 28 : 40
                implicitHeight: 40
                buttonRadius: Appearance.rounding.full
                colBackground: root.restartArmed ? Appearance.colors.colPrimaryContainer : "transparent"
                colBackgroundHover: root.restartArmed
                    ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colSurfaceContainerHighestHover
                colRipple: root.restartArmed
                    ? Appearance.colors.colPrimaryContainerActive : Appearance.colors.colSurfaceContainerHighestActive
                onClicked: root.restart(false)

                Behavior on implicitWidth {
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Appearance.animation.elementMoveFast.type
                        easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                    }
                }

                RowLayout {
                    id: armedContent
                    anchors.centerIn: parent
                    spacing: 6

                    MaterialSymbol {
                        text: "refresh"
                        iconSize: Appearance.font.pixelSize.huge
                        color: root.restartArmed
                            ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
                    }

                    StyledText {
                        visible: root.restartArmed
                        text: Translation.tr("Enter to restart")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnPrimaryContainer
                    }
                }

                StyledToolTip { text: Translation.tr("Restart (Ctrl+R, or Tab then Enter)") }
            }
        }

        // ── Settings and history pages ────────────────────────────
        ColumnLayout {
            anchors.fill: parent
            visible: root.page !== "test"
            spacing: Appearance.sizes.elevationMargin / 2

            RowLayout {
                Layout.fillWidth: true
                Layout.bottomMargin: Appearance.sizes.elevationMargin / 2
                spacing: Appearance.sizes.elevationMargin / 2

                RippleButton {
                    implicitWidth: 34
                    implicitHeight: 34
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colSurfaceContainerHigh
                    colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
                    colRipple: Appearance.colors.colSurfaceContainerHighestActive
                    onClicked: root.showPage("test")

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "arrow_back"
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.page === "settings" ? Translation.tr("Typing test settings")
                        : (root.page === "stats" ? Translation.tr("Statistics") : Translation.tr("Score history"))
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnSurface
                }
            }

            Loader {
                Layout.fillWidth: true
                Layout.fillHeight: true
                active: root.page === "settings"
                visible: active
                sourceComponent: TypingSettingsPage {}
            }

            Loader {
                Layout.fillWidth: true
                Layout.fillHeight: true
                active: root.page === "history"
                visible: active
                sourceComponent: TypingHistoryPage {}
            }

            Loader {
                Layout.fillWidth: true
                Layout.fillHeight: true
                active: root.page === "stats"
                visible: active
                sourceComponent: TypingStatsPage {}
            }
        }

        // A real editor, not key-event text reconstruction: it lets Qt
        // finish dead keys and IME composition before the engine observes
        // committed text. The visible typing surface renders its own chars.
        TextInput {
            id: inputSink
            width: 1
            height: 1
            opacity: 0
            focus: true
            inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
            onTextEdited: {
                if (root.page !== "test" || engine.isFinished || engine.state === "loading") {
                    // Keys pressed on another page must not silently begin
                    // a test behind it.
                    inputSink.text = engine.inputText;
                    return;
                }
                engine.updateInput(text);
            }
            Keys.onPressed: event => {
                if (root.handleShortcut(event.key, event.modifiers))
                    event.accepted = true;
            }
        }
    }
}
