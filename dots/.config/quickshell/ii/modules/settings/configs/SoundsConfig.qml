import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import Quickshell
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: page

    forceWidth: false

    // Pick up freshly installed themes whenever the page is opened
    Component.onCompleted: SoundService.rescan()

    readonly property var customizableEvents: [
        { key: "notifications", icon: "notifications", label: Translation.tr("Notifications") },
        { key: "volumeChange", icon: "volume_up", label: Translation.tr("Volume change") },
        { key: "battery", icon: "battery_alert", label: Translation.tr("Battery & power") },
        { key: "screenshot", icon: "photo_camera", label: Translation.tr("Screenshot shutter") },
        { key: "pomodoro", icon: "av_timer", label: Translation.tr("Pomodoro") },
        { key: "alarm", icon: "alarm", label: Translation.tr("Alarm ring") },
        { key: "session", icon: "login", label: Translation.tr("Login") },
        { key: "devices", icon: "bluetooth_connected", label: Translation.tr("Device connections") },
        { key: "lock", icon: "lock", label: Translation.tr("Screen lock") }
    ]

    property string fileDialogTarget: "" // "" = install archive, else custom-sound category key

    FileDialog {
        id: fileDialog
        currentFolder: page.fileDialogTarget === "" ? "file:///home" : "file:///usr/share/sounds"
        nameFilters: page.fileDialogTarget === ""
            ? [Translation.tr("Theme archives (*.tar.gz *.tgz *.tar.xz *.tar.bz2 *.tar.zst *.zip)"), Translation.tr("All files (*)")]
            : [Translation.tr("Audio files (*.oga *.ogg *.wav *.mp3 *.flac *.opus)"), Translation.tr("All files (*)")]
        onAccepted: {
            const path = decodeURIComponent(selectedFile.toString().replace(/^file:\/\//, ""));
            if (page.fileDialogTarget === "") {
                SoundService.installFromArchive(path);
            } else {
                Config.options.sounds.custom[page.fileDialogTarget] = path;
            }
        }
    }

    ContentSection {
        icon: "volume_up"
        title: Translation.tr("System sounds")

        ConfigSwitch {
            buttonIcon: "music_note"
            text: Translation.tr("Enable system sounds")
            checked: Config.options.sounds.enable
            onCheckedChanged: {
                Config.options.sounds.enable = checked;
            }

            StyledToolTip {
                text: Translation.tr("Master switch for shell event sounds. The alarm ring is not affected.")
            }
        }

        ConfigSlider {
            buttonIcon: "volume_up"
            text: Translation.tr("Sound volume")
            from: 0
            to: 100
            stepSize: 1
            value: Config.options.sounds.volume ?? 100
            onValueChanged: {
                if (Config.options.sounds.volume === Math.round(value))
                    return;

                Config.options.sounds.volume = Math.round(value);
            }
            // Sample the new loudness when the slider is released
            onIsPressedChanged: {
                if (!isPressed)
                    SoundService.preview(Config.options.sounds.theme, ["audio-volume-change", "bell"]);
            }
        }
    }

    ContentSection {
        id: themeSection

        icon: "library_music"
        title: Translation.tr("Sound theme")
        tooltip: Translation.tr("Themes are discovered from /usr/share/sounds and ~/.local/share/sounds. Missing sounds fall back to the FreeDesktop theme.")

        property string installStatus: ""

        Connections {
            target: SoundService
            function onInstallFinished(success, message) {
                themeSection.installStatus = message;
                installStatusClearTimer.restart();
            }
        }

        Timer {
            id: installStatusClearTimer
            interval: 8000
            onTriggered: themeSection.installStatus = ""
        }

        Repeater {
            model: SoundService.themes

            ThemeCard {}
        }

        StyledText {
            visible: SoundService.themes.length === 0
            text: Translation.tr("No sound themes found")
            color: Appearance.colors.colSubtext
        }

        RowLayout {
            Layout.topMargin: 4
            spacing: 8

            GroupButtonWithIcon {
                buttonIcon: "archive"
                buttonText: Translation.tr("Install from file...")
                onClicked: {
                    page.fileDialogTarget = "";
                    fileDialog.open();
                }
            }

            GroupButtonWithIcon {
                buttonIcon: "refresh"
                buttonText: Translation.tr("Rescan")
                onClicked: SoundService.rescan()
            }

            StyledText {
                Layout.fillWidth: true
                visible: themeSection.installStatus !== ""
                text: themeSection.installStatus
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }
    }

    ContentSection {
        icon: "notifications_active"
        title: Translation.tr("Events")

        ConfigSwitch {
            buttonIcon: "notifications"
            text: Translation.tr("Notifications")
            checked: Config.options.sounds.notifications
            onCheckedChanged: {
                Config.options.sounds.notifications = checked;
            }

            StyledToolTip {
                text: Translation.tr("Play a sound when a notification arrives. Muted in Do Not Disturb mode.")
            }
        }

        ConfigSwitch {
            buttonIcon: "volume_up"
            text: Translation.tr("Volume change")
            checked: Config.options.sounds.volumeChange
            onCheckedChanged: {
                Config.options.sounds.volumeChange = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "battery_alert"
            text: Translation.tr("Battery & power")
            checked: Config.options.sounds.battery
            onCheckedChanged: {
                Config.options.sounds.battery = checked;
            }

            StyledToolTip {
                text: Translation.tr("Charger plug/unplug, battery low and battery full.")
            }
        }

        ConfigSwitch {
            buttonIcon: "photo_camera"
            text: Translation.tr("Screenshot shutter")
            checked: Config.options.sounds.screenshot
            onCheckedChanged: {
                Config.options.sounds.screenshot = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "bluetooth_connected"
            text: Translation.tr("Device connections")
            checked: Config.options.sounds.devices
            onCheckedChanged: {
                Config.options.sounds.devices = checked;
            }

            StyledToolTip {
                text: Translation.tr("Bluetooth devices connecting/disconnecting and KDE Connect phone reachability.")
            }
        }

        ConfigSwitch {
            buttonIcon: "lock"
            text: Translation.tr("Screen lock & unlock")
            checked: Config.options.sounds.lock
            onCheckedChanged: {
                Config.options.sounds.lock = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "av_timer"
            text: Translation.tr("Pomodoro")
            checked: Config.options.sounds.pomodoro
            onCheckedChanged: {
                Config.options.sounds.pomodoro = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "alarm"
            text: Translation.tr("Alarm ring")
            checked: Config.options.sounds.alarm
            onCheckedChanged: {
                Config.options.sounds.alarm = checked;
            }

            StyledToolTip {
                text: Translation.tr("Rings even when system sounds are disabled, so the master switch can't silence your alarm.")
            }
        }

        ConfigSwitch {
            buttonIcon: "waves"
            text: Translation.tr("Gentle wake (alarm fade-in)")
            enabled: Config.options.sounds.alarm
            checked: Config.options.sounds.alarmFadeIn
            onCheckedChanged: {
                Config.options.sounds.alarmFadeIn = checked;
            }

            StyledToolTip {
                text: Translation.tr("The alarm starts silent and ramps up to full volume instead of blasting instantly.")
            }
        }

        ConfigSpinBox {
            visible: Config.options.sounds.alarm && Config.options.sounds.alarmFadeIn
            icon: "schedule"
            text: Translation.tr("Fade-in duration (seconds)")
            value: Config.options.sounds.alarmFadeInSeconds
            from: 5
            to: 120
            stepSize: 5
            onValueChanged: {
                Config.options.sounds.alarmFadeInSeconds = value;
            }
        }

        ConfigSwitch {
            buttonIcon: "login"
            text: Translation.tr("Login")
            checked: Config.options.sounds.session
            onCheckedChanged: {
                Config.options.sounds.session = checked;
            }

            StyledToolTip {
                text: Translation.tr("Play a welcome sound when the shell starts.")
            }
        }
    }

    ContentSection {
        icon: "apps"
        title: Translation.tr("Per-app notification sounds")
        tooltip: Translation.tr("Choose which apps may play notification sounds. Apps can also be muted straight from an expanded notification popup.")

        AppSoundRulesEditor {}
    }

    ContentSection {
        icon: "tune"
        title: Translation.tr("Custom sounds")
        tooltip: Translation.tr("Override the theme sound for any event with your own audio file.")

        Repeater {
            model: page.customizableEvents

            CustomSoundRow {}
        }
    }

    // ── Components ────────────────────────────────────────────────────────

    component PreviewButton: RippleButton {
        id: previewButton

        required property var modelData
        property string themeId
        // Greyed out when the theme itself lacks all of these sounds and the
        // preview would fall back to another theme
        readonly property bool available: SoundService.hasOwnSound(themeId, modelData.events)

        implicitWidth: 34
        implicitHeight: 34
        topLeftRadius: Appearance.rounding.full
        topRightRadius: Appearance.rounding.full
        bottomLeftRadius: Appearance.rounding.full
        bottomRightRadius: Appearance.rounding.full
        colBackground: Appearance.colors.colLayer3
        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
        colRipple: Appearance.colors.colSecondaryContainerActive
        opacity: available ? 1 : 0.4
        onClicked: SoundService.preview(previewButton.themeId, previewButton.modelData.events)

        MaterialSymbol {
            anchors.centerIn: parent
            text: previewButton.modelData.icon
            iconSize: Appearance.font.pixelSize.large
            color: Appearance.colors.colOnLayer3
        }

        StyledToolTip {
            text: previewButton.available ? previewButton.modelData.label : Translation.tr("%1 — not in this theme, falls back to FreeDesktop").arg(previewButton.modelData.label)
        }
    }

    component ThemeCard: Rectangle {
        id: card

        required property var modelData
        readonly property bool selected: Config.options.sounds.theme === modelData.id
        readonly property int soundCount: SoundService.soundCount(modelData.id)

        Layout.fillWidth: true
        implicitHeight: cardLayout.implicitHeight + 28
        radius: Appearance.rounding.normal
        color: selected ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer2Base
        border.width: 1
        border.color: selected ? Appearance.colors.colPrimary : Appearance.colors.colLayer0Border

        MouseArea {
            anchors.fill: parent
            onClicked: Config.options.sounds.theme = card.modelData.id
        }

        ColumnLayout {
            id: cardLayout

            spacing: 10

            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                margins: 14
            }

            RowLayout {
                spacing: 10

                MaterialSymbol {
                    text: card.selected ? "radio_button_checked" : "radio_button_unchecked"
                    iconSize: Appearance.font.pixelSize.huge
                    color: card.selected ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        text: card.modelData.name
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        color: card.selected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
                    }

                    StyledText {
                        visible: card.modelData.comment !== ""
                        text: card.modelData.comment
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }

                Rectangle {
                    implicitWidth: countText.implicitWidth + 16
                    implicitHeight: countText.implicitHeight + 6
                    radius: Appearance.rounding.full
                    color: card.selected ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer3

                    StyledText {
                        id: countText
                        anchors.centerIn: parent
                        text: Translation.tr("%1 sounds").arg(card.soundCount)
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: card.selected ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer3
                    }
                }
            }

            RowLayout {
                spacing: 6

                StyledText {
                    text: Translation.tr("Preview:")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    Layout.rightMargin: 4
                }

                Repeater {
                    model: [
                        { icon: "notifications", label: Translation.tr("Notification"), events: ["message-new-instant"] },
                        { icon: "warning", label: Translation.tr("Warning"), events: ["dialog-warning"] },
                        { icon: "error", label: Translation.tr("Error"), events: ["dialog-error"] },
                        { icon: "volume_up", label: Translation.tr("Volume change"), events: ["audio-volume-change", "bell"] },
                        { icon: "power", label: Translation.tr("Power plugged"), events: ["power-plug"] }
                    ]

                    PreviewButton {
                        themeId: card.modelData.id
                    }
                }

                Item {
                    Layout.fillWidth: true
                }
            }
        }
    }

    component AppSoundRulesEditor: ColumnLayout {
        id: editor

        readonly property var conf: Config.options.sounds.notificationApps
        readonly property string query: searchField.text.trim()

        function ruleFor(name) {
            const lower = name.toLowerCase();
            if (conf.neverPlayApps.some(app => app.toLowerCase() === lower))
                return "mute";
            if (conf.alwaysPlayApps.some(app => app.toLowerCase() === lower))
                return "play";
            return "default";
        }

        function setRule(name, rule) {
            const lower = name.toLowerCase();
            conf.alwaysPlayApps = conf.alwaysPlayApps.filter(app => app.toLowerCase() !== lower);
            conf.neverPlayApps = conf.neverPlayApps.filter(app => app.toLowerCase() !== lower);
            if (rule === "play")
                conf.alwaysPlayApps = [...conf.alwaysPlayApps, name];
            else if (rule === "mute")
                conf.neverPlayApps = [...conf.neverPlayApps, name];
        }

        // Apps with explicit rules, then (while searching) installed apps and
        // the raw query as a free-text fallback, since notification app names
        // can differ from any desktop entry
        readonly property var displayedApps: {
            const lowerQuery = query.toLowerCase();
            const taken = new Set();
            const result = [];
            const add = (name, icon) => {
                if (!name || taken.has(name.toLowerCase()))
                    return;
                taken.add(name.toLowerCase());
                result.push({
                    name: name,
                    icon: icon
                });
            };
            const matches = name => lowerQuery === "" || name.toLowerCase().includes(lowerQuery);

            [...conf.alwaysPlayApps, ...conf.neverPlayApps].filter(matches).forEach(name => add(name, ""));
            if (lowerQuery !== "") {
                AppSearch.fuzzyQuery(query).slice(0, 8).forEach(entry => add(entry.name, entry.icon));
                add(query, "");
            }
            return result;
        }

        spacing: 8

        ConfigSelectionArray {
            currentValue: editor.conf.defaultPolicy
            onSelected: newValue => {
                editor.conf.defaultPolicy = newValue;
            }
            options: [
                {
                    displayName: Translation.tr("Play by default"),
                    icon: "volume_up",
                    value: "play"
                },
                {
                    displayName: Translation.tr("Mute by default"),
                    icon: "volume_off",
                    value: "mute"
                }
            ]
        }

        MaterialTextField {
            id: searchField
            Layout.fillWidth: true
            placeholderText: Translation.tr("Search apps or type a name")
        }

        StyledText {
            visible: editor.displayedApps.length === 0
            Layout.fillWidth: true
            text: Translation.tr("No rules yet. Search to pick an installed app, or type any name a notification reports.")
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }

        Repeater {
            model: editor.displayedApps
            delegate: RowLayout {
                id: appRow
                required property var modelData
                readonly property string rule: editor.ruleFor(modelData.name)

                Layout.fillWidth: true
                spacing: 10

                IconImage {
                    implicitSize: 28
                    source: Quickshell.iconPath(appRow.modelData.icon !== "" ? appRow.modelData.icon : AppSearch.guessIcon(appRow.modelData.name), "image-missing")
                }

                StyledText {
                    Layout.fillWidth: true
                    text: appRow.modelData.name
                    elide: Text.ElideRight
                    color: Appearance.colors.colOnSecondaryContainer
                }

                SelectionGroupButton {
                    leftmost: true
                    buttonIcon: "remove"
                    toggled: appRow.rule === "default"
                    onClicked: editor.setRule(appRow.modelData.name, "default")
                    StyledToolTip {
                        text: Translation.tr("Follow default")
                    }
                }
                SelectionGroupButton {
                    buttonIcon: "volume_up"
                    toggled: appRow.rule === "play"
                    onClicked: editor.setRule(appRow.modelData.name, "play")
                    StyledToolTip {
                        text: Translation.tr("Always play")
                    }
                }
                SelectionGroupButton {
                    rightmost: true
                    buttonIcon: "volume_off"
                    toggled: appRow.rule === "mute"
                    onClicked: editor.setRule(appRow.modelData.name, "mute")
                    StyledToolTip {
                        text: Translation.tr("Never play")
                    }
                }
            }
        }
    }

    component CustomSoundRow: Rectangle {
        id: customRow

        required property var modelData
        readonly property string customPath: Config.options.sounds.custom[modelData.key] ?? ""
        readonly property bool hasCustom: customPath !== ""

        Layout.fillWidth: true
        implicitHeight: customRowLayout.implicitHeight + 16
        radius: Appearance.rounding.verysmall
        color: Appearance.colors.colLayer2Base

        RowLayout {
            id: customRowLayout

            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                leftMargin: 12
                rightMargin: 8
            }
            spacing: 10

            MaterialSymbol {
                text: customRow.modelData.icon
                iconSize: Appearance.font.pixelSize.huge
                color: Appearance.colors.colOnLayer2
            }

            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignLeft
                text: customRow.modelData.label
                elide: Text.ElideRight
                color: Appearance.colors.colOnLayer2
            }

            StyledText {
                visible: customRow.hasCustom
                Layout.maximumWidth: 320
                text: customRow.customPath
                elide: Text.ElideMiddle
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }

            RippleButton {
                visible: customRow.hasCustom
                implicitWidth: 32
                implicitHeight: 32
                buttonRadius: Appearance.rounding.full
                colBackground: "transparent"
                onClicked: SoundService.previewFile(customRow.customPath)

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "play_arrow"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnLayer2
                }

                StyledToolTip {
                    text: Translation.tr("Play custom sound")
                }
            }

            RippleButton {
                implicitWidth: 32
                implicitHeight: 32
                buttonRadius: Appearance.rounding.full
                colBackground: "transparent"
                onClicked: {
                    page.fileDialogTarget = customRow.modelData.key;
                    fileDialog.open();
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "folder_open"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnLayer2
                }

                StyledToolTip {
                    text: Translation.tr("Choose a custom sound file")
                }
            }

            RippleButton {
                visible: customRow.hasCustom
                implicitWidth: 32
                implicitHeight: 32
                buttonRadius: Appearance.rounding.full
                colBackground: "transparent"
                onClicked: Config.options.sounds.custom[customRow.modelData.key] = ""

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "close"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnLayer2
                }

                StyledToolTip {
                    text: Translation.tr("Reset to theme sound")
                }
            }
        }
    }
}
