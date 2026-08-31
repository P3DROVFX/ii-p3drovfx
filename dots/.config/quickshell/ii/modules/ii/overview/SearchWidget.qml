pragma ComponentBehavior: Bound

import Qt5Compat.GraphicalEffects
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
import qs.modules.common.functions

Item {
    id: root
    width: implicitWidth
    height: (root.exiting ? root.exitHeight : searchWidgetContent.height) + (GlobalStates.searchConnectActive ? 0 : Appearance.sizes.elevationMargin * 2)
    focus: true
    signal requestToggleActions
    property bool inNotchMode: false
    // Set by the per-monitor Overview host so a deep-link is acknowledged by
    // the monitor that is actually rendering the Search surface.
    property string surfaceMonitorName: ""
    property string routedSessionRequestId: ""
    // File operations are process-backed and must outlive the visible Search
    // surface. The per-monitor Overview host propagates this through its lazy
    // loader, keeping the invisible object tree alive until work completes.
    readonly property bool keepAlive: registeredPanelHostLoader.keepAlive
    readonly property var surfaceScreen: Quickshell.screens.find(screen => screen.name === root.surfaceMonitorName) ?? null
    // Saved panel preferences are never rewritten when the Search moves to a
    // smaller monitor. Only the rendered surface is clamped to a safe viewport.
    readonly property real maximumSurfaceWidth: root.surfaceScreen
        ? Math.max(320, root.surfaceScreen.width - Appearance.sizes.elevationMargin * 4)
        : Number.POSITIVE_INFINITY
    readonly property real maximumSurfaceHeight: root.surfaceScreen
        ? Math.max(320, root.surfaceScreen.height - Appearance.sizes.elevationMargin * 8)
        : Number.POSITIVE_INFINITY
    readonly property real activePanelHeightBudget: Math.max(280,
        root.maximumSurfaceHeight
            - (root.isAiMode ? 16 : searchBar.implicitHeight + searchBar.verticalPadding * 2 + 10))
    // Explicit panel requests come from normal search rows and external
    // deep-links. The text remains editable as that panel's local filter.
    property string requestedPanelId: ""

    readonly property string xdgConfigHome: Directories.config
    readonly property int typingDebounceInterval: 200
    readonly property int typingResultLimit: {
        const query = LauncherSearch.query;
        if (!query)
            return 15;
        const isPrefixed = root.searchPrefixValues.some(prefix => query.startsWith(prefix));
        return isPrefixed ? 500 : 15;
    }
    readonly property bool isSearching: false
    readonly property bool showSkeletons: false

    // One page is what the list can plausibly show plus scroll buffer. The
    // ListView only builds delegates for visible rows, so the cost of a page is
    // the ListModel ops, not the delegates.
    // Inset a result row keeps from the panel's edge. The list's bottom padding
    // reads as the same edge, so both come from here rather than drifting apart
    // as two separate literals.
    readonly property real rowSideMargin: Appearance.sizes.elevationMargin
    readonly property int resultPageSize: 30
    // Rows a single section may claim before every other section has had its
    // turn at the page budget. Its long tail comes back on the second pass.
    readonly property int sectionPageLimit: 8
    // `baseHeight` describes the complete normal Search surface, not only its
    // rows. Reserve the field's own chrome so changing the Settings slider
    // immediately changes where the regular result list begins scrolling.
    readonly property real normalSearchChromeHeight: searchBar.implicitHeight + searchBar.verticalPadding * 2
    readonly property real maxResultsHeight: Math.max(0,
        (Config.options.search.baseHeight ?? 500) - root.normalSearchChromeHeight)
    property int loadedResultsCount: root.resultPageSize
    // Left/Right stays available to edit the query unless the selected row is
    // one of the Settings controls that can consume a horizontal adjustment.
    property bool selectedResultHandlesHorizontalNavigation: false
    property string actionFeedbackText: ""

    onMaxResultsHeightChanged: {
        if (appResults)
            appResults.updateMeasuredContentExtent();
    }

    function showActionFeedback(message) {
        const text = String(message ?? "").trim();
        if (text.length === 0)
            return;
        root.actionFeedbackText = text;
        actionFeedbackTimer.restart();
    }

    Timer {
        id: actionFeedbackTimer
        interval: 3200
        onTriggered: root.actionFeedbackText = ""
    }

    function getFilteredResultsCount() {
        const results = LauncherSearch.results;
        const q = LauncherSearch.query.trim().toLowerCase();
        const showNowPlaying = Config.options.search.nowPlaying?.enable ?? Config.options.search.showNowPlayingBubble;
        let count = 0;
        for (let i = 0; i < results.length; i++) {
            const item = results[i];
            if (!item || ((Config.options.search.alwaysListApps || q !== "" || !showNowPlaying) && item.key === "mpris:now-playing"))
                continue;
            const sectionId = root.resultSectionId(item);
            if (sectionId === "continue" && !root.queryHasAnyPrefix && !root.showContinuationRows)
                continue;
            if (root.categoryAcceptsSection(sectionId))
                count++;
        }
        return count;
    }

    function loadMoreResults() {
        if (!GlobalStates.overviewOpen)
            return;
        const total = root.getFilteredResultsCount();
        if (loadedResultsCount >= total)
            return;
        loadedResultsCount = Math.min(total, loadedResultsCount + root.resultPageSize);
        // Both callers — the scroll position and the cursor nearing the end —
        // are signals the view emits *while* a diff is mutating the model.
        // Diffing from inside one would restart the diff halfway through the
        // previous one, off a key mirror that no longer describes the model.
        // `restart()` also collapses the burst of both signals into one pass.
        pageLoadTimer.restart();
    }

    Timer {
        id: pageLoadTimer
        interval: 0
        repeat: false
        onTriggered: {
            if (!GlobalStates.overviewOpen)
                return;
            appResults.applyResultDiff(root.processResults(LauncherSearch.results));
        }
    }

    Timer {
        id: categoryApplyTimer
        interval: 0
        repeat: false
        onTriggered: {
            if (!GlobalStates.overviewOpen || root.isAnySpecialMode)
                return;
            appResults.applyResultDiff(root.processResults(LauncherSearch.results));
            appResults.selectFirst();
            root.focusSearchInput();
        }
    }

    // Keep one authoritative query path. Binding this property directly to
    // LauncherSearch while also synchronizing it from SearchBar created a
    // QML binding loop during the AI handoff (the query is intentionally
    // cleared when the chat surface takes over).
    property string searchingText: ""

    Connections {
        target: LauncherSearch
        function onQueryChanged() {
            if (root.searchingText !== LauncherSearch.query)
                root.searchingText = LauncherSearch.query;
        }
    }
    readonly property var resolvedPanel: SearchPanelRegistry.resolve(root.searchingText)
    readonly property string activePanelId: root.isAiMode ? "ai" : (root.requestedPanelId || root.resolvedPanel?.id || "")
    readonly property var activePanel: SearchPanelRegistry.byId(root.activePanelId)
    // Registry-hosted panels have a content gutter independent from the
    // SearchBar's own inset. Account for it in the outer width so their
    // declared panel width remains the usable width, not the clipped width.
    readonly property real hostedPanelSideMargin: Appearance.sizes.elevationMargin
    readonly property bool activePanelUsesHost: root.activePanel?.hosted === true
    // Panels normally share SearchBar as their local filter. A panel can
    // explicitly own the primary TextInput (Typing Test) without requiring a
    // panel-id branch in focus or keyboard routing.
    readonly property bool activePanelOwnsInput: root.activePanel?.inputOwner === "panel"
    readonly property bool isClipboardMode: root.activePanelId === "clipboard"
    readonly property bool isBluetoothMode: root.activePanelId === "bluetooth"
    readonly property bool isTranslatorMode: root.activePanelId === "translator"
    readonly property bool isMediaDownloaderMode: root.activePanelId === "mediaDownloader"
    readonly property bool isMaterialSymbolsMode: root.activePanelId === "materialSymbols"
    /**
     * Whether the AI surface owns the search.
     *
     * This is state, not a formula. It used to be derived from the query —
     * and entering AI mode clears the query, which fed straight back into the
     * formula. Qt saw a binding loop and froze the property, so Escape and
     * the back button had nothing left to change and the panel could not be
     * left. Every way in sets the latch; only `exitAiMode()` clears it.
     */
    readonly property bool isAiMode: Ai.enabled && root.aiModeLocked
    // Auto AI recognition: when enabled, a settled query that matches no app,
    // command or prefix hands the search over to the AI chat. Kept apart from
    // the latch so the timer cannot fire twice for one query.
    property bool aiAutoEngaged: false
    property bool aiModeLocked: false
    property int searchHistoryIndex: -1
    property bool applyingSearchHistory: false
    // Prevents a query that entered AI mode from being copied repeatedly when
    // the launcher query is cleared or the draft is restored asynchronously.
    property bool aiDraftHydrated: false
    readonly property bool aiAutoTriggerEnabled: Ai.enabled && (Config.options.search.ai?.trigger ?? "prefix") === "auto"
    readonly property var searchPrefixValues: SearchPanelRegistry.activePrefixes
        .concat(LauncherSearch.enabledUtilityPrefixes())
        .filter((value, index, values) => value && values.indexOf(value) === index)
    readonly property bool queryHasAnyPrefix: root.searchPrefixValues.some(prefix => root.searchingText.startsWith(prefix))
    // Results that are actual matches — generic continuation rows never count.
    // A calculator result does: valid math must not be replaced by auto-AI.
    readonly property int realResultCount: LauncherSearch.results.filter(r => {
        const key = String(r?.key ?? "");
        return r && key !== "cmd:shell" && key !== "web:search" && key !== "ai:ask"
            && key !== "mpris:now-playing" && !r.isFallback && !key.startsWith("fallback:");
    }).length
    readonly property bool isAnySpecialMode: root.activePanelId.length > 0
    /**
     * Publish "a panel owns the search" for consumers that live outside any
     * PanelWindow (the Super shortcut, the workspace grid).
     *
     * Only the surface on the active search monitor may publish: a hosted panel
     * latches through `requestedPanelId`, which is per-surface, so the idle
     * SearchWidget of a second monitor would otherwise clear the flag the
     * moment the prefix is stripped out of the shared query.
     */
    function publishPanelOwnership() {
        if (GlobalStates.activeSearchMonitor !== "" && root.surfaceMonitorName !== ""
                && root.surfaceMonitorName !== GlobalStates.activeSearchMonitor)
            return;
        GlobalStates.searchPanelActive = root.isAnySpecialMode || root.isAiMode;
    }

    onIsAnySpecialModeChanged: root.publishPanelOwnership()
    readonly property string activePanelQuery: {
        if (!root.activePanel)
            return "";
        const prefix = SearchPanelRegistry.prefixOf(root.activePanel);
        return prefix.length > 0 && root.searchingText.startsWith(prefix)
            ? root.searchingText.slice(prefix.length)
            : root.searchingText;
    }

    readonly property var activePanelItem: {
        if (root.activePanelUsesHost)
            return registeredPanelHostLoader.item?.activeItem ?? null;
        return root.activePanelId === "ai" ? aiPanelLoader.item : null;
    }

    onActivePanelItemChanged: {
        if (root.activePanelOwnsInput && root.activePanelItem)
            Qt.callLater(root.focusPrimaryInput);
    }

    // Legacy panels previously had bespoke Loaders and signal wiring. Hosted
    // panels now share one lifecycle, while the active item's optional signals
    // remain available without coupling SearchWidget to a concrete panel type.
    Connections {
        target: root.activePanelItem
        ignoreUnknownSignals: true
        function onRequestSetSearchQuery(query) {
            root.setSearchingText(query);
        }
        function onRequestFocusSearchInput() {
            root.focusSearchInput();
        }
    }

    SearchKeyRouter {
        id: searchKeyRouter
        activePanelItem: root.activePanelItem
        resultsList: appResults
        searchWidget: root
    }

    // Latch: however AI mode was entered (prefix typed, suggestion row or
    // auto detection), it stays on until back/Esc — deleting the text must
    // not yank the panel away mid-conversation.
    onIsAiModeChanged: {
        root.publishPanelOwnership();
        if (root.isAiMode) {
            if (!root.aiDraftHydrated) {
                root.aiDraftHydrated = true;
                const initialDraft = StringUtils.cleanOnePrefix(root.searchingText, [Config.options.search.prefix.ai]).trim();
                if (Ai.draft.trim().length === 0 && initialDraft.length > 0)
                    Ai.draft = initialDraft;
                LauncherSearch.query = "";
            }
            // Focus the AI composer immediately so the user can type without
            // clicking. The latch is *not* set here: `isAiMode` reads
            // `aiModeLocked`, so writing it back from this handler made the
            // binding depend on its own result — Qt broke the loop by
            // freezing the property, and Escape then had nothing to change.
            Qt.callLater(root.focusPrimaryInput);
        } else {
            root.aiDraftHydrated = false;
        }
        root.tryConsumeSurfaceIntent();
    }

    /**
     * Enters AI mode and keeps it: however it was entered, deleting the text
     * must not yank the panel away mid-conversation. Every way in calls this;
     * only the back button and Escape call `exitAiMode()`.
     */
    function engageAiMode() {
        if (!Ai.enabled)
            return;
        root.aiModeLocked = true;
    }

    function selectSearchHistory(direction) {
        const entries = Array.from(Persistent.states.search.recentQueries ?? []);
        if (entries.length === 0)
            return;
        root.searchHistoryIndex = Math.max(-1, Math.min(entries.length - 1, root.searchHistoryIndex + direction));
        root.applyingSearchHistory = true;
        root.searchingText = root.searchHistoryIndex === -1 ? "" : String(entries[root.searchHistoryIndex]);
        root.applyingSearchHistory = false;
    }

    // Debounce so a query that is still matching things asynchronously does
    // not flip the whole widget into AI mode between keystrokes.
    Timer {
        id: aiAutoEngageTimer
        interval: 350
        onTriggered: {
            if (!root.isAnySpecialMode && root.aiAutoTriggerEnabled && !root.aiAutoEngaged && !root.queryHasAnyPrefix && root.searchingText.trim().length >= 3 && root.realResultCount === 0) {
                root.aiAutoEngaged = true;
                root.engageAiMode();
            }
        }
    }

    // A prefix is a route trigger, not part of the hosted panel's local
    // search. Latch its target before clearing the trigger, otherwise the
    // panel would immediately resolve back to ordinary Search. The AI route
    // has its own draft lifecycle and intentionally stays outside this path.
    function consumePanelPrefix(): bool {
        if (root.requestedPanelId.length > 0)
            return false;
        const panel = SearchPanelRegistry.resolve(root.searchingText);
        if (!panel?.hosted)
            return false;
        const prefix = SearchPanelRegistry.prefixOf(panel);
        if (prefix.length === 0)
            return false;
        root.requestedPanelId = panel.id;
        if (panel.id === "fileBrowser")
            GlobalStates.clearFileBrowserSearchResults();
        root.setSearchingText(root.searchingText.slice(prefix.length));
        return true;
    }

    onSearchingTextChanged: {
        if (!root.applyingSearchHistory)
            root.searchHistoryIndex = -1;
        if (root.consumePanelPrefix())
            return;
        // Typing the prefix is one of the ways in, so it latches here rather
        // than as a reaction to the mode changing.
        if (Ai.enabled && root.searchingText.startsWith(Config.options.search.prefix.ai))
            root.engageAiMode();
        if (root.searchingText === "" || root.queryHasAnyPrefix) {
            root.aiAutoEngaged = false;
            aiAutoEngageTimer.stop();
        } else if (!root.isAnySpecialMode && root.aiAutoTriggerEnabled && !root.aiAutoEngaged && root.searchingText.trim().length >= 3 && root.realResultCount === 0) {
            aiAutoEngageTimer.restart();
        }
    }

    Component.onCompleted: root.searchingText = LauncherSearch.query

    onRealResultCountChanged: {
        if (root.aiAutoEngaged)
            return;
        if (!root.isAnySpecialMode && root.aiAutoTriggerEnabled && !root.queryHasAnyPrefix && root.searchingText.trim().length >= 3 && root.realResultCount === 0)
            aiAutoEngageTimer.restart();
        else
            aiAutoEngageTimer.stop();
    }

    Connections {
        target: GlobalStates
        function onOverviewOpenChanged() {
            if (!GlobalStates.overviewOpen) {
                root.requestedPanelId = "";
                if (root.isAiMode || root.aiAutoEngaged || root.aiModeLocked)
                    root.resetAiSearchState(false);
                else
                    root.cancelSearch();
            }
        }
    }

    function consumePanelIntent() {
        if (!GlobalStates.overviewOpen)
            return;
        const requested = GlobalStates.consumePendingSearchPanel();
        const requestedQuery = GlobalStates.consumePendingSearchPanelQuery();
        const panel = SearchPanelRegistry.byId(requested);
        if (panel && panel.enabled()) {
            root.requestedPanelId = requested;
            if (requestedQuery.length > 0)
                root.setSearchingText(requestedQuery);
            Qt.callLater(root.focusSearchInput);
        }
    }

    Connections {
        target: GlobalStates
        function onSearchPanelNavigationRequestChanged() {
            root.consumePanelIntent();
        }
        function onOverviewOpenChanged() {
            if (GlobalStates.overviewOpen)
                root.consumePanelIntent();
        }
    }
    // Idle Search (empty query, suggestions on) renders through the exact same
    // ListView as a typed query — LauncherSearch populates `results` with a
    // curated home screen instead of match rows (see
    // LauncherSearch._computeIdleSuggestions). This flag is now purely
    // cosmetic: it widens the field and switches the search icon's shape, the
    // same way a real query does, before any row has actually loaded.
    readonly property bool showSuggestionsPanel: Config.options.search.suggestions.enable && !Config.options.search.alwaysListApps && !root.isAnySpecialMode && root.searchingText === ""
    readonly property bool alwaysListAppsMode: Config.options.search.alwaysListApps && !root.isAnySpecialMode
    readonly property bool showIdleNowPlaying: searchingText === ""
        && !isAnySpecialMode
        && !alwaysListAppsMode
        && (Config.options.search.nowPlaying?.enable ?? Config.options.search.showNowPlayingBubble)
        && LauncherSearch.results.some(result => String(result?.key ?? "") === "mpris:now-playing")
    property bool showResults: searchingText !== "" || isAnySpecialMode || alwaysListAppsMode || showIdleNowPlaying || showSuggestionsPanel
    property string overviewPosition: (Config.options.bar?.bottom ? "bottom" : (Config.options.overview?.position ?? ""))

    // Re-enable item transitions after panel open animation completes
    Timer {
        id: enableTransitionsTimer
        interval: 400
        repeat: false
        onTriggered: root.suppressItemTransitions = false
    }

    /**
     * Geometry is held still for the length of the close.
     *
     * Closing the overview clears the query and the rows, which collapses this
     * container from a full result list back to the bare field. That collapse
     * used to run *while* the window was already sliding out, so closing with
     * results on screen read as a faster, harsher animation than closing with
     * an empty field — two motions stacked on one another instead of one. It
     * also dragged the wrapper's scale origin, which is bound to half the
     * widget's height, along with it.
     *
     * Holding the last size means the widget leaves exactly the way an empty
     * one does. What it contains is irrelevant by then: the whole thing is
     * fading out.
     */
    property bool exiting: false
    property real exitWidth: 0
    property real exitHeight: 0

    Timer {
        id: exitHoldTimer
        // Past the overview window's own exit, after which none of this is on
        // screen and the size stops mattering.
        interval: 400
        repeat: false
        onTriggered: root.exiting = false
    }

    // Suppress item transitions during panel open/close to avoid flicker
    property bool suppressItemTransitions: true

    /**
     * Typing cadence gate.
     *
     * A burst of keystrokes wants the list to be *correct* as fast as possible:
     * every intermediate ordering is thrown away before the eye can read it, so
     * animating it only spends frames. A deliberate single edit is where the
     * reorder actually reads as motion, and that is where it stays enabled.
     *
     * Measuring the gap between edits picks between the two without a debounce
     * that would delay the results themselves.
     */
    readonly property int burstTypingThreshold: 120
    property double lastQueryEditTime: 0
    // Query the cursor was last snapped to the top for. Asynchronous result
    // sources (file search, app index) refresh the list long after the query
    // settled; those refreshes must not move the user's selection.
    property string selectionAnchorQuery: "\u0000"

    function noteQueryEdit() {
        const now = Date.now();
        root.suppressItemTransitions = (now - root.lastQueryEditTime) < root.burstTypingThreshold;
        root.lastQueryEditTime = now;
        typingSettleTimer.restart();
    }

    Timer {
        id: typingSettleTimer
        interval: root.burstTypingThreshold
        repeat: false
        onTriggered: root.suppressItemTransitions = false
    }

    Connections {
        target: GlobalStates
        function onOverviewOpenChanged() {
            if (GlobalStates.overviewOpen) {
                exitHoldTimer.stop();
                root.exiting = false;
                root.resultCategoryId = "all";
                // Suppress transitions while panel is animating open
                root.suppressItemTransitions = true;
                // Wipe stale results immediately so panel opens empty (no ghost expansion)
                resultModel.clear();
                root.loadedResultsCount = root.resultPageSize;
                if (root.alwaysListAppsMode || root.showIdleNowPlaying || root.showSuggestionsPanel) {
                    Qt.callLater(() => {
                        appResults.applyResultDiff(root.processResults(LauncherSearch.results));
                        root.focusFirstItem();
                    });
                }
                // Re-enable transitions after open animation
                enableTransitionsTimer.restart();
            } else {
                // Freeze the size *before* anything below can shrink it: the
                // query is cleared by another handler on this same signal.
                if (!GlobalStates.searchConnectActive) {
                    root.exitWidth = searchWidgetContent.width;
                    root.exitHeight = searchWidgetContent.height;
                    root.exiting = true;
                    exitHoldTimer.restart();
                }
                // Suppress transitions then clear immediately.
                // Since suppressItemTransitions=true, remove transitions run at duration:0
                // (instantaneous/invisible), so no flicker even though model clears now.
                root.suppressItemTransitions = true;
                resultModel.clear();
            }
        }
    }

    Connections {
        target: LauncherSearch
        function onRequestOpenSettings() {
            GlobalStates.overviewOpen = false;
            Qt.callLater(() => {
                GlobalStates.openSettings();
            });
        }
    }
    implicitWidth: (root.exiting ? root.exitWidth : searchWidgetContent.implicitWidth) + (GlobalStates.searchConnectActive ? 0 : Appearance.sizes.elevationMargin * 2)
    implicitHeight: (root.exiting ? root.exitHeight : searchWidgetContent.implicitHeight) + (GlobalStates.searchConnectActive ? 0 : Appearance.sizes.elevationMargin * 2)

    // Track animation state via Connections to the animation IDs
    property bool _heightAnimating: false
    property bool _widthAnimating: false

    Connections {
        target: heightAnim
        function onRunningChanged() {
            root._heightAnimating = heightAnim.running;
        }
    }

    Connections {
        target: widthAnim
        function onRunningChanged() {
            root._widthAnimating = widthAnim.running;
        }
    }

    // Signals to DynamicIslandStyle that the open animation is stable (no active resize)
    // When true, the DI pill disables its own behaviors and follows SearchWidget's animations directly.
    // In notch mode we always return false so the DI pill remains responsible for all animations.
    readonly property bool openStateStable: root.inNotchMode ? false : (!root._heightAnimating && !root._widthAnimating)

    function focusFirstItem() {
        if (root.isAiMode || root.activePanelOwnsInput) {
            root.focusPrimaryInput();
        } else if (root.activePanelItem && typeof root.activePanelItem.focusInput === "function") {
            root.activePanelItem.focusInput();
        } else {
            appResults.selectFirst();
        }
    }

    function focusPrimaryInput() {
        if (root.activePanelOwnsInput && root.activePanelItem
                && typeof root.activePanelItem.focusInput === "function") {
            root.activePanelItem.focusInput();
            return;
        }
        root.focusSearchInput();
    }

    function focusSearchInput() {
        if (root.isAiMode && aiPanelLoader.item) {
            aiPanelLoader.item.focusComposer();
            return;
        }
        searchBar.forceFocus();
    }

    function selectedResultRow(): var {
        if (appResults.currentIndex < 0 || appResults.currentIndex >= appResults.count)
            return null;
        const delegate = appResults.itemAtIndex(appResults.currentIndex);
        return delegate?.item ?? delegate ?? null;
    }

    function refreshSelectedResultNavigation() {
        const row = root.selectedResultRow();
        root.selectedResultHandlesHorizontalNavigation = row?.supportsHorizontalNavigation === true;
    }

    function navigateSelectedResult(direction: string): bool {
        const row = root.selectedResultRow();
        if (!row)
            return false;
        if (direction === "left" && typeof row.navigateLeft === "function")
            return row.navigateLeft();
        if (direction === "right" && typeof row.navigateRight === "function")
            return row.navigateRight();
        return false;
    }

    function continueInSidebar() {
        const panel = aiPanelLoader.item;
        Ai.surfaceRouter.open({
            surface: "sidebar",
            monitorName: root.surfaceMonitorName,
            sessionId: Ai.sessions.currentId,
            focusIntent: "composer",
            scrollAnchor: panel && typeof panel.captureHandoffState === "function"
                ? panel.captureHandoffState()
                : null
        });
    }

    // A router request is consumed only after this per-monitor Search host is
    // visible and the AI panel exists. Session loading is also acknowledged
    // only after Ai has selected the requested session, so a deep-link cannot
    // clear itself while another conversation is still on screen.
    function tryConsumeSurfaceIntent() {
        const intent = Ai.surfaceRouter.pendingIntent;
        if (!intent || intent.surface !== "search" || intent.monitorName !== root.surfaceMonitorName)
            return;
        // A chat handed over from the sidebar opens the panel rather than
        // waiting for someone to type the prefix first.
        if (GlobalStates.overviewOpen && !root.isAiMode)
            root.engageAiMode();
        if (!GlobalStates.overviewOpen || !root.isAiMode || !aiPanelLoader.item)
            return;
        if (intent.sessionId.length > 0 && Ai.sessions.currentId !== intent.sessionId) {
            if (root.routedSessionRequestId !== intent.requestId) {
                root.routedSessionRequestId = intent.requestId;
                Ai.openSession(intent.sessionId);
            }
            return;
        }
        const panel = aiPanelLoader.item;
        if (!panel || typeof panel.applySurfaceIntent !== "function")
            return;
        if (!panel.applySurfaceIntent(intent))
            return;
        Ai.surfaceRouter.acknowledge(intent.requestId);
        root.routedSessionRequestId = "";
    }

    Connections {
        target: Ai.surfaceRouter
        function onPendingIntentChanged() {
            root.tryConsumeSurfaceIntent();
        }
    }

    Connections {
        target: Ai.sessions
        function onCurrentIdChanged() {
            root.tryConsumeSurfaceIntent();
        }
        function onLoadedChanged() {
            root.tryConsumeSurfaceIntent();
        }
    }

    Connections {
        target: Ai
        function onMessageIDsChanged() {
            root.tryConsumeSurfaceIntent();
        }
        function onMessageByIDChanged() {
            root.tryConsumeSurfaceIntent();
        }
    }

    Connections {
        target: aiPanelLoader
        function onStatusChanged() {
            root.tryConsumeSurfaceIntent();
        }
    }

    Connections {
        target: GlobalStates
        function onOverviewOpenChanged() {
            root.tryConsumeSurfaceIntent();
        }
    }

    function disableExpandAnimation() {
        searchBar.animateWidth = false;
    }

    function cancelSearch() {
        // Normal Search is intentionally ephemeral. The AI composer owns its
        // draft per session; the launcher query must not become a second draft
        // store that brings the last ordinary search back on the next open.
        root.searchingText = "";
        root.requestedPanelId = "";
        LauncherSearch.query = "";
        searchBar.searchInput.text = "";
        searchBar.animateWidth = true;
    }

    // AI state belongs to the AI surface, never to the normal launcher. Clear
    // both halves of the query synchronizer so a previous "&" handoff cannot
    // immediately relatch the panel when the ordinary Search opens again.
    // `Ai.draft` remains untouched: the AI panel alone owns that unsent text.
    function resetAiSearchState(focusNormalSearch = false) {
        root.aiAutoEngaged = false;
        root.aiModeLocked = false;
        root.aiDraftHydrated = false;
        aiAutoEngageTimer.stop();
        root.searchingText = "";
        LauncherSearch.query = "";
        searchBar.searchInput.text = "";
        if (focusNormalSearch) {
            Qt.callLater(() => {
                root.focusSearchInput();
                searchBar.searchInput.forceActiveFocus();
            });
        }
    }

    // Leave AI chat and return to the plain search without discarding an
    // unsent AI draft. Sent drafts are cleared by Ai after submission starts.
    function exitAiMode() {
        root.resetAiSearchState(true);
    }

    function exitActivePanel(): bool {
        if (!root.isAnySpecialMode)
            return false;
        if (root.isAiMode) {
            root.exitAiMode();
            return true;
        }
        root.requestedPanelId = "";
        root.searchingText = "";
        LauncherSearch.query = "";
        searchBar.searchInput.text = "";
        Qt.callLater(root.focusSearchInput);
        return true;
    }

    function handlePanelBackspace(): bool {
        if (!root.isAnySpecialMode)
            return false;
        if (root.activePanelItem && typeof root.activePanelItem.navigateBack === "function"
                && root.activePanelItem.navigateBack())
            return true;
        return root.exitActivePanel();
    }

    // One Escape path for the whole overview surface. A PanelWindow cannot
    // host a Keys attached property, so Overview's window shortcut delegates
    // here; the focused composer and child controls use the same function.
    function handleEscape(): bool {
        if (root.isAiMode) {
            if (aiPanelLoader.item && typeof aiPanelLoader.item.handleEscape === "function" && aiPanelLoader.item.handleEscape())
                return true;
            root.exitAiMode();
            return true;
        }
        if (root.activePanelItem && typeof root.activePanelItem.handleEscape === "function"
                && root.activePanelItem.handleEscape())
            return true;
        return root.exitActivePanel();
    }

    // Send the current search bar text as a chat message. The search bar is
    // the composer in AI mode, so both Enter in the field and the send button
    // in the panel funnel through here.
    function sendAiMessage(messageText) {
        const raw = (typeof messageText === "string" && messageText.length > 0) ? messageText : Ai.draft;
        const cleaned = StringUtils.cleanOnePrefix(raw, [Config.options.search.prefix.ai]).trim();
        if (!cleaned)
            return;
        const parsed = AiActionRegistry.parseInput(cleaned, "/");
        if (parsed.kind === "command" || parsed.kind === "unknown-command") {
            if (root.executeAiCommand(parsed))
                Ai.clearDraftIfCurrent();
        } else {
            Ai.sendUserMessage(Ai.expandComposerReferences(parsed.text));
        }
        if (aiPanelLoader.item && typeof aiPanelLoader.item.focusComposer === "function")
            aiPanelLoader.item.focusComposer();
    }

    // Search and sidebar share the parser; commands that need a sidebar host
    // hand off through the same router instead of becoming accidental prompts.
    function executeAiCommand(parsed: var) {
        if (parsed.kind === "unknown-command") {
            Ai.submissionNotice = Translation.tr("Unknown AI command: %1").arg(parsed.name);
            return false;
        }
        const args = parsed.args ?? [];
        switch (parsed.id) {
        case "model":
            Ai.setModel(args.join(" ").trim());
            break;
        case "provider":
            Ai.setProvider(args.join(" ").trim());
            break;
        case "temp":
        case "temperature":
            Ai.setTemperature(Number(args[0] ?? 0.7));
            break;
        case "think":
            Ai.setThinkingLevel(args[0] ?? "medium");
            break;
        case "effort":
            Ai.setResponseMode(args[0] ?? "balanced");
            break;
        case "web":
            Ai.setWebMode(args[0] ?? "auto");
            break;
        case "tools":
            Ai.setFunctionExposure(args[0] ?? "all");
            break;
        case "tool":
            Ai.setTool(args[0] ?? "");
            break;
        case "chats":
            if (aiPanelLoader.item)
                aiPanelLoader.item.historyOpen = true;
            break;
        case "clear":
        case "new":
            Ai.newChat();
            break;
        default:
            Ai.submissionNotice = Translation.tr("/%1 is available in the sidebar.").arg(parsed.name);
            return false;
        }
        return true;
    }

    function setSearchingText(text) {
        searchBar.searchInput.text = text;
        LauncherSearch.query = text;
    }

    // Priority of the result groups, top to bottom, as the user arranged it in
    // Settings. A group the user removed from that list is simply not iterated
    // below, so its results never reach the model — the list is the on/off
    // switch as much as it is the order.
    readonly property bool bestMatchActive: Config.options.search.bestMatch?.enable === true
    readonly property bool bestMatchUniformList: Config.options.search.bestMatch?.uniformList !== false

    // "suggested" only ever holds rows while Search is idle (see
    // LauncherSearch._computeIdleSuggestions) and is otherwise an empty,
    // harmless bucket — but a config saved before that feature existed may
    // still lack the id entirely. Guarantee it is present exactly once rather
    // than relying on every persisted sectionOrder to have been migrated.
    readonly property var sectionOrder: SearchResultSectionRegistry.activeOrder.indexOf("suggested") !== -1
        ? SearchResultSectionRegistry.activeOrder
        : ["suggested"].concat(SearchResultSectionRegistry.activeOrder)

    // Category filtering is a view concern: providers still rank one complete
    // result set, while Tab changes which classes the normal Search exposes.
    // Keeping it here also means utility prefixes and hosted panels retain
    // their existing query semantics.
    property string resultCategoryId: "all"
    readonly property var resultCategoryDefinitions: [
        { id: "all", label: Translation.tr("All"), icon: "category", sections: [] },
        { id: "apps", label: Translation.tr("Apps"), icon: "apps", sections: ["apps"] },
        { id: "controls", label: Translation.tr("Controls"), icon: "tune", sections: ["controls"] },
        { id: "tools", label: Translation.tr("Tools"), icon: "widgets", sections: ["tools", "actions"] },
        { id: "content", label: Translation.tr("Content"), icon: "article", sections: ["quicklinks", "textSnippets", "files", "siteTabs", "siteFavorites", "siteSuggestions"] },
        { id: "media", label: Translation.tr("Media"), icon: "music_note", sections: ["media"] },
        { id: "settings", label: Translation.tr("Settings"), icon: "settings", sections: ["settings"] },
        { id: "other", label: Translation.tr("Other"), icon: "more_horiz", sections: ["other"] }
    ]
    readonly property var availableResultCategories: root.resultCategoryDefinitions.filter(category => {
        if (category.id === "all")
            return true;
        return category.sections.some(sectionId => root.sectionOrder.indexOf(sectionId) !== -1);
    })
    readonly property var activeResultCategory: root.availableResultCategories.find(category => category.id === root.resultCategoryId)
        ?? root.resultCategoryDefinitions[0]
    // Idle Suggestions is already excluded here without a dedicated check:
    // searchingText is "" and alwaysListAppsMode is false in that state, so
    // the length/alwaysListApps condition below never passes.
    readonly property bool showNormalCategoryFilter: !root.isAnySpecialMode
        && !root.queryHasAnyPrefix
        && (root.searchingText.trim().length > 0 || root.alwaysListAppsMode)

    function categoryAcceptsSection(sectionId: string): bool {
        if (root.queryHasAnyPrefix)
            return true;
        const category = root.activeResultCategory;
        return category.id === "all" || category.sections.indexOf(sectionId) !== -1;
    }

    function cycleResultCategory(step: int) {
        const categories = root.availableResultCategories;
        if (categories.length < 2)
            return;
        let index = categories.findIndex(category => category.id === root.activeResultCategory.id);
        if (index < 0)
            index = 0;
        const direction = step < 0 ? -1 : 1;
        index = (index + direction + categories.length) % categories.length;
        root.resultCategoryId = categories[index].id;
        root.loadedResultsCount = root.resultPageSize;
        categoryApplyTimer.restart();
    }

    readonly property var emptyFallbackActions: [
        { id: "command", label: Translation.tr("Run command"), icon: "terminal", enabled: Config.options.search.modules.shellCommand },
        { id: "ai", label: Translation.tr("Ask AI"), icon: "auto_awesome", enabled: Ai.enabled },
        { id: "web", label: Translation.tr("Search the web"), icon: "travel_explore", enabled: Config.options.search.modules.webSearch }
    ].filter(action => action.enabled)
    readonly property int matchingCategoryResultCount: LauncherSearch.results.filter(item => {
        if (!item)
            return false;
        const sectionId = root.resultSectionId(item);
        return sectionId !== "continue" && root.categoryAcceptsSection(sectionId);
    }).length
    readonly property bool showContinuationRows: root.resultCategoryId === "all"
        && !root.queryHasAnyPrefix
        && root.realResultCount > 0
    readonly property bool showEmptySearchState: root.showNormalCategoryFilter
        && !root.queryHasAnyPrefix
        && root.searchingText.trim().length > 0
        && root.matchingCategoryResultCount === 0

    function executeEmptyFallback(actionId: string) {
        const query = root.searchingText.trim();
        if (query.length === 0)
            return;
        if (actionId === "command") {
            GlobalStates.overviewOpen = false;
            LauncherSearch.runCommandQuery(query);
        } else if (actionId === "web") {
            GlobalStates.overviewOpen = false;
            LauncherSearch.openWebSearch(query);
        } else if (actionId === "ai") {
            LauncherSearch.askAiQuery(query);
        }
    }

    function resultSectionId(item): string {
        const key = String(item?.key ?? "");
        // Idle-only frecency strip (see LauncherSearch._computeIdleSuggestions).
        // Checked first: it wraps another row's own key, e.g. "suggested:app:x".
        if (key.startsWith("suggested:"))
            return "suggested";
        if (item?.isFallback === true)
            return "continue";
        if (item?.isAlias === true)
            return "aliases";
        if (key.startsWith("app:"))
            return "apps";
        if (key.startsWith("site:")) {
            if (item?.siteSource === "open")
                return "siteTabs";
            return item?.siteSource === "favorite" ? "siteFavorites" : "siteSuggestions";
        }
        // The idle now-playing bubble is the only media row, and it used to land
        // in "More results" — a caption that says nothing about it.
        if (key.startsWith("mpris:"))
            return "media";
        if (/^(setting:|panel:settings$|shortcut:openSettings$)/.test(key))
            return "settings";
        if (/^(qtoggle:|bluetooth-device:|sys:|mode:)/.test(key))
            return "controls";
        if (/^(panel:|keybind:|cheatsheet:|shortcut:)/.test(key))
            return "tools";
        if (key.startsWith("tool:") || key.startsWith("win:"))
            return "tools";
        // Files and folders are their own class of result, not "links & text":
        // they are the one group whose rows are a location on disk.
        if (/^(file:|fsearch:)/.test(key))
            return "files";
        if (key.startsWith("quicklink:"))
            return "quicklinks";
        if (key.startsWith("text-snippet:"))
            return "textSnippets";
        if (key.startsWith("math:"))
            return "tools";
        if (/^(cmd:shell|web:search|ai:ask|fallback:)/.test(key))
            return "continue";
        if (/^(action:|snippet:|shell:|process:|generator:|sports:)/.test(key))
            return "actions";
        return "other";
    }

    function sectionPresentation(sectionId: string): var {
        const section = SearchResultSectionRegistry.getComponent(sectionId);
        if (section)
            return { label: section.title, icon: section.icon };
        return { label: Translation.tr("More results"), icon: "search" };
    }

    /**
     * Flattens the ranked results into the row list the ListView consumes.
     *
     * Section captions are emitted as rows of their own instead of relying on
     * `ListView.section`. Qt positions section delegates outside the view's
     * add/move/displaced transitions, so every reorder left the captions
     * snapping to their final spot while the rows around them were still
     * travelling — the overlapping headers and doubled rows.
     *
     * Rows reference the original result object instead of a per-keystroke
     * `Object.assign` copy, so the diff below can compare identities and skip
     * rewriting roles that did not actually change.
     */
    function organizeResults(results, limit) {
        const query = root.searchingText.trim();
        const maxItems = limit > 0 ? limit : results.length;

        const seenKeys = new Set();
        const unique = [];
        const sectionIds = [];
        let hasApplications = false;

        for (let i = 0; i < results.length; i++) {
            const item = results[i];
            if (!item)
                continue;
            const key = String(item.key ?? "");
            if (key.length > 0) {
                if (seenKeys.has(key))
                    continue;
                seenKeys.add(key);
            }
            const sectionId = root.resultSectionId(item);
            // Generic continuations are rendered by the intentional empty
            // state. Explicit command/web/math prefixes still keep their
            // single result row and exact Enter behavior.
            if (sectionId === "continue" && !root.queryHasAnyPrefix && !root.showContinuationRows)
                continue;
            if (!root.categoryAcceptsSection(sectionId))
                continue;
            if (sectionId === "apps")
                hasApplications = true;
            unique.push(item);
            sectionIds.push(sectionId);
        }

        // Applications are always the strongest result class. Only promote a
        // command surface when no application matches, and never promote
        // Settings: configuration discovery is useful, but intentionally
        // secondary to things the user can launch or act on immediately.
        if (root.resultCategoryId === "all" && !hasApplications && query.length >= 2 && root.sectionOrder.indexOf("best") !== -1) {
            let bestIndex = -1;
            for (let i = 0; i < unique.length; i++) {
                const key = String(unique[i].key ?? "");
                if (key.startsWith("panel:") && key !== "panel:settings") {
                    bestIndex = i;
                    break;
                }
            }
            if (bestIndex !== -1)
                sectionIds[bestIndex] = "best";
        }

        const buckets = ({});
        for (let i = 0; i < unique.length; i++) {
            const bucket = buckets[sectionIds[i]];
            if (bucket)
                bucket.push(unique[i]);
            else
                buckets[sectionIds[i]] = [unique[i]];
        }

        // How many rows each section contributes is decided before any of them
        // are laid out, so the page budget is shared rather than consumed
        // front to back. Filling it in order let one broad section swallow the
        // page — a three-letter query matches enough applications to push Files
        // and Controls out of the list entirely, even though they matched.
        //
        // Pass one gives every section its opening few rows; pass two hands the
        // leftover budget to whoever still has more, in section order. Paging
        // then extends the same split as the user scrolls.
        const takes = ({});
        let remaining = maxItems;
        for (let pass = 0; pass < 2 && remaining > 0; pass++) {
            for (let s = 0; s < root.sectionOrder.length && remaining > 0; s++) {
                const sectionId = root.sectionOrder[s];
                const items = buckets[sectionId];
                if (!items || items.length === 0)
                    continue;
                const already = takes[sectionId] ?? 0;
                const ceiling = pass === 0 ? Math.min(items.length, root.sectionPageLimit) : items.length;
                const take = Math.min(ceiling - already, remaining);
                if (take <= 0)
                    continue;
                takes[sectionId] = already + take;
                remaining -= take;
            }
        }

        // A caption tells one group apart from the next. When there is only one
        // group it names nothing, and costs 30px plus a line to read at the top
        // of every short query.
        let groupCount = 0;
        for (let s = 0; s < root.sectionOrder.length; s++) {
            if ((takes[root.sectionOrder[s]] ?? 0) > 0)
                groupCount++;
        }
        // Best-match mode answers the question the captions were organising an
        // answer to, so the rest reads better as one uninterrupted list.
        const heroActive = root.bestMatchActive && query.length > 0;
        const showCaptions = root.resultCategoryId === "all" && groupCount > 1
            && !(heroActive && root.bestMatchUniformList);

        const rows = [];
        for (let s = 0; s < root.sectionOrder.length; s++) {
            const sectionId = root.sectionOrder[s];
            const take = takes[sectionId] ?? 0;
            if (take <= 0)
                continue;
            const items = buckets[sectionId];
            if (showCaptions)
                rows.push({
                    key: "section:" + sectionId,
                    sectionId: sectionId,
                    isHeader: true,
                    isHero: false,
                    isFirst: rows.length === 0,
                    isLast: false,
                    ref: null
                });
            for (let i = 0; i < take; i++) {
                const item = items[i];
                rows.push({
                    key: String(item.key ?? (sectionId + ":" + i)),
                    sectionId: sectionId,
                    isHeader: false,
                    isHero: false,
                    isFirst: i === 0,
                    isLast: i === take - 1,
                    ref: item
                });
            }
        }

        // The prominent row is whichever result the cursor would have landed on
        // anyway, so what Enter does and what the row shows can never disagree.
        if (heroActive) {
            for (let i = 0; i < rows.length; i++) {
                if (rows[i].isHeader)
                    continue;
                rows[i].isHero = true;
                // It stands alone, so the row under it starts the next group.
                rows[i].isLast = true;
                if (i + 1 < rows.length && !rows[i + 1].isHeader)
                    rows[i + 1].isFirst = true;
                break;
            }
        }
        return rows;
    }

    function processResults(results) {
        const q = LauncherSearch.query.trim().toLowerCase();
        const showNowPlaying = Config.options.search.nowPlaying?.enable ?? Config.options.search.showNowPlayingBubble;
        const excludeMpris = Config.options.search.alwaysListApps || q !== "" || !showNowPlaying;
        const filtered = [];
        for (let i = 0; i < results.length; i++) {
            const item = results[i];
            if (item && (!excludeMpris || item.key !== "mpris:now-playing"))
                filtered.push(item);
        }
        return root.organizeResults(filtered, root.loadedResultsCount);
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_J && (event.modifiers & Qt.ControlModifier) && root.isAiMode) {
            root.continueInSidebar();
            event.accepted = true;
            return;
        }
        if (event.key === Qt.Key_K && (event.modifiers & Qt.ControlModifier)) {
            if (root.isAiMode) {
                // The app result list is hidden while AI owns the surface;
                // never toggle an action panel the user cannot see.
                root.focusSearchInput();
                event.accepted = true;
                return;
            }
            if (appResults.visible) {
                root.requestToggleActions();
                event.accepted = true;
            }
            return;
        }

        // ESC first leaves any child panel. Plain Search lets it propagate so
        // Overview can close on the next press.
        if (event.key === Qt.Key_Escape) {
            if (root.handleEscape()) {
                event.accepted = true;
            }
            return;
        }

        // TAB / Backtab: route navigation inside AI panel when in AI mode
        if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
            if (root.isAiMode) {
                if (aiPanelLoader.item) {
                    if (event.key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier))
                        aiPanelLoader.item.focusPrev();
                    else
                        aiPanelLoader.item.focusNext();
                }
                event.accepted = true;
                return;
            }
            if (root.showNormalCategoryFilter) {
                root.cycleResultCategory(event.key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier) ? -1 : 1);
                event.accepted = true;
                return;
            }
        }

        // Handle Backspace: focus and delete character if not focused
        if (event.key === Qt.Key_Backspace) {
            if (root.activePanelOwnsInput)
                return;
            if (root.isAiMode) {
                root.focusSearchInput();
                return;
            }
            if (root.isAnySpecialMode && root.activePanelQuery.trim().length === 0) {
                root.handlePanelBackspace();
                event.accepted = true;
                return;
            }
            if (!searchBar.searchInput.activeFocus) {
                root.focusSearchInput();
                if (event.modifiers & Qt.ControlModifier) {
                    // Delete word before cursor
                    let text = searchBar.searchInput.text;
                    let pos = searchBar.searchInput.cursorPosition;
                    if (pos > 0) {
                        // Find the start of the previous word
                        let left = text.slice(0, pos);
                        let match = left.match(/(\s*\S+)\s*$/);
                        let deleteLen = match ? match[0].length : 1;
                        searchBar.searchInput.text = text.slice(0, pos - deleteLen) + text.slice(pos);
                        searchBar.searchInput.cursorPosition = pos - deleteLen;
                    }
                } else {
                    // Delete character before cursor if any
                    if (searchBar.searchInput.cursorPosition > 0) {
                        searchBar.searchInput.text = searchBar.searchInput.text.slice(0, searchBar.searchInput.cursorPosition - 1) + searchBar.searchInput.text.slice(searchBar.searchInput.cursorPosition);
                        searchBar.searchInput.cursorPosition -= 1;
                    }
                }
                // Always move cursor to end after programmatic edit
                searchBar.searchInput.cursorPosition = searchBar.searchInput.text.length;
                event.accepted = true;
            }
            // If already focused, let TextField handle it
            return;
        }

        // Only handle visible printable characters (ignore control chars, arrows, etc.)
        if (event.text && event.text.length === 1 && event.key !== Qt.Key_Enter && event.key !== Qt.Key_Return && event.key !== Qt.Key_Delete && event.key !== Qt.Key_Tab && event.key !== Qt.Key_Backtab && event.text.charCodeAt(0) >= 0x20)
        {
            if (root.activePanelOwnsInput)
                return;
            if (root.isAiMode) {
                root.focusSearchInput();
                const input = searchBar.searchInput;
                const position = input.cursorPosition;
                input.text = input.text.slice(0, position) + event.text + input.text.slice(position);
                input.cursorPosition = position + event.text.length;
                event.accepted = true;
                return;
            }
            if (!searchBar.searchInput.activeFocus) {
                root.focusSearchInput();
                // Insert the character at the cursor position
                searchBar.searchInput.text = searchBar.searchInput.text.slice(0, searchBar.searchInput.cursorPosition) + event.text + searchBar.searchInput.text.slice(searchBar.searchInput.cursorPosition);
                searchBar.searchInput.cursorPosition += 1;
                event.accepted = true;
                root.focusFirstItem();
            }
        }
    }

    property real shadowOpacity: 1.0

    StyledRectangularShadow {
        target: searchWidgetContent
        visible: !GlobalStates.searchConnectActive && !Config.options.appearance.transparency.popups && !Config.options.appearance.transparency.enable
        opacity: root.shadowOpacity
        offset: Qt.vector2d(0.0, 0.0)
    }
    Rectangle {
        id: searchWidgetContent
        // Centered vertically like every other mode — the AI panel is just
        // another panel below the search bar, same as clipboard/translator.
        anchors.centerIn: parent
        width: GlobalStates.searchConnectActive ? parent.width : (root.exiting ? root.exitWidth : implicitWidth)
        height: GlobalStates.searchConnectActive ? parent.height : (root.exiting ? root.exitHeight : implicitHeight)
        clip: true
        // An antialiased rounded clip costs a render target recreated on every
        // frame of the height animation. Result rows are inset by
        // `rowSideMargin` and rounded themselves, so they never reach the
        // container's corners — only the hosted panels, which draw to their own
        // edges, actually need the mask.
        layer.enabled: !GlobalStates.searchConnectActive
            && (root.activePanelUsesHost || root.isAiMode)
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: searchWidgetContent.width
                height: searchWidgetContent.height
                radius: searchWidgetContent.radius
            }
        }

        MouseArea {
            anchors.fill: parent
            // Absorb clicks inside search widget so they do not hit the full-screen dismiss MouseArea
            onClicked: {}
        }
        implicitWidth: {
            let baseW = 0;
            if (root.activePanel)
                baseW = root.activePanel.width() + (root.activePanelUsesHost ? root.hostedPanelSideMargin * 2 : 0);
            else
                baseW = Math.max(Config.options.search.baseWidth, gridLayout.implicitWidth);

            // In notch mode, the DI container already provides horizontal spacing.
            // Only add the 48px offset in non-notch connect mode.
            if (GlobalStates.searchConnectActive && !root.inNotchMode)
                baseW += 48;
            return Math.min(baseW, root.maximumSurfaceWidth);
        }
        implicitHeight: {
            let bottomMargin = GlobalStates.searchConnectActive ? 16 : 10;
            let desiredHeight = 0;
            if (root.activePanel)
                desiredHeight = (root.activePanelItem?.implicitHeight ?? 520) + (root.isAiMode ? 16 : searchBar.height + searchBar.verticalPadding * 2 + bottomMargin);
            else
                desiredHeight = gridLayout.implicitHeight;
            return Math.min(desiredHeight, root.maximumSurfaceHeight);
        }
        // The collapsed field needs a pill; expanded content must use the same
        // corner as the other shell windows. Switching on `showResults` flipped
        // the corner the instant the flag changed, so a still-tall panel wore the
        // collapsed pill radius for the whole height animation — the fat-corner
        // frame visible mid-collapse.
        //
        // Deriving it from the live (already animated) height instead keeps the
        // two in step in both directions, with no second animation to sync.
        readonly property real collapsedHeight: searchBar.implicitHeight + searchBar.verticalPadding * 2
        readonly property real cornerBlendDistance: 72
        radius: {
            const pill = Appearance.rounding.verylarge;
            const panel = Appearance.rounding.windowRounding;
            if (pill === panel)
                return pill;
            const grown = searchWidgetContent.height - searchWidgetContent.collapsedHeight;
            const t = Math.max(0, Math.min(1, grown / searchWidgetContent.cornerBlendDistance));
            return pill + (panel - pill) * t;
        }
        // The appearance setting is for every panel routed from Search. Some
        // older registry entries opted out individually, making the control
        // look broken for common prefixes such as Clipboard and Translator.
        color: GlobalStates.searchConnectActive ? "transparent"
             : Appearance.colors.colBackgroundSurfaceContainer

        Behavior on color {
            ColorAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }

        Behavior on implicitWidth {
            id: searchWidthBehavior
            // In notch mode, DI pill drives sizing — disable internal animation to avoid double-animation
            enabled: !root.inNotchMode
            NumberAnimation {
                id: widthAnim
                duration: Appearance.animation.elementMoveSmall.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
            }
        }

        Behavior on implicitHeight {
            id: searchHeightBehavior
            // In notch mode, DI pill drives sizing — disable internal animation to avoid double-animation
            enabled: !root.inNotchMode
            NumberAnimation {
                id: heightAnim
                duration: Appearance.animation.elementMoveSmall.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
            }
        }

        GridLayout {
            id: gridLayout
            anchors.left: parent.left
            anchors.right: parent.right
            // In notch mode the DI container provides spacing — adding margins here would double-pad
            anchors.leftMargin: (GlobalStates.searchConnectActive && !root.inNotchMode) ? 24 : 0
            anchors.rightMargin: (GlobalStates.searchConnectActive && !root.inNotchMode) ? 24 : 0
            anchors.top: parent.top
            columns: 1
            rowSpacing: 0
            clip: true

            SearchBar {
                id: searchBar
                property real verticalPadding: 4
                Layout.fillWidth: true
                Layout.preferredHeight: root.isAiMode ? 0 : implicitHeight
                Layout.minimumHeight: 0
                Layout.leftMargin: 10
                Layout.rightMargin: 10
                Layout.topMargin: root.isAiMode ? 0 : verticalPadding
                Layout.bottomMargin: root.isAiMode ? 0 : verticalPadding
                Layout.row: root.overviewPosition == "bottom" ? 1 : 0
                visible: !root.isAiMode
                animateWidth: true
                aiModeActive: root.isAiMode
                Binding {
                    target: searchBar
                    property: "searchingText"
                    value: root.searchingText
                }

                clipboardMode: root.isClipboardMode || root.isBluetoothMode || root.isTranslatorMode || root.isMediaDownloaderMode || root.isMaterialSymbolsMode
                activePanelMode: root.isAnySpecialMode
                activePanel: root.activePanel
                activePanelOwnsInput: root.activePanelOwnsInput
                activePanelQueryEmpty: root.activePanelQuery.trim().length === 0
                supportsPanelSectionToggle: root.activePanelItem?.supportsSectionToggle === true
                clipboardWidth: 830
                currentResultIndex: appResults.currentIndex
                selectedResultRef: LauncherSearch.selectedResult
                isTranslatorPanelFocused: root.isTranslatorMode && root.activePanelItem && root.activePanelItem.focusedControlIndex !== -1
                isMediaDownloaderPanelFocused: root.isMediaDownloaderMode && root.activePanelItem && root.activePanelItem.focusedControlIndex !== -1
                isMaterialSymbolsPanelFocused: root.isMaterialSymbolsMode && root.activePanelItem && root.activePanelItem.focusedControlIndex !== -1
                showSuggestionsPanel: root.showSuggestionsPanel
                showCategoryFilter: root.showNormalCategoryFilter
                categoryFilterLabel: root.activeResultCategory.label
                categoryFilterIcon: root.activeResultCategory.icon
                enabled: !root.isAiMode
                opacity: root.isAiMode ? 0 : 1

                Behavior on opacity {
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Appearance.animation.elementMoveFast.type
                        easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                    }
                }

                Behavior on Layout.preferredHeight {
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveSmall.duration
                        easing.type: Appearance.animation.elementMoveSmall.type
                        easing.bezierCurve: Appearance.animation.elementMoveSmall.bezierCurve
                    }
                }

                onCtrlKPressed: {
                    if (root.activePanelItem) {
                        searchKeyRouter.dispatch("toggleActions");
                    } else if (appResults.visible) {
                        root.requestToggleActions();
                    }
                }

                onBackspaceOnEmpty: root.handlePanelBackspace()
                onPanelShortcut: methodName => searchKeyRouter.dispatch(methodName)

                onTogglePanelSection: {
                    searchKeyRouter.dispatch("toggleSection");
                }

                onCopySelected: {
                    searchKeyRouter.dispatch("copySelected");
                }

                onOpenSelectedInCheatsheet: {
                    if (!searchKeyRouter.dispatch("secondaryActivateSelected"))
                        searchKeyRouter.dispatch("openSelectedInCheatsheet");
                }

                onSaveSelected: searchKeyRouter.dispatch("saveSelected")
                onEditSelected: searchKeyRouter.dispatch("editSelected")
                onOcrSelected: searchKeyRouter.dispatch("ocrSelected")
                onCopyDispatchSelected: searchKeyRouter.dispatch("copyDispatchSelected")
                onCreateFromQuery: searchKeyRouter.dispatch("createFromQuery")
                onHistoryPrevious: root.selectSearchHistory(1)
                onHistoryNext: root.selectSearchHistory(-1)
                onToggleFavorite: {
                    LauncherSearch.toggleFavorite(LauncherSearch.selectedResult);
                }
                onCycleCategoryFilter: step => root.cycleResultCategory(step)

                onEscapeToSearch: {
                    root.handleEscape();
                }

                onSendMessage: {
                    if (root.isAiMode)
                        root.sendAiMessage();
                }

                onRunSecondaryAction: index => {
                    const row = root.selectedResultRow();
                    if (row && typeof row.runSecondary === "function")
                        row.runSecondary(index);
                }

                onNavigateSectionUp: searchKeyRouter.dispatch("sectionPrevious")
                onNavigateSectionDown: searchKeyRouter.dispatch("sectionNext")

                onNavigateUp: searchKeyRouter.dispatch("navigateUp")
                onNavigateDown: searchKeyRouter.dispatch("navigateDown")

                onNavigateLeft: {
                    if (root.activePanelItem)
                        searchKeyRouter.dispatch("navigateLeft");
                    else if (root.selectedResultHandlesHorizontalNavigation)
                        searchKeyRouter.dispatch("navigateLeft");
                }

                onNavigateRight: {
                    if (root.activePanelItem)
                        searchKeyRouter.dispatch("navigateRight");
                    else if (root.selectedResultHandlesHorizontalNavigation)
                        searchKeyRouter.dispatch("navigateRight");
                }

                onActivate: searchKeyRouter.dispatch("activateSelected")

                onDeleteSelected: {
                    if (root.activePanelItem && typeof root.activePanelItem.deleteSelected === "function")
                        root.activePanelItem.deleteSelected();
                }
            }

            Item {
                id: searchResultsSurface

                // A GridLayout cell may only have one direct child. The
                // regular results and the registry-backed panels alternate
                // inside this surface instead of competing for that cell.
                readonly property bool registeredPanelActive: root.activePanelUsesHost
                Layout.fillWidth: true
                implicitHeight: registeredPanelActive
                    ? Math.min(registeredPanelHostLoader.item?.implicitHeight ?? 0, root.activePanelHeightBudget)
                    : (root.isAiMode
                        ? (aiPanelLoader.item?.implicitHeight ?? 520) + Appearance.sizes.elevationMargin * 2
                        : appResultsSurface.implicitHeight)
                height: implicitHeight
                Layout.row: root.overviewPosition == "bottom" ? 0 : 1

                Item {
                    id: appResultsSurface
                    anchors.fill: parent

                // Use opacity-driven visibility so results fade out before collapsing on close
                readonly property bool resultsActive: root.showResults && !root.isAnySpecialMode
                opacity: resultsActive ? 1.0 : 0.0
                visible: opacity > 0.01
                implicitHeight: !resultsActive
                    ? 0
                    : (root.showSkeletons
                        ? searchSkeletons.implicitHeight + (GlobalStates.searchConnectActive ? 12 : 16)
                        : (root.showEmptySearchState
                            ? emptySearchState.implicitHeight
                            // View margins decorate actual rows; they are not
                            // content and must not grow an empty search surface.
                            : appResults.measuredContentExtent))

                Behavior on opacity {
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                    }
                }

                // Deliberately not animated. This height feeds the container's own
                // height Behavior, and animating both put two eased curves in
                // series: the content slid while the frame grew, which is the
                // mushy, laggy expansion. The container animates; the content is
                // simply revealed by it.

                ListView {
                    id: appResults
                    anchors.fill: parent
                    visible: opacity > 0 && !root.showEmptySearchState
                    opacity: root.showSkeletons || root.showEmptySearchState ? 0.0 : 1.0
                    Behavior on opacity {
                        enabled: !root.inNotchMode
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveFast.duration
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Appearance.animationCurves.expressiveEffects
                        }
                    }
                    clip: true
                    topMargin: 0
                    // Matches the rows' own side inset: the gap under the last row
                    // and the gap beside every row are the same edge of the panel,
                    // and they were 6 against 10. Connect mode keeps its own value —
                    // there the grid adds 24px gutters on top of the row inset, so
                    // the two gaps are not the same relationship to begin with.
                    bottomMargin: (GlobalStates.searchConnectActive ? 12 : root.rowSideMargin)
                        + (root.actionFeedbackText.length > 0 ? actionFeedbackBar.height + Appearance.sizes.elevationMargin / 2 : 0)
                    spacing: 2
                    // contentHeight is calculated by a view whose viewport is
                    // this surface's height. Binding the surface straight back
                    // to it creates a circular dependency in Qt. Snapshot the
                    // extent only when the view reports a real content change.
                    property real measuredContentExtent: 0
                    function updateMeasuredContentExtent() {
                        const nextExtent = appResults.count === 0 || appResults.contentHeight <= 0
                            ? 0
                            : Math.min(root.maxResultsHeight,
                                appResults.contentHeight + appResults.topMargin + appResults.bottomMargin);
                        if (Math.abs(appResults.measuredContentExtent - nextExtent) > 0.5)
                            appResults.measuredContentExtent = nextExtent;
                    }
                    Timer {
                        id: resultsExtentSyncTimer
                        interval: 0
                        repeat: false
                        onTriggered: appResults.updateMeasuredContentExtent()
                    }
                    onContentHeightChanged: resultsExtentSyncTimer.restart()
                    onCountChanged: resultsExtentSyncTimer.restart()
                    onTopMarginChanged: resultsExtentSyncTimer.restart()
                    onBottomMarginChanged: resultsExtentSyncTimer.restart()
                    KeyNavigation.up: searchBar
                    highlightMoveDuration: 100
                    // The cascade is a reveal gesture for a list that just appeared.
                    // Replaying it per keystroke made the seventh row wait half a
                    // second to paint, which is the whole "it feels slow" report.
                    property bool staggerReveal: false
                    readonly property int staggerStep: 22

                    Timer {
                        id: staggerRevealWindow
                        interval: 320
                        repeat: false
                        onTriggered: appResults.staggerReveal = false
                    }

                    // Rows are selectable results only; section captions live
                    // in the model and are skipped by keyboard navigation.
                    function isHeaderRow(rowIndex: int): bool {
                        if (rowIndex < 0 || rowIndex >= resultModel.count)
                            return true;
                        return resultModel.get(rowIndex).isHeader === true;
                    }

                    function selectableIndex(from: int, step: int): int {
                        for (let i = from; i >= 0 && i < resultModel.count; i += step) {
                            if (!appResults.isHeaderRow(i))
                                return i;
                        }
                        return -1;
                    }

                    function selectFirst() {
                        const target = appResults.selectableIndex(0, 1);
                        appResults.currentIndex = target;
                    }

                    /**
                     * Move the cursor to the first row of the next or previous
                     * group. With four groups on screen, reaching the last one
                     * a row at a time costs ten keystrokes.
                     */
                    function sectionJump(step: int): bool {
                        if (resultModel.count === 0)
                            return false;
                        const from = Math.max(0, appResults.currentIndex);
                        const current = String(resultModel.get(from)?.sectionId ?? "");
                        for (let i = from + step; i >= 0 && i < resultModel.count; i += step) {
                            const row = resultModel.get(i);
                            if (row.isHeader === true || String(row.sectionId) === current)
                                continue;
                            // Going up lands on the *first* row of that group,
                            // not the last one the scan happened to reach.
                            const target = step < 0 ? appResults.sectionStart(i) : i;
                            appResults.currentIndex = target;
                            return true;
                        }
                        return false;
                    }

                    function sectionStart(rowIndex: int): int {
                        const sectionId = String(resultModel.get(rowIndex)?.sectionId ?? "");
                        let start = rowIndex;
                        while (start > 0) {
                            const previous = resultModel.get(start - 1);
                            if (previous.isHeader === true || String(previous.sectionId) !== sectionId)
                                break;
                            start--;
                        }
                        return start;
                    }

                    function moveSelection(step: int): bool {
                        const target = appResults.selectableIndex(appResults.currentIndex + step, step);
                        if (target === -1)
                            return false;
                        appResults.currentIndex = target;
                        return true;
                    }

                    // An offscreen render target plus a shader pass on every frame of
                    // every resize is not worth paying for a list that fits: the fade
                    // only means anything while there is something to scroll to. The
                    // test is stated against the fixed cap rather than the list's own
                    // height, which is itself derived from contentHeight — comparing
                    // the two made the layer flicker on and off around the boundary.
                    layer.enabled: appResults.count > 0
                        && appResults.contentHeight + appResults.topMargin + appResults.bottomMargin > root.maxResultsHeight
                    layer.effect: OpacityMask {
                        maskSource: Item {
                            id: maskRoot
                            width: appResults.width
                            height: appResults.height

                            property color topFadeColor: {
                                if (appResults.currentItem) {
                                    const visY = appResults.currentItem.y - appResults.contentY;
                                    if (visY <= appResults.topMargin + 36)
                                        return "white";
                                }
                                return appResults.atYBeginning ? "white" : "transparent";
                            }
                            property color bottomFadeColor: {
                                if (appResults.currentItem) {
                                    const visBottom = appResults.currentItem.y - appResults.contentY + appResults.currentItem.height;
                                    if (visBottom >= appResults.height - appResults.bottomMargin - 36)
                                        return "white";
                                }
                                return appResults.atYEnd ? "white" : "transparent";
                            }

                            Behavior on topFadeColor {
                                enabled: !root.inNotchMode
                                ColorAnimation {
                                    duration: Appearance.animation.elementMoveFast.duration
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                                }
                            }
                            Behavior on bottomFadeColor {
                                enabled: !root.inNotchMode
                                ColorAnimation {
                                    duration: Appearance.animation.elementMoveFast.duration
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                                }
                            }

                            Column {
                                anchors.fill: parent
                                spacing: 0

                                Rectangle {
                                    width: parent.width
                                    height: Math.min(46, parent.height / 2)
                                    color: "transparent"
                                    gradient: Gradient {
                                        GradientStop {
                                            position: 0.0
                                            color: maskRoot.topFadeColor
                                        }
                                        GradientStop {
                                            position: 1.0
                                            color: "white"
                                        }
                                    }
                                }

                                Rectangle {
                                    width: parent.width
                                    height: Math.max(0, parent.height - Math.min(46, parent.height / 2) - Math.min(56, parent.height / 2))
                                    color: "white"
                                }

                                Rectangle {
                                    width: parent.width
                                    height: Math.min(56, parent.height / 2)
                                    color: "transparent"
                                    gradient: Gradient {
                                        GradientStop {
                                            position: 0.0
                                            color: "white"
                                        }
                                        GradientStop {
                                            position: 1.0
                                            color: maskRoot.bottomFadeColor
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Touchpad and mouse scroll physics adjustments
                    property real scrollTargetY: 0
                    property real touchpadScrollFactor: Config?.options.interactions.scrolling.touchpadScrollFactor ?? 100
                    property real mouseScrollFactor: Config?.options.interactions.scrolling.mouseScrollFactor ?? 50
                    property real mouseScrollDeltaThreshold: Config?.options.interactions.scrolling.mouseScrollDeltaThreshold ?? 120

                    maximumFlickVelocity: 3500

                    MouseArea {
                        z: 99
                        visible: Config?.options.interactions.scrolling.fasterTouchpadScroll
                        anchors.fill: parent
                        acceptedButtons: Qt.NoButton
                        onWheel: function (wheelEvent) {
                            const delta = wheelEvent.angleDelta.y / appResults.mouseScrollDeltaThreshold;
                            var scrollFactor = Math.abs(wheelEvent.angleDelta.y) >= appResults.mouseScrollDeltaThreshold ? appResults.mouseScrollFactor : appResults.touchpadScrollFactor;

                            const maxY = Math.max(0, appResults.contentHeight - appResults.height);
                            const base = scrollAnim.running ? appResults.scrollTargetY : appResults.contentY;
                            var targetY = Math.max(0, Math.min(base - delta * scrollFactor, maxY));

                            appResults.scrollTargetY = targetY;
                            appResults.contentY = targetY;
                            wheelEvent.accepted = true;
                        }
                    }

                    Behavior on contentY {
                        // No alwaysRunToEnd: contentY is a Flickable's own
                        // property, and refusing to be interrupted made the
                        // animation fight both the native flick and the clamp
                        // that happens every time a diff shrinks contentHeight.
                        NumberAnimation {
                            id: scrollAnim
                            duration: Appearance.animation.scroll.duration
                            easing.type: Appearance.animation.scroll.type
                            easing.bezierCurve: Appearance.animation.scroll.bezierCurve
                        }
                    }

                    onContentYChanged: {
                        if (contentHeight > 0 && contentY + height > contentHeight - 150) {
                            root.loadMoreResults();
                        }
                        if (!scrollAnim.running) {
                            appResults.scrollTargetY = appResults.contentY;
                        }
                    }

                    onCurrentIndexChanged: {
                        // A diff can slide a caption under the cursor. Step off it
                        // in the direction the list grew rather than selecting a
                        // row that cannot be activated.
                        if (currentIndex >= 0 && appResults.isHeaderRow(currentIndex) && resultModel.count > 0) {
                            const recovered = appResults.selectableIndex(currentIndex, 1);
                            appResults.currentIndex = recovered !== -1 ? recovered : appResults.selectableIndex(currentIndex, -1);
                            return;
                        }
                        const selected = currentIndex >= 0 && currentIndex < resultModel.count
                            ? resultModel.get(currentIndex)?.modelRef ?? null
                            : null;
                        LauncherSearch.selectedResult = selected;
                        root.refreshSelectedResultNavigation();
                        if (currentIndex >= count - 5)
                            root.loadMoreResults();
                    }

                    // ── Diff-based model update: drives the move/add/remove transitions ──
                    // `rows` come from organizeResults(): section captions and result
                    // rows in one flat list, each already carrying its grouping flags.
                    // Every insert/remove/move below makes the view re-emit
                    // contentY and currentIndex, and those handlers can ask for
                    // another page. Re-entering here would restart the diff against
                    // a `currentKeys` mirror that the outer pass is still editing,
                    // and rows the outer pass had not reached yet would survive.
                    property bool applyingDiff: false

                    function applyResultDiff(rows) {
                        if (appResults.applyingDiff)
                            return;
                        appResults.applyingDiff = true;
                        try {
                            appResults.applyResultDiffUnguarded(rows);
                        } finally {
                            appResults.applyingDiff = false;
                        }
                    }

                    /**
                     * The result object written into each model row, mirrored
                     * on the JS side.
                     *
                     * `dynamicRoles` does not round-trip object identity: two
                     * reads of one slot hand back two different wrappers of the
                     * same object, so comparing `get(i).modelRef` against the
                     * incoming ref was always unequal and every row was rewritten
                     * on every pass. Comparing against what was actually written
                     * is the only reliable test.
                     */
                    property var rowRefs: []

                    function applyResultDiffUnguarded(rows) {
                        if (rows.length === 0) {
                            if (resultModel.count > 0)
                                resultModel.clear();
                            appResults.rowRefs = [];
                            return;
                        }

                        if (resultModel.count === 0) {
                            appResults.staggerReveal = true;
                            staggerRevealWindow.restart();
                        }

                        const currentKeys = [];
                        for (let i = 0; i < resultModel.count; i++)
                            currentKeys.push(resultModel.get(i).key);

                        // Anything that emptied or resized the model behind this
                        // mirror makes it untrustworthy; a fresh one of nulls
                        // simply treats every row as changed.
                        let currentRefs = appResults.rowRefs.length === currentKeys.length
                            ? appResults.rowRefs.slice()
                            : currentKeys.map(() => null);

                        const newKeySet = new Set();
                        for (let i = 0; i < rows.length; i++)
                            newKeySet.add(rows[i].key);

                        // Remove stale rows from the end so model indexes stay valid.
                        for (let i = currentKeys.length - 1; i >= 0; i--) {
                            if (!newKeySet.has(currentKeys[i])) {
                                resultModel.remove(i);
                                currentKeys.splice(i, 1);
                                currentRefs.splice(i, 1);
                            }
                        }

                        // Move/insert each desired row once. The old implementation
                        // rebuilt a full index map after every operation.
                        for (let newIndex = 0; newIndex < rows.length; newIndex++) {
                            const rowData = rows[newIndex];
                            const currentIndex = currentKeys.indexOf(rowData.key);

                            if (currentIndex === -1) {
                                resultModel.insert(newIndex, {
                                    key: rowData.key,
                                    sectionId: rowData.sectionId,
                                    isHeader: rowData.isHeader,
                                    isHero: rowData.isHero,
                                    isFirst: rowData.isFirst,
                                    isLast: rowData.isLast,
                                    modelRef: rowData.ref
                                });
                                currentKeys.splice(newIndex, 0, rowData.key);
                                currentRefs.splice(newIndex, 0, rowData.ref);
                                continue;
                            }

                            if (currentIndex !== newIndex) {
                                resultModel.move(currentIndex, newIndex, 1);
                                const movedKey = currentKeys.splice(currentIndex, 1)[0];
                                currentKeys.splice(newIndex, 0, movedKey);
                                const movedRef = currentRefs.splice(currentIndex, 1)[0];
                                currentRefs.splice(newIndex, 0, movedRef);
                            }

                            // Rows reference the original result object, so an
                            // unchanged row costs zero setProperty calls — and zero
                            // delegate rebinds — even when it moved.
                            const row = resultModel.get(newIndex);
                            if (row.sectionId !== rowData.sectionId)
                                resultModel.setProperty(newIndex, "sectionId", rowData.sectionId);
                            if (row.isHero !== rowData.isHero)
                                resultModel.setProperty(newIndex, "isHero", rowData.isHero);
                            if (row.isFirst !== rowData.isFirst)
                                resultModel.setProperty(newIndex, "isFirst", rowData.isFirst);
                            if (row.isLast !== rowData.isLast)
                                resultModel.setProperty(newIndex, "isLast", rowData.isLast);
                            if (currentRefs[newIndex] !== rowData.ref) {
                                resultModel.setProperty(newIndex, "modelRef", rowData.ref);
                                currentRefs[newIndex] = rowData.ref;
                            }
                        }

                        // Whatever the passes above did, the model must end up
                        // exactly as long as `rows`. Anything past that length is a
                        // row the diff failed to account for, and it would stay
                        // visible and clickable.
                        while (resultModel.count > rows.length) {
                            resultModel.remove(resultModel.count - 1);
                            currentRefs.pop();
                        }
                        appResults.rowRefs = currentRefs;
                    }

                    Connections {
                        target: root
                        function onSearchingTextChanged() {
                            root.loadedResultsCount = root.resultPageSize;
                            if (appResults.count > 0)
                                appResults.selectFirst();
                            root.noteQueryEdit();
                        }
                    }

                    Connections {
                        target: LauncherSearch
                        function onResultsChanged() {
                            // Guard: don't populate while overview is closed/closing
                            // (stale LauncherSearch.results from previous session would cause ghost expansion)
                            if (!GlobalStates.overviewOpen)
                                return;
                            root.loadedResultsCount = root.resultPageSize;

                            // Derive the decision from this signal's current payload.
                            // showIdleNowPlaying is a binding over the same payload and
                            // can still expose its previous value while resultsChanged
                            // is being delivered, leaving an active but empty surface.
                            const nextRows = root.processResults(LauncherSearch.results);

                            // An empty query only means an empty list when nothing
                            // actually produced rows for the idle surface.
                            if (root.searchingText === "" && !root.alwaysListAppsMode && nextRows.length === 0) {
                                root.suppressItemTransitions = true;
                                resultModel.clear();
                                return;
                            }

                            // One diff per results change. Applying a 15-row slice and
                            // then the full list 150ms later made every keystroke add,
                            // remove and re-add the same rows — the churn the reorder
                            // animation was then asked to render.
                            appResults.applyResultDiff(nextRows);
                            if (root.selectionAnchorQuery !== root.searchingText) {
                                root.selectionAnchorQuery = root.searchingText;
                                root.focusFirstItem();
                            }
                        }
                    }

                    model: ListModel {
                        id: resultModel
                        // Search rows intentionally carry heterogeneous result
                        // objects (apps, panels, inline settings, files). Static
                        // role inference locks `modelRef` to whichever shape is
                        // inserted first and rejects later groups at runtime.
                        dynamicRoles: true
                    }

                    Component.onCompleted: {
                        applyResultDiff(root.processResults(LauncherSearch.results));
                    }

                    delegate: Loader {
                        id: resultDelegate
                        required property int index
                        required property var modelData
                        width: appResults.width
                        height: item ? item.implicitHeight : 0
                        sourceComponent: {
                            if (resultDelegate.modelData.isHeader)
                                return sectionCaption;
                            if (resultDelegate.modelData.isHero === true)
                                return bestMatchRow;
                            if (resultDelegate.modelData.modelRef?.key === "mpris:now-playing")
                                return nowPlayingRow;
                            return resultDelegate.modelData.modelRef?.settingRef ? settingResultCard : normalSearchItem;
                        }
                        onLoaded: root.refreshSelectedResultNavigation()

                        // Entrance belongs to the delegate, not to the view's `add`
                        // transition: an interrupted view transition can strand
                        // opacity at 0, and a row that never paints is a worse bug
                        // than a row that never animates. `y` is left entirely to
                        // the view — a Behavior here raced the move/displaced
                        // transitions and let rows drift over each other.
                        property real revealProgress: 0
                        opacity: revealProgress
                        transform: Translate {
                            y: (1 - resultDelegate.revealProgress) * -6
                        }

                        SequentialAnimation {
                            id: revealAnim
                            PauseAnimation {
                                // `index` is briefly -1 while a delegate is being
                                // torn down, and PauseAnimation rejects a negative
                                // duration outright.
                                duration: appResults.staggerReveal
                                    ? Math.max(0, Math.min(5, resultDelegate.index)) * appResults.staggerStep
                                    : 0
                            }
                            NumberAnimation {
                                target: resultDelegate
                                property: "revealProgress"
                                to: 1
                                duration: Appearance.animation.elementMoveFast.duration
                                easing.type: Appearance.animation.elementMoveFast.type
                                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                            }
                        }

                        Component.onCompleted: revealAnim.start()

                        Component {
                            id: sectionCaption

                            Item {
                                readonly property real topGap: resultDelegate.modelData.isFirst
                                    ? 0
                                    : Appearance.sizes.elevationMargin
                                readonly property real bottomGap: Appearance.sizes.elevationMargin * 0.4
                                implicitHeight: captionRow.implicitHeight + topGap + bottomGap

                                RowLayout {
                                    id: captionRow
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.leftMargin: Appearance.sizes.elevationMargin + 6
                                    anchors.rightMargin: Appearance.sizes.elevationMargin + 6
                                    anchors.topMargin: parent.topGap
                                    spacing: 7

                                    MaterialSymbol {
                                        text: root.sectionPresentation(resultDelegate.modelData.sectionId).icon
                                        iconSize: Appearance.font.pixelSize.small
                                        color: Appearance.colors.colOutline
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: root.sectionPresentation(resultDelegate.modelData.sectionId).label
                                        color: Appearance.colors.colOnSurfaceVariant
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        font.weight: Font.Medium
                                    }
                                }
                            }
                        }

                        Component {
                            id: bestMatchRow

                            // Inset to the same edge as every other row, so the
                            // prominence comes from its shape rather than from
                            // it sitting in a different place.
                            Item {
                                implicitHeight: heroItem.implicitHeight

                                function activate(): bool {
                                    return heroItem.activate();
                                }

                                function clicked(): bool {
                                    heroItem.clicked();
                                    return true;
                                }

                                function runSecondary(index: int) {
                                    heroItem.runSecondary(index);
                                }

                                SearchBestMatch {
                                    id: heroItem
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.leftMargin: root.rowSideMargin
                                    anchors.rightMargin: root.rowSideMargin
                                    entry: resultDelegate.modelData.modelRef
                                    query: root.searchingText
                                    listIndex: resultDelegate.index
                                    listCurrentIndex: appResults.currentIndex
                                    secondaryLimit: Config.options.search.bestMatch?.secondaryActions ?? 4
                                    onResultExecuted: feedbackText => root.showActionFeedback(feedbackText)
                                }
                            }
                        }

                        Component {
                            id: settingResultCard

                            // Loader owns this item's explicit width and
                            // resizes it to the delegate. The card must be a
                            // child instead: a direct child gets stretched
                            // back to full width after its x inset is applied.
                            Item {
                                implicitHeight: settingCardItem.implicitHeight
                                readonly property bool supportsHorizontalNavigation: settingCardItem.supportsHorizontalNavigation

                                function activate(): bool {
                                    return settingCardItem.activate();
                                }

                                function clicked(): bool {
                                    return settingCardItem.clicked();
                                }

                                function navigateLeft(): bool {
                                    return settingCardItem.navigateLeft();
                                }

                                function navigateRight(): bool {
                                    return settingCardItem.navigateRight();
                                }

                                AiSettingResultCard {
                                    id: settingCardItem
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.margins: Appearance.sizes.elevationMargin
                                    height: implicitHeight
                                    setting: resultDelegate.modelData.modelRef.settingRef
                                    compact: true
                                    launcherStyle: true
                                    listIndex: resultDelegate.index
                                    listCount: appResults.count
                                    listCurrentIndex: appResults.currentIndex
                                    groupFirst: resultDelegate.modelData.isFirst === true
                                    groupLast: resultDelegate.modelData.isLast === true
                                }
                            }
                        }

                        Component {
                            id: nowPlayingRow

                            Item {
                                implicitHeight: nowPlayingItem.implicitHeight
                                readonly property bool supportsHorizontalNavigation: nowPlayingItem.supportsHorizontalNavigation

                                function activate(): bool {
                                    return nowPlayingItem.activate();
                                }

                                function clicked(): bool {
                                    return nowPlayingItem.clicked();
                                }

                                function navigateLeft(): bool {
                                    return nowPlayingItem.navigateLeft();
                                }

                                function navigateRight(): bool {
                                    return nowPlayingItem.navigateRight();
                                }

                                SearchNowPlaying {
                                    id: nowPlayingItem
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.leftMargin: root.rowSideMargin
                                    anchors.rightMargin: root.rowSideMargin
                                    entry: resultDelegate.modelData.modelRef
                                    listIndex: resultDelegate.index
                                    listCount: appResults.count
                                    listCurrentIndex: appResults.currentIndex
                                    isFirst: resultDelegate.modelData.isFirst === true
                                    isLast: resultDelegate.modelData.isLast === true
                                    onResultExecuted: feedbackText => root.showActionFeedback(feedbackText)
                                }
                            }
                        }

                        Component {
                            id: normalSearchItem

                            SearchItem {
                                id: searchItem
                                width: resultDelegate.width
                                listIndex: resultDelegate.index
                                listCurrentIndex: appResults.currentIndex
                                // The model row wraps the result; `modelRef` is the
                                // original LauncherSearchResult, not a copy of it.
                                entry: resultDelegate.modelData.modelRef
                                isFirst: resultDelegate.modelData.isFirst === true
                                isLast: resultDelegate.modelData.isLast === true
                                horizontalMargin: root.rowSideMargin
                                // The delegate owns the entrance for every row kind,
                                // captions included; a second fade underneath it only
                                // muddies the curve.
                                animateEntrance: false
                                query: StringUtils.cleanOnePrefix(root.searchingText, [Config.options.search.prefix.action, Config.options.search.prefix.app, Config.options.search.prefix.clipboard, Config.options.search.prefix.math, Config.options.search.prefix.shellCommand, Config.options.search.prefix.webSearch])
                                onResultExecuted: feedbackText => root.showActionFeedback(feedbackText)

                                Connections {
                                    target: root
                                    function onRequestToggleActions() {
                                        if (searchItem.listIndex === appResults.currentIndex) {
                                            searchItem.actionPanelOpen = !searchItem.actionPanelOpen;
                                            searchItem.actionSelectedIndex = 0;
                                            if (searchItem.actionPanelOpen) {
                                                searchItem.forceActiveFocus();
                                            } else {
                                                root.focusSearchInput();
                                            }
                                        }
                                    }
                                }

                                Keys.onPressed: event => {
                                    if (event.key === Qt.Key_K && (event.modifiers & Qt.ControlModifier)) {
                                        searchItem.actionPanelOpen = !searchItem.actionPanelOpen;
                                        searchItem.actionSelectedIndex = 0;
                                        if (searchItem.actionPanelOpen) {
                                            searchItem.forceActiveFocus();
                                        } else {
                                            root.focusSearchInput();
                                        }
                                        event.accepted = true;
                                    } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                                        if (searchItem.actionPanelOpen)
                                            return;
                                        if (root.showNormalCategoryFilter) {
                                            root.cycleResultCategory(event.key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier) ? -1 : 1);
                                        } else if (event.key === Qt.Key_Tab && resultDelegate.modelData.modelRef) {
                                            const tabbedText = resultDelegate.modelData.modelRef.name;
                                            LauncherSearch.query = tabbedText;
                                            searchBar.searchInput.text = tabbedText;
                                            root.focusSearchInput();
                                        } else {
                                            return;
                                        }
                                        event.accepted = true;
                                    }
                                }
                            }
                        }
                    }

                    // ── Reorder animation ──
                    // Captions and rows now share one positioning path, so a caption
                    // can no longer snap to its final spot while the rows around it
                    // are still travelling.
                    readonly property int reorderDuration: root.suppressItemTransitions
                        ? 0
                        : Appearance.animation.elementMoveFast.duration

                    move: Transition {
                        NumberAnimation {
                            properties: "y"
                            duration: appResults.reorderDuration
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Appearance.animationCurves.emphasized
                        }
                    }

                    displaced: Transition {
                        NumberAnimation {
                            properties: "y"
                            duration: appResults.reorderDuration
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Appearance.animationCurves.emphasized
                        }
                    }

                    // No `remove` transition, deliberately.
                    //
                    // It is the only view transition that keeps a delegate alive
                    // after its model row is gone, and therefore the only one that
                    // can strand one: interrupt a removal — which a burst of
                    // keystrokes, or the asynchronous file results landing a beat
                    // after the query settled, does constantly — and the delegate
                    // is left in the scene with no row behind it. It keeps its old
                    // y, reserves no space, and still answers clicks.
                    //
                    // `removeDisplaced` (which falls back to `displaced` above) is
                    // what actually reads as a removal anyway: the rows below close
                    // the gap. The vanishing row itself was never the motion the eye
                    // was following.
                }

                Item {
                    id: emptySearchState
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    implicitHeight: emptyStateContent.implicitHeight + Appearance.sizes.elevationMargin * 4
                    visible: opacity > 0.01
                    opacity: root.showEmptySearchState && !root.showSkeletons ? 1.0 : 0.0

                    transform: Translate {
                        y: emptySearchState.opacity > 0 ? 0 : Appearance.sizes.elevationMargin
                    }

                    Behavior on opacity {
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveFast.duration
                            easing.type: Appearance.animation.elementMoveFast.type
                            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                        }
                    }

                    ColumnLayout {
                        id: emptyStateContent
                        anchors.centerIn: parent
                        width: Math.min(implicitWidth, parent.width - Appearance.sizes.elevationMargin * 4)
                        spacing: Appearance.sizes.elevationMargin

                        MaterialShapeWrappedMaterialSymbol {
                            Layout.alignment: Qt.AlignHCenter
                            shape: MaterialShape.Shape.SoftBurst
                            text: "search_off"
                            iconSize: Appearance.font.pixelSize.huge
                            color: Appearance.colors.colSecondaryContainer
                            colSymbol: Appearance.colors.colOnSecondaryContainer
                        }

                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.maximumWidth: emptySearchState.width - Appearance.sizes.elevationMargin * 4
                            text: Translation.tr("Nothing found for %1").arg(String(root.searchingText.trim()))
                            color: Appearance.colors.colOnSurface
                            font.pixelSize: Appearance.font.pixelSize.large
                            font.weight: Font.DemiBold
                            elide: Text.ElideMiddle
                        }

                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: Translation.tr("Try another category or continue with an action")
                            color: Appearance.colors.colOnSurfaceVariant
                            font.pixelSize: Appearance.font.pixelSize.small
                        }

                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: Appearance.sizes.elevationMargin / 2

                            Repeater {
                                model: root.emptyFallbackActions

                                RippleButton {
                                    id: fallbackChip
                                    required property var modelData
                                    implicitWidth: fallbackChipContent.implicitWidth + Appearance.sizes.elevationMargin * 2
                                    implicitHeight: Appearance.sizes.elevationMargin * 4
                                    buttonRadius: Appearance.rounding.full
                                    colBackground: Appearance.colors.colSurfaceContainerHigh
                                    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                                    colRipple: Appearance.colors.colSecondaryContainerActive
                                    onClicked: root.executeEmptyFallback(modelData.id)

                                    contentItem: RowLayout {
                                        id: fallbackChipContent
                                        anchors.centerIn: parent
                                        spacing: Appearance.sizes.elevationMargin / 2

                                        MaterialSymbol {
                                            text: fallbackChip.modelData.icon
                                            iconSize: Appearance.font.pixelSize.normal
                                            color: Appearance.colors.colOnSurface
                                        }

                                        StyledText {
                                            text: fallbackChip.modelData.label
                                            color: Appearance.colors.colOnSurface
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            font.weight: Font.Medium
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    id: actionFeedbackBar
                    z: 4
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: Appearance.sizes.elevationMargin
                    anchors.rightMargin: Appearance.sizes.elevationMargin
                    anchors.bottomMargin: Appearance.sizes.elevationMargin / 2
                    implicitHeight: feedbackContent.implicitHeight + Appearance.sizes.elevationMargin
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colSecondaryContainer
                    opacity: root.actionFeedbackText.length > 0 ? 1.0 : 0.0
                    visible: opacity > 0.01

                    transform: Translate {
                        y: root.actionFeedbackText.length > 0 ? 0 : Appearance.sizes.elevationMargin
                        Behavior on y {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                    }
                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }

                    RowLayout {
                        id: feedbackContent
                        anchors.centerIn: parent
                        spacing: Appearance.sizes.elevationMargin / 2
                        MaterialSymbol {
                            text: "check_circle"
                            iconSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                        StyledText {
                            text: root.actionFeedbackText
                            color: Appearance.colors.colOnSecondaryContainer
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.Medium
                        }
                    }
                }

                ColumnLayout {
                    id: searchSkeletons
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    anchors.topMargin: 10
                    anchors.bottomMargin: 10
                    spacing: 8
                    visible: opacity > 0
                    opacity: root.showSkeletons ? 1.0 : 0.0
                    Behavior on opacity {
                        enabled: !root.inNotchMode
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveFast.duration
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                        }
                    }

                    Repeater {
                        model: 4
                        Rectangle {
                            id: skeletonRow
                            required property int index
                            Layout.fillWidth: true
                            implicitHeight: 52
                            radius: Appearance.rounding.small
                            color: Appearance.colors.colSurfaceContainerHigh
                            antialiasing: true

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 12

                                Rectangle {
                                    implicitWidth: 32
                                    implicitHeight: 32
                                    radius: Appearance.rounding.full
                                    color: Appearance.colors.colSurfaceContainerHighest
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 4

                                    Rectangle {
                                        Layout.preferredWidth: 120
                                        implicitHeight: 12
                                        radius: Appearance.rounding.verysmall
                                        color: Appearance.colors.colSurfaceContainerHighest
                                    }

                                    Rectangle {
                                        Layout.preferredWidth: 80
                                        implicitHeight: 8
                                        radius: Appearance.rounding.verysmall
                                        color: Appearance.colors.colSurfaceContainerHighest
                                    }
                                }
                            }
                        }
                    }
                }
                }

                Loader {
                    id: registeredPanelHostLoader

                    readonly property bool keepAlive: item?.keepAlive === true
                    active: searchResultsSurface.registeredPanelActive || keepAlive
                    visible: searchResultsSurface.registeredPanelActive
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: root.hostedPanelSideMargin
                    anchors.rightMargin: root.hostedPanelSideMargin
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom

                    sourceComponent: Component {
                        SearchPanelHost {
                            activePanelId: root.activePanelId
                            searchQuery: root.searchingText
                            inNotchMode: root.inNotchMode
                        }
                    }
                }

                Loader {
                    id: aiPanelLoader
                    active: root.isAiMode || opacity > 0.01
                    visible: opacity > 0.01
                    anchors.fill: parent
                    anchors.margins: Appearance.sizes.elevationMargin
                    source: "AiChatPanel.qml"
                    opacity: root.isAiMode ? 1.0 : 0.0

                    // Translate + fade, without the full-surface Gaussian blur that
                    // used to run on exactly the frames where the container is also
                    // animating its height. The motion already reads as arrival.
                    transform: Translate {
                        y: (1.0 - aiPanelLoader.opacity) * 16
                    }
                    Behavior on opacity {
                        enabled: !root.inNotchMode
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveFast.duration
                            easing.type: Appearance.animation.elementMoveFast.type
                            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                        }
                    }

                    Connections {
                        target: aiPanelLoader.item
                        ignoreUnknownSignals: true
                        function onRequestBackToSearch() {
                            root.exitAiMode();
                        }
                        function onRequestFocusComposer() {
                            if (aiPanelLoader.item && typeof aiPanelLoader.item.focusComposer === "function")
                                aiPanelLoader.item.focusComposer();
                        }
                        function onRequestSendMessage(text) {
                            root.sendAiMessage(text);
                        }
                        function onRequestContinueInSidebar() {
                            root.continueInSidebar();
                        }
                    }

                    Binding {
                        target: aiPanelLoader.item
                        property: "activeSurface"
                        value: root.isAiMode
                        when: aiPanelLoader.status === Loader.Ready
                    }
                    Binding {
                        target: aiPanelLoader.item
                        property: "searchHost"
                        value: root
                        when: aiPanelLoader.status === Loader.Ready
                    }
                }
            }

            // Service lifecycle: activate/deactivate with mode
            Connections {
                target: root
                function onIsMediaDownloaderModeChanged() {
                    MediaDownloaderService.active = root.isMediaDownloaderMode;
                }
            }
        }
    }
}
