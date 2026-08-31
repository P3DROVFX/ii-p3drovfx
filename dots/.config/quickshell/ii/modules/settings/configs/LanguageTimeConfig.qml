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

    Process {
        id: translationProc
        property string locale: ""
        command: [Directories.aiTranslationScriptPath, translationProc.locale]
    }

    ContentPage {
        id: page

        anchors.fill: parent
        forceWidth: false
        opacity: subPageOverlay.slideProgress
        visible: opacity > 0

    ContentSection {
        icon: "language"
        title: Translation.tr("Language & Translation")
        Layout.bottomMargin: 12

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
                enabled: !translationProc.running || (translationProc.locale !== localeInput.text.trim())

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
                    translationProc.locale = localeInput.text.trim();
                    translationProc.running = false;
                    translationProc.running = true;
                }
            }
        }

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

        ContentSubsection {
            id: worldClocksSubsection

            function addWorldClock() {
                let list = Config.options.time.worldClocks ? Array.from(Config.options.time.worldClocks) : [];
                list.push({
                    "name": "",
                    "tz": ""
                });
                Config.options.time.worldClocks = list;
            }

            function removeWorldClock(index) {
                let list = Config.options.time.worldClocks ? Array.from(Config.options.time.worldClocks) : [];
                if (index >= 0 && index < list.length) {
                    list.splice(index, 1);
                    Config.options.time.worldClocks = list;
                }
            }

            function updateWorldClock(index, key, value) {
                let current = Config.options.time.worldClocks || [];
                if (index < 0 || index >= current.length)
                    return ;

                let list = [];
                for (let i = 0; i < current.length; i++) {
                    let item = current[i] || {
                        "name": "",
                        "tz": ""
                    };
                    if (i === index) {
                        let newItem = {
                            "name": item.name || "",
                            "tz": item.tz || ""
                        };
                        newItem[key] = value;
                        list.push(newItem);
                    } else {
                        list.push(item);
                    }
                }
                Config.options.time.worldClocks = list;
            }

            title: Translation.tr("World Clocks list")
            icon: "public"
            tooltip: Translation.tr("Manage timezones displayed in the clock widget popup")
            Layout.fillWidth: true

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8

                Repeater {
                    model: Config.options.time.worldClocks

                    ColumnLayout {
                        id: clockRow

                        required property var modelData
                        required property int index
                        property bool searchFailed: false
                        property bool isSearching: false

                        Layout.fillWidth: true
                        spacing: 2

                        Process {
                            id: tzSearchProc

                            property string buffer: ""

                            command: ["bash", "-c", "QUERY=$(echo '" + (clockRow.modelData.name || "").replace(/'/g, "'\\''").replace(/ /g, "_") + "' | iconv -f UTF-8 -t ASCII//TRANSLIT | sed 's/[^a-zA-Z0-9_]//g'); [ -n \"$QUERY\" ] && timedatectl list-timezones | grep -i \"$QUERY\" | head -n 1 || true"]
                            onStarted: {
                                buffer = "";
                                clockRow.searchFailed = false;
                                clockRow.isSearching = true;
                            }
                            onExited: {
                                clockRow.isSearching = false;
                                let res = buffer.trim();
                                if (res) {
                                    worldClocksSubsection.updateWorldClock(clockRow.index, "tz", res);
                                    let prettyName = res.split("/").pop().replace(/_/g, " ");
                                    if ((clockRow.modelData.name || "") === "" || clockRow.modelData.name.toLowerCase() === prettyName.toLowerCase())
                                        worldClocksSubsection.updateWorldClock(clockRow.index, "name", prettyName);

                                } else {
                                    clockRow.searchFailed = true;
                                }
                            }

                            stdout: SplitParser {
                                onRead: (data) => {
                                    return tzSearchProc.buffer += data;
                                }
                            }

                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            MaterialTextField {
                                id: cityField

                                Layout.fillWidth: true
                                Layout.preferredHeight: 40
                                Layout.minimumWidth: 80
                                placeholderText: Translation.tr("City Name (e.g. Tokyo)")
                                text: clockRow.modelData.name || ""
                                wrapMode: TextEdit.NoWrap
                                onEditingFinished: {
                                    if (text !== (clockRow.modelData.name || "")) {
                                        worldClocksSubsection.updateWorldClock(clockRow.index, "name", text);
                                        if ((clockRow.modelData.tz || "") === "")
                                            tzSearchProc.running = true;

                                    }
                                }
                            }

                            MaterialTextField {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 40
                                Layout.minimumWidth: 80
                                visible: clockRow.searchFailed || clockRow.modelData.name === "" || clockRow.isSearching
                                placeholderText: Translation.tr("Timezone ID (e.g. Asia/Tokyo)")
                                text: clockRow.modelData.tz || ""
                                wrapMode: TextEdit.NoWrap
                                onEditingFinished: {
                                    if (text !== (clockRow.modelData.tz || "")) {
                                        worldClocksSubsection.updateWorldClock(clockRow.index, "tz", text);
                                        clockRow.searchFailed = false;
                                    }
                                }
                            }

                            Rectangle {
                                visible: (clockRow.modelData.tz || "") !== "" && !clockRow.searchFailed && !clockRow.isSearching && clockRow.modelData.name !== ""
                                Layout.preferredHeight: 40
                                Layout.preferredWidth: Math.max(tzChipText.implicitWidth + 24, 60)
                                color: Appearance.colors.colLayer3
                                radius: Appearance.rounding.small
                                border.width: 1
                                border.color: Appearance.colors.colLayer0Border

                                StyledText {
                                    id: tzChipText

                                    anchors.centerIn: parent
                                    text: clockRow.modelData.tz || ""
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colOnLayer3
                                    elide: Text.ElideRight
                                    width: parent.width - 24
                                }

                            }

                            MaterialLoadingIndicator {
                                loading: true
                                visible: clockRow.isSearching
                                Layout.preferredHeight: 24
                                Layout.preferredWidth: 24
                            }

                            IconToolbarButton {
                                text: "search"
                                Layout.preferredHeight: 40
                                Layout.preferredWidth: 40
                                enabled: (clockRow.modelData.tz || "") === "" && !clockRow.isSearching
                                onClicked: tzSearchProc.running = true

                                StyledToolTip {
                                    text: Translation.tr("Auto-detect Timezone")
                                }

                            }

                            IconToolbarButton {
                                text: "delete"
                                Layout.preferredHeight: 40
                                Layout.preferredWidth: 40
                                onClicked: {
                                    worldClocksSubsection.removeWorldClock(clockRow.index);
                                }
                            }

                        }

                        StyledText {
                            Layout.leftMargin: 8
                            Layout.bottomMargin: 4
                            visible: clockRow.searchFailed
                            text: Translation.tr("Timezone not found for '%1'. Try a different name or enter the ID manually.").arg(clockRow.modelData.name || "")
                            color: Appearance.colors.colError
                            font.pixelSize: Appearance.font.pixelSize.smaller
                        }

                    }

                }

                RippleButtonWithIcon {
                    Layout.fillWidth: true
                    materialIcon: "add"
                    mainText: Translation.tr("Add World Clock")
                    onClicked: {
                        worldClocksSubsection.addWorldClock();
                    }
                }

            }

        }

    }

    ContentSection {
        icon: "celebration"
        title: Translation.tr("Holidays")

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
