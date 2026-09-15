pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.notes
import qs.modules.ii.notes.editor
import qs.modules.ii.notes.sketch
import "../../../services/notes/NotesSearchIndex.js" as SearchIndex

/**
 * The note itself.
 *
 * The title is edited here because renaming is a property of the note, not of its text —
 * it belongs to the same row as pinning and deleting. The body is rendered from the
 * document; the block editor that makes it typeable is the next piece of work, and it
 * replaces this reader rather than wrapping it.
 */
Item {
    id: root

    property var note: null
    property bool trash: false

    signal deleteRequested()
    signal restoreRequested()
    signal favoriteToggled()
    signal pinToggled()
    signal titleEdited(string title)
    signal outlineRequested()
    signal revisionsRequested()
    signal focusModeToggled()

    // Clipped at the pane's own bounds.
    //
    // The slab below is a *sibling* of the content, so its own `clip` contains nothing —
    // a list long enough to scroll had cards drawn outside the rounded rectangle they are
    // supposed to live in. Clipping belongs to whatever owns the bounds, which is this.
    clip: true

    /// Puts the caret in the note. Called when one is created, not when one is selected.
    function focusEditor() {
        editor.requestAutoFocus();
    }

    /// Asked for by the table of contents, which knows a block id and nothing else.
    function goToBlock(blockId) {
        editor.goToBlock(blockId);
    }

    /**
     * One note giving way to another.
     *
     * The pane keeps its shape and its scroll, so without this the whole column simply
     * held different words in the next frame — indistinguishable from a redraw. A fade is
     * enough: the title, the counts and the page all change together, and the eye follows
     * a column that dims and comes back.
     */
    NumberAnimation {
        id: noteEntrance
        target: body
        property: "opacity"
        from: 0
        to: 1
        duration: Appearance.animation.elementMoveEnter.duration
        easing.type: Appearance.animation.elementMoveEnter.type
        easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
    }

    readonly property string noteId: root.note ? root.note.id : ""
    /// Empty means the note has not chosen one, which is plain.
    /// A note that has not chosen a page falls back to the preference, not to a constant.
    readonly property string paperStyle: root.note && root.note.paper.length > 0
        ? root.note.paper
        : (Config.options.notes.defaultPaper ?? "plain")
    readonly property var backlinks: root.note
        ? SearchIndex.findBacklinks(root.note.id, root.note.title, NotesService.notes, null)
        : []

    readonly property var editorBlocks: editor ? editor.blocks : []
    readonly property int charCount: {
        let count = 0;
        const b = root.editorBlocks;
        if (Array.isArray(b)) {
            for (let i = 0; i < b.length; i++) {
                if (b[i] && typeof b[i].text === "string")
                    count += b[i].text.length;
            }
        }
        return count;
    }
    readonly property int wordCount: {
        let count = 0;
        const b = root.editorBlocks;
        if (Array.isArray(b)) {
            for (let i = 0; i < b.length; i++) {
                if (b[i] && typeof b[i].text === "string" && b[i].text.trim().length > 0) {
                    count += b[i].text.trim().split(/\s+/).length;
                }
            }
        }
        return count;
    }
    readonly property int readingMinutes: Math.max(1, Math.ceil(root.wordCount / 200))

    // ── Reminders and the lock ────────────────────────────────────────────
    //
    // Both of these read fields on the note record. They used to read `note.meta`, a bag
    // the index has never had and `normalizeNote` has always dropped, so every reminder
    // was accepted and forgotten and every lock lasted until the next reload.

    readonly property real reminderAt: root.note ? root.note.reminder : 0
    readonly property bool reminderDone: root.note ? root.note.reminderDone : false
    /**
     * Locked *and* openable.
     *
     * With no PIN there is nothing to hide behind: a note still carrying the flag after
     * the PIN was forgotten would show a cover that no answer opens, which is not a lock,
     * it is a lost note.
     */
    readonly property bool isLocked: root.note ? (root.note.locked && root.hasPin) : false

    /// A PIN exists for the app. There is no default one: a lock everybody's shell opens
    /// with 1234 is worse than no lock, because it looks like protection.
    readonly property bool hasPin: Persistent.states.notes.lockDigest.length > 0

    /// Typing the PIN opens this note until the shell restarts, not for ever.
    property bool unlockedThisSession: false

    onNoteIdChanged: {
        root.unlockedThisSession = false;
        noteEntrance.restart();
    }

    readonly property string reminderLabel: root.reminderAt > 0
        ? Qt.formatDateTime(new Date(root.reminderAt), "d MMM, HH:mm")
        : ""

    function setReminder(timestamp): void {
        if (root.noteId.length > 0)
            NotesService.updateMeta(root.noteId, { reminder: Math.round(timestamp), reminderDone: false });
    }

    function clearReminder(): void {
        if (root.noteId.length > 0)
            NotesService.updateMeta(root.noteId, { reminder: 0, reminderDone: false });
    }

    /// The digest, never the PIN. A salt so two shells with the same PIN do not share a
    /// digest, minted the first time one is chosen.
    function choosePin(pin): void {
        if (Persistent.states.notes.lockSalt.length === 0)
            Persistent.states.notes.lockSalt = Qt.md5(String(Math.random()) + String(Date.now()));
        Persistent.states.notes.lockDigest = Qt.md5(Persistent.states.notes.lockSalt + pin);
        root.lockNote();
    }

    function lockNote(): void {
        if (root.noteId.length === 0)
            return;
        NotesService.updateMeta(root.noteId, { locked: true });
        root.unlockedThisSession = true;
    }

    function unlockNote(): void {
        if (root.noteId.length > 0)
            NotesService.updateMeta(root.noteId, { locked: false });
        root.unlockedThisSession = false;
    }

    signal paperPicked(string style)
    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.large
        color: Appearance.m3colors.m3surfaceContainerHigh
        clip: true
    }

    PagePlaceholder {
        anchors.centerIn: parent
        width: Math.min(parent.width - 60, 420)
        visible: root.note === null
        icon: "edit_note"
        title: Translation.tr("No note selected")
        description: Translation.tr("Pick one from the list, or start a new one.")
    }

    /**
     * A picture, full size, over the page.
     *
     * Inside the pane rather than a window of its own: it is a closer look at something in
     * this note, not a separate thing, and a second window to dismiss would be one more
     * than the job needs.
     */
    Rectangle {
        id: imageViewer
        anchors.fill: parent
        z: 20
        color: Qt.rgba(0, 0, 0, 0.82)
        visible: editor.viewingImage.length > 0

        MouseArea {
            anchors.fill: parent
            onClicked: editor.viewImage("")
        }

        Image {
            anchors.centerIn: parent
            width: Math.min(parent.width - 64, implicitWidth)
            height: implicitWidth > 0 ? width * (implicitHeight / implicitWidth) : 0
            source: editor.viewingImage.length > 0 ? `file://${editor.viewingImage}` : ""
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            smooth: true
            sourceSize.width: 2400
        }

        NotesIconButton {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 12
            symbol: "close"
            tooltipText: Translation.tr("Close")
            colIcon: Appearance.m3colors.m3onSurface
            onTriggered: editor.viewImage("")
        }
    }

    /**
     * The ink sheet, over the page.
     *
     * Inside the pane and above everything, because drawing wants the whole page and a
     * separate window would be one more thing to arrange and dismiss.
     */
    Loader {
        anchors.fill: parent
        z: 30
        active: editor.editingInk.length > 0 && editor.editingInkBlock !== null

        sourceComponent: NotesInkSheet {
            noteId: root.noteId
            block: editor.editingInkBlock
            editor: editor
            onFinished: editor.editInk("")
        }
    }

    NotesPaperPicker {
        id: paperPicker
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.rightMargin: NotesMetrics.panePadding
        anchors.topMargin: 68
        z: 10
        visible: false
        current: root.paperStyle

        onPicked: style => {
            root.paperPicked(style);
            paperPicker.visible = false;
        }
    }

    NotesExportSheet {
        id: exportSheet
        anchors.fill: parent
        z: 35
        visible: false
        noteId: root.noteId
        note: root.note
        onClosed: exportSheet.visible = false
    }

    function openExportSheet() {
        exportSheet.visible = true;
    }

    /**
     * One click anywhere else puts these away.
     *
     * The page picker had no such thing and neither did the popups that came after it: the
     * only way to close one was to find the button that opened it again, which is not
     * where a hand goes.
     */
    MouseArea {
        // Everything below the header. Covering the header too meant the button that
        // opened a popup could not close it again, and switching from the page picker to
        // the menu took two clicks with nothing to show for the first.
        anchors.fill: parent
        // Below the header, whose buttons keep working: the one that opened a popup has to
        // be able to close it, and switching from the page picker to the menu should not
        // cost a click that does nothing. A number rather than an anchor to the header —
        // it lives inside a layout, and anchoring across that is not allowed. It is the
        // same inset the popups themselves hang from.
        anchors.topMargin: 68
        z: 9
        visible: paperPicker.visible || noteMenu.visible || reminderMenu.visible || lockSheet.visible
        onClicked: {
            paperPicker.visible = false;
            noteMenu.visible = false;
            reminderMenu.visible = false;
            lockSheet.visible = false;
        }
    }

    NotesNoteMenu {
        id: noteMenu
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.rightMargin: NotesMetrics.panePadding
        anchors.topMargin: 68
        z: 14
        visible: false

        items: [
            { id: "outline", symbol: "format_list_bulleted", label: Translation.tr("Table of contents") },
            { id: "history", symbol: "history", label: Translation.tr("Version history") },
            { id: "focus", symbol: "fullscreen", label: Translation.tr("Focus mode") },
            { id: "" },
            {
                id: "reminder",
                symbol: root.reminderAt > 0 ? "notifications_active" : "notifications",
                label: Translation.tr("Remind me…"),
                hint: root.reminderLabel
            },
            {
                id: "lock",
                symbol: root.isLocked ? "lock" : "lock_open",
                label: root.isLocked ? Translation.tr("Locked") : Translation.tr("Lock…")
            },
            { id: "export", symbol: "file_export", label: Translation.tr("Export…") },
            { id: "" },
            { id: "delete", symbol: "delete", label: Translation.tr("Move to the trash"), tone: "error" }
        ]

        onPicked: id => {
            noteMenu.visible = false;
            if (id === "outline")
                root.outlineRequested();
            else if (id === "history")
                root.revisionsRequested();
            else if (id === "focus")
                root.focusModeToggled();
            else if (id === "reminder")
                reminderMenu.visible = true;
            else if (id === "lock")
                lockSheet.visible = true;
            else if (id === "export")
                exportSheet.visible = true;
            else if (id === "delete")
                root.deleteRequested();
        }
    }

    NotesNoteMenu {
        id: reminderMenu
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.rightMargin: NotesMetrics.panePadding
        anchors.topMargin: 68
        z: 15
        visible: false
        title: Translation.tr("Remind me")

        readonly property var evening: {
            const when = new Date();
            when.setHours(18, 0, 0, 0);
            return when;
        }

        items: {
            const list = [
                { id: "hour", symbol: "schedule", label: Translation.tr("In an hour") }
            ];
            if (reminderMenu.evening.getTime() > Date.now() + 3600000)
                list.push({ id: "evening", symbol: "bedtime", label: Translation.tr("This evening, 18:00") });
            list.push({ id: "tomorrow", symbol: "wb_twilight", label: Translation.tr("Tomorrow, 09:00") });
            list.push({ id: "week", symbol: "date_range", label: Translation.tr("In a week") });
            if (root.reminderAt > 0) {
                list.push({ id: "" });
                list.push({
                    id: "clear",
                    symbol: "notifications_off",
                    label: Translation.tr("Forget it"),
                    hint: root.reminderLabel,
                    tone: "error"
                });
            }
            return list;
        }

        onPicked: id => {
            reminderMenu.visible = false;
            if (id === "hour") {
                root.setReminder(Date.now() + 3600000);
            } else if (id === "evening") {
                root.setReminder(reminderMenu.evening.getTime());
            } else if (id === "tomorrow") {
                const when = new Date();
                when.setDate(when.getDate() + 1);
                when.setHours(9, 0, 0, 0);
                root.setReminder(when.getTime());
            } else if (id === "week") {
                const when = new Date();
                when.setDate(when.getDate() + 7);
                when.setHours(9, 0, 0, 0);
                root.setReminder(when.getTime());
            } else if (id === "clear") {
                root.clearReminder();
            }
        }
    }

    NotesLockSheet {
        id: lockSheet
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.rightMargin: NotesMetrics.panePadding
        anchors.topMargin: 68
        z: 16
        visible: false
        hasPin: root.hasPin
        noteLocked: root.isLocked

        onPinChosen: pin => {
            root.choosePin(pin);
            lockSheet.visible = false;
        }
        onLockRequested: {
            root.lockNote();
            lockSheet.visible = false;
        }
        onUnlockRequested: {
            root.unlockNote();
            lockSheet.visible = false;
        }
    }

    NotesLockGuard {
        anchors.fill: parent
        z: 25
        visible: root.note !== null && root.isLocked && !root.unlockedThisSession
        digest: Persistent.states.notes.lockDigest
        salt: Persistent.states.notes.lockSalt
        onUnlocked: root.unlockedThisSession = true
    }

    ColumnLayout {
        id: body
        anchors.fill: parent
        anchors.margins: 0
        spacing: 0
        visible: root.note !== null

        RowLayout {
            Layout.fillWidth: true
            // The title, the metadata and the prose all start on the same line. They were
            // 28, 30 and 30, which is invisible as a decision and obvious as a wobble.
            Layout.leftMargin: NotesMetrics.readingPadding
            Layout.rightMargin: NotesMetrics.panePadding
            Layout.topMargin: 22
            spacing: 4

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: titleField.implicitHeight

                StyledTextInput {
                    id: titleField
                    anchors.fill: parent
                    // Never claimed by the window's focus chain. The note's body is what
                    // somebody opening a note wants to type in; the title is renamed
                    // deliberately, by clicking it.
                    activeFocusOnTab: false
                    focus: false
                    // Bound from the note, but only while nobody is typing in it: rebinding
                    // under the cursor is how a rename loses the last character typed.
                    text: root.note && !titleField.activeFocus ? root.note.title : titleField.text
                    font.pixelSize: Appearance.font.pixelSize.hugeass
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer0
                    readOnly: root.trash

                    onEditingFinished: root.titleEdited(titleField.text)
                    onAccepted: titleField.focus = false
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Translation.tr("Untitled note")
                    font: titleField.font
                    color: Appearance.colors.colOnLayer1Inactive
                    visible: titleField.text.length === 0
                }
            }

            /**
             * Four, and then a menu.
             *
             * These are the four a hand reaches for while reading a note — mark it, keep
             * it at the top, change the paper, get out of the way — and the eleven that
             * were here made all four harder to find than any of them is alone. The rest
             * are in the menu, which is also where the one that destroys something lives:
             * a note should not be one stray click from the trash.
             */
            NotesIconButton {
                symbol: "star"
                tooltipText: root.note && root.note.favorite
                    ? Translation.tr("Remove from favourites")
                    : Translation.tr("Add to favourites")
                colIcon: root.note && root.note.favorite ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
                visible: !root.trash
                onTriggered: root.favoriteToggled()
            }

            NotesIconButton {
                symbol: "keep"
                tooltipText: root.note && root.note.pinned
                    ? Translation.tr("Unpin")
                    : Translation.tr("Pin to the top of the list")
                colIcon: root.note && root.note.pinned ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
                visible: !root.trash
                onTriggered: root.pinToggled()
            }

            NotesIconButton {
                symbol: "grid_on"
                tooltipText: Translation.tr("Page style")
                colIcon: root.paperStyle !== "plain" ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
                visible: !root.trash
                toggled: paperPicker.visible
                colBackgroundToggled: Appearance.colors.colSecondaryContainer
                onTriggered: {
                    noteMenu.visible = false;
                    paperPicker.visible = !paperPicker.visible;
                }
            }

            NotesIconButton {
                symbol: "more_vert"
                tooltipText: Translation.tr("Everything else")
                colIcon: Appearance.colors.colOnLayer1
                visible: !root.trash
                toggled: noteMenu.visible
                colBackgroundToggled: Appearance.colors.colSecondaryContainer
                onTriggered: {
                    paperPicker.visible = false;
                    reminderMenu.visible = false;
                    lockSheet.visible = false;
                    noteMenu.visible = !noteMenu.visible;
                }
            }

            NotesIconButton {
                symbol: "restore_from_trash"
                tooltipText: Translation.tr("Put this note back")
                visible: root.trash
                onTriggered: root.restoreRequested()
            }

            /// In the trash only. Everywhere else the trash is a menu item, because the
            /// button that destroys a note should not be the one nearest the pointer when
            /// somebody is reaching for the star.
            NotesIconButton {
                symbol: "delete_forever"
                tooltipText: Translation.tr("Delete permanently")
                colIcon: Appearance.m3colors.m3error
                visible: root.trash
                onTriggered: root.deleteRequested()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: NotesMetrics.readingPadding
            Layout.rightMargin: NotesMetrics.readingPadding
            Layout.topMargin: 0
            spacing: 12

            StyledText {
                text: root.note
                    ? Translation.tr("Edited %1").arg(Qt.formatDateTime(new Date(root.note.modified), "d MMM yyyy, HH:mm"))
                    : ""
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }

            StyledText {
                text: root.note ? Translation.tr("%1 blocks").arg(root.note.blockCount) : ""
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                visible: root.note && root.note.blockCount > 1
            }

            StyledText {
                text: Translation.tr("%1 words").arg(root.wordCount)
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                visible: root.wordCount > 0
            }

            StyledText {
                text: Translation.tr("%1 min read").arg(root.readingMinutes)
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                visible: root.wordCount > 0
            }

            Item {
                Layout.fillWidth: true
            }

            /// A chip the size of the line it sits on. The 44px icon button that used to
            /// end this row was three times the height of the text beside it, and it put
            /// "forget this reminder" one twitch away from "read this reminder".
            RippleButton {
                id: reminderChip
                Layout.alignment: Qt.AlignVCenter
                visible: root.reminderAt > 0
                implicitHeight: 26
                implicitWidth: reminderChipRow.implicitWidth + 20
                buttonRadius: NotesMetrics.pillRadius(26)
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                opacity: root.reminderDone ? 0.6 : 1

                onClicked: {
                    noteMenu.visible = false;
                    reminderMenu.visible = !reminderMenu.visible;
                }

                StyledToolTip {
                    text: root.reminderDone
                        ? Translation.tr("Already mentioned. Click to change it.")
                        : Translation.tr("Click to change or forget it")
                }

                contentItem: RowLayout {
                    id: reminderChipRow
                    anchors.centerIn: parent
                    spacing: 5

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignVCenter
                        text: root.reminderDone ? "notifications" : "notifications_active"
                        iconSize: 14
                        color: Appearance.m3colors.m3onSecondaryContainer
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignVCenter
                        text: root.reminderLabel
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.m3colors.m3onSecondaryContainer
                    }
                }
            }
        }

        // ── Collapsible Backlinks ("Mentioned in") bar ────────────────────
        ColumnLayout {
            id: backlinksBar
            Layout.fillWidth: true
            Layout.leftMargin: NotesMetrics.readingPadding
            Layout.rightMargin: NotesMetrics.readingPadding
            Layout.topMargin: 6
            Layout.bottomMargin: 2
            visible: root.backlinks.length > 0
            spacing: 4

            property bool expanded: false

            RippleButton {
                implicitHeight: 28
                buttonRadius: Appearance.rounding.small
                colBackground: Appearance.m3colors.m3surfaceContainerLowest
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                leftPadding: 8
                rightPadding: 8

                contentItem: RowLayout {
                    spacing: 6
                    MaterialSymbol {
                        text: "link"
                        iconSize: 15
                        color: Appearance.colors.colPrimary
                    }
                    StyledText {
                        text: Translation.tr("Mentioned in (%1)").arg(root.backlinks.length)
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colPrimary
                    }
                    MaterialSymbol {
                        text: backlinksBar.expanded ? "expand_less" : "expand_more"
                        iconSize: 15
                        color: Appearance.colors.colPrimary
                    }
                }

                onClicked: backlinksBar.expanded = !backlinksBar.expanded
            }

            Flow {
                Layout.fillWidth: true
                visible: backlinksBar.expanded
                spacing: 6

                Repeater {
                    model: root.backlinks

                    RippleButton {
                        required property var modelData
                        implicitHeight: 28
                        buttonRadius: Appearance.rounding.small
                        colBackground: Appearance.m3colors.m3surfaceContainerLowest
                        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                        leftPadding: 8
                        rightPadding: 8

                        contentItem: RowLayout {
                            spacing: 4
                            MaterialSymbol {
                                text: "article"
                                iconSize: 14
                                color: Appearance.colors.colPrimary
                            }
                            StyledText {
                                text: modelData.title.length > 0 ? modelData.title : Translation.tr("Untitled note")
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: Appearance.colors.colOnLayer0
                            }
                        }

                        onClicked: Persistent.states.notes.noteId = modelData.id
                    }
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: 12

            // The page, under the text. Its own item rather than a property of the
            // editor: the editor scrolls, and the paper has to stay put and be *offset*
            // instead, or the pattern would slide out from under the words.
            NotesPaper {
                anchors.fill: parent
                paperStyle: root.paperStyle
                paperStrength: Math.max(0, Math.min(100, Config.options.notes.paperStrength ?? 50)) / 100
                scrollOffset: editor.scrollOffset
            }

            NotesEditor {
                id: editor
                anchors.fill: parent
                noteId: root.noteId
            }

            // Floating at the foot of the page rather than pinned above it: it belongs to
            // the block the caret is in, and following the page keeps it near the hand.
            /**
             * Sized to the page it floats on.
             *
             * Sixteen controls at full size need more width than a narrow window gives
             * the note, and the bar was simply cut off at both ends. It scales down to
             * whatever room there is, from the bottom edge it sits on, and stops at full
             * size — a toolbar bigger than its own design would be worse than a small one.
             */
            NotesEditorToolbar {
                id: editorToolbar
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 16
                transformOrigin: Item.Bottom
                scale: Math.min(1, Math.max(0.6,
                    (parent.width - NotesMetrics.paneGap * 2) / Math.max(1, editorToolbar.implicitWidth)))
                editor: editor
                opacity: editor.activeBlockId.length > 0 ? 1 : 0
                visible: opacity > 0

                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }
        }
    }
}
