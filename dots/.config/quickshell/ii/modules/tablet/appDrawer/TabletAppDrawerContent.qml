pragma ComponentBehavior: Bound

import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Quickshell

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.tablet.appWindow
import qs.modules.tablet.menu

/**
 * The drawer's inside: a search field over a grid of every installed app.
 *
 * The search field is not only an app filter. Typing also matches the shell's tool panels —
 * clipboard, emoji, translator, the file browser and the rest — and choosing one replaces
 * the grid with that panel, in place, the way Android's drawer search hands you a result
 * surface rather than opening a separate window. Escape backs out one level at a time:
 * tool -> grid -> closed.
 *
 * The tool panels themselves live in the ii family, so this file cannot import them. The
 * host component is injected by the composition root instead, which is the only place
 * allowed to reach across families. With nothing injected the drawer is still a complete
 * app drawer, minus the tools.
 */
Item {
    id: root

    /// Supplied by TabletFamily. See the note above on why this is injected.
    property Component toolHostComponent: null

    property real revealProgress: 1

    signal dismissRequested
    /// Long-pressed an app: the host decides what "add to home" means, because the home
    /// screen is a different module and the drawer must not reach into it.
    signal appHeld(string appId)

    readonly property string query: searchField.text
    property string activeToolId: ""

    // ── Touch metrics ───────────────────────────────────────────────────────
    // Everything is derived from the screen so one layout serves a small tablet and a
    // large scaled display, the same way the shade does it.
    readonly property real outerMargin: Math.max(20, Math.min(56, Math.round(root.width * 0.04)))
    readonly property real searchHeight: Math.max(52, Math.min(68, Math.round(root.height * 0.062)))
    readonly property var drawerConfig: Config.options?.tablet?.appDrawer
    /// Tile size, and with it the column count, which is what actually decides whether this
    /// reads as an app drawer or as a desktop menu.
    ///
    /// It used to work out at twelve or thirteen columns on a 1920px screen. A Pixel Tablet
    /// shows six; twelve is the density of a program list you scan with a pointer, not of a
    /// grid you hit with a thumb. Seven-ish columns with a bigger tile is the compromise for
    /// a landscape-only family on a wide display — this is not a portrait phone, and six
    /// columns across 1920px would leave tiles the size of playing cards.
    readonly property real tileWidth: (root.drawerConfig?.tileWidth ?? 0) > 0
        ? root.drawerConfig.tileWidth
        : Math.max(120, Math.min(200, Math.round(root.width / 7)))
    readonly property real tileHeight: Math.round(root.tileWidth * 1.18)
    readonly property real appIconSize: (root.drawerConfig?.iconSize ?? 0) > 0
        ? root.drawerConfig.iconSize
        : Math.round(root.tileWidth * 0.52)

    // ── Apps ────────────────────────────────────────────────────────────────
    /// "name" | "nameDesc" | "category" | "usage".
    readonly property string sortMode: root.drawerConfig?.sortMode ?? "name"
    /// One category at a time, and only with an empty query: a filter and a search are two
    /// answers to the same question, and showing both invites them to contradict.
    property string categoryFilter: ""

    /// The thirteen freedesktop main categories collapsed into groups someone would
    /// actually browse. Most apps claim several, so the first match in this order wins and
    /// the order is what decides where a dual-purpose app lands.
    readonly property var categoryGroups: [
        { id: "Development", symbol: "code", match: ["Development"] },
        { id: "Graphics", symbol: "palette", match: ["Graphics"] },
        { id: "Internet", symbol: "public", match: ["Network"] },
        { id: "Multimedia", symbol: "movie", match: ["AudioVideo", "Audio", "Video"] },
        { id: "Games", symbol: "sports_esports", match: ["Game"] },
        { id: "Office", symbol: "description", match: ["Office"] },
        { id: "Education", symbol: "school", match: ["Education", "Science"] },
        { id: "System", symbol: "settings", match: ["Settings", "System"] },
        { id: "Utilities", symbol: "handyman", match: ["Utility"] },
        { id: "Other", symbol: "category", match: [] }
    ]

    function categoryOf(entry) {
        const cats = Array.from(entry?.categories ?? []);
        for (const group of root.categoryGroups) {
            for (const wanted of group.match) {
                if (cats.indexOf(wanted) !== -1)
                    return group.id;
            }
        }
        return "Other";
    }

    function categorySymbol(categoryId) {
        const group = root.categoryGroups.find(g => g.id === categoryId);
        return group?.symbol ?? "category";
    }

    readonly property var apps: {
        const q = root.query.trim();
        // A query already ranks the results, and that ranking is what changes under the
        // user's fingers as they type. Re-sorting it alphabetically would throw away the
        // only ordering that responds to what they are doing.
        if (q.length > 0)
            return AppSearch.fuzzyQuery(q);

        let list = root.sortMode === "usage" ? AppSearch.frecencyQuery("").slice() : AppSearch.list.slice();
        if (root.categoryFilter.length > 0)
            list = list.filter(entry => root.categoryOf(entry) === root.categoryFilter);

        if (root.sortMode === "nameDesc")
            list.sort((a, b) => (b.name ?? "").localeCompare(a.name ?? ""));
        else if (root.sortMode === "category")
            list.sort((a, b) => {
                const ca = root.categoryOf(a);
                const cb = root.categoryOf(b);
                if (ca !== cb)
                    return ca.localeCompare(cb);
                return (a.name ?? "").localeCompare(b.name ?? "");
            });
        // "name" needs no sort: AppSearch.list is already alphabetical, and "usage" is
        // already in frecency order.
        return list;
    }

    /// Categories that actually have something in them. An empty chip is a dead end.
    readonly property var availableCategories: {
        if (root.query.trim().length > 0)
            return [];
        const present = new Set();
        for (const entry of AppSearch.list)
            present.add(root.categoryOf(entry));
        return root.categoryGroups.filter(group => present.has(group.id)).map(group => group.id);
    }

    /// Everything the grid shows: matching system apps first, then installed applications.
    /// System apps are wrapped so the delegate can tell them apart without inspecting types.
    ///
    /// Each row carries a stable key, which is what lets the grid animate a reorder instead
    /// of rebuilding: see applyGridDiff.
    readonly property var gridEntries: {
        const entries = [];
        // A category filter is a filter on applications; the shell's own surfaces are not
        // .desktop entries and have no category to be filtered by.
        if (root.categoryFilter.length === 0) {
            for (const app of root.matchingSystemApps)
                entries.push({ key: "sys:" + app.id, systemAppId: app.id, name: app.name, icon: app.icon, entry: null });
        }
        for (const entry of root.apps)
            entries.push({ key: "app:" + entry.id, systemAppId: "", name: entry.name, icon: "", entry: entry });
        return entries;
    }

    onGridEntriesChanged: root.applyGridDiff(root.gridEntries)

    /**
     * Reconcile the grid's model with `rows` in place, so the view can animate.
     *
     * Assigning a fresh JS array resets the view, and a reset fires no move transitions —
     * every tile is destroyed and rebuilt where it lands. Rows keyed and moved one at a
     * time is what makes the grid visibly rearrange itself as the query narrows, the same
     * way the ii launcher's result list does.
     */
    property bool _applyingDiff: false
    /// The grid's model is created after this Item's own property bindings, so the first
    /// gridEntries change arrives before there is anything to reconcile.
    property bool _gridReady: false

    function applyGridDiff(rows) {
        if (root._applyingDiff || !root._gridReady)
            return;
        root._applyingDiff = true;
        try {
            root._applyGridDiffUnguarded(rows);
        } finally {
            root._applyingDiff = false;
        }
    }

    function _applyGridDiffUnguarded(rows) {
        if (rows.length === 0) {
            if (gridModel.count > 0)
                gridModel.clear();
            return;
        }

        const currentKeys = [];
        for (let i = 0; i < gridModel.count; i++)
            currentKeys.push(gridModel.get(i).key);

        const wanted = new Set();
        for (const row of rows)
            wanted.add(row.key);

        // Backwards, so the indexes of the rows still to be examined stay valid.
        for (let i = currentKeys.length - 1; i >= 0; i--) {
            if (!wanted.has(currentKeys[i])) {
                gridModel.remove(i);
                currentKeys.splice(i, 1);
            }
        }

        for (let newIndex = 0; newIndex < rows.length; newIndex++) {
            const row = rows[newIndex];
            const currentIndex = currentKeys.indexOf(row.key);

            if (currentIndex === -1) {
                gridModel.insert(newIndex, {
                    key: row.key,
                    systemAppId: row.systemAppId,
                    name: row.name,
                    icon: row.icon,
                    entry: row.entry
                });
                currentKeys.splice(newIndex, 0, row.key);
                continue;
            }

            if (currentIndex !== newIndex) {
                gridModel.move(currentIndex, newIndex, 1);
                currentKeys.splice(newIndex, 0, currentKeys.splice(currentIndex, 1)[0]);
            }
        }

        // Whatever the passes above did, the model has to end exactly as long as `rows`.
        // Anything past that length is a tile the diff failed to account for, and it would
        // stay on screen and stay tappable.
        while (gridModel.count > rows.length)
            gridModel.remove(gridModel.count - 1);
    }

    // ── System apps ─────────────────────────────────────────────────────────
    // Shell surfaces the drawer lists as apps: usage stats, modes, the timetable, the
    // keybind sheet. See TabletSystemApps.
    //
    // Always listed, not only while searching. Hiding them behind a search meant the only
    // way to find them was already knowing they existed, which is no way to ship a feature.
    // They lead the grid so they read as their own group rather than as strays among the
    // installed applications.
    readonly property var matchingSystemApps: root.query.trim().length === 0
        ? TabletSystemApps.available
        : TabletSystemApps.search(root.query)

    // ── Tools ───────────────────────────────────────────────────────────────
    // Only what the user could actually open: a panel whose module is switched off is not
    // offered, exactly as the launcher does it.
    // ── Everything else the query can reach ─────────────────────────────────
    // The drawer is this family's launcher, so it has to answer the questions the ii
    // launcher answers: files, and the clipboard. The clipboard especially — reaching it
    // used to mean typing "clipboard", finding a chip, and hitting a small target, which is
    // three deliberate acts for something people want constantly. Entries are results now.
    readonly property int maximumSideResults: root.drawerConfig?.sideResultLimit ?? 6

    readonly property var clipboardResults: {
        const q = root.query.trim();
        if (q.length === 0 || !(root.drawerConfig?.showClipboardResults ?? true))
            return [];
        return Cliphist.fuzzyQuery(q).slice(0, root.maximumSideResults);
    }

    readonly property var fileResults: {
        if (root.query.trim().length === 0 || !(root.drawerConfig?.showFileResults ?? true))
            return [];
        return (LauncherSearch.fileResults ?? []).slice(0, root.maximumSideResults);
    }

    // LauncherSearch owns the `fd` process; feeding it the drawer's query is what makes
    // fileResults populate. Only while the drawer is up, so a closed drawer never spawns a
    // file search.
    onQueryChanged: {
        if (root.revealProgress > 0.01)
            LauncherSearch.query = root.query;
    }

    function clipboardText(entry) {
        return String(entry ?? "").replace(/^\s*\S+\s+/, "").trim();
    }

    function fileName(path) {
        const parts = String(path ?? "").split("/");
        return parts[parts.length - 1] || path;
    }

    readonly property var matchingTools: {
        const q = root.query.trim().toLowerCase();
        if (q.length === 0 || !root.toolHostComponent)
            return [];
        return SearchPanelRegistry.enabledPanels.filter(panel => {
            if (String(panel.label).toLowerCase().includes(q))
                return true;
            return (panel.keywords ?? []).some(keyword => String(keyword).toLowerCase().startsWith(q));
        });
    }

    function openTool(toolId) {
        root.activeToolId = toolId;
    }

    function closeTool() {
        root.activeToolId = "";
    }

    /// One step back. Returns false when there is nothing left to back out of, so the
    /// window above can close itself instead.
    function goBack() {
        if (inlineMenu.opened) {
            inlineMenu.close();
            return true;
        }
        if (root.categoryFilter.length > 0) {
            root.categoryFilter = "";
            return true;
        }
        if (root.activeToolId.length > 0) {
            root.closeTool();
            return true;
        }
        if (searchField.text.length > 0) {
            searchField.text = "";
            return true;
        }
        return false;
    }

    function activateTopResult() {
        if (root.activeToolId.length > 0)
            return;
        if (root.matchingSystemApps.length > 0 && root.apps.length === 0) {
            TabletSystemApps.launch(root.matchingSystemApps[0].id);
            root.dismissRequested();
            return;
        }
        if (root.apps.length > 0) {
            root.apps[0].execute();
            root.dismissRequested();
            return;
        }
        if (root.matchingTools.length > 0)
            root.openTool(root.matchingTools[0].id);
    }

    function reset() {
        root.activeToolId = "";
        root.categoryFilter = "";
        inlineMenu.close();
        searchField.text = "";
        appGrid.contentY = 0;
    }

    /// Opened from the host when a dock button asks for a specific panel.
    function openToolById(toolId) {
        if (SearchPanelRegistry.enabledPanels.some(panel => panel.id === toolId))
            root.openTool(toolId);
    }

    // ── Sort menu ───────────────────────────────────────────────────────────
    readonly property var sortOptions: [
        { id: "name", symbol: "sort_by_alpha", label: Translation.tr("Name (A–Z)") },
        { id: "nameDesc", symbol: "sort_by_alpha", label: Translation.tr("Name (Z–A)") },
        { id: "category", symbol: "category", label: Translation.tr("Category") },
        { id: "usage", symbol: "trending_up", label: Translation.tr("Most used") }
    ]

    function setSortMode(mode) {
        if (Config.options?.tablet?.appDrawer)
            Config.options.tablet.appDrawer.sortMode = mode;
    }

    function openSortMenu(item) {
        const point = item.mapToItem(root, item.width / 2, item.height + 8);
        inlineMenu.openAt(point.x, point.y, root.sortOptions.map(option => ({
            symbol: option.symbol,
            label: option.label,
            checked: root.sortMode === option.id,
            trigger: () => root.setSortMode(option.id)
        })), Translation.tr("Sort by"), "", "sort");
    }

    /// The Android long-press menu. "Add to home screen" is in here rather than being the
    /// whole gesture, which is what it used to be — the same press now offers everything
    /// that press could reasonably mean instead of silently picking one.
    function openAppMenu(item, entry) {
        if (!entry)
            return;
        const point = item.mapToItem(root, item.width / 2, item.height * 0.6);
        const actions = [];

        for (const action of (entry.actions ?? [])) {
            actions.push({
                symbol: "shortcut",
                label: action.name ?? "",
                trigger: () => {
                    action.execute();
                    root.dismissRequested();
                }
            });
        }

        actions.push({
            symbol: "launch",
            label: Translation.tr("Open"),
            trigger: () => {
                entry.execute();
                root.dismissRequested();
            }
        });
        actions.push({
            symbol: "add_to_home_screen",
            label: Translation.tr("Add to home screen"),
            trigger: () => {
                root.appHeld(entry.id);
                root.dismissRequested();
            }
        });
        actions.push({
            symbol: TaskbarApps.isPinned(entry.id) ? "keep_off" : "keep",
            label: TaskbarApps.isPinned(entry.id)
                ? Translation.tr("Unpin from dock")
                : Translation.tr("Pin to dock"),
            trigger: () => TaskbarApps.togglePin(entry.id)
        });

        inlineMenu.openAt(point.x, point.y, actions, entry.name ?? entry.id,
            Quickshell.iconPath(AppSearch.guessIcon(entry.id), "image-missing"), "");
    }

    function focusSearch() {
        searchField.forceActiveFocus();
    }

    // ── Layout ──────────────────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.outerMargin
        // No bottom inset: the grid runs to the edge of the screen and fades out there
        // instead of stopping at a margin, where the last row was being sliced in half.
        anchors.bottomMargin: 0
        spacing: root.outerMargin * 0.6

        // Search bar. Android puts it at the top of the drawer and it keeps focus while
        // you scroll, so typing at any point filters without a second tap.
        Rectangle {
            id: searchBar
            Layout.fillWidth: true
            Layout.maximumWidth: Math.min(720, root.width * 0.6)
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredHeight: root.searchHeight
            radius: height / 2
            color: Appearance.colors.colLayer1

            opacity: root.revealProgress
            transform: Translate {
                y: (1 - root.revealProgress) * root.searchHeight * 0.8
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 20
                anchors.rightMargin: 12
                spacing: 12

                MaterialSymbol {
                    text: root.activeToolId.length > 0 ? "arrow_back" : "search"
                    iconSize: Math.round(root.searchHeight * 0.42)
                    color: Appearance.colors.colOnLayer1

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -12
                        enabled: root.activeToolId.length > 0
                        onClicked: root.closeTool()
                    }
                }

                TextField {
                    id: searchField
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    verticalAlignment: Text.AlignVCenter
                    background: null
                    color: Appearance.colors.colOnLayer1
                    placeholderText: Translation.tr("Search apps and tools")
                    placeholderTextColor: Appearance.colors.colSubtext
                    font.family: Appearance.font.family.main
                    font.pixelSize: Math.round(root.searchHeight * 0.30)
                    selectByMouse: true

                    Keys.onEscapePressed: {
                        if (!root.goBack())
                            root.dismissRequested();
                    }

                    // Enter takes the top result, the way Android's drawer search does. Apps
                    // win when there are any: someone typing a name wants that app, not a
                    // tool that happens to share a keyword. A query that matches no app but
                    // does match a tool opens the tool instead of doing nothing.
                    //
                    // onAccepted, not Keys.onReturnPressed: TextField consumes Return itself
                    // and turns it into this signal, so the Keys handler never sees it.
                    onAccepted: root.activateTopResult()
                }

                MaterialSymbol {
                    visible: searchField.text.length > 0
                    text: "close"
                    iconSize: Math.round(root.searchHeight * 0.40)
                    color: Appearance.colors.colOnLayer1

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -12
                        onClicked: searchField.text = ""
                    }
                }

                // Only without a query: with one, the order is the ranking, so a sort
                // control here would offer to break the results rather than arrange them.
                MaterialSymbol {
                    id: sortButton
                    visible: searchField.text.length === 0 && (root.drawerConfig?.showSortButton ?? true)
                    text: "sort"
                    iconSize: Math.round(root.searchHeight * 0.40)
                    color: Appearance.colors.colOnLayer1

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -12
                        onClicked: root.openSortMenu(sortButton)
                    }
                }
            }
        }

        // Category chips. Android's drawer is one flat list, but a desktop's application
        // menu is thousands of entries deep, and the categories are already in the .desktop
        // files — not offering them means the only way through the list is scrolling.
        Flickable {
            id: categoryStrip
            Layout.fillWidth: true
            Layout.preferredHeight: categoryStrip.shown ? categoryRow.implicitHeight : 0
            visible: Layout.preferredHeight > 0
            opacity: root.revealProgress
            contentWidth: categoryRow.implicitWidth
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            // Hidden while a panel owns the body: the chips filter a grid that is not on
            // screen, so leaving them up offers a control that does nothing visible.
            readonly property bool shown: (root.drawerConfig?.showCategoryFilter ?? true)
                && root.activeToolId.length === 0
                && root.query.trim().length === 0
                && root.availableCategories.length > 1

            Behavior on Layout.preferredHeight {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(categoryStrip)
            }

            RowLayout {
                id: categoryRow
                spacing: 8

                Repeater {
                    model: [""].concat(root.availableCategories)

                    delegate: Rectangle {
                        id: categoryChip
                        required property string modelData
                        readonly property bool selected: root.categoryFilter === categoryChip.modelData

                        implicitWidth: categoryChipRow.implicitWidth + 28
                        implicitHeight: Math.max(40, Math.round(root.searchHeight * 0.68))
                        radius: height / 2
                        color: categoryChip.selected ? Appearance.colors.colPrimary
                            : (categoryChipArea.pressed ? Appearance.colors.colLayer2Active : Appearance.colors.colLayer2)

                        Behavior on color {
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(categoryChip)
                        }

                        RowLayout {
                            id: categoryChipRow
                            anchors.centerIn: parent
                            spacing: 6

                            MaterialSymbol {
                                text: categoryChip.modelData.length === 0
                                    ? "apps" : root.categorySymbol(categoryChip.modelData)
                                iconSize: 18
                                color: categoryChip.selected ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                            }

                            StyledText {
                                text: categoryChip.modelData.length === 0
                                    ? Translation.tr("All") : Translation.tr(categoryChip.modelData)
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: categoryChip.selected ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                            }
                        }

                        MouseArea {
                            id: categoryChipArea
                            anchors.fill: parent
                            onClicked: root.categoryFilter = categoryChip.modelData
                        }
                    }
                }
            }
        }

        // Tool suggestions, between the field and the grid, like Android's result chips.
        Flickable {
            Layout.fillWidth: true
            Layout.preferredHeight: root.matchingTools.length > 0 ? toolRow.implicitHeight : 0
            visible: Layout.preferredHeight > 0
            contentWidth: toolRow.implicitWidth
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Behavior on Layout.preferredHeight {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }

            RowLayout {
                id: toolRow
                spacing: 10

                Repeater {
                    model: root.matchingTools

                    delegate: Rectangle {
                        id: toolChip
                        required property var modelData

                        implicitWidth: chipRow.implicitWidth + 32
                        implicitHeight: Math.max(44, Math.round(root.searchHeight * 0.78))
                        radius: height / 2
                        color: chipArea.pressed ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer2

                        Behavior on color {
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                        }

                        RowLayout {
                            id: chipRow
                            anchors.centerIn: parent
                            spacing: 8

                            MaterialSymbol {
                                text: toolChip.modelData.icon ?? "wand_stars"
                                iconSize: 20
                                color: Appearance.colors.colOnLayer2
                            }

                            StyledText {
                                text: toolChip.modelData.label ?? toolChip.modelData.id
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnLayer2
                            }
                        }

                        MouseArea {
                            id: chipArea
                            anchors.fill: parent
                            onClicked: root.openTool(toolChip.modelData.id)
                        }
                    }
                }
            }
        }

        // The body is either the app grid or, once a tool is chosen, that tool's panel.
        Item {
            id: body
            Layout.fillWidth: true
            Layout.fillHeight: true

            // The grid arrives a beat after the search field, so the drawer reads as one
            // surface assembling rather than everything appearing at once.
            readonly property real bodyReveal: Math.max(0, Math.min(1, (root.revealProgress - 0.2) / 0.8))
            opacity: body.bodyReveal
            transform: Translate {
                // `body`, not `parent`: a Transform is not an Item and has no visual parent,
                // so `parent.bodyReveal` was undefined and translated the grid by NaN.
                y: (1 - body.bodyReveal) * 40
            }

            // Results that are not apps get their own column beside the grid rather than
            // being mixed into it: a clipboard entry is a line of text and an app is an
            // icon, and interleaving them makes both harder to scan. On a tablet there is
            // room for both at once, which is the whole reason the drawer is full-screen.
            readonly property bool hasSideResults: root.clipboardResults.length > 0
                || root.fileResults.length > 0
            // Not readonly: a Behavior cannot animate a readonly property, and this one has
            // to ease so the grid does not jump sideways the instant a result arrives.
            property real sideColumnWidth: body.hasSideResults
                ? Math.max(320, Math.min(520, Math.round(body.width * 0.32))) : 0

            Behavior on sideColumnWidth {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(body)
            }

            /**
             * The bottom of each scroller, faded to transparent.
             *
             * ScrollEdgeFade paints a colour band, which works when the view sits on a flat
             * surface of that colour. This one sits on a blurred screencopy, so any colour
             * the band could paint is itself see-through: it washed the last row out
             * without ever ending it, and the row stayed visibly sliced underneath. Fading
             * the view's own alpha works against any backdrop, because what shows through
             * IS the backdrop.
             */
            /// Deep enough to take most of a row, or a row that straddles the edge still
            /// shows a solid top half above the fade and reads as cut.
            readonly property real fadeSize: Math.round(root.tileHeight * 0.9)

            GridView {
                id: appGrid
                // Fades the grid's own alpha, not a colour band over it. ScrollEdgeFade
                // paints a colour, which ends content only when the surface behind is that
                // colour — this one sits on a blurred screencopy, so any colour it could
                // paint is itself see-through and the last row stayed visibly sliced under
                // the wash. What shows through here is the backdrop, which is the point.
                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: Math.max(1, appGrid.width)
                        height: Math.max(1, appGrid.height)
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: "white" }
                            GradientStop {
                                position: appGrid.height > 0
                                    ? Math.max(0, 1 - body.fadeSize / appGrid.height) : 1
                                color: "white"
                            }
                            GradientStop { position: 1.0; color: "transparent" }
                        }
                    }
                }
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                anchors.rightMargin: body.sideColumnWidth > 0 ? body.sideColumnWidth + 24 : 0
                visible: root.activeToolId.length === 0
                enabled: visible

                cellWidth: root.tileWidth
                cellHeight: root.tileHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                cacheBuffer: 600

                // Room to scroll the last row clear of the fade. Without it the bottom row
                // can only ever be reached half-covered by the gradient.
                // Enough room to scroll the last row clear of the fade, so the bottom of
                // the list can still be read in full.
                bottomMargin: body.fadeSize

                model: ListModel {
                    id: gridModel
                    // The rows carry a DesktopEntry in one field and nothing in it for the
                    // shell's own surfaces. Static role inference locks that field to
                    // whichever shape lands first and drops every later write in silence.
                    dynamicRoles: true
                }

                Component.onCompleted: {
                    root._gridReady = true;
                    root.applyGridDiff(root.gridEntries);
                }

                // What makes a narrowing query read as the grid rearranging itself rather
                // than as a new grid appearing. `y` and `x` only: an interrupted opacity
                // transition can strand a tile invisible, and a tile that never paints is a
                // worse bug than a tile that never animates.
                move: Transition {
                    NumberAnimation {
                        properties: "x,y"
                        duration: Appearance.animation.elementMove.duration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.emphasized
                    }
                }

                displaced: Transition {
                    NumberAnimation {
                        properties: "x,y"
                        duration: Appearance.animation.elementMove.duration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.emphasized
                    }
                }

                add: Transition {
                    NumberAnimation {
                        property: "scale"
                        from: 0.86
                        to: 1
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Easing.OutCubic
                    }
                }

                delegate: Item {
                    id: appCell
                    required property var modelData
                    width: appGrid.cellWidth
                    height: appGrid.cellHeight

                    readonly property bool isSystemApp: String(appCell.modelData.systemAppId ?? "").length > 0

                    TabletAppTile {
                        id: appTile
                        anchors.centerIn: parent
                        width: appGrid.cellWidth - 8
                        height: appGrid.cellHeight - 8
                        entry: appCell.isSystemApp ? null : appCell.modelData.entry
                        systemName: appCell.isSystemApp ? appCell.modelData.name : ""
                        systemIcon: appCell.isSystemApp ? appCell.modelData.icon : ""
                        iconSize: root.appIconSize
                        onActivated: {
                            if (appCell.isSystemApp)
                                TabletSystemApps.launch(appCell.modelData.systemAppId);
                            else
                                appCell.modelData.entry.execute();
                            root.dismissRequested();
                        }
                        onHeld: {
                            // A shell surface is not a desktop icon: it has no .desktop entry
                            // to place and no actions to offer, so long-press does nothing.
                            if (appCell.isSystemApp)
                                return;
                            if (root.drawerConfig?.longPressMenu ?? true) {
                                root.openAppMenu(appTile, appCell.modelData.entry);
                                return;
                            }
                            root.appHeld(appCell.modelData.entry.id);
                            root.dismissRequested();
                        }
                        onContextRequested: {
                            // A right click has unambiguous pointer semantics and therefore
                            // always opens the menu, even when touch hold is configured for
                            // the legacy direct add-to-home shortcut.
                            if (!appCell.isSystemApp)
                                root.openAppMenu(appTile, appCell.modelData.entry);
                        }
                    }
                }
            }

            // ── Clipboard and files ─────────────────────────────────────────
            Flickable {
                id: sideColumn
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: body.sideColumnWidth
                visible: width > 1 && root.activeToolId.length === 0
                clip: true
                contentHeight: sideContent.implicitHeight
                bottomMargin: body.fadeSize
                boundsBehavior: Flickable.StopAtBounds
                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: Math.max(1, sideColumn.width)
                        height: Math.max(1, sideColumn.height)
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: "white" }
                            GradientStop {
                                position: sideColumn.height > 0
                                    ? Math.max(0, 1 - body.fadeSize / sideColumn.height) : 1
                                color: "white"
                            }
                            GradientStop { position: 1.0; color: "transparent" }
                        }
                    }
                }

                ColumnLayout {
                    id: sideContent
                    width: sideColumn.width
                    spacing: 4

                    StyledText {
                        Layout.fillWidth: true
                        Layout.leftMargin: 16
                        Layout.topMargin: 4
                        visible: root.clipboardResults.length > 0
                        text: Translation.tr("Clipboard")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                    }

                    Repeater {
                        model: root.clipboardResults

                        delegate: TabletSearchResultRow {
                            required property var modelData
                            Layout.fillWidth: true
                            symbol: "content_paste"
                            title: root.clipboardText(modelData.entry ?? modelData)
                            subtitle: Translation.tr("Copy to clipboard")
                            onActivated: {
                                Cliphist.copy(modelData.entry ?? modelData);
                                root.dismissRequested();
                            }
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        Layout.leftMargin: 16
                        Layout.topMargin: 8
                        visible: root.fileResults.length > 0
                        text: Translation.tr("Files")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                    }

                    Repeater {
                        model: root.fileResults

                        delegate: TabletSearchResultRow {
                            required property var modelData
                            Layout.fillWidth: true
                            symbol: "description"
                            title: root.fileName(modelData)
                            subtitle: String(modelData)
                            onActivated: {
                                Quickshell.execDetached(["xdg-open", String(modelData)]);
                                root.dismissRequested();
                            }
                        }
                    }
                }
            }

            // The ends of both scrollers, faded into the surface behind them rather than
            // cut off by it. The colour is the drawer's own scrim, so the fade lands on
            // exactly what is painted underneath.
            // Outside the GridView: a child of a Flickable joins its scrolling content, so
            // an empty-state placeholder put in there would drift with the view.
            PagePlaceholder {
                anchors.fill: parent
                // Only when nothing at all matched — apps, clipboard and files alike.
                visible: appGrid.visible && !body.hasSideResults
                shown: gridModel.count === 0
                icon: "search_off"
                title: Translation.tr("No apps")
                description: Translation.tr("Nothing matches this search")
                sizeScale: 1.3
                descriptionHorizontalAlignment: Text.AlignHCenter
            }

            Loader {
                id: toolHost
                anchors.fill: parent
                active: root.activeToolId.length > 0 && root.toolHostComponent !== null
                visible: active
                sourceComponent: root.toolHostComponent

                onLoaded: toolHost.syncToPanel()

                function syncToPanel() {
                    if (!toolHost.item)
                        return;
                    toolHost.item.activePanelId = root.activeToolId;
                    toolHost.item.searchQuery = "";
                }

                Connections {
                    target: root
                    function onActiveToolIdChanged() {
                        toolHost.syncToPanel();
                    }
                }
            }
        }
    }

    // Last, and outside the layout: it has to cover the grid it was opened from.
    TabletInlineMenu {
        id: inlineMenu
        anchors.fill: parent
    }
}
