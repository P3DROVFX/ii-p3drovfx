import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.sidebarLeft.translator
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Item {
    id: root

    property real padding: 4
    property var inputField: inputCanvas.inputTextArea
    property string translatedText: ""
    property string detectedSource: ""

    readonly property string targetLanguage: Config.options.language.translator.targetLanguage
    readonly property string sourceLanguage: Config.options.language.translator.sourceLanguage

    readonly property var autoEntry: ({
        code: "auto",
        label: Translation.tr("Automatic")
    })
    readonly property var catalogEntries: [root.autoEntry].concat(LanguageCatalog.entries.map(entry => ({
        code: entry.code,
        label: entry.name
    })))
    readonly property var sourceEntries: root.useDeepL ? deeplSourceLanguages.entries : root.catalogEntries
    readonly property var targetEntries: root.useDeepL ? deeplTargetLanguages.entries : root.catalogEntries

    onSourceEntriesChanged: root.resolveLanguage(false)
    onTargetEntriesChanged: root.resolveLanguage(true)

    function labelFor(entries: var, code: string): string {
        const match = entries.find(entry => entry.code === code);
        return match ? match.label : LanguageCatalog.nameFor(code);
    }

    function setLanguage(isTarget: bool, code: string) {
        const key = isTarget ? "targetLanguage" : "sourceLanguage";
        if (Config.options.language.translator[key] === code)
            return;
        Config.options.language.translator[key] = code;
        translateTimer.restart();
    }

    function normalizeInto(entries: var, code: string): string {
        if (code === "auto" || entries.some(entry => entry.code === code))
            return code;
        const base = code.split("-")[0];
        const match = entries.find(entry => entry.code === base) ?? entries.find(entry => entry.code.startsWith(base + "-"));
        return match ? match.code : "auto";
    }

    function swapLanguages() {
        const detected = root.detectedSource.length > 0 ? LanguageCatalog.codeFor(root.detectedSource) : "auto";
        const source = root.sourceLanguage !== "auto" ? root.sourceLanguage : detected;
        const target = root.targetLanguage;
        const translated = root.translatedText;
        root.setLanguage(true, root.normalizeInto(root.targetEntries, source));
        root.setLanguage(false, root.normalizeInto(root.sourceEntries, target));
        if (translated.length > 0)
            root.inputField.text = translated;
    }

    function resolveLanguage(isTarget: bool) {
        const entries = isTarget ? root.targetEntries : root.sourceEntries;
        if (entries.length <= 1)
            return;
        const code = LanguageCatalog.codeFor(isTarget ? root.targetLanguage : root.sourceLanguage);
        root.setLanguage(isTarget, root.normalizeInto(entries, code));
    }

    readonly property var providers: [
        {
            code: "deepl",
            label: "DeepL"
        },
        {
            code: "auto",
            label: Translation.tr("Automatic")
        },
        {
            code: "google",
            label: "Google"
        },
        {
            code: "bing",
            label: "Bing"
        }
    ]
    readonly property string provider: Config.options.sidebar.translator.useDeepL ? "deepl" : Config.options.language.translator.engine

    function setProvider(code: string) {
        Config.options.sidebar.translator.useDeepL = code === "deepl";
        if (code !== "deepl")
            Config.options.language.translator.engine = code;
        translateTimer.restart();
    }

    readonly property string deeplApiKey: KeyringStorage.keyringData?.apiKeys?.deepl ?? ""
    readonly property bool useDeepL: Config.options.sidebar.translator.useDeepL && deeplApiKey.length > 0
    readonly property bool deeplMissingKey: Config.options.sidebar.translator.useDeepL && deeplApiKey.length === 0

    Component.onCompleted: {
        if (Config.options.sidebar.translator.useDeepL && !KeyringStorage.loaded)
            KeyringStorage.fetchKeyringData();
        reloadLanguages();
    }

    onUseDeepLChanged: reloadLanguages()
    onDeeplApiKeyChanged: reloadLanguages()

    function reloadLanguages() {
        LanguageCatalog.load();
        if (!Config.options.sidebar.translator.useDeepL || root.deeplApiKey.length === 0)
            return;
        deeplSourceLanguages.start(root.deeplApiKey);
        deeplTargetLanguages.start(root.deeplApiKey);
    }

    property string selectorMode: ""
    readonly property bool selectorIsProvider: root.selectorMode === "provider"
    readonly property bool selectorIsTarget: root.selectorMode === "target"
    readonly property var selectorEntries: root.selectorIsProvider ? root.providers : (root.selectorIsTarget ? root.targetEntries : root.sourceEntries)
    readonly property string selectorCurrent: root.selectorIsProvider ? root.provider : (root.selectorIsTarget ? root.targetLanguage : root.sourceLanguage)

    function applySelection(code: string) {
        if (root.selectorIsProvider)
            root.setProvider(code);
        else
            root.setLanguage(root.selectorIsTarget, code);
    }

    onFocusChanged: {
        if (root.focus)
            root.inputField?.forceActiveFocus();
    }

    Timer {
        id: translateTimer
        interval: Config.options.sidebar.translator.delay
        repeat: false
        onTriggered: () => {
            if (root.inputField.text.trim().length === 0) {
                root.translatedText = "";
                root.detectedSource = "";
                return;
            }
            if (root.useDeepL)
                deeplTranslateProc.start();
            else
                translateProc.start();
        }
    }

    Process {
        id: translateProc
        command: ["bash", "-c", `trans -brief -no-bidi -no-ansi`
            + ` -engine '${StringUtils.shellSingleQuoteEscape(Config.options.language.translator.engine)}'`
            + ` -source '${StringUtils.shellSingleQuoteEscape(root.sourceLanguage)}'`
            + ` -target '${StringUtils.shellSingleQuoteEscape(root.targetLanguage)}'`
            + ` '${StringUtils.shellSingleQuoteEscape(root.inputField.text.trim())}'`]
        property string buffer: ""
        property string errorBuffer: ""

        function start() {
            translateProc.running = false;
            translateProc.buffer = "";
            translateProc.errorBuffer = "";
            translateProc.running = true;
        }

        stdout: SplitParser {
            onRead: data => {
                translateProc.buffer += data + "\n";
            }
        }
        stderr: SplitParser {
            onRead: data => {
                translateProc.errorBuffer += data + "\n";
            }
        }
        onExited: (exitCode, exitStatus) => {
            const translated = translateProc.buffer.trim();
            root.translatedText = translated.length > 0 ? translated : translateProc.errorBuffer.trim();
            root.detectedSource = "";
        }
    }

    Process {
        id: deeplTranslateProc
        property string buffer: ""

        function start() {
            deeplTranslateProc.running = false;
            deeplTranslateProc.buffer = "";
            deeplTranslateProc.running = true;
        }

        command: {
            const text = JSON.stringify(root.inputField.text.trim());
            const targetLang = root.targetLanguage === "auto" ? "EN" : root.targetLanguage.toUpperCase();
            let body = `{"text":[${text}],"target_lang":"${targetLang}"`;
            if (root.sourceLanguage !== "auto")
                body += `,"source_lang":"${root.sourceLanguage.toUpperCase()}"`;
            body += "}";
            return ["curl", "-s", "-X", "POST", "https://api-free.deepl.com/v2/translate",
                "-H", `Authorization: DeepL-Auth-Key ${root.deeplApiKey}`,
                "-H", "Content-Type: application/json",
                "-d", body];
        }
        stdout: SplitParser {
            onRead: data => {
                deeplTranslateProc.buffer += data + "\n";
            }
        }
        onExited: (exitCode, exitStatus) => {
            try {
                const resp = JSON.parse(deeplTranslateProc.buffer);
                root.translatedText = resp.translations.map(t => t.text).join("\n");
                root.detectedSource = resp.translations[0].detected_source_language ?? "";
            } catch (e) {
                root.translatedText = deeplTranslateProc.buffer.trim();
            }
        }
    }

    component DeeplLanguageFetch: Process {
        id: fetcher
        property string listType
        property string apiKey
        property var fallbackEntry
        property var entries: []
        property string buffer: ""
        command: ["curl", "-sg", `https://api-free.deepl.com/v2/languages?type=${fetcher.listType}`,
            "-H", `Authorization: DeepL-Auth-Key ${fetcher.apiKey}`]

        function start(key: string) {
            fetcher.apiKey = key;
            fetcher.buffer = "";
            fetcher.running = true;
        }

        stdout: SplitParser {
            onRead: data => {
                fetcher.buffer += data;
            }
        }
        onExited: (exitCode, exitStatus) => {
            try {
                const languages = JSON.parse(fetcher.buffer).map(language => {
                    const code = LanguageCatalog.codeFor(language.language.toLowerCase());
                    const name = LanguageCatalog.nameFor(code);
                    return {
                        code: code,
                        label: name === code ? language.name : name
                    };
                }).sort((a, b) => a.label.localeCompare(b.label));
                fetcher.entries = [fetcher.fallbackEntry].concat(languages);
            } catch (e) {
                fetcher.entries = [fetcher.fallbackEntry];
            }
            fetcher.buffer = "";
        }
    }

    DeeplLanguageFetch {
        id: deeplSourceLanguages
        listType: "source"
        fallbackEntry: root.autoEntry
    }

    DeeplLanguageFetch {
        id: deeplTargetLanguages
        listType: "target"
        fallbackEntry: root.autoEntry
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: root.padding
        }

        StyledFlickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: contentColumn.implicitHeight

            ColumnLayout {
                id: contentColumn
                width: parent.width

                StyledText {
                    Layout.fillWidth: true
                    visible: root.deeplMissingKey
                    text: Translation.tr("DeepL enabled but no API key set. Add it in Settings > Interface.")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colError
                    wrapMode: Text.Wrap
                    horizontalAlignment: Text.AlignHCenter
                    topPadding: 4
                    bottomPadding: 4
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    DropdownButton {
                        id: targetLanguageButton
                        displayText: root.labelFor(root.targetEntries, root.targetLanguage)
                        onClicked: {
                            root.selectorMode = "target";
                        }
                    }

                    Item { Layout.fillWidth: true }

                    GroupButton {
                        id: swapButton
                        baseWidth: height
                        buttonRadius: Appearance.rounding.small
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            iconSize: Appearance.font.pixelSize.larger
                            text: "swap_vert"
                            color: Appearance.colors.colOnLayer1
                        }
                        onClicked: {
                            root.swapLanguages();
                        }
                    }

                    DropdownButton {
                        id: providerButton
                        iconName: "translate"
                        displayText: root.labelFor(root.providers, root.provider)
                        onClicked: {
                            root.selectorMode = "provider";
                        }
                    }
                }

                TextCanvas {
                    id: outputCanvas
                    isInput: false
                    placeholderText: Translation.tr("Translation goes here...")
                    property bool hasTranslation: (root.translatedText.trim().length > 0)
                    text: hasTranslation ? root.translatedText : ""
                    GroupButton {
                        id: copyButton
                        baseWidth: height
                        buttonRadius: Appearance.rounding.small
                        enabled: outputCanvas.displayedText.trim().length > 0
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            iconSize: Appearance.font.pixelSize.larger
                            text: "content_copy"
                            color: copyButton.enabled ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
                        }
                        onClicked: {
                            Quickshell.clipboardText = outputCanvas.displayedText
                        }
                    }
                    GroupButton {
                        id: searchButton
                        baseWidth: height
                        buttonRadius: Appearance.rounding.small
                        enabled: outputCanvas.displayedText.trim().length > 0
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            iconSize: Appearance.font.pixelSize.larger
                            text: "travel_explore"
                            color: searchButton.enabled ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
                        }
                        onClicked: {
                            let url = Config.options.search.engineBaseUrl + outputCanvas.displayedText;
                            for (let site of Config.options.search.excludedSites) {
                                url += ` -site:${site}`;
                            }
                            Qt.openUrlExternally(url);
                        }
                    }
                }

            }
        }

        DropdownButton {
            id: sourceLanguageButton
            displayText: root.labelFor(root.sourceEntries, root.sourceLanguage)
            onClicked: {
                root.selectorMode = "source";
            }
        }

        TextCanvas {
            id: inputCanvas
            isInput: true
            placeholderText: Translation.tr("Enter text to translate...")
            onInputTextChanged: {
                translateTimer.restart();
            }
            GroupButton {
                id: pasteButton
                baseWidth: height
                buttonRadius: Appearance.rounding.small
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    iconSize: Appearance.font.pixelSize.larger
                    text: "content_paste"
                    color: deleteButton.enabled ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
                }
                onClicked: {
                    root.inputField.text = Quickshell.clipboardText
                }
            }
            GroupButton {
                id: deleteButton
                baseWidth: height
                buttonRadius: Appearance.rounding.small
                enabled: inputCanvas.displayedText.length > 0
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    iconSize: Appearance.font.pixelSize.larger
                    text: "close"
                    color: deleteButton.enabled ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
                }
                onClicked: {
                    root.inputField.text = ""
                }
            }
        }
    }

    Loader {
        anchors.fill: parent
        active: root.selectorMode.length > 0
        visible: root.selectorMode.length > 0
        z: 9999
        sourceComponent: SelectionDialog {
            id: selectorDialog
            titleText: root.selectorIsProvider ? Translation.tr("Select Provider") : Translation.tr("Select Language")
            searchable: !root.selectorIsProvider
            searchPlaceholder: Translation.tr("Search languages")
            items: root.selectorEntries.map(entry => entry.code)
            labelFor: code => root.labelFor(root.selectorEntries, code)
            defaultChoice: root.selectorCurrent
            onCanceled: () => {
                root.selectorMode = "";
            }
            onSelected: (result) => {
                if (result && result.length > 0)
                    root.applySelection(result);
                root.selectorMode = "";
            }
        }
    }
}
