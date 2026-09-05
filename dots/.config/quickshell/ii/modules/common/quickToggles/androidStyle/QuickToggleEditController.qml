import QtQuick
import "QuickToggleCatalog.js" as QuickToggleCatalog
import "QuickToggleLayout.js" as QuickToggleLayout

// Transaction boundary for every editable quick-toggle operation. This item
// intentionally receives the JsonObject through `config` instead of importing
// Config directly, which keeps the editing state testable and makes the write
// boundary explicit at the panel integration point.
Item {
    id: root

    property var config: null
    property list<var> persistedPages: []
    property int columns: 4

    property bool active: false
    property string mode: "none"
    property string draggedId: ""
    property int sourcePage: -1
    property int targetPage: -1
    property int sourceIndex: -1
    property int targetIndex: -1
    property list<var> draftPages: []
    property list<var> originalPages: []
    property int candidateSizeW: 1
    property int candidateSizeH: 1

    // Drag stability. Rounding the dragged rectangle to the nearest cell used
    // to flip on sub-pixel jitter, so a pointer parked on the seam between two
    // toggles swapped them again on every mouse sample. `reorderHysteresis` is
    // the extra fraction of a cell the pointer must travel past the midpoint
    // before the cell it currently owns concedes, and `reorderSettleMs` holds
    // the layout still while the reflow animates unless the pointer covers
    // `reorderSettleTravel` cells, which only a deliberate drag does.
    property real reorderHysteresis: 0.25
    property int reorderSettleMs: 0
    property real reorderSettleTravel: 1.0
    readonly property var dragCellState: QuickToggleLayout.createDragCellState()

    signal draftChanged
    signal committed
    signal cancelled
    signal rejected(string reason)

    function clonePages(source) {
        var pages = source || [];
        var cloned = JSON.parse(JSON.stringify(pages));
        return cloned.length > 0 ? cloned : [[]];
    }

    function clearTransaction() {
        active = false;
        mode = "none";
        draggedId = "";
        sourcePage = -1;
        targetPage = -1;
        sourceIndex = -1;
        targetIndex = -1;
        candidateSizeW = 1;
        candidateSizeH = 1;
        draftPages = [];
        originalPages = [];
        QuickToggleLayout.resetDragCellState(dragCellState);
    }

    function beginTransaction(transactionMode) {
        originalPages = clonePages(root.persistedPages);
        draftPages = clonePages(root.persistedPages);
        active = true;
        mode = transactionMode;
    }

    function findItemInPages(pages, id) {
        for (var pageIndex = 0; pageIndex < pages.length; pageIndex++) {
            var page = pages[pageIndex] || [];
            var index = QuickToggleLayout.findItem(page, id);
            if (index >= 0)
                return { page: pageIndex, index: index };
        }
        return { page: -1, index: -1 };
    }

    function beginReorder(id, pageIndex) {
        if (typeof id !== "string" || id.length === 0)
            return false;
        beginTransaction("reorder");
        var location = findItemInPages(draftPages, id);
        if (pageIndex >= 0 && pageIndex < draftPages.length && location.page !== pageIndex) {
            clearTransaction();
            rejected("reorder source item is not on the requested page");
            return false;
        }
        if (location.page < 0) {
            clearTransaction();
            rejected("reorder source item does not exist");
            return false;
        }
        draggedId = id;
        sourcePage = location.page;
        targetPage = location.page;
        sourceIndex = location.index;
        targetIndex = location.index;
        QuickToggleLayout.resetDragCellState(dragCellState);
        return true;
    }

    function previewReorder(pageIndex, index) {
        if (!active || mode !== "reorder" || draggedId.length === 0)
            return false;
        if (pageIndex < 0 || pageIndex >= draftPages.length)
            return false;

        var location = findItemInPages(draftPages, draggedId);
        if (location.page < 0)
            return false;
        var target = Math.max(0, Math.min(Number(index), (draftPages[pageIndex] || []).length));
        if (!isFinite(target))
            target = (draftPages[pageIndex] || []).length;
        target = Math.floor(target);

        if (location.page === pageIndex) {
            if (target > location.index)
                target--;
            target = Math.max(0, Math.min(target, Math.max(0, draftPages[pageIndex].length - 1)));
            if (target === location.index) {
                targetPage = pageIndex;
                targetIndex = target;
                return false;
            }
        } else {
            target = Math.max(0, Math.min(target, draftPages[pageIndex].length));
        }

        var pages = clonePages(draftPages);
        var item = pages[location.page].splice(location.index, 1)[0];
        pages[pageIndex].splice(target, 0, item);
        draftPages = pages;
        targetPage = pageIndex;
        targetIndex = target;
        draftChanged();
        return true;
    }

    // Convert the prospective dragged rectangle into a row-major insertion
    // point using the same packed draft that renders the grid. The controller
    // owns the draft; delegates only provide pointer geometry.
    //
    // The cell resolution runs before any packing: a pointer sample that lands
    // on the cell the drag already owns — the overwhelming majority of them —
    // costs a couple of divisions instead of a deep clone of the page.
    function previewReorderAt(pageIndex, pointerX, pointerY, cellWidth, cellHeight, spacing) {
        if (!active || mode !== "reorder")
            return false;
        if (pageIndex < 0 || pageIndex >= draftPages.length)
            return false;

        var page = draftPages[pageIndex] || [];
        var draggedIndex = QuickToggleLayout.findItem(page, draggedId);
        if (draggedIndex < 0)
            return false;
        var size = QuickToggleLayout.itemSize(page[draggedIndex]);

        var cell = QuickToggleLayout.resolveDragCell({
            pointerX: pointerX,
            pointerY: pointerY,
            cellWidth: cellWidth,
            cellHeight: cellHeight,
            spacing: spacing,
            columns: root.columns,
            columnSpan: size.width,
            rowSpan: size.height
        }, dragCellState, {
            hysteresis: root.reorderHysteresis,
            settleMs: root.reorderSettleMs,
            settleTravel: root.reorderSettleTravel,
            now: Date.now()
        });
        if (!cell.accepted) {
            if (cell.locked)
                QuickToggleLayout.deferDragCell(dragCellState, cell);
            return false;
        }

        var moved = applyDragCell(pageIndex, page, cell.row, cell.column);
        QuickToggleLayout.acceptDragCell(dragCellState, cell, pointerX, pointerY, Date.now(), moved);
        return moved;
    }

    function applyDragCell(pageIndex, page, row, column) {
        var packed = QuickToggleLayout.pack(page, root.columns);
        return previewReorder(pageIndex, QuickToggleLayout.findInsertionIndex(
            packed.items,
            row,
            column,
            draggedId,
            root.columns
        ));
    }

    // A drag released while the settle lock still held its last crossing must
    // land where the pointer was aiming, not where the lock froze the preview.
    function flushPendingReorder(pageIndex) {
        if (!active || mode !== "reorder" || !dragCellState.pendingValid)
            return false;
        if (pageIndex < 0 || pageIndex >= draftPages.length)
            return false;
        var page = draftPages[pageIndex] || [];
        if (QuickToggleLayout.findItem(page, draggedId) < 0)
            return false;
        var row = dragCellState.pendingRow;
        var column = dragCellState.pendingColumn;
        dragCellState.pendingValid = false;
        return applyDragCell(pageIndex, page, row, column);
    }

    function moveToPage(pageIndex, index) {
        return previewReorder(pageIndex, index === undefined ? (draftPages[pageIndex] || []).length : index);
    }

    function setTargetPage(pageIndex) {
        if (!active || mode !== "reorder" || pageIndex < 0 || pageIndex >= draftPages.length)
            return false;
        // A different page is a different grid: the cell the drag owned there
        // must not steer the first sample taken on this one.
        if (targetPage !== pageIndex)
            QuickToggleLayout.resetDragCellState(dragCellState);
        targetPage = pageIndex;
        return true;
    }

    function beginResize(id, pageIndex) {
        if (!beginReorder(id, pageIndex))
            return false;
        mode = "resize";
        var location = findItemInPages(draftPages, draggedId);
        var data = draftPages[location.page][location.index];
        var normalized = QuickToggleCatalog.normalizeSize(data.type, data.sizeW, data.sizeH, root.columns);
        candidateSizeW = normalized[0];
        candidateSizeH = normalized[1];
        return true;
    }

    function previewResize(width, height) {
        if (!active || mode !== "resize" || draggedId.length === 0)
            return false;
        var location = findItemInPages(draftPages, draggedId);
        if (location.page < 0)
            return false;
        var data = draftPages[location.page][location.index];
        var normalized = QuickToggleCatalog.normalizeSize(data.type, width, height, root.columns);
        if (normalized[0] === candidateSizeW && normalized[1] === candidateSizeH)
            return false;

        candidateSizeW = normalized[0];
        candidateSizeH = normalized[1];
        var pages = clonePages(draftPages);
        pages[location.page][location.index].sizeW = candidateSizeW;
        pages[location.page][location.index].sizeH = candidateSizeH;
        draftPages = pages;
        draftChanged();
        return true;
    }

    function validatePages(pages) {
        if (!Array.isArray(pages) || pages.length < 1)
            return false;
        var ids = Object.create(null);
        for (var pageIndex = 0; pageIndex < pages.length; pageIndex++) {
            var page = pages[pageIndex];
            if (!Array.isArray(page))
                return false;
            for (var index = 0; index < page.length; index++) {
                var data = page[index];
                if (!data || typeof data.id !== "string" || data.id.length === 0 || typeof data.type !== "string")
                    return false;
                if (ids[data.id])
                    return false;
                ids[data.id] = true;
                if (!QuickToggleCatalog.isSizeAllowed(data.type, data.sizeW, data.sizeH, root.columns)
                        && QuickToggleCatalog.hasType(data.type))
                    return false;
            }
        }
        return true;
    }

    function normalizedPages(pages) {
        return QuickToggleCatalog.normalizePages(pages, root.columns, {
            logWarnings: true,
            warn: function(message) { console.warn(message); }
        });
    }

    function samePages(left, right) {
        return JSON.stringify(left) === JSON.stringify(right);
    }

    function persist(pages) {
        var normalized = normalizedPages(pages);
        if (!validatePages(normalized)) {
            rejected("refusing to persist invalid quick-toggle pages");
            return false;
        }
        var currentSource = root.config && root.config.pages !== undefined ? root.config.pages : root.persistedPages;
        var current = normalizedPages(currentSource);
        if (samePages(current, normalized)) {
            clearTransaction();
            return true;
        }
        if (!root.config) {
            rejected("quick-toggle config target is unavailable");
            return false;
        }
        root.config.pages = normalized;
        root.config.layoutVersion = 2;
        clearTransaction();
        committed();
        return true;
    }

    function commitReorder() {
        if (!active || mode !== "reorder")
            return false;
        flushPendingReorder(targetPage);
        if (targetPage >= 0 && targetPage !== sourcePage) {
            var location = findItemInPages(draftPages, draggedId);
            if (location.page !== targetPage)
                moveToPage(targetPage);
        }
        return persist(draftPages);
    }

    function commitResize() {
        if (!active || mode !== "resize")
            return false;
        return persist(draftPages);
    }

    function cancel() {
        if (!active)
            return false;
        clearTransaction();
        cancelled();
        return true;
    }

    function cancelReorder() {
        if (!active || mode !== "reorder")
            return false;
        return cancel();
    }

    function cancelResize() {
        if (!active || mode !== "resize")
            return false;
        return cancel();
    }

    function updateOrPersist(mutator) {
        var source = root.config && root.config.pages !== undefined ? root.config.pages : root.persistedPages;
        var pages = active ? clonePages(draftPages) : clonePages(source);
        mutator(pages);
        if (active) {
            draftPages = normalizedPages(pages);
            draftChanged();
            return true;
        }
        return persist(pages);
    }

    function addToggle(type, pageIndex) {
        if (!QuickToggleCatalog.hasType(type) || pageIndex < 0)
            return false;
        return updateOrPersist(function(pages) {
            if (pageIndex >= pages.length)
                return;
            if (findItemInPages(pages, type).page >= 0)
                return;
            pages[pageIndex].push(QuickToggleCatalog.item(type, type, undefined, undefined, root.columns));
        });
    }

    function removeToggle(id) {
        if (typeof id !== "string" || id.length === 0)
            return false;
        return updateOrPersist(function(pages) {
            var location = findItemInPages(pages, id);
            if (location.page >= 0)
                pages[location.page].splice(location.index, 1);
        });
    }

    function addPage() {
        var result = updateOrPersist(function(pages) { pages.push([]); });
        if (result) {
            var pages = active ? draftPages : (root.config && root.config.pages !== undefined ? root.config.pages : root.persistedPages);
            targetPage = pages.length - 1;
        }
        return result;
    }

    function removePage(pageIndex) {
        if (pageIndex < 0)
            return false;
        var sourcePages = root.config && root.config.pages !== undefined ? root.config.pages : root.persistedPages;
        var pageCount = active ? draftPages.length : sourcePages.length;
        if (pageCount <= 1 || pageIndex >= pageCount)
            return false;
        return updateOrPersist(function(pages) { pages.splice(pageIndex, 1); });
    }

    Component.onDestruction: {
        if (active)
            clearTransaction();
    }
}
