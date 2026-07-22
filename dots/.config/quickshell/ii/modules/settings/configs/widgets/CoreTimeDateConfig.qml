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
            text: Translation.tr("Time & Date Formats")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
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
                        value: "dd/MM, ddd"
                    },
                    {
                        displayName: Translation.tr("Month First MM/dd"),
                        value: "MM/dd, ddd"
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
                                StyledToolTip { text: Translation.tr("Auto-detect Timezone") }
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
        enabled: Config.options.bar.styles.clock === "material"
        icon: "interests"
        title: Translation.tr("Material 3 Design")

        ConfigSwitch {
            buttonIcon: "flip"
            text: Translation.tr("Move secondary component to the opposite")
            checked: Config.options.bar.clock.secondaryOpposite
            onCheckedChanged: {
                Config.options.bar.clock.secondaryOpposite = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "radio_button_checked"
            text: Translation.tr("Show primary component")
            checked: Config.options.bar.clock.showPrimary
            onCheckedChanged: {
                Config.options.bar.clock.showPrimary = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "radio_button_unchecked"
            text: Translation.tr("Show secondary component")
            checked: Config.options.bar.clock.showSecondary
            onCheckedChanged: {
                Config.options.bar.clock.showSecondary = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "sync"
            text: Translation.tr("Swap secondary component with the primary")
            checked: Config.options.bar.clock.swapPrimaryWithSecondary
            onCheckedChanged: {
                Config.options.bar.clock.swapPrimaryWithSecondary = checked;
            }
        }
    }

    ContentSection {
        icon: "alarm"
        title: Translation.tr("Alarm Settings")

        ConfigSwitch {
            buttonIcon: "fullscreen"
            text: Translation.tr("Fullscreen ringing popup")
            checked: Config.options.time.alarms.useFullscreenPopup
            onCheckedChanged: {
                Config.options.time.alarms.useFullscreenPopup = checked;
            }
            StyledToolTip {
                text: Translation.tr("Shows a full-screen overlay when an alarm is ringing. If disabled, a notification will be used instead.")
            }
        }

        ConfigSwitch {
            buttonIcon: "pace"
            text: Translation.tr("Show analog clock in popup")
            checked: Config.options.time.alarms.showAnalogClock
            onCheckedChanged: {
                Config.options.time.alarms.showAnalogClock = checked;
            }
            StyledToolTip {
                text: Translation.tr("Show or hide the decorative analog clock in the bar clock widget popup.")
            }
        }

        ConfigSwitch {
            buttonIcon: "public"
            text: Translation.tr("Show world clocks in popup")
            checked: Config.options.time.alarms.showWorldClocks
            onCheckedChanged: {
                Config.options.time.alarms.showWorldClocks = checked;
            }
            StyledToolTip {
                text: Translation.tr("Show or hide the world clocks section in the bar clock widget popup.")
            }
        }

        ConfigSwitch {
            buttonIcon: "notifications_active"
            text: Translation.tr("Show alarms section in popup")
            checked: Config.options.time.alarms.showAlarmsSection
            onCheckedChanged: {
                Config.options.time.alarms.showAlarmsSection = checked;
            }
            StyledToolTip {
                text: Translation.tr("Show or hide the alarms card in the bar clock widget popup.")
            }
        }
    }
}
