pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/*
 * One At a Glance Target or Complication in its ordered list: the row (icon,
 * name, summary, on/off, move, edit, remove) and, opened, its editor — the
 * type's own settings, where it shows, and its All/Any requirements.
 */
Rectangle {
    id: root

    property string kind: "target" // "target" | "complication"
    property var item: ({})
    property int index: 0
    property int count: 1
    property bool open: false

    signal toggleOpen
    signal moved(int delta)
    signal removed
    signal changed(var item)

    readonly property var info: AtAGlanceService.typeInfo(root.kind, root.item.type)
    readonly property var settings: root.item.settings ?? ({})

    // Switches report their first binding as a change; only act once the card
    // is built, and only on a real difference from the stored (or default) value.
    property bool armed: false
    Component.onCompleted: Qt.callLater(() => root.armed = true)

    readonly property var defaults: AtAGlanceService.defaultSettings(root.kind, root.item.type ?? "")
    readonly property var itemDefaults: ({ enabled: true, showOnDesktop: true, showOnLock: true, disableSubComplication: false, requireAll: [], requireAny: [] })

    function setting(key, fallback) {
        const v = root.settings[key];
        if (v !== undefined && v !== null)
            return v;
        return root.defaults[key] !== undefined ? root.defaults[key] : fallback;
    }

    // Written after the handler returns: a synchronous write rebuilds the
    // binding that is still being evaluated (a binding loop).
    function emit(copy) {
        Qt.callLater(() => root.changed(copy));
    }

    function set(key, value) {
        if (!root.armed)
            return;
        const current = root.item[key] ?? root.itemDefaults[key];
        if (JSON.stringify(current) === JSON.stringify(value))
            return;
        const copy = AtAGlanceService.plain(root.item);
        copy[key] = value;
        root.emit(copy);
    }

    function setSetting(key, value) {
        if (!root.armed)
            return;
        if (JSON.stringify(root.setting(key, undefined)) === JSON.stringify(value))
            return;
        const copy = AtAGlanceService.plain(root.item);
        copy.settings = copy.settings ?? {};
        copy.settings[key] = value;
        root.emit(copy);
    }

    function setRequirements(group, list) {
        if (JSON.stringify(root.item[group] ?? []) === JSON.stringify(list))
            return;
        const copy = AtAGlanceService.plain(root.item);
        copy[group] = list;
        Qt.callLater(() => root.changed(copy));
    }

    readonly property string summary: {
        const all = (root.item.requireAll ?? []).length;
        const any = (root.item.requireAny ?? []).length;
        const where = root.item.showOnDesktop === false ? Translation.tr("Lock screen only")
            : root.item.showOnLock === false ? Translation.tr("Desktop only") : "";
        const parts = [root.info.description];
        if (all + any > 0)
            parts.push(Translation.tr("%1 Any and %2 All Requirements configured").arg(any).arg(all));
        if (where !== "")
            parts.push(where);
        return parts.join(" · ");
    }

    Layout.fillWidth: true
    implicitHeight: column.implicitHeight + 24
    radius: Appearance.rounding.normal
    color: root.open ? Appearance.colors.colLayer2 : Appearance.colors.colLayer1
    opacity: root.item.enabled === false ? 0.7 : 1

    ColumnLayout {
        id: column
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        // ── Row ────────────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            MaterialShapeWrappedMaterialSymbol {
                text: root.info.icon
                iconSize: 20
                padding: 10
                shape: root.kind === "target" ? MaterialShape.Shape.Cookie9Sided : MaterialShape.Shape.Circle
                color: root.item.enabled === false ? Appearance.colors.colLayer3 : Appearance.colors.colPrimaryContainer
                colSymbol: root.item.enabled === false ? Appearance.colors.colOnLayer3 : Appearance.colors.colOnPrimaryContainer
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                StyledText {
                    Layout.fillWidth: true
                    text: root.info.name
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnLayer1
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.summary
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
            }

            Repeater {
                model: [
                    { icon: "arrow_upward", tip: Translation.tr("Move up"), enabled: root.index > 0, act: () => root.moved(-1) },
                    { icon: "arrow_downward", tip: Translation.tr("Move down"), enabled: root.index < root.count - 1, act: () => root.moved(1) },
                    { icon: root.open ? "expand_less" : "tune", tip: root.open ? Translation.tr("Close") : Translation.tr("Settings & requirements"), enabled: true, act: () => root.toggleOpen() },
                    { icon: "delete", tip: Translation.tr("Remove"), enabled: true, act: () => root.removed() }
                ]
                delegate: RippleButton {
                    id: key
                    required property var modelData
                    implicitWidth: 34
                    implicitHeight: 34
                    buttonRadius: 17
                    enabled: key.modelData.enabled
                    colBackground: "transparent"
                    onClicked: key.modelData.act()
                    contentItem: MaterialSymbol {
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: key.modelData.icon
                        iconSize: 20
                        color: Appearance.colors.colOnLayer1
                        opacity: key.enabled ? 1 : 0.35
                    }
                    StyledToolTip {
                        text: key.modelData.tip
                    }
                }
            }

            StyledSwitch {
                checked: root.item.enabled !== false
                onClicked: root.set("enabled", checked)
            }
        }

        // ── Editor ─────────────────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            visible: root.open
            spacing: 4

            ContentSubsectionLabel {
                visible: settingsColumn.visibleChildren.length > 0
                text: Translation.tr("Settings")
            }

            ColumnLayout {
                id: settingsColumn
                Layout.fillWidth: true
                spacing: 4

                // Date / Clock formats
                ConfigTextField {
                    Layout.fillWidth: true
                    visible: root.item.type === "date"
                    icon: "calendar_today"
                    text: Translation.tr("Date Format")
                    placeholderText: Translation.tr("Automatic (ddd, MMM d)")
                    tooltip: Translation.tr("Qt date format, e.g. dddd, d MMMM. Leave empty for the automatic format")
                    inputText: String(root.setting("dateFormat", ""))
                    textField.onEditingFinished: root.setSetting("dateFormat", textField.text.trim())
                }
                ConfigTextField {
                    Layout.fillWidth: true
                    visible: root.item.type === "clock"
                    icon: "schedule"
                    text: Translation.tr("Time Format")
                    placeholderText: Translation.tr("Automatic (system time format)")
                    tooltip: Translation.tr("Qt time format, e.g. hh:mm or h:mm ap")
                    inputText: String(root.setting("timeFormat", ""))
                    textField.onEditingFinished: root.setSetting("timeFormat", textField.text.trim())
                }

                // Greeting
                ConfigTextField {
                    Layout.fillWidth: true
                    visible: root.kind === "target" && root.item.type === "greeting"
                    icon: "badge"
                    text: Translation.tr("Greeting Name")
                    placeholderText: Translation.tr("Your name to show in the greeting")
                    inputText: String(root.setting("name", ""))
                    textField.onEditingFinished: root.setSetting("name", textField.text.trim())
                }
                ConfigSwitch {
                    Layout.fillWidth: true
                    visible: root.kind === "target" && (root.item.type === "greeting" || root.item.type === "blank")
                    buttonIcon: "visibility_off"
                    text: root.item.type === "blank" ? Translation.tr("Hide if no Complications") : Translation.tr("Dynamically Hide")
                    checked: root.setting("hideIfNoComplications", false)
                    onCheckedChanged: root.setSetting("hideIfNoComplications", checked)
                    StyledToolTip {
                        text: Translation.tr("Hides the Target if no Complications are available to show below it")
                    }
                }
                ConfigSwitch {
                    Layout.fillWidth: true
                    visible: root.kind === "target" && root.item.type === "greeting"
                    buttonIcon: "open_in_full"
                    text: Translation.tr("Open Expanded At a Glance")
                    checked: root.setting("openExpandedOnClick", false)
                    onCheckedChanged: root.setSetting("openExpandedOnClick", checked)
                    StyledToolTip {
                        text: Translation.tr("Open the expanded view on click, rather than doing nothing")
                    }
                }
                ConfigSwitch {
                    Layout.fillWidth: true
                    visible: root.kind === "target" && root.item.type === "blank"
                    buttonIcon: "widgets"
                    text: Translation.tr("Show Complications")
                    checked: root.setting("showComplications", true)
                    onCheckedChanged: root.setSetting("showComplications", checked)
                    StyledToolTip {
                        text: Translation.tr("Allow up to two Complications to be shown below the empty Target title")
                    }
                }

                // Calendar
                ConfigRow {
                    Layout.fillWidth: true
                    uniform: true
                    visible: root.kind === "target" && root.item.type === "calendar"
                    ConfigSwitch {
                        buttonIcon: "event_available"
                        text: Translation.tr("Show All Day Events")
                        checked: root.setting("showAllDay", false)
                        onCheckedChanged: root.setSetting("showAllDay", checked)
                        StyledToolTip { text: Translation.tr("Show events which last all day") }
                    }
                    ConfigSwitch {
                        buttonIcon: "location_on"
                        text: Translation.tr("Show Location")
                        checked: root.setting("showLocation", true)
                        onCheckedChanged: root.setSetting("showLocation", checked)
                        StyledToolTip { text: Translation.tr("Show event locations, where available") }
                    }
                }
                ConfigSwitch {
                    Layout.fillWidth: true
                    visible: root.kind === "target" && root.item.type === "calendar"
                    buttonIcon: "help"
                    text: Translation.tr("Show Unconfirmed")
                    checked: root.setting("showUnconfirmed", true)
                    onCheckedChanged: root.setSetting("showUnconfirmed", checked)
                    StyledToolTip { text: Translation.tr("Show events which you have not marked as confirmed attendance") }
                }
                ContentSubsectionLabel {
                    visible: root.kind === "target" && root.item.type === "calendar"
                    text: Translation.tr("Show event for time before start")
                }
                ConfigSelectionArray {
                    visible: root.kind === "target" && root.item.type === "calendar"
                    currentValue: root.setting("preEventMinutes", 60)
                    onSelected: value => root.setSetting("preEventMinutes", value)
                    options: [
                        { displayName: Translation.tr("1 minute"), value: 1 },
                        { displayName: Translation.tr("5 minutes"), value: 5 },
                        { displayName: Translation.tr("15 minutes"), value: 15 },
                        { displayName: Translation.tr("30 minutes"), value: 30 },
                        { displayName: Translation.tr("1 hour"), value: 60 },
                        { displayName: Translation.tr("2 hours"), value: 120 }
                    ]
                }
                ContentSubsectionLabel {
                    visible: root.kind === "target" && root.item.type === "calendar"
                    text: Translation.tr("Show event for time after start")
                }
                ConfigSelectionArray {
                    visible: root.kind === "target" && root.item.type === "calendar"
                    currentValue: root.setting("postEventMinutes", -1)
                    onSelected: value => root.setSetting("postEventMinutes", value)
                    options: [
                        { displayName: Translation.tr("Until end of event"), value: -1 },
                        { displayName: Translation.tr("5 minutes"), value: 5 },
                        { displayName: Translation.tr("15 minutes"), value: 15 },
                        { displayName: Translation.tr("30 minutes"), value: 30 },
                        { displayName: Translation.tr("1 hour"), value: 60 }
                    ]
                }

                // Music
                ConfigRow {
                    Layout.fillWidth: true
                    uniform: true
                    visible: root.kind === "target" && root.item.type === "music"
                    ConfigSwitch {
                        buttonIcon: "album"
                        text: Translation.tr("Show Album Art")
                        checked: root.setting("showAlbumArt", true)
                        onCheckedChanged: root.setSetting("showAlbumArt", checked)
                        StyledToolTip { text: Translation.tr("Shows album art for the currently playing track, if available") }
                    }
                    ConfigSwitch {
                        buttonIcon: "pause_circle"
                        text: Translation.tr("Show While Paused")
                        checked: root.setting("showWhenPaused", false)
                        onCheckedChanged: root.setSetting("showWhenPaused", checked)
                        StyledToolTip { text: Translation.tr("Keep the track on screen after playback is paused") }
                    }
                }

                // Notifications
                ConfigTextField {
                    Layout.fillWidth: true
                    visible: root.kind === "target" && root.item.type === "notifications"
                    icon: "apps"
                    text: Translation.tr("Select App")
                    placeholderText: Translation.tr("All apps")
                    tooltip: Translation.tr("App names to show notifications from, separated by commas")
                    inputText: String(root.setting("apps", ""))
                    textField.onEditingFinished: root.setSetting("apps", textField.text.trim())
                }
                ConfigRow {
                    Layout.fillWidth: true
                    uniform: true
                    visible: root.kind === "target" && root.item.type === "notifications"
                    ConfigSwitch {
                        buttonIcon: "smartphone"
                        text: Translation.tr("Include Phone")
                        checked: root.setting("includePhone", true)
                        onCheckedChanged: root.setSetting("includePhone", checked)
                        StyledToolTip { text: Translation.tr("Also show notifications mirrored from your phone") }
                    }
                    ConfigSwitch {
                        buttonIcon: "wrap_text"
                        text: Translation.tr("Remove New Lines")
                        checked: root.setting("trimNewLines", true)
                        onCheckedChanged: root.setSetting("trimNewLines", checked)
                        StyledToolTip { text: Translation.tr("Remove new lines from the notification's content, fitting as much of it into the Target as possible") }
                    }
                }
                ConfigSpinBox {
                    Layout.fillWidth: true
                    visible: root.kind === "target" && root.item.type === "notifications"
                    icon: "filter_9_plus"
                    text: Translation.tr("Maximum pages")
                    from: 1
                    to: 10
                    stepSize: 1
                    value: root.setting("maxCount", 3)
                    onValueChanged: root.setSetting("maxCount", value)
                }

                // Weather forecast
                ConfigSpinBox {
                    Layout.fillWidth: true
                    visible: root.kind === "target" && root.item.type === "weather"
                    icon: "view_column"
                    text: Translation.tr("Forecast columns")
                    from: 2
                    to: 4
                    stepSize: 1
                    value: root.setting("columns", 4)
                    onValueChanged: root.setSetting("columns", value)
                }

                // Night Light
                ConfigSwitch {
                    Layout.fillWidth: true
                    visible: root.kind === "target" && root.item.type === "nightLight"
                    buttonIcon: "light_mode"
                    text: Translation.tr("Show Night Light Enable Prompt")
                    checked: root.setting("showWhenOff", false)
                    onCheckedChanged: root.setSetting("showWhenOff", checked)
                    StyledToolTip { text: Translation.tr("Also show the Target while Night Light is off, to turn it on with a tap") }
                }

                // At a Glance categories
                ContentSubsectionLabel {
                    visible: root.kind === "target" && root.item.type === "glance"
                    text: Translation.tr("Show these Targets")
                }
                GridLayout {
                    Layout.fillWidth: true
                    visible: root.kind === "target" && root.item.type === "glance"
                    columns: 2
                    columnSpacing: 4
                    rowSpacing: 4
                    uniformCellWidths: true
                    Repeater {
                        model: root.item.type === "glance" ? AtAGlanceService.glanceCategories : []
                        delegate: ConfigSwitch {
                            id: category
                            required property var modelData
                            Layout.fillWidth: true
                            buttonIcon: category.modelData.icon
                            text: category.modelData.name
                            checked: !Array.from(root.setting("hidden", [])).includes(category.modelData.key)
                            onCheckedChanged: {
                                const hidden = Array.from(root.setting("hidden", [])).filter(k => k !== category.modelData.key);
                                if (!checked)
                                    hidden.push(category.modelData.key);
                                root.setSetting("hidden", hidden);
                            }
                            StyledToolTip { text: category.modelData.description }
                        }
                    }
                }
                ConfigSpinBox {
                    Layout.fillWidth: true
                    visible: root.kind === "target" && root.item.type === "glance"
                    icon: "sports_soccer"
                    text: Translation.tr("Show matches starting within (hours)")
                    from: 0
                    to: 72
                    stepSize: 1
                    value: root.setting("sportsWindowHours", 12)
                    onValueChanged: root.setSetting("sportsWindowHours", value)
                }

                // Complications
                ConfigSwitch {
                    Layout.fillWidth: true
                    visible: root.kind === "complication" && root.item.type === "weather"
                    buttonIcon: "description"
                    text: Translation.tr("Show condition")
                    checked: root.setting("showCondition", false)
                    onCheckedChanged: root.setSetting("showCondition", checked)
                    StyledToolTip { text: Translation.tr("Add the weather description after the temperature") }
                }
                ConfigSpinBox {
                    Layout.fillWidth: true
                    visible: root.kind === "complication" && root.item.type === "alarm"
                    icon: "alarm"
                    text: Translation.tr("Show alarms within (hours)")
                    from: 1
                    to: 24
                    stepSize: 1
                    value: root.setting("hoursAhead", 12)
                    onValueChanged: root.setSetting("hoursAhead", value)
                }
                ConfigSwitch {
                    Layout.fillWidth: true
                    visible: root.kind === "complication" && root.item.type === "alarm"
                    buttonIcon: "smartphone"
                    text: Translation.tr("Include phone alarms")
                    checked: root.setting("includePhone", true)
                    onCheckedChanged: root.setSetting("includePhone", checked)
                    StyledToolTip { text: Translation.tr("Also consider the next alarm set on your phone") }
                }
                ConfigTextField {
                    Layout.fillWidth: true
                    visible: root.kind === "complication" && (root.item.type === "sms" || root.item.type === "missedCalls")
                    icon: "apps"
                    text: Translation.tr("Phone apps")
                    tooltip: Translation.tr("Names of the phone apps to count notifications from, separated by commas")
                    inputText: String(root.setting("apps", ""))
                    textField.onEditingFinished: root.setSetting("apps", textField.text.trim())
                }
                ConfigSwitch {
                    Layout.fillWidth: true
                    visible: root.kind === "complication" && root.item.type === "battery"
                    buttonIcon: "battery_alert"
                    text: Translation.tr("Only when low")
                    checked: root.setting("onlyWhenLow", false)
                    onCheckedChanged: root.setSetting("onlyWhenLow", checked)
                    StyledToolTip { text: Translation.tr("Show the battery level only below the low battery threshold") }
                }

                // Dismissed lists
                RippleButtonWithIcon {
                    visible: root.kind === "target" && (root.item.type === "calendar" || root.item.type === "music")
                    readonly property string key: root.item.type === "calendar" ? "dismissedEvents" : "dismissedApps"
                    readonly property int dismissedCount: Array.from(root.setting(key, [])).length
                    enabled: dismissedCount > 0
                    materialIcon: "restart_alt"
                    mainText: root.item.type === "calendar"
                        ? Translation.tr("Clear Dismissed Events (%1)").arg(dismissedCount)
                        : Translation.tr("Clear Dismissed Apps (%1)").arg(dismissedCount)
                    onClicked: root.setSetting(key, [])
                    StyledToolTip {
                        text: root.item.type === "calendar"
                            ? Translation.tr("Reset the list of dismissed events, allowing hidden events to show again if they are still valid")
                            : Translation.tr("Clear the list of apps that have been dismissed, allowing their tracks to appear again")
                    }
                }
            }

            // ── Where it shows ─────────────────────────────────────────────────
            ContentSubsectionLabel {
                text: Translation.tr("Show on")
            }
            ConfigRow {
                Layout.fillWidth: true
                uniform: true
                ConfigSwitch {
                    buttonIcon: "desktop_windows"
                    text: Translation.tr("Desktop")
                    checked: root.item.showOnDesktop !== false
                    onCheckedChanged: root.set("showOnDesktop", checked)
                    StyledToolTip { text: Translation.tr("Show on the desktop widget") }
                }
                ConfigSwitch {
                    buttonIcon: "lock"
                    text: Translation.tr("Lock Screen")
                    checked: root.item.showOnLock !== false
                    onCheckedChanged: root.set("showOnLock", checked)
                    StyledToolTip { text: Translation.tr("Show while the screen is locked") }
                }
            }
            ConfigSwitch {
                Layout.fillWidth: true
                visible: root.kind === "target" && root.item.type === "calendar"
                buttonIcon: "remove_circle_outline"
                text: Translation.tr("Disable Sub-Complication")
                checked: root.item.disableSubComplication === true
                onCheckedChanged: root.set("disableSubComplication", checked)
                StyledToolTip { text: Translation.tr("Don't show the Target's own complication (the event location) next to its subtitle") }
            }

            // ── Requirements ───────────────────────────────────────────────────
            Repeater {
                model: [
                    { group: "requireAll", title: Translation.tr("All of"), hint: Translation.tr("Show only when all of these are met") },
                    { group: "requireAny", title: Translation.tr("Any of"), hint: Translation.tr("Show when at least one of these is met") }
                ]
                delegate: ColumnLayout {
                    id: groupColumn
                    required property var modelData
                    readonly property var requirements: AtAGlanceService.listOf(root.item[groupColumn.modelData.group])
                    Layout.fillWidth: true
                    spacing: 4

                    ContentSubsectionLabel {
                        text: Translation.tr("Requirements · %1").arg(groupColumn.modelData.title)
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: groupColumn.requirements.length === 0 ? Translation.tr("No requirements. %1").arg(groupColumn.modelData.hint) : groupColumn.modelData.hint
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        wrapMode: Text.WordWrap
                    }
                    Repeater {
                        model: groupColumn.requirements.length
                        delegate: AtAGlanceRequirementRow {
                            required property int index
                            requirement: groupColumn.requirements[index] ?? ({})
                            onChanged: req => {
                                const next = groupColumn.requirements.slice();
                                next[index] = req;
                                root.setRequirements(groupColumn.modelData.group, next);
                            }
                            onRemoved: {
                                const next = groupColumn.requirements.slice();
                                next.splice(index, 1);
                                root.setRequirements(groupColumn.modelData.group, next);
                            }
                        }
                    }
                    StyledComboBox {
                        Layout.fillWidth: true
                        buttonIcon: "add"
                        textRole: "displayName"
                        model: [{ displayName: Translation.tr("Add requirement…"), type: "" }].concat(
                            AtAGlanceService.requirementTypes.map(t => ({ displayName: t.name, type: t.type })))
                        currentIndex: 0
                        onActivated: index => {
                            const type = model[index]?.type ?? "";
                            currentIndex = 0;
                            if (type === "")
                                return;
                            const next = groupColumn.requirements.slice();
                            next.push(AtAGlanceService.newRequirement(type));
                            root.setRequirements(groupColumn.modelData.group, next);
                        }
                    }
                }
            }
        }
    }
}
