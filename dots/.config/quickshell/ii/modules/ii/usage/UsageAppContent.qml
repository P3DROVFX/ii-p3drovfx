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
import qs.modules.ii.usage.limits

/**
 * The App usage app inside its window, built from the clock app's parts so the two read
 * as one family: the bar across the top, the rail on the left (Settings at its foot),
 * and the current page. Each page owns its side sheets and its FAB, the way the Limits
 * page already did inside the old overlay.
 *
 * Only the visible page exists. What is being looked at — the period, the metric, the
 * picked app — lives here in `viewState`, so moving between App usage and Battery keeps
 * the same day on screen, and a fresh opening starts from the remembered view.
 *
 * Without the sampler there is nothing to show on any page, so the setup page stands in
 * for all of them until it has been built.
 */
FocusScope {
    id: root

    signal closeRequested()

    /// Hosted inside another window (the tablet family's app window), which brings its
    /// own close button.
    property bool embedded: false

    // ── Layout ──────────────────────────────────────────────────────────
    readonly property bool compact: root.width < ClockStyle.compactMax
    readonly property var appState: Persistent.states.usageApp
    readonly property bool canExpandRail: root.width >= ClockStyle.railExpandMin
    readonly property bool railExpanded: root.canExpandRail && (root.appState?.railExpanded ?? true)
    readonly property real railWidth: root.railExpanded ? ClockStyle.railExpandedWidth : ClockStyle.railCollapsedWidth
    readonly property real pageLayoutWidth: Math.max(0, root.width - ClockStyle.paneGap * 2
        - (root.compact ? 0 : root.railWidth + ClockStyle.paneGap))

    // ── Tabs ────────────────────────────────────────────────────────────
    readonly property var opts: Config.options.appStats
    /// The battery page exists only on a machine that has one; limits only while on.
    readonly property var tabs: {
        const list = [{ id: "apps", icon: "query_stats", label: Translation.tr("App usage") }];
        if (Battery.available)
            list.push({ id: "battery", icon: "battery_full", label: Translation.tr("Battery") });
        if (Config.options.screenTime?.enable ?? true)
            list.push({ id: "limits", icon: "hourglass_top", label: Translation.tr("Daily limits") });
        return list;
    }
    readonly property var tabIds: root.tabs.map(tab => tab.id)
    readonly property var tabComponents: ({
        apps: appsComponent,
        battery: batteryComponent,
        limits: limitsComponent
    })
    readonly property var badges: ({
        apps: "",
        battery: Battery.available && Battery.isCharging ? "•" : "",
        limits: ScreenTimeLimits.paused ? "•" : ""
    })

    property string currentTab: ""
    property string shownTab: ""
    property bool settingsOpen: false
    /// An app whose new limit the Limits page opens once it has been built.
    property string pendingLimitKey: ""

    readonly property bool setupNeeded: !AppStats.binaryPresent
    readonly property Item page: pageLoader.item
    readonly property bool detailOpen: !root.settingsOpen && (root.page?.detailOpen ?? false)

    // The window is kept hidden for a while after closing (see UsageApp).
    readonly property bool shown: root.Window.window?.visible ?? true

    // ── What is on screen ───────────────────────────────────────────────
    // Granularity and metric are keys rather than indexes: the config stores them by
    // name, and a reordered chip row must not silently change what opens.
    QtObject {
        id: viewState

        property string granularity: "day"
        property string metricKey: "fg"
        /// Periods back from the current one: 0 is today / this week / this month.
        property int periodOffset: 0
        property string selectedKey: ""

        onGranularityChanged: root.rememberView()
        onMetricKeyChanged: root.rememberView()
    }

    /// Which view a fresh opening starts on. Always the current period — going back is
    /// deliberate, and reopening days later onto a stale month would read as missing data.
    function resolveView(): void {
        const remembered = root.opts?.rememberLastView ?? true;
        viewState.granularity = (remembered ? root.opts?.lastGranularity : root.opts?.defaultGranularity) ?? "day";
        viewState.metricKey = (remembered ? root.opts?.lastMetric : root.opts?.defaultMetric) ?? "fg";
        viewState.periodOffset = 0;
        if (!(root.opts?.keepSelection ?? false))
            viewState.selectedKey = "";
    }

    function rememberView(): void {
        if (!(root.opts?.rememberLastView ?? true))
            return;
        if (root.opts.lastGranularity !== viewState.granularity)
            root.opts.lastGranularity = viewState.granularity;
        if (root.opts.lastMetric !== viewState.metricKey)
            root.opts.lastMetric = viewState.metricKey;
    }

    function initialTab(): string {
        const pending = GlobalStates.usageAppPendingTab;
        GlobalStates.usageAppPendingTab = "";
        if (root.tabIds.includes(pending))
            return pending;
        const last = (root.opts?.rememberLastView ?? true) ? (root.opts?.lastView ?? "apps") : "apps";
        return root.tabIds.includes(last) ? last : "apps";
    }

    function selectTab(tabId: string): void {
        if (!root.tabIds.includes(tabId))
            return;
        root.settingsOpen = false;
        root.currentTab = tabId;
        if ((root.opts?.rememberLastView ?? true) && root.opts.lastView !== tabId)
            root.opts.lastView = tabId;
    }

    function toggleSettings(): void {
        root.settingsOpen = !root.settingsOpen;
    }

    function goBack(): void {
        if (root.settingsOpen)
            root.settingsOpen = false;
        else
            root.page?.closeDetail?.();
    }

    function openLimitFor(appKey: string): void {
        if (!root.tabIds.includes("limits"))
            return;
        root.pendingLimitKey = appKey;
        if (root.currentTab === "limits")
            root.consumePendingLimit();
        else
            root.selectTab("limits");
    }

    function consumePendingLimit(): void {
        const key = root.pendingLimitKey;
        if (key.length === 0 || root.shownTab !== "limits" || !root.page?.newLimitFor)
            return;
        root.pendingLimitKey = "";
        // An app already under a limit opens that limit rather than a duplicate.
        const existing = ScreenTimeLimits.limits.find(rule => rule.kind !== "total" && (rule.keys ?? []).includes(key));
        if (existing)
            root.page.editLimit(existing);
        else
            root.page.newLimitFor(key);
    }

    Component.onCompleted: {
        root.resolveView();
        root.currentTab = root.initialTab();
        root.shownTab = root.currentTab;
    }

    onShownChanged: {
        if (root.shown) {
            root.resolveView();
            const pending = root.initialTab();
            if (pending !== root.currentTab)
                root.selectTab(pending);
            refreshTimer.restart();
            Qt.callLater(() => root.forceActiveFocus());
        } else {
            refreshTimer.stop();
            root.settingsOpen = false;
            root.page?.closeDetail?.();
        }
    }

    // The flush rereads today and recomputes every figure; done while the window is
    // still mapping, that recompute cost the first frames.
    Timer {
        id: refreshTimer
        interval: 250
        running: true
        onTriggered: AppStats.refresh()
    }

    // A tab that disappears (the limits switched off) cannot stay selected.
    onTabIdsChanged: {
        if (root.currentTab.length > 0 && !root.tabIds.includes(root.currentTab))
            root.selectTab("apps");
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
        function onUsageAppPendingTabChanged() {
            const pending = GlobalStates.usageAppPendingTab;
            if (pending.length === 0)
                return;
            GlobalStates.usageAppPendingTab = "";
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

    Keys.onPressed: event => {
        const ctrl = event.modifiers & Qt.ControlModifier;
        if (ctrl && event.key >= Qt.Key_1 && event.key < Qt.Key_1 + root.tabIds.length) {
            root.selectTab(root.tabIds[event.key - Qt.Key_1]);
            event.accepted = true;
        } else if (ctrl && (event.key === Qt.Key_W || event.key === Qt.Key_Q) && !root.embedded) {
            root.closeRequested();
            event.accepted = true;
        } else if (ctrl && event.key === Qt.Key_Comma) {
            root.toggleSettings();
            event.accepted = true;
        } else if (event.key === Qt.Key_Escape) {
            if (!root.settingsOpen && root.page?.handleEscape?.())
                event.accepted = true;
            else if (root.settingsOpen) {
                root.settingsOpen = false;
                event.accepted = true;
            }
        } else if (!root.settingsOpen && root.page?.handleKey) {
            event.accepted = root.page.handleKey(event.key, event.modifiers) === true;
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
            title: root.settingsOpen ? Translation.tr("App usage settings")
                : root.detailOpen ? (root.page?.detailTitle ?? "")
                : root.setupNeeded ? Translation.tr("App usage")
                : (root.tabs.find(tab => tab.id === root.currentTab)?.label ?? "")
            subtitle: root.settingsOpen || root.detailOpen ? "" : (root.page?.pageSubtitle ?? "")
            subtitleOpacity: pageHost.opacity
            showBack: root.settingsOpen || root.detailOpen
            showRailToggle: !root.compact && root.canExpandRail
            showClose: !root.embedded
            railExpanded: root.railExpanded
            onBackRequested: root.goBack()
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
                tabs: root.setupNeeded ? [] : root.tabs
                currentTab: root.currentTab
                expanded: root.railExpanded
                settingsOpen: root.settingsOpen
                settingsTooltip: Translation.tr("App usage settings")
                badges: root.badges
                onSelected: tabId => root.selectTab(tabId)
                onSettingsRequested: root.toggleSettings()

                Behavior on Layout.preferredWidth {
                    animation: ClockStyle.motionFast.numberAnimation.createObject(this)
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
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
                            focus: !root.settingsOpen
                            visible: !root.settingsOpen || settingsLoader.progress < 1
                            enabled: !root.settingsOpen
                            sourceComponent: root.setupNeeded ? setupComponent
                                : (root.tabComponents[root.shownTab] ?? null)
                            onLoaded: Qt.callLater(root.consumePendingLimit)
                        }
                    }

                    // Settings slides over the page, as in the clock app.
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

                        sourceComponent: UsageSettingsPage {
                            compact: root.compact
                            layoutWidth: root.pageLayoutWidth
                        }

                        transform: Translate {
                            x: (1 - settingsLoader.progress) * Math.min(pageArea.width * 0.1, 96)
                        }
                    }
                }

                ClockNavigation {
                    Layout.fillWidth: true
                    visible: root.compact && !root.setupNeeded && root.tabs.length > 1
                    tabs: root.tabs
                    currentTab: root.currentTab
                    onSelected: tabId => root.selectTab(tabId)
                }
            }
        }
    }

    Component {
        id: setupComponent
        UsageSetup {}
    }

    Component {
        id: appsComponent
        UsageAppsPage {
            compact: root.compact
            viewState: viewState
            onLimitRequested: appKey => root.openLimitFor(appKey)
        }
    }

    Component {
        id: batteryComponent
        UsageBatteryPage {
            compact: root.compact
            viewState: viewState
        }
    }

    Component {
        id: limitsComponent
        UsageLimits {}
    }
}
