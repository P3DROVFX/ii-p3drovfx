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
        if (index >= 0)
            Persistent.states.cheatsheet.tabIndex = index;
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
    readonly property bool cacheWanted: Config.ready && Persistent.ready
        && Config.options.cheatsheet.keepLastTabLoaded
    function prepareCache() { root.cachePrepared = true; }
    readonly property bool cacheReady: cheatsheetLoader.item?.pageReady ?? false

    Timer {
        // Let configuration and startup services settle before hidden incubation.
        interval: 1500
        running: root.cacheWanted && !root.cachePrepared && !root.cacheProbeEnabled
        onTriggered: root.prepareCache()
    }
    onCacheWantedChanged: if (!cacheWanted) cachePrepared = false

    Loader {
        active: root.cacheProbeEnabled && Config.ready && Persistent.ready
        sourceComponent: CheatsheetCacheProbe {
            controller: root
            cacheReady: root.cacheReady
        }
    }

    Timer {
        id: closeTimer
        interval: 400
        repeat: false
        onTriggered: {
            root.activeState = false;
        }
    }

    function requestOpen() {
        closeTimer.stop();
        root.activeState = true;
        if (!GlobalStates.cheatsheetOpen) {
            GlobalStates.cheatsheetOpen = true;
        }
    }

    function requestClose() {
        if (GlobalStates.cheatsheetOpen) {
            GlobalStates.cheatsheetOpen = false;
        }
        closeTimer.restart();
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
        if (Persistent.states.cheatsheet.tabIndex !== timetableIndex)
            Persistent.states.cheatsheet.tabIndex = timetableIndex;
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
            property int selectedTab: Math.max(0, Math.min(root.tabButtonList.length - 1, Persistent.states.cheatsheet.tabIndex))
            readonly property bool pageReady: swipeView.selectionReady
                && swipeView.currentItem?.isCurrent === true
                && swipeView.currentItem?.status === Loader.Ready
                && (swipeView.currentItem.item?.lookupReady ?? true)

            // Persistence is changed only by a navigation request. SwipeView
            // adjusts its index while Repeater inserts children asynchronously;
            // those intermediate indices are not a user selection.
            function selectTab(index) {
                if (index < 0 || index >= root.tabButtonList.length) return;
                if (Persistent.states.cheatsheet.tabIndex !== index)
                    Persistent.states.cheatsheet.tabIndex = index;
                swipeView.restoreSelection();
            }
            onSelectedTabChanged: Qt.callLater(swipeView.restoreSelection)

            Connections {
                target: root
                function onTabButtonListChanged() {
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
            exclusiveZone: 0
            implicitWidth: cheatsheetBackground.width + Appearance.sizes.elevationMargin * 2
            implicitHeight: cheatsheetBackground.height + Appearance.sizes.elevationMargin * 2
            WlrLayershell.namespace: "quickshell:cheatsheet"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: GlobalStates.cheatsheetOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
            color: "transparent"

            mask: Region {
                item: cheatsheetInputMask
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
                    initialFocusTimer.restart();
                    registerGrabTimer.restart();
                    animInTimer.restart();
                    return;
                }
                registerGrabTimer.stop();
                GlobalFocusGrab.removeDismissable(cheatsheetRoot);
                cheatsheetBackground.animateIn = false;
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

            Component.onCompleted: {
                // Built ahead of time while hidden: onVisibleChanged drives the
                // open from here on.
                if (!visible)
                    return;
                registerGrabTimer.start();
                animInTimer.start();
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

            Item {
                id: cheatsheetInputMask
                width: cheatsheetBackground.width
                height: cheatsheetBackground.height
                anchors.centerIn: parent
            }

            Item {
                id: dialogWrap
                anchors.fill: parent
                // A reference sheet must be readable on its first frame.
                opacity: GlobalStates.cheatsheetOpen ? 1.0 : 0.0
                Behavior on opacity {
                    enabled: !GlobalStates.cheatsheetOpen
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(dialogWrap)
                }

                StyledRectangularShadow {
                    target: cheatsheetBackground
                }

                Rectangle {
                    id: cheatsheetBackground
                    anchors.centerIn: parent
                    color: Appearance.colors.colLayer0
                    border.width: 1
                    border.color: Appearance.colors.colLayer0Border
                    radius: Appearance.rounding.windowRounding
                    property real padding: 20
                    property bool animateIn: false

                    Timer {
                        id: animInTimer
                        interval: 0
                        repeat: false
                        onTriggered: cheatsheetBackground.animateIn = true
                    }

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

                        scale: cheatsheetBackground.animateIn ? 1.0 : 0.0
                        Behavior on scale {
                            NumberAnimation {
                                duration: 300
                                easing.type: Easing.OutBack
                                easing.overshoot: 1.5
                            }
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
                        visible: Boolean(root.tabButtonList[swipeView.currentIndex] && root.tabButtonList[swipeView.currentIndex].icon === "calendar_month")
                        animateIn: cheatsheetBackground.animateIn && timetableViewSwitch.visible
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
                            enableShadow: false

                            transform: Translate {
                                id: toolbarTrans
                                y: cheatsheetBackground.animateIn ? 0 : -20
                            }
                            opacity: cheatsheetBackground.animateIn ? 1.0 : 0.0

                            Behavior on opacity {
                                NumberAnimation {
                                    duration: 280
                                    easing.type: Easing.OutCubic
                                }
                            }
                            Behavior on transform {
                                NumberAnimation {
                                    duration: 320
                                    easing.type: Easing.OutBack
                                    easing.overshoot: 1.3
                                }
                            }

                            ToolbarTabBar {
                                id: tabBar
                                tabButtonList: root.tabButtonList
                                showShortcutHints: cheatsheetBackground.ctrlPressed

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
                                if (count !== root.tabButtonList.length) return;
                                selectionReady = false;
                                setCurrentIndex(cheatsheetRoot.selectedTab);
                                selectionReady = true;
                            }
                            onCountChanged: {
                                selectionReady = false;
                                Qt.callLater(restoreSelection);
                            }
                            Component.onCompleted: {
                                if (contentItem) contentItem.highlightMoveDuration = 0;
                                Qt.callLater(restoreSelection);
                            }

                            property real calculatedWidth: cheatsheetRoot.screen ? cheatsheetRoot.screen.width * 0.92 : 1700
                            property real calculatedHeight: cheatsheetRoot.screen ? cheatsheetRoot.screen.height * 0.75 : 650

                            Layout.preferredWidth: Math.min(1800, Math.max(900, calculatedWidth))
                            Layout.preferredHeight: Math.min(850, Math.max(500, calculatedHeight))
                            spacing: 10
                            currentIndex: cheatsheetRoot.selectedTab
                            readonly property bool currentPageLocksHorizontalSwipe: currentItem
                                && currentItem.status === Loader.Ready
                                && currentItem.item
                                && currentItem.item.timetableDragActive === true
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
