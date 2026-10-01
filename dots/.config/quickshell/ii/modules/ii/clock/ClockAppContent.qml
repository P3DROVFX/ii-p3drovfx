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
import qs.modules.ii.clock.reminders

/**
 * The app inside the window, laid out like the Notes app: the bar across the top, the
 * rail on the left (collapsed or expanded, Settings at its foot), the current tab, and a
 * side sheet that opens on the right for anything that used to be a dialog.
 *
 * Only the visible tab exists. Switching fades the old one out and builds the new one,
 * so an idle tab never holds a delegate, a binding or a timer. A sheet belongs to the tab
 * that opened it and is dropped with it. The settings page slides over the tab area and
 * is built only while it is open.
 */
FocusScope {
    id: root

    signal closeRequested()

    // ── Layout ──────────────────────────────────────────────────────────
    readonly property bool compact: root.width < ClockStyle.compactMax
    readonly property var appState: Persistent.states.clockApp
    readonly property bool canExpandRail: root.width >= ClockStyle.railExpandMin
    readonly property bool railExpanded: root.canExpandRail && (root.appState?.railExpanded ?? true)
    readonly property real railWidth: root.railExpanded ? ClockStyle.railExpandedWidth : ClockStyle.railCollapsedWidth
    readonly property real sheetWidth: root.compact
        ? root.width - ClockStyle.paneGap * 2
        : Math.max(ClockStyle.sheetWidthMin, Math.min(ClockStyle.sheetWidth, root.width * 0.28))
    // The width the page will have once the rail and the sheet have settled. Pages make
    // every layout decision (columns, tile heights, type sizes) against this, and only let
    // the real, animating width stretch what they already laid out — so opening the sheet
    // slides the page narrower like the timetable does, instead of re-flowing it on every
    // frame of the animation (which is what made the tiles and their text shake).
    readonly property real pageLayoutWidth: Math.max(0, root.width - ClockStyle.paneGap * 2
        - (root.compact ? 0 : root.railWidth + ClockStyle.paneGap)
        - (sidePanel.open && !root.compact ? root.sheetWidth + ClockStyle.paneGap : 0))
    // A page is "wide" once it can hold two columns next to each other.
    readonly property bool wide: root.pageLayoutWidth >= ClockStyle.mediumMax

    // ── Tabs ────────────────────────────────────────────────────────────
    readonly property var tabs: [
        { id: "alarms", icon: "alarm", label: Translation.tr("Alarms") },
        { id: "worldClock", icon: "public", label: Translation.tr("World clock") },
        { id: "timer", icon: "hourglass_top", label: Translation.tr("Timer") },
        { id: "stopwatch", icon: "timer", label: Translation.tr("Stopwatch") },
        { id: "pomodoro", icon: "timelapse", label: Translation.tr("Pomodoro") },
        { id: "bedtime", icon: "bedtime", label: Translation.tr("Bedtime") },
        { id: "reminders", icon: "task_alt", label: Translation.tr("Reminders") }
    ]
    readonly property var tabIds: root.tabs.map(tab => tab.id)
    readonly property var tabComponents: ({
        alarms: alarmsComponent,
        worldClock: worldClockComponent,
        timer: timerComponent,
        stopwatch: stopwatchComponent,
        pomodoro: pomodoroComponent,
        bedtime: bedtimeComponent,
        reminders: remindersComponent
    })
    // The main action of each tab, shown at the top of the rail (or as a FAB when the
    // rail is gone). Stopwatch and pomodoro drive everything from their own controls.
    readonly property var tabActions: ({
        alarms: { label: Translation.tr("New alarm"), symbol: "alarm_add" },
        worldClock: { label: Translation.tr("Add city"), symbol: "add_location_alt" },
        timer: { label: Translation.tr("New timer"), symbol: "add" },
        reminders: { label: Translation.tr("New reminder"), symbol: "add_task" }
    })
    readonly property var currentAction: root.settingsOpen || pageLoader.item?.actionAvailable === false
        ? null : (root.tabActions[root.currentTab] ?? null)

    readonly property var badges: {
        const countdowns = Array.from(TimerService.countdowns ?? []);
        const runningTimers = countdowns.filter(timer => !timer.paused && !timer.notified).length;
        const enabledAlarms = Array.from(AlarmService.alarms ?? []).filter(alarm => alarm?.enabled).length;
        return {
            alarms: enabledAlarms > 0 ? String(enabledAlarms) : "",
            worldClock: WorldClockService.clocks.length > 0 ? String(WorldClockService.clocks.length) : "",
            timer: runningTimers > 0 ? String(runningTimers) : "",
            stopwatch: TimerService.stopwatchRunning ? "•" : "",
            pomodoro: TimerService.pomodoroRunning ? "•" : "",
            bedtime: BedtimeService.phase !== "none" ? "•" : "",
            reminders: RemindersService.activeCount > 0 ? String(RemindersService.activeCount) : ""
        };
    }

    property string currentTab: ""
    property string shownTab: ""
    property bool settingsOpen: false

    readonly property var currentTabInfo: root.tabs.find(tab => tab.id === root.shownTab) ?? root.tabs[0]

    // ── Time ────────────────────────────────────────────────────────────
    // The app's own clock, alive only while the window is: seconds here never make the
    // rest of the shell tick every second.
    readonly property bool showSeconds: Config.options.clockApp?.showSecondsInApp ?? true
    readonly property date now: appClock.date

    // The window is kept hidden for a while after closing (see ClockApp); nothing in it
    // should tick for a screen nobody sees.
    readonly property bool shown: root.Window.window?.visible ?? true

    SystemClock {
        id: appClock
        enabled: root.shown
        precision: root.showSeconds ? SystemClock.Seconds : SystemClock.Minutes
    }

    onShownChanged: {
        if (root.shown) {
            Qt.callLater(() => root.forceActiveFocus());
        } else {
            sidePanel.closeNow();
            root.settingsOpen = false;
        }
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
        const last = root.appState?.tab ?? "alarms";
        return root.tabIds.includes(last) ? last : "alarms";
    }

    function selectTab(tabId: string): void {
        if (!root.tabIds.includes(tabId))
            return;
        root.settingsOpen = false;
        if (tabId !== root.currentTab)
            sidePanel.closeNow();
        root.currentTab = tabId;
        root.appState.tab = tabId;
    }

    function toggleSettings(): void {
        sidePanel.closeNow();
        root.settingsOpen = !root.settingsOpen;
    }

    function triggerPrimaryAction(): void {
        const page = pageLoader.item;
        if (page && typeof page.primaryAction === "function")
            page.primaryAction();
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

    // A sheet or field that owned the keyboard is destroyed on close; hand the keys back
    // so the app shortcuts keep working without a click.
    Connections {
        target: root.Window.window
        function onActiveFocusItemChanged() {
            if (root.Window.window && !root.Window.window.activeFocusItem)
                Qt.callLater(() => root.forceActiveFocus());
        }
    }

    Connections {
        target: sidePanel
        function onClosed() {
            Qt.callLater(() => {
                if (pageLoader.item)
                    pageLoader.item.forceActiveFocus();
                else
                    root.forceActiveFocus();
            });
        }
    }

    Keys.onPressed: event => {
        const ctrl = event.modifiers & Qt.ControlModifier;
        if (ctrl && event.key >= Qt.Key_1 && event.key <= Qt.Key_9 && event.key - Qt.Key_1 < root.tabIds.length) {
            root.selectTab(root.tabIds[event.key - Qt.Key_1]);
            event.accepted = true;
        } else if (ctrl && (event.key === Qt.Key_W || event.key === Qt.Key_Q)) {
            root.closeRequested();
            event.accepted = true;
        } else if (ctrl && event.key === Qt.Key_Comma) {
            root.toggleSettings();
            event.accepted = true;
        } else if (ctrl && event.key === Qt.Key_N && root.currentAction) {
            root.triggerPrimaryAction();
            event.accepted = true;
        } else if (event.key === Qt.Key_Escape && sidePanel.open) {
            sidePanel.close();
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

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: ClockStyle.paneGap
        anchors.topMargin: ClockStyle.gapTiny
        spacing: ClockStyle.gapTiny

        ClockTopBar {
            Layout.fillWidth: true
            // The title follows the tab you picked at once; the subtitle belongs to the page
            // and fades with it, so the two never disagree mid-switch.
            title: root.settingsOpen ? Translation.tr("Clock settings") : (root.tabs.find(tab => tab.id === root.currentTab)?.label ?? "")
            subtitle: root.settingsOpen ? "" : (pageLoader.item?.pageSubtitle ?? "")
            subtitleOpacity: pageHost.opacity
            showBack: root.settingsOpen
            showRailToggle: !root.compact && root.canExpandRail
            railExpanded: root.railExpanded
            onBackRequested: root.settingsOpen = false
            onRailToggled: root.appState.railExpanded = !root.appState.railExpanded
            onCloseRequested: root.closeRequested()
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            ClockRail {
                Layout.fillHeight: true
                Layout.preferredWidth: root.railWidth
                Layout.rightMargin: ClockStyle.paneGap
                visible: !root.compact
                tabs: root.tabs
                currentTab: root.currentTab
                expanded: root.railExpanded
                settingsOpen: root.settingsOpen
                badges: root.badges
                onSelected: tabId => root.selectTab(tabId)
                onSettingsRequested: root.toggleSettings()

                Behavior on Layout.preferredWidth {
                    animation: ClockStyle.motionFast.numberAnimation.createObject(this)
                }
            }

            ColumnLayout {
                id: pageColumn
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: !(root.compact && sidePanel.open)
                spacing: ClockStyle.paneGap

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
                            focus: !root.settingsOpen && !sidePanel.open
                            sourceComponent: root.tabComponents[root.shownTab] ?? null
                        }
                    }

                    // The tab's main action as a large FAB in the page's own corner. It
                    // lives in the page area, so an opening sheet pushes it along with
                    // the page instead of covering it.
                    FloatingActionButton {
                        id: pageFab
                        readonly property bool shown: root.currentAction !== null
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.rightMargin: ClockStyle.gapLarge
                        anchors.bottomMargin: pageFab.shown ? ClockStyle.gapLarge : -pageFab.height - ClockStyle.gapHuge
                        z: 5
                        baseSize: ClockStyle.fabSizeLarge
                        iconSize: 34
                        buttonRadius: Appearance.rounding.large
                        buttonRadiusPressed: Appearance.rounding.normal
                        iconText: root.currentAction?.symbol ?? "add"
                        buttonText: root.currentAction?.label ?? ""
                        // The cheatsheet's FAB: the label unfolds to the left on hover.
                        expanded: hovered
                        shortcut: "Ctrl\n+ N"
                        opacity: pageFab.shown ? 1 : 0
                        enabled: pageFab.shown
                        colBackground: Appearance.colors.colPrimaryContainer
                        colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                        colBackgroundActive: Appearance.colors.colPrimaryContainerActive
                        colRipple: Appearance.colors.colPrimaryContainerActive
                        colOnBackground: Appearance.colors.colOnPrimaryContainer
                        onClicked: root.triggerPrimaryAction()

                        Behavior on anchors.bottomMargin {
                            animation: ClockStyle.motionSpatial.numberAnimation.createObject(this)
                        }
                        Behavior on opacity {
                            animation: ClockStyle.motionFast.numberAnimation.createObject(this)
                        }

                        StyledToolTip {
                            text: (root.currentAction?.label ?? "") + " (Ctrl+N)"
                        }
                    }

                    // Settings slides over the tab. The slide is a 0→1 progress, not an
                    // x bound to the page width: a width that grows while the side sheet
                    // closes would otherwise drag a "closed" page back into view.
                    Loader {
                        id: settingsLoader
                        property real progress: root.settingsOpen ? 1 : 0

                        anchors.fill: parent
                        active: root.settingsOpen || progress > 0
                        visible: progress > 0
                        z: 10

                        opacity: progress
                        Behavior on progress {
                            enabled: !ClockStyle.reducedMotion
                            NumberAnimation {
                                duration: root.settingsOpen ? ClockStyle.motionEnter.duration : ClockStyle.motionExit.duration
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: root.settingsOpen ? Appearance.animationCurves.emphasizedDecel : Appearance.animationCurves.emphasizedAccel
                            }
                        }

                        sourceComponent: ClockSettingsPage {
                            compact: root.compact
                            wide: root.wide
                            layoutWidth: root.pageLayoutWidth
                            onTabRequested: tabId => root.selectTab(tabId)
                        }

                        transform: Translate {
                            x: (1 - settingsLoader.progress) * Math.min(pageArea.width * 0.1, 96)
                        }
                    }
                }

                ClockNavigation {
                    Layout.fillWidth: true
                    visible: root.compact
                    tabs: root.tabs
                    currentTab: root.currentTab
                    onSelected: tabId => root.selectTab(tabId)
                }
            }

            // ── Side sheet ──────────────────────────────────────────────
            // The slot animates its width and clips; the sheet inside keeps its own
            // width pinned to the right, so it slides in instead of reflowing.
            Item {
                id: sheetSlot
                Layout.fillHeight: true
                Layout.preferredWidth: sidePanel.open ? root.sheetWidth + (root.compact ? 0 : ClockStyle.paneGap) : 0
                visible: Layout.preferredWidth > 1
                clip: true

                Behavior on Layout.preferredWidth {
                    enabled: !ClockStyle.reducedMotion
                    animation: ClockStyle.motionDefault.numberAnimation.createObject(this)
                }

                ClockSidePanel {
                    id: sidePanel
                    anchors {
                        top: parent.top
                        bottom: parent.bottom
                        right: parent.right
                    }
                    width: root.sheetWidth
                    pickers: pickerHost
                }
            }
        }
    }

    ClockPickerHost {
        id: pickerHost
        anchors.fill: parent
        z: 100
    }

    Component {
        id: alarmsComponent
        AlarmsTab {
            layoutWidth: root.pageLayoutWidth
            now: root.now
            compact: root.compact
            wide: root.wide
            panels: sidePanel
        }
    }

    Component {
        id: worldClockComponent
        WorldClockTab {
            layoutWidth: root.pageLayoutWidth
            now: root.now
            compact: root.compact
            wide: root.wide
            showSeconds: root.showSeconds
            panels: sidePanel
        }
    }

    Component {
        id: timerComponent
        TimerTab {
            layoutWidth: root.pageLayoutWidth
            compact: root.compact
            wide: root.wide
            panels: sidePanel
        }
    }

    Component {
        id: stopwatchComponent
        StopwatchTab {
            layoutWidth: root.pageLayoutWidth
            compact: root.compact
            wide: root.wide
        }
    }

    Component {
        id: bedtimeComponent
        BedtimeTab {
            layoutWidth: root.pageLayoutWidth
            now: root.now
            compact: root.compact
            wide: root.wide
            panels: sidePanel
        }
    }

    Component {
        id: remindersComponent
        RemindersTab {
            layoutWidth: root.pageLayoutWidth
            now: root.now
            compact: root.compact
            wide: root.wide
            panels: sidePanel
            onSettingsRequested: root.toggleSettings()
        }
    }

    Component {
        id: pomodoroComponent
        PomodoroTab {
            layoutWidth: root.pageLayoutWidth
            compact: root.compact
            wide: root.wide
        }
    }
}
