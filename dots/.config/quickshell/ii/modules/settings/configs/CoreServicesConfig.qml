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
    id: coreConfigRoot
    forceWidth: false

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 12

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
        icon: "volume_up"
        title: Translation.tr("Audio Controls")

        ConfigSwitch {
            buttonIcon: "hearing"
            text: Translation.tr("Earbang protection")
            checked: Config.options.audio.protection.enable
            onCheckedChanged: {
                Config.options.audio.protection.enable = checked;
            }
            StyledToolTip {
                text: Translation.tr("Prevents abrupt increments and restricts volume limit")
            }
        }

        ConfigSpinBox {
            enabled: Config.options.audio.protection.enable
            icon: "arrow_warm_up"
            text: Translation.tr("Max allowed volume increase")
            value: Config.options.audio.protection.maxAllowedIncrease
            from: 0
            to: 100
            stepSize: 2
            onValueChanged: {
                Config.options.audio.protection.maxAllowedIncrease = value;
            }
        }

        ConfigSpinBox {
            enabled: Config.options.audio.protection.enable
            icon: "vertical_align_top"
            text: Translation.tr("Volume limit")
            value: Config.options.audio.protection.maxAllowed
            from: 0
            to: 154
            stepSize: 2
            onValueChanged: {
                Config.options.audio.protection.maxAllowed = value;
            }
        }
    }

    ContentSection {
        icon: "battery_android_full"
        title: Translation.tr("Power & Battery Management")

        ConfigSpinBox {
            icon: "warning"
            text: Translation.tr("Low warning")
            value: Config.options.battery.low
            from: 0
            to: 100
            stepSize: 5
            onValueChanged: {
                Config.options.battery.low = value;
            }
        }

        ConfigSpinBox {
            icon: "dangerous"
            text: Translation.tr("Critical warning")
            value: Config.options.battery.critical
            from: 0
            to: 100
            stepSize: 5
            onValueChanged: {
                Config.options.battery.critical = value;
            }
        }

        ConfigSwitch {
            buttonIcon: "pause"
            text: Translation.tr("Automatic suspend")
            checked: Config.options.battery.automaticSuspend
            onCheckedChanged: {
                Config.options.battery.automaticSuspend = checked;
            }
            StyledToolTip {
                text: Translation.tr("Automatically suspends the system when battery is low")
            }
        }

        ConfigSpinBox {
            enabled: Config.options.battery.automaticSuspend
            icon: "mode_standby"
            text: Translation.tr("Suspend at (%)")
            value: Config.options.battery.suspend
            from: 0
            to: 100
            stepSize: 5
            onValueChanged: {
                Config.options.battery.suspend = value;
            }
        }

        ConfigSpinBox {
            icon: "charger"
            text: Translation.tr("Full battery warning")
            value: Config.options.battery.full
            from: 0
            to: 101
            stepSize: 5
            onValueChanged: {
                Config.options.battery.full = value;
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
                onSelected: newValue => {
                    if (newValue === "hh:mm") {
                        Quickshell.execDetached(["bash", "-c", `sed -i 's/\\TIME12\\b/TIME/' '${FileUtils.trimFileProtocol(Directories.config)}/hypr/hyprlock.conf'`]);
                    } else {
                        Quickshell.execDetached(["bash", "-c", `sed -i 's/\\TIME\\b/TIME12/' '${FileUtils.trimFileProtocol(Directories.config)}/hypr/hyprlock.conf'`]);
                    }

                    Config.options.time.format = newValue;
                }
                options: [
                    {
                        displayName: Translation.tr("24h"),
                        value: "hh:mm"
                    },
                    {
                        displayName: Translation.tr("12h am/pm"),
                        value: "h:mm ap"
                    },
                    {
                        displayName: Translation.tr("12h AM/PM"),
                        value: "h:mm AP"
                    },
                ]
            }
        }

        ContentSubsection {
            title: Translation.tr("Date Format")
            icon: "date_range"
            tooltip: Translation.tr("Changes the date format in the bar")
            Layout.fillWidth: true

            ConfigSelectionArray {
                currentValue: Config.options.time.dateFormat
                onSelected: newValue => {
                    Config.options.time.dateFormat = newValue;
                }
                options: [
                    {
                        displayName: Translation.tr("Date First dd/MM"),
                        value: "ddd dd/MM"
                    },
                    {
                        displayName: Translation.tr("Month First MM/dd"),
                        value: "ddd MM/dd"
                    }
                ]
            }
        }

        ContentSubsection {
            id: worldClocksSubsection
            title: Translation.tr("World Clocks list")
            icon: "public"
            tooltip: Translation.tr("Manage timezones displayed in the clock widget popup")
            Layout.fillWidth: true

            function addWorldClock() {
                let list = Config.options.time.worldClocks ? Array.from(Config.options.time.worldClocks) : [];
                list.push({ "name": "", "tz": "" });
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
                if (index < 0 || index >= current.length) return;
                
                let list = [];
                for (let i = 0; i < current.length; i++) {
                    let item = current[i] || { "name": "", "tz": "" };
                    if (i === index) {
                        let newItem = { "name": item.name || "", "tz": item.tz || "" };
                        newItem[key] = value;
                        list.push(newItem);
                    } else {
                        list.push(item);
                    }
                }
                Config.options.time.worldClocks = list;
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8

                Repeater {
                    model: Config.options.time.worldClocks

                    ColumnLayout {
                        id: clockRow
                        Layout.fillWidth: true
                        spacing: 2

                        required property var modelData
                        required property int index
                        property bool searchFailed: false
                        property bool isSearching: false

                        Process {
                            id: tzSearchProc
                            command: ["bash", "-c", "QUERY=$(echo '" + (clockRow.modelData.name || "").replace(/'/g, "'\\''").replace(/ /g, "_") + "' | iconv -f UTF-8 -t ASCII//TRANSLIT | sed 's/[^a-zA-Z0-9_]//g'); [ -n \"$QUERY\" ] && timedatectl list-timezones | grep -i \"$QUERY\" | head -n 1 || true"]
                            property string buffer: ""
                            stdout: SplitParser {
                                onRead: data => tzSearchProc.buffer += data
                            }
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
                                    if ((clockRow.modelData.name || "") === "" || clockRow.modelData.name.toLowerCase() === prettyName.toLowerCase()) {
                                        worldClocksSubsection.updateWorldClock(clockRow.index, "name", prettyName);
                                    }
                                } else {
                                    clockRow.searchFailed = true;
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
                                        if ((clockRow.modelData.tz || "") === "") {
                                            tzSearchProc.running = true;
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                visible: (clockRow.modelData.tz || "") !== "" && !clockRow.searchFailed
                                Layout.preferredHeight: 36
                                Layout.preferredWidth: Math.max(tzChipText.implicitWidth + 16, 60)
                                color: Appearance.colors.colSurfaceContainerHigh
                                radius: Appearance.rounding.full

                                StyledText {
                                    id: tzChipText
                                    anchors.centerIn: parent
                                    text: clockRow.modelData.tz || ""
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colOnSurfaceVariant
                                    elide: Text.ElideRight
                                    width: parent.width - 16
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
                                Layout.preferredHeight: 36
                                Layout.preferredWidth: 36
                                enabled: (clockRow.modelData.tz || "") === "" && !clockRow.isSearching
                                onClicked: tzSearchProc.running = true
                                StyledToolTip { text: Translation.tr("Auto-detect Timezone from City Name") }
                            }

                            IconToolbarButton {
                                text: "delete"
                                Layout.preferredHeight: 36
                                Layout.preferredWidth: 36
                                onClicked: {
                                    worldClocksSubsection.removeWorldClock(clockRow.index);
                                }
                            }
                        }

                        MaterialTextField {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 40
                            Layout.minimumWidth: 80
                            visible: clockRow.searchFailed
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
            
            MaterialTextArea {
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
                model: [
                    { displayName: Translation.tr("Auto (Detect)"), value: "auto" },
                    ...Translation.allAvailableLanguages.map(lang => ({ displayName: lang, value: lang }))
                ]
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
                model: Translation.allAvailableLanguages.map(lang => ({ displayName: lang, value: lang }))
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
        icon: "notifications_active"
        title: Translation.tr("Interactive Alerts")

        ConfigSwitch {
            buttonIcon: "battery_alert"
            text: Translation.tr("Battery sound toggle")
            checked: Config.options.sounds.battery
            onCheckedChanged: {
                Config.options.sounds.battery = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "av_timer"
            text: Translation.tr("Pomodoro sound toggle")
            checked: Config.options.sounds.pomodoro
            onCheckedChanged: {
                Config.options.sounds.pomodoro = checked;
            }
        }
    }

    ContentSection {
        icon: "album"
        title: Translation.tr("Media Integrations")

        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("Prioritized player (e.g. spotify)")
            text: Config.options.media.priorityPlayer
            wrapMode: TextEdit.NoWrap
            onTextChanged: {
                Config.options.media.priorityPlayer = text;
            }
        }

        ConfigSwitch {
            buttonIcon: "filter_list"
            text: Translation.tr("Filter duplicate players")
            checked: Config.options.media.filterDuplicatePlayers
            isLast: true
            onCheckedChanged: {
                Config.options.media.filterDuplicatePlayers = checked;
            }
            StyledToolTip {
                text: Translation.tr("Attempt to remove dupes (the aggregator playerctl one and browsers' native ones when there's plasma browser integration)")
            }
        }

        ContentSubsectionLabel { text: Translation.tr("Music Recognition") }

        ConfigSpinBox {
            icon: "timer_off"
            text: Translation.tr("Total duration timeout (s)")
            value: Config.options.musicRecognition.timeout
            from: 10
            to: 100
            stepSize: 2
            isFirst: true
            onValueChanged: {
                Config.options.musicRecognition.timeout = value;
            }
        }
        ConfigSpinBox {
            icon: "av_timer"
            text: Translation.tr("Polling interval (s)")
            value: Config.options.musicRecognition.interval
            from: 2
            to: 10
            stepSize: 1
            isLast: true
            onValueChanged: {
                Config.options.musicRecognition.interval = value;
            }
        }

        ContentSubsectionLabel { text: Translation.tr("Lyrics services") }

        ConfigSwitch {
            buttonIcon: "check"
            text: Translation.tr("Enable lyrics service")
            checked: Config.options.lyricsService.enable
            isFirst: true
            onCheckedChanged: {
                Config.options.lyricsService.enable = checked;
            }
        }

        ConfigSwitch {
            enabled: Config.options.lyricsService.enable
            buttonIcon: "mood"
            text: Translation.tr("Enable Genius lyrics service")
            checked: Config.options.lyricsService.enableGenius
            onCheckedChanged: {
                Config.options.lyricsService.enableGenius = checked;
            }
        }

        ConfigSwitch {
            enabled: Config.options.lyricsService.enable
            buttonIcon: "library_books"
            text: Translation.tr("Enable LrcLib lyrics service")
            isLast: true
            checked: Config.options.lyricsService.enableLrclib
            onCheckedChanged: {
                Config.options.lyricsService.enableLrclib = checked;
            }
        }
    }

    ContentSection {
        icon: "policy"
        title: Translation.tr("Work Safety & Policies")

        ContentSubsectionLabel { text: Translation.tr("Hiding Suspects") }

        WarningBox {
            Layout.fillWidth: true
            text: Translation.tr("Enabling strict policies will globally block media and NSFW content across all widgets.")
            isFirst: true
        }

        ConfigSwitch {
            buttonIcon: "assignment"
            text: Translation.tr("Hide clipboard images")
            checked: Config.options.workSafety.enable.clipboard
            onCheckedChanged: {
                Config.options.workSafety.enable.clipboard = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "wallpaper"
            text: Translation.tr("Hide suspect/anime wallpapers")
            checked: Config.options.workSafety.enable.wallpaper
            isLast: true
            onCheckedChanged: {
                Config.options.workSafety.enable.wallpaper = checked;
            }
        }

        ContentSubsectionLabel { text: Translation.tr("Policies settings") }

            ContentSubsection {
                title: Translation.tr("AI policy")
                icon: "smart_toy"
                Layout.fillWidth: true
                isFirst: true
                ConfigSelectionArray {
                    currentValue: Config.options.policies.ai
                    onSelected: newValue => {
                        Config.options.policies.ai = newValue;
                    }
                    options: [
                        { displayName: Translation.tr("No"), icon: "close", value: 0 },
                        { displayName: Translation.tr("Yes"), icon: "check", value: 1 },
                        { displayName: Translation.tr("Local"), icon: "sync_saved_locally", value: 2 }
                    ]
                }
            }

            ContentSubsection {
                title: Translation.tr("Weeb policy")
                icon: "face"
                Layout.fillWidth: true
                ConfigSelectionArray {
                    currentValue: Config.options.policies.weeb
                    onSelected: newValue => {
                        Config.options.policies.weeb = newValue;
                    }
                    options: [
                        { displayName: Translation.tr("No"), icon: "close", value: 0 },
                        { displayName: Translation.tr("Yes"), icon: "check", value: 1 },
                        { displayName: Translation.tr("Closet"), icon: "ev_shadow", value: 2 }
                    ]
                }
            }

            ContentSubsection {
                title: Translation.tr("Wallpaper browser policy")
                icon: "wallpaper"
                Layout.fillWidth: true
                ConfigSelectionArray {
                    currentValue: Config.options.policies.wallpapers
                    onSelected: newValue => {
                        Config.options.policies.wallpapers = newValue;
                    }
                    options: [
                        { displayName: Translation.tr("No"), icon: "close", value: 0 },
                        { displayName: Translation.tr("Yes"), icon: "check", value: 1 }
                    ]
                }
            }

            ContentSubsection {
                title: Translation.tr("Translator policy")
                icon: "translate"
                Layout.fillWidth: true
                ConfigSelectionArray {
                    currentValue: Config.options.policies.translator
                    onSelected: newValue => {
                        Config.options.policies.translator = newValue;
                    }
                    options: [
                        { displayName: Translation.tr("No"), icon: "close", value: 0 },
                        { displayName: Translation.tr("Yes"), icon: "check", value: 1 }
                    ]
                }
            }

            ContentSubsection {
                title: Translation.tr("Sidebar player policy")
                icon: "music_note"
                Layout.fillWidth: true
                ConfigSelectionArray {
                    currentValue: Config.options.policies.player
                    onSelected: newValue => {
                        Config.options.policies.player = newValue;
                    }
                    options: [
                        { displayName: Translation.tr("No"), icon: "close", value: 0 },
                        { displayName: Translation.tr("Yes"), icon: "check", value: 1 }
                    ]
                }
            }
    }

    ContentSection {
        icon: "speed"
        title: Translation.tr("Network & Performance Utilities")

        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("User agent string")
            text: Config.options.networking.userAgent
            wrapMode: TextEdit.Wrap
            onTextChanged: {
                Config.options.networking.userAgent = text;
            }
        }

        ConfigSpinBox {
            icon: "memory"
            text: Translation.tr("Resources polling interval (ms)")
            value: Config.options.resources.updateInterval
            from: 100
            to: 10000
            stepSize: 100
            onValueChanged: {
                Config.options.resources.updateInterval = value;
            }
        }
    }

    ContentSection {
        id: btImagesSection
        icon: "bluetooth"
        title: Translation.tr("Bluetooth Device Images")

        // Processing Logic
        property string pendingMac: ""
        readonly property string manageScript: Quickshell.shellPath("scripts/services/manage_device_image.sh")

        function getDeviceImages() {
            let images = (Config.options.apps && Config.options.bluetoothDeviceImages) ? Config.options.bluetoothDeviceImages : [];
            // Convert to real JS array if it isn't already
            return Array.from(images);
        }

        function getAvailableDevices() {
            let all = BluetoothStatus.friendlyDeviceList;
            let managed = getDeviceImages();
            let available = [];
            for (let i = 0; i < all.length; i++) {
                let isManaged = false;
                for (let j = 0; j < managed.length; j++) {
                    if (all[i].address === managed[j].mac) {
                        isManaged = true;
                        break;
                    }
                }
                if (!isManaged) {
                    available.push(all[i]);
                }
            }
            return available;
        }

        function getDeviceName(mac) {
            let all = BluetoothStatus.friendlyDeviceList;
            for (let i = 0; i < all.length; i++) {
                if (all[i].address === mac) {
                    return all[i].name || "Unknown Device";
                }
            }
            return "Unknown Device";
        }

        Process {
            id: pickerProc
            stdout: StdioCollector {
                onStreamFinished: {
                    let path = text.trim();
                    if (path.length > 0 && btImagesSection.pendingMac !== "") {
                        copyProc.exec([btImagesSection.manageScript, "copy", path, btImagesSection.pendingMac]);
                    }
                }
            }
        }

        Process {
            id: copyProc
            stdout: StdioCollector {
                onStreamFinished: {
                    let filename = text.trim();
                    if (filename.length > 0) {
                        let list = btImagesSection.getDeviceImages();
                        let idx = -1;
                        for (let i = 0; i < list.length; i++) {
                            if (list[i].mac === btImagesSection.pendingMac) {
                                idx = i;
                                break;
                            }
                        }
                        if (idx !== -1) {
                            list[idx] = { "mac": btImagesSection.pendingMac, "image": filename };
                        } else {
                            list.push({ "mac": btImagesSection.pendingMac, "image": filename });
                        }
                        Config.options.bluetoothDeviceImages = list;
                        btImagesSection.pendingMac = ""; 
                    }
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("1. Select a Device")
            visible: btImagesSection.getAvailableDevices().length > 0
            isFirst: true
            
            Flow {
                Layout.fillWidth: true
                spacing: 12
                
                Repeater {
                    model: btImagesSection.getAvailableDevices()
                    delegate: Rectangle {
                        width: 240
                        height: 76
                        radius: Appearance.rounding.normal
                        color: isSelected ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer3
                        border.width: 0
                        
                        readonly property bool isSelected: btImagesSection.pendingMac === (modelData ? modelData.address : "")
                        
                        Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutQuart } }
                        Behavior on border.color { ColorAnimation { duration: 250; easing.type: Easing.OutQuart } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 14
                            spacing: 12

                            Item {
                                Layout.preferredWidth: 42
                                Layout.preferredHeight: 42

                                MaterialShape {
                                    anchors.centerIn: parent
                                    implicitSize: 42
                                    color: isSelected ? Appearance.colors.colPrimary : Appearance.colors.colSurfaceContainerHighest
                                    
                                    function rollShape() {
                                        const shapes = ["Cookie6Sided", "Cookie7Sided", "Cookie9Sided", "Cookie12Sided", "Clover8Leaf", "SoftBurst", "Circle", "Sunny"];
                                        shapeString = shapes[Math.floor(Math.random() * shapes.length)];
                                    }
                                    Component.onCompleted: rollShape()
                                }

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "bluetooth"
                                    iconSize: 22
                                    fill: 1
                                    color: isSelected ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurfaceVariant
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                StyledText {
                                    text: (modelData && modelData.name) ? modelData.name : "Unknown"
                                    font.weight: Font.DemiBold
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    color: isSelected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurface
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                StyledText {
                                    text: (modelData && modelData.address) ? modelData.address : ""
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: isSelected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurfaceVariant
                                    opacity: isSelected ? 0.9 : 0.7
                                    Layout.fillWidth: true
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (modelData) btImagesSection.pendingMac = modelData.address
                        }
                    }
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("2. Assign Image")
            visible: btImagesSection.pendingMac !== ""
            
            Rectangle {
                Layout.fillWidth: true
                height: 120
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer3
                border.width: 0

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 12
                    
                    ColumnLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 2
                        StyledText {
                            text: Translation.tr("Preparing to style: ") + btImagesSection.getDeviceName(btImagesSection.pendingMac)
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnSurface
                            Layout.alignment: Qt.AlignHCenter
                        }
                        StyledText {
                            text: btImagesSection.pendingMac
                            font.family: Appearance.font.family.numbers
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOutline
                            Layout.alignment: Qt.AlignHCenter
                        }
                    }

                    RippleButtonWithIcon {
                        Layout.alignment: Qt.AlignHCenter
                        materialIcon: "add_photo_alternate"
                        mainText: Translation.tr("Upload Artwork")
                        onClicked: pickerProc.exec([btImagesSection.manageScript, "pick"])
                    }
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Managed Devices")
            visible: btImagesSection.getDeviceImages().length > 0
            isLast: true

            Flow {
                Layout.fillWidth: true
                spacing: 12

                Repeater {
                    model: btImagesSection.getDeviceImages()
                    delegate: Rectangle {
                        width: 180
                        height: 220
                        radius: Appearance.rounding.normal
                        color: Appearance.colors.colLayer3
                        border.width: 0

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 14
                            spacing: 12

                            // Image Container
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 110
                                color: Appearance.colors.colLayer1
                                radius: Appearance.rounding.normal
                                clip: true

                                Image {
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    source: (modelData && modelData.image) ? "file://" + Directories.shellConfig + "/bluetooth_images/" + modelData.image : ""
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                    mipmap: true
                                }
                            }

                            // Info Container
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                
                                StyledText {
                                    text: modelData ? btImagesSection.getDeviceName(modelData.mac) : ""
                                    font.weight: Font.DemiBold
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    color: Appearance.colors.colOnSurface
                                    Layout.alignment: Qt.AlignHCenter
                                    horizontalAlignment: Text.AlignHCenter
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }

                                StyledText {
                                    text: modelData ? modelData.mac : ""
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.family: Appearance.font.family.numbers
                                    color: Appearance.colors.colOnSurfaceVariant
                                    Layout.alignment: Qt.AlignHCenter
                                    horizontalAlignment: Text.AlignHCenter
                                    Layout.fillWidth: true
                                }
                            }

                            // Delete Action
                            RowLayout {
                                Layout.fillWidth: true
                                Item { Layout.fillWidth: true } // Spacer pushes button to right
                                
                                IconToolbarButton {
                                    text: "delete"
                                    onClicked: {
                                        let list = btImagesSection.getDeviceImages();
                                        list.splice(index, 1);
                                        Config.options.bluetoothDeviceImages = list;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    ContentSection {
        icon: "save"
        title: Translation.tr("File Paths & Transfers")

        ContentSubsectionLabel { text: Translation.tr("Save paths") }

        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("Video record path")
            text: Config.options.screenRecord.savePath
            wrapMode: TextEdit.Wrap
            onTextChanged: {
                Config.options.screenRecord.savePath = text;
            }
        }

        ConfigSwitch {
            buttonIcon: "videocam"
            text: Translation.tr("Use OBS for recording")
            checked: Config.options.screenRecord.service === "obs"
            onCheckedChanged: {
                Config.options.screenRecord.service = checked ? "obs" : "wf-recorder";
            }
        }

        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("Screenshot path")
            text: Config.options.screenSnip.savePath
            wrapMode: TextEdit.Wrap
            onTextChanged: {
                Config.options.screenSnip.savePath = text;
            }
        }

        ContentSubsectionLabel { text: Translation.tr("LocalSend CLI") }

        HelperLinkBox {
            Layout.fillWidth: true
            title: Translation.tr("LocalSend")
            text: Translation.tr("An open-source cross-platform alternative to AirDrop. Check GitHub for installation instructions.")
            isFirst: true

            RippleButtonWithIcon {
                mainText: Translation.tr("Open GitHub")
                materialIcon: "open_in_new"
                Layout.topMargin: 4
                Layout.bottomMargin: 4
                colBackground: Appearance.colors.colLayer0
                colBackgroundHover: Appearance.colors.colLayer0Hover
                colRipple: Appearance.colors.colLayer0Active
                downAction: () => {
                    Qt.openUrlExternally("https://github.com/localsend/localsend")
                }
            }
        }

        ConfigSwitch {
            buttonIcon: "power_settings_new"
            text: Translation.tr("Auto-start")
            checked: Config.options.localsend.autoStart
            enabled: LocalSend.available
            onCheckedChanged: {
                Config.options.localsend.autoStart = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "notifications"
            text: Translation.tr("Show notifications")
            checked: Config.options.localsend.showNotifications
            enabled: LocalSend.available
            onCheckedChanged: {
                Config.options.localsend.showNotifications = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "branding_watermark"
            text: Translation.tr("Prefer popup over notification")
            checked: Config.options.localsend.preferPopupOverNotification
            enabled: LocalSend.available
            onCheckedChanged: {
                Config.options.localsend.preferPopupOverNotification = checked;
            }
        }

        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("Download path")
            text: Config.options.localsend.downloadPath
            wrapMode: TextEdit.Wrap
            enabled: LocalSend.available
            onTextChanged: {
                Config.options.localsend.downloadPath = text;
            }
        }

        ContentSubsectionLabel { text: Translation.tr("Wallpaper Browser") }

        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("Wallpaper Browser download path")
            text: Config.options.wallpapers.paths.download
            wrapMode: TextEdit.Wrap
            onTextChanged: {
                Config.options.wallpapers.paths.download = text;
            }
        }
    }

    ContentSection {
        icon: "cloud"
        title: Translation.tr("Weather Service")

        TipBox {
            Layout.fillWidth: true
            text: Translation.tr("Enable GPS location relies on geoclue2 and might take a few seconds to fetch the coordinates on boot.")
            isFirst: true
        }

        ConfigSwitch {
            buttonIcon: "assistant_navigation"
            text: Translation.tr("Enable GPS location")
            checked: Config.options.bar.weather.enableGPS
            onCheckedChanged: {
                Config.options.bar.weather.enableGPS = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "thermometer"
            text: Translation.tr("Fahrenheit unit")
            checked: Config.options.bar.weather.useUSCS
            onCheckedChanged: {
                Config.options.bar.weather.useUSCS = checked;
            }
        }

        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("City name")
            text: Config.options.bar.weather.city
            wrapMode: TextEdit.Wrap
            onTextChanged: {
                Config.options.bar.weather.city = text;
            }
        }

        ConfigSpinBox {
            icon: "av_timer"
            text: Translation.tr("Polling interval (m)")
            value: Config.options.bar.weather.fetchInterval
            from: 5
            to: 50
            stepSize: 5
            onValueChanged: {
                Config.options.bar.weather.fetchInterval = value;
            }
        }
    }

    ContentSection {
        title: Translation.tr("Terminal Settings")
        icon: "terminal"

        ConfigSwitch {
            buttonIcon: "dark_mode"
            text: Translation.tr("Force dark mode in terminal")
            checked: Config.options.appearance.wallpaperTheming.terminalGenerationProps.forceDarkMode
            onCheckedChanged: {
                Config.options.appearance.wallpaperTheming.terminalGenerationProps.forceDarkMode = checked;
            }
            StyledToolTip {
                text: Translation.tr("Ignored if terminal theming is not enabled in Colors & Themes")
            }
        }

        ConfigSpinBox {
            icon: "contrast"
            text: Translation.tr("Terminal: Harmony %")
            value: Config.options.appearance.wallpaperTheming.terminalGenerationProps.harmony * 100
            from: 0
            to: 100
            stepSize: 1
            onValueChanged: {
                Config.options.appearance.wallpaperTheming.terminalGenerationProps.harmony = value / 100;
            }
        }

        ConfigSpinBox {
            icon: "tune"
            text: Translation.tr("Terminal: Harmonize threshold")
            value: Config.options.appearance.wallpaperTheming.terminalGenerationProps.harmonizeThreshold
            from: 0
            to: 100
            stepSize: 1
            onValueChanged: {
                Config.options.appearance.wallpaperTheming.terminalGenerationProps.harmonizeThreshold = value;
            }
        }

        ConfigSpinBox {
            icon: "brightness_high"
            text: Translation.tr("Terminal: Foreground boost %")
            value: Config.options.appearance.wallpaperTheming.terminalGenerationProps.termFgBoost * 100
            from: 0
            to: 100
            stepSize: 1
            onValueChanged: {
                Config.options.appearance.wallpaperTheming.terminalGenerationProps.termFgBoost = value / 100;
            }
        }
    }

    ContentSection {
        icon: "build"
        title: Translation.tr("Waffle Tweaks (Optional)")

        ConfigSwitch {
            buttonIcon: "align_horizontal_center"
            text: Translation.tr("Fix switch handle position")
            checked: Config.options.waffles.tweaks.switchHandlePositionFix
            onCheckedChanged: {
                Config.options.waffles.tweaks.switchHandlePositionFix = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "animation"
            text: Translation.tr("Smoother menu animations")
            checked: Config.options.waffles.tweaks.smootherMenuAnimations
            onCheckedChanged: {
                Config.options.waffles.tweaks.smootherMenuAnimations = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "search"
            text: Translation.tr("Smoother search bar")
            checked: Config.options.waffles.tweaks.smootherSearchBar
            onCheckedChanged: {
                Config.options.waffles.tweaks.smootherSearchBar = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "calendar_today"
            text: Translation.tr("Force 2-character day of week on calendar")
            checked: Config.options.waffles.calendar.force2CharDayOfWeek
            onCheckedChanged: {
                Config.options.waffles.calendar.force2CharDayOfWeek = checked;
            }
        }
    }
    }
}
