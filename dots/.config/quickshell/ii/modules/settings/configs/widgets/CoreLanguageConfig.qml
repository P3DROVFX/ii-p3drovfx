import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: false
    signal goBack()

    RowLayout {
        spacing: 12

        RippleButton {
            implicitWidth: implicitHeight
            implicitHeight: 40
            topLeftRadius: Appearance.rounding.full
            topRightRadius: Appearance.rounding.full
            bottomLeftRadius: Appearance.rounding.full
            bottomRightRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colRipple: Appearance.colors.colSecondaryContainerActive

            MaterialSymbol {
                anchors.centerIn: parent
                text: "arrow_back"
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnSecondaryContainer
            }

            onClicked: root.goBack()
        }

        StyledText {
            text: Translation.tr("Language & Translation")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    // Translator languages model
    property list<string> languages: ["auto"]
    property list<var> languagesModel: [{ "displayName": "auto", "value": "auto" }]
    property bool languageLoadRequested: false

    function loadLanguages() {
        if (root.languageLoadRequested || getLanguagesProc.running)
            return;

        root.languageLoadRequested = true;
        getLanguagesProc.bufferList = [];
        getLanguagesProc.running = true;
    }

    // The page is loaded through an async sub-page Loader. Wait until the
    // object tree is complete before changing the ComboBox model.
    Timer {
        id: languageLoadTimer
        interval: 0
        running: true
        onTriggered: root.loadLanguages()
    }

    Process {
        id: getLanguagesProc
        command: ["trans", "-list-languages", "-no-bidi"]
        property list<string> bufferList: []
        running: false
        stdout: SplitParser {
            onRead: data => {
                const lines = String(data).split(/\r?\n/);
                for (const line of lines) {
                    const language = line.trim();
                    if (language.length > 0)
                        getLanguagesProc.bufferList.push(language);
                }
            }
        }
        onExited: exitCode => {
            if (exitCode !== 0)
                return;

            const languages = Array.from(new Set(getLanguagesProc.bufferList))
                .filter(language => language !== "auto")
                .sort((a, b) => a.localeCompare(b));
            languages.unshift("auto");

            root.languages = languages;
            root.languagesModel = languages.map(language => ({
                "displayName": language,
                "value": language
            }));
            getLanguagesProc.bufferList = [];
        }
    }

    ContentSection {
        icon: "neurology"
        title: Translation.tr("AI Assistant")

        HelperLinkBox {
            Layout.fillWidth: true
            title: Translation.tr("Google AI Studio")
            text: Translation.tr("Get your Gemini API Key here for free.")
            isFirst: true

            RippleButtonWithIcon {
                mainText: Translation.tr("Open Website")
                materialIcon: "open_in_new"
                Layout.topMargin: 4
                Layout.bottomMargin: 4
                colBackground: Appearance.colors.colLayer0
                colBackgroundHover: Appearance.colors.colLayer0Hover
                colRipple: Appearance.colors.colLayer0Active
                downAction: () => {
                    Qt.openUrlExternally("https://aistudio.google.com/app/apikey")
                }
            }
        }

        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("System prompt")
            text: Config.options.ai.systemPrompt
            wrapMode: TextEdit.Wrap
            onTextChanged: {
                Qt.callLater(() => {
                    Config.options.ai.systemPrompt = text;
                });
            }
        }
    }

    ContentSection {
        icon: "language"
        title: Translation.tr("Language & Translation")

        ContentSubsection {
            title: Translation.tr("Interface Language")
            icon: "translate"
            tooltip: Translation.tr("Select the language for the user interface.\n\"Auto\" will use your system's locale.")
            Layout.fillWidth: true

            StyledComboBox {
                id: languageSelector
                buttonIcon: "language"
                textRole: "displayName"
                model: [
                    {
                        displayName: Translation.tr("Auto (System)"),
                        value: "auto"
                    },
                    ...Translation.allAvailableLanguages.map(lang => {
                        return {
                            displayName: lang,
                            value: lang
                        };
                    })
                ]
                currentIndex: {
                    const index = model.findIndex(item => item.value === Config.options.language.ui);
                    return index !== -1 ? index : 0;
                }
                onActivated: index => {
                    Config.options.language.ui = model[index].value;
                }
            }
            
            MaterialTextField {
                id: localeInput
                Layout.fillWidth: true
                placeholderText: Translation.tr("Locale code for Gemini generation, e.g. fr_FR")
                text: Config.options.language.ui === "auto" ? Qt.locale().name : Config.options.language.ui
            }

            RippleButton {
                id: generateTranslationBtn
                Layout.fillWidth: true
                Layout.topMargin: 8
                implicitHeight: 48
                buttonRadius: Appearance.rounding.normal
                colBackground: Appearance.colors.colPrimaryContainer
                colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                colRipple: Appearance.colors.colPrimaryContainerActive
                enabled: !AiTranslation.running

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 12
                    MaterialSymbol {
                        text: "auto_awesome"
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colOnPrimaryContainer
                    }
                    StyledText {
                        text: generateTranslationBtn.enabled ? Translation.tr("Generate Translation with AI (Takes ~2 mins)") : Translation.tr("Generating... Do not close window")
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.bold: true
                        color: Appearance.colors.colOnPrimaryContainer
                    }
                }

                onClicked: {
                    AiTranslation.start(localeInput.text.trim(), Config.options.language.aiModel);
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Translator defaults")
            icon: "g_translate"
            tooltip: Translation.tr("Select the default source and target language for both the Search Launcher and the Sidebar Translator panels.")
            Layout.fillWidth: true

            ContentSubsectionLabel {
                text: Translation.tr("From")
            }
            StyledComboBox {
                id: defaultSourceLangSelector
                buttonIcon: "language"
                textRole: "displayName"
                model: root.languagesModel
                currentIndex: {
                    const index = model.findIndex(item => item.value === Config.options.language.translator.defaultSourceLanguage);
                    return index !== -1 ? index : 0;
                }
                onActivated: index => {
                    Config.options.language.translator.defaultSourceLanguage = model[index].value;
                }
            }

            ContentSubsectionLabel {
                text: Translation.tr("To")
            }
            StyledComboBox {
                id: defaultTargetLangSelector
                buttonIcon: "translate"
                textRole: "displayName"
                model: root.languagesModel
                currentIndex: {
                    const index = model.findIndex(item => item.value === Config.options.language.translator.defaultTargetLanguage);
                    return index !== -1 ? index : 0;
                }
                onActivated: index => {
                    Config.options.language.translator.defaultTargetLanguage = model[index].value;
                }
            }
        }
    }
}
