import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.overlay

/**
 * The quick notes panel: every note in a list, and a plain text editor for one of them.
 *
 * Deliberately not the Notes app. The panel is small and opened mid-game, so it does two
 * things — jot something down, read what was jotted — and hands anything richer to the
 * app. Text goes through the service's legacy bridge, which keeps a note's drawing intact
 * when only its text is edited.
 */
OverlayBackground {
    id: root

    property bool isClickthrough: false
    /// A note to open straight away instead of the list, for callers that were showing one.
    property int initialTabIndex: -1

    property string currentNoteId: ""
    readonly property bool editing: root.currentNoteId.length > 0
    /// The text last handed to the service, so a reload that brings back our own write
    /// never replaces what is in the field.
    property string savedText: ""
    property bool editable: true
    /// A note this panel just created. The index lands a moment after `createNote`
    /// returns, so until then the note is open here without being in the list.
    property string pendingNoteId: ""

    property var copyListEntries: []
    property string lastParsedCopylistText: ""
    property var parsedCopylistLines: []
    property real maxCopyButtonSize: 20

    /// Block types plain text cannot carry back. A note holding one is shown, not edited.
    readonly property var richBlockTypes: ["image", "table", "linkPreview", "fileLink", "audio", "embed"]

    readonly property var noteRows: Array.from(NotesService.notes ?? []).sort((a, b) =>
        (Number(b.pinned) - Number(a.pinned)) || (b.modified - a.modified))

    implicitWidth: 300
    implicitHeight: 200

    Component.onCompleted: {
        const noteId = NotesService.noteIdForTab(root.initialTabIndex);
        if (noteId.length > 0)
            root.openNote(noteId);
    }

    Component.onDestruction: {
        // The debounce timer dies with this widget; commit whatever it was still holding.
        if (saveDebounce.running) {
            saveDebounce.stop();
            root.saveNow();
        }
    }

    Connections {
        target: NotesService
        function onDataChanged() {
            root.syncFromService();
        }
    }

    Connections {
        // Other surfaces point the panel at a note by its position.
        target: Persistent.states.overlay.notes
        function onTabIndexChanged() {
            const noteId = NotesService.noteIdForTab(Persistent.states.overlay.notes.tabIndex);
            if (noteId.length > 0 && noteId !== root.currentNoteId)
                root.openNote(noteId);
        }
    }

    function tabOf(noteId) {
        return (NotesService.tabsData.tabs ?? []).find(tab => tab.noteId === noteId) ?? null;
    }

    function isRich(noteId) {
        const document = NotesService.documentOf(noteId);
        return !!document && (document.blocks ?? []).some(item => root.richBlockTypes.includes(item.type));
    }

    /// What the field shows. A read-only note is rendered as markdown, and its images
    /// become their captions: the renderer would go and fetch them, local or remote.
    function shownText(content) {
        return root.editable ? content : content.replace(/!\[([^\]]*)\]\([^)]*\)/g, "[$1]");
    }

    function openNote(noteId) {
        const note = NotesService.noteById(noteId);
        if (!note && noteId !== root.pendingNoteId)
            return;
        // Locked notes stay behind the app's PIN.
        if (note?.locked) {
            root.openInApp(noteId);
            return;
        }
        if (saveDebounce.running) {
            saveDebounce.stop();
            root.saveNow();
        }
        const tab = root.tabOf(noteId);
        root.currentNoteId = noteId;
        root.editable = !root.isRich(noteId);
        root.savedText = tab?.content ?? "";
        textInput.text = root.shownText(root.savedText);
        titleInput.text = note?.title ?? "";
        if (note)
            Persistent.states.overlay.notes.tabIndex = NotesService.noteIndexOf(noteId);
        root.updateCopyListEntries();
    }

    function closeNote() {
        if (saveDebounce.running) {
            saveDebounce.stop();
            root.saveNow();
        }
        root.commitTitle();
        root.currentNoteId = "";
        root.pendingNoteId = "";
        root.copyListEntries = [];
    }

    function newNote() {
        if (!NotesService.ready)
            return;
        root.closeNote();
        root.pendingNoteId = NotesService.createNote({ title: "" });
        root.openNote(root.pendingNoteId);
        Qt.callLater(() => textInput.forceActiveFocus());
    }

    function captureNote() {
        const text = quickInput.text.trim();
        if (text.length === 0)
            return;
        // Keep the draft if the service cannot save it yet.
        const result = NotesService.create(text.split("\n")[0].slice(0, 80), text, null);
        if (result.ok)
            quickInput.text = "";
    }

    function deleteCurrentNote() {
        const noteId = root.currentNoteId;
        saveDebounce.stop();
        root.currentNoteId = "";
        root.copyListEntries = [];
        NotesService.deleteNote(noteId);
    }

    function openInApp(noteId) {
        root.closeNote();
        GlobalStates.notesOpen = false;
        GlobalStates.openNotes(noteId);
    }

    function saveNow() {
        if (!root.editing || !root.editable)
            return;
        const text = textInput.text;
        if (text === root.savedText)
            return;
        if (root.currentNoteId !== root.pendingNoteId && NotesService.noteIndexOf(root.currentNoteId) < 0)
            return;
        root.savedText = text;
        NotesService.updateTabById(root.currentNoteId, text);
        NotesService.rebuildProjection();
    }

    function commitTitle() {
        if (!root.editing)
            return;
        const note = NotesService.noteById(root.currentNoteId);
        const title = titleInput.text.trim();
        if (note && note.title !== title)
            NotesService.updateMeta(root.currentNoteId, { title: title });
    }

    function syncFromService() {
        if (!root.editing)
            return;
        const note = NotesService.noteById(root.currentNoteId);
        if (!note && root.currentNoteId === root.pendingNoteId)
            return;
        if (note && root.currentNoteId === root.pendingNoteId) {
            root.pendingNoteId = "";
            Persistent.states.overlay.notes.tabIndex = NotesService.noteIndexOf(note.id);
        }
        if (!note || note.trashedAt !== 0 || note.locked) {
            // Removed or locked from somewhere else while open here.
            saveDebounce.stop();
            root.currentNoteId = "";
            root.copyListEntries = [];
            return;
        }
        const wasEditable = root.editable;
        root.editable = !root.isRich(root.currentNoteId);
        if (!titleInput.activeFocus && titleInput.text !== note.title)
            titleInput.text = note.title;
        const content = root.tabOf(root.currentNoteId)?.content ?? "";
        if (root.editable !== wasEditable) {
            saveDebounce.stop();
            root.savedText = content;
            textInput.text = root.shownText(content);
            return;
        }
        if (saveDebounce.running || content === root.savedText || content === textInput.text)
            return;
        // Edited elsewhere: take the new text, keeping the caret where it was.
        const cursor = textInput.cursorPosition;
        root.savedText = content;
        textInput.text = root.shownText(content);
        textInput.cursorPosition = Math.min(cursor, content.length);
    }

    // ── Copyable bullets ─────────────────────────────────────────────────

    function scheduleCopylistUpdate(immediate = false) {
        if (immediate) {
            copyListDebounce.stop();
            root.updateCopyListEntries();
        } else {
            copyListDebounce.restart();
        }
    }

    function updateCopyListEntries() {
        const textValue = textInput.text;
        if (!root.editing || !root.editable || textValue.length === 0) {
            root.lastParsedCopylistText = "";
            root.parsedCopylistLines = [];
            root.copyListEntries = [];
            return;
        }

        if (textValue !== root.lastParsedCopylistText) {
            const lineRegex = /(.*?)(\r?\n|$)/g;
            let match = null;
            const parsed = [];
            while ((match = lineRegex.exec(textValue)) !== null) {
                const lineText = match[1];
                const lineStart = match.index;
                const bulletMatch = lineText.match(/^\s*-\s+(.*\S)\s*$/);
                if (bulletMatch) {
                    parsed.push({
                        content: bulletMatch[1].trim(),
                        start: lineStart,
                        end: lineStart + lineText.length
                    });
                }
                if (match[2] === "")
                    break;
            }
            root.lastParsedCopylistText = textValue;
            root.parsedCopylistLines = parsed;
            if (parsed.length === 0) {
                root.copyListEntries = [];
                return;
            }
        }

        root.updateCopylistPositions();
    }

    function updateCopylistPositions() {
        if (root.parsedCopylistLines.length === 0)
            return;
        const rawSelectionStart = textInput.selectionStart;
        const rawSelectionEnd = textInput.selectionEnd;
        const selectionStart = rawSelectionStart === -1 ? textInput.cursorPosition : rawSelectionStart;
        const selectionEnd = rawSelectionEnd === -1 ? textInput.cursorPosition : rawSelectionEnd;
        const rangeStart = Math.min(selectionStart, selectionEnd);
        const rangeEnd = Math.max(selectionStart, selectionEnd);

        root.copyListEntries = root.parsedCopylistLines.map(line => {
            // Don't show copy button if line is (partially) selected
            if (rangeEnd > line.start && rangeStart <= line.end)
                return null;
            const startRect = textInput.positionToRectangle(line.start);
            let endRect = textInput.positionToRectangle(line.end);
            if (!isFinite(startRect.y))
                return null;
            if (!isFinite(endRect.y))
                endRect = startRect;
            const lineBottom = endRect.y + endRect.height;
            return {
                content: line.content,
                y: startRect.y,
                height: Math.max(lineBottom - startRect.y, textInput.font.pixelSize + 8)
            };
        }).filter(entry => entry !== null);
    }

    Timer {
        id: saveDebounce
        interval: 500
        onTriggered: root.saveNow()
    }

    Timer {
        id: copyListDebounce
        interval: 100
        onTriggered: root.updateCopylistPositions()
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: 12
        }
        spacing: 8

        // ── Header ───────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 4

            HeaderButton {
                visible: root.editing
                symbol: "arrow_back"
                tooltip: Translation.tr("All notes")
                onClicked: root.closeNote()
            }

            StyledText {
                visible: !root.editing
                Layout.fillWidth: true
                Layout.leftMargin: 4
                text: Translation.tr("%1 notes").arg(String(root.noteRows.length))
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }

            StyledTextInput {
                id: titleInput
                visible: root.editing
                Layout.fillWidth: true
                clip: true
                readOnly: !root.editable
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.DemiBold
                selectByMouse: true
                onEditingFinished: root.commitTitle()
                onAccepted: textInput.forceActiveFocus()

                StyledText {
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    visible: titleInput.text.length === 0
                    text: Translation.tr("Untitled note")
                    font.pixelSize: titleInput.font.pixelSize
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colSubtext
                }
            }

            HeaderButton {
                visible: !root.editing
                enabled: NotesService.ready
                symbol: "add"
                tooltip: Translation.tr("New note")
                onClicked: root.newNote()
            }

            HeaderButton {
                visible: root.editing
                symbol: "delete"
                tooltip: Translation.tr("Move to trash")
                onClicked: root.deleteCurrentNote()
            }

            HeaderButton {
                symbol: "open_in_new"
                tooltip: Translation.tr("Open in Notes")
                onClicked: root.openInApp(root.currentNoteId)
            }
        }

        // ── All notes ────────────────────────────────────────────────────
        Rectangle {
            visible: !root.editing
            Layout.fillWidth: true
            implicitHeight: 38
            radius: Appearance.rounding.full
            color: quickInput.activeFocus ? Appearance.m3colors.m3surfaceContainerHighest : Appearance.m3colors.m3surfaceContainerHigh

            Behavior on color {
                ColorAnimation { duration: Appearance.animation.elementMoveFast.duration }
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 6
                spacing: 8

                MaterialSymbol {
                    text: "edit_note"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colPrimary
                }

                StyledTextInput {
                    id: quickInput
                    Layout.fillWidth: true
                    clip: true
                    selectByMouse: true
                    Accessible.name: Translation.tr("Quick note")
                    onAccepted: root.captureNote()

                    StyledText {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        visible: quickInput.text.length === 0
                        text: Translation.tr("Quick note…")
                        font.pixelSize: quickInput.font.pixelSize
                        color: Appearance.colors.colSubtext
                    }
                }

                RippleButton {
                    implicitWidth: 32
                    implicitHeight: 26
                    visible: quickInput.text.trim().length > 0
                    enabled: NotesService.ready
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colPrimary
                    colBackgroundHover: Appearance.colors.colPrimaryHover
                    onClicked: root.captureNote()

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "arrow_upward"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnPrimary
                    }

                    StyledToolTip {
                        text: Translation.tr("Save note")
                    }
                }
            }
        }

        Item {
            visible: !root.editing
            Layout.fillWidth: true
            Layout.fillHeight: true

            ColumnLayout {
                anchors.centerIn: parent
                visible: root.noteRows.length === 0
                spacing: 6

                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    text: "note_stack"
                    iconSize: 36
                    color: Appearance.colors.colSubtext
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Translation.tr("No notes yet")
                    color: Appearance.colors.colSubtext
                }
            }

            ListView {
                id: listView
                anchors.fill: parent
                clip: true
                spacing: 4
                model: root.noteRows
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: StyledScrollBar {}

                delegate: NoteRow {}

                TouchpadScrollHandler {
                    flickable: listView
                }
            }
        }

        // ── One note ─────────────────────────────────────────────────────
        RippleButton {
            visible: root.editing && !root.editable
            Layout.fillWidth: true
            implicitHeight: 32
            buttonRadius: Appearance.rounding.small
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            onClicked: root.openInApp(root.currentNoteId)

            contentItem: RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 8

                MaterialSymbol {
                    text: "visibility"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnSecondaryContainer
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Has tables or media — edit it in Notes")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnSecondaryContainer
                    elide: Text.ElideRight
                }
            }
        }

        ScrollView {
            id: editorScrollView
            visible: root.editing
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            ScrollBar.vertical.policy: ScrollBar.AsNeeded
            onWidthChanged: root.scheduleCopylistUpdate(true)

            StyledTextArea { // This has to be a direct child of ScrollView for proper scrolling
                id: textInput
                wrapMode: TextEdit.Wrap
                readOnly: !root.editable
                placeholderText: Translation.tr("Write something…\nLines starting with '-' get a copy button.")
                selectByMouse: true
                persistentSelection: true
                // Read-only notes are shown rendered; plain text is what gets edited.
                textFormat: root.editable ? TextEdit.PlainText : TextEdit.MarkdownText
                background: null
                padding: 4

                onTextChanged: {
                    if (root.editing && text !== root.savedText)
                        saveDebounce.restart();
                    root.scheduleCopylistUpdate(true);
                }
                onHeightChanged: root.scheduleCopylistUpdate(true)
                onContentHeightChanged: root.scheduleCopylistUpdate(true)
                onCursorPositionChanged: root.scheduleCopylistUpdate()
                onSelectionStartChanged: root.scheduleCopylistUpdate()
                onSelectionEndChanged: root.scheduleCopylistUpdate()

                TouchpadScrollHandler {
                    flickable: editorScrollView.contentItem
                }
            }

            Item {
                width: editorScrollView.availableWidth
                height: textInput.height
                visible: root.copyListEntries.length > 0
                clip: true

                Repeater {
                    model: ScriptModel {
                        values: root.copyListEntries
                    }
                    delegate: RippleButton {
                        id: copyButton
                        required property var modelData
                        readonly property real lineHeight: Math.min(Math.max(modelData.height, Appearance.font.pixelSize.normal + 6), root.maxCopyButtonSize)
                        property bool justCopied: false

                        implicitHeight: lineHeight
                        implicitWidth: lineHeight
                        buttonRadius: height / 2
                        y: modelData.y
                        anchors.right: parent.right
                        anchors.rightMargin: -4
                        z: 5

                        Timer {
                            id: resetState
                            interval: 700
                            onTriggered: copyButton.justCopied = false
                        }

                        onClicked: {
                            Quickshell.clipboardText = copyButton.modelData.content;
                            justCopied = true;
                            resetState.start();
                        }

                        contentItem: Item {
                            anchors.centerIn: parent
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: copyButton.justCopied ? "check" : "content_copy"
                                iconSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnLayer1
                            }
                        }
                    }
                }
            }
        }

        StyledText {
            visible: root.editing && root.editable
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignRight
            text: saveDebounce.running || NotesService.writing
                ? Translation.tr("Saving...")
                : Translation.tr("Saved")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
    }

    component HeaderButton: RippleButton {
        id: headerButton
        property string symbol
        property string tooltip

        implicitWidth: 30
        implicitHeight: 30
        buttonRadius: Appearance.rounding.full
        colBackgroundHover: Appearance.m3colors.m3surfaceContainerHighest

        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            text: headerButton.symbol
            iconSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colOnLayer1
        }

        StyledToolTip {
            text: headerButton.tooltip
        }
    }

    component NoteRow: Rectangle {
        id: row
        required property var modelData

        width: ListView.view.width
        implicitHeight: 48
        radius: Appearance.rounding.small
        color: rowArea.containsMouse ? Appearance.m3colors.m3surfaceContainerHighest : Appearance.m3colors.m3surfaceContainerHigh

        Behavior on color {
            ColorAnimation { duration: Appearance.animation.elementMoveFast.duration }
        }

        MouseArea {
            id: rowArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.openNote(row.modelData.id)
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 10

            MaterialSymbol {
                text: row.modelData.locked ? "lock"
                    : (row.modelData.icon && row.modelData.icon.length > 0 ? row.modelData.icon : "description")
                iconSize: Appearance.font.pixelSize.larger
                color: row.modelData.favorite ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: row.modelData.title && row.modelData.title.length > 0
                        ? row.modelData.title
                        : Translation.tr("Untitled note")
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    text: row.modelData.locked ? Translation.tr("Locked")
                        : (row.modelData.preview && row.modelData.preview.length > 0
                            ? row.modelData.preview.replace(/\s+/g, " ")
                            : Translation.tr("Empty note"))
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                }
            }

            MaterialSymbol {
                visible: row.modelData.pinned
                text: "keep"
                iconSize: 14
                color: Appearance.colors.colSubtext
            }
        }
    }
}
