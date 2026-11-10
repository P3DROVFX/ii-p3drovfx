pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.services.ai
import qs.services.ai.blocks
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.notes
import "../../../../services/notes/NotesDocument.js" as Doc
import "../../../../services/notes/NotesMarkdown.js" as Markdown
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

    /// Bottom breathing room so the active line is never hidden under the floating toolbar.
    readonly property int bottomClearance: 96
    property var imageDimensions: ({})

    property var activeTextEdit: null
    readonly property bool hasActiveTextFocus: (root.activeTextEdit !== null && root.activeTextEdit.activeFocus)
        || root.activeBlockId.length > 0
    readonly property bool hasSelection: (root.activeTextEdit !== null && root.activeTextEdit.selectedText.length > 0)
        || (root.activeTextEdit !== null && root.activeTextEdit.activeFocus && root.lastSelectionBlockId === root.activeBlockId && root.lastSelectionText.length > 0)
    readonly property string selectedText: root.activeTextEdit !== null && root.activeTextEdit.selectedText.length > 0
        ? root.activeTextEdit.selectedText
        : (root.hasSelection ? root.lastSelectionText : "")
    readonly property int selectedStart: root.activeTextEdit !== null && root.activeTextEdit.selectionStart !== root.activeTextEdit.selectionEnd
        ? Math.min(root.activeTextEdit.selectionStart, root.activeTextEdit.selectionEnd)
        : root.lastSelectionStart
    readonly property int selectedEnd: root.activeTextEdit !== null && root.activeTextEdit.selectionStart !== root.activeTextEdit.selectionEnd
        ? Math.max(root.activeTextEdit.selectionStart, root.activeTextEdit.selectionEnd)
        : root.lastSelectionEnd

    readonly property rect selectionGeometry: {
        if (!root.hasSelection || !root.activeTextEdit)
            return Qt.rect(0, 0, 0, 0);
        try {
            const te = root.activeTextEdit;
            const sMin = root.selectedStart;
            const sMax = root.selectedEnd;
            if (sMin < 0 || sMax <= sMin)
                return Qt.rect(0, 0, 0, 0);
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
    // Latches true the first time AI is invoked, then gates the deferred AI
    // Loader below. Keeps the AI task/menu/compare tree (N1: ~78 MiB PSS) out
    // of the eager editor for the common case of editing without AI.
    property bool aiLoaded: false
    property bool externalAiGenerationActive: false
    readonly property bool aiBusy: root.externalAiGenerationActive
        || (aiLoader.item && aiLoader.item.aiTask && aiLoader.item.aiTask.running)
    property bool pendingAiMenuRequest: false
    property string pendingAiScope: ""
    property string pendingAiText: ""
    property string pendingAiBlockId: ""

    // The selection belongs to the block, not to the focus state. Opening the AI menu
    // moves focus into the menu, so activeTextEdit can become null before Replace is
    // clicked; these coordinates keep the original selection addressable in that case.
    property string aiSelectionBlockId: ""
    property string aiSelectionText: ""
    property int aiSelectionStart: -1
    property int aiSelectionEnd: -1

    // Text inputs clear activeTextEdit as soon as the AI toolbar receives focus. Keep a
    // value-only snapshot while the selection is live so the toolbar can still open AI
    // after that focus transition.
    property string lastSelectionBlockId: ""
    property string lastSelectionText: ""
    property string lastSelectionFullText: ""
    property int lastSelectionStart: -1
    property int lastSelectionEnd: -1

    onAiBusyChanged: {
        if (!root.aiBusy)
            return;
        Qt.callLater(() => {
            if (root && root.aiBusy)
                list.positionViewAtEnd();
        });
    }

    function rememberSelection(textEdit, blockId): void {
        if (!textEdit || !textEdit.activeFocus)
            return;
        if (textEdit.selectionStart === textEdit.selectionEnd) {
            if (root.lastSelectionBlockId === String(blockId ?? "")) {
                root.lastSelectionBlockId = "";
                root.lastSelectionText = "";
                root.lastSelectionFullText = "";
                root.lastSelectionStart = -1;
                root.lastSelectionEnd = -1;
            }
            return;
        }
        const start = Math.min(textEdit.selectionStart, textEdit.selectionEnd);
        const end = Math.max(textEdit.selectionStart, textEdit.selectionEnd);
        const selected = String(textEdit.selectedText ?? "");
        if (selected.length === 0)
            return;
        root.lastSelectionBlockId = String(blockId ?? "");
        root.lastSelectionText = selected;
        root.lastSelectionFullText = String(textEdit.text ?? "");
        root.lastSelectionStart = start;
        root.lastSelectionEnd = end;
    }

    /// Leaves a Markdown block in its rendered state before an AI result is committed.
    /// TextEdit is intentionally the source view while focused, so keeping the old caret
    /// here would make freshly generated formatting look like plain text until the window
    /// was closed.
    function clearTextFocus(): void {
        const te = root.activeTextEdit;
        root.focusRequest = "";
        root.focusCaret = -1;
        if (te) {
            if (typeof te.deselect === "function")
                te.deselect();
            te.focus = false;
        }
        root.activeTextEdit = null;
        root.activeBlockId = "";
        root.lastSelectionBlockId = "";
        root.lastSelectionText = "";
        root.lastSelectionFullText = "";
        root.lastSelectionStart = -1;
        root.lastSelectionEnd = -1;
    }

    function presentPendingAiMenu(): void {
        if (!root.pendingAiMenuRequest || !aiLoader.item)
            return;
        const menu = aiLoader.item.aiMenu;
        if (!menu)
            return;
        menu.targetScope = root.pendingAiScope;
        menu.targetText = root.pendingAiText;
        menu.targetBlockId = root.pendingAiBlockId;
        root.pendingAiMenuRequest = false;
        root.aiMenuOpen = true;
    }

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
            const te = root.activeTextEdit;
            root.aiSelectionBlockId = root.activeBlockId;
            root.aiSelectionText = te.text;
            root.aiSelectionStart = Math.min(te.selectionStart, te.selectionEnd);
            root.aiSelectionEnd = Math.max(te.selectionStart, te.selectionEnd);
        } else if (scope === "selection" && root.lastSelectionBlockId.length > 0) {
            const cachedIndex = root.indexOfBlock(root.lastSelectionBlockId);
            const cachedBlock = root.blockAt(cachedIndex);
            const cachedFullText = cachedBlock
                ? (root.lastSelectionFullText.length > 0
                    ? root.lastSelectionFullText
                    : String(cachedBlock.text ?? ""))
                : "";
            if (cachedBlock && root.lastSelectionStart >= 0 && root.lastSelectionEnd > root.lastSelectionStart
                && root.lastSelectionEnd <= cachedFullText.length) {
                blockId = root.lastSelectionBlockId;
                text = root.lastSelectionText;
                root.aiSelectionBlockId = blockId;
                root.aiSelectionText = cachedFullText;
                root.aiSelectionStart = root.lastSelectionStart;
                root.aiSelectionEnd = root.lastSelectionEnd;
            } else {
                root.aiSelectionBlockId = "";
                root.aiSelectionText = "";
                root.aiSelectionStart = -1;
                root.aiSelectionEnd = -1;
                scope = root.activeBlock ? "block" : "note";
            }
        } else {
            root.aiSelectionBlockId = "";
            root.aiSelectionText = "";
            root.aiSelectionStart = -1;
            root.aiSelectionEnd = -1;
            if (scope === "selection")
                scope = root.activeBlock ? "block" : "note";
        }

        if (scope === "block" && root.activeBlock) {
            text = root.activeBlock.text ?? "";
        } else if (scope !== "selection") {
            scope = "note";
            const doc = NotesService.documentOf(root.noteId);
            text = doc ? Doc.contentString(doc) : "";
        }

        root.pendingAiScope = scope;
        root.pendingAiText = text;
        root.pendingAiBlockId = blockId;
        root.pendingAiMenuRequest = true;
        root.aiLoaded = true;
        root.presentPendingAiMenu();
    }

    function replaceActiveSelection(newText): void {
        const replacement = String(newText ?? "");
        const te = root.activeTextEdit;
        if (te && root.hasSelection) {
            const sMin = Math.min(te.selectionStart, te.selectionEnd);
            const sMax = Math.max(te.selectionStart, te.selectionEnd);
            const full = te.text;
            const replaced = full.slice(0, sMin) + replacement + full.slice(sMax);
            te.text = replaced;
            te.select(sMin, sMin + replacement.length);
            if (root.activeBlockId)
                root.commitText(root.activeBlockId, replaced);
            Qt.callLater(() => {
                if (!root || !te)
                    return;
                te.deselect();
                te.focus = false;
                if (root.activeTextEdit === te)
                    root.activeTextEdit = null;
            });
            return;
        }

        const blockId = root.aiSelectionBlockId;
        const block = root.blockAt(root.indexOfBlock(blockId));
        if (!block || root.aiSelectionStart < 0 || root.aiSelectionEnd < root.aiSelectionStart)
            return;
        const full = root.aiSelectionText.length > 0
            ? root.aiSelectionText
            : String(block.text ?? "");
        const start = Math.min(root.aiSelectionStart, full.length);
        const end = Math.min(root.aiSelectionEnd, full.length);
        const replaced = full.slice(0, start) + replacement + full.slice(end);
        if (!root.apply([{ op: "update", id: blockId, patch: { text: replaced } }]))
            return;
        root.syncFromDocument(true);
        root.focusCaret = -1;
        root.focusRequest = "";
    }

    function onAiReplace(newText): void {
        const cs = aiLoader.item.aiCompareSheet;
        const mode = cs.mode;
        if (mode === "selection") {
            root.replaceActiveSelection(newText);
        } else if (mode === "block" && cs.targetBlockId) {
            if (root.apply([{ op: "update", id: cs.targetBlockId, patch: { text: newText } }]))
                root.syncFromDocument(true);
        } else if (mode === "title") {
            NotesService.updateMeta(root.noteId, { title: newText.trim() });
        } else if (mode === "tags") {
            const rawTags = newText.match(/#[^\s#]+/g) || [];
            const tags = rawTags.map(t => t.replace(/^#/, ""));
            if (tags.length > 0)
                NotesService.updateMeta(root.noteId, { tags: tags });
        } else {
            if (cs.taskTitle.indexOf("Resumo") !== -1 || cs.taskTitle.indexOf("Summary") !== -1) {
                root.apply([{ op: "insert", index: 0, block: { type: "callout", tone: "info", text: newText } }]);
            } else {
                if (root.activeBlockId) {
                    if (root.apply([{ op: "update", id: root.activeBlockId, patch: { text: newText } }]))
                        root.syncFromDocument(true);
                } else if (root.blocks.length > 0) {
                    if (root.apply([{ op: "update", id: root.blocks[0].id, patch: { text: newText } }]))
                        root.syncFromDocument(true);
                }
            }
        }
    }

    function onAiInsertBelow(newText): void {
        const targetId = aiLoader.item.aiCompareSheet.targetBlockId || root.activeBlockId;
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
     *
     * `keepScroll` exists because replacing `blocks` hands the ListView a brand new array,
     * and a new model is a reset: the view drops `contentY` and goes back to the top. That
     * is what threw the page away on every Enter — splitting has to rebuild the list to
     * show the new block. Saving the offset for the length of the rebuild keeps the page
     * where it was; only a different note opts out, because it starts at its own top.
     */
    function syncFromDocument(forceText = false, keepScroll = true): void {
        const document = root.noteId.length > 0 ? NotesService.documentOf(root.noteId) : null;
        const next = document ? Doc.asArray(document.blocks) : [];
        root.ready = document !== null;
        if (forceText || root.signatureOf(next) !== root.signatureOf(root.blocks)) {
            const savedOffset = keepScroll ? Math.max(0, list.contentY - list.originY) : 0;
            root.blocks = next;
            // The reset happens synchronously, inside the assignment; restoring it in the
            // same turn means the frame never gets drawn at the top.
            list.contentY = list.originY + savedOffset;
        }
        if (root.pendingAutoFocus && root.blocks.length > 0) {
            root.pendingAutoFocus = false;
            root.focusFirstBlock();
        }
    }

    onNoteIdChanged: {
        const aiItem = aiLoader.item;
        if (aiItem && aiItem.aiTask && aiItem.aiTask.running)
            aiItem.aiTask.cancel();
        root.aiMenuOpen = false;
        root.aiCompareOpen = false;
        root.pendingAiMenuRequest = false;
        root.pendingAiScope = "";
        root.pendingAiText = "";
        root.pendingAiBlockId = "";
        root.aiSelectionBlockId = "";
        root.aiSelectionText = "";
        root.aiSelectionStart = -1;
        root.aiSelectionEnd = -1;
        root.undoStack = [];
        root.redoStack = [];
        root.lastSelectionBlockId = "";
        root.lastSelectionText = "";
        root.lastSelectionFullText = "";
        root.lastSelectionStart = -1;
        root.lastSelectionEnd = -1;
        // A different note starts at its own top, so this is the one rebuild that must not
        // carry the previous page's offset over.
        root.syncFromDocument(false, false);
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
            if (!root.writingOurselves)
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
        root.syncFromDocument(true);
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
        root.syncFromDocument(true);
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
        const index = root.indexOfBlock(blockId);
        if (index >= 0 && root.blocks[index])
            root.blocks[index].text = text;
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

    property real minScrollOffset: -1
    property bool advanceScrollOnFocus: false

    /// Enter. Splits here, or leaves the list when the item is empty.
    function splitAt(blockId, offset, text): void {
        const index = root.indexOfBlock(blockId);
        const block = root.blockAt(index);
        if (!block)
            return;
        const savedOffset = Math.max(0, list.contentY - list.originY);
        const currentItem = list.itemAtIndex(index);
        const maxOffsetBefore = Math.max(0, list.contentHeight - list.height);
        const nearBottom = (maxOffsetBefore > 0 && savedOffset >= maxOffsetBefore - 32)
            || (currentItem !== null && (currentItem.y + currentItem.height - list.contentY) >= list.height - 220 && index >= root.blocks.length - 2);
        root.minScrollOffset = savedOffset;
        root.advanceScrollOnFocus = nearBottom;

        const current = Object.assign({}, block, { text: text });
        if (Shortcuts.shouldExit(current)) {
            root.apply(Shortcuts.exitOperations(current));
            root.focusCaret = 0;
            root.focusRequest = blockId;
            return;
        }
        // The typed text has to land first: the split reads the block's text from the
        // document, and the document has not seen this keystroke yet.
        block.text = text;
        root.apply([{ op: "update", id: blockId, patch: { text: text } }], false, false);
        if (root.apply([{ op: "split", id: blockId, offset: offset }])) {
            root.focusCaret = 0;
            root.focusRequest = root.blockIdAt(index + 1);
        }
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

    /**
     * Adds text generated from the note-level prompt without erasing existing prose.
     * A brand-new note starts with one empty paragraph, so use that paragraph instead of
     * leaving an empty line above the generated answer.
     */
    function insertGeneratedText(text): bool {
        const generated = String(text ?? "").trim();
        if (generated.length === 0 || root.noteId.length === 0)
            return false;

        const parsed = Markdown.fromAiMarkdown(generated, { noteId: root.noteId });
        const generatedBlocks = Doc.asArray(parsed.blocks);
        if (generatedBlocks.length === 0)
            return false;

        const document = NotesService.documentOf(root.noteId);
        const currentBlocks = document ? Doc.asArray(document.blocks) : root.blocks;

        if (currentBlocks.length === 1) {
            const first = currentBlocks[0];
            if (first.type === "text" && String(first.text ?? "").trim().length === 0) {
                const firstGenerated = generatedBlocks[0];
                const firstProps = {};
                for (const key in firstGenerated) {
                    if (key !== "id" && key !== "type")
                        firstProps[key] = firstGenerated[key];
                }
                const ops = [{ op: "setType", id: first.id, type: firstGenerated.type, props: firstProps }];
                for (let i = 1; i < generatedBlocks.length; i++) {
                    ops.push({ op: "insert", index: i, block: generatedBlocks[i] });
                }
                if (!root.apply(ops))
                    return false;
                root.syncFromDocument(true);
                // Generated Markdown should open in its rendered form immediately. A focus
                // request would intentionally switch a marked-up block back to source text.
                root.focusCaret = -1;
                root.focusRequest = "";
                return true;
            }
        }

        const at = currentBlocks.length;
        const ops = generatedBlocks.map((block, index) => ({
            op: "insert",
            index: at + index,
            block: block
        }));
        const inserted = root.apply(ops);
        if (inserted) {
            root.syncFromDocument(true);
            root.focusCaret = -1;
            root.focusRequest = "";
        }
        return inserted;
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

    function ensureBlockVisible(at): void {
        if (at < 0 || at >= root.blocks.length || list.height <= 0)
            return;
        const floorY = root.minScrollOffset >= 0 ? list.originY + root.minScrollOffset : -1e9;
        let item = list.itemAtIndex(at);
        if (!item) {
            list.positionViewAtIndex(at, ListView.Contain);
            item = list.itemAtIndex(at);
        }
        if (list.contentY < floorY)
            list.contentY = floorY;
        if (!item)
            return;

        const topMargin = 24;
        const visibleBottom = Math.max(topMargin + 28, list.height - root.bottomClearance);
        const itemTop = item.y - list.contentY;
        const itemBottom = itemTop + item.height;

        if (itemBottom > visibleBottom) {
            const delta = itemBottom - visibleBottom;
            const maxContentY = list.originY + Math.max(0, list.contentHeight - list.height);
            list.contentY = Math.max(floorY, Math.min(maxContentY, list.contentY + delta));
        } else if (root.advanceScrollOnFocus) {
            const step = Math.max(NotesMetrics.paperLineHeight, item.height);
            const maxContentY = list.originY + Math.max(0, list.contentHeight - list.height);
            list.contentY = Math.min(maxContentY, Math.max(list.contentY, floorY + step));
        } else if (itemTop < topMargin && root.minScrollOffset < 0) {
            const delta = topMargin - itemTop;
            list.contentY = Math.max(list.originY, list.contentY - delta);
        }
    }

    function ensureCursorVisible(textEdit): void {
        if (!textEdit || !textEdit.activeFocus || list.height <= 0)
            return;
        try {
            const caret = textEdit.cursorRectangle;
            const mapped = textEdit.mapToItem(list, caret.x, caret.y);
            const topMargin = 24;
            const visibleBottom = Math.max(topMargin + 28, list.height - root.bottomClearance);
            const caretTop = mapped.y;
            const caretBottom = mapped.y + Math.max(caret.height, NotesMetrics.paperLineHeight);
            if (caretBottom > visibleBottom) {
                const maxContentY = list.originY + Math.max(0, list.contentHeight - list.height);
                list.contentY = Math.min(maxContentY, list.contentY + (caretBottom - visibleBottom));
            } else if (caretTop < topMargin && root.minScrollOffset < 0) {
                list.contentY = Math.max(list.originY, list.contentY - (topMargin - caretTop));
            }
        } catch (e) {}
    }

    onFocusRequestChanged: {
        if (root.focusRequest.length === 0)
            return;
        const at = root.indexOfBlock(root.focusRequest);
        if (at >= 0)
            root.ensureBlockVisible(at);
        refocusTimer.restart();
    }

    Timer {
        id: refocusTimer
        // As short as a timer can be. The caret has to come back within one frame of the
        // conversion, or a keystroke typed in that gap has nowhere to land — which costs
        // the first character of whatever follows a markdown prefix.
        interval: 1
        repeat: false
        onTriggered: {
            const at = root.indexOfBlock(root.focusRequest);
            if (at >= 0)
                root.ensureBlockVisible(at);
            root.minScrollOffset = -1;
            root.advanceScrollOnFocus = false;
            root.focusTick++;
        }
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

    /**
     * How much height the footer has to add to reach the bottom of the viewport.
     *
     * A note shorter than the page leaves dead space under its last line, and a click in
     * it has to mean "keep typing" rather than nothing. Measured from the last *row* and
     * never from `contentHeight`: the footer is part of `contentHeight`, so a binding on
     * that would be a loop that keeps relaying out the row the caret is in.
     */
    property real footerFill: 0

    function fitFooter(): void {
        // Only the rows near the viewport are instantiated, so the last row exists exactly
        // when the page is short enough to end on screen — which is the only case that has
        // space to fill. A longer note leaves the footer at its base, as before.
        const last = list.count > 0 ? list.itemAtIndex(list.count - 1) : null;
        root.footerFill = last ? Math.max(0, list.height - (last.y + last.height)) : 0;
    }

    Connections {
        target: list
        function onContentHeightChanged() {
            root.fitFooter();
        }
        function onHeightChanged() {
            root.fitFooter();
        }
        function onCountChanged() {
            root.fitFooter();
        }
    }

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
            // A fixed base, grown to the rest of the viewport by `footerFill`, so the
            // empty space under the last line still belongs to the page. Sizing it from
            // `contentHeight` — which the footer is part of — was a binding loop that kept
            // the list relaying out, rebuilding the delegate the caret is in and dropping
            // the focus on every pass.
            width: list.width
            height: Math.max(200 + (root.aiBusy ? aiLoading.implicitHeight : 0), root.footerFill)

            AiTypingIndicator {
                id: aiLoading
                anchors.left: parent.left
                anchors.leftMargin: NotesMetrics.readingPadding
                anchors.top: parent.top
                anchors.topMargin: NotesMetrics.cardLineSpacing
                active: root.aiBusy
                visible: root.aiBusy
            }

            // Clicking the space under the last block puts the caret in it, or makes a
            // paragraph when the note ends in something you cannot type into.
            MouseArea {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.top: root.aiBusy ? aiLoading.bottom : parent.top
                onClicked: {
                    const last = root.blockAt(root.blocks.length - 1);
                    if (last && ["text", "heading", "list", "quote", "callout"].includes(last.type)) {
                        root.focusCaret = -1; // The end of the block, which is where the page goes on.
                        root.focusRequest = last.id;
                    } else {
                        root.apply([{ op: "insert", index: root.blocks.length, block: { type: "text" } }]);
                    }
                }
            }
        }

        TouchpadScrollHandler {
            flickable: list
        }
    }

    NotesSelectionBar {
        id: selectionBar
        editor: root
        onAiRequested: root.openAiMenu("selection")
    }

    // Deferred AI subsystem: task + menu + compare sheet. Built on the first
    // openAiMenu() (aiLoaded latch) instead of eagerly with the editor. The
    // aliases let root's AI handlers reach the ids once it exists.
    Loader {
        id: aiLoader
        anchors.fill: parent
        active: root.aiLoaded

        sourceComponent: Item {
            anchors.fill: parent
            property alias aiTask: aiTask
            property alias aiMenu: aiMenu
            property alias aiCompareSheet: aiCompareSheet

            AiTextTask {
                id: aiTask
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
                        aiCompareSheet.taskTitle = taskName;
                        aiCompareSheet.originalText = userText;
                        aiCompareSheet.proposedText = "";
                        aiCompareSheet.task = aiTask;
                        aiCompareSheet.targetBlockId = meta.blockId ?? "";
                        aiCompareSheet.mode = meta.mode ?? "selection";
                        root.aiCompareOpen = true;
                        // Publish the compare surface before starting the request so a
                        // slow endpoint still gives immediate feedback and a synchronous
                        // policy/model error has a visible destination.
                        aiTask.start(systemPrompt, userText);
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

        }

        onLoaded: root.presentPendingAiMenu()
    }

    Component.onCompleted: root.syncFromDocument()
}
