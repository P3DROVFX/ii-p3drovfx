import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "timetable"

Scope {
    id: root
    // Small session-only overrides protect a recent user choice from a stale
    // FileView notification. The durable value is still written to Persistent;
    // these scalars disappear with the shell and do not retain page trees.
    property int sessionTab: -1
    property string sessionTimetableMode: ""
    property var tabButtonList: {
        let list = [];
        if (Config.options.cheatsheet.enableTimetable) {
            list.push({
                "id": "timetable",
                "icon": "calendar_month",
                "name": Translation.tr("Timetable")
            });
        }
        list.push({
            "id": "keybinds",
            "icon": "keyboard",
            "name": Translation.tr("Keybinds")
        });
        if (Config.options.cheatsheet.enablePeriodicTable) {
            list.push({
                "id": "elements",
                "icon": "experiment",
                "name": Translation.tr("Elements")
            });
        }
        if (Config.options.cheatsheet.enableAminoAcids) {
            list.push({
                "id": "aminoAcids",
                "icon": "biotech",
                "name": Translation.tr("Amino acids")
            });
        }
        if (Config.options.cheatsheet.enableCommands) {
            list.push({
                "id": "commands",
                "icon": "terminal",
                "name": Translation.tr("Commands")
            });
        }
        if (Config.options.cheatsheet.enableWorkspaceProfiles) {
            list.push({
                "id": "workspaces",
                "icon": "dashboard",
                "name": Translation.tr("Workspaces")
            });
        }
        if (Config.options.cheatsheet.enableGmail) {
            list.push({
                "id": "email",
                "icon": "mail",
                "name": Translation.tr("Email")
            });
        }
        if (Config.options.cheatsheet.enableTypingTest) {
            list.push({
                "id": "typingTest",
                "icon": "speed",
                "name": Translation.tr("Typing test")
            });
        }
        if (Config.options.cheatsheet.enableDevTools) {
            list.push({
                "id": "devTools",
                "icon": "handyman",
                "name": Translation.tr("Dev tools")
            });
        }
        return list;
    }

    function indexOfTab(tabId) {
        return root.tabButtonList.findIndex(tab => tab.id === tabId);
    }

    function consumePendingTab() {
        const pendingTab = GlobalStates.cheatsheetPendingTab;
        if (pendingTab.length === 0)
            return;
        const index = root.indexOfTab(pendingTab);
        GlobalStates.cheatsheetPendingTab = "";
        if (index >= 0) {
            root.sessionTab = index;
            Persistent.states.cheatsheet.tabIndex = index;
            if (cheatsheetLoader.item && typeof cheatsheetLoader.item.selectTab === "function") {
                cheatsheetLoader.item.selectTab(index);
            }
        }
    }

    Connections {
        target: GlobalStates
        function onCheatsheetOpenChanged() {
            if (GlobalStates.cheatsheetOpen) {
                root.consumePendingTab();
                root.requestOpen();
            } else {
                root.requestClose();
            }
        }

        function onTimetableNavigationRequestChanged() {
            root.openTimetableNavigation();
        }
    }

    property bool activeState: false
    property bool cachePrepared: false
    // Opt-in diagnostic; normal sessions have no sampler or diagnostic timers.
    readonly property bool cacheProbeEnabled: Quickshell.env("II_CHEATSHEET_CACHE_PROBE") === "1"
    readonly property bool cacheWanted: Config.ready && Persistent.ready && Config.options.cheatsheet.keepLastTabLoaded
    onActiveStateChanged: {
        if (!root.activeState) {
            // Once the surface is closed, let the next opening read the durable
            // value again so external open requests (Gmail, Welcome, etc.) can
            // choose a different page while the window is hidden.
            root.sessionTab = -1;
            root.sessionTimetableMode = "";
        }
    }
    function prepareCache() {
        root.cachePrepared = true;
    }
    readonly property bool cacheReady: cheatsheetLoader.item?.pageReady ?? false

    Timer {
        // Let configuration and startup services settle before hidden incubation.
        interval: 1500
        running: root.cacheWanted && !root.cachePrepared && !root.cacheProbeEnabled
        onTriggered: root.prepareCache()
    }
    onCacheWantedChanged: if (!cacheWanted)
        cachePrepared = false

    Loader {
        active: root.cacheProbeEnabled && Config.ready && Persistent.ready
        sourceComponent: CheatsheetCacheProbe {
            controller: root
            cacheReady: root.cacheReady
        }
    }


    function requestOpen() {
        root.activeState = true;
        if (!GlobalStates.cheatsheetOpen) {
            GlobalStates.cheatsheetOpen = true;
        }
    }

    function requestClose() {
        if (GlobalStates.cheatsheetOpen) {
            GlobalStates.cheatsheetOpen = false;
        }
        if (!cheatsheetLoader.item) root.activeState = false;
    }

    function requestToggle() {
        if (GlobalStates.cheatsheetOpen) {
            requestClose();
        } else {
            requestOpen();
        }
    }

    function openTimetableNavigation() {
        const timetableIndex = root.tabButtonList.findIndex(tab => tab.id === "timetable");
        if (timetableIndex < 0)
            return;
        root.sessionTab = timetableIndex;
        root.sessionTimetableMode = "month";
        if (Persistent.states.cheatsheet.tabIndex !== timetableIndex)
            Persistent.states.cheatsheet.tabIndex = timetableIndex;
        if (cheatsheetLoader.item && typeof cheatsheetLoader.item.selectTab === "function")
            cheatsheetLoader.item.selectTab(timetableIndex);
        Persistent.states.cheatsheet.timetableView = "month";
        root.requestOpen();
    }

    RetainedLoader {
        id: cheatsheetLoader
        // Keep the window chrome and only the last selected tab.
        // With caching disabled, closing releases the window immediately.
        requested: root.activeState || root.cachePrepared
        retainFor: 0

        sourceComponent: PanelWindow {
            id: cheatsheetRoot
            visible: root.activeState
            property int selectedTab: 0
            property int protectedTab: -1
            property int previousTab: -1
            readonly property bool pageReady: swipeView.selectionReady && swipeView.currentItem?.isCurrent === true && swipeView.currentItem?.status === Loader.Ready && (swipeView.currentItem.item?.lookupReady ?? true)

            function clampTab(index) {
                return Math.max(0, Math.min(root.tabButtonList.length - 1, Number(index) || 0));
            }

            function initializeSelection() {
                const next = root.sessionTab >= 0
                    ? cheatsheetRoot.clampTab(root.sessionTab)
                    : cheatsheetRoot.clampTab(Persistent.states.cheatsheet.tabIndex);
                root.sessionTab = next;
                cheatsheetRoot.protectedTab = -1;
                cheatsheetRoot.previousTab = -1;
                cheatsheetRoot.selectedTab = next;
            }

            // Persistence is changed only by a navigation request. SwipeView
            // adjusts its index while Repeater inserts children asynchronously;
            // those intermediate indices are not a user selection.
            function selectTab(index) {
                if (index < 0 || index >= root.tabButtonList.length)
                    return;
                cheatsheetRoot.previousTab = cheatsheetRoot.selectedTab;
                cheatsheetRoot.protectedTab = index;
                root.sessionTab = index;
                if (cheatsheetRoot.selectedTab !== index)
                    cheatsheetRoot.selectedTab = index;
                if (Persistent.states.cheatsheet.tabIndex !== index)
                    Persistent.states.cheatsheet.tabIndex = index;
                swipeView.restoreSelection();
            }
            onSelectedTabChanged: Qt.callLater(swipeView.restoreSelection)

            Component.onCompleted: {
                cheatsheetRoot.initializeSelection();
                Qt.callLater(swipeView.restoreSelection);
                // Built ahead of time while hidden: onVisibleChanged drives the
                // open from here on.
                if (!visible)
                    return;
                registerGrabTimer.start();
            }

            Connections {
                target: Persistent.states.cheatsheet
                function onTabIndexChanged() {
                    const next = cheatsheetRoot.clampTab(Persistent.states.cheatsheet.tabIndex);
                    if (cheatsheetRoot.protectedTab >= 0) {
                        if (next === cheatsheetRoot.protectedTab)
                            return;
                        if (next === cheatsheetRoot.previousTab) {
                            Persistent.states.cheatsheet.tabIndex = cheatsheetRoot.protectedTab;
                            return;
                        }
                        cheatsheetRoot.protectedTab = -1;
                        cheatsheetRoot.previousTab = -1;
                    }
                    root.sessionTab = next;
                    if (cheatsheetRoot.selectedTab !== next)
                        cheatsheetRoot.selectedTab = next;
                }
            }

            Connections {
                target: root
                function onTabButtonListChanged() {
                    if (root.sessionTab >= 0) {
                        const next = cheatsheetRoot.clampTab(root.sessionTab);
                        root.sessionTab = next;
                        if (cheatsheetRoot.selectedTab !== next)
                            cheatsheetRoot.selectedTab = next;
                        if (Persistent.states.cheatsheet.tabIndex !== next)
                            Persistent.states.cheatsheet.tabIndex = next;
                    }
                    swipeView.selectionReady = false;
                    Qt.callLater(swipeView.restoreSelection);
                }
            }

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            function hide() {
                root.requestClose();
            }
            // The toolbar highlights selectedTab while the SwipeView shows
            // currentIndex; any drift between them (count clamping during
            // asynchronous incubation, the dead initial currentIndex binding
            // while children insert) renders an inactive zero-sized delegate
            // and the page looks empty with the tab still highlighted. Re-assert
            // the saved selection on every open so a cold cache cannot persist
            // the desync across openings.
            exclusiveZone: 0
            implicitWidth: cheatsheetBackground.width + Appearance.sizes.elevationMargin * 2
            implicitHeight: cheatsheetBackground.height + Appearance.sizes.elevationMargin * 2
            WlrLayershell.namespace: "quickshell:cheatsheet"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: GlobalStates.cheatsheetOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
            color: "transparent"

            mask: Region {
                item: cheatsheetBackground
            }

            Timer {
                id: registerGrabTimer
                interval: 0
                repeat: false
                onTriggered: {
                    GlobalFocusGrab.addDismissable(cheatsheetRoot);
                }
            }

            onVisibleChanged: {
                if (visible) {
                    cheatsheetRoot.initializeSelection();
                    Qt.callLater(swipeView.restoreSelection);
                    initialFocusTimer.restart();
                    registerGrabTimer.restart();
                    return;
                }
                registerGrabTimer.stop();
                GlobalFocusGrab.removeDismissable(cheatsheetRoot);
                cheatsheetRoot.protectedTab = -1;
                cheatsheetRoot.previousTab = -1;
                cheatsheetBackground.ctrlPressed = false;
            }

            Timer {
                id: initialFocusTimer
                interval: 0
                repeat: false
                onTriggered: {
                    if (swipeView.currentItem && swipeView.currentItem.status === Loader.Ready && swipeView.currentItem.item) {
                        swipeView.currentItem.item.forceActiveFocus();
                    } else if (swipeView.currentItem) {
                        swipeView.currentItem.forceActiveFocus();
                    }
                }
            }

            Component.onDestruction: {
                registerGrabTimer.stop();
                GlobalFocusGrab.removeDismissable(cheatsheetRoot);
            }
            Connections {
                target: GlobalFocusGrab
                function onDismissed() {
                    cheatsheetRoot.hide();
                }
            }


            WindowAnimationSurface {
                id: dialogWrap
                anchors.fill: parent
                open: GlobalStates.cheatsheetOpen
                mapped: cheatsheetRoot.visible
                panelWidth: cheatsheetBackground.width
                panelHeight: cheatsheetBackground.height
                onClosed: if (!GlobalStates.cheatsheetOpen) root.activeState = false

                StyledRectangularShadow {
                    target: cheatsheetBackground
                }

                Rectangle {
                    id: cheatsheetBackground
                    anchors.centerIn: parent
                    color: Appearance.colors.colLayer0
                    radius: Appearance.rounding.windowRounding
                    property real padding: 20

                    property real maxBgWidth: cheatsheetRoot.screen ? cheatsheetRoot.screen.width * 0.95 : 1900
                    property real maxBgHeight: cheatsheetRoot.screen ? cheatsheetRoot.screen.height * 0.80 : 1000

                    implicitWidth: Math.min(maxBgWidth, cheatsheetColumnLayout.implicitWidth + padding * 2)
                    implicitHeight: Math.min(maxBgHeight, cheatsheetColumnLayout.implicitHeight + padding * 2)

                    focus: true
                    property bool ctrlPressed: false

                    Keys.priority: Keys.BeforeItem
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Control || (event.modifiers & Qt.ControlModifier)) {
                            cheatsheetBackground.ctrlPressed = true;
                        }

                        if (event.modifiers & Qt.ControlModifier) {
                            if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
                                const targetIndex = event.key - Qt.Key_1;
                                if (targetIndex >= 0 && targetIndex < root.tabButtonList.length) {
                                    tabBar.setCurrentIndex(targetIndex);
                                    event.accepted = true;
                                    return;
                                }
                            }
                            if (event.key === Qt.Key_PageDown) {
                                tabBar.incrementCurrentIndex();
                                event.accepted = true;
                                return;
                            } else if (event.key === Qt.Key_PageUp) {
                                tabBar.decrementCurrentIndex();
                                event.accepted = true;
                                return;
                            }
                        }

                        if (event.key === Qt.Key_Escape) {
                            cheatsheetRoot.hide();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Slash) {
                            if (swipeView.currentItem && swipeView.currentItem.item) {
                                swipeView.currentItem.item.forceActiveFocus();
                            }
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Tab) {
                            tabBar.setCurrentIndex((tabBar.currentIndex + 1) % root.tabButtonList.length);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Backtab) {
                            tabBar.setCurrentIndex((tabBar.currentIndex - 1 + root.tabButtonList.length) % root.tabButtonList.length);
                            event.accepted = true;
                        }
                    }

                    Keys.onReleased: event => {
                        if (event.key === Qt.Key_Control || !(event.modifiers & Qt.ControlModifier)) {
                            cheatsheetBackground.ctrlPressed = false;
                        }
                    }

                    RippleButton {
                        id: closeButton
                        implicitWidth: 40
                        implicitHeight: 40
                        buttonRadius: Appearance.rounding.full
                        anchors {
                            top: parent.top
                            right: parent.right
                            topMargin: 20
                            rightMargin: 20
                        }


                        onClicked: {
                            cheatsheetRoot.hide();
                        }

                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            font.pixelSize: Appearance.font.pixelSize.title
                            text: "close"
                            rotation: closeButton.isHovered ? 90 : 0
                            Behavior on rotation {
                                NumberAnimation {
                                    duration: 200
                                    easing.type: Easing.OutBack
                                    easing.overshoot: 1.5
                                }
                            }
                        }
                    }

                    // Left counterpart of the close button: only the timetable tab
                    // has two shapes to choose between, so it only appears there.
                    TimetableViewSwitch {
                        id: timetableViewSwitch
                        sessionMode: root.sessionTimetableMode
                        onModeRequested: mode => {
                            root.sessionTimetableMode = mode;
                            Persistent.states.cheatsheet.timetableView = mode;
                        }
                        visible: Boolean(root.tabButtonList[swipeView.currentIndex] && root.tabButtonList[swipeView.currentIndex].icon === "calendar_month")
                        animateIn: timetableViewSwitch.visible
                        compact: cheatsheetBackground.width < 1100
                        // Anchored to the column (a sibling) rather than the tab
                        // bar itself: an anchor may only target a parent or a
                        // sibling, and the tab bar is a grandchild.
                        anchors {
                            left: parent.left
                            leftMargin: 20
                            top: cheatsheetColumnLayout.top
                            topMargin: Math.max(0, (topToolbar.height - timetableViewSwitch.height) / 2)
                        }
                    }

                    ColumnLayout {
                        id: cheatsheetColumnLayout
                        anchors.centerIn: parent
                        width: Math.min(implicitWidth, parent.width - parent.padding * 2)
                        height: Math.min(implicitHeight, parent.height - parent.padding * 2)
                        spacing: 10

                        Toolbar {
                            id: topToolbar
                            Layout.alignment: Qt.AlignHCenter
                            Layout.maximumWidth: cheatsheetColumnLayout.width
                            enableShadow: false


                            ToolbarTabBar {
                                id: tabBar
                                tabButtonList: root.tabButtonList
                                showShortcutHints: cheatsheetBackground.ctrlPressed
                                // A row of every cheatsheet page is wider than a
                                // compact display. Keep every destination as an
                                // icon, while only the current one keeps its label.
                                collapseInactiveLabels: cheatsheetRoot.screen && cheatsheetRoot.screen.width < 1100

                                requestOnly: true
                                currentIndex: cheatsheetRoot.selectedTab
                                onIndexSelected: index => cheatsheetRoot.selectTab(index)
                            }
                        }

                        SwipeView {
                            id: swipeView
                            Layout.topMargin: 5
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            property bool selectionReady: false
                            function restoreSelection() {
                                if (count !== root.tabButtonList.length)
                                    return;
                                selectionReady = false;
                                setCurrentIndex(cheatsheetRoot.selectedTab);
                                alignViewport();
                                selectionReady = true;
                            }
                            // A SwipeView scrolls its viewport only when the current
                            // index *changes*, and the saved index is already set while
                            // the window incubates hidden, with no screen to size
                            // against. The pages are laid out at placeholder widths
                            // then, so the viewport settles on whichever page sits at
                            // offset zero; when the real geometry arrives the pages move
                            // and the viewport does not. The toolbar then highlights a
                            // page parked off-screen and the sheet reads as empty until
                            // the next tab switch moves the index. Re-snapping the
                            // viewport to the selected page keeps the two in step.
                            function alignViewport() {
                                const view = swipeView.contentItem;
                                if (!view || typeof view.positionViewAtIndex !== "function")
                                    return;
                                if (count !== root.tabButtonList.length)
                                    return;
                                if (view.moving || view.dragging)
                                    return;
                                view.positionViewAtIndex(cheatsheetRoot.selectedTab, ListView.SnapPosition);
                            }
                            onWidthChanged: Qt.callLater(alignViewport)
                            onHeightChanged: Qt.callLater(alignViewport)
                            onCountChanged: {
                                selectionReady = false;
                                Qt.callLater(restoreSelection);
                            }
                            Component.onCompleted: {
                                if (contentItem)
                                    contentItem.highlightMoveDuration = 0;
                                Qt.callLater(restoreSelection);
                            }

                            property real calculatedWidth: cheatsheetRoot.screen ? cheatsheetRoot.screen.width * 0.92 : 1700
                            property real calculatedHeight: cheatsheetRoot.screen ? cheatsheetRoot.screen.height * 0.75 : 650

                            // These are desktop preferences, not minima. A
                            // minimum wider than the monitor made pages keep
                            // calculating content outside the visible dialog.
                            Layout.preferredWidth: Math.min(1800, calculatedWidth)
                            Layout.maximumWidth: calculatedWidth
                            Layout.preferredHeight: Math.min(850, calculatedHeight)
                            Layout.maximumHeight: calculatedHeight
                            spacing: 10
                            readonly property bool currentPageLocksHorizontalSwipe: currentItem && currentItem.status === Loader.Ready && currentItem.item && currentItem.item.timetableDragActive === true
                            interactive: !swipeView.currentPageLocksHorizontalSwipe
                            onCurrentIndexChanged: {
                                if (selectionReady && count === root.tabButtonList.length && cheatsheetRoot.selectedTab !== currentIndex)
                                    cheatsheetRoot.selectTab(currentIndex);
                                if (root.activeState && currentItem && currentItem.status === Loader.Ready && currentItem.item) {
                                    currentItem.item.forceActiveFocus();
                                }
                            }

                            implicitWidth: Math.max.apply(null, contentChildren.map(child => child.implicitWidth || 0))
                            implicitHeight: Math.max.apply(null, contentChildren.map(child => child.implicitHeight || 0))

                            clip: true

                            Repeater {
                                id: tabs
                                model: root.tabButtonList
                                delegate: Loader {
                                    id: tabDelegate
                                    required property var modelData
                                    required property int index

                                    Keys.forwardTo: [cheatsheetBackground]

                                    // The saved selection is stable while SwipeView
                                    // inserts children and adjusts its own index.
                                    readonly property bool isCurrent: cheatsheetRoot.selectedTab === index
                                    // Selection replaces the cache; closing preserves it.
                                    active: isCurrent && (root.activeState || root.cachePrepared)
                                    visible: isCurrent && root.activeState
                                    enabled: isCurrent && root.activeState && GlobalStates.cheatsheetOpen
                                    asynchronous: true

                                    onStatusChanged: {
                                        if (status === Loader.Ready) {
                                            if (swipeView.currentIndex === index && cheatsheetRoot.visible)
                                                item.forceActiveFocus();
                                        }
                                    }

                                    Binding {
                                        target: tabDelegate.item
                                        property: "keyNavTarget"
                                        value: cheatsheetBackground
                                        when: tabDelegate.status === Loader.Ready && tabDelegate.item.hasOwnProperty("keyNavTarget")
                                    }

                                    Binding {
                                        target: tabDelegate.item
                                        property: "sessionMode"
                                        value: root.sessionTimetableMode
                                        when: tabDelegate.status === Loader.Ready && tabDelegate.item.hasOwnProperty("sessionMode")
                                    }

                                    source: {
                                        switch (modelData.icon) {
                                        case "calendar_month":
                                            return "CheatsheetTimetable.qml";
                                        case "keyboard":
                                            return "CheatsheetKeybinds.qml";
                                        case "experiment":
                                            return "CheatsheetPeriodicTable.qml";
                                        case "biotech":
                                            return "CheatsheetAminoAcids.qml";
                                        case "terminal":
                                            return "commands/CheatsheetCommands.qml";
                                        case "dashboard":
                                            return "CheatsheetWorkspaces.qml";
                                        case "mail":
                                            return "CheatsheetEmail.qml";
                                        case "speed":
                                            return "CheatsheetTypingTest.qml";
                                        case "handyman":
                                            return "CheatsheetDevTools.qml";
                                        default:
                                            return "";
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    GlobalShortcut {
        name: "cheatsheetToggle"
        description: "Toggles cheatsheet on press"
        onPressed: {
            root.requestToggle();
        }
    }

    GlobalShortcut {
        name: "cheatsheetOpen"
        description: "Opens cheatsheet on press"
        onPressed: {
            root.requestOpen();
        }
    }

    GlobalShortcut {
        name: "cheatsheetClose"
        description: "Closes cheatsheet on press"
        onPressed: {
            root.requestClose();
        }
    }
}
