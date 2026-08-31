import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Qt.labs.synchronizer
import qs.modules.common.functions
import "phone"

Item {
    id: root
    required property var scopeRoot
    property int sidebarPadding: 12
    anchors.fill: parent
    property var visitedTabs: ({})

    // "Keep left sidebar loaded" has to reach the tab contents, not just the window:
    // the per-tab Loaders below are what actually hold the Phone/AI/etc. trees, so
    // gating them on sidebarLeftOpen alone threw away every open subpage on close.
    readonly property bool keepLoaded: Config.ready && Config.options.sidebar.keepLeftSidebarLoaded
    readonly property bool tabsWanted: GlobalStates.sidebarLeftOpen || root.keepLoaded
    property string routedSessionRequestId: ""

    function cycleTab(direction) {
        if (root.tabCount <= 1)
            return;
        const next = (tabBar.currentIndex + direction + root.tabCount) % root.tabCount;
        tabBar.setCurrentIndex(next);
    }

    // Policy controls must be handled at the content boundary as well as by
    // the surrounding PanelWindow/TopLayer. The active tab can contain a
    // TextEdit, which otherwise consumes Ctrl+D/P/O before the window-level
    // Keys handler sees it.
    Keys.priority: Keys.BeforeItem
    Keys.onPressed: event => {
        if ((event.modifiers & Qt.ControlModifier) === 0)
            return;

        const controller = root.scopeRoot;
        if (event.key === Qt.Key_O) {
            if (controller && typeof controller.togglePoliciesExtended === "function")
                controller.togglePoliciesExtended();
            else
                GlobalStates.policiesExtended = !GlobalStates.policiesExtended;
        } else if (event.key === Qt.Key_D) {
            if (controller && typeof controller.togglePoliciesDetach === "function")
                controller.togglePoliciesDetach();
            else
                GlobalStates.policiesDetached = !GlobalStates.policiesDetached;
        } else if (event.key === Qt.Key_P) {
            if (controller && typeof controller.togglePoliciesPin === "function")
                controller.togglePoliciesPin();
            else
                GlobalStates.policiesPinned = !GlobalStates.policiesPinned;
        } else if (event.key === Qt.Key_PageDown) {
            root.cycleTab(1);
        } else if (event.key === Qt.Key_PageUp) {
            root.cycleTab(-1);
        } else if (event.key === Qt.Key_Tab) {
            root.cycleTab((event.modifiers & Qt.ShiftModifier) ? -1 : 1);
        } else if (event.key === Qt.Key_Backtab) {
            root.cycleTab(-1);
        } else {
            return;
        }
        event.accepted = true;
    }

    // Toggles from Config
    property bool aiChatEnabled: Ai.enabled
    property bool translatorEnabled: Config.options.policies.translator !== 0
    property bool mediaEnabled: Config.options.policies.player !== 0
    property bool wallpapersEnabled: Config.options.policies.wallpapers !== 0
    property bool animeEnabled: Config.options.policies.weeb !== 0
    property bool animeCloset: Config.options.policies.weeb === 2

    // Tab and Page mapping
    property var tabs: [
        {
            icon: "neurology",
            name: Translation.tr("Intelligence"),
            enabled: root.aiChatEnabled,
            component: aiChat
        },
        {
            icon: "translate",
            name: Translation.tr("Translator"),
            enabled: root.translatorEnabled,
            component: translator
        },
        {
            icon: "music_note",
            name: Translation.tr("Media"),
            enabled: root.mediaEnabled,
            component: media
        },
        {
            icon: "wallpaper",
            name: Translation.tr("Wallpapers"),
            enabled: root.wallpapersEnabled,
            component: wallpaperBrowser
        },
        {
            icon: "bookmark_heart",
            name: Translation.tr("Anime"),
            enabled: root.animeEnabled && !root.animeCloset,
            component: anime
        },
        {
            icon: "smartphone",
            name: Translation.tr("Phone"),
            enabled: Config.options.policies.phone !== 0,
            component: phonePlaceholder
        }
    ]

    property var activeTabs: tabs.filter(t => t.enabled)
    property var tabButtonList: activeTabs.map(t => ({
                icon: t.icon,
                name: t.name
            }))
    property int tabCount: activeTabs.length
    // Holds the previously-focused tab index so the bounce-in animation
    // (mirroring the Cheatsheet tab transition) knows the direction.
    property int _prevTabIndex: Persistent.states.sidebar.policies.tab
    Component.onCompleted: {
        root._prevTabIndex = Persistent.states.sidebar.policies.tab;
    }

    function validateTabIndex() {
        if (!Persistent.ready)
            return;
        var t = Persistent.states.sidebar.policies.tab;
        if (tabCount > 0) {
            if (t < 0 || t >= tabCount) {
                Persistent.states.sidebar.policies.tab = 0;
            }
        } else {
            if (t !== 0) {
                Persistent.states.sidebar.policies.tab = 0;
            }
        }
    }

    onActiveTabsChanged: {
        root.validateTabIndex();
    }

    Connections {
        target: Persistent
        function onReadyChanged() {
            root.validateTabIndex();
        }
    }

    Connections {
        target: Persistent.states.sidebar.policies
        ignoreUnknownSignals: true
        function onTabChanged() {
            root.validateTabIndex();
        }
    }

    Connections {
        target: GlobalStates
        function onSidebarLeftOpenChanged() {
            if (!GlobalStates.sidebarLeftOpen && !root.keepLoaded) {
                root.visitedTabs = {};
            }
            if (GlobalStates.sidebarLeftOpen) {
                const animMultiplier = (Config.options && Config.options.appearance && Config.options.appearance.animationMultiplier !== undefined) ? Config.options.appearance.animationMultiplier : 1.0;
                if (animMultiplier <= 0.25) {
                    toolbarContainer.opacity = 1
                    toolbarTrans.x = 0
                    tabBar.opacity = 1
                    tabBarTrans.x = 0
                    return;
                }
                toolbarContainer.opacity = 0
                toolbarTrans.x = -80
                tabBar.opacity = 0
                tabBarTrans.x = -30
                
                toolbarEntranceAnim.stop()
                toolbarEntranceAnim.start()

                if (swipeView.currentItem && swipeView.currentItem.item && typeof swipeView.currentItem.item.triggerContentEntrance === "function") {
                    swipeView.currentItem.item.triggerContentEntrance();
                }
            }
        }
    }

    ParallelAnimation {
        id: toolbarEntranceAnim

        // Clean slide-in of navbar container from left-to-right (-80 -> 0)
        SequentialAnimation {
            PauseAnimation { duration: 30 }
            ParallelAnimation {
                NumberAnimation { target: toolbarContainer; property: "opacity"; to: 1.0; duration: 280; easing.type: Easing.OutCubic }
                NumberAnimation { target: toolbarTrans; property: "x"; to: 0; duration: 360; easing.type: Easing.OutCubic }
            }
        }

        // Staggered slide-in of tab buttons inside the navbar
        SequentialAnimation {
            PauseAnimation { duration: 90 }
            ParallelAnimation {
                NumberAnimation { target: tabBar; property: "opacity"; to: 1.0; duration: 250; easing.type: Easing.OutCubic }
                NumberAnimation { target: tabBarTrans; property: "x"; to: 0; duration: 320; easing.type: Easing.OutCubic }
            }
        }
    }

    function focusActiveItem() {
        if (swipeView.currentItem && swipeView.currentItem.item) {
            swipeView.currentItem.item.forceActiveFocus();
        }
    }

    // Nothing in the focus chain hands focus down to the tab contents, so the AI chat
    // input never gets it on its own. Focus it explicitly when the sidebar opens on that
    // tab, when the user switches to it, and when its Loader finishes activating.
    function focusAiInput() {
        if (!GlobalStates.sidebarLeftOpen) return;
        if (!root.activeTabs[swipeView.currentIndex] || root.activeTabs[swipeView.currentIndex].icon !== "neurology") return;
        if (swipeView.currentItem && swipeView.currentItem.item) {
            swipeView.currentItem.item.forceActiveFocus();
        }
    }

    // The Translator tab owns keyboard shortcuts that live on its root ("type /
    // to translate" and Ctrl+Enter to swap languages). Keys only reach that root
    // while it (or its input) holds active focus, so hand it focus the same way
    // the AI tab gets its composer focused.
    function focusTranslatorInput() {
        console.log("[TranslatorTest] focusTranslatorInput, tab icon:", root.activeTabs[swipeView.currentIndex]?.icon);
        if (!GlobalStates.sidebarLeftOpen) return;
        if (!root.activeTabs[swipeView.currentIndex] || root.activeTabs[swipeView.currentIndex].icon !== "translate") return;
        if (swipeView.currentItem && swipeView.currentItem.item) {
            swipeView.currentItem.item.forceActiveFocus();
        }
    }

    // Consume a sidebar deep-link only after the AI tab is the visible
    // SwipeView item. A requested session is selected first; until the session
    // store confirms that selection the router intent remains pending.
    function tryConsumeSurfaceIntent() {
        const intent = Ai.surfaceRouter.pendingIntent;
        if (!intent || intent.surface !== "sidebar")
            return;
        if (!GlobalStates.sidebarLeftOpen || intent.monitorName !== GlobalStates.activeLeftSidebarMonitor)
            return;
        if (!root.activeTabs[swipeView.currentIndex] || root.activeTabs[swipeView.currentIndex].icon !== "neurology" || !swipeView.currentItem || !swipeView.currentItem.item)
            return;
        if (intent.sessionId.length > 0 && Ai.sessions.currentId !== intent.sessionId) {
            if (root.routedSessionRequestId !== intent.requestId) {
                root.routedSessionRequestId = intent.requestId;
                Ai.openSession(intent.sessionId);
            }
            return;
        }
        const chat = swipeView.currentItem.item;
        if (!chat || typeof chat.applySurfaceIntent !== "function" || !chat.applySurfaceIntent(intent))
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
        target: GlobalStates
        function onSidebarLeftOpenChanged() {
            if (GlobalStates.sidebarLeftOpen) {
                Qt.callLater(root.focusAiInput);
                Qt.callLater(root.focusTranslatorInput);
            }
            root.tryConsumeSurfaceIntent();
        }
    }

    ColumnLayout {
        // Clip to the sidebar bounds. Without this, the Toolbar (with
        // Layout.alignment: Qt.AlignHCenter) overflows visibly past the sidebar
        // edges during width transitions, when the tab count changes at runtime,
        // or when translated strings are wider than the English defaults.
        clip: true
        anchors {
            fill: parent
            leftMargin: sidebarPadding
            rightMargin: sidebarPadding
            bottomMargin: sidebarPadding
            topMargin: sidebarPadding
        }
        spacing: sidebarPadding

        Item {
            id: toolbarContainer
            visible: activeTabs.length > 1
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredHeight: mainToolbar.implicitHeight
            Layout.maximumWidth: parent.width - sidebarPadding * 2
            Layout.preferredWidth: Math.min(mainToolbar.implicitWidth, parent.width - sidebarPadding * 2)

            transform: Translate {
                id: toolbarTrans
                x: 0
            }

            Toolbar {
                id: mainToolbar
                anchors.fill: parent
                enableShadow: false
                colBackground: Appearance.colors.colLayer3
                ToolbarTabBar {
                    id: tabBar
                    Layout.alignment: Qt.AlignHCenter
                    tabButtonList: root.tabButtonList
                    currentIndex: Persistent.states.sidebar.policies.tab

                    transform: Translate {
                        id: tabBarTrans
                        x: 0
                    }

                    onCurrentIndexChanged: {
                        if (currentIndex >= 0 && currentIndex < root.tabCount && Persistent.states.sidebar.policies.tab !== currentIndex) {
                            Persistent.states.sidebar.policies.tab = currentIndex;
                        }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Appearance.rounding.normal
            color: "transparent"

            SwipeView {
                id: swipeView
                anchors.fill: parent
                spacing: 10
                
                onCountChanged: {
                    if (count > 0 && Persistent.states.sidebar.policies.tab >= 0 && Persistent.states.sidebar.policies.tab < count) {
                        currentIndex = Persistent.states.sidebar.policies.tab;
                    }
                }
                
                Connections {
                    target: Persistent.states.sidebar.policies
                    function onTabChanged() {
                        if (swipeView.currentIndex !== Persistent.states.sidebar.policies.tab && Persistent.states.sidebar.policies.tab >= 0 && Persistent.states.sidebar.policies.tab < swipeView.count) {
                            swipeView.currentIndex = Persistent.states.sidebar.policies.tab;
                        }
                    }
                }

                onCurrentIndexChanged: {
                    if (currentIndex >= 0 && currentIndex < root.tabCount && Persistent.states.sidebar.policies.tab !== currentIndex) {
                        Persistent.states.sidebar.policies.tab = currentIndex;
                    }
                    Qt.callLater(() => {
                        root._prevTabIndex = currentIndex;
                    });
                    
                    if (currentIndex >= 0) {
                        var visited = root.visitedTabs;
                        if (!visited[currentIndex]) {
                            visited[currentIndex] = true;
                            root.visitedTabs = visited;
                        }
                    }

                    if (swipeView.currentItem && swipeView.currentItem.item && typeof swipeView.currentItem.item.triggerContentEntrance === "function") {
                        swipeView.currentItem.item.triggerContentEntrance();
                    }

                    Qt.callLater(root.focusAiInput);
                    Qt.callLater(root.tryConsumeSurfaceIntent);
                }

                Component.onCompleted: {
                    if (contentItem) {
                        contentItem.highlightMoveDuration = 0;
                    }
                    if (count > 0 && Persistent.states.sidebar.policies.tab >= 0 && Persistent.states.sidebar.policies.tab < count) {
                        currentIndex = Persistent.states.sidebar.policies.tab;
                    }
                    var visited = root.visitedTabs;
                    visited[currentIndex] = true;
                    root.visitedTabs = visited;
                }

                clip: true

                Repeater {
                    model: root.activeTabs
                    Loader {
                        id: tabDelegate
                        required property var modelData
                        required property int index

                        active: (root.tabsWanted && (SwipeView.isCurrentItem || !!root.visitedTabs[index]))
                                || (modelData.icon === "smartphone" && (GlobalStates.phoneMicRunning || GlobalStates.phoneCameraRunning))
                        sourceComponent: modelData.component

                        transform: Translate {
                            id: trans
                            x: 0
                        }

                        onLoaded: {
                            if (item) {
                                item.anchors.fill = this;
                                root.tryConsumeSurfaceIntent();

                                // Opening the sidebar and changing policy toggles can
                                // activate this Loader asynchronously. In that case
                                // the open/index handlers may run before AiChat exists,
                                // leaving its entrance-only content at opacity 0.
                                if (isCurrent && GlobalStates.sidebarLeftOpen) {
                                    Qt.callLater(function() {
                                        if (tabDelegate.item && tabDelegate.isCurrent && GlobalStates.sidebarLeftOpen && typeof tabDelegate.item.triggerContentEntrance === "function") {
                                            tabDelegate.item.triggerContentEntrance();
                                        }
                                    });
                                    Qt.callLater(root.focusAiInput);
                                    Qt.callLater(root.focusTranslatorInput);
                                }
                            }
                        }

                        readonly property bool isCurrent: swipeView.currentIndex === index
                        onIsCurrentChanged: {
                            if (isCurrent) {
                                const diff = index - root._prevTabIndex;
                                if (diff !== 0) {
                                    bounceAnim.stop();
                                    opacityAnim.stop();
                                    trans.x = diff > 0 ? 120 : -120;
                                    tabDelegate.opacity = 0;
                                    bounceAnim.start();
                                    opacityAnim.start();
                                }
                                // Trigger entrance animation for the tab content
                                Qt.callLater(function() {
                                    if (tabDelegate.item && typeof tabDelegate.item.triggerContentEntrance === "function") {
                                        tabDelegate.item.triggerContentEntrance();
                                    }
                                });
                                Qt.callLater(root.focusTranslatorInput);
                            } else {
                                tabDelegate.opacity = 1;
                                trans.x = 0;
                            }
                        }

                        NumberAnimation {
                            id: bounceAnim
                            target: trans
                            property: "x"
                            to: 0
                            duration: 420
                            easing.type: Easing.OutBack
                            easing.overshoot: 1.45
                        }

                        NumberAnimation {
                            id: opacityAnim
                            target: tabDelegate
                            property: "opacity"
                            from: 0
                            to: 1
                            duration: 280
                            easing.type: Easing.OutCubic
                        }
                    }
                }
            }

            // Show placeholder if no tabs are active
            Loader {
                anchors.fill: parent
                active: root.activeTabs.length === 0
                sourceComponent: placeholder
            }
        }

        Component {
            id: aiChat
            AiChat {}
        }
        Component {
            id: translator
            Translator {}
        }
        Component {
            id: media
            SidebarPlayerControl {}
        }
        Component {
            id: wallpaperBrowser
            WallpaperBrowserUI {}
        }
        Component {
            id: anime
            Anime {}
        }
        Component {
            id: phonePlaceholder
            Phone {}
        }
        Component {
            id: placeholder
            Item {
                StyledText {
                    anchors.centerIn: parent
                    text: root.animeCloset ? Translation.tr("Nothing") : Translation.tr("Enjoy your empty sidebar...")
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }
}
