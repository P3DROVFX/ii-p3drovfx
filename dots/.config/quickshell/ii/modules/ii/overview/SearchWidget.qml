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
    signal requestToggleActions

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

    readonly property string artUrl: MprisController.artUrl || ""
    readonly property bool isLocalArt: artUrl.startsWith("file://")
    property string artDownloadLocation: Directories.coverArt
    property string artFileName: Qt.md5(artUrl)
    property string artFilePath: `${artDownloadLocation}/${artFileName}`
    property bool artDownloaded: false

    readonly property string artSource: {
        if (!artUrl) return "";
        if (isLocalArt) return artUrl;
        return artDownloaded ? Qt.resolvedUrl(artFilePath) : "";
    }

    onArtFilePathChanged: {
        if (!artUrl || artUrl.length === 0) {
            artDownloaded = false;
            return;
        }
        if (isLocalArt) {
            artDownloaded = true;
            return;
        }
        artDownloader.targetFile = artUrl;
        artDownloader.artFilePath = artFilePath;
        artDownloader.artTempPath = artFilePath + ".tmp";
        artDownloaded = false;
        artDownloader.running = true;
    }

    Process {
        id: artDownloader
        property string targetFile: root.artUrl
        property string artFilePath: root.artFilePath
        property string artTempPath: root.artFilePath + ".tmp"
        command: ["bash", "-c", `[ -f ${artFilePath} ] || (curl -4 -sSL '${targetFile}' -o '${artTempPath}' && mv '${artTempPath}' '${artFilePath}')`]
        onExited: {
            artDownloaded = true;
        }
    }

    function getFilteredResultsCount() {
        const results = LauncherSearch.results;
        const q = LauncherSearch.query.trim().toLowerCase();
        let count = 0;
        for (let i = 0; i < results.length; i++) {
            const item = results[i];
            if (item && (!(Config.options.search.alwaysListApps || q !== "") || item.key !== "mpris:now-playing"))
                count++;
        }
        return count;
    }

    function loadMoreResults() {
        const total = root.getFilteredResultsCount();
        if (loadedResultsCount < total) {
            loadedResultsCount = Math.min(total, loadedResultsCount + 50);
            resultModel.values = root.processResults(LauncherSearch.results);
        }
    }

    property string searchingText: LauncherSearch.query
    readonly property bool isClipboardMode: root.searchingText.startsWith(Config.options.search.prefix.clipboard)
    readonly property bool isBluetoothMode: root.searchingText.startsWith(Config.options.search.prefix.bluetooth)
    readonly property bool isTranslatorMode: root.searchingText.startsWith(Config.options.search.prefix.translator)
    readonly property bool isAnySpecialMode: root.isClipboardMode || root.isBluetoothMode || root.isTranslatorMode
    readonly property bool alwaysListAppsMode: Config.options.search.alwaysListApps && !root.isAnySpecialMode
    property bool showResults: searchingText != "" || isAnySpecialMode || alwaysListAppsMode || (searchingText === "" && LauncherSearch.results.length > 0)
    property string overviewPosition: Config.options.overview?.position ?? ""
    property bool isNowPlayingFocused: false

    Connections {
        target: GlobalStates
        function onOverviewOpenChanged() {
            if (GlobalStates.overviewOpen) {
                root.loadedResultsCount = 50;
                if (root.alwaysListAppsMode) {
                    Qt.callLater(() => {
                        // Show first 15 immediately for instant response,
                        // then load the rest after a short delay
                        const allResults = LauncherSearch.results;
                        resultModel.values = allResults.slice(0, 15);
                        root.focusFirstItem();
                        resultsDebounce.restart();
                    });
                }
            } else {
                root.isNowPlayingFocused = false;
                resultsDebounce.stop();
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
    implicitWidth: {
        if (root.isBluetoothMode)
            return (Config.options.search.clipboard.panelWidth ?? 860) + Appearance.sizes.elevationMargin * 2;
        if (root.isClipboardMode)
            return (Config.options.search.clipboard.panelWidth ?? 860) + Appearance.sizes.elevationMargin * 2;
        if (root.isTranslatorMode)
            return (Config.options.search.clipboard.panelWidth ?? 860) + Appearance.sizes.elevationMargin * 2;
        return searchWidgetContent.implicitWidth + Appearance.sizes.elevationMargin * 2;
    }
    implicitHeight: {
        if (root.isBluetoothMode)
            return (bluetoothPanelLoader.item ? bluetoothPanelLoader.item.implicitHeight : 520) + Appearance.sizes.elevationMargin * 2;
        if (root.isClipboardMode)
            return (clipboardPanelLoader.item ? clipboardPanelLoader.item.implicitHeight : 560) + searchBar.verticalPadding * 2 + Appearance.sizes.elevationMargin * 2;
        if (root.isTranslatorMode)
            return (translatorPanelLoader.item ? translatorPanelLoader.item.implicitHeight : 520) + searchBar.verticalPadding * 2 + Appearance.sizes.elevationMargin * 2;
        return searchWidgetContent.implicitHeight + searchBar.verticalPadding * 2 + Appearance.sizes.elevationMargin * 2;
    }

    function focusFirstItem() {
        if (root.isBluetoothMode) {} else if (root.isClipboardMode) {} else if (root.isTranslatorMode) {
            if (translatorPanelLoader.item)
                translatorPanelLoader.item.focusInput();
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
        const excludeMpris = Config.options.search.alwaysListApps || q !== "";
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
        if (event.key === Qt.Key_Left) {
            if (nowPlayingFloatingBubble.bubbleActive) {
                if (searchBar.searchInput.activeFocus && searchBar.searchInput.cursorPosition > 0) {
                    // Let cursor move left in input
                    return;
                }
                root.isNowPlayingFocused = true;
                nowPlayingFloatingBubble.forceActiveFocus();
                event.accepted = true;
                return;
            }
        }

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
    }
    Rectangle {
        id: searchWidgetContent
        anchors.horizontalCenter: parent.horizontalCenter
        clip: true
        implicitWidth: {
            if (root.isBluetoothMode)
                return Config.options.search.clipboard.panelWidth ?? 860;
            if (root.isClipboardMode)
                return Config.options.search.clipboard.panelWidth ?? 860;
            if (root.isTranslatorMode)
                return Config.options.search.clipboard.panelWidth ?? 860;
            return gridLayout.implicitWidth;
        }
        implicitHeight: {
            if (root.isBluetoothMode)
                return bluetoothPanelLoader.item ? bluetoothPanelLoader.item.implicitHeight + searchBar.height + searchBar.verticalPadding * 2 + 10 : 520;
            if (root.isClipboardMode)
                return clipboardPanelLoader.item ? clipboardPanelLoader.item.implicitHeight + searchBar.height + searchBar.verticalPadding * 2 + 10 : 560;
            if (root.isTranslatorMode)
                return translatorPanelLoader.item ? translatorPanelLoader.item.implicitHeight + searchBar.height + searchBar.verticalPadding * 2 + 10 : 520;
            return gridLayout.implicitHeight;
        }
        radius: searchBar.height / 2 + searchBar.verticalPadding
        color: Appearance.colors.colBackgroundSurfaceContainer

        Behavior on implicitWidth {
            id: searchWidthBehavior
            NumberAnimation {
                duration: 350
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
            }
        }

        Behavior on implicitHeight {
            id: searchHeightBehavior
            NumberAnimation {
                duration: 350
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
            }
        }

        GridLayout {
            id: gridLayout
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            columns: 1
            clip: true

            SearchBar {
                id: searchBar
                property real verticalPadding: 4
                Layout.fillWidth: true
                Layout.leftMargin: 10
                Layout.rightMargin: 4
                Layout.topMargin: verticalPadding
                Layout.bottomMargin: verticalPadding
                Layout.row: root.overviewPosition == "bottom" ? 2 : 0
                animateWidth: true
                Synchronizer on searchingText {
                    property alias source: root.searchingText
                }

                clipboardMode: root.isClipboardMode || root.isBluetoothMode || root.isTranslatorMode
                clipboardWidth: 830
                currentResultIndex: appResults.currentIndex
                isTranslatorPanelFocused: root.isTranslatorMode && translatorPanelLoader.item && translatorPanelLoader.item.focusedControlIndex !== -1

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
                }

                onNavigateRight: {
                    if (root.isBluetoothMode && bluetoothPanelLoader.item)
                        bluetoothPanelLoader.item.navigateRight();
                    else if (root.isClipboardMode && clipboardPanelLoader.item)
                        clipboardPanelLoader.item.navigateRight();
                    else if (root.isTranslatorMode && translatorPanelLoader.item)
                        translatorPanelLoader.item.navigateRight();
                }

                onActivate: {
                    if (root.isBluetoothMode && bluetoothPanelLoader.item)
                        bluetoothPanelLoader.item.activateSelected();
                    else if (root.isClipboardMode && clipboardPanelLoader.item)
                        clipboardPanelLoader.item.activateSelected();
                    else if (root.isTranslatorMode && translatorPanelLoader.item)
                        translatorPanelLoader.item.activateSelected();
                }

                onDeleteSelected: {
                    if (root.isBluetoothMode && bluetoothPanelLoader.item) {
                        bluetoothPanelLoader.item.activateSelected();
                    } else if (root.isClipboardMode && clipboardPanelLoader.item) {
                        clipboardPanelLoader.item.activateSelected();
                    } else if (root.isTranslatorMode && translatorPanelLoader.item) {
                        translatorPanelLoader.item.activateSelected();
                    }
                }
            }

            Rectangle {
                visible: root.showResults || root.isAnySpecialMode
                Layout.fillWidth: true
                height: 1
                color: Appearance.colors.colOutlineVariant
                Layout.row: 1
            }

            Item {
                visible: root.showResults && !root.isAnySpecialMode
                Layout.fillWidth: true
                implicitHeight: root.showSkeletons ? searchSkeletons.implicitHeight + 20 : Math.min(600, appResults.contentHeight + appResults.topMargin + appResults.bottomMargin)
                Layout.row: root.overviewPosition == "bottom" ? 0 : 2

                Behavior on implicitHeight {
                    // Disabled during active debounce to avoid layout thrashing
                    // while the user is still typing rapidly
                    enabled: !resultsDebounce.running
                    NumberAnimation {
                        duration: 300
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
                            duration: 180
                            easing.type: Easing.OutQuad
                        }
                    }
                    clip: true
                    topMargin: 10
                    bottomMargin: 10
                    spacing: 2
                    KeyNavigation.up: searchBar
                    highlightMoveDuration: 100

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

                    Connections {
                        target: root
                        function onSearchingTextChanged() {
                            root.loadedResultsCount = 50;
                            if (appResults.count > 0)
                                appResults.currentIndex = 0;
                        }
                    }

                    // Debounce timer: delivers full results 150ms after the last
                    // results change, avoiding per-keystroke full list recomputation
                    Timer {
                        id: resultsDebounce
                        interval: 150
                        repeat: false
                        onTriggered: {
                            resultModel.values = root.processResults(LauncherSearch.results);
                        }
                    }

                    Connections {
                        target: LauncherSearch
                        function onResultsChanged() {
                            root.loadedResultsCount = 50;
                            // Immediately show first 15 results for snappy visual feedback
                            const immediate = root.processResults(LauncherSearch.results);
                            const quickSlice = immediate.length > 15 ? immediate.slice(0, 15) : immediate;
                            resultModel.values = quickSlice;
                            root.focusFirstItem();
                            // Schedule full result delivery after debounce
                            if (immediate.length > 15)
                                resultsDebounce.restart();
                        }
                    }

                    model: ScriptModel {
                        id: resultModel
                        objectProp: "key"
                        Component.onCompleted: {
                            values = root.processResults(LauncherSearch.results);
                        }
                    }

                    delegate: SearchItem {
                        id: searchItem
                        required property int index
                        listIndex: index
                        listCurrentIndex: appResults.currentIndex
                        required property var modelData
                        anchors.left: parent?.left
                        anchors.right: parent?.right
                        entry: modelData
                        query: StringUtils.cleanOnePrefix(root.searchingText, [Config.options.search.prefix.action, Config.options.search.prefix.app, Config.options.search.prefix.clipboard, Config.options.search.prefix.emojis, Config.options.search.prefix.math, Config.options.search.prefix.shellCommand, Config.options.search.prefix.webSearch])

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
                }

                ColumnLayout {
                    id: searchSkeletons
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    anchors.topMargin: 10
                    anchors.bottomMargin: 10
                    spacing: 8
                    visible: opacity > 0
                    opacity: root.showSkeletons ? 1.0 : 0.0
                    Behavior on opacity {
                        NumberAnimation {
                            duration: 180
                            easing.type: Easing.OutQuad
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
                Layout.row: root.overviewPosition == "bottom" ? 0 : 2

                opacity: root.isClipboardMode ? 1.0 : 0.0
                Behavior on opacity {
                    NumberAnimation {
                        duration: 280
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
                Layout.row: root.overviewPosition == "bottom" ? 0 : 2

                opacity: root.isBluetoothMode ? 1.0 : 0.0
                Behavior on opacity {
                    NumberAnimation {
                        duration: 280
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
                Layout.row: root.overviewPosition == "bottom" ? 0 : 2

                opacity: root.isTranslatorMode ? 1.0 : 0.0
                Behavior on opacity {
                    NumberAnimation {
                        duration: 280
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
        }
    }

    // Now Playing Floating Bubble (Expressive Spinning Vinyl)
    Rectangle {
        id: nowPlayingFloatingBubble

        readonly property bool bubbleActive: (root.alwaysListAppsMode || root.searchingText !== "") && MprisController.activePlayer !== null

        anchors.right: searchWidgetContent.left
        anchors.rightMargin: 12
        y: searchWidgetContent.y + searchBar.y + (searchBar.height - height) / 2

        width: bubbleActive ? 96 : 0
        height: 48
        radius: 24
        visible: width > 0
        clip: true

        color: root.isNowPlayingFocused ? Appearance.colors.colSurfaceContainerHigh : Appearance.colors.colBackgroundSurfaceContainer

        border.width: 0

        focus: root.isNowPlayingFocused
        activeFocusOnTab: false

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(nowPlayingFloatingBubble)
        }

        Behavior on width {
            NumberAnimation {
                duration: 350
                easing.type: Easing.OutQuint
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 6
            anchors.rightMargin: 6
            spacing: 6
            opacity: nowPlayingFloatingBubble.width >= 80 ? 1.0 : 0.0
            Behavior on opacity {
                NumberAnimation {
                    duration: 150
                }
            }

            // Album art circle (Expressive Spinning Vinyl)
            Rectangle {
                id: artContainer
                Layout.preferredWidth: 36
                Layout.preferredHeight: 36
                radius: 18
                color: Appearance.colors.colSurfaceContainerHighest

                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: artContainer.width
                        height: artContainer.height
                        radius: artContainer.radius
                    }
                }

                Image {
                    id: albumArtImage
                    anchors.fill: parent
                    source: root.artSource
                    fillMode: Image.PreserveAspectCrop
                    visible: root.artSource !== ""

                    property real currentRotation: 0
                    property real targetSpeed: MprisController.isPlaying ? 30 : 0
                    property real currentSpeed: 0
                    property var lastTime: 0

                    Behavior on currentSpeed {
                        NumberAnimation {
                            duration: 2000
                            easing.type: Easing.OutQuad
                        }
                    }

                    Timer {
                        id: spinTimer
                        interval: 16
                        repeat: true
                        running: MprisController.isPlaying || albumArtImage.currentSpeed > 0.1
                        onTriggered: {
                            let now = Date.now();
                            if (albumArtImage.lastTime > 0) {
                                let dt = (now - albumArtImage.lastTime) / 1000.0;
                                albumArtImage.currentRotation = (albumArtImage.currentRotation + albumArtImage.currentSpeed * dt) % 360;
                            }
                            albumArtImage.lastTime = now;
                        }
                        onRunningChanged: {
                            if (running) {
                                albumArtImage.lastTime = Date.now();
                            } else {
                                albumArtImage.lastTime = 0;
                            }
                        }
                    }

                    rotation: currentRotation
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "music_note"
                    iconSize: 18
                    color: Appearance.colors.colOnSurfaceVariant
                    visible: root.artSource === ""
                }
            }

            // Play/pause button inside dynamic MaterialShape
            MaterialShape {
                id: playPauseShape
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: 36
                Layout.preferredHeight: 36
                shape: root.isNowPlayingFocused ? MaterialShape.Shape.Cookie4Sided : MaterialShape.Shape.Cookie7Sided
                color: root.isNowPlayingFocused ? Appearance.colors.colPrimary : Appearance.colors.colSurfaceContainerHighest

                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(playPauseShape)
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: MprisController.isPlaying ? "pause" : "play_arrow"
                    iconSize: 18
                    color: root.isNowPlayingFocused ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurfaceVariant
                    fill: root.isNowPlayingFocused ? 1 : 0
                    Behavior on fill {
                        NumberAnimation {
                            duration: 200
                        }
                    }
                }
            }
        }

        PointingHandInteraction {
            id: bubbleMouseArea
            anchors.fill: parent
            onClicked: {
                root.isNowPlayingFocused = true;
                nowPlayingFloatingBubble.forceActiveFocus();
                MprisController.togglePlaying();
            }
        }

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Right || event.key === Qt.Key_Escape) {
                root.isNowPlayingFocused = false;
                searchBar.forceFocus();
                event.accepted = true;
            } else if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                MprisController.togglePlaying();
                event.accepted = true;
            }
        }
    }
}
