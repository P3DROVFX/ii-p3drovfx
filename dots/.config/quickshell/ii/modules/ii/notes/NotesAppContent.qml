pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.notes
import "../../../services/notes/NotesSearchIndex.js" as SearchIndex

/**
 * The app inside the window: a rail of places, a list of notes, and the note itself.
 *
 * Three panes because notes are three questions at once — *where am I*, *which note*, and
 * *what does it say* — and answering them in one column means a trip back and forth for
 * every note anyone looks at. It collapses to two and then to one, in that order, because
 * the rail is the part a person can hold in their head and the note is the part they
 * cannot.
 */
Item {
    id: root

    signal closeRequested()

    readonly property var state: Persistent.states.notes

    // ── Breakpoints ───────────────────────────────────────────────────────
    // Measured from the panel, never from the screen: the window is resizable, and a
    // layout that reads the monitor would keep a three-pane layout inside a panel far too
    // narrow for it.
    readonly property bool compact: root.width < 760
    readonly property bool railExpanded: root.width >= 1100 && root.state.railExpanded

    // ── Selection ─────────────────────────────────────────────────────────

    readonly property string query: rail.query

    readonly property bool trashScope: root.state.scope === "trash"

    /// Every note the current place contains, before the search box narrows it.
    readonly property var scopedNotes: {
        const all = Array.from(NotesService.index.notes ?? []);
        const scope = root.state.scope;
        if (scope === "trash")
            return all.filter(note => note.trashedAt > 0);
        const live = all.filter(note => note.trashedAt === 0);
        if (scope === "favorites")
            return live.filter(note => note.favorite);
        if (scope === "recent")
            return live.slice().sort((a, b) => b.modified - a.modified).slice(0, 20);
        if (scope === "all" || scope.length === 0)
            return live;
        return live.filter(note => note.notebookId === scope || note.sectionId === scope);
    }

    readonly property var parsedQuery: SearchIndex.parseQuery(root.query)
    readonly property var searchTerms: root.parsedQuery.terms

    readonly property var visibleNotes: {
        const term = root.query.trim();
        const scoped = root.scopedNotes;
        if (term.length === 0) {
            return scoped.slice().sort((a, b) => {
                if (a.pinned !== b.pinned)
                    return a.pinned ? -1 : 1;
                return b.modified - a.modified;
            });
        }
        return SearchIndex.searchNotes(term, scoped, null, NotesService.notebooks);
    }

    readonly property string selectedId: {
        const wanted = root.state.noteId;
        if (root.visibleNotes.some(note => note.id === wanted))
            return wanted;
        return root.visibleNotes.length > 0 ? root.visibleNotes[0].id : "";
    }

    readonly property var selectedNote: root.visibleNotes.find(note => note.id === root.selectedId) ?? null

    /// The bar says where you are, not what you have open. The note's own title is right
    /// there in the pane beside it, and printing it twice tells the reader nothing and
    /// costs them the one thing the bar could have said.
    readonly property string scopeName: {
        const scope = root.state.scope;
        if (scope === "trash")
            return Translation.tr("Trash");
        if (scope === "favorites")
            return Translation.tr("Favourites");
        if (scope === "recent")
            return Translation.tr("Recent");
        if (scope === "all" || scope.length === 0)
            return Translation.tr("All notes");
        for (const notebook of NotesService.notebooks) {
            if (notebook.id === scope)
                return notebook.title;
            for (const section of notebook.sections) {
                if (section.id === scope)
                    return `${notebook.title} · ${section.title}`;
            }
        }
        return Translation.tr("All notes");
    }

    function select(noteId): void {
        root.state.noteId = String(noteId ?? "");
        if (root.compact)
            root.showingDetail = true;
    }

    /// Only meaningful in the one-pane layout, where list and note take turns.
    property bool showingDetail: false
    property bool focusMode: false

    /**
     * Which whole-app page is open, if any: "" is the note itself, and "settings",
     * "stats" and "templates" take its place.
     *
     * Pages, not sheets, and pages in the *third column* — where a note's own content
     * goes. Nothing dims, nothing is hidden: the rail still says where you are and the
     * list still shows the notes, so leaving is one click on either of them, and a page
     * never covers what you were reading a moment ago.
     */
    property string page: ""

    readonly property bool pageOpen: root.page.length > 0

    readonly property string barTitle: {
        if (root.page === "settings")
            return Translation.tr("Settings");
        if (root.page === "stats")
            return Translation.tr("Statistics");
        if (root.page === "templates")
            return Translation.tr("Templates");
        return root.scopeName;
    }

    readonly property string barSubtitle: {
        if (root.page === "settings")
            return Translation.tr("This app only");
        if (root.page === "stats")
            return Translation.tr("Across every note");
        if (root.page === "templates")
            return Translation.tr("Start a note with structure in it");
        if (root.query.trim().length > 0)
            return Translation.tr("%1 of %2 notes").arg(root.visibleNotes.length).arg(root.scopedNotes.length);
        if (root.visibleNotes.length === 1)
            return Translation.tr("One note");
        return Translation.tr("%1 notes").arg(root.visibleNotes.length);
    }

    // ── Actions ───────────────────────────────────────────────────────────

    function createNote(): void {
        const noteId = NotesService.createNote({ title: "" });
        root.state.noteId = noteId;
        root.showingDetail = true;
        // On a timer rather than the next turn of the loop. The window's own focus chain
        // hands active focus to the first text item in it — the note's title — when the
        // toplevel is activated, and that happens after the callLater would have run: the
        // caret ended up in the title and the first thing typed renamed the note.
        editorFocusTimer.restart();
    }

    /// A note from a template: made, filled, opened, and the page steps out of the way.
    function createFromTemplate(title, tags, blocks): void {
        const noteId = NotesService.createNote({ title: title, tags: tags });
        if (noteId && blocks && blocks.length > 0) {
            NotesService.writeDocument(noteId, {
                id: noteId,
                title: title,
                blocks: blocks
            });
        }
        root.page = "";
        root.state.noteId = noteId;
        root.showingDetail = true;
        editorFocusTimer.restart();
    }

    function deleteSelected(): void {
        if (root.selectedId.length === 0)
            return;
        if (root.trashScope)
            NotesService.purgeNote(root.selectedId);
        else
            NotesService.deleteNote(root.selectedId);
        root.state.noteId = "";
    }

    function restoreSelected(): void {
        if (root.selectedId.length > 0)
            NotesService.restoreNote(root.selectedId);
    }

    function toggleFavorite(): void {
        const note = root.selectedNote;
        if (note)
            NotesService.updateMeta(note.id, { favorite: !note.favorite });
    }

    function togglePinned(): void {
        const note = root.selectedNote;
        if (note)
            NotesService.updateMeta(note.id, { pinned: !note.pinned });
    }

    // A note the app was asked to open, from a widget, the overlay or an IPC call.
    function consumePendingNote(): void {
        const wanted = GlobalStates.notesAppPendingNote;
        if (wanted.length === 0)
            return;
        GlobalStates.notesAppPendingNote = "";
        if (NotesService.notes.some(note => note.id === wanted)) {
            root.state.scope = "all";
            root.select(wanted);
            // Asked for by name, from a widget, the overlay or a script: whoever sent that
            // wants to work on this note, not to look at a list with it highlighted.
            editorFocusTimer.restart();
        }
    }

    Timer {
        id: editorFocusTimer
        interval: 120
        onTriggered: detail.focusEditor()
    }

    Component.onCompleted: root.consumePendingNote()

    Connections {
        target: GlobalStates
        function onNotesAppPendingNoteChanged() {
            root.consumePendingNote();
        }
    }

    /**
     * The app's own shortcuts.
     *
     * `Shortcut` rather than `Keys.onPressed`, because these belong to the window and not
     * to whichever item happens to hold focus. The key handler worked only while something
     * focusable was focused, and the moment the note title stopped claiming focus on open,
     * Ctrl+N stopped existing.
     */
    Shortcut {
        sequences: ["Ctrl+N"]
        context: Qt.WindowShortcut
        onActivated: root.createNote()
    }

    Shortcut {
        sequences: ["Ctrl+F"]
        context: Qt.WindowShortcut
        onActivated: rail.focusSearch()
    }

    Shortcut {
        sequences: ["Ctrl+Shift+F"]
        context: Qt.WindowShortcut
        onActivated: root.focusMode = !root.focusMode
    }

    Shortcut {
        sequences: ["Escape"]
        context: Qt.WindowShortcut
        onActivated: {
            if (revisionsSheet.visible)
                revisionsSheet.visible = false;
            else if (root.page.length > 0)
                root.page = "";
            else if (outlineDrawer.visible)
                outlineDrawer.visible = false;
            else if (root.focusMode)
                root.focusMode = false;
            else if (root.compact && root.showingDetail)
                root.showingDetail = false;
            else if (rail.query.length > 0)
                rail.clearSearch();
            else
                root.closeRequested();
        }
    }

    NotesRevisionsSheet {
        id: revisionsSheet
        anchors.fill: parent
        z: 43
        visible: false
        noteId: root.selectedId
        currentBlocks: detail.editorBlocks
        onClosed: revisionsSheet.visible = false
        onRevisionRestored: revisionsSheet.visible = false
    }

    NotesOutline {
        id: outlineDrawer
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        anchors.margins: 12
        width: 280
        z: 38
        visible: false
        blocks: detail.editorBlocks
        onClosed: outlineDrawer.visible = false
        onHeadingClicked: blockId => {
            outlineDrawer.visible = false;
            detail.goToBlock(blockId);
        }
    }

    // ── Layout ────────────────────────────────────────────────────────────

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: NotesMetrics.paneGap
        spacing: NotesMetrics.paneGap

        NotesTopBar {
            id: topBar
            Layout.fillWidth: true
            visible: !root.focusMode
            title: root.barTitle
            subtitle: root.barSubtitle
            showBack: (root.compact && root.showingDetail) || root.page.length > 0
            showRailToggle: !root.compact && root.width >= 1100 && root.page.length === 0
            railExpanded: root.railExpanded
            statsActive: root.page === "stats"

            onRailToggled: root.state.railExpanded = !root.state.railExpanded
            onBackRequested: {
                if (root.page.length > 0)
                    root.page = "";
                else
                    root.showingDetail = false;
            }
            onStatsRequested: root.page = root.page === "stats" ? "" : "stats"
            onCloseRequested: root.closeRequested()
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            // Zero, because the gap between panes is now a splitter that occupies it. Two
            // sources of the same space would make the seam twice as wide as it looks.
            spacing: 0

            NotesNavigationRail {
                id: rail
                Layout.fillHeight: true
                Layout.preferredWidth: expanded
                    ? Math.max(NotesMetrics.railMinimumWidth,
                               Math.min(NotesMetrics.railMaximumWidth, root.state.railWidth))
                    : NotesMetrics.railCollapsedWidth
                visible: !root.compact && !root.focusMode
                expanded: root.railExpanded
                scope: root.state.scope
                settingsOpen: root.page === "settings"

                onScopePicked: scope => {
                    root.state.scope = scope;
                    root.state.noteId = "";
                    // A place was asked for, so a page that is covering the places is in
                    // the way of the answer.
                    root.page = "";
                }
                onCreateRequested: {
                    root.page = "";
                    root.createNote();
                }
                onTemplatesRequested: root.page = root.page === "templates" ? "" : "templates"
                onSettingsRequested: root.page = root.page === "settings" ? "" : "settings"

                Behavior on Layout.preferredWidth {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }

            NotesPaneSplitter {
                Layout.fillHeight: true
                // Present whenever both panes are, because this item *is* the gap between
                // them: hiding it with the rail collapsed left the two slabs touching,
                // since the row itself carries no spacing of its own.
                visible: !root.compact
                // A collapsed rail has no width worth dragging; the seam stays, the handle
                // does not.
                resizable: root.railExpanded && !root.focusMode
                Layout.preferredWidth: root.focusMode ? 0 : -1
                onMoved: delta => root.state.railWidth = Math.max(NotesMetrics.railMinimumWidth,
                    Math.min(NotesMetrics.railMaximumWidth, root.state.railWidth + delta))
            }

            NotesList {
                id: notesList
                Layout.fillHeight: true
                Layout.preferredWidth: root.compact
                    ? -1
                    : Math.max(NotesMetrics.listMinimumWidth,
                               Math.min(NotesMetrics.listMaximumWidth, root.state.listWidth))
                Layout.fillWidth: root.compact
                // A page takes the note's column, not the list's — the list is how you
                // leave one. It only steps aside in the one-column layout, where there is
                // no room for both.
                visible: !root.focusMode && (!root.compact || (!root.showingDetail && !root.pageOpen))
                notes: root.visibleNotes
                selectedId: root.selectedId
                searching: root.query.trim().length > 0
                searchTerms: root.searchTerms
                trash: root.trashScope

                onNotePicked: noteId => {
                    root.page = "";
                    root.select(noteId);
                }
                onTemplatesRequested: root.page = "templates"
            }

            NotesPaneSplitter {
                Layout.fillHeight: true
                visible: !root.compact
                resizable: !root.focusMode
                Layout.preferredWidth: root.focusMode ? 0 : -1
                onMoved: delta => root.state.listWidth = Math.max(NotesMetrics.listMinimumWidth,
                    Math.min(NotesMetrics.listMaximumWidth, root.state.listWidth + delta))
            }

            /**
             * The whole-app pages, where the list and the note would be.
             *
             * In `Loader`s because both of them cost something to exist — the statistics
             * page reads every document in the store to count what is in it — and neither
             * is open most of the time.
             */
            Loader {
                Layout.fillWidth: true
                Layout.fillHeight: true
                active: root.page === "settings"
                visible: active

                sourceComponent: NotesSettingsPage {
                    onExportRequested: {
                        root.page = "";
                        detail.openExportSheet();
                    }
                }
            }

            Loader {
                Layout.fillWidth: true
                Layout.fillHeight: true
                active: root.page === "stats"
                visible: active

                sourceComponent: NotesStatsPage {}
            }

            Loader {
                Layout.fillWidth: true
                Layout.fillHeight: true
                active: root.page === "templates"
                visible: active

                sourceComponent: NotesTemplatesPage {
                    onTemplateChosen: (title, tags, blocks) => root.createFromTemplate(title, tags, blocks)
                }
            }

            NotesDetail {
                id: detail
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: ((!root.compact || root.showingDetail) || root.focusMode) && !root.pageOpen
                note: root.selectedNote
                trash: root.trashScope

                onDeleteRequested: root.deleteSelected()
                onRestoreRequested: root.restoreSelected()
                onFavoriteToggled: root.toggleFavorite()
                onPinToggled: root.togglePinned()
                onOutlineRequested: outlineDrawer.visible = !outlineDrawer.visible
                onRevisionsRequested: revisionsSheet.visible = true
                onFocusModeToggled: root.focusMode = !root.focusMode
                onPaperPicked: style => {
                    if (root.selectedId.length > 0)
                        NotesService.updateMeta(root.selectedId, { paper: style });
                }
                onTitleEdited: title => {
                    if (root.selectedId.length > 0)
                        NotesService.updateMeta(root.selectedId, { title: title });
                }
            }
        }
    }
}
