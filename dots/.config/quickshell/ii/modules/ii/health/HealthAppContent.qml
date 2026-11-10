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
import qs.modules.ii.health.components
import qs.modules.ii.health.tabs

/**
 * The app inside the window, in the clock's frame: the bar across the top, the rail on
 * the left (Settings at its foot), the current page, and a side sheet that opens on the
 * right and pushes the page.
 *
 * Only the visible page exists. A finding opened from an alert, a notification or the
 * Overview arrives as `GlobalStates.healthAppPendingFinding`: the right page is
 * selected and asked to show it.
 */
FocusScope {
    id: root

    signal closeRequested()

    // ── Layout ──────────────────────────────────────────────────────────
    readonly property bool compact: root.width < ClockStyle.compactMax
    readonly property var appState: Persistent.states.healthApp
    readonly property bool canExpandRail: root.width >= ClockStyle.railExpandMin
    readonly property bool railExpanded: root.canExpandRail && (root.appState?.railExpanded ?? true)
    readonly property real railWidth: root.railExpanded ? ClockStyle.railExpandedWidth : ClockStyle.railCollapsedWidth
    readonly property real sheetWidth: root.compact
        ? root.width - ClockStyle.paneGap * 2
        : Math.max(ClockStyle.sheetWidthMin, Math.min(ClockStyle.sheetWidth, root.width * 0.28))
    readonly property real pageLayoutWidth: Math.max(0, root.width - ClockStyle.paneGap * 2
        - (root.compact ? 0 : root.railWidth + ClockStyle.paneGap)
        - (sidePanel.open && !root.compact ? root.sheetWidth + ClockStyle.paneGap : 0))
    readonly property bool wide: root.pageLayoutWidth >= ClockStyle.mediumMax

    // ── Pages ───────────────────────────────────────────────────────────
    readonly property var tabs: [
        { id: "overview", icon: "monitor_heart", label: Translation.tr("Overview") },
        { id: "services", icon: "settings_alert", label: Translation.tr("Services") },
        { id: "crashes", icon: "heart_broken", label: Translation.tr("Crashes") },
        { id: "journal", icon: "receipt_long", label: Translation.tr("Journal") },
        // Still "storage" inside: saved state and alerts point at it.
        { id: "storage", icon: "developer_board", label: Translation.tr("Hardware") },
        { id: "system", icon: "memory", label: Translation.tr("System") }
    ]
    readonly property var tabIds: root.tabs.map(tab => tab.id)
    readonly property var tabComponents: ({
        overview: overviewComponent,
        services: servicesComponent,
        crashes: crashesComponent,
        journal: journalComponent,
        storage: storageComponent,
        system: systemComponent
    })
    // The page's main action as the FAB. Pages without one hide it.
    readonly property var tabActions: ({
        overview: { label: Translation.tr("Check now"), symbol: "health_metrics" },
        storage: { label: Translation.tr("Free up space"), symbol: "cleaning_services" }
    })
    readonly property var currentAction: root.settingsOpen || !root.helperReady || pageLoader.item?.actionAvailable === false
        ? null : (root.tabActions[root.currentTab] ?? null)

    readonly property var badges: {
        const units = HealthService.findingsOfKind(["unit", "restartLoop", "appLaunch"]).length;
        const crashes = HealthService.crashGroups.filter(g => !g.muted && !(g.dismissedAt > 0)).reduce((n, g) => n + Number(g.count ?? 0), 0);
        const newErrors = HealthService.journal.groups.filter(g => g.state === "new").length;
        const storage = HealthService.findingsOfKind(HealthService.hardwareKinds).filter(f => f.sev !== "info" && !HealthService.isSnoozed(f)).length;
        const system = HealthService.findingsOfKind(["firmware", "reboot", "deletedLibs", "pacnew", "timesync", "security",
            "rebuild", "shellHelper", "shellMemory", "shellErrors", "slowBoot", "config"]).filter(f => f.sev !== "info" && !HealthService.isSnoozed(f)).length;
        return {
            overview: "",
            services: units > 0 ? String(units) : "",
            crashes: crashes > 0 ? String(crashes) : "",
            journal: newErrors > 0 ? String(newErrors) : "",
            storage: storage > 0 ? String(storage) : "",
            system: system > 0 ? String(system) : ""
        };
    }

    /// The helper has been built; until then every page is replaced by the setup page.
    readonly property bool helperReady: HealthService.binaryPresent

    property string currentTab: ""
    property string shownTab: ""
    property bool settingsOpen: false

    // The window is kept hidden for a while after closing; nothing in it should tick.
    readonly property bool shown: root.Window.window?.visible ?? true
    property double now: Date.now()

    Timer {
        interval: 30000
        repeat: true
        running: root.shown
        triggeredOnStart: true
        onTriggered: root.now = Date.now()
    }

    /// One assistant for the whole window: only one sheet or stage is ever open.
    HealthAssistant {
        id: assistant
    }

    function copyReport(): void {
        HealthService.copyReport(path => snackbar.show(Translation.tr("Report copied, and saved as %1").arg(String(path).split("/").pop()), "", null, false));
    }

    // "Check now" from any page: say it finished, and what it found.
    Connections {
        target: HealthService
        enabled: root.shown
        function onRescanned() {
            const n = HealthService.attentionCount;
            snackbar.show(Translation.tr("Checked again at %1: %2").arg(Qt.formatTime(new Date(), "hh:mm"))
                .arg(n > 0 ? HealthText.plural(n, Translation.tr("%1 thing needs attention"), Translation.tr("%1 things need attention")) : Translation.tr("all clear")), "", null, false);
        }
    }

    // An answer that arrived for a sheet or stage closed while it was being written.
    Connections {
        target: assistant
        enabled: root.shown
        function onAnswerReady(key, question) {
            if (assistant.subjectKey === key)
                return;
            snackbar.show(Translation.tr("Answer ready: %1").arg(question), Translation.tr("Open"),
                () => HealthService.openSubject(key), false);
        }
    }

    // What finished out of sight. A fixed finding's row is gone by the time its
    // restart settles, so the outcome is said here; a failure stays in its row too.
    Connections {
        target: HealthService
        enabled: root.shown
        function onActionSettled(id, action) {
            if (action?.verb === "copyReport")
                return;
            const what = action?.title ?? "";
            const text = HealthService.actionText(action);
            const bad = action?.state === "failed" || action?.state === "stillFailing";
            snackbar.show(what.length > 0 ? `${what}: ${text}` : text,
                bad && HealthService.finding(id) ? Translation.tr("Open") : "",
                () => HealthService.openFinding(id), bad);
        }
    }

    onShownChanged: {
        if (root.shown) {
            Qt.callLater(() => root.forceActiveFocus());
        } else {
            sidePanel.closeNow();
            root.settingsOpen = false;
            assistant.reset();
        }
    }

    Component.onCompleted: {
        root.currentTab = root.initialTab();
        root.shownTab = root.currentTab;
        root.consumePendingFinding();
    }

    function initialTab(): string {
        const pending = GlobalStates.healthAppPendingTab;
        GlobalStates.healthAppPendingTab = "";
        if (root.tabIds.includes(pending))
            return pending;
        const last = root.appState?.tab ?? "overview";
        return root.tabIds.includes(last) ? last : "overview";
    }

    function selectTab(tabId: string): void {
        if (!root.tabIds.includes(tabId))
            return;
        root.settingsOpen = false;
        if (tabId !== root.currentTab) {
            sidePanel.closeNow();
            assistant.reset();
        }
        root.currentTab = tabId;
        root.appState.tab = tabId;
    }

    function toggleSettings(): void {
        sidePanel.closeNow();
        assistant.reset();
        root.settingsOpen = !root.settingsOpen;
    }

    function triggerPrimaryAction(): void {
        const page = pageLoader.item;
        if (page && typeof page.primaryAction === "function")
            page.primaryAction();
    }

    /// Opens whatever finding the outside world asked for, once its page exists.
    property string _findingToShow: ""

    function consumePendingFinding(): void {
        const id = GlobalStates.healthAppPendingFinding;
        if (id.length === 0)
            return;
        GlobalStates.healthAppPendingFinding = "";
        root._findingToShow = id;
        Qt.callLater(root.showPendingFinding);
    }

    function showPendingFinding(): void {
        const page = pageLoader.item;
        if (root._findingToShow.length === 0 || !page || root.shownTab !== root.currentTab)
            return;
        if (typeof page.showFinding === "function")
            page.showFinding(root._findingToShow);
        root._findingToShow = "";
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
        function onHealthAppPendingTabChanged() {
            const pending = GlobalStates.healthAppPendingTab;
            if (pending.length === 0)
                return;
            GlobalStates.healthAppPendingTab = "";
            root.selectTab(pending);
        }
        function onHealthAppPendingFindingChanged() {
            root.consumePendingFinding();
        }
    }

    Connections {
        target: pageLoader
        function onLoaded() {
            Qt.callLater(root.showPendingFinding);
        }
    }

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
            assistant.reset();
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
        } else if (ctrl && event.key === Qt.Key_R) {
            HealthService.rescan();
            event.accepted = true;
        } else if (ctrl && (event.modifiers & Qt.ShiftModifier) && event.key === Qt.Key_C) {
            root.copyReport();
            event.accepted = true;
        } else if (event.key === Qt.Key_Question) {
            snackbar.show(Translation.tr("↑ ↓ or j k move · Enter opens · a asks the assistant · s snoozes · Ctrl+1–6 pages · Ctrl+R checks · Ctrl+Shift+C copies a report · Esc closes"), "", null, false);
            event.accepted = true;
        } else if (!root.settingsOpen && typeof pageLoader.item?.handleNavKey === "function" && pageLoader.item.handleNavKey(event)) {
            // The page's list moved, opened or acted on its focused row.
            event.accepted = true;
        } else if (event.key === Qt.Key_Escape && assistant.expanded) {
            assistant.dismiss();
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
            title: root.settingsOpen ? Translation.tr("System Health settings")
                : root.currentTab === "overview" ? Translation.tr("System Health")
                : (root.tabs.find(tab => tab.id === root.currentTab)?.label ?? "")
            subtitle: root.settingsOpen ? "" : (pageLoader.item?.pageSubtitle ?? "")
            subtitleOpacity: pageHost.opacity
            showBack: root.settingsOpen
            showRailToggle: !root.compact && root.canExpandRail
            railExpanded: root.railExpanded
            onBackRequested: root.settingsOpen = false
            onRailToggled: root.appState.railExpanded = !root.appState.railExpanded
            onCloseRequested: root.closeRequested()

            ClockIconButton {
                visible: root.helperReady && !root.settingsOpen
                symbol: "summarize"
                tooltip: Translation.tr("Copy a report for a bug report (Ctrl+Shift+C)")
                onClicked: root.copyReport()
            }
            ClockIconButton {
                visible: root.helperReady && !root.settingsOpen
                symbol: "refresh"
                tooltip: Translation.tr("Check now (Ctrl+R)")
                onClicked: HealthService.rescan()
            }
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
                settingsTooltip: Translation.tr("System Health settings")
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
                            sourceComponent: !root.helperReady ? setupComponent : (root.tabComponents[root.shownTab] ?? null)
                        }
                    }

                    HealthSnackbar {
                        id: snackbar
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.leftMargin: ClockStyle.gapLarge
                        anchors.bottomMargin: ClockStyle.gapLarge
                        // Clear of the FAB beside it.
                        anchors.rightMargin: ClockStyle.gapLarge + (pageFab.shown ? pageFab.width + ClockStyle.gap : 0)
                        z: 6
                    }

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
                        expanded: hovered
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
                            text: root.currentAction?.label ?? ""
                        }
                    }

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

                        sourceComponent: HealthSettingsPage {
                            compact: root.compact
                            wide: root.wide
                            layoutWidth: root.pageLayoutWidth
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
                }
            }
        }
    }

    Component {
        id: setupComponent
        HealthSetup {
            compact: root.compact
        }
    }

    Component {
        id: overviewComponent
        OverviewTab {
            layoutWidth: root.pageLayoutWidth
            now: root.now
            compact: root.compact
            panels: sidePanel
            assistant: assistant
            onTabRequested: tabId => root.selectTab(tabId)
        }
    }

    Component {
        id: servicesComponent
        ServicesTab {
            layoutWidth: root.pageLayoutWidth
            now: root.now
            compact: root.compact
            panels: sidePanel
            assistant: assistant
        }
    }

    Component {
        id: crashesComponent
        CrashesTab {
            layoutWidth: root.pageLayoutWidth
            now: root.now
            compact: root.compact
            assistant: assistant
        }
    }

    Component {
        id: journalComponent
        JournalTab {
            layoutWidth: root.pageLayoutWidth
            now: root.now
            compact: root.compact
            panels: sidePanel
            assistant: assistant
        }
    }

    Component {
        id: storageComponent
        StorageTab {
            layoutWidth: root.pageLayoutWidth
            now: root.now
            compact: root.compact
            panels: sidePanel
            assistant: assistant
        }
    }

    Component {
        id: systemComponent
        SystemTab {
            layoutWidth: root.pageLayoutWidth
            now: root.now
            compact: root.compact
            panels: sidePanel
            assistant: assistant
        }
    }
}
