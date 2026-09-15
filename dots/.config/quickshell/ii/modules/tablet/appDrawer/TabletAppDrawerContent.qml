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
import "TabletAppGridLayout.js" as AppGridLayout
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
        const shellRows = [];
        // A category filter is a filter on applications; the shell's own surfaces are not
        // .desktop entries and have no category to be filtered by.
        if (root.categoryFilter.length === 0) {
            for (const app of root.matchingSystemApps)
                shellRows.push({ key: "sys:" + app.id, systemAppId: app.id, name: app.name, icon: app.icon, entry: null });
            // Panels ride the same row shape, so they get the same delegate and the same
            // tinted plate. The "tool:" prefix on the id is what tells the tap handler to
            // open one in place instead of launching it.
            for (const panel of root.shelfTools)
                shellRows.push({ key: "tool:" + panel.id, systemAppId: "tool:" + panel.id,
                                 name: panel.label ?? panel.id, icon: panel.icon ?? "wand_stars", entry: null });
        }

        const appRows = [];
        for (const entry of root.apps)
            appRows.push({ key: "app:" + entry.id, systemAppId: "", name: entry.name, icon: "", entry: entry });

        // A query has already ranked the applications and there is nothing to interleave
        // that ranking with; usage and category have nothing to say about a surface that is
        // not an application. In those three the shell's items keep an end of their own
        // rather than being sorted by a key they do not have.
        if (root.query.trim().length > 0)
            return root.withUniqueKeys(shellRows.concat(appRows));
        if (root.sortMode === "usage" || root.sortMode === "category")
            return root.withUniqueKeys(appRows.concat(shellRows));

        const all = shellRows.concat(appRows);
        all.sort((left, right) => root.sortMode === "nameDesc"
            ? String(right.name ?? "").localeCompare(String(left.name ?? ""))
            : String(left.name ?? "").localeCompare(String(right.name ?? "")));
        return root.withUniqueKeys(all);
    }

    /**
     * Make every row's key unique.
     *
     * The diff identifies a row by its key and finds it with indexOf, which returns the
     * *first* match. Two rows sharing a key therefore both resolve to the same model row:
     * one gets moved twice and the other is never placed, which is how the grid ended up
     * with tiles stacked on each other and cells left empty. Duplicate ids are not
     * hypothetical here — the same application shipped in /usr/share and again in
     * ~/.local/share yields two entries the launcher is right to show separately.
     */
    function withUniqueKeys(rows) {
        const seen = {};
        for (const row of rows) {
            const base = row.key;
            const count = seen[base] ?? 0;
            seen[base] = count + 1;
            if (count > 0)
                row.key = `${base}#${count}`;
        }
        return rows;
    }

    onGridEntriesChanged: root.applyGridDiff(root.gridEntries)

    /**
     * The handful of apps you actually open, above the grid.
     *
     * Android's drawer opens on a predicted row because most launches are a small set of
     * apps and hunting for them alphabetically every time is work the launcher can do for
     * you. `AppUsage` has been scoring launches all along — the "Most used" sort already
     * reads it — so this is surfacing a signal the shell already had rather than a new one.
     *
     * Hidden when the grid is already frecency-ordered, since the row would then just be its
     * own first line, and hidden while searching, because a query is a better predictor than
     * a history and the two would disagree in front of the user.
     */
    readonly property bool suggestionsAvailable: root.query.trim().length === 0
        && root.categoryFilter.length === 0
        && root.sortMode !== "usage"
        && (root.drawerConfig?.showSuggestions ?? true)

    /// Tall enough for the tile's own contents and no taller. The grid's cell height leaves
    /// deliberate air around each tile so rows breathe; a single row of six inherits that as
    /// a band of dead space under the labels instead.
    /**
     * How tall the predicted band is, worked out from numbers that are known immediately.
     *
     * This matters more than it looks. The band lives in the grid's top margin, and a margin
     * that arrives a frame late leaves the view resting somewhere that is no longer the top —
     * which is exactly how three earlier attempts ended up opening the drawer halfway down
     * the app list. Measuring a child's implicit height is what made it late; a sum of
     * constants is correct on the first frame and needs no correction afterwards.
     */
    readonly property real suggestionsBandHeight: root.suggestedApps.length > 0
        ? Math.round(Appearance.font.pixelSize.smaller * 1.7 + 6
                     + root.suggestionTileHeight + root.outerMargin * 0.9)
        : 0

    readonly property real suggestionTileHeight: Math.round(
        root.appIconSize + 6 + Appearance.font.pixelSize.smaller * 2.4 + 18)

    readonly property var suggestedApps: {
        if (!root.suggestionsAvailable)
            return [];
        // Only apps with a real score: frecencyQuery pads its result with everything else in
        // alphabetical order, and an alphabetical tail dressed up as a prediction is worse
        // than no row at all.
        const ranked = AppSearch.frecencyQuery("").filter(entry => AppUsage.getScore(entry.id) > 0);
        return ranked.slice(0, 6);
    }

    // ── A–Z index ───────────────────────────────────────────────────────────
    /**
     * Where each letter starts in the grid, for the scrubber down the right-hand side.
     *
     * A few hundred apps in an alphabetical grid is a long way to drag a finger to reach
     * anything past the middle of the alphabet, and this family has no scrollbar to throw a
     * thumb at. Android's launcher solves it with a letter rail; so does this.
     *
     * Every row is indexed. The shell's surfaces used to lead the grid in their own order, so
     * letting them claim letters sent "A" to the top of the list rather than to the first
     * thing beginning with A; with one sorted list that distinction is gone.
     */
    readonly property bool alphabetIndexAvailable: root.query.trim().length === 0
        && (root.sortMode === "name" || root.sortMode === "nameDesc")
        && root.gridEntries.length > 40

    readonly property var alphabetIndex: {
        if (!root.alphabetIndexAvailable)
            return [];
        const firstIndexFor = {};
        const inOrder = [];
        for (let i = 0; i < root.gridEntries.length; i++) {
            const row = root.gridEntries[i];
            const name = String(row.name ?? "").trim();
            if (name.length === 0)
                continue;
            // Fold the accent off so "Ãpp" files under A rather than under a letter with no
            // rail entry, and bucket everything non-alphabetic under one heading.
            const folded = name.charAt(0).toLocaleUpperCase()
                .normalize("NFD").replace(/[̀-ͯ]/g, "");
            const letter = /^[A-Z]$/.test(folded) ? folded : "#";
            if (firstIndexFor[letter] === undefined) {
                firstIndexFor[letter] = i;
                inOrder.push({ letter: letter, index: i });
            }
        }
        return inOrder;
    }

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

        /**
         * Rebuild outright when little survives.
         *
         * The incremental path exists so a narrowing query reads as the grid rearranging
         * itself, and for that it is worth the moves. Typing into an empty field, or
         * clearing the field again, replaces essentially the whole list — hundreds of moves
         * whose transitions run over each other, and a delegate whose move is interrupted
         * is left wherever it was: stacked on a neighbour, or nowhere at all. Below half
         * survival there is no rearrangement to show anyway.
         *
         * The survival ratio is measured against the LONGER of the two lists, not the
         * shorter one. Against the shorter one, going from a six-result query back to the
         * whole library scored 6/6 survival and took the incremental path — several hundred
         * inserts, each one displacing every tile after it, with the transitions cut short
         * by the next insert. That is exactly the shape of the bug this guard exists to
         * prevent, and it is what left the reopened drawer with tiles stacked on their
         * neighbours and cells empty. `churn` catches the same case from the other side:
         * even a high survival ratio is not worth animating past a few dozen operations.
         */
        let retained = 0;
        for (const key of currentKeys)
            if (wanted.has(key))
                retained++;
        const churn = (currentKeys.length - retained) + (rows.length - retained);
        if (currentKeys.length > 0
                && (retained < Math.max(currentKeys.length, rows.length) * 0.5 || churn > 48)) {
            gridModel.clear();
            for (const row of rows)
                gridModel.append({
                    key: row.key,
                    systemAppId: row.systemAppId,
                    name: row.name,
                    icon: row.icon,
                    entry: row.entry
                });
            return;
        }

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

    /**
     * Every tool the shell can host, offered without typing for one.
     *
     * Categories filter applications; these are not applications. They are the shell's own
     * panels — clipboard, emoji, the translator, the media downloader — and until now the
     * only way to one was to guess its name into the search field, which means only someone
     * who already knew it existed could find it.
     *
     * Drawn as icon-led pills in an accent tint rather than as more outlined category chips,
     * because they answer a different question and a row that looks the same reads as more
     * of the same.
     */
    /**
     * The shell's own panels, listed in the grid as if they were applications.
     *
     * They were a row of labelled pills under the categories, which made them a separate
     * kind of object to learn about before you could use one. They are not: from where the
     * user is standing, the clipboard and the translator open the same way an app does.
     */
    readonly property var shelfTools: {
        if (!root.toolHostComponent || !(root.drawerConfig?.showToolShelf ?? true))
            return [];
        const q = root.query.trim().toLowerCase();
        if (q.length === 0)
            return SearchPanelRegistry.enabledPanels;
        return SearchPanelRegistry.enabledPanels.filter(panel => {
            if (String(panel.label).toLowerCase().includes(q))
                return true;
            return (panel.keywords ?? []).some(keyword => String(keyword).toLowerCase().startsWith(q));
        });
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
        // The top of a Flickable with a top margin is -topMargin, not 0. Zero was one whole
        // band below it, so the drawer opened with the predicted row already scrolled off
        // and the top fade fully in — the grid looked like it had been left mid-scroll.
        appGrid.contentY = -appGrid.topMargin;
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
            /// Shallower than the bottom's. The bottom fade has to swallow a whole row
            /// running off the screen edge; the top one only has to say "there is more
            /// above", and a deep one there would eat the row you just scrolled to.
            readonly property real topFadeSize: Math.round(root.tileHeight * 0.32)

            GridView {
                id: appGrid
                // Fades the grid's own alpha, not a colour band over it. ScrollEdgeFade
                // paints a colour, which ends content only when the surface behind is that
                // colour — this one sits on a blurred screencopy, so any colour it could
                // paint is itself see-through and the last row stayed visibly sliced under
                // the wash. What shows through here is the backdrop, which is the point.
                /// How much of the top fade is in. Zero at rest, so the first row is not
                /// dimmed until there is something above it to have scrolled past.
                property real topFade: Math.max(0, Math.min(1,
                    (appGrid.contentY - appGrid.originY + appGrid.topMargin) / 48))

                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: Math.max(1, appGrid.width)
                        height: Math.max(1, appGrid.height)
                        gradient: Gradient {
                            GradientStop {
                                position: 0.0
                                color: Qt.rgba(1, 1, 1, 1 - appGrid.topFade)
                            }
                            GradientStop {
                                position: appGrid.height > 0
                                    ? Math.min(0.45, body.topFadeSize / appGrid.height) : 0
                                color: "white"
                            }
                            GradientStop {
                                position: appGrid.height > 0
                                    ? Math.max(0.55, 1 - body.fadeSize / appGrid.height) : 1
                                color: "white"
                            }
                            GradientStop { position: 1.0; color: "transparent" }
                        }
                    }
                }
                /**
                 * The columns, centred in what is left after the rail and the side column.
                 *
                 * A GridView lays its cells out from its left edge and leaves whatever does
                 * not divide evenly as dead space on the right — so a grid anchored across
                 * the whole body was a block of icons pushed to one side, with a ragged gap
                 * beside the A–Z rail that grew and shrank with the tile size. Sizing the
                 * view to a whole number of columns and centring *that* is what makes the
                 * grid sit in the middle of the screen, and it is exact rather than
                 * approximately even.
                 *
                 * Centred against the whole body rather than against what the rail leaves,
                 * because the rail is a thin overlay on the edge and the eye centres the
                 * block against the screen. The clamp is what keeps that honest: when the
                 * slack is smaller than the reserve — a side column open, a very wide tile
                 * — the grid slides left just far enough to clear it instead of running
                 * underneath.
                 */
                readonly property real rightReserve: body.sideColumnWidth > 0
                    ? body.sideColumnWidth + 24
                    : (letterRail.width > 0 ? letterRail.width + 8 : 0)
                readonly property real availableWidth: Math.max(0, body.width - appGrid.rightReserve)
                readonly property int columnCount: AppGridLayout.columnCount(
                    appGrid.availableWidth, appGrid.cellWidth)

                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: AppGridLayout.gridWidth(appGrid.availableWidth, appGrid.cellWidth)
                x: AppGridLayout.originX(body.width, appGrid.availableWidth, appGrid.width)

                // The columns change place when the side column opens; easing that keeps it
                // reading as the grid making room rather than as the grid being replaced.
                Behavior on x {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(appGrid)
                }

                visible: root.activeToolId.length === 0
                enabled: visible

                /// Room for the predicted band, which is parented into contentItem below.
                topMargin: root.activeToolId.length === 0 ? root.suggestionsBandHeight : 0

                cellWidth: root.tileWidth
                cellHeight: root.tileHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                // Two screens' worth rather than a flat 600px. Tiles are ~240px tall now, so
                // the old buffer held barely two rows and delegates were being destroyed and
                // rebuilt constantly while scrolling — every rebuild re-runs the icon theme
                // lookup, which is the moment a tile can come back without one.
                cacheBuffer: Math.max(600, Math.round(root.tileHeight * 8))

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
                            if (appCell.isSystemApp) {
                                const id = String(appCell.modelData.systemAppId);
                                if (id.startsWith("tool:")) {
                                    // Opens inside the drawer: the surface stays where the
                                    // user's attention already is, so the drawer must not
                                    // dismiss itself afterwards.
                                    root.openTool(id.substring(5));
                                    return;
                                }
                                TabletSystemApps.launch(id);
                            } else
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


            /**
             * The predicted row, scrolling with the apps rather than pinned above them.
             *
             * Parented into the grid's own contentItem: that is the item scrolling moves, so
             * the band travels with the list without anything computing an offset from
             * contentY. Every previous attempt did compute one, and every one of them drifted
             * — the view's idea of the top and the band's position were two separate things
             * that had to be kept in step across the model filling, the strip measuring and
             * the reveal animating.
             *
             * It sits at -height, i.e. in the top margin the grid reserves for it, which is
             * why that margin has to be a number known from the first frame.
             */
            Item {
                id: suggestionsBand
                parent: appGrid.contentItem
                y: -height
                width: appGrid.width
                height: root.suggestionsBandHeight
                visible: root.suggestedApps.length > 0 && root.activeToolId.length === 0

                StyledText {
                    id: suggestionsLabel
                    x: 4
                    y: 0
                    text: Translation.tr("Most used")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }

                Row {
                    anchors.left: parent.left
                    anchors.top: suggestionsLabel.bottom
                    anchors.topMargin: 6
                    spacing: 0

                    Repeater {
                        model: root.suggestedApps

                        delegate: TabletAppTile {
                            id: suggestionTile
                            required property var modelData

                            width: root.tileWidth
                            height: root.suggestionTileHeight
                            entry: suggestionTile.modelData
                            iconSize: root.appIconSize

                            onActivated: {
                                suggestionTile.modelData.execute();
                                root.dismissRequested();
                            }
                            onHeld: {
                                if (root.drawerConfig?.longPressMenu ?? true)
                                    root.openAppMenu(suggestionTile, suggestionTile.modelData);
                                else
                                    root.appHeld(suggestionTile.modelData.id);
                            }
                            onContextRequested: root.openAppMenu(suggestionTile, suggestionTile.modelData)
                        }
                    }
                }
            }

            // ── A–Z scrubber ────────────────────────────────────────────────
            // A rail rather than a scrollbar: the target is a letter, not a position, and a
            // letter is something you can aim a thumb at. Dragging scrubs, so finding "S" is
            // one gesture instead of a tap and a look.
            Item {
                id: letterRail
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                // Not inset by the grid's bottom fade. That fade ends the *grid's* content;
                // applying it here cost the rail two hundred pixels of height, which is what
                // squeezed twenty-six letters into a third of the column.
                anchors.bottomMargin: Appearance.sizes.elevationMargin
                width: root.alphabetIndexAvailable && body.sideColumnWidth < 1 ? letterRailWidth : 0
                visible: width > 0 && root.activeToolId.length === 0

                // Wide enough to be aimed at rather than hit by luck: a 28px strip is a
                // pointer target, and this is scrubbed with a thumb.
                readonly property real letterRailWidth: Math.max(52, Math.round(root.tileWidth * 0.34))
                /// Rows share the column's height. Twenty-six letters rarely reach the cap,
                /// so the cap only matters on a short list or a very tall screen.
                readonly property real rowHeight: root.alphabetIndex.length > 0
                    ? Math.min(46, letterRail.height / root.alphabetIndex.length) : 0

                /// Turns a y inside the rail into a jump. Clamped, because a drag that runs
                /// off either end should stick to the first or last letter rather than stop
                /// responding.
                function jumpTo(y) {
                    if (root.alphabetIndex.length === 0 || letterRail.rowHeight <= 0)
                        return;
                    const slot = Math.floor((y - letters.y) / letterRail.rowHeight);
                    const clamped = Math.max(0, Math.min(root.alphabetIndex.length - 1, slot));
                    appGrid.positionViewAtIndex(root.alphabetIndex[clamped].index, GridView.Beginning);
                    letterRail.activeSlot = clamped;
                }

                property int activeSlot: -1
                /// Kept a moment after the finger lifts so the letter you landed on fades
                /// out instead of snapping back the instant you let go.
                property bool scrubbing: false

                Timer {
                    id: railRelease
                    interval: 450
                    repeat: false
                    onTriggered: letterRail.activeSlot = -1
                }

                Column {
                    id: letters
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width

                    Repeater {
                        model: root.alphabetIndex

                        delegate: Item {
                            id: letterSlot
                            required property var modelData
                            required property int index

                            width: letters.width
                            height: letterRail.rowHeight

                            /// 1 on the letter under the finger, falling off over the two
                            /// either side. A single highlighted letter tells you where you
                            /// are; a gradient tells you which way you are going, which is
                            /// what a scrub needs.
                            // Not readonly: a Behavior cannot animate a readonly property,
                            // and the whole point of this one is that it eases.
                            property real emphasis: {
                                if (letterRail.activeSlot < 0)
                                    return 0;
                                const distance = Math.abs(letterRail.activeSlot - letterSlot.index);
                                return distance > 2 ? 0 : 1 - distance / 3;
                            }

                            Behavior on emphasis {
                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(letterSlot)
                            }

                            // A filled pill under the active letter, not an outline: this
                            // project has no borders, and a fill also reads at arm's length.
                            Rectangle {
                                anchors.centerIn: parent
                                width: letterRail.letterRailWidth * 0.82 * letterSlot.emphasis
                                height: width
                                radius: height / 2
                                color: Appearance.colors.colPrimary
                                opacity: letterSlot.emphasis
                            }

                            StyledText {
                                anchors.centerIn: parent
                                text: letterSlot.modelData.letter
                                // Grows towards the finger. The step is small on purpose —
                                // the rail must not reflow while it is being dragged.
                                font.pixelSize: Appearance.font.pixelSize.small
                                    + Math.round(letterSlot.emphasis * 8)
                                font.weight: letterSlot.emphasis > 0.66 ? Font.Bold : Font.Medium
                                color: letterSlot.emphasis > 0.66
                                    ? Appearance.colors.colOnPrimary : Appearance.colors.colSubtext

                                Behavior on color {
                                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                                }
                            }
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onPressed: mouse => {
                        railRelease.stop();
                        letterRail.scrubbing = true;
                        letterRail.jumpTo(mouse.y);
                    }
                    onPositionChanged: mouse => {
                        // Hovering previews which letter you would land on; pressing goes
                        // there. Same handler, because on a touchscreen there is no hover and
                        // the first event is always a press anyway.
                        if (pressed) {
                            letterRail.jumpTo(mouse.y);
                        } else if (letterRail.rowHeight > 0) {
                            const slot = Math.floor((mouse.y - letters.y) / letterRail.rowHeight);
                            letterRail.activeSlot = Math.max(0,
                                Math.min(root.alphabetIndex.length - 1, slot));
                        }
                    }
                    onReleased: {
                        letterRail.scrubbing = false;
                        railRelease.restart();
                    }
                    onCanceled: {
                        letterRail.scrubbing = false;
                        railRelease.restart();
                    }
                    onExited: {
                        if (!letterRail.scrubbing)
                            railRelease.restart();
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
