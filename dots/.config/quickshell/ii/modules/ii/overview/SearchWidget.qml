pragma ComponentBehavior: Bound

import Qt.labs.synchronizer
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Item {
    id: root
    width: implicitWidth
    height: implicitHeight
    focus: true
    signal requestToggleActions
    property bool inNotchMode: false

    readonly property string xdgConfigHome: Directories.config
    readonly property int typingDebounceInterval: 200
    readonly property int typingResultLimit: {
        const query = LauncherSearch.query;
        if (!query)
            return 15;
        const isPrefixed = query.startsWith(Config.options.search.prefix.app) || query.startsWith(Config.options.search.prefix.fileBrowser) || query.startsWith(Config.options.search.prefix.emojis) || query.startsWith(Config.options.search.prefix.windowSearch) || query.startsWith(Config.options.search.prefix.fileSearch);
        return isPrefixed ? 500 : 15;
    }
    readonly property bool isSearching: false
    readonly property bool showSkeletons: false

    property int loadedResultsCount: 50

    function getFilteredResultsCount() {
        const results = LauncherSearch.results;
        const q = LauncherSearch.query.trim().toLowerCase();
        let count = 0;
        for (let i = 0; i < results.length; i++) {
            const item = results[i];
            if (item && (!(Config.options.search.alwaysListApps || q !== "" || !Config.options.search.showNowPlayingBubble) || item.key !== "mpris:now-playing"))
                count++;
        }
        return count;
    }

    function loadMoreResults() {
        const total = root.getFilteredResultsCount();
        if (loadedResultsCount < total) {
            loadedResultsCount = Math.min(total, loadedResultsCount + 50);
            appResults.applyResultDiff(root.processResults(LauncherSearch.results));
        }
    }

    property string searchingText: LauncherSearch.query
    readonly property bool isClipboardMode: root.searchingText.startsWith(Config.options.search.prefix.clipboard)
    readonly property bool isBluetoothMode: root.searchingText.startsWith(Config.options.search.prefix.bluetooth)
    readonly property bool isTranslatorMode: root.searchingText.startsWith(Config.options.search.prefix.translator)
    readonly property bool isMediaDownloaderMode: Config.options.mediaDownloader.enabled && root.searchingText.startsWith(Config.options.search.prefix.mediaDownloader)
    readonly property bool isAnySpecialMode: root.isClipboardMode || root.isBluetoothMode || root.isTranslatorMode || root.isMediaDownloaderMode
    readonly property bool alwaysListAppsMode: Config.options.search.alwaysListApps && !root.isAnySpecialMode
    property bool showResults: searchingText != "" || isAnySpecialMode || alwaysListAppsMode || (searchingText === "" && LauncherSearch.results.length > 0)
    property string overviewPosition: Config.options.overview?.position ?? ""
    

    // Suppress item transitions during panel open/close to avoid flicker
    property bool suppressItemTransitions: true



    Connections {
        target: GlobalStates
        function onOverviewOpenChanged() {
            if (GlobalStates.overviewOpen) {
                // Cancel pending clear — open before timer fired
                clearModelTimer.stop();
                // Suppress transitions while panel is animating open
                root.suppressItemTransitions = true;
                // Wipe stale results immediately so panel opens empty
                resultModel.clear();
                root.loadedResultsCount = 50;
                if (root.alwaysListAppsMode) {
                    Qt.callLater(() => {
                        // Show first 15 immediately for instant response,
                        // then load the rest after a short delay
                        const allResults = LauncherSearch.results;
                        appResults.applyResultDiff(allResults.slice(0, 15));
                        root.focusFirstItem();
                        resultsDebounce.restart();
                    });
                }
                // Re-enable transitions after open animation
                enableTransitionsTimer.restart();
            } else {
                resultsDebounce.stop();
                // Suppress transitions while panel animates closed
                root.suppressItemTransitions = true;
                // Delay clear until after close animation to avoid remove-transition flicker
                clearModelTimer.restart();
            }
        }
    }

    Connections {
        target: LauncherSearch
        function onRequestOpenSettings() {
            GlobalStates.overviewOpen = false;
            Qt.callLater(() => {
                GlobalStates.policiesPanelOpen = true;
            });
        }
    }
    implicitWidth: searchWidgetContent.implicitWidth + (GlobalStates.searchConnectActive ? 0 : Appearance.sizes.elevationMargin * 2)
    implicitHeight: searchWidgetContent.implicitHeight + (GlobalStates.searchConnectActive ? 0 : Appearance.sizes.elevationMargin * 2)

    // Signals to DynamicIslandStyle that the open animation is stable (no active resize)
    // When true, the DI pill disables its own behaviors and follows SearchWidget's animations directly.
    // In notch mode we always return false so the DI pill remains responsible for all animations.
    readonly property bool openStateStable: root.inNotchMode ? false : (!searchHeightBehavior.animation.running && !searchWidthBehavior.animation.running)

    function focusFirstItem() {
        if (root.isBluetoothMode) {} else if (root.isClipboardMode) {} else if (root.isTranslatorMode) {
            if (translatorPanelLoader.item)
                translatorPanelLoader.item.focusInput();
        } else if (root.isMediaDownloaderMode) {
            if (mediaDownloaderPanelLoader.item)
                mediaDownloaderPanelLoader.item.focusInput();
        } else {
            appResults.currentIndex = 0;
        }
    }

    function focusSearchInput() {
        searchBar.forceFocus();
    }

    function disableExpandAnimation() {
        searchBar.animateWidth = false;
    }

    function cancelSearch() {
        searchBar.searchInput.selectAll();
        LauncherSearch.query = "";
        searchBar.animateWidth = true;
    }

    function setSearchingText(text) {
        searchBar.searchInput.text = text;
        LauncherSearch.query = text;
    }

    function processResults(results) {
        const q = LauncherSearch.query.trim().toLowerCase();
        const excludeMpris = Config.options.search.alwaysListApps || q !== "" || !Config.options.search.showNowPlayingBubble;
        const out = [];
        const limit = root.loadedResultsCount;
        for (let i = 0; i < results.length && out.length < limit; i++) {
            const item = results[i];
            if (item && (!excludeMpris || item.key !== "mpris:now-playing"))
                out.push(item);
        }
        return out;
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_K && (event.modifiers & Qt.ControlModifier)) {
            if (appResults.visible) {
                root.requestToggleActions();
                event.accepted = true;
            }
            return;
        }

        // Prevent Esc and Backspace from registering
        if (event.key === Qt.Key_Escape)
            return;

        // Handle Backspace: focus and delete character if not focused
        if (event.key === Qt.Key_Backspace) {
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
        if (event.text && event.text.length === 1 && event.key !== Qt.Key_Enter && event.key !== Qt.Key_Return && event.key !== Qt.Key_Delete && event.text.charCodeAt(0) >= 0x20) // ignore control chars like Backspace, Tab, etc.
        {
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

    StyledRectangularShadow {
        target: searchWidgetContent
        visible: !GlobalStates.searchConnectActive
    }
    Rectangle {
        id: searchWidgetContent
        anchors.centerIn: parent
        width: GlobalStates.searchConnectActive ? parent.width : implicitWidth
        height: GlobalStates.searchConnectActive ? parent.height : implicitHeight
        clip: true
        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: searchWidgetContent.width
                height: searchWidgetContent.height
                radius: searchWidgetContent.radius
            }
        }
        implicitWidth: {
            let baseW = 0;
            if (root.isBluetoothMode)
                baseW = Config.options.search.clipboard.panelWidth ?? 860;
            else if (root.isClipboardMode)
                baseW = Config.options.search.clipboard.panelWidth ?? 860;
            else if (root.isTranslatorMode)
                baseW = Config.options.search.clipboard.panelWidth ?? 860;
            else if (root.isMediaDownloaderMode)
                baseW = Config.options.search.clipboard.panelWidth ?? 860;
            else
                baseW = Math.max(Config.options.search.baseWidth, gridLayout.implicitWidth);

            // In notch mode, the DI container already provides horizontal spacing.
            // Only add the 48px offset in non-notch connect mode.
            if (GlobalStates.searchConnectActive && !root.inNotchMode)
                return baseW + 48;
            return baseW;
        }
        implicitHeight: {
            let bottomMargin = GlobalStates.searchConnectActive ? 16 : 10;
            if (root.isBluetoothMode)
                return bluetoothPanelLoader.item ? bluetoothPanelLoader.item.implicitHeight + searchBar.height + searchBar.verticalPadding * 2 + bottomMargin : 520;
            if (root.isClipboardMode)
                return clipboardPanelLoader.item ? clipboardPanelLoader.item.implicitHeight + searchBar.height + searchBar.verticalPadding * 2 + bottomMargin : 560;
            if (root.isTranslatorMode)
                return translatorPanelLoader.item ? translatorPanelLoader.item.implicitHeight + searchBar.height + searchBar.verticalPadding * 2 + bottomMargin : 520;
            if (root.isMediaDownloaderMode)
                return mediaDownloaderPanelLoader.item ? mediaDownloaderPanelLoader.item.implicitHeight + searchBar.height + searchBar.verticalPadding * 2 + bottomMargin : 560;
            return gridLayout.implicitHeight;
        }
        radius: Appearance.rounding.windowRounding
        color: GlobalStates.searchConnectActive ? "transparent" : Appearance.colors.colBackgroundSurfaceContainer

        Behavior on implicitWidth {
            id: searchWidthBehavior
            // In notch mode, DI pill drives sizing — disable internal animation to avoid double-animation
            enabled: !root.inNotchMode
            NumberAnimation {
                duration: Appearance.animation.elementMove.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
            }
        }

        Behavior on implicitHeight {
            id: searchHeightBehavior
            // In notch mode, DI pill drives sizing — disable internal animation to avoid double-animation
            enabled: !root.inNotchMode
            NumberAnimation {
                duration: Appearance.animation.elementMove.duration
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
            clip: true

            SearchBar {
                id: searchBar
                property real verticalPadding: 4
                Layout.fillWidth: true
                Layout.leftMargin: 10
                Layout.rightMargin: 10
                Layout.topMargin: verticalPadding
                Layout.bottomMargin: verticalPadding
                Layout.row: root.overviewPosition == "bottom" ? 1 : 0
                animateWidth: true
                Synchronizer on searchingText {
                    property alias source: root.searchingText
                }

                clipboardMode: root.isClipboardMode || root.isBluetoothMode || root.isTranslatorMode || root.isMediaDownloaderMode
                clipboardWidth: 830
                currentResultIndex: appResults.currentIndex
                isTranslatorPanelFocused: root.isTranslatorMode && translatorPanelLoader.item && translatorPanelLoader.item.focusedControlIndex !== -1
                isMediaDownloaderPanelFocused: root.isMediaDownloaderMode && mediaDownloaderPanelLoader.item && mediaDownloaderPanelLoader.item.focusedControlIndex !== -1

                onCtrlKPressed: {
                    if (appResults.visible) {
                        root.requestToggleActions();
                    }
                }

                onNavigateUp: {
                    if (root.isBluetoothMode) {
                        if (bluetoothPanelLoader.item)
                            bluetoothPanelLoader.item.navigateUp();
                    } else if (root.isClipboardMode) {
                        if (clipboardPanelLoader.item)
                            clipboardPanelLoader.item.navigateUp();
                    } else if (root.isTranslatorMode) {
                        if (translatorPanelLoader.item)
                            translatorPanelLoader.item.navigateUp();
                    } else if (root.isMediaDownloaderMode) {
                        if (mediaDownloaderPanelLoader.item)
                            mediaDownloaderPanelLoader.item.navigateUp();
                    } else {
                        if (appResults.count > 0 && appResults.currentIndex > 0)
                            appResults.currentIndex--;
                    }
                }

                onNavigateDown: {
                    if (root.isBluetoothMode) {
                        if (bluetoothPanelLoader.item)
                            bluetoothPanelLoader.item.navigateDown();
                    } else if (root.isClipboardMode) {
                        if (clipboardPanelLoader.item)
                            clipboardPanelLoader.item.navigateDown();
                    } else if (root.isTranslatorMode) {
                        if (translatorPanelLoader.item)
                            translatorPanelLoader.item.navigateDown();
                    } else if (root.isMediaDownloaderMode) {
                        if (mediaDownloaderPanelLoader.item)
                            mediaDownloaderPanelLoader.item.navigateDown();
                    } else {
                        if (appResults.count > 0 && appResults.currentIndex < appResults.count - 1)
                            appResults.currentIndex++;
                    }
                }

                onNavigateLeft: {
                    if (root.isBluetoothMode && bluetoothPanelLoader.item)
                        bluetoothPanelLoader.item.navigateLeft();
                    else if (root.isClipboardMode && clipboardPanelLoader.item)
                        clipboardPanelLoader.item.navigateLeft();
                    else if (root.isTranslatorMode && translatorPanelLoader.item)
                        translatorPanelLoader.item.navigateLeft();
                    else if (root.isMediaDownloaderMode && mediaDownloaderPanelLoader.item)
                        mediaDownloaderPanelLoader.item.navigateLeft();
                }

                onNavigateRight: {
                    if (root.isBluetoothMode && bluetoothPanelLoader.item)
                        bluetoothPanelLoader.item.navigateRight();
                    else if (root.isClipboardMode && clipboardPanelLoader.item)
                        clipboardPanelLoader.item.navigateRight();
                    else if (root.isTranslatorMode && translatorPanelLoader.item)
                        translatorPanelLoader.item.navigateRight();
                    else if (root.isMediaDownloaderMode && mediaDownloaderPanelLoader.item)
                        mediaDownloaderPanelLoader.item.navigateRight();
                }

                onActivate: {
                    if (root.isBluetoothMode && bluetoothPanelLoader.item)
                        bluetoothPanelLoader.item.activateSelected();
                    else if (root.isClipboardMode && clipboardPanelLoader.item)
                        clipboardPanelLoader.item.activateSelected();
                    else if (root.isTranslatorMode && translatorPanelLoader.item)
                        translatorPanelLoader.item.activateSelected();
                    else if (root.isMediaDownloaderMode && mediaDownloaderPanelLoader.item)
                        mediaDownloaderPanelLoader.item.activateSelected();
                }

                onDeleteSelected: {
                    if (root.isBluetoothMode && bluetoothPanelLoader.item) {
                        bluetoothPanelLoader.item.activateSelected();
                    } else if (root.isClipboardMode && clipboardPanelLoader.item) {
                        clipboardPanelLoader.item.activateSelected();
                    } else if (root.isTranslatorMode && translatorPanelLoader.item) {
                        translatorPanelLoader.item.activateSelected();
                    } else if (root.isMediaDownloaderMode && mediaDownloaderPanelLoader.item) {
                        mediaDownloaderPanelLoader.item.activateSelected();
                    }
                }
            }

            Item {
                // Use opacity-driven visibility so results fade out before collapsing on close
                readonly property bool resultsActive: root.showResults && !root.isAnySpecialMode
                opacity: resultsActive ? 1.0 : 0.0
                visible: opacity > 0.01
                Layout.fillWidth: true
                implicitHeight: root.showSkeletons ? searchSkeletons.implicitHeight + (GlobalStates.searchConnectActive ? 16 : 20) : Math.min(600, appResults.contentHeight + appResults.topMargin + appResults.bottomMargin)
                Layout.row: root.overviewPosition == "bottom" ? 0 : 1

                Behavior on opacity {
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                    }
                }

                Behavior on implicitHeight {
                    // Disabled during active debounce to avoid layout thrashing
                    // while the user is still typing rapidly
                    enabled: !resultsDebounce.running
                    NumberAnimation {
                        duration: Appearance.animation.elementMove.duration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                    }
                }

                ListView {
                    id: appResults
                    anchors.fill: parent
                    visible: opacity > 0
                    opacity: root.showSkeletons ? 0.0 : 1.0
                    Behavior on opacity {
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveFast.duration
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Appearance.animationCurves.expressiveEffects
                        }
                    }
                    clip: true
                    topMargin: 10
                    bottomMargin: GlobalStates.searchConnectActive ? 16 : 10
                    spacing: 2
                    KeyNavigation.up: searchBar
                    highlightMoveDuration: 100

                    layer.enabled: root.searchingText != "" && appResults.count > 0
                    layer.effect: OpacityMask {
                        maskSource: Item {
                            id: maskRoot
                            width: appResults.width
                            height: appResults.height

                            property color topFadeColor: {
                                if (appResults.currentItem) {
                                    const visY = appResults.currentItem.y - appResults.contentY;
                                    if (visY <= appResults.topMargin + 36) return "white";
                                }
                                return appResults.atYBeginning ? "white" : "transparent";
                            }
                            property color bottomFadeColor: {
                                if (appResults.currentItem) {
                                    const visBottom = appResults.currentItem.y - appResults.contentY + appResults.currentItem.height;
                                    if (visBottom >= appResults.height - appResults.bottomMargin - 36) return "white";
                                }
                                return appResults.atYEnd ? "white" : "transparent";
                            }

                            Behavior on topFadeColor {
                                ColorAnimation {
                                    duration: Appearance.animation.elementMoveFast.duration
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                                }
                            }
                            Behavior on bottomFadeColor {
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
                        NumberAnimation {
                            id: scrollAnim
                            alwaysRunToEnd: true
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
                        if (currentIndex >= count - 5 && count < root.getFilteredResultsCount()) {
                            root.loadMoreResults();
                        }
                    }

                    // ── Diff-based model update: triggers move/add/remove transitions ──
                    function applyResultDiff(newItems) {
                        // Build lookup of current keys in order
                        var oldKeys = [];
                        for (var i = 0; i < resultModel.count; i++)
                            oldKeys.push(resultModel.get(i).key);

                        var newKeys = newItems.map(function(x) { return x.key; });

                        // 1. Remove items no longer in newKeys
                        var toRemove = [];
                        for (var i = 0; i < oldKeys.length; i++) {
                            if (newKeys.indexOf(oldKeys[i]) === -1)
                                toRemove.push(oldKeys[i]);
                        }
                        for (var ri = 0; ri < toRemove.length; ri++) {
                            for (var j = 0; j < resultModel.count; j++) {
                                if (resultModel.get(j).key === toRemove[ri]) {
                                    resultModel.remove(j);
                                    break;
                                }
                            }
                        }

                        // 2. Insert new items not yet in model
                        var currentKeys = [];
                        for (var i = 0; i < resultModel.count; i++)
                            currentKeys.push(resultModel.get(i).key);

                        for (var ni = 0; ni < newItems.length; ni++) {
                            var item = newItems[ni];
                            if (currentKeys.indexOf(item.key) === -1) {
                                var insertAt = Math.min(ni, resultModel.count);
                                resultModel.insert(insertAt, {
                                    key: item.key,
                                    modelRef: item
                                });
                                currentKeys.splice(insertAt, 0, item.key);
                            }
                        }

                        // 3. Move items into correct order
                        for (var mi = 0; mi < newKeys.length; mi++) {
                            var currentPos = -1;
                            for (var ci = 0; ci < resultModel.count; ci++) {
                                if (resultModel.get(ci).key === newKeys[mi]) {
                                    currentPos = ci;
                                    break;
                                }
                            }
                            if (currentPos !== -1 && currentPos !== mi) {
                                resultModel.move(currentPos, mi, 1);
                            }
                        }

                        // 4. Sync model data (update modelRef for any changed item)
                        for (var si = 0; si < newItems.length && si < resultModel.count; si++) {
                            resultModel.setProperty(si, "modelRef", newItems[si]);
                        }
                    }

                    Connections {
                        target: root
                        function onSearchingTextChanged() {
                            root.loadedResultsCount = 50;
                            if (appResults.count > 0)
                                appResults.currentIndex = 0;
                            // User is typing — enable item transitions now
                            if (root.searchingText !== "")
                                root.suppressItemTransitions = false;
                        }
                    }

                    // Debounce timer: delivers full results 150ms after the last
                    // results change, avoiding per-keystroke full list recomputation
                    Timer {
                        id: resultsDebounce
                        interval: 150
                        repeat: false
                        onTriggered: {
                            appResults.applyResultDiff(root.processResults(LauncherSearch.results));
                        }
                    }

                    Connections {
                        target: LauncherSearch
                        function onResultsChanged() {
                            root.loadedResultsCount = 50;
                            // Immediately show first 15 results for snappy visual feedback
                            const immediate = root.processResults(LauncherSearch.results);
                            const quickSlice = immediate.length > 15 ? immediate.slice(0, 15) : immediate;
                            appResults.applyResultDiff(quickSlice);
                            root.focusFirstItem();
                            // Schedule full result delivery after debounce
                            if (immediate.length > 15)
                                resultsDebounce.restart();
                        }
                    }

                    model: ListModel {
                        id: resultModel
                    }

                    Component.onCompleted: {
                        applyResultDiff(root.processResults(LauncherSearch.results));
                    }

                    delegate: SearchItem {
                        id: searchItem
                        required property int index
                        listIndex: index
                        listCurrentIndex: appResults.currentIndex
                        required property var modelData
                        anchors.left: parent?.left
                        anchors.right: parent?.right
                        // modelData is {key, modelRef} from ListModel — pass the actual result object
                        entry: modelData.modelRef
                        query: StringUtils.cleanOnePrefix(root.searchingText, [Config.options.search.prefix.action, Config.options.search.prefix.app, Config.options.search.prefix.clipboard, Config.options.search.prefix.emojis, Config.options.search.prefix.math, Config.options.search.prefix.shellCommand, Config.options.search.prefix.webSearch])

                        // Animate y when ListView repositions this delegate (via move/displaced)
                        Behavior on y {
                            NumberAnimation {
                                duration: 220
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Appearance.animationCurves.emphasized
                            }
                        }

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
                            } else if (event.key === Qt.Key_Tab) {
                                if (searchItem.actionPanelOpen)
                                    return;
                                if (LauncherSearch.results.length === 0)
                                    return;
                                const tabbedText = searchItem.modelData.name;
                                LauncherSearch.query = tabbedText;
                                searchBar.searchInput.text = tabbedText;
                                event.accepted = true;
                                root.focusSearchInput();
                            }
                        }
                    }

                    // ── Reorder animation: items jump to new positions as results change ──
                    move: Transition {
                        NumberAnimation {
                            properties: "y"
                            duration: root.suppressItemTransitions ? 0 : 220
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Appearance.animationCurves.emphasized
                        }
                    }

                    displaced: Transition {
                        NumberAnimation {
                            properties: "y"
                            duration: root.suppressItemTransitions ? 0 : 220
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Appearance.animationCurves.emphasized
                        }
                    }

                    add: Transition {
                        ParallelAnimation {
                            NumberAnimation {
                                property: "opacity"
                                from: 0.0; to: 1.0
                                duration: root.suppressItemTransitions ? 0 : 180
                                easing.type: Easing.OutQuad
                            }
                            NumberAnimation {
                                property: "y"
                                duration: root.suppressItemTransitions ? 0 : 220
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                            }
                        }
                    }

                    remove: Transition {
                        NumberAnimation {
                            property: "opacity"
                            to: 0.0
                            duration: root.suppressItemTransitions ? 0 : 120
                            easing.type: Easing.OutQuad
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

                            // Shimmer animation with wave phase shift
                            SequentialAnimation on opacity {
                                loops: Animation.Infinite
                                running: searchSkeletons.visible
                                NumberAnimation {
                                    from: 0.25
                                    to: 0.65
                                    duration: 600 + skeletonRow.index * 100
                                    easing.type: Easing.InOutQuad
                                }
                                NumberAnimation {
                                    from: 0.65
                                    to: 0.25
                                    duration: 600 + skeletonRow.index * 100
                                    easing.type: Easing.InOutQuad
                                }
                            }

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
                id: clipboardPanelLoader
                // Keep active during fade-out to prevent layout jumps mid-animation
                active: root.isClipboardMode || opacity > 0.01
                visible: opacity > 0.01
                Layout.fillWidth: true
                source: "ClipboardPanel.qml"
                Layout.row: root.overviewPosition == "bottom" ? 0 : 1

                opacity: root.isClipboardMode ? 1.0 : 0.0
                Behavior on opacity {
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                    }
                }

                Binding {
                    target: clipboardPanelLoader.item
                    property: "searchQuery"
                    value: StringUtils.cleanOnePrefix(root.searchingText, [Config.options.search.prefix.clipboard])
                    when: clipboardPanelLoader.status === Loader.Ready
                }
            }

            Loader {
                id: bluetoothPanelLoader
                // Keep active during fade-out to prevent layout jumps mid-animation
                active: root.isBluetoothMode || opacity > 0.01
                visible: opacity > 0.01
                Layout.fillWidth: true
                source: "BluetoothPanel.qml"
                Layout.row: root.overviewPosition == "bottom" ? 0 : 1

                opacity: root.isBluetoothMode ? 1.0 : 0.0
                Behavior on opacity {
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                    }
                }

                Binding {
                    target: bluetoothPanelLoader.item
                    property: "searchQuery"
                    value: StringUtils.cleanOnePrefix(root.searchingText, [Config.options.search.prefix.bluetooth])
                    when: bluetoothPanelLoader.status === Loader.Ready
                }
            }

            Loader {
                id: translatorPanelLoader
                // Keep active during fade-out to prevent layout jumps mid-animation
                active: root.isTranslatorMode || opacity > 0.01
                visible: opacity > 0.01
                Layout.fillWidth: true
                source: "TranslatorPanel.qml"
                Layout.row: root.overviewPosition == "bottom" ? 0 : 1

                opacity: root.isTranslatorMode ? 1.0 : 0.0
                Behavior on opacity {
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                    }
                }

                Binding {
                    target: translatorPanelLoader.item
                    property: "searchQuery"
                    value: StringUtils.cleanOnePrefix(root.searchingText, [Config.options.search.prefix.translator])
                    when: translatorPanelLoader.status === Loader.Ready
                }

                Connections {
                    target: translatorPanelLoader.item
                    ignoreUnknownSignals: true
                    function onRequestSetSearchQuery(query) {
                        root.setSearchingText(Config.options.search.prefix.translator + query);
                    }
                    function onRequestFocusSearchInput() {
                        root.focusSearchInput();
                    }
                }
            }

            Loader {
                id: mediaDownloaderPanelLoader
                // Keep active during fade-out to prevent layout jumps mid-animation
                active: root.isMediaDownloaderMode || opacity > 0.01
                visible: opacity > 0.01
                Layout.fillWidth: true
                source: "MediaDownloaderPanel.qml"
                Layout.row: root.overviewPosition == "bottom" ? 0 : 1

                opacity: root.isMediaDownloaderMode ? 1.0 : 0.0
                Behavior on opacity {
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                    }
                }

                Binding {
                    target: mediaDownloaderPanelLoader.item
                    property: "searchQuery"
                    value: StringUtils.cleanOnePrefix(root.searchingText, [Config.options.search.prefix.mediaDownloader])
                    when: mediaDownloaderPanelLoader.status === Loader.Ready
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
