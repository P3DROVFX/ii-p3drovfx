import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Qt5Compat.GraphicalEffects
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth

import qs.modules.common.quickToggles
import qs.modules.common.quickToggles.androidStyle
import "androidStyle/QuickToggleCatalog.js" as QuickToggleCatalog
import "androidStyle/QuickToggleLayout.js" as QuickToggleLayout

AbstractQuickPanel {
    id: root
    property bool editMode: false

    // ── Hosting ───────────────────────────────────────────────────────────────
    // The sidebar is the default host and sets none of these. Another host (the Dynamic
    // Island dashboard) hands in its own layout object and turns off what it does not
    // use; the grid, the resize, the reorder and the tray are the same code either way.

    /** A layout object ({ columns, pages, layoutVersion }) that replaces the family's. */
    property var layoutOverride: null
    /** Which family's catalogue entries are offered (QuickToggleCatalog `families`). */
    property string familyId: PanelFamily.current
    /** One page, no indicator, no page controls and no wheel paging. */
    property bool pagingEnabled: true
    /** The sidebar's pinned sliders above the grid. */
    property bool showFixedSliders: true
    /** A grid with a fixed number of rows; edits that would overflow it are refused. */
    property int maxRows: -1
    /** See QuickToggleEditController.growToFit. */
    property var growToFit: null
    /** Shown in place of the page controls while editing, when paging is off. */
    property Component editToolbar: null

    /** A tile (the island's toolbar) asks the host to enter or leave edit mode. */
    signal editModeToggleRequested()
    // Full-screen hosts can own the vertical axis for the complete panel. In that mode the
    // unused-toggle tray publishes its natural height and never steals a drag from the
    // surrounding Flickable; horizontal paging remains local to this component.
    property bool externalVerticalScroll: false
    // Gesture-driven hosts feed their 0→1 pull progress here so the sliders and the tile grid
    // come in one after the other instead of appearing at once. 1.0 = fully revealed (ii).
    property real revealProgress: 1.0
    function stageReveal(delay) {
        const span = Math.max(0.001, 1 - delay);
        return Math.max(0, Math.min(1, (root.revealProgress - delay) / span));
    }
    Layout.fillWidth: true
    Layout.alignment: Qt.AlignHCenter

    // Current page index
    property int currentPage: 0

    property int entranceTrigger: -1

    Connections {
        target: GlobalStates
        function onSidebarRightOpenChanged() {
            if (!GlobalStates.sidebarRightOpen && editController.active) {
                editController.cancel();
            }
        }
    }

    onEditModeChanged: {
        if (!root.editMode && editController.active)
            editController.cancel();
    }

    Shortcut {
        sequence: "Escape"
        enabled: root.editMode && editController.active
        onActivated: editController.cancel()
    }

    // Sizes
    property real spacing: 6
    property real padding: 6
    readonly property real baseCellWidth: {
        const availableWidth = root.width - (root.padding * 2) - (root.spacing * Math.max(0, root.columns - 1));
        return Math.max(1, availableWidth / Math.max(1, root.columns));
    }
    readonly property real gridWidth: Math.max(0, (root.columns * root.baseCellWidth) + (Math.max(0, root.columns - 1) * root.spacing))
    // Hosts with touch-sized grids (tablet family) raise this; the ii sidebar keeps 56,
    // and every derived metric (icon circles, typography) scales off it.
    property real baseCellHeight: 56

    // Sliders hug their track instead of filling a full cell, so rows made only of
    // them pack shorter. Render (positionedItems), page height and the drag cell
    // mapping all consume the same two values — one source of truth each.
    readonly property list<string> compactToggleTypes: {
        var types = [];
        var all = QuickToggleCatalog.allTypes();
        for (var i = 0; i < all.length; i++) {
            if (QuickToggleCatalog.kind(all[i]) === "slider")
                types.push(all[i]);
        }
        return types;
    }
    readonly property real compactRowHeight: QuickToggleMetrics.sliderWidgetHeight(root.baseCellHeight)

    // Toggles config
    readonly property list<string> availableToggleTypes: QuickToggleCatalog.allTypes()
    function isToggleVisible(toggleType) {
        return QuickToggleCatalog.availableForFamily(toggleType, root.familyId)
    }
    /**
     * The layout object this family owns, and the one every edit writes to.
     *
     * Not `quickToggles.android` directly any more: the desktop sidebar is 460px wide and
     * the tablet's shade is the whole screen, so one arrangement cannot serve both — and
     * sharing the key meant adapting either silently rearranged the other. See
     * PanelFamily.quickToggleLayout.
     */
    readonly property var layoutConfig: root.layoutOverride ?? PanelFamily.quickToggleLayout()

    readonly property int columns: root.layoutConfig?.columns ?? 4

    // Pages data — reads from Config and exposes the canonical in-memory shape.
    // The legacy `size` field is read only by the catalog normalizer and is not
    // returned to delegates.
    readonly property list<var> pages: {
        if (!Config.ready)
            return [[]];
        // Not `layoutConfig.pages`: a family that has never been edited borrows the
        // desktop's arrangement rather than opening on a blank grid.
        const stored = root.layoutOverride ? root.layoutOverride.pages : PanelFamily.quickTogglePages();
        if (!stored || stored.length === 0)
            return [[]];
        return QuickToggleCatalog.normalizePages(stored, root.columns, {
            warn: function(message) { console.warn(message); }
        });
    }

    QuickToggleEditController {
        id: editController
        config: root.layoutConfig
        persistedPages: root.pages
        columns: root.columns
        cellWidth: root.baseCellWidth
        cellHeight: root.baseCellHeight
        spacing: root.spacing
        maxRows: root.maxRows
        growToFit: root.growToFit
        // Hold a fresh swap for exactly as long as the delegates take to slide
        // into their new slots, so a hesitating pointer cannot re-order the
        // grid while it is still visibly reflowing. Zero when animations are
        // off, because then there is nothing to wait for.
        reorderSettleMs: Appearance.animation.elementMoveFast.duration
    }

    property alias editController: editController

    // The persisted page arrays are the delegate model. A gesture may change
    // preview geometry, but it must never reorder/retype this model while a
    // MouseArea owns the grab.
    readonly property list<var> displayPages: root.pages

    // Same-page reorder and resize get a live packed preview. Cross-page drag
    // keeps both pages stable until release, then commits one atomic move.
    readonly property list<var> geometryPages: {
        if (!editController.active)
            return root.pages;
        if (editController.mode === "resize"
                || editController.targetPage === editController.sourcePage)
            return editController.draftPages;
        return root.pages;
    }

    // All used toggle types across all pages
    readonly property list<string> allUsedTypes: {
        var types = [];
        for (var p = 0; p < root.pages.length; p++) {
            var page = root.pages[p];
            if (!page)
                continue;
            for (var i = 0; i < page.length; i++) {
                if (page[i] && page[i].type)
                    types.push(page[i].type);
            }
        }
        return types;
    }

    readonly property list<var> unusedToggles: {
        const types = availableToggleTypes.filter(type => root.isToggleVisible(type) && !allUsedTypes.includes(type));
        // A variant group is one entry: the design the user has cycled to, among the
        // group's designs still off the grid.
        const shown = [];
        const seenGroups = {};
        for (let i = 0; i < types.length; i++) {
            const group = QuickToggleCatalog.variantGroup(types[i]);
            if (group === "") {
                shown.push(types[i]);
                continue;
            }
            if (seenGroups[group])
                continue;
            seenGroups[group] = true;
            shown.push(root.trayVariantFor(group, types));
        }
        return shown.map(type => QuickToggleCatalog.item(type, type, undefined, undefined, root.columns));
    }

    // ── Variant groups in the tray ────────────────────────────────────────────
    /**
     * The design each variant group shows in the tray, by group: { weather: "weatherCard" }.
     * Tray state only - it is never saved, and it never changes a tile on the grid.
     */
    property var trayVariantChoice: ({})

    /** A group's designs that can still be added (off the grid, allowed in this host). */
    function trayVariants(group, availableTypes) {
        const pool = availableTypes ?? root.availableToggleTypes.filter(type =>
            root.isToggleVisible(type) && !root.allUsedTypes.includes(type));
        return QuickToggleCatalog.variantsOf(group).filter(type => pool.includes(type));
    }

    function trayVariantFor(group, availableTypes) {
        const variants = root.trayVariants(group, availableTypes);
        const chosen = root.trayVariantChoice[group];
        return variants.includes(chosen) ? chosen : variants[0];
    }

    /** Show the next (1) or previous (-1) design of a group in the tray. */
    function cycleTrayVariant(group, delta) {
        const variants = root.trayVariants(group);
        if (variants.length < 2)
            return;
        const current = Math.max(0, variants.indexOf(root.trayVariantFor(group)));
        const next = variants[(current + delta + variants.length) % variants.length];
        const choice = Object.assign({}, root.trayVariantChoice);
        choice[group] = next;
        root.trayVariantChoice = choice;
    }

    /**
     * The tray section that is open, by id. One at a time, and only the open one is
     * built: the tray holds every tile that is not on the grid, so building all of
     * them at once is what makes opening edit mode expensive. Not saved - edit mode
     * opens on the first section.
     */
    property string trayExpandedSection: ""
    /** A section's header, which is also its height while closed. */
    readonly property real traySectionHeaderHeight: 44
    /**
     * The island animates its own height, and it has to animate toward where the tray
     * is *going*, not where it is: sized from the live height it would be easing toward
     * a value that is itself easing, and would always trail the section (opening) or
     * run ahead of it (closing). So the sections animate, and this says what they
     * animate to - see `targetImplicitHeight`.
     */
    readonly property real trayTargetColumnHeight: {
        const sections = root.traySections;
        if (sections.length === 0)
            return 0;
        let total = 8 * (sections.length - 1);   // trayColumn.spacing
        for (let i = 0; i < sections.length; i++) {
            total += root.traySectionHeaderHeight;
            if (sections[i].id === root.trayExpandedSection)
                total += root.trayBadgeOverhang + sections[i].height + 10;
        }
        return total;
    }
    readonly property real trayTargetHeight: root.trayMaxHeight < 0
        ? root.trayTargetColumnHeight : Math.min(root.trayTargetColumnHeight, root.trayMaxHeight)

    /** The tray's height right now, as its sections animate. */
    readonly property real trayLiveHeight: unusedTogglesLoader.item ? unusedTogglesLoader.item.implicitHeight : 0
    /**
     * Everything but the tray, measured while the tray is at rest.
     *
     * The target below cannot be written as "what the panel is now, plus what the tray
     * still has to move": the panel's height and the tray's own are separate bindings
     * that settle at different points within a frame, so their difference flickers -
     * and a host easing toward it restarts its animation every frame (the island took
     * exactly twice its duration to arrive). Holding the still part instead makes the
     * target exact and constant for the whole animation.
     */
    property real nonTrayHeight: 0
    function syncNonTrayHeight() {
        if (Math.abs(root.trayLiveHeight - root.trayTargetHeight) < 0.5)
            root.nonTrayHeight = root.implicitHeight - root.trayLiveHeight;
    }
    onImplicitHeightChanged: root.syncNonTrayHeight()
    onTrayLiveHeightChanged: root.syncNonTrayHeight()
    onTrayTargetHeightChanged: root.syncNonTrayHeight()

    /**
     * The height the panel is heading for. A host that animates its own size (the
     * island) sizes itself from this, so the two move as one; the panel's own layout
     * keeps animating as usual.
     */
    readonly property real targetImplicitHeight: {
        if (!root.editMode || !unusedTogglesLoader.item)
            return root.implicitHeight;
        return root.nonTrayHeight + root.trayTargetHeight;
    }

    /**
     * Sections open and close on the island's own morph, so the two move as one. The
     * shell's spatial preset is both longer and bouncier, which read as the tray
     * arriving before (or after) the surface holding it.
     */
    readonly property int traySectionDuration: Math.round(420 * Appearance.animMultiplier)
    function toggleTraySection(sectionId) {
        root.trayExpandedSection = root.trayExpandedSection === sectionId ? "" : sectionId;
    }
    // Opening edit mode, or losing the open section, falls back to the first one.
    onTraySectionsChanged: {
        if (root.traySections.length === 0)
            return;
        if (!root.traySections.some(section => section.id === root.trayExpandedSection))
            root.trayExpandedSection = root.traySections[0].id;
    }

    // ── Tray sections ─────────────────────────────────────────────────────────
    // The tray offers what is not on the grid grouped into a few broad sections, each
    // packed on its own with the same packer the grid uses.
    readonly property var trayCategoryMeta: ({
        connectivity: { label: Translation.tr("Connectivity"), icon: "wifi" },
        system: { label: Translation.tr("System & tools"), icon: "tune" },
        sliders: { label: Translation.tr("Sliders"), icon: "linear_scale" },
        widgets: { label: Translation.tr("Widgets"), icon: "widgets" }
    })

    /**
     * A section is as wide as the grid above it, so its edges line up with the tiles'.
     * The tiles inside it therefore pack a little narrower, inset far enough that their
     * add badges stay inside the section.
     */
    readonly property real traySectionInset: root.trayBadgeOverhang + 4
    readonly property real trayCellWidth: Math.max(1,
        (root.gridWidth - 2 * root.traySectionInset - root.spacing * Math.max(0, root.columns - 1))
        / Math.max(1, root.columns))

    function packedHeight(packed) {
        const rows = packed ? packed.rowsUsed : 0;
        if (rows === 0)
            return 0;
        const rowHeights = QuickToggleLayout.rowPixelHeights(
            packed, root.baseCellHeight, root.spacing, root.compactRowHeight, root.compactToggleTypes);
        if (!rowHeights)
            return rows * (root.baseCellHeight + root.spacing) - root.spacing;
        let total = 0;
        for (let i = 0; i < rowHeights.length; i++)
            total += rowHeights[i] + root.spacing;
        return Math.max(0, total - root.spacing);
    }

    readonly property var traySections: {
        const sections = [];
        const order = QuickToggleCatalog.categoryOrder();
        for (let c = 0; c < order.length; c++) {
            const id = order[c];
            const items = root.unusedToggles.filter(item => QuickToggleCatalog.category(item.type) === id);
            if (items.length === 0)
                continue;
            const packed = QuickToggleLayout.pack(items, root.columns, root.trayCellWidth, root.baseCellHeight, root.spacing);
            const meta = root.trayCategoryMeta[id] ?? { label: id, icon: "category" };
            sections.push({
                id: id,
                label: meta.label,
                icon: meta.icon,
                items: QuickToggleLayout.positionedItems(items, packed, root.trayCellWidth, root.baseCellHeight,
                    root.spacing, root.compactRowHeight, root.compactToggleTypes),
                height: root.packedHeight(packed)
            });
        }
        return sections;
    }

    // One packer owns both visible geometry and height. Delegates are decorated
    // by stable id below; their model order remains the persisted order.
    readonly property list<var> packedPages: {
        var result = [];
        for (var i = 0; i < geometryPages.length; i++)
            result.push(QuickToggleLayout.pack(
                geometryPages[i] || [],
                root.columns,
                root.baseCellWidth,
                root.baseCellHeight,
                root.spacing
            ));
        return result;
    }

    readonly property list<var> positionedPages: {
        var result = [];
        for (var i = 0; i < root.pages.length; i++) {
            result.push(QuickToggleLayout.positionedItems(
                root.pages[i] || [],
                root.packedPages[i] || { rowsUsed: 0, items: [] },
                root.baseCellWidth,
                root.baseCellHeight,
                root.spacing,
                root.compactRowHeight,
                root.compactToggleTypes
            ));
        }
        return result;
    }

    // Calculate height for a specific page
    function pageHeight(pageIndex) {
        if (pageIndex < 0 || pageIndex >= root.pages.length)
            return baseCellHeight;
        var packedPage = packedPages[pageIndex];
        var rows = packedPage ? packedPage.rowsUsed : 0;
        var rowHeights = QuickToggleLayout.rowPixelHeights(
            packedPage, baseCellHeight, spacing, compactRowHeight, compactToggleTypes);
        if (!rowHeights)
            return Math.max(baseCellHeight, rows * (baseCellHeight + spacing) - spacing);
        var total = 0;
        for (var i = 0; i < rowHeights.length; i++)
            total += rowHeights[i] + spacing;
        return Math.max(baseCellHeight, total - spacing);
    }

    // Dynamic height based on current page
    readonly property real currentContentHeight: Math.max(pageHeight(currentPage), editController.resizePreviewBottom) + (editMode ? 14 : 0)

    // How tall the panel is allowed to get, handed down by whoever hosts it.
    // Negative means unconstrained, which is what a host that does not measure
    // itself gets. Everything above the tray is fixed, so the tray gets what is
    // left of the budget and scrolls the rest.
    property real maxContentHeight: -1
    // Every unused toggle wears an add badge that hangs 6px past its own top and
    // right edge (EditableQuickToggleItem). Outside a clip that just draws over
    // the panel padding; inside one it gets sliced, so the tray has to hand those
    // 6px back on both sides.
    readonly property real trayBadgeOverhang: 6
    readonly property real trayMaxHeight: {
        if (root.maxContentHeight <= 0)
            return -1;
        return Math.max(root.baseCellHeight,
            root.maxContentHeight - unusedTogglesLoader.y - root.padding * 2);
    }

    implicitHeight: contentItem.implicitHeight + root.padding * 2

    // Page management functions
    function addPage() {
        if (editController.addPage())
            currentPage = editController.targetPage;
    }

    function removePage(pageIndex) {
        if (!editController.removePage(pageIndex))
            return;
        var remaining = root.pages.length;
        currentPage = Math.min(currentPage, Math.max(0, remaining - 1));
    }

    function goToPage(pageIndex) {
        if (pageIndex < 0 || pageIndex >= displayPages.length)
            return;
        currentPage = pageIndex;
    }

    // Drag-scroll: called by toggle buttons during drag to auto-scroll pages
    // absX: x coordinate mapped to panel root
    // dragButton: the toggle button being dragged
    property real dragScrollEdgeThreshold: 40
    property int dragScrollPendingPage: -1

    Timer {
        id: dragScrollTimer
        interval: 500
        repeat: false
        onTriggered: {
            if (root.dragScrollPendingPage >= 0 && root.dragScrollPendingPage < root.displayPages.length) {
                root.currentPage = root.dragScrollPendingPage;
                if (root.editController.active)
                    root.editController.setTargetPage(root.dragScrollPendingPage);
            }
            root.dragScrollPendingPage = -1;
        }
    }

    function cancelDragScroll() {
        dragScrollTimer.stop();
        dragScrollPendingPage = -1;
    }

    function handleDragScrollRequest(absX, dragButton) {
        var newPage = -1;
        if (absX < dragScrollEdgeThreshold && currentPage > 0) {
            newPage = currentPage - 1;
        } else if (absX > root.width - dragScrollEdgeThreshold && currentPage < displayPages.length - 1) {
            newPage = currentPage + 1;
        }

        if (newPage >= 0 && newPage !== dragScrollPendingPage) {
            dragScrollPendingPage = newPage;
            dragScrollTimer.restart();
        } else if (newPage < 0) {
            // Back in safe zone — reset pending
            dragScrollPendingPage = -1;
            dragScrollTimer.stop();
        }
    }

    Column {
        id: contentItem
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: root.padding
        }
        spacing: 8

        Column {
            id: fixedSlidersColumn
            anchors.horizontalCenter: parent.horizontalCenter
            width: root.gridWidth
            spacing: root.spacing
            visible: fixedSlidersModel.count > 0

            readonly property real reveal: root.stageReveal(0)
            opacity: reveal
            transform: Translate {
                y: -(1 - fixedSlidersColumn.reveal) * root.baseCellHeight * 0.5
            }

            StableQuickToggleModel {
                id: fixedSlidersModel
                sourceValues: {
                    var list = [];
                    const cfg = Config.options.sidebar.quickSliders;
                    if (root.showFixedSliders && cfg.enable) {
                        if (cfg.showBrightness)
                            list.push(QuickToggleCatalog.item("brightnessSlider", "brightnessSlider", root.columns, 1, root.columns));
                        if (cfg.showGamma)
                            list.push(QuickToggleCatalog.item("gammaSlider", "gammaSlider", root.columns, 1, root.columns));
                        if (cfg.showVolume)
                            list.push(QuickToggleCatalog.item("volumeSlider", "volumeSlider", root.columns, 1, root.columns));
                        if (cfg.showMic)
                            list.push(QuickToggleCatalog.item("micSlider", "micSlider", root.columns, 1, root.columns));
                    }
                    return list;
                }
            }

            Repeater {
                id: fixedSlidersRepeater
                model: fixedSlidersModel
                delegate: AndroidToggleDelegateChooser {
                    editMode: false // Force false so they can't be dragged
                    baseCellWidth: root.baseCellWidth
                    baseCellHeight: root.baseCellHeight
                    spacing: root.spacing
                    isUnused: false
                    pageIndex: -1
                    gridColumns: root.columns
                    panel: root
                    gridRef: fixedSlidersColumn
                    entranceTrigger: root.entranceTrigger

                    onOpenAudioOutputDialog: root.openAudioOutputDialog()
                    onOpenAudioInputDialog: root.openAudioInputDialog()
                    onOpenBluetoothDialog: root.openBluetoothDialog()
                    onOpenNightLightDialog: root.openNightLightDialog()
                    onOpenWifiDialog: root.openWifiDialog()
                    onOpenDarkModeDialog: root.openDarkModeDialog()
                    onOpenLocalSendDialog: root.openLocalSendDialog()
                    onOpenVpnDialog: root.openVpnDialog()
                    onOpenTailscaleDialog: root.openTailscaleDialog()
                    onOpenKdeConnectDialog: root.openKdeConnectDialog()
                    onOpenDnsOverTlsDialog: root.openDnsOverTlsDialog()
                    onOpenIdleInhibitorDialog: root.openIdleInhibitorDialog()
                    onOpenScreenShaderDialog: root.openScreenShaderDialog()
                    onOpenModesDialog: root.openModesDialog()
                }
            }
        }

        // Horizontal paging container
        Item {
            id: flickableContainer
            width: parent.width
            height: root.currentContentHeight

            readonly property real reveal: root.stageReveal(0.25)
            opacity: reveal
            transform: Translate {
                y: -(1 - flickableContainer.reveal) * root.baseCellHeight * 0.7
            }

            clip: !root.editMode

            Flickable {
                id: flickable
                anchors.fill: parent
                contentWidth: width * root.displayPages.length
                contentHeight: height
                flickableDirection: Flickable.HorizontalFlick
                boundsBehavior: Flickable.StopAtBounds
                interactive: !root.editMode

                // Snap to page on release
                onMovementEnded: {
                    var targetPage = Math.round(contentX / width);
                    targetPage = Math.max(0, Math.min(targetPage, root.displayPages.length - 1));
                    root.currentPage = targetPage;
                    snapAnimation.to = targetPage * width;
                    snapAnimation.start();
                }

                // Mouse wheel / scroll paging
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.NoButton
                    // Off with paging: a single page has nothing to page to, and taking
                    // the wheel would starve the host (the island pages with it).
                    enabled: root.pagingEnabled
                    onWheel: function (wheelEvent) {
                        if (root.externalVerticalScroll
                                && Math.abs(wheelEvent.angleDelta.y) >= Math.abs(wheelEvent.angleDelta.x)) {
                            // Let the host's vertical WheelHandler move the complete column,
                            // from configured toggles all the way through the unused tray.
                            wheelEvent.accepted = false;
                            return;
                        }
                        if (Math.abs(wheelEvent.angleDelta.x) > Math.abs(wheelEvent.angleDelta.y)) {
                            // Horizontal scroll
                            if (wheelEvent.angleDelta.x < 0 && root.currentPage < root.displayPages.length - 1) {
                                root.goToPage(root.currentPage + 1);
                            } else if (wheelEvent.angleDelta.x > 0 && root.currentPage > 0) {
                                root.goToPage(root.currentPage - 1);
                            }
                        } else {
                            // Vertical scroll → map to horizontal paging
                            if (wheelEvent.angleDelta.y < 0 && root.currentPage < root.displayPages.length - 1) {
                                root.goToPage(root.currentPage + 1);
                            } else if (wheelEvent.angleDelta.y > 0 && root.currentPage > 0) {
                                root.goToPage(root.currentPage - 1);
                            }
                        }
                        wheelEvent.accepted = true;
                    }
                }

                NumberAnimation {
                    id: snapAnimation
                    target: flickable
                    property: "contentX"
                    duration: 350
                    easing.type: Easing.OutQuint
                }

                Row {
                    id: pagesRow
                    height: parent.height

                    Repeater {
                        id: pagesRepeater
                        model: root.displayPages.length

                        Item {
                            id: pageContainer
                            required property int index
                            width: flickable.width
                            height: flickable.height

                            // Show only current page content as visible when current
                            property bool isCurrent: root.currentPage === index
                            property list<var> pageToggles: root.positionedPages[index] || []

                            Item {
                                id: pageContentCanvas
                                // Keep delegates and their mouse grabs alive during cross-page
                                // reorder, but do not paint inactive pages outside the viewport.
                                opacity: !root.editMode || pageContainer.isCurrent ? 1 : 0
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: root.gridWidth
                                anchors.top: parent.top
                                implicitHeight: root.pageHeight(pageContainer.index)
                                height: implicitHeight
                                objectName: "pageContent_" + pageContainer.index

                                StableQuickToggleModel {
                                    id: pageToggleModel
                                    sourceValues: pageContainer.pageToggles
                                }

                                Repeater {
                                    id: gridRepeater
                                    model: pageToggleModel
                                    delegate: AndroidToggleDelegateChooser {

                                        editMode: root.editMode
                                        baseCellWidth: root.baseCellWidth
                                        baseCellHeight: root.baseCellHeight
                                        spacing: root.spacing
                                        isUnused: false
                                        pageIndex: pageContainer.index
                                        gridColumns: root.columns
                                        panel: root
                                        gridRef: pageContentCanvas
                                        entranceTrigger: root.entranceTrigger

                                        onOpenAudioOutputDialog: root.openAudioOutputDialog()
                                        onOpenAudioInputDialog: root.openAudioInputDialog()
                                        onOpenBluetoothDialog: root.openBluetoothDialog()
                                        onOpenNightLightDialog: root.openNightLightDialog()
                                        onOpenWifiDialog: root.openWifiDialog()
                                        onOpenDarkModeDialog: root.openDarkModeDialog()
                                        onOpenLocalSendDialog: root.openLocalSendDialog()
                                        onOpenVpnDialog: root.openVpnDialog()
                                        onOpenTailscaleDialog: root.openTailscaleDialog()
                                        onOpenKdeConnectDialog: root.openKdeConnectDialog()
                                        onOpenDnsOverTlsDialog: root.openDnsOverTlsDialog()
                                        onOpenIdleInhibitorDialog: root.openIdleInhibitorDialog()
                                        onOpenScreenShaderDialog: root.openScreenShaderDialog()
                                        onOpenModesDialog: root.openModesDialog()
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // Page indicators (dots)
        Row {
            id: pageIndicators
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 6
            visible: root.pagingEnabled && root.displayPages.length > 1

            Repeater {
                model: root.displayPages.length
                delegate: Rectangle {
                    required property int index
                    width: root.currentPage === index ? 16 : 8
                    height: 8
                    radius: height / 2
                    color: root.currentPage === index ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
                    opacity: root.currentPage === index ? 1.0 : 0.5

                    Behavior on width {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -4
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.goToPage(index)
                    }
                }
            }
        }

        // Edit mode: the host's own controls, when it has no pages to manage
        FadeLoader {
            shown: root.editMode && !root.pagingEnabled && root.editToolbar !== null
            fade: false
            keepAlive: false
            anchors {
                left: parent.left
                right: parent.right
            }
            sourceComponent: root.editToolbar
        }

        // Edit mode: page navigation + add page buttons
        FadeLoader {
            shown: root.editMode && root.pagingEnabled
            fade: false
            // Destroy page-nav controls when not in edit mode — they are only
            // needed while the user is rearranging tiles and hold several
            // RippleButton instances in memory when keepAlive is true.
            keepAlive: false
            anchors {
                left: parent.left
                right: parent.right
            }
            sourceComponent: RowLayout {
                spacing: 6

                // Previous page button
                RippleButton {
                    Layout.preferredWidth: root.baseCellHeight
                    Layout.preferredHeight: root.baseCellHeight * 0.6
                    visible: root.currentPage > 0
                    buttonRadius: Appearance.rounding.full
                    buttonRadiusPressed: height / 2
                    colBackground: Appearance.colors.colSurfaceContainerHigh
                    colBackgroundHover: Appearance.colors.colSurfaceContainerHighest
                    onClicked: root.goToPage(root.currentPage - 1)
                    contentItem: MaterialSymbol {
                        text: "chevron_left"
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colOnSurface
                        horizontalAlignment: Text.AlignHCenter
                    }
                }

                // Page label
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.baseCellHeight * 0.6
                    radius: Appearance.rounding.full
                    color: "transparent"
                    border.color: Appearance.colors.colOutline
                    border.width: 1

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 8
                        MaterialSymbol {
                            text: "auto_awesome_motion"
                            font.pixelSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colPrimary
                        }
                        StyledText {
                            text: Translation.tr("Page %1 / %2").arg(root.currentPage + 1).arg(root.displayPages.length)
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.Bold
                            color: Appearance.colors.colOnSurface
                        }
                    }
                }

                // Next page button
                RippleButton {
                    Layout.preferredWidth: root.baseCellHeight
                    Layout.preferredHeight: root.baseCellHeight * 0.6
                    visible: root.currentPage < root.displayPages.length - 1
                    bottomLeftRadius: Appearance.rounding.full
                    topLeftRadius: Appearance.rounding.full
                    bottomRightRadius: Appearance.rounding.verysmall
                    topRightRadius: Appearance.rounding.verysmall
                    buttonRadiusPressed: height / 2
                    colBackground: Appearance.colors.colSurfaceContainerHigh
                    colBackgroundHover: Appearance.colors.colSurfaceContainerHighest
                    onClicked: root.goToPage(root.currentPage + 1)
                    contentItem: MaterialSymbol {
                        text: "chevron_right"
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colOnSurface
                        horizontalAlignment: Text.AlignHCenter
                    }
                }

                // Add page button
                RippleButton {
                    Layout.preferredWidth: root.baseCellHeight
                    Layout.preferredHeight: root.baseCellHeight * 0.6
                    bottomLeftRadius: Appearance.rounding.verysmall
                    topLeftRadius: Appearance.rounding.verysmall
                    bottomRightRadius: Appearance.rounding.verysmall
                    topRightRadius: Appearance.rounding.verysmall
                    buttonRadiusPressed: height / 2
                    colBackground: Appearance.colors.colPrimary
                    colBackgroundHover: Appearance.colors.colPrimaryHover
                    onClicked: root.addPage()
                    contentItem: MaterialSymbol {
                        text: "add"
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colOnPrimary
                        horizontalAlignment: Text.AlignHCenter
                    }
                    StyledToolTip {
                        text: Translation.tr("Add new page")
                    }
                }

                // Delete current page (only if >1 pages and current is empty)
                RippleButton {
                    Layout.preferredWidth: root.baseCellHeight
                    Layout.preferredHeight: root.baseCellHeight * 0.6
                    visible: root.displayPages.length > 1
                    bottomLeftRadius: Appearance.rounding.verysmall
                    topLeftRadius: Appearance.rounding.verysmall
                    bottomRightRadius: Appearance.rounding.full
                    topRightRadius: Appearance.rounding.full
                    buttonRadiusPressed: height / 2
                    colBackground: Appearance.colors.colErrorContainer
                    colBackgroundHover: Appearance.colors.colErrorContainerHover
                    onClicked: root.removePage(root.currentPage)
                    contentItem: MaterialSymbol {
                        text: "delete"
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colOnErrorContainer
                        horizontalAlignment: Text.AlignHCenter
                    }
                    StyledToolTip {
                        text: Translation.tr("Remove current page")
                    }
                }
            }
        }

        // Separator between used and unused toggles in edit mode
        FadeLoader {
            shown: root.editMode
            fade: false
            keepAlive: false
            anchors {
                left: parent.left
                right: parent.right
                leftMargin: root.baseCellHeight / 2
                rightMargin: root.baseCellHeight / 2
            }
            sourceComponent: Rectangle {
                implicitHeight: 1
                color: Appearance.colors.colOutlineVariant
            }
        }

        // Unused toggles (edit mode) — keepAlive: false so the entire drawer
        // (up to ~40 toggle delegates) is destroyed when edit mode is off.
        // This is the largest single contributor to idle RAM when quick toggles
        // are configured: every unused toggle type creates a full QML delegate.
        FadeLoader {
            id: unusedTogglesLoader
            shown: root.editMode
            fade: false
            keepAlive: false
            anchors {
                left: parent.left
                right: parent.right
            }
            sourceComponent: Item {
                id: trayViewport
                implicitHeight: trayFlickable.implicitHeight

                // The same treatment as the sidebar's task list: one mask rounds the
                // viewport's corners and fades whichever edge has more content past it,
                // so scrolled sections leave through a curve instead of a straight cut.
                layer.enabled: visible
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        id: trayMask
                        width: trayViewport.width
                        height: trayViewport.height
                        radius: Appearance.rounding.large
                        readonly property real fadeFraction: Math.min(0.5, trayEdgeFade.fadeSize / Math.max(1, height))
                        property real topAlpha: trayEdgeFade.overflowing && trayEdgeFade.startGap > trayEdgeFade.edgeTolerance ? 0 : 1
                        property real bottomAlpha: trayEdgeFade.overflowing && trayEdgeFade.endGap > trayEdgeFade.edgeTolerance ? 0 : 1
                        Behavior on topAlpha {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                        Behavior on bottomAlpha {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                        gradient: Gradient {
                            GradientStop { position: 0; color: Qt.rgba(1, 1, 1, trayMask.topAlpha) }
                            GradientStop { position: trayMask.fadeFraction; color: "white" }
                            GradientStop { position: 1 - trayMask.fadeFraction; color: "white" }
                            GradientStop { position: 1; color: Qt.rgba(1, 1, 1, trayMask.bottomAlpha) }
                        }
                    }
                }

                StyledFlickable {
                    id: trayFlickable
                    anchors.fill: parent
                    readonly property real fullHeight: trayColumn.implicitHeight
                    implicitHeight: root.trayMaxHeight < 0 ? fullHeight
                        : Math.min(fullHeight, root.trayMaxHeight)
                    contentWidth: width
                    contentHeight: fullHeight
                    clip: true
                    interactive: !root.externalVerticalScroll && contentHeight > height

                    Column {
                        id: trayColumn
                        width: parent.width
                        spacing: 8

                        // Keyed by section id: an edit updates the sections it touches
                        // instead of rebuilding the tray (see TraySectionModel).
                        TraySectionModel {
                            id: traySectionModel
                            sourceValues: root.traySections
                        }

                        Repeater {
                            model: traySectionModel

                            delegate: Rectangle {
                                id: section
                                required property var sectionData
                                readonly property var modelData: section.sectionData

                                readonly property bool expanded: root.trayExpandedSection === section.modelData.id
                                /** The header's own height, and the closed section's. */
                                readonly property real headerHeight: root.traySectionHeaderHeight
                                readonly property real openHeight: section.headerHeight
                                    + root.trayBadgeOverhang + unusedCanvas.height + 10

                                width: trayColumn.width
                                /**
                                 * One motion: the section grows and its tiles are revealed
                                 * by the growth, the way the island reveals the face it
                                 * opens into - no second animation fading the tiles in.
                                 */
                                implicitHeight: section.expanded ? section.openHeight : section.headerHeight
                                Behavior on implicitHeight {
                                    NumberAnimation {
                                        duration: root.traySectionDuration
                                        easing.type: Easing.BezierSpline
                                        easing.bezierCurve: Appearance.animationCurves.standard
                                    }
                                }
                                radius: Appearance.rounding.large
                                color: Appearance.colors.colLayer2

                                // The whole header opens and closes the section.
                                MouseArea {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    height: section.headerHeight
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.toggleTraySection(section.modelData.id)
                                }

                                RowLayout {
                                    id: sectionHeader
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    // Clear of the corner's curve at both ends.
                                    anchors.leftMargin: 18
                                    anchors.rightMargin: 16
                                    anchors.top: parent.top
                                    height: section.headerHeight
                                    spacing: 8

                                    MaterialSymbol {
                                        text: section.modelData.icon
                                        iconSize: Appearance.font.pixelSize.large
                                        color: Appearance.colors.colOnLayer2
                                    }
                                    StyledText {
                                        text: section.modelData.label
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        font.weight: Font.DemiBold
                                        color: Appearance.colors.colOnLayer2
                                    }
                                    // What a closed section holds.
                                    StyledText {
                                        text: section.modelData.items.length
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: Appearance.colors.colSubtext
                                    }
                                    Item { Layout.fillWidth: true }
                                    MaterialSymbol {
                                        text: "expand_more"
                                        iconSize: Appearance.font.pixelSize.large
                                        color: Appearance.colors.colOnLayer2
                                        rotation: section.expanded ? 180 : 0
                                        // The same motion as the section it belongs to.
                                        Behavior on rotation {
                                            NumberAnimation {
                                                duration: root.traySectionDuration
                                                easing.type: Easing.BezierSpline
                                                easing.bezierCurve: Appearance.animationCurves.standard
                                            }
                                        }
                                    }
                                }

                                // The growing section reveals its tiles. The clip lives
                                // here rather than on the section: a rectangular clip over
                                // the section would cut its own rounded corners.
                                Item {
                                    id: sectionBody
                                    y: section.headerHeight
                                    width: parent.width
                                    height: Math.max(0, section.height - section.headerHeight)
                                    clip: true
                                    visible: sectionBody.height > 0

                                Item {
                                    id: unusedCanvas
                                    /**
                                     * Only the open section's tiles exist, and they outlive
                                     * the close: destroyed at the first frame, the tiles
                                     * would vanish and leave an empty box collapsing.
                                     */
                                    readonly property bool live: section.expanded
                                        || section.height > section.headerHeight + 1
                                    y: root.trayBadgeOverhang
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: parent.width - 2 * root.traySectionInset
                                    height: section.modelData.height

                                    // Toggles and sliders are built for real; widget
                                    // tiles stand in as previews (QuickToggleTrayPreview),
                                    // which is what keeps opening edit mode cheap.
                                    StableQuickToggleModel {
                                        id: unusedToggleModel
                                        sourceValues: unusedCanvas.live
                                            ? section.modelData.items.filter(item =>
                                                !QuickToggleCatalog.usesTrayPreview(item.type))
                                            : []
                                    }

                                    Repeater {
                                        model: unusedCanvas.live
                                            ? section.modelData.items.filter(item =>
                                                QuickToggleCatalog.usesTrayPreview(item.type))
                                            : []
                                        delegate: QuickToggleTrayPreview {
                                            required property int index
                                            required property var modelData
                                            buttonIndex: index
                                            buttonData: modelData
                                            isUnused: true
                                            editMode: root.editMode
                                            baseCellWidth: root.trayCellWidth
                                            baseCellHeight: root.baseCellHeight
                                            cellSpacing: root.spacing
                                            cellSize: modelData.sizeW
                                            pageIndex: root.currentPage
                                            gridColumns: root.columns
                                            panel: root
                                            gridRef: unusedCanvas
                                        }
                                    }

                                    Repeater {
                                        model: unusedToggleModel
                                        delegate: AndroidToggleDelegateChooser {
                                            editMode: root.editMode
                                            baseCellWidth: root.trayCellWidth
                                            baseCellHeight: root.baseCellHeight
                                            spacing: root.spacing
                                            isUnused: true
                                            pageIndex: root.currentPage
                                            gridColumns: root.columns
                                            panel: root
                                            gridRef: unusedCanvas
                                        }
                                    }

                                    // Arrows over tiles that have other designs: on top of
                                    // the tiles, placed from the same packed geometry.
                                    Repeater {
                                        model: unusedCanvas.live
                                            ? section.modelData.items.filter(item =>
                                                root.trayVariants(QuickToggleCatalog.variantGroup(item.type)).length > 1)
                                            : []
                                        delegate: QuickToggleVariantSwitcher {
                                            required property var modelData
                                            item: modelData
                                            panel: root
                                            cellWidth: root.trayCellWidth
                                            cellHeight: root.baseCellHeight
                                            cellSpacing: root.spacing
                                        }
                                    }
                                }
                                }
                            }
                        }
                    }
                }

                ScrollEdgeFade {
                    id: trayEdgeFade
                    target: trayFlickable
                    blurEdges: true
                    fadeSize: Math.round(Appearance.font.pixelSize.huge * 1.8)
                    color: "transparent"
                }
            }
        }
    }

    // Keep flickable in sync with currentPage
    onCurrentPageChanged: {
        if (!flickable.moving) {
            snapAnimation.stop();
            snapAnimation.to = currentPage * flickable.width;
            snapAnimation.start();
        }
    }

    // Clamp currentPage when pages are removed
    onPagesChanged: {
        if (currentPage >= pages.length) {
            currentPage = Math.max(0, pages.length - 1);
        }
    }

}
