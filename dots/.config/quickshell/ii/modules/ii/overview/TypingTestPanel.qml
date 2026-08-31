pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import "typing"

Item {
    id: root

    readonly property int panelWidth: Config.options.search.appearance.panelWidth
    implicitWidth: panelWidth
    implicitHeight: scaffold.implicitHeight

    function focusInput() {
        if (engine.isFinished)
            return false;
        inputSink.forceActiveFocus();
        return true;
    }

    function handleEscape() {
        return false;
    }

    function restart(reuseSeed) {
        engine.reset(Boolean(reuseSeed));
    }

    function setMode(value) {
        if (engine.isRunning)
            return;
        Config.options.search.typingTest.mode = String(value);
        root.restart(false);
    }

    function setTime(value) {
        if (engine.isRunning)
            return;
        Config.options.search.typingTest.time = Number(value);
        root.restart(false);
    }

    function setWords(value) {
        if (engine.isRunning)
            return;
        Config.options.search.typingTest.words = Number(value);
        root.restart(false);
    }

    function setLanguage(value) {
        if (engine.isRunning)
            return;
        Config.options.search.typingTest.language = String(value);
        TypingLanguages.request(String(value));
    }

    function togglePunctuation() {
        if (engine.isRunning)
            return;
        Config.options.search.typingTest.punctuation = !Config.options.search.typingTest.punctuation;
        root.restart(false);
    }

    function toggleNumbers() {
        if (engine.isRunning)
            return;
        Config.options.search.typingTest.numbers = !Config.options.search.typingTest.numbers;
        root.restart(false);
    }

    function eraseCurrentWord() {
        const textBeforeCursor = inputSink.text.slice(0, inputSink.cursorPosition);
        const textAfterCursor = inputSink.text.slice(inputSink.cursorPosition);
        const shortenedBeforeCursor = textBeforeCursor.replace(/\S+\s*$/, "");
        inputSink.text = shortenedBeforeCursor + textAfterCursor;
        inputSink.cursorPosition = shortenedBeforeCursor.length;
        engine.updateInput(inputSink.text);
    }

    Component.onCompleted: TypingLanguages.request(Config.options.search.typingTest.language)

    TypingTestEngine {
        id: engine
        mode: Config.options.search.typingTest.mode
        timeLimitSeconds: Config.options.search.typingTest.time
        wordLimit: Config.options.search.typingTest.words
        punctuation: Config.options.search.typingTest.punctuation
        numbers: Config.options.search.typingTest.numbers
        languagePack: TypingLanguages.currentPack
    }

    Timer {
        interval: 100
        repeat: true
        running: engine.isRunning
        onTriggered: engine.tick()
    }

    Connections {
        target: engine
        function onResetRequested() {
            inputSink.text = "";
            Qt.callLater(root.focusInput);
        }
    }

    Connections {
        target: TypingLanguages
        function onCurrentPackChanged() {
            if (TypingLanguages.currentPack?.id !== Config.options.search.typingTest.language)
                return;
            Qt.callLater(root.focusInput);
        }
    }

    SearchPanelScaffold {
        id: scaffold
        anchors.fill: parent
        showHeader: false
        showStatus: TypingLanguages.errorText.length > 0
        statusText: TypingLanguages.errorText
        minimumContentHeight: Config.options.search.appearance.panelBodyHeight
        primaryHint: ({ key: "Esc", label: qsTr("Back") })
        hints: [
            { key: "Ctrl+R", label: qsTr("Restart") },
            { key: "Shift+Enter", label: qsTr("Finish zen") }
        ]

        Item {
            anchors.fill: parent

            ColumnLayout {
                anchors.fill: parent
                spacing: Appearance.sizes.elevationMargin

                TypingTestToolbar {
                    id: toolbar
                    Layout.fillWidth: true
                    engine: engine
                    languages: TypingLanguages.languages
                    onRequestMode: root.setMode(mode)
                    onRequestTime: root.setTime(seconds)
                    onRequestWords: root.setWords(count)
                    onRequestLanguage: root.setLanguage(languageId)
                    onRequestTogglePunctuation: root.togglePunctuation()
                    onRequestToggleNumbers: root.toggleNumbers()
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    TypingWordViewport {
                        anchors.centerIn: parent
                        width: parent.width
                        height: Math.round(estimatedLineHeight * 3)
                        visible: engine.mode !== "zen" && !engine.isFinished && engine.state !== "loading"
                        engine: engine
                    }

                    Text {
                        anchors.centerIn: parent
                        width: parent.width
                        visible: engine.mode === "zen" && !engine.isFinished
                        text: engine.inputText.length > 0 ? engine.inputText : qsTr("Start typing freely…")
                        wrapMode: Text.Wrap
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.huge
                        font.weight: Font.Medium
                        color: engine.inputText.length > 0 ? Appearance.colors.colOnSurface : Appearance.colors.colSubtext
                    }

                    ColumnLayout {
                        anchors.centerIn: parent
                        visible: engine.state === "loading"
                        spacing: Appearance.sizes.elevationMargin / 2
                        MaterialLoadingIndicator { Layout.alignment: Qt.AlignHCenter; implicitWidth: Appearance.sizes.elevationMargin * 3; implicitHeight: implicitWidth }
                        StyledText { text: qsTr("Loading language…"); color: Appearance.colors.colOnSurfaceVariant; font.pixelSize: Appearance.font.pixelSize.small }
                    }

                    TypingResults {
                        anchors.fill: parent
                        visible: engine.isFinished
                        engine: engine
                        onRestart: root.restart(false)
                        onRepeat: root.restart(true)
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: !engine.isFinished

                    StyledText {
                        text: engine.mode === "time"
                            ? String(Math.max(0, Math.ceil(engine.timeLimitSeconds - engine.elapsedSeconds))) + "s"
                            : (engine.mode === "words" ? String(engine.completedWords()) + "/" + String(engine.wordLimit) : String(Math.floor(engine.elapsedSeconds)) + "s")
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.large
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colPrimary
                    }
                    Item { Layout.fillWidth: true }
                    StyledText {
                        visible: Config.options.search.typingTest.showLiveWpm && engine.isRunning
                        text: qsTr("%1 wpm").arg(String(Math.round(engine.wpm)))
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                    StyledText {
                        visible: Config.options.search.typingTest.showLiveAccuracy && engine.isRunning && engine.mode !== "zen"
                        text: qsTr("%1%").arg(String(Math.round(engine.accuracy)))
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnSurfaceVariant
                    }
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
                enabled: !engine.isFinished && engine.state !== "loading"
                inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                onTextEdited: engine.updateInput(text)
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_R && (event.modifiers & Qt.ControlModifier)) {
                        root.restart(false);
                        event.accepted = true;
                        return;
                    }
                    if (event.key === Qt.Key_Backspace && (event.modifiers & Qt.ControlModifier)) {
                        root.eraseCurrentWord();
                        event.accepted = true;
                        return;
                    }
                    if (engine.mode === "zen" && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                            && (event.modifiers & Qt.ShiftModifier)) {
                        engine.finish();
                        event.accepted = true;
                    }
                }
            }
        }
    }
}
