pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.services.ai
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.notes
import "../../../../services/notes/NotesDocument.js" as Doc
import "../../../../services/notes/NotesShortcuts.js" as Shortcuts

/**
 * The editor: a list of blocks, and the one place operations are applied.
 *
 * The structural rule that everything else follows: **a text edit never rebuilds the
 * list.** The delegate owns its own text while it is being typed in, and reports it on a
 * debounce; the local `blocks` array is only replaced when the note changes or when a
 * block is inserted, removed, moved or retyped. Feeding every keystroke back through the
 * model would rebuild the delegate the cursor is sitting in, and the caret would jump to
 * the start of the line on every character.
 */
Item {
    id: root

    property string noteId: ""
    /// Blocks as the list draws them. Structural changes replace this; typing does not.
    property var blocks: []
    property bool ready: false

    property var activeTextEdit: null
    readonly property bool hasSelection: root.activeTextEdit !== null && root.activeTextEdit.selectedText.length > 0
    readonly property string selectedText: root.hasSelection ? root.activeTextEdit.selectedText : ""

    readonly property rect selectionGeometry: {
        if (!root.hasSelection || !root.activeTextEdit)
            return Qt.rect(0, 0, 0, 0);
        try {
            const te = root.activeTextEdit;
            const sMin = Math.min(te.selectionStart, te.selectionEnd);
            const sMax = Math.max(te.selectionStart, te.selectionEnd);
            const r1 = te.positionToRectangle(sMin);
            const r2 = te.positionToRectangle(sMax);
            const startPoint = te.mapToItem(root, r1.x, r1.y);
            const endPoint = te.mapToItem(root, r2.x + r2.width, r2.y + r2.height);
            return Qt.rect(
                Math.min(startPoint.x, endPoint.x),
                startPoint.y,
                Math.max(24, Math.abs(endPoint.x - startPoint.x)),
                Math.max(r1.height, (endPoint.y - startPoint.y) + r2.height)
            );
        } catch (e) {
            return Qt.rect(0, 0, 0, 0);
        }
    }

    property bool aiMenuOpen: false
    property bool aiCompareOpen: false

    function openAiMenu(requestedScope = ""): void {
        let scope = requestedScope;
        let text = "";
        let blockId = root.activeBlockId;

        if (!scope) {
            if (root.hasSelection)
                scope = "selection";
            else if (root.activeBlock)
                scope = "block";
            else
                scope = "note";
        }

        if (scope === "selection" && root.hasSelection) {
            text = root.selectedText;
        } else if (scope === "block" && root.activeBlock) {
            text = root.activeBlock.text ?? "";
        } else {
            scope = "note";
            const doc = NotesService.documentOf(root.noteId);
            text = doc ? Doc.contentString(doc) : "";
        }

        aiMenu.targetScope = scope;
        aiMenu.targetText = text;
        aiMenu.targetBlockId = blockId;
        root.aiMenuOpen = true;
    }

    function replaceActiveSelection(newText): void {
        if (!root.activeTextEdit)
            return;
        const te = root.activeTextEdit;
        const sMin = Math.min(te.selectionStart, te.selectionEnd);
        const sMax = Math.max(te.selectionStart, te.selectionEnd);
        const full = te.text;
        const replaced = full.slice(0, sMin) + newText + full.slice(sMax);
        te.text = replaced;
        te.select(sMin, sMin + newText.length);
        if (root.activeBlockId)
            root.commitText(root.activeBlockId, replaced);
    }

    function onAiReplace(newText): void {
        const mode = aiCompareSheet.mode;
        if (mode === "selection" && root.hasSelection) {
            root.replaceActiveSelection(newText);
        } else if (mode === "block" && aiCompareSheet.targetBlockId) {
            root.apply([{ op: "update", id: aiCompareSheet.targetBlockId, patch: { text: newText } }]);
        } else if (mode === "title") {
            NotesService.updateMeta(root.noteId, { title: newText.trim() });
        } else if (mode === "tags") {
            const rawTags = newText.match(/#[^\s#]+/g) || [];
            const tags = rawTags.map(t => t.replace(/^#/, ""));
            if (tags.length > 0)
                NotesService.updateMeta(root.noteId, { tags: tags });
        } else {
            if (aiCompareSheet.taskTitle.indexOf("Resumo") !== -1 || aiCompareSheet.taskTitle.indexOf("Summary") !== -1) {
                root.apply([{ op: "insert", index: 0, block: { type: "callout", tone: "info", text: newText } }]);
            } else {
                if (root.activeBlockId)
                    root.apply([{ op: "update", id: root.activeBlockId, patch: { text: newText } }]);
                else if (root.blocks.length > 0)
                    root.apply([{ op: "update", id: root.blocks[0].id, patch: { text: newText } }]);
            }
        }
    }

    function onAiInsertBelow(newText): void {
        const targetId = aiCompareSheet.targetBlockId || root.activeBlockId;
        const at = targetId.length > 0
            ? root.indexOfBlock(targetId) + 1
            : root.blocks.length;
        root.apply([{ op: "insert", index: at, block: { type: "text", text: newText } }]);
    }

    readonly property int count: root.blocks.length

    /// How far the page has been scrolled, so the paper behind it can travel along.
    readonly property real scrollOffset: list.contentY

    signal blockFocused(string blockId)

    // ── Loading ───────────────────────────────────────────────────────────

    /**
     * Everything about the blocks *except* their text.
     *
     * Text is the one field a delegate owns while it is being typed in, so a change to it
     * must not rebuild the row the caret is in. Everything else has to reach the delegate:
     * an earlier version compared only id, type and indent, and the result was that a
     * drawing saved its picture and its strokes to disk and the block on screen never
     * heard about either — it went on offering to start a new drawing over a note that
     * already had one.
     */
    function signatureOf(blocks): string {
        return JSON.stringify(Doc.asArray(blocks).map(item => {
            const copy = {};
            for (const key in item) {
                if (key !== "text")
                    copy[key] = item[key];
            }
            return copy;
        }));
    }

    /**
     * Reads the document again.
     *
     * Safe to call at any time, because it replaces `blocks` only when the *structure*
     * changed. That matters more than it sounds: a document can arrive after the note has
     * been selected — the file is read asynchronously — and an editor that only looked
     * once would show an empty page over a note that has text in it. The first thing typed
     * would then be saved over the real content.
     */
    function syncFromDocument(): void {
        const document = root.noteId.length > 0 ? NotesService.documentOf(root.noteId) : null;
        const next = document ? Doc.asArray(document.blocks) : [];
        root.ready = document !== null;
        if (root.signatureOf(next) !== root.signatureOf(root.blocks))
            root.blocks = next;
        if (root.pendingAutoFocus && root.blocks.length > 0) {
            root.pendingAutoFocus = false;
            root.focusFirstBlock();
        }
    }

    onNoteIdChanged: {
        root.undoStack = [];
        root.redoStack = [];
        root.syncFromDocument();
    }

    Connections {
        target: NotesService
        function onNoteChanged(noteId) {
            // Only when somebody else changed it. Our own writes already match what the
            // delegates are showing, and resyncing would rebuild the row being typed in.
            if (noteId === root.noteId && !root.writingOurselves)
                root.syncFromDocument();
        }
        function onDataChanged() {
            // Not gated on readiness any more: this is how a document that finished
            // loading after its note was selected reaches the editor at all.
            root.syncFromDocument();
        }
    }

    property bool writingOurselves: false

    /**
     * Whether the caret should land in the note as soon as it loads.
     *
     * Set by whoever *made* the note, not by whoever opened one. Selecting a note in the
     * list should leave the keyboard where it was so the list can still be walked with the
     * arrows; a note that was just created has nowhere else the caret could reasonably be.
     */
    property bool pendingAutoFocus: false

    function focusFirstBlock(): void {
        const typable = root.blocks.find(item =>
            ["text", "heading", "list", "quote", "callout"].includes(item.type));
        if (typable)
            root.focusRequest = typable.id;
    }

    function requestAutoFocus(): void {
        if (root.blocks.length > 0)
            root.focusFirstBlock();
        else
            root.pendingAutoFocus = true;
    }

    // ── Operations ────────────────────────────────────────────────────────

    property var undoStack: []
    property var redoStack: []
    readonly property int undoLimit: 200

    /**
     * The single way anything changes.
     *
     * `structural` says whether the list has to be rebuilt afterwards. A text update does
     * not: the delegate already shows what was written.
     */
    function apply(ops, structural = true, recordUndo = true): bool {
        if (root.noteId.length === 0)
            return false;
        root.writingOurselves = true;
        const result = NotesService.applyOps(root.noteId, ops);
        root.writingOurselves = false;
        if (!result.ok || !result.changed)
            return false;
        if (recordUndo) {
            root.undoStack = root.undoStack.concat([result.inverse]).slice(-root.undoLimit);
            root.redoStack = [];
        }
        if (structural)
            root.syncFromDocument();
        return true;
    }

    function undo(): void {
        if (root.undoStack.length === 0)
            return;
        const ops = root.undoStack[root.undoStack.length - 1];
        root.undoStack = root.undoStack.slice(0, -1);
        root.writingOurselves = true;
        const result = NotesService.applyOps(root.noteId, ops);
        root.writingOurselves = false;
        if (result.ok && result.changed)
            root.redoStack = root.redoStack.concat([result.inverse]);
        root.syncFromDocument();
    }

    function redo(): void {
        if (root.redoStack.length === 0)
            return;
        const ops = root.redoStack[root.redoStack.length - 1];
        root.redoStack = root.redoStack.slice(0, -1);
        root.writingOurselves = true;
        const result = NotesService.applyOps(root.noteId, ops);
        root.writingOurselves = false;
        if (result.ok && result.changed)
            root.undoStack = root.undoStack.concat([result.inverse]);
        root.syncFromDocument();
    }

    function blockAt(index): var {
        return index >= 0 && index < root.blocks.length ? root.blocks[index] : null;
    }

    function indexOfBlock(blockId): int {
        return root.blocks.findIndex(item => item.id === blockId);
    }

    /**
     * Brings a block into view and puts the caret in it.
     *
     * The table of contents had no way to do this: clicking a heading closed the drawer
     * and left the page exactly where it was, which looks like the click missed.
     */
    function goToBlock(blockId): void {
        const at = root.indexOfBlock(blockId);
        if (at < 0)
            return;
        list.positionViewAtIndex(at, ListView.Beginning);
        root.focusCaret = 0;
        root.focusRequest = blockId;
        root.focusTick++;
    }

    // ── What the delegates ask for ────────────────────────────────────────

    /// Text as it is typed. Not structural: the delegate is already showing this.
    function commitText(blockId, text): void {
        root.apply([{ op: "update", id: blockId, patch: { text: text } }], false);
    }

    /**
     * A markdown prefix was typed. The block becomes what it says and the prefix goes.
     *
     * Returns the text the delegate should now show, or null when nothing applied — the
     * delegate cannot read it back from the model, because the model is not rebuilt for
     * text edits.
     */
    function tryShortcut(blockId, text): var {
        const index = root.indexOfBlock(blockId);
        const block = root.blockAt(index);
        if (!block)
            return null;
        const conversion = Shortcuts.conversionFor(block, text);
        if (!conversion)
            return null;
        if (!root.apply(Shortcuts.conversionOperations(block, conversion, index)))
            return null;
        root.focusRequest = conversion.type === "divider"
            ? root.blockIdAt(index + 1)
            : blockId;
        return conversion.text;
    }

    function blockIdAt(index): string {
        const block = root.blockAt(index);
        return block ? block.id : "";
    }

    /// Enter. Splits here, or leaves the list when the item is empty.
    function splitAt(blockId, offset, text): void {
        const index = root.indexOfBlock(blockId);
        const block = root.blockAt(index);
        if (!block)
            return;
        const current = Object.assign({}, block, { text: text });
        if (Shortcuts.shouldExit(current)) {
            root.apply(Shortcuts.exitOperations(current));
            root.focusRequest = blockId;
            return;
        }
        // The typed text has to land first: the split reads the block's text from the
        // document, and the document has not seen this keystroke yet.
        root.apply([{ op: "update", id: blockId, patch: { text: text } }], false, false);
        if (root.apply([{ op: "split", id: blockId, offset: offset }]))
            root.focusRequest = root.blockIdAt(index + 1);
    }

    /// Backspace at the very start. Joins this block onto the one above.
    function mergeInto(blockId, text): void {
        const index = root.indexOfBlock(blockId);
        const block = root.blockAt(index);
        if (!block || index <= 0)
            return;
        // A structured empty block becomes a paragraph first: backspace at the start of a
        // bullet should undo the bullet, not eat the line above it.
        if (block.type !== "text" && String(text).length === 0) {
            root.apply([{ op: "setType", id: blockId, type: "text", props: { text: "", indent: block.indent ?? 0 } }]);
            root.focusRequest = blockId;
            return;
        }
        const previous = root.blockAt(index - 1);
        root.apply([{ op: "update", id: blockId, patch: { text: text } }], false, false);
        const caret = previous && previous.hasOwnProperty("text") ? String(previous.text).length : 0;
        if (root.apply([{ op: "merge", id: blockId }])) {
            root.focusRequest = previous.id;
            root.focusCaret = caret;
        }
    }

    function indent(blockId, delta): void {
        root.apply([{ op: "indent", id: blockId, delta: delta }]);
        root.focusRequest = blockId;
    }

    function setType(blockId, type, props = null): void {
        root.apply([{ op: "setType", id: blockId, type: type, props: props ?? {} }]);
        root.focusRequest = blockId;
    }

    function toggleChecked(blockId): void {
        const block = root.blockAt(root.indexOfBlock(blockId));
        if (!block || block.type !== "list" || block.style !== "checkbox")
            return;
        root.apply([{ op: "update", id: blockId, patch: { checked: !block.checked } }]);
    }

    /**
     * Resizing a picture, live.
     *
     * Applied without a resync on purpose: the signature includes `width`, so a resync
     * would rebuild the row on every frame of the drag and take the grip out from under
     * the pointer. The delegate is told directly instead, and the document catches up when
     * something else resyncs.
     */
    function setImageWidth(blockId, fraction): void {
        root.apply([{ op: "update", id: blockId, patch: { width: fraction } }], false);
        root.liveWidths[blockId] = fraction;
        root.liveWidthsChanged();
    }

    /// Widths being dragged right now, so the picture follows the pointer without the list
    /// being rebuilt underneath it.
    property var liveWidths: ({})

    /**
     * Brings a file into the note as a picture.
     *
     * Two steps, because the copy is asynchronous: the file is handed to the store, and
     * the block is inserted when the store reports the name it landed under. Inserting
     * first and hoping would leave a block pointing at a name the helper may have had to
     * change to avoid overwriting something.
     */
    property string pendingImageFor: ""
    property int pendingImageIndex: -1

    function insertImageFromFile(path): void {
        if (root.noteId.length === 0)
            return;
        root.pendingImageFor = root.noteId;
        root.pendingImageIndex = root.activeBlockId.length > 0
            ? root.indexOfBlock(root.activeBlockId) + 1
            : root.blocks.length;
        NotesService.importAsset(root.noteId, String(path));
    }

    Connections {
        target: NotesService
        function onAssetImported(noteId, name) {
            if (noteId !== root.pendingImageFor || name.length === 0)
                return;
            const at = root.pendingImageIndex < 0 ? root.blocks.length : root.pendingImageIndex;
            root.pendingImageFor = "";
            root.pendingImageIndex = -1;
            root.apply([{ op: "insert", index: at, block: { type: "image", asset: name } }]);
        }
    }

    /// The picture somebody asked to see full size, or "".
    property string viewingImage: ""

    /// The drawing being worked on, or "". The sheet is hosted by the pane rather than by
    /// the block: it needs the whole page, and a surface that grew out of a row between
    /// two paragraphs would push the note around while somebody drew on it.
    property string editingInk: ""
    readonly property var editingInkBlock: root.blockAt(root.indexOfBlock(root.editingInk))

    function editInk(blockId): void {
        root.editingInk = String(blockId ?? "");
    }

    /// A fresh drawing, appended after the caret and opened straight away.
    function insertInk(): void {
        const at = root.activeBlockId.length > 0
            ? root.indexOfBlock(root.activeBlockId) + 1
            : root.blocks.length;
        if (!root.apply([{ op: "insert", index: at, block: { type: "ink" } }]))
            return;
        root.editInk(root.blockIdAt(at));
    }

    function viewImage(path): void {
        root.viewingImage = String(path ?? "");
    }

    /**
     * Pastes whatever the clipboard holds.
     *
     * The clipboard has to be *asked* what it holds, and asking is a subprocess, so this
     * cannot answer synchronously — which is why the text block hands the keystroke over
     * rather than deciding for itself. An image becomes a block; anything else is pasted
     * as text by the field that asked, one frame later.
     */
    signal pasteFellThrough()

    function pasteFromClipboard(): void {
        if (root.noteId.length === 0 || pasteProbe.running)
            return;
        pasteProbe.running = true;
    }

    Process {
        id: pasteProbe
        // One command rather than a probe and a fetch: two runs can see two different
        // clipboards, and the second would write a file for an image that is no longer
        // there.
        command: ["bash", "-c",
            `set -e
             type=$(wl-paste --list-types 2>/dev/null | grep -m1 '^image/') || true
             if [ -z "$type" ]; then echo NONE; exit 0; fi
             mkdir -p ${Directories.tempImages}
             out=${Directories.tempImages}/paste-$(date +%s%N).png
             wl-paste --type "$type" > "$out"
             echo "$out"`]

        stdout: StdioCollector {
            id: pasteOutput
            onStreamFinished: {
                const answer = pasteOutput.text.trim();
                if (answer.length === 0 || answer === "NONE") {
                    root.pasteFellThrough();
                    return;
                }
                root.insertImageFromFile(answer);
            }
        }
    }

    /**
     * Files dropped on the page.
     *
     * Images become an image block with asset copy; all other files become a fileLink card.
     */
    DropArea {
        anchors.fill: parent
        keys: ["text/uri-list"]

        onDropped: drop => {
            for (const url of drop.urls) {
                const rawPath = String(url).replace(/^file:\/\//, "");
                const path = decodeURIComponent(rawPath);
                if (/\.(png|jpe?g|gif|webp|bmp|svg)$/i.test(path))
                    root.insertImageFromFile(path);
                else
                    root.insertFile(path);
            }
        }
    }

    /// Puts a new block after the one the caret is in, which is where somebody asking for
    /// a table expects it — not at the end of the note.
    function insertBlock(type, props): void {
        const at = root.activeBlockId.length > 0
            ? root.indexOfBlock(root.activeBlockId) + 1
            : root.blocks.length;
        const made = Object.assign({ type: type }, props ?? {});
        if (root.apply([{ op: "insert", index: at, block: made }]))
            root.focusRequest = root.blockIdAt(at);
    }

    function insertFile(path): void {
        if (root.noteId.length === 0 || !path)
            return;
        const at = root.activeBlockId.length > 0
            ? root.indexOfBlock(root.activeBlockId) + 1
            : root.blocks.length;
        root.apply([{
            op: "insert",
            index: at,
            block: { type: "fileLink", path: String(path) }
        }]);
    }

    function insertLinkPreview(url, atIndex = -1): void {
        if (root.noteId.length === 0 || !url)
            return;
        const at = atIndex >= 0 ? atIndex : (root.activeBlockId.length > 0
            ? root.indexOfBlock(root.activeBlockId) + 1
            : root.blocks.length);
        root.apply([{
            op: "insert",
            index: at,
            block: { type: "linkPreview", url: String(url) }
        }]);
    }

    /// The file chooser, through the same helpers the rest of the shell uses.
    function pickImage(): void {
        if (!imagePicker.running)
            imagePicker.running = true;
    }

    Process {
        id: imagePicker
        command: ["bash", "-c",
            `if command -v zenity >/dev/null; then
                 zenity --file-selection --title="Insert a picture" \
                     --file-filter='Images | *.png *.jpg *.jpeg *.gif *.webp *.bmp *.svg' 2>/dev/null
             elif command -v kdialog >/dev/null; then
                 kdialog --getopenfilename "$HOME" 'image/png image/jpeg image/gif image/webp' 2>/dev/null
             fi`]

        stdout: StdioCollector {
            id: pickerOutput
            onStreamFinished: {
                const path = pickerOutput.text.trim();
                if (path.length > 0)
                    root.insertImageFromFile(path);
            }
        }
    }

    function pickFile(): void {
        if (!filePicker.running)
            filePicker.running = true;
    }

    Process {
        id: filePicker
        command: ["bash", "-c",
            `if command -v zenity >/dev/null; then
                 zenity --file-selection --title="Attach a file" 2>/dev/null
             elif command -v kdialog >/dev/null; then
                 kdialog --getopenfilename "$HOME" 2>/dev/null
             fi`]

        stdout: StdioCollector {
            id: filePickerOutput
            onStreamFinished: {
                const path = filePickerOutput.text.trim();
                if (path.length > 0) {
                    if (/\.(png|jpe?g|gif|webp|bmp|svg)$/i.test(path))
                        root.insertImageFromFile(path);
                    else
                        root.insertFile(path);
                }
            }
        }
    }

    function removeBlock(blockId): void {
        const index = root.indexOfBlock(blockId);
        root.apply([{ op: "delete", id: blockId }]);
        root.focusRequest = root.blockIdAt(Math.max(0, index - 1));
    }

    function moveFocus(blockId, delta): void {
        const index = root.indexOfBlock(blockId);
        const next = index + delta;
        if (next < 0 || next >= root.blocks.length)
            return;
        root.focusRequest = root.blockIdAt(next);
        root.focusCaret = delta < 0 ? -1 : 0;
    }

    /// Which block should take the caret next, and where in it. Consumed by the delegate
    /// that matches, because only it knows when it is ready to be focused.
    property string focusRequest: ""
    /// -1 means the end of the block; 0 or more is an offset.
    property int focusCaret: -1

    /**
     * Bumped to ask the delegates to look again.
     *
     * A structural change rebuilds every delegate, and the one that should take the caret
     * may not exist yet when the request is made — its `Component.onCompleted` runs before
     * the Loader has even handed it a reference to this editor, so it has nothing to ask.
     * Rather than depend on the order those things happen in, the request is repeated a
     * frame later and the delegates check again.
     */
    property int focusTick: 0

    onFocusRequestChanged: {
        if (root.focusRequest.length > 0)
            refocusTimer.restart();
    }

    Timer {
        id: refocusTimer
        // As short as a timer can be. The caret has to come back within one frame of the
        // conversion, or a keystroke typed in that gap has nowhere to land — which costs
        // the first character of whatever follows a markdown prefix.
        interval: 1
        repeat: false
        onTriggered: root.focusTick++
    }

    /**
     * Whether this block is the one that should take the caret, and where in it.
     *
     * A *look*, not a claim. Clearing the request here is what broke the caret after a
     * markdown conversion: the delegate that answered was rebuilt an instant later and
     * died before it could act, and by then the request it had already cleared was gone —
     * so nothing took the focus and the next keystroke went nowhere.
     *
     * `-2` means "not you".
     */
    function peekFocus(blockId): int {
        return root.focusRequest === blockId ? root.focusCaret : -2;
    }

    /// Called by the delegate once it actually has the caret.
    function clearFocusRequest(blockId): void {
        if (root.focusRequest !== blockId)
            return;
        root.focusRequest = "";
        root.focusCaret = -1;
    }

    /// The block the caret is in, for the toolbar.
    property string activeBlockId: ""
    readonly property var activeBlock: root.blockAt(root.indexOfBlock(root.activeBlockId))

    // ── The list ──────────────────────────────────────────────────────────

    ListView {
        id: list
        anchors.fill: parent
        model: root.blocks
        spacing: 0
        clip: true
        // Every block has to exist for the caret to be able to reach it with the keyboard,
        // and a note is a page rather than a feed.
        cacheBuffer: 20000

        delegate: NoteBlockDelegate {
            required property var modelData
            required property int index
            width: list.width
            editor: root
            block: modelData
            blockIndex: index
        }

        footer: Item {
            // A fixed height. Sizing it from the space left in the view reads
            // `contentHeight`, which the footer is part of — a binding loop that keeps the
            // list relaying out, rebuilding the delegate the caret is in and dropping the
            // focus on every pass.
            height: 200

            // Clicking the space under the last block puts the caret in it, or makes a
            // paragraph when the note ends in something you cannot type into.
            MouseArea {
                anchors.fill: parent
                onClicked: {
                    const last = root.blockAt(root.blocks.length - 1);
                    if (last && ["text", "heading", "list", "quote", "callout"].includes(last.type))
                        root.focusRequest = last.id;
                    else
                        root.apply([{ op: "insert", index: root.blocks.length, block: { type: "text" } }]);
                }
            }
        }
    }

    AiTextTask {
        id: aiTask
    }

    NotesSelectionBar {
        id: selectionBar
        editor: root
        onAiRequested: root.openAiMenu("selection")
    }

    Rectangle {
        id: aiMenuBackdrop
        anchors.fill: parent
        z: 40
        visible: root.aiMenuOpen
        color: Qt.rgba(0, 0, 0, 0.45)

        MouseArea {
            anchors.fill: parent
            onClicked: root.aiMenuOpen = false
        }

        NotesAiMenu {
            id: aiMenu
            anchors.centerIn: parent
            width: Math.min(parent.width - 32, 420)
            height: Math.min(parent.height - 32, 520)
            editor: root

            onActionRequested: (taskName, systemPrompt, userText, meta) => {
                root.aiMenuOpen = false;
                aiTask.start(systemPrompt, userText);
                aiCompareSheet.taskTitle = taskName;
                aiCompareSheet.originalText = userText;
                aiCompareSheet.proposedText = "";
                aiCompareSheet.task = aiTask;
                aiCompareSheet.targetBlockId = meta.blockId ?? "";
                aiCompareSheet.mode = meta.mode ?? "selection";
                root.aiCompareOpen = true;
            }

            onChatRequested: contextText => {
                if (contextText.length > 0)
                    Quickshell.execDetached(["wl-copy", "--", contextText]);
                GlobalStates.sidebarLeftOpen = true;
            }

            onClosed: root.aiMenuOpen = false
        }
    }

    NotesAiCompareSheet {
        id: aiCompareSheet
        anchors.fill: parent
        z: 50
        visible: root.aiCompareOpen

        onReplaceRequested: (newText) => {
            root.onAiReplace(newText);
            root.aiCompareOpen = false;
        }

        onInsertBelowRequested: (newText) => {
            root.onAiInsertBelow(newText);
            root.aiCompareOpen = false;
        }

        onDiscardRequested: {
            root.aiCompareOpen = false;
        }
    }

    Component.onCompleted: root.syncFromDocument()
}
