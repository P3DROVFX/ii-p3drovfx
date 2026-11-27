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
import qs.modules.ii.vitals.components
import qs.modules.ii.vitals.pages

/**
 * The app inside the window, in the clock's frame: the bar across the top, the rail on
 * the left (Settings at its foot), the current page, and a side sheet that opens on the
 * right and pushes the page. The page's main action is the FAB in its corner.
 *
 * The rail lists only the destinations that have data (VitalsTypes.pagesFor), so it
 * grows as the phone starts writing new types. Without data, one empty state stands in
 * for every page and says what to do next. Only the visible page exists; every page is
 * a VitalsPage (components/VitalsPage.qml has the contract).
 */
FocusScope {
    id: root

    signal closeRequested()

    // ── Layout ──────────────────────────────────────────────────────────
    readonly property bool compact: root.width < ClockStyle.compactMax
    readonly property var appState: Persistent.states.vitalsApp
    readonly property bool canExpandRail: root.width >= ClockStyle.railExpandMin
    readonly property bool railExpanded: root.canExpandRail && (root.appState?.railExpanded ?? true)
    readonly property real railWidth: root.railExpanded ? ClockStyle.railExpandedWidth : ClockStyle.railCollapsedWidth
    readonly property real sheetWidth: root.compact
        ? root.width - ClockStyle.paneGap * 2
        : Math.max(ClockStyle.sheetWidthMin, Math.min(ClockStyle.sheetWidth, root.width * 0.28))
    readonly property real pageLayoutWidth: Math.max(0, root.width - ClockStyle.paneGap * 2
        - (root.compact ? 0 : root.railWidth + ClockStyle.paneGap)
        - (sidePanel.open && !root.compact ? root.sheetWidth + ClockStyle.paneGap : 0))

    // ── Pages ───────────────────────────────────────────────────────────
    /// The store has been read; until then nothing is drawn, so the empty state does not
    /// flash before the data.
    readonly property bool storeRead: !VitalsService.enabled || VitalsService.loaded
    readonly property bool showPages: VitalsService.enabled && VitalsService.dates.length > 0
    readonly property var pageIds: root.showPages ? VitalsTypes.pagesFor(VitalsService.present) : []
    readonly property var tabs: root.pageIds.map(id => ({
        id: id,
        icon: VitalsStyle.pageInfo[id]?.icon ?? "monitoring",
        label: VitalsStyle.pageInfo[id]?.label ?? id
    }))
    readonly property var tabComponents: ({
        today: todayComponent,
        activity: activityComponent,
        sleep: sleepComponent,
        heart: heartComponent,
        workouts: workoutsComponent,
        body: bodyComponent,
        more: moreComponent
    })
    readonly property var badges: ({ today: VitalsService.syncing ? "•" : "" })

    /// The page asked for (by a caller or the last session), kept until it exists.
    property string wantedPage: ""
    property string currentPage: ""
    property string shownPage: ""
    property bool settingsOpen: false
    /// Set once the frame is built. A page asked for while the window is still being built
    /// asynchronously waits in GlobalStates until then: switching pages mid-build destroyed
    /// the page being incubated and the saved page then overwrote the one asked for.
    property bool ready: false

    readonly property Item page: pageLoader.item
    readonly property var currentFab: root.settingsOpen || !root.showPages ? null : (root.page?.fab ?? null)

    // The window is kept hidden for a while after closing; nothing in it should tick.
    readonly property bool shown: root.Window.window?.visible ?? true
    property real now: Date.now()

    Timer {
        interval: 30000
        repeat: true
        running: root.shown
        triggeredOnStart: true
        onTriggered: root.now = Date.now()
    }

    function consumePending(): void {
        if (!root.ready)
            return;
        const pending = GlobalStates.vitalsAppPendingPage;
        GlobalStates.vitalsAppPendingPage = "";
        if (pending === "settings") {
            root.openSettings();
            return;
        }
        if (pending.length > 0) {
            root.settingsOpen = false;
            root.wantedPage = pending;
        }
        root.settle();
    }

    /// Lands on the wanted page once it exists, else on Today.
    function settle(): void {
        if (!root.ready || root.pageIds.length === 0)
            return;
        const target = root.pageIds.includes(root.wantedPage) ? root.wantedPage : root.pageIds[0];
        if (target !== root.currentPage)
            root.showPage(target);
    }

    function selectPage(pageId: string): void {
        if (!root.pageIds.includes(pageId))
            return;
        root.wantedPage = pageId;
        root.appState.page = pageId;
        root.settingsOpen = false;
        root.showPage(pageId);
    }

    function showPage(pageId: string): void {
        if (pageId !== root.currentPage)
            sidePanel.closeNow();
        root.currentPage = pageId;
    }

    function openSettings(): void {
        sidePanel.closeNow();
        root.settingsOpen = true;
    }

    function toggleSettings(): void {
        if (root.settingsOpen)
            root.settingsOpen = false;
        else
            root.openSettings();
    }

    /// The phone is asked for what changed whenever the app opens while linked.
    function syncOnOpen(): void {
        if (VitalsService.linked && !VitalsService.syncing)
            VitalsService.syncNow();
    }

    Component.onCompleted: {
        root.wantedPage = root.appState?.page ?? "today";
        root.ready = true;
        root.consumePending();
        root.syncOnOpen();
    }

    onShownChanged: {
        if (root.shown) {
            root.consumePending();
            root.syncOnOpen();
            Qt.callLater(() => root.forceActiveFocus());
        } else {
            sidePanel.closeNow();
            root.settingsOpen = false;
        }
    }

    onPageIdsChanged: root.settle()

    onCurrentPageChanged: {
        if (root.currentPage === root.shownPage)
            return;
        if (root.shownPage.length === 0 || ClockStyle.reducedMotion) {
            root.shownPage = root.currentPage;
            return;
        }
        pageSwitch.restart();
    }

    Connections {
        target: GlobalStates
        function onVitalsAppPendingPageChanged() {
            if (GlobalStates.vitalsAppPendingPage.length > 0)
                root.consumePending();
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
        if (ctrl && event.key >= Qt.Key_1 && event.key <= Qt.Key_9 && event.key - Qt.Key_1 < root.pageIds.length) {
            root.selectPage(root.pageIds[event.key - Qt.Key_1]);
            event.accepted = true;
        } else if (ctrl && (event.key === Qt.Key_W || event.key === Qt.Key_Q)) {
            root.closeRequested();
            event.accepted = true;
        } else if (ctrl && event.key === Qt.Key_Comma) {
            root.toggleSettings();
            event.accepted = true;
        } else if (ctrl && event.key === Qt.Key_R) {
            if (VitalsService.linked && !VitalsService.syncing)
                VitalsService.syncNow();
            event.accepted = true;
        } else if (event.key === Qt.Key_Escape && sidePanel.open) {
            sidePanel.close();
            event.accepted = true;
        } else if (event.key === Qt.Key_Escape && root.settingsOpen) {
            root.settingsOpen = false;
            event.accepted = true;
        } else if (event.key === Qt.Key_Escape && root.page?.handleEscape()) {
            event.accepted = true;
        } else if (!root.settingsOpen && event.key !== Qt.Key_Escape && root.page) {
            event.accepted = root.page.handleKey(event.key, event.modifiers) === true;
        }
    }

    SequentialAnimation {
        id: pageSwitch

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
                root.shownPage = root.currentPage;
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
            title: root.settingsOpen ? Translation.tr("Vitals settings")
                : root.showPages ? (VitalsStyle.pageInfo[root.currentPage]?.label ?? "")
                : Translation.tr("ii Vitals")
            subtitle: root.settingsOpen ? "" : (root.page?.pageSubtitle ?? "")
            subtitleOpacity: pageHost.opacity
            showBack: root.settingsOpen
            showRailToggle: !root.compact && root.canExpandRail
            railExpanded: root.railExpanded
            onBackRequested: root.settingsOpen = false
            onRailToggled: root.appState.railExpanded = !root.appState.railExpanded
            onCloseRequested: root.closeRequested()

            // The bottom bar has no room for Settings.
            ClockIconButton {
                visible: root.compact && !root.settingsOpen
                symbol: "settings"
                tooltip: Translation.tr("Vitals settings (Ctrl+,)")
                onClicked: root.openSettings()
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
                currentTab: root.currentPage
                expanded: root.railExpanded
                settingsOpen: root.settingsOpen
                settingsTooltip: Translation.tr("Vitals settings")
                badges: root.badges
                onSelected: tabId => root.selectPage(tabId)
                onSettingsRequested: root.toggleSettings()

                Behavior on Layout.preferredWidth {
                    enabled: !ClockStyle.reducedMotion
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
                            visible: !root.settingsOpen || settingsLoader.progress < 1
                            enabled: !root.settingsOpen
                            sourceComponent: !root.storeRead ? null
                                : !root.showPages ? emptyComponent
                                : (root.tabComponents[root.shownPage] ?? null)
                        }
                    }

                    FloatingActionButton {
                        id: pageFab
                        readonly property bool shown: root.currentFab !== null
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.rightMargin: ClockStyle.gapLarge
                        anchors.bottomMargin: pageFab.shown ? ClockStyle.gapLarge : -pageFab.height - ClockStyle.gapHuge
                        z: 5
                        baseSize: ClockStyle.fabSizeLarge
                        iconSize: 34
                        buttonRadius: ClockStyle.radiusFab
                        buttonRadiusPressed: ClockStyle.radiusFabPressed
                        iconText: root.currentFab?.symbol ?? "add"
                        buttonText: root.currentFab?.label ?? ""
                        expanded: hovered
                        opacity: pageFab.shown ? 1 : 0
                        enabled: pageFab.shown
                        colBackground: ClockStyle.colPrimaryContainer
                        colBackgroundHover: ClockStyle.colPrimaryContainerHover
                        colBackgroundActive: ClockStyle.colPrimaryContainerActive
                        colRipple: ClockStyle.colPrimaryContainerActive
                        colOnBackground: ClockStyle.colOnPrimaryContainer
                        onClicked: root.page?.fabTriggered()

                        Behavior on anchors.bottomMargin {
                            enabled: !ClockStyle.reducedMotion
                            animation: ClockStyle.motionSpatial.numberAnimation.createObject(this)
                        }
                        Behavior on opacity {
                            animation: ClockStyle.motionFast.numberAnimation.createObject(this)
                        }

                        StyledToolTip {
                            text: root.currentFab?.label ?? ""
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

                        sourceComponent: VitalsSettingsPage {
                            compact: root.compact
                            layoutWidth: root.pageLayoutWidth
                            now: root.now
                        }

                        transform: Translate {
                            x: (1 - settingsLoader.progress) * Math.min(pageArea.width * 0.1, 96)
                        }
                    }
                }

                ClockNavigation {
                    Layout.fillWidth: true
                    visible: root.compact && root.tabs.length > 1
                    tabs: root.tabs
                    currentTab: root.currentPage
                    onSelected: tabId => root.selectPage(tabId)
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
        id: emptyComponent
        VitalsEmptyPage {
            compact: root.compact
            layoutWidth: root.pageLayoutWidth
            now: root.now
        }
    }

    Component {
        id: todayComponent
        VitalsTodayPage {
            compact: root.compact
            layoutWidth: root.pageLayoutWidth
            panels: sidePanel
            now: root.now
            onPageRequested: pageId => root.selectPage(pageId)
        }
    }

    Component {
        id: activityComponent
        VitalsActivityPage {
            compact: root.compact
            layoutWidth: root.pageLayoutWidth
            panels: sidePanel
            now: root.now
            onPageRequested: pageId => root.selectPage(pageId)
        }
    }

    Component {
        id: sleepComponent
        VitalsSleepPage {
            compact: root.compact
            layoutWidth: root.pageLayoutWidth
            panels: sidePanel
            now: root.now
            onPageRequested: pageId => root.selectPage(pageId)
        }
    }

    Component {
        id: heartComponent
        VitalsHeartPage {
            compact: root.compact
            layoutWidth: root.pageLayoutWidth
            panels: sidePanel
            now: root.now
            onPageRequested: pageId => root.selectPage(pageId)
        }
    }

    Component {
        id: workoutsComponent
        VitalsWorkoutsPage {
            compact: root.compact
            layoutWidth: root.pageLayoutWidth
            panels: sidePanel
            now: root.now
            onPageRequested: pageId => root.selectPage(pageId)
        }
    }

    Component {
        id: bodyComponent
        VitalsBodyPage {
            compact: root.compact
            layoutWidth: root.pageLayoutWidth
            panels: sidePanel
            now: root.now
            onPageRequested: pageId => root.selectPage(pageId)
        }
    }

    Component {
        id: moreComponent
        VitalsMorePage {
            compact: root.compact
            layoutWidth: root.pageLayoutWidth
            panels: sidePanel
            now: root.now
            onPageRequested: pageId => root.selectPage(pageId)
        }
    }
}
