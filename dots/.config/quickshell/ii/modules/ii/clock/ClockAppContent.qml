pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import Quickshell

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import qs.modules.ii.clock.tabs

/**
 * The app inside the window: navigation, the app bar, and one tab at a time.
 *
 * Only the visible tab exists. Switching fades the old one out and builds the new one,
 * so an idle tab never holds a delegate, a binding or a timer. The settings page slides
 * over the tab area and is built only while it is open.
 */
FocusScope {
    id: root

    signal closeRequested()

    // ── Layout ──────────────────────────────────────────────────────────
    readonly property bool compact: root.width < ClockStyle.compactMax
    readonly property bool wide: root.width >= ClockStyle.mediumMax
    readonly property bool useRail: !root.compact

    // ── Tabs ────────────────────────────────────────────────────────────
    readonly property var tabs: [
        { id: "alarms", icon: "alarm", label: Translation.tr("Alarms") },
        { id: "worldClock", icon: "public", label: Translation.tr("World clock") },
        { id: "timer", icon: "hourglass_top", label: Translation.tr("Timer") },
        { id: "stopwatch", icon: "timer", label: Translation.tr("Stopwatch") },
        { id: "pomodoro", icon: "timelapse", label: Translation.tr("Pomodoro") }
    ]
    readonly property var tabIds: root.tabs.map(tab => tab.id)
    readonly property var tabComponents: ({
        alarms: alarmsComponent,
        worldClock: worldClockComponent,
        timer: timerComponent,
        stopwatch: stopwatchComponent,
        pomodoro: pomodoroComponent
    })

    property string currentTab: ""
    property string shownTab: ""
    property bool settingsOpen: false

    readonly property var currentTabInfo: root.tabs.find(tab => tab.id === root.shownTab) ?? root.tabs[0]

    // ── Time ────────────────────────────────────────────────────────────
    // The app's own clock, alive only while the window is: seconds here never make the
    // rest of the shell tick every second.
    readonly property bool showSeconds: Config.options.clockApp?.showSecondsInApp ?? true
    readonly property date now: appClock.date

    SystemClock {
        id: appClock
        precision: root.showSeconds ? SystemClock.Seconds : SystemClock.Minutes
    }

    Component.onCompleted: {
        root.currentTab = root.initialTab();
        root.shownTab = root.currentTab;
    }

    function initialTab(): string {
        const pending = GlobalStates.clockAppPendingTab;
        GlobalStates.clockAppPendingTab = "";
        if (root.tabIds.includes(pending))
            return pending;
        const start = Config.options.clockApp?.startTab ?? "last";
        if (start !== "last" && root.tabIds.includes(start))
            return start;
        const last = Persistent.states.clockApp?.tab ?? "alarms";
        return root.tabIds.includes(last) ? last : "alarms";
    }

    function selectTab(tabId: string): void {
        if (!root.tabIds.includes(tabId))
            return;
        root.settingsOpen = false;
        root.currentTab = tabId;
        Persistent.states.clockApp.tab = tabId;
    }

    onCurrentTabChanged: {
        if (root.currentTab === root.shownTab || root.shownTab.length === 0)
            return;
        if (ClockStyle.reducedMotion) {
            root.shownTab = root.currentTab;
            return;
        }
        tabSwitch.restart();
    }

    Connections {
        target: GlobalStates
        function onClockAppPendingTabChanged() {
            const pending = GlobalStates.clockAppPendingTab;
            if (pending.length === 0)
                return;
            GlobalStates.clockAppPendingTab = "";
            root.selectTab(pending);
        }
    }

    // A sheet or picker that owned the keyboard is destroyed on close; hand the keys back
    // so the app shortcuts keep working without a click.
    Connections {
        target: root.Window.window
        function onActiveFocusItemChanged() {
            if (root.Window.window && !root.Window.window.activeFocusItem)
                Qt.callLater(() => root.forceActiveFocus());
        }
    }

    Keys.onPressed: event => {
        const ctrl = event.modifiers & Qt.ControlModifier;
        if (ctrl && event.key >= Qt.Key_1 && event.key <= Qt.Key_5) {
            root.selectTab(root.tabIds[event.key - Qt.Key_1]);
            event.accepted = true;
        } else if (ctrl && (event.key === Qt.Key_W || event.key === Qt.Key_Q)) {
            root.closeRequested();
            event.accepted = true;
        } else if (ctrl && event.key === Qt.Key_Comma) {
            root.settingsOpen = !root.settingsOpen;
            event.accepted = true;
        } else if (event.key === Qt.Key_Escape && root.settingsOpen) {
            root.settingsOpen = false;
            event.accepted = true;
        }
    }

    SequentialAnimation {
        id: tabSwitch

        NumberAnimation {
            target: pageHost
            property: "opacity"
            to: 0
            duration: ClockStyle.motionExit.duration / 2
            easing.type: Easing.BezierSpline
            easing.bezierCurve: ClockStyle.motionExit.bezierCurve
        }
        ScriptAction {
            script: {
                root.shownTab = root.currentTab;
                pageTranslate.y = ClockStyle.enterOffset;
            }
        }
        ParallelAnimation {
            NumberAnimation {
                target: pageHost
                property: "opacity"
                to: 1
                duration: ClockStyle.motionEnter.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: ClockStyle.motionEnter.bezierCurve
            }
            NumberAnimation {
                target: pageTranslate
                property: "y"
                to: 0
                duration: ClockStyle.motionDefault.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: ClockStyle.motionDefault.bezierCurve
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: ClockStyle.colBackground
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        ClockNavigation {
            Layout.fillHeight: true
            visible: root.useRail
            vertical: true
            tabs: root.tabs
            currentTab: root.currentTab
            onSelected: tabId => root.selectTab(tabId)
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            ClockTopBar {
                Layout.fillWidth: true
                Layout.topMargin: root.compact ? 0 : ClockStyle.gapSmall
                title: root.settingsOpen ? Translation.tr("Clock settings") : root.currentTabInfo.label
                subtitle: root.settingsOpen ? "" : (pageLoader.item?.pageSubtitle ?? "")
                showBack: root.settingsOpen
                onBackRequested: root.settingsOpen = false

                ClockIconButton {
                    visible: !root.settingsOpen
                    symbol: "settings"
                    tooltip: Translation.tr("Clock settings")
                    onClicked: root.settingsOpen = true
                }
            }

            Item {
                id: pageArea
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                Item {
                    id: pageHost
                    anchors.fill: parent
                    transform: Translate {
                        id: pageTranslate
                    }

                    Loader {
                        id: pageLoader
                        anchors.fill: parent
                        focus: !root.settingsOpen
                        sourceComponent: root.tabComponents[root.shownTab] ?? null
                    }
                }

                Loader {
                    id: settingsLoader
                    anchors.fill: parent
                    active: root.settingsOpen || settingsSlide.x < pageArea.width
                    z: 10

                    sourceComponent: ClockSettingsPage {
                        compact: root.compact
                        onTabRequested: tabId => root.selectTab(tabId)
                    }

                    transform: Translate {
                        id: settingsSlide
                        x: root.settingsOpen ? 0 : pageArea.width
                        Behavior on x {
                            enabled: !ClockStyle.reducedMotion
                            NumberAnimation {
                                duration: ClockStyle.motionDefault.duration
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: ClockStyle.motionDefault.bezierCurve
                            }
                        }
                    }
                }
            }

            ClockNavigation {
                Layout.fillWidth: true
                visible: !root.useRail
                vertical: false
                tabs: root.tabs
                currentTab: root.currentTab
                onSelected: tabId => root.selectTab(tabId)
            }
        }
    }

    Component {
        id: alarmsComponent
        AlarmsTab {
            now: root.now
            compact: root.compact
            wide: root.wide
        }
    }

    Component {
        id: worldClockComponent
        WorldClockTab {
            now: root.now
            compact: root.compact
            wide: root.wide
            showSeconds: root.showSeconds
        }
    }

    Component {
        id: timerComponent
        TimerTab {
            compact: root.compact
            wide: root.wide
        }
    }

    Component {
        id: stopwatchComponent
        StopwatchTab {
            compact: root.compact
            wide: root.wide
        }
    }

    Component {
        id: pomodoroComponent
        PomodoroTab {
            compact: root.compact
            wide: root.wide
        }
    }
}
