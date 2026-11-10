import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.models
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root
    property int entranceTrigger: -1
    // Defensive fallback for alternate hosts smaller than the dashboard's
    // fixed 350px bottom group.
    readonly property bool compact: root.height > 0 && root.height < 300
    property var tabButtonList: [
        {
            "name": Translation.tr("Pomodoro"),
            "icon": "search_activity"
        },
        {
            "name": Translation.tr("Stopwatch"),
            "icon": "timer"
        },
        {
            "name": Translation.tr("Timer"),
            "icon": "hourglass_top"
        }
    ]
    property int selectedTab: Math.max(0, Math.min(root.tabButtonList.length - 1,
        Persistent.states.sidebar.bottomGroup.timerTab))
    property bool keyboardEnabled: false
    property bool showShortcutHints: false

    function selectTab(index) {
        if (index < 0 || index >= root.tabButtonList.length || root.selectedTab === index)
            return;

        root.selectedTab = index;
        Persistent.states.sidebar.bottomGroup.timerTab = index;
    }


    function toggleActiveTimer() {
        if (root.selectedTab === 0)
            TimerService.togglePomodoro();
        else if (root.selectedTab === 1)
            TimerService.toggleStopwatch();
        else
            TimerService.startDraftCountdown();
    }

    function resetActiveTimer() {
        if (root.selectedTab === 0)
            TimerService.resetPomodoro();
        else if (root.selectedTab === 1 && !TimerService.stopwatchRunning)
            TimerService.stopwatchReset();
    }

    function handleKey(event) {
        if (!root.keyboardEnabled)
            return false;
        const plain = event.modifiers === Qt.NoModifier || event.modifiers === Qt.ControlModifier;
        if (event.modifiers === Qt.ControlModifier && event.key >= Qt.Key_1 && event.key <= Qt.Key_3) {
            if (!event.isAutoRepeat) root.selectTab(event.key - Qt.Key_1);
            return true;
        }
        if (event.modifiers === Qt.NoModifier && (event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp)) {
            if (!event.isAutoRepeat)
                root.selectTab(root.selectedTab + (event.key === Qt.Key_PageDown ? 1 : -1));
            return true;
        }
        if (event.modifiers === Qt.ControlModifier && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
            if (!event.isAutoRepeat) root.toggleActiveTimer();
            return true;
        }
        if (root.selectedTab === 2)
            return countdownLoader.item?.handleKey(event) ?? false;
        if (plain && (event.key === Qt.Key_Space || event.key === Qt.Key_S)) {
            if (!event.isAutoRepeat) root.toggleActiveTimer();
            return true;
        }
        if (plain && event.key === Qt.Key_R) {
            if (!event.isAutoRepeat) root.resetActiveTimer();
            return true;
        }
        if (plain && event.key === Qt.Key_L && root.selectedTab === 1) {
            if (!event.isAutoRepeat) TimerService.stopwatchRecordLap();
            return true;
        }
        if (plain && event.key === Qt.Key_E && root.selectedTab === 0) {
            if (!event.isAutoRepeat) TimerService.requestCustomTime();
            return true;
        }
        return false;
    }


    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Toolbar {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredHeight: Appearance.sizes.toolbarHeight
            enableShadow: false
            colBackground: Appearance.colors.colSurfaceContainer
            ToolbarTabBar {
                id: tabBar
                tabButtonList: root.tabButtonList
                // Three labelled tabs are wider than the sidebar; only the
                // selected one keeps its label.
                collapseInactiveLabels: true
                requestOnly: true
                currentIndex: root.selectedTab
                onIndexSelected: root.selectTab(index)
                delegate: ToolbarTabButton {
                    id: timerTab
                    required property int index
                    required property var modelData
                    current: index === root.selectedTab
                    text: modelData.name
                    materialSymbol: modelData.icon
                    collapseInactiveLabel: true
                    onClicked: root.selectTab(index)
                    Accessible.name: modelData.name
                    contentItem: Row {
                        anchors.centerIn: parent
                        spacing: timerTab.labelCollapsed ? 0 : 6
                        TaskShortcutContent {
                            anchors.verticalCenter: parent.verticalCenter
                            width: Appearance.font.pixelSize.smallest * 3
                            height: Appearance.font.pixelSize.larger
                            symbol: timerTab.materialSymbol
                            fill: timerTab.current ? 1 : 0
                            shortcut: String(timerTab.index + 1)
                            showHint: root.showShortcutHints
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: timerTab.text
                            visible: !timerTab.labelCollapsed
                        }
                    }
                }
            }
        }

        SwipeView {
            id: swipeView
            property bool initialized: false
            Layout.topMargin: root.compact ? 4 : 10
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 10
            clip: true
            currentIndex: root.selectedTab
            Component.onCompleted: initialized = true
            onCurrentIndexChanged: {
                if (initialized && currentIndex !== root.selectedTab)
                    root.selectTab(currentIndex);
            }

            // Tabs: only the selected timer owns its visual tree.
            Loader {
                active: root.selectedTab === 0
                asynchronous: true
                sourceComponent: PomodoroTimer {
                    entranceTrigger: root.entranceTrigger
                    showShortcutHints: root.showShortcutHints
                }
                id: pomodoroLoader
            }
            Loader {
                active: root.selectedTab === 1
                asynchronous: true
                id: stopwatchLoader
                sourceComponent: Stopwatch {
                    entranceTrigger: root.entranceTrigger
                    showShortcutHints: root.showShortcutHints
                }
            }
            Loader {
                active: root.selectedTab === 2
                asynchronous: true
                id: countdownLoader
                sourceComponent: CountdownTimer {
                    entranceTrigger: root.entranceTrigger
                    showShortcutHints: root.showShortcutHints
                }
            }
        }
    }

}
