pragma ComponentBehavior: Bound

//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.functions as CF
import "modules/settings"

FloatingWindow {
    id: root
    property string firstRunFilePath: CF.FileUtils.trimFileProtocol(`${Directories.state}/user/first_run.txt`)
    property string firstRunFileContent: "This file is just here to confirm you've been greeted :>"
    property real contentPadding: 8
    property bool showNextTime: false

    property int currentPage: 0
    property real scrollPos: 0
    property int previousPage: 0
    property string lastSearch: ""
    property int lastSearchIndex: -1
    property int resultsCount: 0
    property string activeSearchQuery: ""
    property string pendingSearchText: ""

    property string pendingSectionHighlight: ""
    property string pendingSubPage: ""

    // Settings navigation is intentionally session-local. The stack contains
    // the states behind the current page, including an open sub-page, and is
    // capped so a long exploratory session cannot grow without bound.
    property var navigationHistory: []
    property var navigationForwardHistory: []
    property bool navigationHistoryActive: false
    property bool restoringNavigation: false
    property int observedHistoryPage: -1
    property string observedHistorySubPage: ""
    property var pendingNavigationRestore: null

    function findSubPageHost(node) {
        if (!node)
            return null;
        if (node.navigationPath !== undefined)
            return node;

        if (node.item) {
            const itemHost = root.findSubPageHost(node.item);
            if (itemHost)
                return itemHost;
        }

        const children = node.children || [];
        for (let i = 0; i < children.length; ++i) {
            const childHost = root.findSubPageHost(children[i]);
            if (childHost)
                return childHost;
        }
        return null;
    }

    function currentSubPagePath() {
        const host = root.findSubPageHost(pageLoader.item);
        if (host && host.navigationPath !== undefined)
            return host.navigationPath.map(value => value.toString());

        if (!pageLoader.item || pageLoader.item.activeSubPage === undefined)
            return [];
        const url = pageLoader.item.activeSubPage.toString();
        return url === "" ? [] : [url];
    }

    function currentSubPageUrl() {
        const path = root.currentSubPagePath();
        return path.length > 0 ? JSON.stringify(path) : "";
    }

    readonly property var activeNavigationHost: root.findSubPageHost(pageLoader.item)

    function subPagePathFromState(state) {
        if (!state || !state.subPage)
            return [];
        try {
            const parsed = JSON.parse(state.subPage);
            return Array.isArray(parsed) ? parsed : [state.subPage];
        } catch (error) {
            // Keep compatibility with the single-URL representation used
            // before nested subpages were included in the history.
            return [state.subPage];
        }
    }

    // Deep links (search results, IPC) carry registry-relative paths such as
    // "ai/CustomModelsConfig.qml". Loader resolves a relative source against
    // ConfigSubPageHost.qml's own directory, which silently misses the file —
    // so anchor every relative entry to the settings configs folder here.
    function resolveSubPageEntry(value) {
        const raw = String(value ?? "");
        // Qt.resolvedUrl() inside shell components returns Quickshell's
        // `qs:/...` scheme. It is already absolute even though it has no
        // `://`; prefixing the configs directory produces
        // `modules/settings/configs/qs:/...` and the Loader silently fails.
        if (raw === "" || /^[A-Za-z][A-Za-z0-9+.-]*:/.test(raw))
            return raw;
        return Qt.resolvedUrl("modules/settings/configs/" + raw).toString();
    }

    function restoreSubPagePath(encodedPath) {
        const path = encodedPath ? root.subPagePathFromState({ subPage: encodedPath }) : [];
        const resolved = path.map(entry => root.resolveSubPageEntry(entry));
        const host = root.findSubPageHost(pageLoader.item);
        if (host && host.restoreNavigationPath) {
            host.restoreNavigationPath(resolved);
            return true;
        }

        if (pageLoader.item && pageLoader.item.activeSubPage !== undefined)
            pageLoader.item.activeSubPage = resolved.length > 0 ? resolved[0] : "";
        return false;
    }

    function sameNavigationState(a, b) {
        return a && b && a.page === b.page && a.subPage === b.subPage;
    }

    function currentNavigationState() {
        // `pageLoader.item` can still be the outgoing page while its switch
        // animation is running. The observed state is updated synchronously,
        // so it remains the authoritative browser-like location here.
        if (root.navigationHistoryActive && root.observedHistoryPage >= 0) {
            return {
                page: root.observedHistoryPage,
                subPage: root.observedHistorySubPage
            };
        }
        return {
            page: root.currentPage,
            subPage: root.currentSubPageUrl()
        };
    }

    function appendNavigationState(stack, state) {
        if (!state)
            return stack;
        const last = stack.length > 0 ? stack[stack.length - 1] : null;
        if (root.sameNavigationState(last, state))
            return stack;
        let next = stack.concat([state]);
        if (next.length > 10)
            next = next.slice(next.length - 10);
        return next;
    }

    function rememberObservedState() {
        if (!root.navigationHistoryActive || root.restoringNavigation || root.observedHistoryPage < 0)
            return;

        const state = {
            page: root.observedHistoryPage,
            subPage: root.observedHistorySubPage
        };
        const last = root.navigationHistory.length > 0
            ? root.navigationHistory[root.navigationHistory.length - 1]
            : null;
        if (root.sameNavigationState(last, state))
            return;

        root.navigationHistory = root.appendNavigationState(root.navigationHistory, state);
        // A page/sub-page chosen after going back starts a new branch, just as
        // in a browser. The forward button must not resurrect the abandoned
        // branch.
        root.navigationForwardHistory = [];
    }

    function beginNavigationSession() {
        root.navigationHistory = [];
        root.navigationForwardHistory = [];
        root.restoringNavigation = false;
        root.pendingNavigationRestore = null;
        root.observedHistoryPage = root.currentPage;
        root.observedHistorySubPage = root.currentSubPageUrl();
        root.navigationHistoryActive = true;
    }

    function endNavigationSession() {
        // A sub-page is part of the session too. Clear it when the window
        // closes so reopening Settings always starts at the page itself and
        // never inherits a stale overlay from the previous session.
        if (pageLoader.item && pageLoader.item.activeSubPage !== undefined)
            pageLoader.item.activeSubPage = "";
        root.navigationHistoryActive = false;
        root.navigationHistory = [];
        root.navigationForwardHistory = [];
        root.restoringNavigation = false;
        root.pendingNavigationRestore = null;
        root.observedHistoryPage = -1;
        root.observedHistorySubPage = "";
    }

    function handleObservedPageChanged() {
        if (root.navigationHistoryActive && root.observedHistoryPage !== root.currentPage)
            root.rememberObservedState();
        root.observedHistoryPage = root.currentPage;
        root.observedHistorySubPage = "";
    }

    function handleObservedSubPageChanged() {
        const nextSubPage = root.currentSubPageUrl();
        if (!root.navigationHistoryActive) {
            root.observedHistorySubPage = nextSubPage;
            return;
        }
        if (root.restoringNavigation) {
            root.observedHistorySubPage = nextSubPage;
            if (root.pendingNavigationRestore
                    && nextSubPage === root.pendingNavigationRestore.subPage)
                root.finishNavigationRestore();
            return;
        }
        if (nextSubPage === root.observedHistorySubPage)
            return;

        // The built-in sub-page back buttons clear activeSubPage. If the
        // previous stack entry is the page underneath, consume that entry
        // instead of adding a duplicate forward transition.
        const last = root.navigationHistory.length > 0
            ? root.navigationHistory[root.navigationHistory.length - 1]
            : null;
        if (nextSubPage === "" && root.observedHistorySubPage !== ""
                && root.sameNavigationState(last, { page: root.currentPage, subPage: "" })) {
            root.navigationHistory = root.navigationHistory.slice(0, -1);
            root.navigationForwardHistory = root.appendNavigationState(
                root.navigationForwardHistory,
                { page: root.currentPage, subPage: root.observedHistorySubPage });
        } else {
            root.rememberObservedState();
        }
        root.observedHistorySubPage = nextSubPage;
    }

    function finishNavigationRestore() {
        if (!root.restoringNavigation)
            return;
        root.pendingNavigationRestore = null;
        root.observedHistoryPage = root.currentPage;
        root.observedHistorySubPage = root.currentSubPageUrl();
        Qt.callLater(() => root.restoringNavigation = false);
    }

    function restoreNavigationState(target) {
        root.restoringNavigation = true;
        root.pendingNavigationRestore = target;

        if (root.currentPage !== target.page) {
            root.currentPage = target.page;
        } else if (root.restoreSubPagePath(target.subPage)) {
            // The corresponding navigation-path signal finishes the restore
            // after all nested loaders have received their target pages.
            if (target.subPage === root.currentSubPageUrl())
                root.finishNavigationRestore();
        } else {
            root.finishNavigationRestore();
        }
        return true;
    }

    function navigateBack() {
        if (!root.navigationHistoryActive || root.restoringNavigation
                || root.navigationHistory.length === 0)
            return false;

        const current = root.currentNavigationState();
        const target = root.navigationHistory[root.navigationHistory.length - 1];
        root.navigationHistory = root.navigationHistory.slice(0, -1);
        root.navigationForwardHistory = root.appendNavigationState(
            root.navigationForwardHistory, current);
        return root.restoreNavigationState(target);
    }

    function navigateForward() {
        if (!root.navigationHistoryActive || root.restoringNavigation
                || root.navigationForwardHistory.length === 0)
            return false;

        const current = root.currentNavigationState();
        const target = root.navigationForwardHistory[root.navigationForwardHistory.length - 1];
        root.navigationForwardHistory = root.navigationForwardHistory.slice(0, -1);
        root.navigationHistory = root.appendNavigationState(root.navigationHistory, current);
        return root.restoreNavigationState(target);
    }

    // ── Flat page list, derived from SettingsPageRegistry ────────────────
    // Pages are addressed by stable `id`, not index — use pageIndexById().
    property var pages: SettingsPageRegistry.pages.map(p => ({
                id: p.id,
                name: Translation.tr(p.name),
                icon: p.icon,
                component: p.component,
                hidden: p.hidden === true
            }))

    // Hidden pages sit at the end of the list; nav pages come first.
    readonly property int navPageCount: pages.filter(p => !p.hidden).length

    function pageIndexById(id) {
        return SettingsPageRegistry.pageIndexById(id);
    }

    /**
     * Shows the section a deep link asked for, once its page is up.
     *
     * The highlight used to be started only from the page loader's `onLoaded`,
     * which is fine for a link followed from inside the window — that always
     * changes page. A link from outside often does not: the window may already
     * be showing that page, and then nothing loads and nothing ever fires. So
     * a page that is already up is handled here, and one that is still loading
     * is left to `onLoaded`.
     */
    function applyPendingSectionHighlight() {
        if (root.pendingSectionHighlight === "")
            return;
        if (pageLoader.status === Loader.Ready)
            pendingHighlightTimer.restart();
    }

    function consumePendingSettingsPage() {
        const pending = GlobalStates.consumePendingSettingsPage();
        root.pendingSubPage = GlobalStates.settingsPendingSubPage || "";
        GlobalStates.settingsPendingSubPage = "";
        if ((GlobalStates.settingsPendingSection || "") !== "") {
            root.pendingSectionHighlight = GlobalStates.settingsPendingSection;
            GlobalStates.settingsPendingSection = "";
            // After the page switch below has been processed: if it changed
            // page, the loader takes it; if it did not, this does.
            Qt.callLater(() => root.applyPendingSectionHighlight());
        }
        if (!pending || pending === "")
            return;

        if (pending === "clipboard") {
            const launcherIndex = root.pageIndexById("launcher");
            if (launcherIndex >= 0) {
                root.currentPage = launcherIndex;
                const targetSubPage = "ClipboardConfig.qml";
                if (pageLoader.status === Loader.Ready) {
                    Qt.callLater(() => root.restoreSubPagePath(targetSubPage));
                } else {
                    root.pendingSubPage = targetSubPage;
                }
                return;
            }
        }

        const directIndex = root.pageIndexById(pending);
        if (directIndex >= 0) {
            const samePage = root.currentPage === directIndex;
            root.currentPage = directIndex;
            if (samePage && root.pendingSubPage !== ""
                    && pageLoader.status === Loader.Ready) {
                const targetSubPage = root.pendingSubPage;
                root.pendingSubPage = "";
                Qt.callLater(() => root.restoreSubPagePath(targetSubPage));
            }
            return;
        }

        // Keep compatibility with older callers that passed a component name.
        for (let i = 0; i < root.pages.length; i++) {
            if (root.pages[i].component.indexOf(pending) !== -1) {
                root.currentPage = i;
                break;
            }
        }
    }

    function cycleNavPage(delta) {
        if (root.currentPage >= root.navPageCount) {
            root.currentPage = delta > 0 ? 0 : root.navPageCount - 1;
            return;
        }
        root.currentPage = (root.currentPage + delta + root.navPageCount) % root.navPageCount;
    }

    // ── Grouped page list for Sidebar ────────────────────────────────────
    property var pageGroups: SettingsPageRegistry.groups.map(g => ({
                id: g.id,
                name: Translation.tr(g.name),
                pages: g.pageIds.map(id => {
                    const i = SettingsPageRegistry.pageIndexById(id);
                    return {
                        name: Translation.tr(SettingsPageRegistry.pages[i].name),
                        icon: SettingsPageRegistry.pages[i].icon,
                        pageIndex: i
                    };
                })
            }))

    title: "illogical-impulse Settings"
    implicitWidth: 1100
    implicitHeight: 750
    minimumSize: Qt.size(750, 500)
    color: "transparent"

    Connections {
        target: GlobalStates
        function onSettingsOpenChanged() {
            root.visible = GlobalStates.settingsOpen;
            if (GlobalStates.settingsOpen) {
                root.navigationHistoryActive = false;
                SearchRegistry.setSettingsActive(true);
                settingsSearchBar.forceFocus();
                root.consumePendingSettingsPage();
                Qt.callLater(() => root.beginNavigationSession());
            } else {
                root.pendingSearchText = "";
                SearchRegistry.setSettingsActive(false);
                root.endNavigationSession();
            }
        }
    }

    Connections {
        target: GlobalStates
        function onSettingsNavigationRequestChanged() {
            if (!GlobalStates.settingsOpen || !root.visible)
                return;
            root.consumePendingSettingsPage();
            settingsSearchBar.forceFocus();
        }
    }

    Connections {
        target: SearchRegistry
        function onIndexReady() {
            if (!root.visible || root.pendingSearchText === "")
                return;
            const query = root.pendingSearchText;
            root.pendingSearchText = "";
            root.acceptSearch(query);
        }
    }

    onVisibleChanged: {
        if (!visible) {
            root.pendingSearchText = "";
            SearchRegistry.setSettingsActive(false);
            root.endNavigationSession();
            if (GlobalStates.settingsOpen)
                GlobalStates.settingsOpen = false;
        } else if (GlobalStates.settingsOpen) {
            SearchRegistry.setSettingsActive(true);
            Qt.callLater(() => root.ensurePageReady());
        }
    }

    Component.onCompleted: {
        root.visible = GlobalStates.settingsOpen;
        if (root.visible) {
            // The deep link that opened this window fired before the window
            // existed: the loader below shell.qml only starts building it when
            // `settingsOpen` turns true, so both Connections above missed the
            // signal that carried the destination. A warm window has them and
            // navigates; a cold one used to land on whatever page was last
            // shown and drop the request on the floor.
            root.consumePendingSettingsPage();
            Qt.callLater(() => {
                SearchRegistry.setSettingsActive(true);
                root.beginNavigationSession();
            });
        }
        MaterialThemeLoader.reapplyTheme();
        // Re-apply ignore alpha rule: Settings is lazy-loaded, so the rule fired
        // in Appearance.onIgnoreAlphaChanged before this window existed. Re-send
        // now that the xdg-toplevel is mapped and Hyprland can match it.
        var a = Appearance.ignoreAlpha;
        Quickshell.execDetached(["hyprctl", "eval",
            "hl.window_rule({ match = { title = '^(illogical-impulse Settings)$' }, no_blur = false, ignorealpha = " + a + " })"]);
    }

    function acceptSearch(text) {
        const result = SearchRegistry.getDynamicSearchResults(text);

        if (result == null || result.length === 0) {
            settingsSearchBar.shakeNoResults();
            root.activeSearchQuery = "";
            root.resultsCount = 0;
            root.lastSearchIndex = -1;
            if (root.currentPage === root.pageIndexById("search")) {
                root.currentPage = root.previousPage;
            }
            return;
        }

        let totalWidgets = 0;
        for (let s of result) {
            totalWidgets += s.items.length;
            for (let sub of s.subsections) {
                totalWidgets += sub.items.length;
            }
        }

        root.resultsCount = totalWidgets;
        root.lastSearchIndex = 0;

        if (root.currentPage !== root.pageIndexById("search")) {
            root.previousPage = root.currentPage;
        }
        root.activeSearchQuery = text;
        SearchRegistry.currentSearch = text;
        root.currentPage = root.pageIndexById("search");
    }

    function ensurePageReady() {
        if (!root.visible || !Config.ready)
            return;
        if (pageLoader.status === Loader.Loading || pageLoader.status === Loader.Ready)
            return;
        pageLoader.beginGatedLoad(root.pages[root.currentPage].component);
    }

    Rectangle {
        anchors.fill: parent
        color: Appearance.colors.colLayer0
        radius: Appearance.windowRounding
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
    }

    ColumnLayout {
        spacing: contentPadding
        anchors {
            fill: parent
            margins: contentPadding
        }

        Keys.onPressed: event => {
            // Cycling only covers nav pages — hidden pages (profile, search
            // results) are reachable through their own entry points.
            if (event.modifiers === Qt.ControlModifier) {
                if (event.key === Qt.Key_PageDown) {
                    root.currentPage = Math.min(root.currentPage + 1, root.navPageCount - 1);
                    event.accepted = true;
                } else if (event.key === Qt.Key_PageUp) {
                    root.currentPage = Math.max(Math.min(root.currentPage, root.navPageCount) - 1, 0);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Tab) {
                    root.cycleNavPage(1);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Backtab) {
                    root.cycleNavPage(-1);
                    event.accepted = true;
                }
            }
        }

        // ── Top Header Row (User Header + Search Bar) ─────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: 56
            spacing: contentPadding

            UserHeader {
                id: userHeader
                Layout.preferredWidth: 230
                Layout.fillHeight: true
                isActive: root.currentPage === root.pageIndexById("profile")
                onClicked: root.currentPage = root.pageIndexById("profile")
            }

            SearchBar {
                id: settingsSearchBar
                Layout.fillWidth: true
                Layout.fillHeight: true

                lastSearchIndex: root.lastSearchIndex
                resultsCount: root.resultsCount

                onTextChanged: text => {
                    if (text === "")
                        root.pendingSearchText = "";
                    if (text === "") {
                        if (root.currentPage === root.pageIndexById("search")) {
                            root.currentPage = root.previousPage;
                        }
                        root.activeSearchQuery = "";
                        root.resultsCount = 0;
                        root.lastSearchIndex = -1;
                    }
                }

                onAccepted: text => {
                    if (text.trim() === "") {
                        root.acceptSearch(text);
                        return;
                    }
                    if (!SearchRegistry.indexed) {
                        root.pendingSearchText = text;
                        SearchRegistry.ensureIndexing();
                        return;
                    }
                    root.acceptSearch(text);
                }

                onCloseRequested: GlobalStates.settingsOpen = false
            }
        }

        ConfigHealthBanner {}

        RowLayout { // Window content with sidebar and content pane
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: contentPadding

            // ── Sidebar v2 ────────────────────────────────────────────────
            Sidebar {
                id: sidebarV2
                z: 1
                Layout.fillHeight: true
                implicitWidth: 230

                currentPage: root.currentPage
                groups: root.pageGroups

                onPageSelected: idx => {
                    root.currentPage = idx;
                }
            }
            Rectangle { // Content container
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "transparent"
                radius: Appearance.windowRounding
                clip: true

                Loader {
                    id: pageLoader
                    width: parent.width
                    height: parent.height
                    opacity: 1.0
                    transformOrigin: Item.Left

                    active: Config.ready && pageLoadArmed
                    asynchronous: true

                    property bool pageLoadArmed: false
                    property bool _skeletonGateActive: false

                    Component.onCompleted: {
                        Qt.callLater(() => root.ensurePageReady());
                    }

                    property bool _waitingForLoad: false

                    function beginGatedLoad(nextSource) {
                        if (!nextSource || nextSource === "")
                            return;

                        pageLoadArmed = false;
                        _skeletonGateActive = true;
                        _waitingForLoad = true;
                        // The skeleton is a fallback for pages slow enough that
                        // an empty pane would look broken. Revealing it on every
                        // switch made the fast pages - which is most of them -
                        // flash three grey cards for a couple of frames.
                        pageSkeleton.revealed = false;
                        skeletonDelayTimer.restart();
                        source = nextSource;
                        pageActivationTimer.restart();
                    }

                    function resetPageSkeleton() {
                        skeletonDelayTimer.stop();
                        pageSkeleton.revealed = false;
                    }

                    function handlePageLoadStarted() {
                        if (_skeletonGateActive)
                            return;
                        pageSkeleton.revealed = false;
                        skeletonDelayTimer.restart();
                    }

                    function handlePageLoadFailed() {
                        _skeletonGateActive = false;
                        pageLoadArmed = false;
                        resetPageSkeleton();
                        _waitingForLoad = false;
                    }

                    onLoaded: {
                        _skeletonGateActive = false;
                        skeletonDelayTimer.stop();
                        pageSkeleton.revealed = false;
                        if (root.pendingSectionHighlight !== "") {
                            pendingHighlightTimer.restart();
                        }
                        if (root.pendingSubPage !== undefined && root.pendingSubPage !== "") {
                            const targetSub = root.pendingSubPage;
                            root.pendingSubPage = "";
                            root.restoreSubPagePath(targetSub);
                        }
                        if (_waitingForLoad) {
                            _waitingForLoad = false;
                            switchAnimIncoming.start();
                        }
                        if (root.restoringNavigation && root.pendingNavigationRestore
                                && root.pendingNavigationRestore.page === root.currentPage) {
                            const targetSubPage = root.pendingNavigationRestore.subPage;
                            if (!root.restoreSubPagePath(targetSubPage))
                                root.finishNavigationRestore();
                        }
                    }

                    onStatusChanged: {
                        if (status === Loader.Loading) {
                            handlePageLoadStarted();
                        } else if (status === Loader.Error) {
                            handlePageLoadFailed();
                        }
                    }

                    onSourceChanged: {
                        if (source !== "")
                            handlePageLoadStarted();
                    }

                    Timer {
                        id: pageActivationTimer
                        // Only needs to give the outgoing page its own frame to
                        // be torn down in; it used to sit for a third of the
                        // whole page-switch budget doing nothing.
                        interval: 16
                        repeat: false
                        onTriggered: {
                            if (root.visible && Config.ready)
                                pageLoader.pageLoadArmed = true;
                        }
                    }

                    Timer {
                        id: pendingHighlightTimer
                        interval: 150
                        repeat: false
                        onTriggered: {
                            if (root.pendingSectionHighlight !== "") {
                                SearchRegistry.currentSearch = root.pendingSectionHighlight;
                                root.pendingSectionHighlight = "";
                            }
                        }
                    }

                    Timer {
                        id: skeletonDelayTimer
                        // Covers pageActivationTimer plus the build time of a
                        // typical page, so only the genuinely heavy ones ever
                        // reach the skeleton.
                        interval: 200
                        repeat: false
                        onTriggered: {
                            if (pageLoader.status === Loader.Loading || pageLoader._waitingForLoad)
                                pageSkeleton.revealed = true;
                        }
                    }

                    Connections {
                        target: root
                        function onCurrentPageChanged() {
                            root.handleObservedPageChanged();
                            switchAnimOutgoing.complete();
                            switchAnimOutgoing.start();
                        }
                        function onScrollPosChanged() {
                            if (root.scrollPos == -1)
                                return;
                            scrollTimer.start();
                        }
                    }

                    Timer {
                        id: scrollTimer
                        interval: 250
                        onTriggered: {
                            pageLoader.item.contentY = root.scrollPos;
                            root.scrollPos = -1;
                        }
                    }

                    SequentialAnimation {
                        id: switchAnimOutgoing

                        ParallelAnimation {
                            NumberAnimation {
                                target: pageLoader
                                property: "opacity"
                                from: 1
                                to: 0
                                duration: 100
                                easing.type: Easing.OutQuad
                            }
                            NumberAnimation {
                                target: pageLoader
                                property: "scale"
                                from: 1
                                to: 0.97
                                duration: 100
                                easing.type: Easing.OutQuad
                            }
                        }
                        onFinished: {
                            pageLoader.x = 0;
                            pageLoader.beginGatedLoad(root.pages[root.currentPage].component);
                        }
                    }

                    SequentialAnimation {
                        id: switchAnimIncoming

                        ParallelAnimation {
                            NumberAnimation {
                                target: pageLoader
                                property: "opacity"
                                from: 0
                                to: 1
                                duration: 180
                                easing.type: Easing.OutCubic
                            }
                            NumberAnimation {
                                target: pageLoader
                                property: "scale"
                                from: 0.97
                                to: 1
                                duration: 180
                                easing.type: Easing.OutCubic
                            }
                        }
                    }

                } // closes Loader

                SettingsPageSkeleton {
                    id: pageSkeleton
                    anchors.fill: parent
                    z: 1
                }
            } // closes Rectangle (Content container)
        } // closes RowLayout (Window content)

    } // closes ColumnLayout

    // PointerHandlers do not own a cursor surface, so every control underneath
    // keeps its PointingHandCursor. React on press instead of waiting for a tap
    // gesture that another control can cancel while taking the grab.
    TapHandler {
        acceptedButtons: Qt.BackButton | Qt.ExtraButton1
        grabPermissions: PointerHandler.CanTakeOverFromAnything
        onPressedChanged: if (pressed) root.navigateBack()
    }

    TapHandler {
        acceptedButtons: Qt.ForwardButton | Qt.ExtraButton2
        grabPermissions: PointerHandler.CanTakeOverFromAnything
        onPressedChanged: if (pressed) root.navigateForward()
    }

    // Keep observation reactive to the actual page host. This also catches
    // nested hosts whose activeSubPage changes without replacing the page
    // Loader item.
    readonly property string liveSubPagePath: root.currentSubPageUrl()
    onLiveSubPagePathChanged: root.handleObservedSubPageChanged()

    Connections {
        target: root.activeNavigationHost
        ignoreUnknownSignals: true
        function onNavigationPathChanged() {
            root.handleObservedSubPageChanged();
        }
        function onNavigationChanged() {
            root.handleObservedSubPageChanged();
        }
    }

}
