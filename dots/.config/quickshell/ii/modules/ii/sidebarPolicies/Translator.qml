import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io

/**
 * Translator widget with the `trans` commandline tool.
 * Redesigned for Material 3 Expressive
 */
Item {
    id: root

    // Sizes
    property real padding: Appearance.rounding.small

    // Colors
    property color colLangBtn: Appearance.colors.colSecondaryContainer
    property color colLangBtnHover: Appearance.colors.colSecondaryContainerHover
    property color colLangBtnActive: Appearance.colors.colSecondaryContainerActive
    property color colLangText: Appearance.colors.colOnSecondaryContainer

    property color colSwapBtn: Appearance.colors.colTertiaryContainer
    property color colSwapBtnHover: Appearance.colors.colTertiaryContainerHover
    property color colSwapBtnActive: Appearance.colors.colTertiaryContainerActive
    property color colSwapIcon: Appearance.colors.colOnTertiaryContainer

    property color colInputBox: Appearance.colors.colPrimaryContainer
    property color colInputText: Appearance.colors.colOnPrimaryContainer

    property color colResultBox: Appearance.colors.colSurfaceContainerHigh
    property color colResultText: Appearance.colors.colOnSurface

    property color colPasteBtn: colResultBox
    property color colPasteBtnHover: Appearance.colors.colSurfaceContainerHighestHover
    property color colPasteBtnActive: Appearance.colors.colSurfaceContainerHighestActive
    property color colPasteIcon: colResultText

    property color colResultActionBtn: colInputBox
    property color colResultActionBtnHover: Appearance.colors.colPrimaryContainerHover
    property color colResultActionBtnActive: Appearance.colors.colPrimaryContainerActive
    property color colResultActionIcon: colInputText

    // Widgets
    property var inputField: inputTextArea

    // Widget variables
    property bool translationFor: false // Indicates if the translation is for an autocorrected text
    property string translatedText: ""
    property string secondTranslatedText: ""
    property list<string> languages: []

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

    // States
    property bool showLanguageSelector: false
    property bool languageSelectorTarget: false // true for target language, false for source language

    function showLanguageSelectorDialog(isTargetLang: bool) {
        root.languageSelectorTarget = isTargetLang;
        root.showLanguageSelector = true;
    }

    onFocusChanged: focus => {
        if (focus) {
            root.inputField.forceActiveFocus();
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
            if (root.inputField.text.trim().length > 0) {
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
        onStarted: {
            buffer = ""
            root.translatedText = ""
            root.secondTranslatedText = ""
        }
        onExited: () => {
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
        spacing: 8

        // Language Selectors Row
        RowLayout {
            Layout.fillWidth: true
            spacing: Appearance.rounding.small

            RippleButton {
                Layout.fillWidth: true
                Layout.preferredHeight: 50
                Layout.preferredWidth: 1
                buttonRadius: Appearance.rounding.full
                colBackground: pressed ? colLangBtnActive : (hovered ? colLangBtnHover : colLangBtn)

                contentItem: RowLayout {
                    anchors.fill: parent
                    spacing: 8
                    Item {
                        Layout.fillWidth: true
                    }
                    StyledText {
                        Layout.fillWidth: true
                        Layout.maximumWidth: implicitWidth
                        elide: Text.ElideRight
                        horizontalAlignment: Text.AlignHCenter
                        text: root.sourceLanguage
                        color: colLangText
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.bold: true
                    }
                    MaterialSymbol {
                        text: "arrow_drop_down"
                        color: colLangText
                        iconSize: Appearance.font.pixelSize.larger
                    }
                    Item {
                        Layout.fillWidth: true
                    }
                }
                onClicked: root.showLanguageSelectorDialog(false)
            }

            RippleButton {
                implicitWidth: 50
                implicitHeight: 50
                buttonRadius: Appearance.rounding.full
                colBackground: pressed ? colSwapBtnActive : (hovered ? colSwapBtnHover : colSwapBtn)
                contentItem: Item {
                    anchors.fill: parent
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "swap_horiz"
                        color: colSwapIcon
                        iconSize: Appearance.font.pixelSize.larger
                    }
                }
                onClicked: {
                    let temp = root.sourceLanguage;
                    root.sourceLanguage = root.targetLanguage;
                    root.targetLanguage = temp;
                    // Trigger translation
                    if (root.inputField.text.trim().length > 0) {
                        translateTimer.restart();
                    }
                }
            }

            RippleButton {
                Layout.fillWidth: true
                Layout.preferredHeight: 50
                Layout.preferredWidth: 1
                buttonRadius: Appearance.rounding.full
                colBackground: pressed ? colLangBtnActive : (hovered ? colLangBtnHover : colLangBtn)

                contentItem: RowLayout {
                    anchors.fill: parent
                    spacing: 8
                    Item {
                        Layout.fillWidth: true
                    }
                    StyledText {
                        Layout.fillWidth: true
                        Layout.maximumWidth: implicitWidth
                        elide: Text.ElideRight
                        horizontalAlignment: Text.AlignHCenter
                        text: root.targetLanguage
                        color: colLangText
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.bold: true
                    }
                    MaterialSymbol {
                        text: "arrow_drop_down"
                        color: colLangText
                        iconSize: Appearance.font.pixelSize.larger
                    }
                    Item {
                        Layout.fillWidth: true
                    }
                }
                onClicked: root.showLanguageSelectorDialog(true)
            }
        }

        // Input Area (Source)
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Appearance.rounding.large
            color: colInputBox

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Appearance.rounding.normal

                StyledFlickable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    StyledTextArea {
                        id: inputTextArea
                        width: parent.width
                        placeholderText: Translation.tr("Translate text")
                        wrapMode: TextEdit.Wrap
                        font.pixelSize: Appearance.font.pixelSize.huge // Material 3 Expressive
                        color: colInputText
                        background: null
                        onTextChanged: translateTimer.restart()
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    StyledText {
                        text: root.inputField.text.length + " characters"
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
                    Item {
                        Layout.fillWidth: true
                    }
                    RippleButton {
                        implicitWidth: 40
                        implicitHeight: 40
                        buttonRadius: Appearance.rounding.full
                        colBackground: pressed ? colPasteBtnActive : (hovered ? colPasteBtnHover : colPasteBtn)
                        contentItem: Item {
                            anchors.fill: parent
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "close"
                                color: colPasteIcon
                            }
                        }
                        onClicked: root.inputField.text = ""
                        visible: root.inputField.text.length > 0
                    }
                    RippleButton {
                        implicitWidth: 40
                        implicitHeight: 40
                        buttonRadius: Appearance.rounding.full
                        colBackground: pressed ? colPasteBtnActive : (hovered ? colPasteBtnHover : colPasteBtn)
                        contentItem: Item {
                            anchors.fill: parent
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "content_paste"
                                color: colPasteIcon
                            }
                        }
                        onClicked: root.inputField.text = Quickshell.clipboardText
                    }
                }
            }
        }

        // Output Area (Target)
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Appearance.rounding.large
            color: colResultBox

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Appearance.rounding.normal

                StyledFlickable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 0
                    clip: true

                    contentHeight: contentColumn.implicitHeight

                    ColumnLayout {
                        id: contentColumn
                        width: parent.width
                        spacing: 8

                        // Main translated output
                        StyledText {
                            text: root.translatedText !== "" ? root.translatedText : Translation.tr("Translation will appear here...")
                            visible: true

                            wrapMode: Text.Wrap
                            font.pixelSize: Appearance.font.pixelSize.huge
                            color: root.translatedText !== "" ? colResultText : Appearance.colors.colSubtext
                            opacity: root.translatedText !== "" ? 1.0 : 0.6

                            Layout.fillWidth: true
                        }

                        // Transliteration translated output
                        Rectangle {
                            id: transliterationBubble

                            Layout.fillWidth: true
                            visible: root.secondTranslatedText.length > 0
                            
                            opacity: visible ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 120 } }

                            radius: Appearance.rounding.large
                            color: Qt.darker(colResultBox, 1.8)

                            implicitHeight: transliterationText.implicitHeight + 20
                            property bool hovered: false

                            HoverHandler {
                                onHoveredChanged: transliterationBubble.hovered = hovered
                            }

                            StyledText {
                                id: transliterationText

                                text: root.secondTranslatedText
                                wrapMode: Text.Wrap
                                color: colResultText

                                anchors {
                                    top: parent.top
                                    left: parent.left
                                    right: parent.right
                                    margins: 10
                                    bottomMargin: 10
                                }
                            }

                            // Copy button
                            RippleButton {
                                implicitWidth: 28
                                implicitHeight: 28
                                buttonRadius: Appearance.rounding.full

                                anchors {
                                    right: parent.right
                                    bottom: parent.bottom
                                    margins: 6
                                }

                                opacity: transliterationBubble.hovered ? 1.0 : 0.0
                                visible: opacity > 0.01
                                colBackground: pressed ? colResultActionBtnActive : (hovered ? colResultActionBtnHover : colResultActionBtn)
                                Behavior on opacity { NumberAnimation { duration: 150 } }

                                contentItem: Item {
                                    anchors.fill: parent

                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "content_copy"
                                        color: colResultActionIcon
                                        font.pixelSize: 14
                                    }
                                }

                                onClicked: Quickshell.clipboardText = root.secondTranslatedText
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Item {
                        Layout.fillWidth: true
                    }
                    RippleButton {
                        implicitWidth: 40
                        implicitHeight: 40
                        buttonRadius: Appearance.rounding.full
                        colBackground: pressed ? colResultActionBtnActive : (hovered ? colResultActionBtnHover : colResultActionBtn)
                        contentItem: Item {
                            anchors.fill: parent
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "content_copy"
                                color: colResultActionIcon
                            }
                        }
                        onClicked: Quickshell.clipboardText = root.translatedText
                        visible: root.translatedText.length > 0
                    }
                    RippleButton {
                        implicitWidth: 40
                        implicitHeight: 40
                        buttonRadius: Appearance.rounding.full
                        colBackground: pressed ? colResultActionBtnActive : (hovered ? colResultActionBtnHover : colResultActionBtn)
                        contentItem: Item {
                            anchors.fill: parent
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "travel_explore"
                                color: colResultActionIcon
                            }
                        }
                        onClicked: {
                            let url = Config.options.search.engineBaseUrl + root.translatedText;
                            for (let site of Config.options.search.excludedSites) {
                                url += ` -site:${site}`;
                            }
                            Qt.openUrlExternally(url);
                        }
                        visible: root.translatedText.length > 0
                    }
                }
            }
        }
    }

    Loader {
        anchors.fill: parent
        active: root.showLanguageSelector
        visible: root.showLanguageSelector
        z: 9999
        sourceComponent: SelectionDialog {
            id: languageSelectorDialog
            titleText: Translation.tr("Select Language")
            items: root.languages
            defaultChoice: root.languageSelectorTarget ? root.targetLanguage : root.sourceLanguage
            enableSearch: true
            onCanceled: () => {
                root.showLanguageSelector = false;
            }
            onSelected: result => {
                root.showLanguageSelector = false;
                if (!result || result.length === 0)
                    return; // No selection made

                if (root.languageSelectorTarget) {
                    root.targetLanguage = result;
                    Config.options.language.translator.targetLanguage = result; // Save to config
                } else {
                    root.sourceLanguage = result;
                    Config.options.language.translator.sourceLanguage = result; // Save to config
                }

                translateTimer.restart(); // Restart translation after language change
            }
        }
    }
}
