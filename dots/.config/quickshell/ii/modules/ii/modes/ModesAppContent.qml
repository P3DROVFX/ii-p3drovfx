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
import qs.modules.ii.modes.tabs

/**
 * Modes & Routines inside its window, built from the clock app's parts: the bar across
 * the top, the rail on the left (Settings at its foot), and the current page. Each page
 * owns its side sheets, its FAB and its editor, which slides over the page as a detail
 * view; the bar then shows the editor's name and a way back.
 *
 * This is also where the assistant's run state lives: one phase (`idle` → `running` →
 * `success`/`answered`/`error`), one agent (created on the first sent request and kept
 * alive across tab switches, since the bar that started it belongs to whichever page is
 * showing), and the reveal seam — when a run produces a definition, or anything else
 * asks the engine to show one, the tab changes and the page opens it, cold or warm
 * alike. Nothing here reads `Ai`: the agent file is the module's only door to the AI
 * graph, and it opens on first use.
 */
FocusScope {
    id: root

    signal closeRequested()

    /// Hosted inside another window (the tablet family's app window), which brings its
    /// own close button.
    property bool embedded: false

    // ── Layout ──────────────────────────────────────────────────────────
    readonly property bool compact: root.width < ClockStyle.compactMax
    readonly property var appState: Persistent.states.modesApp
    readonly property bool canExpandRail: root.width >= ClockStyle.railExpandMin
    readonly property bool railExpanded: root.canExpandRail && (root.appState?.railExpanded ?? true)
    readonly property real railWidth: root.railExpanded ? ClockStyle.railExpandedWidth : ClockStyle.railCollapsedWidth
    readonly property real pageLayoutWidth: Math.max(0, root.width - ClockStyle.paneGap * 2
        - (root.compact ? 0 : root.railWidth + ClockStyle.paneGap))

    // ── Tabs ────────────────────────────────────────────────────────────
    readonly property var tabs: [
        { id: "modes", icon: "tune", label: Translation.tr("Modes") },
        { id: "routines", icon: "auto_mode", label: Translation.tr("Routines") },
        { id: "activity", icon: "history", label: Translation.tr("Activity") }
    ]
    readonly property var tabIds: root.tabs.map(tab => tab.id)
    readonly property var tabComponents: ({
        modes: modesComponent,
        routines: routinesComponent,
        activity: activityComponent
    })
    readonly property var badges: ({
        modes: Modes.activeModeId.length > 0 ? "•" : "",
        routines: "",
        activity: ""
    })

    property string currentTab: ""
    property string shownTab: ""
    property bool settingsOpen: false

    readonly property Item page: pageLoader.item
    readonly property bool detailOpen: !root.settingsOpen && (root.page?.detailOpen ?? false)

    // The window is kept hidden for a while after closing (see ModesApp).
    readonly property bool shown: root.Window.window?.visible ?? true

    function initialTab(): string {
        const pending = GlobalStates.modesAppPendingTab;
        GlobalStates.modesAppPendingTab = "";
        if (root.tabIds.includes(pending))
            return pending;
        const reveal = Modes.revealRequest;
        if (reveal?.id)
            return String(reveal.kind) === "routine" ? "routines" : "modes";
        const last = Config.options.modes?.lastTab ?? "modes";
        return root.tabIds.includes(last) ? last : "modes";
    }

    function selectTab(tabId: string): void {
        if (!root.tabIds.includes(tabId))
            return;
        root.settingsOpen = false;
        root.currentTab = tabId;
        if (Config.options.modes.lastTab !== tabId)
            Config.options.modes.lastTab = tabId;
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

    Component.onCompleted: {
        root.currentTab = root.initialTab();
        root.shownTab = root.currentTab;
    }

    onShownChanged: {
        if (root.shown) {
            const pending = root.initialTab();
            if (pending !== root.currentTab)
                root.selectTab(pending);
            Qt.callLater(root.consumeReveal);
            Qt.callLater(() => root.forceActiveFocus());
        } else {
            root.settingsOpen = false;
            root.page?.closeDetail?.();
        }
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
        function onModesAppPendingTabChanged() {
            const pending = GlobalStates.modesAppPendingTab;
            if (pending.length === 0)
                return;
            GlobalStates.modesAppPendingTab = "";
            root.selectTab(pending);
        }
    }

    // ── Assistant run ───────────────────────────────────────────────────
    // The phase is owned here so a tab switch can destroy and rebuild the page holding
    // the bar without touching the request in flight.
    property string aiPhase: "idle"
    property string aiErrorText: ""
    property string aiCreatedName: ""
    /// Latched on the first request: the agent — and with it the whole AI graph — is
    /// constructed only from then on, never by opening Modes.
    property bool aiTouched: false
    /// A definition waiting to be shown while its page is still building.
    property var pendingReveal: null

    function requestAi(text: string): void {
        root.aiErrorText = "";
        root.aiCreatedName = "";
        root.aiTouched = true;
        const agent = agentLoader.item;
        if (!agent) {
            root.aiErrorText = Translation.tr("The assistant could not start.");
            root.aiPhase = "error";
            return;
        }
        agent.submit(text);
    }

    function dismissAi(): void {
        if (root.aiPhase === "running")
            return;
        root.aiPhase = "idle";
        root.aiErrorText = "";
    }

    function revealDefinition(kind: string, id: string): void {
        root.pendingReveal = { kind: kind, id: id };
        root.selectTab(kind === "routine" ? "routines" : "modes");
        Qt.callLater(root.consumeReveal);
    }

    /// Hands the pending definition to its page once that page actually exists; the
    /// page loader calls this again when it has built. An engine request (a chat card's
    /// Open, the IPC route) is taken here too, so it is not shown twice.
    function consumeReveal(): void {
        if (!root.pendingReveal && Modes.revealRequest?.id)
            root.pendingReveal = Modes.takeRevealRequest();
        const request = root.pendingReveal;
        if (!request?.id)
            return;
        const wanted = request.kind === "routine" ? "routines" : "modes";
        if (root.currentTab !== wanted) {
            root.selectTab(wanted);
            return;
        }
        if (root.shownTab !== wanted || !root.page?.reveal)
            return;
        const exists = request.kind === "routine" ? Modes.routineById(request.id) : Modes.modeById(request.id);
        root.pendingReveal = null;
        if (exists)
            root.page.reveal(request.id);
    }

    Connections {
        target: Modes

        function onRevealRequested(request) {
            if (!request?.id)
                return;
            Qt.callLater(root.consumeReveal);
        }
    }

    // The one file in this module that touches `Ai`; the Loader is the gate.
    Loader {
        id: agentLoader
        active: root.aiTouched
        sourceComponent: ModesAiAgent {
            onAccepted: root.aiPhase = "running"
            onRejected: reason => {
                root.aiErrorText = reason;
                root.aiPhase = "error";
            }
            onFinished: (state, errorText, created, kind, id, name) => {
                if (created) {
                    root.aiCreatedName = name;
                    root.revealDefinition(kind, id);
                    root.aiPhase = "success";
                    return;
                }
                if (state === "cancelled") {
                    // The user stopped it: no failure theatre, no verdict.
                    root.aiPhase = "idle";
                    root.aiErrorText = "";
                    return;
                }
                if (state === "completed") {
                    // The model answered without writing — a refusal, a question back.
                    // The words are in the transcript, so the bar says so and points there.
                    root.aiPhase = "answered";
                    root.aiErrorText = "";
                    return;
                }
                root.aiErrorText = errorText.length > 0 ? errorText : Translation.tr("The assistant did not finish.");
                root.aiPhase = "error";
            }
        }
    }

    // ── Keys ────────────────────────────────────────────────────────────
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
        if (ctrl && event.key >= Qt.Key_1 && event.key <= Qt.Key_3) {
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
            title: root.settingsOpen ? Translation.tr("Modes & Routines settings")
                : root.detailOpen ? (root.page?.detailTitle ?? "")
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
                tabs: root.tabs
                currentTab: root.currentTab
                expanded: root.railExpanded
                settingsOpen: root.settingsOpen
                settingsTooltip: Translation.tr("Modes & Routines settings")
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
                            sourceComponent: root.tabComponents[root.shownTab] ?? null
                            onLoaded: Qt.callLater(root.consumeReveal)
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

                        sourceComponent: ModesSettingsPage {
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
                    visible: root.compact
                    tabs: root.tabs
                    currentTab: root.currentTab
                    onSelected: tabId => root.selectTab(tabId)
                }
            }
        }
    }

    Component {
        id: modesComponent
        ModesTab {
            compact: root.compact
            aiPhase: root.aiPhase
            aiErrorText: root.aiErrorText
            aiCreatedName: root.aiCreatedName
            onAiSubmitted: text => root.requestAi(text)
            onAiStopRequested: agentLoader.item?.cancel()
            onAiDismissed: root.dismissAi()
            onAiSuccessFinished: root.aiPhase = "idle"
            onAiOpenChatRequested: agentLoader.item?.openChat()
        }
    }

    Component {
        id: routinesComponent
        RoutinesTab {
            compact: root.compact
            aiPhase: root.aiPhase
            aiErrorText: root.aiErrorText
            aiCreatedName: root.aiCreatedName
            onAiSubmitted: text => root.requestAi(text)
            onAiStopRequested: agentLoader.item?.cancel()
            onAiDismissed: root.dismissAi()
            onAiSuccessFinished: root.aiPhase = "idle"
            onAiOpenChatRequested: agentLoader.item?.openChat()
        }
    }

    Component {
        id: activityComponent
        ActivityTab {
            compact: root.compact
        }
    }
}
