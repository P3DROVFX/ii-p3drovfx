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

    readonly property bool compact: root.height > 0 && root.height < 300
    readonly property bool dense: root.width > 0 && root.width < 260
    readonly property int fieldRadius: Appearance.rounding.small

    // -- form state --
    property bool formHasDate: false
    property date formDate: new Date()
    property int formPriority: 0
    property var formTags: []

    readonly property bool canSave: titleInput.text.trim().length > 0
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
        Todo.addItem({
            "content": titleInput.text.trim(),
            "done": false,
            "date": root.formHasDate ? root.formDate : null,
            "notes": notesArea.text.trim(),
            "priority": root.formPriority,
            "tags": root.formTags
        });
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

    Component.onCompleted: titleInput.forceActiveFocus()

    // -- shared field vocabulary (EventSidebar recipe) --

    component FormCaption: StyledText {
        font.pixelSize: Appearance.font.pixelSize.smallest
        font.weight: Font.Bold
        color: Appearance.colors.colOnSurfaceVariant
    }

    component OptionChip: Rectangle {
        id: optionChip

        property string label: ""
        property bool selected: false
        property color dotColor: "transparent"
        signal triggered()

        readonly property bool hasDot: optionChip.dotColor.a > 0

        implicitWidth: contentRow.implicitWidth + 24
        implicitHeight: 34
        radius: Appearance.rounding.full
        color: optionChip.selected ? Appearance.colors.colSecondaryContainer : "transparent"

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(optionChip)
        }

        DashedBorder {
            anchors.fill: parent
            visible: !optionChip.selected
            color: ColorUtils.applyAlpha(Appearance.colors.colOutline, 0.8)
            borderWidth: 1
            dashLength: 4
            gapLength: 3
            radius: Appearance.rounding.full
        }

        Row {
            id: contentRow
            anchors.centerIn: parent
            spacing: 6

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

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: optionChip.triggered()
        }
    }

    component FieldRow: Rectangle {
        id: fieldRow

        property string symbol: ""
        property int shapeKind: MaterialShape.Shape.Cookie12Sided
        property string caption: ""
        property string value: ""
        property string trailingSymbol: "chevron_right"
        signal triggered()

        Layout.fillWidth: true
        implicitHeight: 62
        radius: root.fieldRadius
        color: fieldRowPointer.containsMouse
            ? Appearance.colors.colSurfaceContainerHighestHover
            : Appearance.m3colors.m3surfaceContainerHighest

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(fieldRow)
        }

        MouseArea {
            id: fieldRowPointer
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: fieldRow.triggered()
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
                rotation: fieldRowPointer.containsMouse ? 18 : 0
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

            // Header: one way out, the provider the task lands in.
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                RippleButton {
                    implicitWidth: root.compact ? 40 : 44
                    implicitHeight: root.compact ? 40 : 44
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.m3colors.m3surfaceContainerHighest
                    colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
                    colBackgroundActive: Appearance.colors.colSurfaceContainerHighestActive

                    onClicked: root.closeRequested()

                    contentItem: Item {
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "arrow_back"
                            iconSize: root.compact ? 20 : 22
                            color: Appearance.colors.colOnSurface
                        }
                    }

                    StyledToolTip {
                        text: Translation.tr("Back to tasks")
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Add task")
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
                            text: Translation.tr("Title")
                        }

                        StyledTextInput {
                            id: titleInput
                            objectName: "newTaskTitleInput"
                            Layout.fillWidth: true
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
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                OptionChip {
                    label: Translation.tr("No date")
                    selected: !root.formHasDate
                    onTriggered: root.formHasDate = false
                }

                OptionChip {
                    label: Translation.tr("Today")
                    selected: root.formHasDate && root.sameDay(root.formDate, new Date())
                    onTriggered: root.selectDate(new Date())
                }

                OptionChip {
                    label: Translation.tr("Tomorrow")
                    selected: root.formHasDate && root.sameDay(root.formDate, new Date(Date.now() + 86400000))
                    onTriggered: {
                        const tomorrow = new Date();
                        tomorrow.setDate(tomorrow.getDate() + 1);
                        root.selectDate(tomorrow);
                    }
                }
            }

            FieldRow {
                symbol: "calendar_month"
                shapeKind: MaterialShape.Shape.Cookie12Sided
                caption: Translation.tr("Due date")
                value: root.formHasDate
                    ? Qt.formatDate(root.formDate, "dddd, d MMMM yyyy")
                    : Translation.tr("No date")
                trailingSymbol: "expand_more"
                onTriggered: datePicker.open(root.formHasDate ? root.formDate : null, Translation.tr("Due date"))
            }

            // Priority — hidden entirely on providers that drop it.
            ColumnLayout {
                visible: Todo.supportsPriority
                Layout.fillWidth: true
                spacing: 8

                FormCaption {
                    Layout.leftMargin: 4
                    text: Translation.tr("Priority")
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 6

                    Repeater {
                        model: root.priorityOptions

                        OptionChip {
                            required property var modelData

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
                                text: Translation.tr("Tags")
                            }

                            StyledTextInput {
                                id: tagInput
                                objectName: "newTaskTagInput"
                                Layout.fillWidth: true
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnSurface

                                StyledText {
                                    anchors.fill: parent
                                    visible: tagInput.text.length === 0
                                    verticalAlignment: Text.AlignVCenter
                                    text: Translation.tr("Add a tag")
                                    color: Appearance.colors.colOnLayer1Inactive
                                }

                                Keys.onReturnPressed: root.addTagFromInput()
                                Keys.onEnterPressed: root.addTagFromInput()
                            }
                        }

                        RippleButton {
                            implicitWidth: 32
                            implicitHeight: 32
                            buttonRadius: Appearance.rounding.full
                            colBackground: Appearance.colors.colPrimaryContainer
                            colBackgroundHover: Appearance.colors.colPrimaryContainerHover

                            onClicked: root.addTagFromInput()

                            contentItem: Item {
                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "add"
                                    iconSize: 18
                                    color: Appearance.colors.colOnPrimaryContainer
                                }
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
                            text: Translation.tr("Notes")
                        }

                        StyledTextArea {
                            id: notesArea
                            objectName: "newTaskNotesArea"
                            Layout.fillWidth: true
                            Layout.fillHeight: true
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
        onAccepted: date => root.selectDate(date)
    }

    readonly property int fabSize: root.dense ? 40 : (root.compact ? 42 : 52)
    readonly property int fabMargins: root.dense ? 6 : (root.compact ? 10 : 14)

    StyledRectangularShadow {
        target: saveFab
        radius: saveFab.buttonRadius
        blur: 0.6 * Appearance.sizes.elevationMargin
    }

    // Same spot, same shape as the create FAB: the button that opened this
    // page is the button that commits it.
    FloatingActionButton {
        id: saveFab

        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: root.fabMargins
        anchors.bottomMargin: root.fabMargins
        baseSize: root.fabSize
        iconSize: root.compact ? 20 : 24
        enabled: root.canSave
        onClicked: root.save()
        iconText: "check"
    }
}
