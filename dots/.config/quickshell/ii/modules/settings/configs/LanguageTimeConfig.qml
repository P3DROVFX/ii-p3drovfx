import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.settings.configs.widgets
import qs.modules.settings.configs.language

// The `contentY` alias lets settings.qml search-scroll still work.
Item {
    id: root

    property alias contentY: page.contentY
    // Active sub-page URL ("" = none)
    property alias activeSubPage: subPageOverlay.activeSubPage

    function openSubPage(url) {
        root.activeSubPage = Qt.resolvedUrl(url);
    }

    property list<string> languages: ["auto"]
    property list<var> languagesModel: [{ "displayName": "auto", "value": "auto" }]
    property bool languageLoadRequested: false
    property int deferredLoadStage: 0

    function loadLanguages() {
        if (root.languageLoadRequested || getLanguagesProc.running)
            return;

        root.languageLoadRequested = true;
        getLanguagesProc.bufferList = [];
        getLanguagesProc.running = true;
    }

    // Keep external-process startup and the live previews out of the async
    // page-incubation critical path. Updating a ComboBox model while its page
    // is still being created is a rare but reproducible source of crashes.
    Timer {
        id: languageLoadTimer
        interval: 0
        running: true
        onTriggered: root.loadLanguages()
    }

    Timer {
        id: previewLoadTimer
        interval: 0
        running: true
        onTriggered: root.deferredLoadStage = 1
    }

    Timer {
        id: weekPickerLoadTimer
        interval: 0
        onTriggered: root.deferredLoadStage = 2
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

    ContentPage {
        id: page

        anchors.fill: parent
        forceWidth: false
        opacity: subPageOverlay.slideProgress
        visible: opacity > 0

    LanguagePane {
        Layout.fillWidth: true
    }

    AiTranslationPane {
        Layout.fillWidth: true
    }

    ContentSection {
        Layout.topMargin: 12
        icon: "g_translate"
        title: Translation.tr("Translator")

        ContentSubsection {
            title: Translation.tr("Translator defaults")
            icon: "g_translate"
            tooltip: Translation.tr("Select the default source and target language for both the Search Launcher and the Sidebar Translator panels.")
            Layout.fillWidth: true

            TranslatorDefaultsPicker {
                Layout.fillWidth: true
                languageModel: root.languagesModel
            }
        }
    }

    ContentSection {
        Layout.topMargin: 12
        icon: "nest_clock_farsight_analog"
        title: Translation.tr("Time & Date Formats")

        ProgressiveSectionLoader {
            id: timeDatePreviewLoader
            source: Qt.resolvedUrl("widgets/TimeDatePreview.qml")
            active: root.deferredLoadStage >= 1
            asynchronous: true
            estimatedHeight: 342
            prioritizeOnViewport: true
            Layout.fillWidth: true
            Layout.bottomMargin: 16
            onLoaded: weekPickerLoadTimer.start()
        }

        ConfigRow {
            uniform: true

        ConfigSwitch {
            buttonIcon: "pace"
            text: Translation.tr("Second precision")
            checked: Config.options.time.secondPrecision
            onCheckedChanged: {
                Config.options.time.secondPrecision = checked;
            }

            StyledToolTip {
                text: Translation.tr("Enable if you want clocks to show seconds accurately")
            }

        }

        ConfigSwitch {
            buttonIcon: "avg_pace"
            text: Translation.tr("Show seconds on a clock")
            checked: Config.options.bar.clock.showSeconds
            onCheckedChanged: {
                Config.options.bar.clock.showSeconds = checked;
            }

            StyledToolTip {
                text: Translation.tr("Enable if you want bar clock to show seconds")
            }

        }
        }

        ContentSubsection {
            title: Translation.tr("First day of week")
            icon: "today"
            tooltip: Translation.tr("Choose how calendars arrange the seven-day week")
            Layout.fillWidth: true

            ProgressiveSectionLoader {
                source: Qt.resolvedUrl("widgets/WeekStartPicker.qml")
                active: root.deferredLoadStage >= 2
                asynchronous: true
                estimatedHeight: 306
                prioritizeOnViewport: true
                Layout.fillWidth: true
            }
        }

        ContentSubsection {
            title: Translation.tr("Clock Format")
            icon: "schedule"
            tooltip: Translation.tr("Changes the clock format globally")
            Layout.fillWidth: true

            ConfigSelectionArray {
                currentValue: Config.options.time.format
                onSelected: (newValue) => {
                    DateUtils.syncHyprlockTimeFormat(newValue);
                    Config.options.time.format = newValue;
                }
                options: [{
                    "displayName": Translation.tr("24h"),
                    "value": "hh:mm"
                }, {
                    "displayName": Translation.tr("12h am/pm"),
                    "value": "h:mm ap"
                }, {
                    "displayName": Translation.tr("12h AM/PM"),
                    "value": "h:mm AP"
                }]
            }

        }

        ContentSubsection {
            title: Translation.tr("Date Format")
            icon: "date_range"
            tooltip: Translation.tr("Changes the date format in the bar")
            Layout.fillWidth: true

            ConfigSelectionArray {
                currentValue: Config.options.time.dateFormat
                onSelected: (newValue) => {
                    Config.options.time.dateFormat = newValue;
                }
                options: [{
                    "displayName": Translation.tr("Date First dd/MM"),
                    "value": "dd/MM, ddd"
                }, {
                    "displayName": Translation.tr("Month First MM/dd"),
                    "value": "MM/dd, ddd"
                }]
            }

        }

        // Own ColumnLayout so the card's auto first/last rounding sees no unrelated siblings
        ColumnLayout {
            Layout.fillWidth: true
            Layout.topMargin: 8
            spacing: 4

            ServiceCard {
                cardIcon: "edit_calendar"
                cardHue: 280
                cardShape: "Cookie9Sided"
                title: Translation.tr("Custom format strings")
                description: Translation.tr("Fine-tune how dates and times are shown across the shell")
                onOpenCard: root.openSubPage("widgets/TimeDateFormatsConfig.qml")
            }
        }

    }

    WorldClocksPane {
        Layout.topMargin: 12
        Layout.fillWidth: true
    }

    ContentSection {
        Layout.topMargin: 12
        icon: "celebration"
        title: Translation.tr("Holidays")

        ConfigRow {
            uniform: true

        ConfigSwitch {
            buttonIcon: "flag"
            text: Translation.tr("Show public holidays")
            checked: Config.options.calendar.holidays.enable
            onCheckedChanged: Config.options.calendar.holidays.enable = checked

            StyledToolTip {
                text: Translation.tr("Public holidays are fetched once per year from the Nager.Date open API and kept on disk")
            }
        }

        ConfigSwitch {
            buttonIcon: "calendar_month"
            text: Translation.tr("Show holidays in month view")
            checked: Config.options.calendar.holidays.showInMonthView
            enabled: Config.options.calendar.holidays.enable
            onCheckedChanged: Config.options.calendar.holidays.showInMonthView = checked

            StyledToolTip {
                text: Translation.tr("Mark holidays on the calendar's month grid")
            }
        }
        }

        ConfigTextField {
            icon: "public"
            text: Translation.tr("Country code")
            placeholderText: Translation.tr("auto")
            tooltip: Translation.tr("An ISO 3166-1 alpha-2 code such as BR, US or GB.\n\"auto\" derives it from your system locale.")
            inputText: Config.options.calendar.holidays.countryCode
            enabled: Config.options.calendar.holidays.enable
            textField.onEditingFinished: {
                const value = textField.text.trim();
                Config.options.calendar.holidays.countryCode = value.length > 0 ? value : "auto";
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: 4
            Layout.topMargin: 4
            opacity: Config.options.calendar.holidays.enable ? 1 : 0.4
            text: Holidays.countryCode.length > 0
                ? Translation.tr("Showing holidays for %1").arg(Holidays.countryCode)
                : Translation.tr("No country could be resolved — enter a two-letter code above")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            wrapMode: Text.Wrap
        }
    }

    }

    // Sub-page overlay (slides in from the right)
    ConfigSubPageHost {
        id: subPageOverlay

        anchors.fill: parent
        z: 10
    }

}
