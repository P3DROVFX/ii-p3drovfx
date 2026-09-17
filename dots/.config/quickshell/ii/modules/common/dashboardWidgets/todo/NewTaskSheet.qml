import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services

/**
 * The task creation form, filling the whole To-Do widget as a subpage.
 *
 * Field design is the EventSidebar recipe from the Cheatsheet Timetable:
 * filled rectangles on m3surfaceContainerHighest with rounding.small and no
 * outline, a cookie-shaped icon on colPrimaryContainer at the left, a small
 * bold caption above the value, and option pills that are filled when
 * selected and dashed when not.
 *
 * The form only draws the fields the active provider can actually store —
 * Todo.supports* is the contract, so a Google Tasks user never sees a
 * priority picker that would be dropped on the wire.
 */
Item {
    id: root
    objectName: "newTaskSheet"

    signal closeRequested()
    signal saved()
    signal controlPressed()
    signal controlReleased()
    property bool showShortcutHints: false
    readonly property bool datePickerOpen: datePicker.opened

    function reveal(item) {
        if (!item.activeFocus) return;
        const position = item.mapToItem(formColumn, 0, 0);
        const available = Math.max(1, formFlickable.height - root.fabSize - root.fabMargins * 2);
        if (position.y < formFlickable.contentY)
            formFlickable.contentY = Math.max(0, position.y);
        else if (position.y + item.height > formFlickable.contentY + available)
            formFlickable.contentY = Math.max(0, Math.min(formFlickable.contentHeight - formFlickable.height,
                position.y + item.height - available));
    }

    function openDatePicker() {
        datePicker.open(root.formHasDate ? root.formDate : null, Translation.tr("Due date"));
        datePicker.forceActiveFocus();
    }

    function releaseKey(event) {
        if (event.key === Qt.Key_Control || !(event.modifiers & Qt.ControlModifier))
            root.controlReleased();
    }

    function handleKey(event) {
        if (event.key === Qt.Key_Control || (event.modifiers & Qt.ControlModifier))
            root.controlPressed();
        if (root.datePickerOpen) {
            if (event.key === Qt.Key_Escape) {
                if (!event.isAutoRepeat) datePicker.dismiss();
                return true;
            }
            if (event.modifiers !== Qt.NoModifier) return false;
            let date = new Date(datePicker.selected);
            if (event.key === Qt.Key_Left) date.setDate(date.getDate() - 1);
            else if (event.key === Qt.Key_Right) date.setDate(date.getDate() + 1);
            else if (event.key === Qt.Key_Up) date.setDate(date.getDate() - 7);
            else if (event.key === Qt.Key_Down) date.setDate(date.getDate() + 7);
            else if (event.key === Qt.Key_PageUp) date = datePicker.addMonths(date, -1);
            else if (event.key === Qt.Key_PageDown) date = datePicker.addMonths(date, 1);
            else if (event.key === Qt.Key_Home) date = new Date();
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                if (!event.isAutoRepeat) datePicker.confirm();
                return true;
            } else return false;
            datePicker.selected = date;
            datePicker.viewYear = date.getFullYear();
            datePicker.viewMonth = date.getMonth();
            return true;
        }
        if (event.key === Qt.Key_Escape) {
            if (!event.isAutoRepeat) root.closeRequested();
            return true;
        }
        if (event.modifiers !== Qt.ControlModifier) return false;
        if (event.key >= Qt.Key_1 && event.key <= Qt.Key_3 && Todo.supportsDate) {
            if (!event.isAutoRepeat) {
                if (event.key === Qt.Key_1) root.formHasDate = false;
                else {
                    const date = new Date();
                    date.setDate(date.getDate() + (event.key === Qt.Key_3 ? 1 : 0));
                    root.selectDate(date);
                }
            }
            return true;
        }
        if (event.key >= Qt.Key_4 && event.key <= Qt.Key_7 && Todo.supportsPriority) {
            if (!event.isAutoRepeat) root.formPriority = root.priorityOptions[event.key - Qt.Key_4].value;
            return true;
        }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (!event.isAutoRepeat) root.save();
        } else if (event.key === Qt.Key_T) titleInput.forceActiveFocus();
        else if (event.key === Qt.Key_D && Todo.supportsDate) {
            if (!event.isAutoRepeat) root.openDatePicker();
        } else if (event.key === Qt.Key_P && Todo.supportsPriority) {
            if (!event.isAutoRepeat) {
                const index = root.priorityOptions.findIndex(option => option.value === root.formPriority);
                root.formPriority = root.priorityOptions[(index + 1) % root.priorityOptions.length].value;
                priorityRepeater.itemAt((index + 1) % root.priorityOptions.length)?.forceActiveFocus();
            }
        } else if (event.key === Qt.Key_G && Todo.supportsTags) tagInput.forceActiveFocus();
        else if (event.key === Qt.Key_O && Todo.supportsNotes) notesArea.forceActiveFocus();
        else return false;
        return true;
    }

    Keys.onPressed: event => { event.accepted = root.handleKey(event); }
    Keys.onReleased: event => root.releaseKey(event)

    readonly property bool compact: root.height > 0 && root.height < 300
    readonly property bool dense: root.width > 0 && root.width < 260
    readonly property int fieldRadius: Appearance.rounding.small

    // -- form state --
    property var editTask: null
    readonly property bool editing: root.editTask !== null
    property string openedProvider: ""
    property bool formHasDate: false
    property date formDate: new Date()
    property int formPriority: 0
    property var formTags: []

    readonly property bool canSave: titleInput.text.trim().length > 0
        && (!root.editing || (root.openedProvider === Todo.provider && Todo.canEditTask(root.editTask)))
    // TickTick's priority scale (0 none / 1 low / 3 medium / 5 high) doubles
    // as the local schema, so the same chips work for both providers.
    readonly property var priorityOptions: [
        { "value": 0, "label": Translation.tr("None") },
        { "value": 1, "label": Translation.tr("Low") },
        { "value": 3, "label": Translation.tr("Medium") },
        { "value": 5, "label": Translation.tr("High") }
    ]

    function clearInput() {
        titleInput.text = "";
        notesArea.text = "";
        tagInput.text = "";
        root.formHasDate = false;
        root.formPriority = 0;
        root.formTags = [];
    }

    function sameDay(a, b) {
        return a && b && a.getFullYear() === b.getFullYear()
            && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
    }

    function save() {
        if (!root.canSave)
            return;
        const changes = {
            "content": titleInput.text.trim(),
            "date": root.formHasDate ? root.formDate : null,
            "notes": notesArea.text.trim(),
            "priority": root.formPriority,
            "tags": root.formTags
        };
        if (root.editing) {
            if (!Todo.updateItem(root.editTask, changes))
                return;
        } else {
            Todo.addItem(Object.assign({ "done": false }, changes));
        }
        root.clearInput();
        root.saved();
        root.closeRequested();
    }

    // Tags the user already uses elsewhere, offered as one-tap suggestions.
    readonly property var existingTags: {
        const seen = new Set();
        const list = Todo.list;
        for (let i = 0; i < list.length; i++) {
            const tags = list[i]?.tags;
            if (!Array.isArray(tags))
                continue;
            for (let j = 0; j < tags.length; j++) {
                const tag = String(tags[j]);
                if (tag.length > 0 && !root.formTags.includes(tag))
                    seen.add(tag);
            }
        }
        return Array.from(seen).slice(0, 6);
    }

    function selectDate(date) {
        root.formDate = date;
        root.formHasDate = true;
    }

    Component.onCompleted: {
        root.openedProvider = Todo.provider;
        if (root.editing) {
            titleInput.text = root.editTask.content ?? "";
            notesArea.text = root.editTask.notes ?? "";
            root.formHasDate = root.editTask.hasDate === true && !!root.editTask.date;
            root.formDate = root.formHasDate ? new Date(root.editTask.date) : new Date();
            root.formPriority = root.editTask.priority ?? 0;
            root.formTags = Array.from(root.editTask.tags ?? []);
        }
        titleInput.forceActiveFocus();
    }

    // -- shared field vocabulary (EventSidebar recipe) --

    component FormCaption: StyledText {
        font.pixelSize: Appearance.font.pixelSize.smallest
        animateChange: true
        font.weight: Font.Bold
        color: Appearance.colors.colOnSurfaceVariant
    }

    component OptionChip: RippleButton {
        id: optionChip

        property string label: ""
        property bool selected: false
        property color dotColor: "transparent"
        property string shortcut: ""
        signal triggered()

        readonly property bool hasDot: optionChip.dotColor.a > 0

        implicitWidth: Math.max(contentRow.implicitWidth, hintLabel.implicitWidth) + 24
        implicitHeight: 34
        buttonRadius: Appearance.rounding.full
        colBackground: optionChip.selected || optionChip.activeFocus
            ? Appearance.colors.colSecondaryContainer : "transparent"
        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
        colBackgroundActive: Appearance.colors.colSecondaryContainerActive
        Accessible.name: optionChip.label
        Accessible.role: Accessible.CheckBox
        Accessible.checked: optionChip.selected
        onClicked: optionChip.triggered()
        onActiveFocusChanged: root.reveal(optionChip)
        Keys.onPressed: event => { event.accepted = root.handleKey(event); }
        Keys.onReleased: event => root.releaseKey(event)
        property real hintProgress: root.showShortcutHints && (shortcut.length > 0 || activeFocus) ? 1 : 0
        Behavior on hintProgress {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(optionChip)
        }

        StyledText {
            id: hintLabel
            anchors.centerIn: parent
            text: optionChip.shortcut || "Space"
            opacity: optionChip.hintProgress
            font.pixelSize: Appearance.font.pixelSize.smallest
            font.weight: Font.Bold
            color: optionChip.selected || optionChip.activeFocus
                ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurfaceVariant
        }

        Behavior on colBackground {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(optionChip)
        }


        contentItem: Row {
            id: contentRow
            anchors.centerIn: parent
            spacing: 6
            opacity: 1 - optionChip.hintProgress

            Rectangle {
                id: chipDot
                visible: optionChip.hasDot
                anchors.verticalCenter: parent.verticalCenter
                width: 8
                height: 8
                radius: 4
                color: optionChip.dotColor
            }

            StyledText {
                id: chipLabel
                anchors.verticalCenter: parent.verticalCenter
                text: optionChip.label
                font.pixelSize: Appearance.font.pixelSize.smallie
                font.weight: Font.Bold
                color: optionChip.selected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurfaceVariant
            }
        }

    }

    component FieldRow: RippleButton {
        id: fieldRow

        property string symbol: ""
        property int shapeKind: MaterialShape.Shape.Cookie12Sided
        property string caption: ""
        property string value: ""
        property string trailingSymbol: "chevron_right"
        signal triggered()

        Layout.fillWidth: true
        implicitHeight: 62
        buttonRadius: root.fieldRadius
        colBackground: fieldRow.hovered || fieldRow.activeFocus
            ? Appearance.colors.colSurfaceContainerHighestHover
            : Appearance.m3colors.m3surfaceContainerHighest
        onClicked: fieldRow.triggered()
        onActiveFocusChanged: root.reveal(fieldRow)
        Accessible.name: fieldRow.caption + ": " + fieldRow.value

        Behavior on colBackground {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(fieldRow)
        }


        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 12
            spacing: 10

            MaterialShapeWrappedMaterialSymbol {
                text: fieldRow.symbol
                iconSize: 18
                padding: 9
                shape: fieldRow.shapeKind
                color: Appearance.colors.colPrimaryContainer
                colSymbol: Appearance.colors.colOnPrimaryContainer
                rotation: fieldRow.hovered ? 18 : 0
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                FormCaption {
                    text: fieldRow.caption
                }

                StyledText {
                    Layout.fillWidth: true
                    text: fieldRow.value
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnSurface
                    elide: Text.ElideRight
                }
            }

            MaterialSymbol {
                text: fieldRow.trailingSymbol
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnSurfaceVariant
            }
        }
    }

    StyledFlickable {
        id: formFlickable
        anchors.fill: parent
        contentHeight: formColumn.implicitHeight + (root.fabSize + root.fabMargins * 2)
        clip: true

        ColumnLayout {
            id: formColumn
            width: formFlickable.width
            spacing: root.compact ? 8 : 12
            enabled: !root.datePickerOpen

            // Header: one way out, the provider the task lands in.
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                RippleButton {
                    implicitWidth: root.compact ? 40 : 44
                    Accessible.name: Translation.tr("Back to tasks")
                    implicitHeight: root.compact ? 40 : 44
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.m3colors.m3surfaceContainerHighest
                    colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
                    colBackgroundActive: Appearance.colors.colSurfaceContainerHighestActive

                    onClicked: root.closeRequested()

                    contentItem: TaskShortcutContent {
                        symbol: "arrow_back"
                        shortcut: "Esc"
                        showHint: root.showShortcutHints
                        iconSize: root.compact ? 20 : 22
                    }

                    StyledToolTip {
                        text: Translation.tr("Back to tasks")
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.editing ? Translation.tr("Edit task") : Translation.tr("Add task")
                    font.pixelSize: Appearance.font.pixelSize.larger
                    font.bold: true
                    color: Appearance.colors.colOnLayer1
                    elide: Text.ElideRight
                }

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: providerLabel.implicitWidth + 16
                    implicitHeight: 28
                    radius: Appearance.rounding.full
                    color: Appearance.m3colors.m3surfaceContainerHighest

                    StyledText {
                        id: providerLabel
                        anchors.centerIn: parent
                        text: Todo.providerName
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.Bold
                        color: Appearance.colors.colPrimary
                    }
                }
            }

            // Title — the only required field.
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 66
                radius: root.fieldRadius
                color: Appearance.m3colors.m3surfaceContainerHighest

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 12
                    spacing: 10

                    MaterialShapeWrappedMaterialSymbol {
                        text: "title"
                        iconSize: 18
                        padding: 9
                        shape: MaterialShape.Shape.Cookie7Sided
                        color: Appearance.colors.colPrimaryContainer
                        colSymbol: Appearance.colors.colOnPrimaryContainer
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        FormCaption {
                            text: root.showShortcutHints ? "Ctrl + T" : Translation.tr("Title")
                        }

                        StyledTextInput {
                            id: titleInput
                            objectName: "newTaskTitleInput"
                            activeFocusOnTab: true
                            onActiveFocusChanged: root.reveal(titleInput)
                            Keys.priority: Keys.BeforeItem
                            Keys.onPressed: event => { event.accepted = root.handleKey(event); }
                            Keys.onReleased: event => root.releaseKey(event)
                            Layout.fillWidth: true
                            // The title shares its row with the leading shape;
                            // keep long single-line input inside its own lane.
                            clip: true
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.Bold
                            color: Appearance.colors.colOnSurface

                            StyledText {
                                anchors.fill: parent
                                visible: titleInput.text.length === 0
                                verticalAlignment: Text.AlignVCenter
                                text: Translation.tr("What needs doing?")
                                color: Appearance.colors.colOnLayer1Inactive
                            }
                        }
                    }
                }
            }

            // Date: quick chips, a summary row and a collapsible month grid.
            Flow {
                Layout.fillWidth: true
                visible: Todo.supportsDate
                spacing: 6

                OptionChip {
                    label: Translation.tr("No date")
                    shortcut: "Ctrl + 1"
                    selected: !root.formHasDate
                    onTriggered: root.formHasDate = false
                }

                OptionChip {
                    label: Translation.tr("Today")
                    shortcut: "Ctrl + 2"
                    selected: root.formHasDate && root.sameDay(root.formDate, new Date())
                    onTriggered: root.selectDate(new Date())
                }

                OptionChip {
                    label: Translation.tr("Tomorrow")
                    shortcut: "Ctrl + 3"
                    selected: root.formHasDate && root.sameDay(root.formDate, new Date(Date.now() + 86400000))
                    onTriggered: {
                        const tomorrow = new Date();
                        tomorrow.setDate(tomorrow.getDate() + 1);
                        root.selectDate(tomorrow);
                    }
                }
            }

            FieldRow {
                id: dateField
                visible: Todo.supportsDate
                symbol: "calendar_month"
                shapeKind: MaterialShape.Shape.Cookie12Sided
                caption: root.showShortcutHints ? "Ctrl + D" : Translation.tr("Due date")
                value: root.formHasDate
                    ? Qt.formatDate(root.formDate, "dddd, d MMMM yyyy")
                    : Translation.tr("No date")
                trailingSymbol: "expand_more"
                onTriggered: root.openDatePicker()
            }

            // Priority — hidden entirely on providers that drop it.
            ColumnLayout {
                visible: Todo.supportsPriority
                Layout.fillWidth: true
                spacing: 8

                FormCaption {
                    Layout.leftMargin: 4
                    text: root.showShortcutHints ? "Ctrl + P" : Translation.tr("Priority")
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 6

                    Repeater {
                        id: priorityRepeater
                        model: root.priorityOptions

                        OptionChip {
                            required property var modelData
                            required property int index
                            shortcut: "Ctrl + " + (index + 4)

                            label: modelData.label
                            selected: root.formPriority === modelData.value
                            dotColor: modelData.value === 5 ? Appearance.colors.colError
                                : modelData.value === 3 ? Appearance.colors.colTertiary
                                : modelData.value === 1 ? Appearance.colors.colPrimary : "transparent"
                            onTriggered: root.formPriority = modelData.value
                        }
                    }
                }
            }

            // Tags — local schema only; remote providers never see the field.
            ColumnLayout {
                visible: Todo.supportsTags
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 62
                    radius: root.fieldRadius
                    color: Appearance.m3colors.m3surfaceContainerHighest

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 8
                        spacing: 10

                        MaterialSymbol {
                            text: "label"
                            iconSize: 18
                            color: Appearance.colors.colPrimary
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            FormCaption {
                                text: root.showShortcutHints ? "Ctrl + G · Enter" : Translation.tr("Tags")
                            }

                            StyledTextInput {
                                id: tagInput
                                objectName: "newTaskTagInput"
                                activeFocusOnTab: true
                                onActiveFocusChanged: root.reveal(tagInput)
                                Keys.priority: Keys.BeforeItem
                                Keys.onPressed: event => { event.accepted = root.handleKey(event); }
                                Keys.onReleased: event => root.releaseKey(event)
                                Layout.fillWidth: true
                                clip: true
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnSurface

                                StyledText {
                                    anchors.fill: parent
                                    visible: tagInput.text.length === 0
                                    verticalAlignment: Text.AlignVCenter
                                    text: Translation.tr("Add a tag")
                                    color: Appearance.colors.colOnLayer1Inactive
                                }

                                Keys.onReturnPressed: event => {
                                    if (!root.handleKey(event)) root.addTagFromInput();
                                }
                                Keys.onEnterPressed: event => {
                                    if (!root.handleKey(event)) root.addTagFromInput();
                                }
                            }
                        }

                        RippleButton {
                            implicitWidth: 32
                            implicitHeight: 32
                            buttonRadius: Appearance.rounding.full
                            colBackground: Appearance.colors.colPrimaryContainer
                            colBackgroundHover: Appearance.colors.colPrimaryContainerHover

                            onClicked: root.addTagFromInput()

                            contentItem: TaskShortcutContent {
                                symbol: "add"
                                shortcut: "Enter"
                                showHint: root.showShortcutHints
                                iconSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnPrimaryContainer
                            }

                            StyledToolTip {
                                text: Translation.tr("Add tag")
                            }
                        }
                    }
                }

                Flow {
                    visible: root.formTags.length > 0
                    Layout.fillWidth: true
                    spacing: 6

                    Repeater {
                        model: root.formTags

                        OptionChip {
                            required property var modelData
                            required property int index

                            label: modelData
                            selected: true
                            onTriggered: root.removeTag(index)
                        }
                    }
                }

                Flow {
                    visible: root.existingTags.length > 0
                    Layout.fillWidth: true
                    spacing: 6

                    Repeater {
                        model: root.existingTags

                        OptionChip {
                            required property var modelData

                            label: modelData
                            selected: false
                            onTriggered: root.addTag(modelData)
                        }
                    }
                }
            }

            // Notes.
            Rectangle {
                Layout.fillWidth: true
                visible: Todo.supportsNotes
                Layout.preferredHeight: 96
                radius: root.fieldRadius
                color: Appearance.m3colors.m3surfaceContainerHighest

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 10

                    MaterialShapeWrappedMaterialSymbol {
                        Layout.alignment: Qt.AlignTop
                        text: "notes"
                        iconSize: 18
                        padding: 9
                        shape: MaterialShape.Shape.Pill
                        color: Appearance.colors.colPrimaryContainer
                        colSymbol: Appearance.colors.colOnPrimaryContainer
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 0

                        FormCaption {
                            text: root.showShortcutHints ? "Ctrl + O" : Translation.tr("Notes")
                        }

                        StyledFlickable {
                            id: notesFlick
                            objectName: "newTaskNotesFlickable"
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            contentWidth: width
                            contentHeight: Math.max(height, notesArea.height)
                            interactive: contentHeight > height

                            StyledTextArea {
                                id: notesArea
                                objectName: "newTaskNotesArea"
                                activeFocusOnTab: true
                                onActiveFocusChanged: root.reveal(notesArea)
                                Keys.priority: Keys.BeforeItem
                                Keys.onPressed: event => { event.accepted = root.handleKey(event); }
                                Keys.onReleased: event => root.releaseKey(event)
                                width: notesFlick.width
                                height: Math.max(notesFlick.height, contentHeight)
                                wrapMode: TextEdit.Wrap
                                background: null
                                padding: 0
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnSurface

                                StyledText {
                                    anchors.fill: parent
                                    visible: notesArea.text.length === 0 && !notesArea.activeFocus
                                    verticalAlignment: Text.AlignTop
                                    text: Translation.tr("Details, links, anything else")
                                    color: Appearance.colors.colOnLayer1Inactive
                                    font.pixelSize: Appearance.font.pixelSize.small
                                }
                            }
                        }
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: root.compact ? 8 : 12
            }
        }
    }

    function addTagFromInput() {
        const tag = tagInput.text.trim();
        if (tag.length === 0)
            return;
        tagInput.text = "";
        root.addTag(tag);
    }

    function addTag(tag) {
        if (root.formTags.includes(tag))
            return;
        root.formTags = root.formTags.concat([tag]);
    }

    function removeTag(index) {
        const next = root.formTags.slice();
        next.splice(index, 1);
        root.formTags = next;
    }

    DatePickerPopup {
        id: datePicker
        anchors.fill: parent
        Keys.onPressed: event => { event.accepted = root.handleKey(event); }
        Keys.onReleased: event => root.releaseKey(event)
        onOpenedChanged: {
            if (!opened) dateField.forceActiveFocus();
        }

        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            text: "← ↑ ↓ → · PgUp / PgDn · Home\nEnter · Esc"
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colOnSurface
            opacity: root.showShortcutHints ? 1 : 0
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }
        onAccepted: date => root.selectDate(date)
    }

    readonly property int fabSize: root.dense ? 40 : (root.compact ? 42 : 52)
    readonly property int fabMargins: root.dense ? 6 : (root.compact ? 10 : 14)

}
