pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Dialogs
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * Creating or editing a reminder, in the side sheet — Samsung Reminder's editor laid out
 * the way the alarm editor is: the title, then when (date, time or all day, repeat, early
 * alert, alert level), then what (checklist, notes, attachments), then where it is filed
 * (category, Important).
 *
 * Works on a draft; nothing reaches RemindersService until Save (or Ctrl+Enter).
 */
ClockSheet {
    id: root

    /// The reminder being edited, or "" for a new one.
    property string reminderId: ""
    /// Fields a new reminder starts with: a template, the quick-add text, the open category.
    property var initialDraft: null

    readonly property bool editing: root.reminderId.length > 0
    readonly property var reminder: root.editing ? RemindersService.reminder(root.reminderId) : null

    // ── Draft ───────────────────────────────────────────────────────────
    property bool hasSchedule: false
    property string draftDate: ""
    property string draftTime: ""
    property var draftRepeat: null
    property var draftEarly: null
    property string draftAlert: "default"
    property string draftCategory: "default"
    property bool draftImportant: false
    property var draftChecklist: []
    property var draftAttachments: []
    /// Which fold is open below the schedule rows: "repeat", "early" or "".
    property string expanded: ""
    property bool addingLink: false
    property bool addingCategory: false
    /// Set by the first save: Ctrl+Enter in a field reaches both the field and the sheet.
    property bool saved: false

    readonly property var draftDay: root.draftDate.length > 0 ? ClockFormat.parseDay(root.draftDate) : new Date()
    readonly property bool allDay: root.draftTime.length === 0
    readonly property var suggestions: titleField.input.activeFocus && !root.editing
        ? RemindersService.recent.length > 0 || RemindersService.reminders.length > 0
            ? root.suggestionsFor(titleField.text) : []
        : []

    function suggestionsFor(text) {
        const pool = RemindersService.recent.concat(RemindersService.reminders.map(item => item.title));
        const needle = String(text ?? "").trim().toLowerCase();
        if (needle.length < 2)
            return [];
        const seen = {};
        return pool.filter(title => {
            const lower = String(title).toLowerCase();
            if (seen[lower] || lower === needle || !lower.includes(needle))
                return false;
            seen[lower] = true;
            return true;
        }).slice(0, 4);
    }

    function load(): void {
        const source = root.editing ? root.reminder : (root.initialDraft ?? {});
        titleField.text = String(source?.title ?? "");
        notesArea.text = String(source?.notes ?? "");
        const schedule = source?.schedule ?? null;
        root.hasSchedule = schedule !== null && schedule !== undefined && String(schedule.date ?? "").length > 0;
        root.draftDate = root.hasSchedule ? String(schedule.date) : "";
        root.draftTime = root.hasSchedule ? String(schedule.time ?? "") : "";
        root.draftRepeat = root.hasSchedule && schedule.repeat ? JSON.parse(JSON.stringify(schedule.repeat)) : null;
        root.draftEarly = source?.early ? JSON.parse(JSON.stringify(source.early)) : null;
        root.draftAlert = String(source?.alert ?? "default");
        root.draftCategory = String(source?.categoryId ?? Config.options.clockApp.reminders.defaultCategory ?? "default");
        if (!RemindersService.categories.some(category => category.id === root.draftCategory))
            root.draftCategory = "default";
        root.draftImportant = Boolean(source?.important);
        root.draftChecklist = Array.from(source?.checklist ?? []).map((item, index) => ({
            id: String(item.id ?? ("c" + index)), text: String(item.text ?? ""), done: Boolean(item.done)
        }));
        root.draftAttachments = Array.from(source?.attachments ?? []).map(item => Object.assign({}, item));
    }

    function newId(prefix: string): string {
        return prefix + Date.now().toString(36) + Math.random().toString(36).slice(2, 6);
    }

    // ── When ────────────────────────────────────────────────────────────
    function setSchedule(on: bool): void {
        root.hasSchedule = on;
        if (on && root.draftDate.length === 0)
            root.setWhen(root.inMinutes(60), false);
        if (!on)
            root.expanded = "";
    }

    function inMinutes(minutes: int): var {
        return new Date(Date.now() + minutes * 60000);
    }

    /** One preset: in an hour, this evening, tomorrow morning, next week. */
    function at(dayOffset: int, hour: int, minute: int): var {
        const now = new Date();
        return new Date(now.getFullYear(), now.getMonth(), now.getDate() + dayOffset, hour, minute);
    }

    function setWhen(date, allDay: bool): void {
        root.hasSchedule = true;
        root.draftDate = Qt.formatDate(date, "yyyy-MM-dd");
        root.draftTime = allDay ? "" : Qt.formatTime(date, "HH:mm");
    }

    readonly property var presets: {
        const now = new Date();
        const evening = now.getHours() >= 20 ? root.at(1, 20, 0) : root.at(0, 20, 0);
        const mondayShift = (8 - now.getDay()) % 7 || 7;
        return [
            { label: Translation.tr("In 1 hour"), symbol: "more_time", at: root.inMinutes(60) },
            { label: now.getHours() >= 20 ? Translation.tr("Tomorrow evening") : Translation.tr("This evening"), symbol: "nights_stay", at: evening },
            { label: Translation.tr("Tomorrow morning"), symbol: "wb_twilight", at: root.at(1, 9, 0) },
            { label: Translation.tr("Next week"), symbol: "date_range", at: root.at(mondayShift, 9, 0) }
        ];
    }

    function pickDate(): void {
        root.host?.pickers?.pickDate(root.draftDay, Translation.tr("Remind me on"),
            date => root.draftDate = Qt.formatDate(date, "yyyy-MM-dd"));
    }

    /// Picking a time on an all-day reminder gives it that time: the tile is the way out.
    function pickTime(): void {
        const parts = (root.draftTime || RemindersService.allDayTime || "09:00").split(":").map(Number);
        root.host?.pickers?.pickTime(parts[0] || 0, parts[1] || 0, Translation.tr("Remind me at"),
            (hour, minute) => root.draftTime = ClockFormat.pad(hour) + ":" + ClockFormat.pad(minute));
    }

    function earlyLabel(early): string {
        if (!early)
            return Translation.tr("Off");
        if (early.kind === "day")
            return Translation.tr("1 day before");
        if (early.kind === "week")
            return Translation.tr("1 week before");
        const date = new Date(early.at);
        return Qt.locale().toString(date, "ddd, d MMM") + " " + ClockFormat.dateTime(date);
    }

    function pickEarly(): void {
        const due = root.hasSchedule ? ClockFormat.parseDay(root.draftDate) : new Date();
        const start = root.draftEarly?.kind === "custom" ? new Date(root.draftEarly.at)
            : new Date(due.getFullYear(), due.getMonth(), due.getDate() - 1, 9, 0);
        root.host?.pickers?.pickDate(start, Translation.tr("Early alert on"), date => {
            root.host?.pickers?.pickTime(start.getHours(), start.getMinutes(), Translation.tr("Early alert at"), (hour, minute) => {
                root.draftEarly = { kind: "custom", at: new Date(date.getFullYear(), date.getMonth(), date.getDate(), hour, minute).getTime() };
            });
        });
    }

    // ── What ────────────────────────────────────────────────────────────
    function addChecklistItem(text: string): void {
        const value = text.trim();
        if (value.length === 0)
            return;
        root.draftChecklist = root.draftChecklist.concat([{ id: root.newId("c"), text: value, done: false }]);
    }

    function editChecklistItem(id: string, fields): void {
        root.draftChecklist = root.draftChecklist.map(item => item.id === id ? Object.assign({}, item, fields) : item);
    }

    function removeChecklistItem(id: string): void {
        root.draftChecklist = root.draftChecklist.filter(item => item.id !== id);
    }

    function moveChecklistItem(id: string, delta: int): void {
        const list = root.draftChecklist.slice();
        const index = list.findIndex(item => item.id === id);
        const target = index + delta;
        if (index < 0 || target < 0 || target >= list.length)
            return;
        const moved = list.splice(index, 1)[0];
        list.splice(target, 0, moved);
        root.draftChecklist = list;
    }

    function addAttachment(attachment): void {
        root.draftAttachments = root.draftAttachments.concat([Object.assign({ id: root.newId("a") }, attachment)]);
    }

    function removeAttachment(id: string): void {
        root.draftAttachments = root.draftAttachments.filter(item => item.id !== id);
    }

    function addLink(text: string): void {
        let url = text.trim();
        if (url.length === 0)
            return;
        if (!/^[a-z][a-z0-9+.-]*:/i.test(url))
            url = "https://" + url;
        root.addAttachment({ kind: "link", url: url, name: "" });
        root.addingLink = false;
    }

    function fields() {
        return {
            title: titleField.text.trim(),
            notes: notesArea.text.trim(),
            categoryId: root.draftCategory,
            important: root.draftImportant,
            checklist: root.draftChecklist.filter(item => item.text.trim().length > 0),
            attachments: root.draftAttachments,
            schedule: root.hasSchedule ? {
                date: root.draftDate,
                time: root.draftTime,
                repeat: root.draftRepeat,
                occurrence: root.reminder?.schedule?.occurrence ?? 0
            } : null,
            early: root.hasSchedule ? root.draftEarly : null,
            alert: root.draftAlert
        };
    }

    function save(): void {
        if (root.saved)
            return;
        const fields = root.fields();
        if (fields.title.length === 0 && fields.checklist.length === 0 && fields.notes.length === 0) {
            titleField.focusInput();
            return;
        }
        root.saved = true;
        if (root.editing)
            RemindersService.update(root.reminderId, fields);
        else
            RemindersService.create(fields);
        root.close();
    }

    title: root.editing ? Translation.tr("Edit reminder") : Translation.tr("New reminder")
    subtitle: root.editing && root.reminder
        ? (root.reminder.completed ? Translation.tr("Completed") : RemindersService.whenText(root.reminder, new Date()))
        : ""

    Component.onCompleted: {
        root.load();
        Qt.callLater(() => {
            if (!root.editing)
                titleField.focusInput();
        });
    }

    // A reminder deleted or completed elsewhere while its sheet is open.
    Connections {
        target: RemindersService
        function onRemindersChanged() {
            if (root.editing && !RemindersService.reminder(root.reminderId))
                root.close();
        }
    }

    Keys.onPressed: event => {
        if ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
            root.save();
            event.accepted = true;
        }
    }

    headerActions: [
        ClockIconButton {
            visible: root.editing
            symbol: root.reminder?.completed ? "undo" : "check_circle"
            size: 38
            iconSize: Appearance.font.pixelSize.larger
            tooltip: root.reminder?.completed ? Translation.tr("Restore") : Translation.tr("Complete")
            onClicked: {
                RemindersService.toggleComplete(root.reminderId);
                root.close();
            }
        },
        ClockIconButton {
            visible: root.editing
            symbol: "content_copy"
            size: 38
            iconSize: Appearance.font.pixelSize.larger
            tooltip: Translation.tr("Duplicate")
            onClicked: {
                RemindersService.duplicate(root.reminderId);
                root.close();
            }
        },
        ClockIconButton {
            visible: root.editing
            symbol: "delete"
            size: 38
            iconSize: Appearance.font.pixelSize.larger
            colIcon: ClockStyle.colError
            tooltip: Translation.tr("Move to recycle bin")
            onClicked: {
                const id = root.reminderId;
                root.reminderId = "";
                RemindersService.trash([id]);
                root.close();
            }
        }
    ]

    // ── Title ───────────────────────────────────────────────────────────
    ClockFormField {
        id: titleField
        symbol: "edit_note"
        caption: Translation.tr("Reminder")
        placeholder: Translation.tr("What do you want to remember?")
        onAccepted: root.save()
    }

    // Past reminders, to reuse their wording (Samsung's search suggestions).
    Flow {
        Layout.fillWidth: true
        visible: root.suggestions.length > 0
        spacing: 6

        Repeater {
            model: root.suggestions

            SheetChip {
                required property string modelData
                symbol: "history"
                label: modelData
                height_: 30
                onClicked: titleField.text = modelData
            }
        }
    }

    // ── When ────────────────────────────────────────────────────────────
    ClockFormToggle {
        symbol: "event"
        shapeKind: MaterialShape.Shape.Cookie12Sided
        label: Translation.tr("Date and time")
        description: root.hasSchedule
            ? (Qt.locale().toString(root.draftDay, "dddd, d MMMM") + (root.allDay ? " · " + Translation.tr("All day") : " · " + ClockFormat.alarmTime(root.draftTime)))
            : Translation.tr("No alert: it waits in No alert until you're ready")
        checked: root.hasSchedule
        onToggled: checked => root.setSchedule(checked)
    }

    Flow {
        Layout.fillWidth: true
        spacing: 6

        Repeater {
            model: root.presets

            ClockFormChip {
                required property var modelData
                symbol: modelData.symbol
                label: modelData.label
                selected: root.hasSchedule && root.draftDate === Qt.formatDate(modelData.at, "yyyy-MM-dd")
                    && root.draftTime === Qt.formatTime(modelData.at, "HH:mm")
                onTriggered: root.setWhen(modelData.at, false)
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        visible: root.hasSchedule
        spacing: 10

        // The date and the time are the values this sheet is about, so they get the tall
        // tile in expressive digits rather than a row. Two tiles joined into one shape:
        // outer corners large, the seam between them tight.
        RowLayout {
            id: whenRow
            Layout.fillWidth: true
            Layout.preferredHeight: 124
            spacing: ClockStyle.gapTiny

            readonly property var timeParts: ClockFormat.alarmParts(root.allDay ? RemindersService.allDayTime
                : root.draftTime)
            /// One size for both tiles, from whichever has the least room, so the digits line up.
            readonly property int digitSize: Math.round(Math.max(28, Math.min(64, dateTile.heightLimit,
                dateTile.widthLimit, timeTile.widthLimit)))

            WhenTile {
                id: dateTile
                Layout.preferredWidth: Math.floor((whenRow.width - whenRow.spacing) * 0.4)
                leading: true
                symbol: "calendar_month"
                caption: Translation.tr("Date")
                digits: String(root.draftDay.getDate())
                digitEms: 1.2
                digitSize: whenRow.digitSize
                // "Today" and "Tomorrow" only: any other day's relative name repeats the date.
                footer: {
                    const today = new Date(new Date().setHours(0, 0, 0, 0));
                    const days = Math.round((root.draftDay.getTime() - today.getTime()) / 86400000);
                    const name = days === 0 || days === 1 ? ClockFormat.relativeDay(root.draftDay, new Date())
                        : Qt.locale().toString(root.draftDay, "ddd");
                    const month = Qt.locale().toString(root.draftDay,
                        root.draftDay.getFullYear() === today.getFullYear() ? "MMMM" : "MMM yyyy");
                    return name + " · " + month;
                }
                onTriggered: root.pickDate()
            }

            WhenTile {
                id: timeTile
                Layout.fillWidth: true
                leading: false
                symbol: "schedule"
                caption: root.allDay ? Translation.tr("All day") : Translation.tr("Time")
                digits: whenRow.timeParts.hours + ":" + whenRow.timeParts.minutes
                suffix: whenRow.timeParts.meridiem
                // An all-day reminder alerts at the settings' time: shown in the light axes
                // until a time of its own is picked.
                boldness: root.allDay ? 0 : 1
                digitEms: 2.4 + (whenRow.timeParts.meridiem.length > 0 ? 0.8 : 0)
                digitSize: whenRow.digitSize
                footer: Translation.tr("%1 alert").arg(RemindersStyle.alertLevel(root.draftAlert === "default"
                    ? RemindersService.defaultAlert : root.draftAlert).label)
                onTriggered: root.pickTime()
            }
        }

        ClockFormToggle {
            symbol: "wb_sunny"
            shapeKind: MaterialShape.Shape.SoftBurst
            label: Translation.tr("All day")
            description: Translation.tr("Alerts at %1")
                .arg(ClockFormat.alarmTime(RemindersService.allDayTime))
            checked: root.allDay
            onToggled: checked => root.draftTime = checked ? "" : "09:00"
        }

        ClockFormPicker {
            symbol: "repeat"
            shapeKind: MaterialShape.Shape.Cookie9Sided
            caption: Translation.tr("Repeat")
            value: RemindersService.repeatText(root.draftRepeat ? normalizeRepeat(root.draftRepeat) : null)
            expanded: root.expanded === "repeat"
            onTriggered: root.expanded = root.expanded === "repeat" ? "" : "repeat"

            function normalizeRepeat(repeat) {
                return Object.assign({ interval: 1, weekdays: [], monthDays: [], yearDates: [], end: { kind: "never" } }, repeat);
            }
        }

        Loader {
            Layout.fillWidth: true
            Layout.leftMargin: 4
            active: root.expanded === "repeat"
            visible: active
            sourceComponent: ReminderRepeatEditor {
                repeat: root.draftRepeat
                startDate: root.draftDay
                pickers: root.host?.pickers ?? null
                onEdited: repeat => root.draftRepeat = repeat
            }
        }

        ClockFormPicker {
            symbol: "notification_add"
            shapeKind: MaterialShape.Shape.Cookie6Sided
            caption: Translation.tr("Early alert")
            value: root.earlyLabel(root.draftEarly)
            expanded: root.expanded === "early"
            onTriggered: root.expanded = root.expanded === "early" ? "" : "early"
        }

        Flow {
            Layout.fillWidth: true
            Layout.leftMargin: 4
            visible: root.expanded === "early"
            spacing: 6

            Repeater {
                model: [
                    { id: "", label: Translation.tr("Off") },
                    { id: "day", label: Translation.tr("1 day before") },
                    { id: "week", label: Translation.tr("1 week before") },
                    { id: "custom", label: Translation.tr("Custom…") }
                ]

                ClockFormChip {
                    required property var modelData
                    label: modelData.label
                    selected: (root.draftEarly?.kind ?? "") === modelData.id
                    onTriggered: {
                        if (modelData.id === "custom")
                            root.pickEarly();
                        else
                            root.draftEarly = modelData.id.length > 0 ? { kind: modelData.id, at: 0 } : null;
                    }
                }
            }
        }

        // ── Alert level ─────────────────────────────────────────────────
        StyledText {
            Layout.topMargin: 2
            text: Translation.tr("Alert type")
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.Bold
            color: ClockStyle.colOnSurfaceVariant
        }

        Flow {
            Layout.fillWidth: true
            spacing: 6

            ClockFormChip {
                label: Translation.tr("Default (%1)").arg(RemindersStyle.alertLevel(RemindersService.defaultAlert).label)
                selected: root.draftAlert === "default"
                onTriggered: root.draftAlert = "default"
            }

            Repeater {
                model: RemindersStyle.alertLevels

                ClockFormChip {
                    required property var modelData
                    symbol: modelData.icon
                    label: modelData.label
                    selected: root.draftAlert === modelData.id
                    onTriggered: root.draftAlert = modelData.id
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            text: RemindersStyle.alertLevel(root.draftAlert === "default" ? RemindersService.defaultAlert : root.draftAlert).description
            wrapMode: Text.Wrap
            font.pixelSize: ClockStyle.textSmall
            color: ClockStyle.colSubtext
        }
    }

    // ── Checklist ───────────────────────────────────────────────────────
    SectionLabel {
        text: Translation.tr("Checklist")
    }

    Repeater {
        model: root.draftChecklist

        Rectangle {
            id: itemRow
            required property var modelData
            required property int index
            Layout.fillWidth: true
            implicitHeight: 44
            radius: Appearance.rounding.small
            color: itemInput.activeFocus ? ClockStyle.colFieldHover : ClockStyle.colField

            Behavior on color {
                enabled: !ClockStyle.reducedMotion
                animation: ClockStyle.motionFast.colorAnimation.createObject(this)
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 4
                spacing: 6

                ReminderCheck {
                    size: 20
                    checked: itemRow.modelData.done
                    colAccent: RemindersStyle.categoryColor(root.draftCategory)
                    onToggled: root.editChecklistItem(itemRow.modelData.id, { done: !itemRow.modelData.done })
                }

                StyledTextInput {
                    id: itemInput
                    Layout.fillWidth: true
                    text: itemRow.modelData.text
                    clip: true
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.strikeout: itemRow.modelData.done
                    color: ClockStyle.colOnSurface
                    onEditingFinished: {
                        if (itemInput.text !== itemRow.modelData.text)
                            root.editChecklistItem(itemRow.modelData.id, { text: itemInput.text });
                    }
                }

                ClockIconButton {
                    visible: itemRow.index > 0
                    symbol: "arrow_upward"
                    size: 30
                    iconSize: ClockStyle.iconSmall
                    tooltip: Translation.tr("Move up")
                    onClicked: root.moveChecklistItem(itemRow.modelData.id, -1)
                }

                ClockIconButton {
                    symbol: "close"
                    size: 30
                    iconSize: ClockStyle.iconSmall
                    tooltip: Translation.tr("Remove")
                    onClicked: root.removeChecklistItem(itemRow.modelData.id)
                }
            }
        }
    }

    ClockFormField {
        id: checklistField
        symbol: "add_task"
        shapeKind: MaterialShape.Shape.Cookie4Sided
        caption: Translation.tr("Add item")
        placeholder: Translation.tr("Milk, eggs, the charger…")
        onAccepted: {
            root.addChecklistItem(checklistField.text);
            checklistField.text = "";
        }
    }

    // ── Notes ───────────────────────────────────────────────────────────
    // A form row grown to hold paragraphs. Its shape changes into another while the
    // notes have focus, instead of turning.
    Rectangle {
        Layout.fillWidth: true
        Layout.topMargin: 6
        implicitHeight: Math.max(76, notesColumn.implicitHeight + 20)
        radius: Appearance.rounding.small
        color: notesArea.activeFocus ? ClockStyle.colFieldHover : ClockStyle.colField

        Behavior on color {
            enabled: !ClockStyle.reducedMotion
            animation: ClockStyle.motionFast.colorAnimation.createObject(this)
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.IBeamCursor
            onClicked: notesArea.forceActiveFocus()
        }

        RowLayout {
            anchors {
                fill: parent
                leftMargin: 10
                rightMargin: 12
                topMargin: 10
                bottomMargin: 10
            }
            spacing: 10

            MaterialShapeWrappedMaterialSymbol {
                Layout.alignment: Qt.AlignTop
                text: "notes"
                iconSize: 18
                padding: 9
                // The morph is motion too: with reduced motion the shape stays put.
                shape: notesArea.activeFocus && !ClockStyle.reducedMotion
                    ? MaterialShape.Shape.Flower : MaterialShape.Shape.Clover4Leaf
                color: ClockStyle.colPrimaryContainer
                colSymbol: ClockStyle.colOnPrimaryContainer
            }

            ColumnLayout {
                id: notesColumn
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Notes")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.Bold
                    color: ClockStyle.colOnSurfaceVariant
                }

                StyledTextArea {
                    id: notesArea
                    Layout.fillWidth: true
                    padding: 0
                    topPadding: 2
                    wrapMode: TextEdit.Wrap
                    placeholderText: Translation.tr("Add notes")
                    background: null
                    color: ClockStyle.colOnSurface

                    // Return makes a new line here, so the save shortcut is caught first.
                    Keys.onPressed: event => {
                        if ((event.modifiers & Qt.ControlModifier)
                                && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
                            root.save();
                            event.accepted = true;
                        }
                    }
                }
            }
        }
    }

    // ── Attachments ─────────────────────────────────────────────────────
    SectionLabel {
        text: Translation.tr("Attachments")
    }

    Flow {
        Layout.fillWidth: true
        visible: root.draftAttachments.some(item => item.kind === "image")
        spacing: 6

        Repeater {
            model: root.draftAttachments.filter(item => item.kind === "image")

            Rectangle {
                id: imageTile
                required property var modelData
                width: 76
                height: 76
                radius: ClockStyle.radiusSmall
                color: ClockStyle.colField
                clip: true

                StyledImage {
                    anchors.fill: parent
                    source: "file://" + imageTile.modelData.path
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: 152
                    sourceSize.height: 152
                    asynchronous: true
                }

                ClockIconButton {
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: 2
                    symbol: "close"
                    size: 26
                    iconSize: 16
                    colBackground: ColorUtils.applyAlpha(ClockStyle.colSurface, 0.85)
                    tooltip: Translation.tr("Remove")
                    onClicked: root.removeAttachment(imageTile.modelData.id)
                }
            }
        }
    }

    Repeater {
        model: root.draftAttachments.filter(item => item.kind !== "image")

        ClockFormPicker {
            id: attachRow
            required property var modelData
            symbol: modelData.kind === "link" ? "link" : "draft"
            shapeKind: modelData.kind === "link" ? MaterialShape.Shape.Puffy : MaterialShape.Shape.Gem
            caption: modelData.kind === "link" ? Translation.tr("Link") : Translation.tr("File")
            value: modelData.kind === "link" ? modelData.url : (modelData.name || modelData.path)
            showChevron: false
            onTriggered: Qt.openUrlExternally(modelData.kind === "link" ? modelData.url : "file://" + modelData.path)

            ClockIconButton {
                symbol: "close"
                size: 32
                iconSize: Appearance.font.pixelSize.large
                tooltip: Translation.tr("Remove")
                onClicked: root.removeAttachment(attachRow.modelData.id)
            }
        }
    }

    ClockFormField {
        id: linkField
        visible: root.addingLink
        symbol: "add_link"
        shapeKind: MaterialShape.Shape.PuffyDiamond
        caption: Translation.tr("Link")
        placeholder: "https://"
        onAccepted: {
            root.addLink(linkField.text);
            linkField.text = "";
        }
    }

    // Actions, not choices: filled assist chips one step up from the sheet, where the
    // dashed chips above are things to pick.
    Flow {
        Layout.fillWidth: true
        spacing: 6

        SheetChip {
            symbol: "add_photo_alternate"
            label: Translation.tr("Image")
            enabled: root.draftAttachments.filter(item => item.kind === "image").length < 8
            onClicked: {
                dialogLoader.kind = "image";
                dialogLoader.active = true;
            }
        }

        SheetChip {
            symbol: "attach_file"
            label: Translation.tr("File")
            onClicked: {
                dialogLoader.kind = "file";
                dialogLoader.active = true;
            }
        }

        SheetChip {
            symbol: "add_link"
            label: Translation.tr("Link")
            selected: root.addingLink
            onClicked: {
                root.addingLink = !root.addingLink;
                if (root.addingLink)
                    Qt.callLater(linkField.focusInput);
            }
        }
    }

    // ── Filed under ─────────────────────────────────────────────────────
    SectionLabel {
        text: Translation.tr("Category")
    }

    Flow {
        Layout.fillWidth: true
        spacing: 6

        Repeater {
            model: RemindersService.categories

            CategoryChip {
                required property var modelData
                category: modelData
            }
        }

        SheetChip {
            symbol: "add"
            label: Translation.tr("New category")
            selected: root.addingCategory
            onClicked: {
                root.addingCategory = !root.addingCategory;
                if (root.addingCategory)
                    Qt.callLater(categoryField.focusInput);
            }
        }
    }

    ClockFormField {
        id: categoryField
        visible: root.addingCategory
        symbol: "create_new_folder"
        shapeKind: MaterialShape.Shape.Pentagon
        caption: Translation.tr("Category name")
        placeholder: Translation.tr("Home, Work, Shopping…")
        onAccepted: {
            const color = RemindersStyle.palette[RemindersService.categories.length % RemindersStyle.palette.length];
            const id = RemindersService.addCategory(categoryField.text, color, "list");
            if (id.length > 0)
                root.draftCategory = id;
            categoryField.text = "";
            root.addingCategory = false;
        }
    }

    ClockFormToggle {
        symbol: "star"
        shapeKind: MaterialShape.Shape.Sunny
        label: Translation.tr("Important")
        description: Translation.tr("Starred, and listed under Important")
        checked: root.draftImportant
        onToggled: checked => root.draftImportant = checked
    }

    actions: [
        ClockSheetAction {
            label: Translation.tr("Cancel")
            symbol: "close"
            onClicked: root.close()
        },
        ClockSheetAction {
            primary: true
            label: root.editing ? Translation.tr("Save changes") : Translation.tr("Save")
            symbol: "check"
            onClicked: root.save()
        }
    ]

    // The portal file chooser, built only while picking.
    Loader {
        id: dialogLoader
        property string kind: "image"
        active: false
        sourceComponent: FileDialog {
            title: dialogLoader.kind === "image" ? Translation.tr("Add an image") : Translation.tr("Attach a file")
            nameFilters: dialogLoader.kind === "image"
                ? [Translation.tr("Images (*.png *.jpg *.jpeg *.webp *.gif *.bmp *.avif)")]
                : [Translation.tr("All files (*)")]
            onAccepted: {
                const path = decodeURIComponent(selectedFile.toString().replace(/^file:\/\//, ""));
                if (dialogLoader.kind === "image") {
                    RemindersService.importImage(path, copy => {
                        if (copy.length > 0)
                            root.addAttachment({ kind: "image", path: copy, name: path.slice(path.lastIndexOf("/") + 1) });
                    });
                } else {
                    root.addAttachment({ kind: "file", path: path, name: path.slice(path.lastIndexOf("/") + 1) });
                }
                dialogLoader.active = false;
            }
            onRejected: dialogLoader.active = false
            Component.onCompleted: open()
        }
    }

    component SectionLabel: StyledText {
        Layout.topMargin: 6
        font.pixelSize: Appearance.font.pixelSize.smaller
        font.weight: Font.Bold
        color: ClockStyle.colOnSurfaceVariant
    }

    /// An action chip on the sheet: filled one step up the ladder, so it doesn't vanish into
    /// the sheet's own colour the way the page-level chip's surface does.
    component SheetChip: ClockChip {
        colIdle: ClockStyle.colField
        colIdleHover: ClockStyle.colFieldHover
    }

    /// The form chip's vocabulary (dashed until chosen) in the category's own colour: the
    /// chosen one fills with a tint of it and squares off.
    component CategoryChip: RippleButton {
        id: chip
        property var category
        readonly property bool on: root.draftCategory === chip.category.id
        readonly property color colAccent: chip.category.color.length > 0 ? chip.category.color : ClockStyle.colPrimary

        implicitHeight: 34
        implicitWidth: chipRow.implicitWidth + 24
        buttonRadius: chip.on ? ClockStyle.radiusSmall : ClockStyle.pill(chip.height)
        colBackground: chip.on ? ColorUtils.applyAlpha(chip.colAccent, 0.3) : "transparent"
        colBackgroundHover: ColorUtils.applyAlpha(chip.colAccent, chip.on ? 0.38 : 0.08)
        colRipple: ColorUtils.applyAlpha(chip.colAccent, 0.45)
        onClicked: root.draftCategory = chip.category.id

        DashedBorder {
            anchors.fill: parent
            visible: !chip.on
            color: ColorUtils.applyAlpha(Appearance.colors.colOutline, 0.8)
            borderWidth: 1
            dashLength: 4
            gapLength: 3
            radius: ClockStyle.pill(chip.height)
        }

        contentItem: Item {
            RowLayout {
                id: chipRow
                anchors.centerIn: parent
                spacing: 6

                MaterialSymbol {
                    text: chip.on ? "check" : chip.category.icon
                    iconSize: ClockStyle.iconSmall
                    color: chip.colAccent
                }

                StyledText {
                    text: RemindersService.categoryName(chip.category.id)
                    font.pixelSize: ClockStyle.textNormal
                    font.weight: Font.DemiBold
                    color: ClockStyle.colOnSurface
                }
            }
        }
    }

    /// One half of the date/time tile: a caption, the value in expressive digits, a footer.
    /// The whole tile opens its picker and fills with the primary container under the pointer.
    component WhenTile: Rectangle {
        id: tile

        property string symbol: ""
        property string caption: ""
        property string digits: ""
        property string suffix: ""
        property string footer: ""
        /// 0 = the light, inactive axes, 1 = the bold ones; interpolated, never swapped.
        property real boldness: 1
        /// About how many ems the digits take, for the size the width allows.
        property real digitEms: 1
        property int digitSize: 48
        /// The tile on the left: large outer corners on that side, the tight seam on the other.
        property bool leading: true

        readonly property bool hovered: tilePointer.containsMouse
        readonly property color colContent: tile.hovered ? ClockStyle.colOnPrimaryContainer
            : ClockStyle.colOnSurface
        readonly property color colCaption: tile.hovered ? ClockStyle.colOnPrimaryContainer
            : ClockStyle.colOnSurfaceVariant
        readonly property real widthLimit: (tile.width - 24) / tile.digitEms
        readonly property real heightLimit: digitBox.height / 1.2
        readonly property real seam: Appearance.rounding.verysmall

        signal triggered()

        Layout.fillHeight: true
        topLeftRadius: tile.leading ? ClockStyle.radiusLarge : tile.seam
        bottomLeftRadius: tile.leading ? ClockStyle.radiusLarge : tile.seam
        topRightRadius: tile.leading ? tile.seam : ClockStyle.radiusLarge
        bottomRightRadius: tile.leading ? tile.seam : ClockStyle.radiusLarge
        color: tile.hovered ? ClockStyle.colPrimaryContainer : ClockStyle.colField

        Behavior on color {
            enabled: !ClockStyle.reducedMotion
            animation: ClockStyle.motionFast.colorAnimation.createObject(this)
        }
        Behavior on boldness {
            enabled: !ClockStyle.reducedMotion
            animation: ClockStyle.motionDefault.numberAnimation.createObject(this)
        }

        MouseArea {
            id: tilePointer
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tile.triggered()
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                spacing: 5

                MaterialSymbol {
                    text: tile.symbol
                    iconSize: Appearance.font.pixelSize.smallie
                    color: tile.colCaption
                }

                StyledText {
                    Layout.fillWidth: true
                    text: tile.caption
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.Bold
                    color: tile.colCaption
                    elide: Text.ElideRight
                }
            }

            Item {
                id: digitBox
                Layout.fillWidth: true
                Layout.fillHeight: true

                RowLayout {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4

                    StyledText {
                        Layout.alignment: Qt.AlignBaseline
                        text: tile.digits
                        font.family: ClockStyle.fontMain
                        font.variableAxes: ({
                                "wght": 560 + 200 * tile.boldness,
                                "wdth": 30 + 10 * tile.boldness,
                                "ROND": 100
                            })
                        font.pixelSize: tile.digitSize
                        color: tile.colContent
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignBaseline
                        visible: tile.suffix.length > 0
                        text: tile.suffix
                        font.family: ClockStyle.fontMain
                        font.variableAxes: ClockStyle.axesDigits
                        font.pixelSize: Math.round(tile.digitSize * 0.34)
                        color: tile.colContent
                    }
                }
            }

            StyledText {
                id: footerText
                Layout.fillWidth: true
                text: tile.footer
                font.pixelSize: ClockStyle.textSmall
                color: tile.colContent
                opacity: 0.8
                elide: Text.ElideRight

                HoverHandler {
                    id: footerHover
                }
                StyledToolTip {
                    extraVisibleCondition: footerHover.hovered && footerText.truncated
                    text: footerText.text
                }
            }
        }
    }
}
