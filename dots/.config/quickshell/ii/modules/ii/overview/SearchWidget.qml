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

    readonly property string xdgConfigHome: Directories.config
    readonly property int typingDebounceInterval: 200
    readonly property int typingResultLimit: {
        const query = LauncherSearch.query;
        if (!query)
            return 15;
        const isPrefixed = query.startsWith(Config.options.search.prefix.app) || query.startsWith(Config.options.search.prefix.fileBrowser) || query.startsWith(Config.options.search.prefix.emojis) || query.startsWith(Config.options.search.prefix.windowSearch) || query.startsWith(Config.options.search.prefix.fileSearch) || query.startsWith(Config.options.search.prefix.materialSymbols);
        return isPrefixed ? 500 : 15;
    }
    readonly property bool isSearching: false
    readonly property bool showSkeletons: false

    property int loadedResultsCount: 50
    property int maxSearchItems: 50
    property var allSearchResults: []
    property var searchResultMap: ({})
    property bool searchSlotsInitialized: false

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
            root.maxSearchItems = loadedResultsCount;
            Qt.callLater(() => {
                root.rebuildSearchResults();
            });
        }
    }

    property string searchingText: LauncherSearch.query
    property bool inNotchMode: false
    property bool openStateStable: false

    Timer {
        id: openStableTimer
        interval: 250
        onTriggered: root.openStateStable = true
    }

    Component.onCompleted: {
        if (GlobalStates.overviewOpen) {
            root.openStateStable = false;
            openStableTimer.restart();
            root.loadedResultsCount = 50;
            if (root.alwaysListAppsMode) {
                const allResults = LauncherSearch.results;
                root.allSearchResults = allResults.slice(0, 15);
                root.updateSearchSlots();
                root.focusFirstItem();
                resultsDebounce.restart();
            } else {
                root.rebuildSearchResults();
            }
        }
    }

    onImplicitHeightChanged: {
        if (GlobalStates.overviewOpen && (root.screen ? GlobalStates.activeSearchMonitor === root.screen.name : true)) {
            if (root.visible || root.inNotchMode) {
                GlobalStates.activeSearchHeight = implicitHeight;
            }
        }
    }

    onImplicitWidthChanged: {
        if (GlobalStates.overviewOpen && (root.screen ? GlobalStates.activeSearchMonitor === root.screen.name : true)) {
            if (root.visible || root.inNotchMode) {
                GlobalStates.activeSearchWidth = implicitWidth;
            }
        }
    }

    readonly property bool isClipboardMode: root.searchingText.startsWith(Config.options.search.prefix.clipboard)
    readonly property bool isBluetoothMode: root.searchingText.startsWith(Config.options.search.prefix.bluetooth)
    readonly property bool isTranslatorMode: root.searchingText.startsWith(Config.options.search.prefix.translator)
    readonly property bool isMediaDownloaderMode: Config.options.mediaDownloader.enabled && root.searchingText.startsWith(Config.options.search.prefix.mediaDownloader)
    readonly property bool isMaterialSymbolsMode: root.searchingText.startsWith(Config.options.search.prefix.materialSymbols)
    readonly property bool isAnySpecialMode: root.isClipboardMode || root.isBluetoothMode || root.isTranslatorMode || root.isMediaDownloaderMode || root.isMaterialSymbolsMode
    readonly property bool alwaysListAppsMode: Config.options.search.alwaysListApps && !root.isAnySpecialMode
    property bool showResults: searchingText != "" || isAnySpecialMode || alwaysListAppsMode || (searchingText === "" && LauncherSearch.results.length > 0)
    property string overviewPosition: Config.options.overview?.position ?? ""
    Connections {
        target: GlobalStates
        function onOverviewOpenChanged() {
            if (GlobalStates.overviewOpen) {
                root.openStateStable = false;
                openStableTimer.restart();

                if (root.visible || root.inNotchMode) {
                    if (root.screen ? GlobalStates.activeSearchMonitor === root.screen.name : true) {
                        GlobalStates.activeSearchHeight = root.implicitHeight;
                        GlobalStates.activeSearchWidth = root.implicitWidth;
                    }
                }

                root.loadedResultsCount = 50;
                Qt.callLater(() => {
                    root.focusSearchInput();
                });
                if (root.alwaysListAppsMode) {
                    Qt.callLater(() => {
                        const allResults = LauncherSearch.results;
                        root.allSearchResults = allResults.slice(0, 15);
                        root.updateSearchSlots();
                        root.focusFirstItem();
                        resultsDebounce.restart();
                    });
                } else {
                    Qt.callLater(() => {
                        root.rebuildSearchResults();
                    });
                }
            } else {
                root.openStateStable = false;
                openStableTimer.stop();
                resultsDebounce.stop();
                // cancelSearch is now handled at the end of the slide-out animation in Overview.qml
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
    implicitWidth: searchWidgetContent.implicitWidth + ((GlobalStates.searchConnectActive || root.inNotchMode) ? 0 : Appearance.sizes.elevationMargin * 2)
    implicitHeight: searchWidgetContent.implicitHeight + ((GlobalStates.searchConnectActive || root.inNotchMode) ? 0 : Appearance.sizes.elevationMargin * 2)

    function focusFirstItem() {
        if (root.isBluetoothMode) {} else if (root.isClipboardMode) {} else if (root.isTranslatorMode) {
            if (translatorPanelLoader.item)
                translatorPanelLoader.item.focusInput();
        } else if (root.isMediaDownloaderMode) {
            if (mediaDownloaderPanelLoader.item)
                mediaDownloaderPanelLoader.item.focusInput();
        } else if (root.isMaterialSymbolsMode) {
            if (materialSymbolsPanelLoader.item)
                materialSymbolsPanelLoader.item.focusInput();
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

    function updateSearchSlots() {
        const newUids = [];
        for (let i = 0; i < allSearchResults.length; i++) {
            newUids.push(allSearchResults[i].key);
        }

        const map = {};
        for (let i = 0; i < allSearchResults.length; i++) {
            map[allSearchResults[i].key] = allSearchResults[i];
        }
        searchResultMap = map;

        const slots = [];
        for (let i = 0; i < appResultsRepeater.count; i++) {
            slots.push(appResultsRepeater.itemAt(i));
        }

        const isInitial = !root.searchSlotsInitialized;

        const oldUids = [];
        for (let i = 0; i < slots.length; i++) {
            oldUids.push(slots[i] ? slots[i].uniqueId : "");
        }

        const slotToNewPos = {};
        const usedNewPositions = new Set();

        for (let slotIdx = 0; slotIdx < slots.length; slotIdx++) {
            const oldUid = oldUids[slotIdx];
            if (!oldUid)
                continue;
            const newPos = newUids.indexOf(oldUid);
            if (newPos >= 0) {
                slotToNewPos[slotIdx] = newPos;
                usedNewPositions.add(newPos);
            }
        }

        for (let newPos = 0; newPos < newUids.length; newPos++) {
            if (usedNewPositions.has(newPos))
                continue;
            for (let slotIdx = 0; slotIdx < slots.length; slotIdx++) {
                if (!(slotIdx in slotToNewPos)) {
                    slotToNewPos[slotIdx] = newPos;
                    usedNewPositions.add(newPos);
                    break;
                }
            }
        }

        for (let slotIdx = 0; slotIdx < slots.length; slotIdx++) {
            const slot = slots[slotIdx];
            if (!slot)
                continue;
            const newPos = slotToNewPos[slotIdx];
            if (newPos === undefined) {
                slot.currentPosition = -1;
                slot.uniqueId = "";
                slot.hasData = false;
                slot.positionAnimationEnabled = false;
            } else {
                const uid = newUids[newPos];
                const isPreserved = oldUids[slotIdx] === uid && oldUids[slotIdx] !== "";
                slot.currentPosition = newPos;
                slot.positionAnimationEnabled = !isInitial && isPreserved;
                if (!isPreserved) {
                    slot.uniqueId = uid;
                    slot.hasData = true;
                }
            }
        }

        if (isInitial) {
            root.searchSlotsInitialized = true;
        }

        updateSearchPositions();
    }

    function updateSearchPositions() {
        const slotEntries = [];
        for (let i = 0; i < appResultsRepeater.count; i++) {
            const slot = appResultsRepeater.itemAt(i);
            if (slot && slot.hasData) {
                slotEntries.push({
                    slot: slot,
                    pos: slot.currentPosition
                });
            }
        }

        appResults.count = slotEntries.length;

        slotEntries.sort(function (a, b) {
            return a.pos - b.pos;
        });

        const SPACING = 2;
        let yPos = appResults.topMargin;
        for (let i = 0; i < slotEntries.length; i++) {
            slotEntries[i].slot.yPos = yPos;
            yPos += slotEntries[i].slot.implicitHeight + SPACING;
        }
        appResults._contentAreaHeight = yPos + appResults.bottomMargin - SPACING;
    }

    function rebuildSearchResults() {
        allSearchResults = processResults(LauncherSearch.results);
        updateSearchSlots();
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_K && (event.modifiers & Qt.ControlModifier)) {
            if (appResults.visible) {
                root.requestToggleActions();
                event.accepted = true;
            }
            return;
        }

        if (event.key === Qt.Key_Escape) {
            GlobalStates.overviewOpen = false;
            event.accepted = true;
            return;
        }

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
        visible: !GlobalStates.searchConnectActive && !root.inNotchMode
    }
    Rectangle {
        id: searchWidgetContent
        anchors.centerIn: parent
        width: (GlobalStates.searchConnectActive || root.inNotchMode) ? parent.width : implicitWidth
        height: (GlobalStates.searchConnectActive || root.inNotchMode) ? parent.height : implicitHeight
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
            else if (root.isMaterialSymbolsMode)
                baseW = materialSymbolsPanelLoader.item ? materialSymbolsPanelLoader.item.implicitWidth : 560;
            else
                baseW = Math.max(Config.options.search.baseWidth, gridLayout.implicitWidth);

            if (GlobalStates.searchConnectActive)
                return baseW + 48;
            return baseW;
        }
        implicitHeight: {
            let bottomMargin = (GlobalStates.searchConnectActive && !root.inNotchMode) ? 16 : 0;
            if (root.isBluetoothMode)
                return bluetoothPanelLoader.item ? bluetoothPanelLoader.item.implicitHeight + searchBar.height + searchBar.verticalPadding * 2 + bottomMargin : 520;
            if (root.isClipboardMode)
                return clipboardPanelLoader.item ? clipboardPanelLoader.item.implicitHeight + searchBar.height + searchBar.verticalPadding * 2 + bottomMargin : 560;
            if (root.isTranslatorMode)
                return translatorPanelLoader.item ? translatorPanelLoader.item.implicitHeight + searchBar.height + searchBar.verticalPadding * 2 + bottomMargin : 520;
            if (root.isMediaDownloaderMode)
                return mediaDownloaderPanelLoader.item ? mediaDownloaderPanelLoader.item.implicitHeight + searchBar.height + searchBar.verticalPadding * 2 + bottomMargin : 560;
            if (root.isMaterialSymbolsMode)
                return materialSymbolsPanelLoader.item ? materialSymbolsPanelLoader.item.implicitHeight + searchBar.height + searchBar.verticalPadding * 2 + bottomMargin : 520;
            return gridLayout.implicitHeight;
        }
        radius: Appearance.rounding.windowRounding
        color: (GlobalStates.searchConnectActive || root.inNotchMode) ? "transparent" : Appearance.colors.colBackgroundSurfaceContainer

        Behavior on implicitWidth {
            id: searchWidthBehavior
            enabled: !root.inNotchMode
            NumberAnimation {
                duration: Appearance.animation.elementMove.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
            }
        }

        Behavior on implicitHeight {
            id: searchHeightBehavior
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

                clipboardMode: root.isClipboardMode || root.isBluetoothMode || root.isTranslatorMode || root.isMediaDownloaderMode || root.isMaterialSymbolsMode
                clipboardWidth: 830
                currentResultIndex: appResults.currentIndex
                isTranslatorPanelFocused: root.isTranslatorMode && translatorPanelLoader.item && translatorPanelLoader.item.focusedControlIndex !== -1
                isMediaDownloaderPanelFocused: root.isMediaDownloaderMode && mediaDownloaderPanelLoader.item && mediaDownloaderPanelLoader.item.focusedControlIndex !== -1
                isMaterialSymbolsPanelFocused: root.isMaterialSymbolsMode && materialSymbolsPanelLoader.item && materialSymbolsPanelLoader.item.focusedControlIndex !== -1

                onCtrlKPressed: {
                    if (appResults.visible) {
                        root.requestToggleActions();
                    }
                }

                onCopySvgPressed: {
                    if (root.isMaterialSymbolsMode && materialSymbolsPanelLoader.item) {
                        materialSymbolsPanelLoader.item.copyFocusedIconSvg();
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
                    } else if (root.isMaterialSymbolsMode) {
                        if (materialSymbolsPanelLoader.item)
                            materialSymbolsPanelLoader.item.navigateUp();
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
                    } else if (root.isMaterialSymbolsMode) {
                        if (materialSymbolsPanelLoader.item)
                            materialSymbolsPanelLoader.item.navigateDown();
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
                    else if (root.isMaterialSymbolsMode && materialSymbolsPanelLoader.item)
                        materialSymbolsPanelLoader.item.navigateLeft();
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
                    else if (root.isMaterialSymbolsMode && materialSymbolsPanelLoader.item)
                        materialSymbolsPanelLoader.item.navigateRight();
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
                    else if (root.isMaterialSymbolsMode && materialSymbolsPanelLoader.item)
                        materialSymbolsPanelLoader.item.activateSelected();
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
                    } else if (root.isMaterialSymbolsMode && materialSymbolsPanelLoader.item) {
                        materialSymbolsPanelLoader.item.activateSelected();
                    }
                }
            }

            Item {
                visible: root.showResults && !root.isAnySpecialMode
                Layout.fillWidth: true
                implicitHeight: root.showSkeletons ? searchSkeletons.implicitHeight + ((GlobalStates.searchConnectActive && !root.inNotchMode) ? 16 : 0) : Math.min(600, appResults.contentHeight + appResults.topMargin + appResults.bottomMargin)
                Layout.row: root.overviewPosition == "bottom" ? 0 : 1

                Behavior on implicitHeight {
                    // Disabled during active debounce to avoid layout thrashing
                    // while the user is still typing rapidly. Also disabled in notch mode
                    // since the notch parent container animates its height itself.
                    enabled: !resultsDebounce.running && !root.inNotchMode
                    NumberAnimation {
                        duration: Appearance.animation.elementMove.duration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                    }
                }

                Item {
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

                    // Backward-compatible properties (replaces ListView API)
                    property int currentIndex: 0
                    property int count: 0
                    readonly property real contentHeight: _contentAreaHeight
                    readonly property real topMargin: 10
                    readonly property real bottomMargin: (GlobalStates.searchConnectActive && !root.inNotchMode) ? 16 : 0
                    readonly property bool atYBeginning: appResultsFlick.contentY <= 0
                    readonly property bool atYEnd: appResultsFlick.contentY + appResultsFlick.height >= _contentAreaHeight
                    property real contentY: appResultsFlick.contentY
                    property real _contentAreaHeight: 0
                    property real _scrollTargetY: 0

                    onCurrentIndexChanged: {
                        if (currentIndex >= count - 5 && count < root.getFilteredResultsCount()) {
                            root.loadMoreResults();
                        }
                    }

                    readonly property Item currentItem: {
                        if (currentIndex < 0)
                            return null;
                        for (var i = 0; i < appResultsRepeater.count; i++) {
                            var s = appResultsRepeater.itemAt(i);
                            if (s && s.currentPosition === currentIndex && s.hasData) {
                                return s.searchItemRef;
                            }
                        }
                        return null;
                    }

                    function itemAtIndex(idx) {
                        for (var i = 0; i < appResultsRepeater.count; i++) {
                            var s = appResultsRepeater.itemAt(i);
                            if (s && s.currentPosition === idx && s.hasData) {
                                return s.searchItemRef;
                            }
                        }
                        return null;
                    }

                    Flickable {
                        id: appResultsFlick
                        anchors.fill: parent
                        clip: true

                        contentY: 0
                        contentHeight: appResults._contentAreaHeight

                        maximumFlickVelocity: 3500
                        boundsBehavior: Flickable.DragOverBounds
                        pixelAligned: true

                        // Touchpad and mouse scroll physics adjustments
                        property real touchpadScrollFactor: Config?.options.interactions.scrolling.touchpadScrollFactor ?? 100
                        property real mouseScrollFactor: Config?.options.interactions.scrolling.mouseScrollFactor ?? 50
                        property real mouseScrollDeltaThreshold: Config?.options.interactions.scrolling.mouseScrollDeltaThreshold ?? 120

                        MouseArea {
                            z: 99
                            visible: Config?.options.interactions.scrolling.fasterTouchpadScroll
                            anchors.fill: parent
                            acceptedButtons: Qt.NoButton
                            onWheel: function (wheelEvent) {
                                const delta = wheelEvent.angleDelta.y / appResultsFlick.mouseScrollDeltaThreshold;
                                var scrollFactor = Math.abs(wheelEvent.angleDelta.y) >= appResultsFlick.mouseScrollDeltaThreshold ? appResultsFlick.mouseScrollFactor : appResultsFlick.touchpadScrollFactor;

                                const maxY = Math.max(0, appResultsFlick.contentHeight - appResultsFlick.height);
                                const base = scrollAnim.running ? appResults._scrollTargetY : appResultsFlick.contentY;
                                var targetY = Math.max(0, Math.min(base - delta * scrollFactor, maxY));

                                appResults._scrollTargetY = targetY;
                                appResultsFlick.contentY = targetY;
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
                                appResults._scrollTargetY = contentY;
                            }
                        }

                        layer.enabled: root.searchingText != "" && appResults.count > 0
                        layer.effect: OpacityMask {
                            maskSource: Item {
                                id: maskRoot
                                width: appResultsFlick.width
                                height: appResultsFlick.height

                                property color topFadeColor: {
                                    var ci = appResults.currentItem;
                                    if (ci) {
                                        var parentSlot = ci.parent;
                                        if (parentSlot) {
                                            var visY = parentSlot.y - appResultsFlick.contentY;
                                            if (visY <= appResults.topMargin + 36)
                                                return "white";
                                        }
                                    }
                                    return appResults.atYBeginning ? "white" : "transparent";
                                }
                                property color bottomFadeColor: {
                                    var ci = appResults.currentItem;
                                    if (ci) {
                                        var parentSlot = ci.parent;
                                        if (parentSlot) {
                                            var visBottom = parentSlot.y - appResultsFlick.contentY + parentSlot.height;
                                            if (visBottom >= appResultsFlick.height - appResults.bottomMargin - 36)
                                                return "white";
                                        }
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

                        // Debounce timer: delivers full results 150ms after the last
                        // results change, avoiding per-keystroke full list recomputation
                        Timer {
                            id: resultsDebounce
                            interval: 150
                            repeat: false
                            onTriggered: {
                                root.rebuildSearchResults();
                            }
                        }

                        Item {
                            id: appResultsContainer
                            width: parent.width
                            height: appResults._contentAreaHeight

                            Repeater {
                                id: appResultsRepeater
                                model: root.maxSearchItems

                                delegate: Item {
                                    id: slotDelegate
                                    required property int index

                                    property bool positionAnimationEnabled: false
                                    property string uniqueId: ""
                                    property int currentPosition: -1
                                    property bool hasData: false
                                    property real yPos: 0

                                    readonly property var slotData: root.searchResultMap[uniqueId] || null

                                    y: yPos
                                    width: parent.width
                                    implicitHeight: hasData && searchItem ? searchItem.implicitHeight : 0
                                    height: implicitHeight
                                    visible: hasData
                                    opacity: hasData ? 1.0 : 0.0

                                    Behavior on opacity {
                                        NumberAnimation {
                                            duration: 180
                                            easing.type: Easing.BezierSpline
                                            easing.bezierCurve: Appearance.animationCurves.emphasized
                                        }
                                    }

                                    onUniqueIdChanged: {
                                        if (uniqueId !== "" && searchItem) {
                                            searchItem.replayEntryAnimation();
                                        }
                                    }

                                    readonly property Item searchItemRef: searchItem

                                    SearchItem {
                                        id: searchItem
                                        visible: slotDelegate.hasData
                                        anchors.left: parent.left
                                        anchors.right: parent.right

                                        entry: slotDelegate.slotData
                                        query: StringUtils.cleanOnePrefix(root.searchingText, [Config.options.search.prefix.action, Config.options.search.prefix.app, Config.options.search.prefix.clipboard, Config.options.search.prefix.emojis, Config.options.search.prefix.math, Config.options.search.prefix.shellCommand, Config.options.search.prefix.webSearch])
                                        listIndex: slotDelegate.currentPosition
                                        listCount: appResults.count
                                        listCurrentIndex: appResults.currentIndex
                                        openStateStable: root.openStateStable

                                        Connections {
                                            target: searchItem
                                            function onImplicitHeightChanged() {
                                                if (slotDelegate.hasData) {
                                                    Qt.callLater(root.updateSearchPositions);
                                                }
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
                                                const tabbedText = searchItem.entry ? searchItem.entry.name : "";
                                                LauncherSearch.query = tabbedText;
                                                searchBar.searchInput.text = tabbedText;
                                                event.accepted = true;
                                                root.focusSearchInput();
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Connections {
                        target: root
                        function onSearchingTextChanged() {
                            root.loadedResultsCount = 50;
                            root.maxSearchItems = 50;
                            appResultsFlick.contentY = 0;
                            if (appResults.count > 0)
                                appResults.currentIndex = 0;
                        }
                    }

                    Connections {
                        target: LauncherSearch
                        function onResultsChanged() {
                            root.loadedResultsCount = 50;
                            root.maxSearchItems = 50;
                            // Immediately show first 15 results for snappy visual feedback
                            const immediate = root.processResults(LauncherSearch.results);
                            const quickSlice = immediate.length > 15 ? immediate.slice(0, 15) : immediate;
                            root.allSearchResults = quickSlice;
                            root.updateSearchSlots();
                            root.focusFirstItem();
                            // Schedule full result delivery after debounce
                            if (immediate.length > 15)
                                resultsDebounce.restart();
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
                visible: root.isClipboardMode
                active: root.isClipboardMode
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
                visible: root.isBluetoothMode
                active: root.isBluetoothMode
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
                visible: root.isTranslatorMode
                active: root.isTranslatorMode
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
                visible: root.isMediaDownloaderMode
                active: root.isMediaDownloaderMode
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

            Loader {
                id: materialSymbolsPanelLoader
                visible: root.isMaterialSymbolsMode
                active: root.isMaterialSymbolsMode
                Layout.fillWidth: true
                source: "MaterialSymbolsPanel.qml"
                Layout.row: root.overviewPosition == "bottom" ? 0 : 1

                opacity: root.isMaterialSymbolsMode ? 1.0 : 0.0
                Behavior on opacity {
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                    }
                }

                Binding {
                    target: materialSymbolsPanelLoader.item
                    property: "searchQuery"
                    value: StringUtils.cleanOnePrefix(root.searchingText, [Config.options.search.prefix.materialSymbols])
                    when: materialSymbolsPanelLoader.status === Loader.Ready
                }

                Connections {
                    target: materialSymbolsPanelLoader.item
                    ignoreUnknownSignals: true
                    function onRequestFocusSearchInput() {
                        root.focusSearchInput();
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
