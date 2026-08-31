import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Effects
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: overviewScope
    property bool dontAutoCancelSearch: false

    signal setSearchingTextRequested(string text)
    signal exitActivePanelRequested

    Loader {
        id: overviewVariantsLoader
        active: !GlobalStates.searchConnectActive && !GlobalStates.floatingNotchOwnsSearch
        sourceComponent: Component {
            Variants {
                id: overviewVariant

                property var variantModel: Quickshell.screens

                model: overviewVariant.variantModel

                LazyLoader {
                    id: realOverviewLoader
                    required property var modelData
                    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(modelData)
                    property int monitorIndex: overviewVariant.variantModel.indexOf(modelData)
                    property bool monitorIsFocused: (Hyprland.focusedMonitor?.name === monitor?.name) || (Hyprland.focusedMonitor?.id == monitorIndex)
                    property bool contentKeepAlive: false
                    // Keep the focused window alive while it is visible or
                    // while its closing animation still has pixels on screen.
                    // The Scope and IPC shortcuts remain loaded, but this
                    // expensive per-monitor PanelWindow is destroyed otherwise.
                    property bool visualActive: false
                    active: contentKeepAlive || (monitorIsFocused && (GlobalStates.overviewOpen || visualActive))

                    onMonitorIsFocusedChanged: {
                        if (!monitorIsFocused)
                            visualActive = false;
                    }

                    component: PanelWindow {
                        id: root

                        screen: realOverviewLoader.modelData
                        readonly property bool monitorIsFocused: realOverviewLoader.monitorIsFocused
                        readonly property int monitorIndex: realOverviewLoader.monitorIndex
                        readonly property bool keepAlive: searchWidget.keepAlive
                        readonly property bool isBottomBar: !Config.options.bar.vertical && Config.options.bar.bottom

                        readonly property bool isScrollingLayout: Persistent.states.hyprland.layout === "scrolling"
                        readonly property string animStyle: (GlobalStates.searchCenterMode || Config.options.search.suggestions.enable) ? "zoom" : (Config.options.overview.animationStyle ?? "bounce")

                        WlrLayershell.namespace: "quickshell:overview"
                        WlrLayershell.layer: WlrLayer.Overlay
                        WlrLayershell.keyboardFocus: GlobalStates.overviewOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
                        color: "transparent"

                        property int animDurationEnter: Math.round(420 * Appearance.animMultiplier)
                        property int animDurationExit: Math.round(260 * Appearance.animMultiplier)
                        property list<real> animCurveEnter: Appearance.animationCurves.expressiveFastSpatial
                        property list<real> animCurveExit: Appearance.animationCurves.emphasizedAccel
                        /**
                         * Whether a panel (AI or hosted) owns the search surface.
                         * `GlobalStates` is read first on purpose: it is a singleton,
                         * so the binding always records a dependency on it, while an
                         * `id` that is not yet constructed when the binding is first
                         * evaluated records none at all.
                         */
                        readonly property bool searchPanelOwned: GlobalStates.searchPanelActive
                            || (searchWidget?.isAiMode ?? false)
                            || (searchWidget?.isAnySpecialMode ?? false)
                        /**
                         * Panel ownership plus an ordinary query. Only the panel half
                         * unloads the grid: destroying it for every keystroke would
                         * rebuild every window thumbnail as soon as the query cleared.
                         */
                        readonly property bool searchSurfaceOwned: root.searchPanelOwned
                            || GlobalStates.activeSearchQuery !== ""
                            || LauncherSearch.query !== ""
                        readonly property bool overviewShouldShow: !root.searchSurfaceOwned
                            && !GlobalStates.searchOnlyMode
                            && !GlobalStates.searchCenterMode
                            && !Config.options.search.suggestions.enable
                            && (Config?.options.overview.enable ?? true)
                        property real overviewRevealProgress: 1.0
                        property real overviewFadeProgress: 1.0
                        property bool _overviewRevealInitialized: false

                        ParallelAnimation {
                            id: overviewRevealAnim
                            NumberAnimation {
                                target: root
                                property: "overviewRevealProgress"
                                from: 0.0
                                to: 1.0
                                duration: root.animDurationEnter
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: root.animCurveEnter
                            }
                            NumberAnimation {
                                target: root
                                property: "overviewFadeProgress"
                                from: 0.0
                                to: 1.0
                                duration: root.animDurationEnter
                                easing.type: Easing.OutCubic
                            }
                        }

                        function syncOverviewReveal() {
                            if (!root._overviewRevealInitialized)
                                return;

                            if (!GlobalStates.overviewOpen)
                                return;

                            const shouldShow = root.overviewShouldShow;
                            overviewRevealAnim.stop();

                            if (!shouldShow) {
                                root.overviewRevealProgress = 0.0;
                                root.overviewFadeProgress = 0.0;
                                return;
                            }

                            // Force a real 0 -> 1 transition. This is intentionally
                            // explicit instead of relying on a Behavior over a binding.
                            root.overviewRevealProgress = 0.0;
                            root.overviewFadeProgress = 0.0;
                            Qt.callLater(() => {
                                if (GlobalStates.overviewOpen && LauncherSearch.query === "" && root.overviewShouldShow)
                                    overviewRevealAnim.start();
                            });
                        }

                        function consumePendingSearchQuery() {
                            if (!GlobalStates.activeSearchQuery)
                                return;
                            root.setSearchingText(GlobalStates.activeSearchQuery);
                            GlobalStates.activeSearchQuery = "";
                        }

                        Connections {
                            target: LauncherSearch
                            function onQueryChanged() {
                                root.syncOverviewReveal();
                            }
                        }

                        Connections {
                            target: searchWidget
                            function onIsAnySpecialModeChanged() {
                                root.syncOverviewReveal();
                            }
                            function onIsAiModeChanged() {
                                root.syncOverviewReveal();
                            }
                        }

                        Connections {
                            target: GlobalStates
                            function onSearchPanelActiveChanged() {
                                root.syncOverviewReveal();
                            }
                            function onActiveSearchQueryChanged() {
                                root.syncOverviewReveal();
                            }
                            function onOverviewOpenChanged() {
                                // The reveal is decided while the surface is open;
                                // every change that led up to the open was rejected
                                // by the guard at the top of syncOverviewReveal.
                                Qt.callLater(root.syncOverviewReveal);
                            }
                        }

                        Component.onCompleted: {
                            realOverviewLoader.visualActive = true;
                            root.overviewRevealProgress = root.overviewShouldShow && LauncherSearch.query === "" ? 1.0 : 0.0;
                            root.overviewFadeProgress = root.overviewRevealProgress;
                            root._overviewRevealInitialized = true;
                            root.consumePendingSearchQuery();
                        }

                        onKeepAliveChanged: realOverviewLoader.contentKeepAlive = keepAlive
                        Component.onDestruction: realOverviewLoader.contentKeepAlive = false

                        visible: GlobalStates.overviewOpen || searchWidgetWrapper.slideOpacity > 0
                        onVisibleChanged: {
                            if (root.visible)
                                realOverviewLoader.visualActive = true;
                            else if (!GlobalStates.overviewOpen)
                                realOverviewLoader.visualActive = false;
                        }

                        mask: Region {
                            item: GlobalStates.overviewOpen ? contentItem : null
                        }

                        anchors {
                            top: true
                            bottom: true
                            left: true
                            right: true
                        }
                        property int barSize: Config.options.bar.vertical ? Appearance.sizes.verticalBarWindowWidth : Appearance.sizes.barHeight
                        property int margin: barSize * 2
                        margins {
                            top: -margin * 2
                            bottom: -margin * 2
                            left: -margin * 2
                            right: -margin * 2
                        }

                        Connections {
                            target: GlobalStates
                            function onOverviewOpenChanged() {
                                if (!GlobalStates.overviewOpen) {
                                    searchWidget.disableExpandAnimation();
                                    overviewScope.dontAutoCancelSearch = false;
                                } else {
                                    const hasIncomingQuery = GlobalStates.activeSearchQuery.length > 0;
                                    if (!hasIncomingQuery) {
                                        overviewScope.dontAutoCancelSearch = false;
                                        searchWidget.cancelSearch();
                                    }
                                    root.consumePendingSearchQuery();
                                    delayedGrabTimer.start();
                                }
                            }
                        }

                        HyprlandFocusGrab {
                            id: grab
                            windows: [root]
                            property bool canBeActive: root.monitorIsFocused || GlobalStates.overviewOpen
                            active: false
                        }

                        // PanelWindow is a Wayland interface, not a QtQuick
                        // Item, so a Keys attached property here is ignored.
                        // Resolve Escape with a real window shortcut instead;
                        // it remains active even when the composer lost focus.
                        Shortcut {
                            enabled: root.monitorIsFocused && GlobalStates.overviewOpen && searchWidget.isAiMode
                            sequence: "Escape"
                            onActivated: searchWidget.handleEscape()
                        }

                        Timer {
                            id: delayedGrabTimer
                            interval: Config.options.hacks.arbitraryRaceConditionDelay
                            repeat: false
                            onTriggered: {
                                if (!grab.canBeActive)
                                    return;
                                grab.active = GlobalStates.overviewOpen;
                                if (grab.active) {
                                    searchWidget.focusSearchInput();
                                }
                            }
                        }

                        Connections {
                            target: overviewScope
                            function onSetSearchingTextRequested(text) {
                                root.setSearchingText(text);
                            }
                            function onExitActivePanelRequested() {
                                searchWidget.handleEscape();
                            }
                        }

                        function setSearchingText(text) {
                            searchWidget.setSearchingText(text);
                            searchWidget.focusFirstItem();
                        }

                        Item {
                            id: contentItem
                            anchors.fill: parent

                            MouseArea { // We could have used PanelWindow.mask to detect this, but this is more stable
                                anchors.fill: parent
                                enabled: GlobalStates.overviewOpen
                                onClicked: GlobalStates.overviewOpen = false
                            }

                            Item { // Wrapper for animation
                                id: searchWidgetWrapper
                                readonly property bool isNotchMode: Config.ready && Config.options.bar.dynamicIsland.notchMode.enable
                                implicitHeight: isNotchMode ? GlobalStates.activeSearchHeight : searchWidget.implicitHeight
                                implicitWidth: isNotchMode ? GlobalStates.activeSearchWidth : searchWidget.implicitWidth
                                z: 999
                                visible: !isNotchMode
                                height: isNotchMode ? implicitHeight : searchWidget.height

                                // Slide from top/bottom — direction matches top bar / bottom bar
                                readonly property real slideOffset: (root.isBottomBar ? 1 : -1) * (implicitHeight + root.margin * 2 + Appearance.sizes.elevationMargin + 40)
                                readonly property real initialYOffset: (GlobalStates.searchCenterMode || Config.options.search.suggestions.enable) ? 0 : (root.animStyle === "zoom" ? (root.isBottomBar ? 20 : -20) : searchWidgetWrapper.slideOffset)

                                // Driven directly — no Behavior, to avoid QML skipping anim while invisible
                                property real slideY: initialYOffset
                                property real slideOpacity: 0.0

                                opacity: isNotchMode ? 0.0 : slideOpacity
                                transform: [
                                    Translate {
                                        y: searchWidgetWrapper.slideY
                                    },
                                    Scale {
                                        origin.x: searchWidgetWrapper.width / 2
                                        origin.y: searchWidgetWrapper.height / 2
                                        xScale: root.animStyle === "zoom" ? (0.92 + 0.08 * searchWidgetWrapper.slideOpacity) : 1.0
                                        yScale: root.animStyle === "zoom" ? (0.92 + 0.08 * searchWidgetWrapper.slideOpacity) : 1.0
                                    }
                                ]

                                layer.enabled: !isNotchMode
                                layer.effect: MultiEffect {
                                    blurEnabled: (1.0 - searchWidgetWrapper.slideOpacity) > 0.001
                                    blurMax: 64.0
                                    blur: (1.0 - searchWidgetWrapper.slideOpacity) * 1.0
                                }

                                Timer {
                                    id: slideInStartTimer
                                    interval: 16 // 1 frame at 60fps — ensures QML paints reset before animating
                                    repeat: false
                                    onTriggered: {
                                        slideInYAnim.from = searchWidgetWrapper.initialYOffset;
                                        slideInYAnim.to = 0;
                                        slideInOpacityAnim.from = 0.0;
                                        slideInOpacityAnim.to = 1.0;
                                        slideInParallel.start();
                                    }
                                }

                                function triggerSlideIn() {
                                    slideOutParallel.stop();
                                    slideInParallel.stop();
                                    slideInStartTimer.stop();
                                    searchWidgetWrapper.slideY = searchWidgetWrapper.initialYOffset;
                                    searchWidgetWrapper.slideOpacity = 0.0;
                                    slideInYAnim.from = searchWidgetWrapper.initialYOffset;
                                    slideInYAnim.to = 0;
                                    slideInOpacityAnim.from = 0.0;
                                    slideInOpacityAnim.to = 1.0;
                                    slideInParallel.start();
                                }

                                function triggerSlideOut() {
                                    slideInParallel.stop();
                                    slideOutParallel.stop();
                                    slideOutYAnim.from = searchWidgetWrapper.slideY;
                                    slideOutYAnim.to = searchWidgetWrapper.initialYOffset;
                                    slideOutOpacityAnim.from = searchWidgetWrapper.slideOpacity;
                                    slideOutOpacityAnim.to = 0.0;
                                    slideOutParallel.start();
                                }

                                ParallelAnimation {
                                    id: slideInParallel
                                    NumberAnimation {
                                        id: slideInYAnim
                                        target: searchWidgetWrapper
                                        property: "slideY"
                                        duration: root.animDurationEnter
                                        easing.type: root.animStyle === "bounce" ? Easing.OutBack : Easing.OutCubic
                                        easing.overshoot: root.animStyle === "bounce" ? 1.2 : 0
                                    }
                                    NumberAnimation {
                                        id: slideInOpacityAnim
                                        target: searchWidgetWrapper
                                        property: "slideOpacity"
                                        duration: root.animDurationEnter
                                        easing.type: Easing.OutCubic
                                    }
                                }

                                ParallelAnimation {
                                    id: slideOutParallel
                                    NumberAnimation {
                                        id: slideOutYAnim
                                        target: searchWidgetWrapper
                                        property: "slideY"
                                        duration: root.animDurationExit
                                        easing.type: Easing.InCubic
                                    }
                                    NumberAnimation {
                                        id: slideOutOpacityAnim
                                        target: searchWidgetWrapper
                                        property: "slideOpacity"
                                        duration: root.animDurationExit
                                        easing.type: Easing.InCubic
                                        onFinished: {
                                            root.isClosing = false;
                                        }
                                    }
                                }

                                Connections {
                                    target: root
                                    function onVisibleChanged() {
                                        if (root.visible && GlobalStates.overviewOpen) {
                                            // Window just became visible — trigger slide-in from scratch
                                            searchWidgetWrapper.triggerSlideIn();
                                        }
                                    }
                                }

                                Connections {
                                    target: GlobalStates
                                    function onOverviewOpenChanged() {
                                        if (GlobalStates.overviewOpen) {
                                            if (root.visible) {
                                                searchWidgetWrapper.triggerSlideIn();
                                            }
                                            // If not visible yet, onVisibleChanged will handle it
                                        } else {
                                            searchWidgetWrapper.triggerSlideOut();
                                        }
                                    }
                                }

                                Keys.onPressed: event => {
                                    if (event.key === Qt.Key_Escape) {
                                        if (searchWidget.handleEscape()) {
                                            event.accepted = true;
                                            return;
                                        }
                                        GlobalStates.overviewOpen = false;
                                    }
                                }

                                width: implicitWidth
                                readonly property real centeredPreferredY: parent.height * Config.options.search.centerVerticalRatio - 29
                                readonly property real centeredSafeInset: root.margin * 2 + Appearance.sizes.elevationMargin
                                readonly property real centeredMaximumY: parent.height - searchWidget.implicitHeight - centeredSafeInset
                                y: GlobalStates.searchCenterMode
                                    ? Math.max(centeredSafeInset, Math.min(centeredPreferredY, centeredMaximumY))
                                    : (root.isBottomBar ? (parent.height - searchWidget.implicitHeight - (root.margin * 2 + Appearance.sizes.elevationMargin)) : (root.margin * 2 + Appearance.sizes.elevationMargin))
                                anchors.horizontalCenter: parent.horizontalCenter

                                SearchWidget {
                                    id: searchWidget
                                    shadowOpacity: searchWidgetWrapper.slideOpacity
                                    surfaceMonitorName: root.screen?.name ?? ""
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                            }

                            Loader { // Classic overview
                                id: overviewLoader
                                anchors.bottom: root.isBottomBar ? searchWidgetWrapper.top : undefined
                                anchors.top: root.isBottomBar ? undefined : searchWidgetWrapper.bottom
                                anchors.horizontalCenter: parent.horizontalCenter
                                // A panel owning the search destroys the grid rather
                                // than merely fading it: AI mode was already handled
                                // this way, and leaving every other hosted panel to
                                // opacity alone is what let the workspaces stay on
                                // screen behind them.
                                active: root.visible && !GlobalStates.searchOnlyMode && !GlobalStates.searchCenterMode && !Config.options.search.suggestions.enable && (Config?.options.overview.enable ?? true) && !root.isScrollingLayout && !root.searchPanelOwned
                                // Driven by the reveal progress alone. Gating this on
                                // `overviewShouldShow` too meant a panel that opened
                                // without ever changing the query could leave the grid
                                // on screen behind it.
                                opacity: searchWidgetWrapper.slideOpacity * root.overviewFadeProgress

                                layer.enabled: overviewLoader.opacity < 0.999
                                layer.effect: MultiEffect {
                                    blurEnabled: overviewLoader.opacity < 0.999
                                    blurMax: 64.0
                                    blur: (1.0 - Math.min(1.0, Math.max(0.0, overviewLoader.opacity))) * 1.0
                                }

                                transform: [
                                    Translate {
                                        y: root.animStyle === "zoom" ? ((1.0 - Math.min(1.0, Math.max(0.0, overviewLoader.opacity))) * (root.isBottomBar ? 30 : -30)) : searchWidgetWrapper.slideY + ((1.0 - root.overviewRevealProgress) * (root.isBottomBar ? -30 : 30))
                                    },
                                    Scale {
                                        origin.x: overviewLoader.implicitWidth / 2
                                        origin.y: overviewLoader.implicitHeight / 2
                                        xScale: root.animStyle === "zoom" ? (0.92 + 0.08 * Math.min(1.0, Math.max(0.0, overviewLoader.opacity))) : 1.0
                                        yScale: root.animStyle === "zoom" ? (0.92 + 0.08 * Math.min(1.0, Math.max(0.0, overviewLoader.opacity))) : 1.0
                                    }
                                ]

                                sourceComponent: OverviewWidget {
                                    panelWindow: root
                                    visible: root.overviewFadeProgress > 0.001
                                    monitorIndex: root.monitorIndex
                                }
                            }

                            Loader { // Scrolling overview
                                id: scrollingOverviewLoader
                                anchors.fill: parent
                                active: root.visible && !GlobalStates.searchOnlyMode && !GlobalStates.searchCenterMode && !Config.options.search.suggestions.enable && (Config?.options.overview.enable ?? true) && root.isScrollingLayout && !root.searchPanelOwned
                                opacity: searchWidgetWrapper.slideOpacity * root.overviewFadeProgress

                                layer.enabled: scrollingOverviewLoader.opacity < 0.999
                                layer.effect: MultiEffect {
                                    blurEnabled: scrollingOverviewLoader.opacity < 0.999
                                    blurMax: 64.0
                                    blur: (1.0 - Math.min(1.0, Math.max(0.0, scrollingOverviewLoader.opacity))) * 1.0
                                }

                                transform: [
                                    Translate {
                                        y: root.animStyle === "zoom" ? ((1.0 - Math.min(1.0, Math.max(0.0, scrollingOverviewLoader.opacity))) * (root.isBottomBar ? 30 : -30)) : searchWidgetWrapper.slideY + ((1.0 - root.overviewRevealProgress) * (root.isBottomBar ? -30 : 30))
                                    },
                                    Scale {
                                        origin.x: scrollingOverviewLoader.width / 2
                                        origin.y: scrollingOverviewLoader.height / 2
                                        xScale: root.animStyle === "zoom" ? (0.92 + 0.08 * Math.min(1.0, Math.max(0.0, scrollingOverviewLoader.opacity))) : 1.0
                                        yScale: root.animStyle === "zoom" ? (0.92 + 0.08 * Math.min(1.0, Math.max(0.0, scrollingOverviewLoader.opacity))) : 1.0
                                    }
                                ]

                                sourceComponent: ScrollingOverviewWidget {
                                    anchors.fill: parent
                                    panelWindow: root
                                    visible: root.overviewFadeProgress > 0.001
                                    monitorIndex: root.monitorIndex
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    onSetSearchingTextRequested: text => {
        if (GlobalStates.searchConnectActive || GlobalStates.floatingNotchOwnsSearch) {
            GlobalStates.activeSearchQuery = text;
        }
    }

    function togglePrefixedSearch(prefix) {
        GlobalStates.superReleaseMightTrigger = false;
        if (GlobalStates.overviewOpen && overviewScope.dontAutoCancelSearch && LauncherSearch.query.startsWith(prefix)) {
            GlobalStates.overviewOpen = false;
            return;
        }
        overviewScope.dontAutoCancelSearch = true;
        if (GlobalStates.overviewOpen) {
            overviewScope.setSearchingTextRequested(prefix);
        } else {
            // The default overview is lazy-loaded. Keep the prefix until its
            // PanelWindow exists so the first shortcut press is not lost.
            GlobalStates.activeSearchQuery = prefix;
            GlobalStates.overviewOpen = true;
        }
    }

    function toggleClipboard() {
        togglePrefixedSearch(Config.options.search.prefix.clipboard);
    }

    function toggleEmojis() {
        togglePrefixedSearch(Config.options.search.prefix.emojis);
    }

    function toggleBluetooth() {
        togglePrefixedSearch(Config.options.search.prefix.bluetooth);
    }

    function toggleMaterialSymbols() {
        togglePrefixedSearch(Config.options.search.prefix.materialSymbols);
    }

    function toggleTranslator() {
        togglePrefixedSearch(Config.options.search.prefix.translator);
    }

    function toggleTypingTest() {
        togglePrefixedSearch(Config.options.search.prefix.typingTest);
    }

    function toggleAi() {
        if (!Ai.enabled)
            return;
        togglePrefixedSearch(Config.options.search.prefix.ai);
    }

    IpcHandler {
        target: "search"

        function toggle() {
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        }
        function workspacesToggle() {
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        }
        function close() {
            GlobalStates.overviewOpen = false;
        }
        function open() {
            GlobalStates.overviewOpen = true;
        }
        function setQuery(text: string): void {
            overviewScope.setSearchingTextRequested(text);
        }
        function toggleReleaseInterrupt() {
            GlobalStates.superReleaseMightTrigger = false;
        }
        function clipboardToggle() {
            GlobalStates.superReleaseMightTrigger = false;
            overviewScope.toggleClipboard();
        }
        function bluetoothToggle() {
            GlobalStates.superReleaseMightTrigger = false;
            overviewScope.toggleBluetooth();
        }
        function materialSymbolsToggle() {
            GlobalStates.superReleaseMightTrigger = false;
            overviewScope.toggleMaterialSymbols();
        }
        function translatorToggle() {
            GlobalStates.superReleaseMightTrigger = false;
            overviewScope.toggleTranslator();
        }
        function typingTestToggle() {
            GlobalStates.superReleaseMightTrigger = false;
            overviewScope.toggleTypingTest();
        }
        function aiToggle() {
            GlobalStates.superReleaseMightTrigger = false;
            overviewScope.toggleAi();
        }
        function searchOnlyToggle() {
            GlobalStates.superReleaseMightTrigger = false;
            GlobalStates.toggleSearchOnly();
        }
    }

    GlobalShortcut {
        name: "searchToggle"
        description: "Toggles search on press"

        onPressed: {
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        }
    }
    GlobalShortcut {
        name: "overviewWorkspacesClose"
        description: "Closes overview on press"

        onPressed: {
            GlobalStates.overviewOpen = false;
        }
    }
    GlobalShortcut {
        name: "overviewWorkspacesToggle"
        description: "Toggles overview on press"

        onPressed: {
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        }
    }
    GlobalShortcut {
        name: "searchOnlyToggle"
        description: "Toggles search only mode on press"

        onPressed: {
            GlobalStates.toggleSearchOnly();
        }
    }
    GlobalShortcut {
        name: "searchToggleRelease"
        description: "Toggles search on release"

        // Debounce: prevents double-fire from the global shortcuts protocol.
        // When SUPER_L is bound as both modifier (SUPER) and trigger key (SUPER_L),
        // the compositor sends `released` twice: once for the key release and once
        // for the modifier state change. The 50ms window catches both without
        // affecting normal press-release cycles.
        property int _lastToggleTime: 0

        onPressed: {
            GlobalStates.superReleaseMightTrigger = true;
        }

        onReleased: {
            const now = Date.now();
            if (now - _lastToggleTime < 50)
                return;
            _lastToggleTime = now;

            if (!GlobalStates.superReleaseMightTrigger) {
                GlobalStates.superReleaseMightTrigger = true;
                return;
            }
            // Inside a panel, Super is a step back to the plain search rather
            // than a step out of the launcher entirely. Leaving the panel clears
            // the flag synchronously, so a flag that survives the request was
            // stale and the press still belongs to the Overview.
            if (GlobalStates.overviewOpen && GlobalStates.searchPanelActive) {
                overviewScope.exitActivePanelRequested();
                if (!GlobalStates.searchPanelActive)
                    return;
            }
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        }
    }
    GlobalShortcut {
        name: "searchToggleReleaseInterrupt"
        description: "Interrupts possibility of search being toggled on release. " + "This is necessary because GlobalShortcut.onReleased in quickshell triggers whether or not you press something else while holding the key. " + "To make sure this works consistently, use binditn = MODKEYS, catchall in an automatically triggered submap that includes everything."

        onPressed: {
            GlobalStates.superReleaseMightTrigger = false;
        }
    }
    GlobalShortcut {
        name: "overviewClipboardToggle"
        description: "Toggle clipboard query on overview widget"

        onPressed: {
            GlobalStates.superReleaseMightTrigger = false;
            overviewScope.toggleClipboard();
        }
    }

    GlobalShortcut {
        name: "overviewEmojiToggle"
        description: "Toggle emoji query on overview widget"

        onPressed: {
            GlobalStates.superReleaseMightTrigger = false;
            overviewScope.toggleEmojis();
        }
    }

    GlobalShortcut {
        name: "overviewMaterialSymbolsToggle"
        description: "Toggle Material Symbols search on overview widget"

        onPressed: {
            GlobalStates.superReleaseMightTrigger = false;
            overviewScope.toggleMaterialSymbols();
        }
    }

    GlobalShortcut {
        name: "overviewTranslatorToggle"
        description: "Toggle Translator search on overview widget"

        onPressed: {
            GlobalStates.superReleaseMightTrigger = false;
            overviewScope.toggleTranslator();
        }
    }

    GlobalShortcut {
        name: "overviewCommandsOpen"
        description: "Open Search directly in the Commands panel"

        onPressed: {
            GlobalStates.superReleaseMightTrigger = false;
            GlobalStates.openSearchPanel("commands");
        }
    }

    GlobalShortcut {
        name: "overviewAiToggle"
        description: "Toggle AI chat on overview widget"

        onPressed: {
            GlobalStates.superReleaseMightTrigger = false;
            overviewScope.toggleAi();
        }
    }
}
