import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

ContentPage {
    id: root

    forceWidth: false

    property var languages: ["auto"]
    property var languagesModel: [{ "displayName": "auto", "value": "auto" }]

    Process {
        id: getLanguagesProc
        command: ["trans", "-list-languages", "-no-bidi"]
        property var bufferList: ["auto"]
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
                
                let modelList = [];
                for (let i = 0; i < langs.length; i++) {
                    modelList.push({
                        "displayName": langs[i],
                        "value": langs[i]
                    });
                }
                root.languagesModel = modelList;
                getLanguagesProc.bufferList = [];
            }
        }
    
        Process {
            id: translationProc
            property string locale: ""
            command: [Directories.aiTranslationScriptPath, translationProc.locale]
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

    ContentSection {
        icon: "nest_clock_farsight_analog"
        title: Translation.tr("Time & Date Formats")

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

        ConfigSwitch {
            buttonIcon: "today"
            text: Translation.tr("Start week on Monday")
            checked: Config.options.time.firstDayOfWeek === 0
            onCheckedChanged: {
                Config.options.time.firstDayOfWeek = checked ? 0 : 6;
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
                    if (newValue === "hh:mm")
                        Quickshell.execDetached(["bash", "-c", `sed -i 's/\\TIME12\\b/TIME/' '${FileUtils.trimFileProtocol(Directories.config)}/hypr/hyprlock.conf'`]);
                    else
                        Quickshell.execDetached(["bash", "-c", `sed -i 's/\\TIME\\b/TIME12/' '${FileUtils.trimFileProtocol(Directories.config)}/hypr/hyprlock.conf'`]);
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


}
