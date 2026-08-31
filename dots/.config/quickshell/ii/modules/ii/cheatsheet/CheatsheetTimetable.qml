import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import "timetable"

/**
 * Host for the timetable calendar shapes.
 *
 * Owns the plate both views sit on, and nothing else: the week grid and the
 * month grid are independent trees, and only the selected one exists. The
 * selector itself lives in the cheatsheet header, so this file never has to
 * know how the choice is made — it just follows the persisted state.
 */
Item {
    id: root

    focus: true

    property real maxContentWidth: 1600
    property real maxHeight: 700

    implicitWidth: root.maxContentWidth
    implicitHeight: root.maxHeight

    readonly property var supportedModes: ["day", "threeDay", "week", "month"]

    // The persisted value reads back invalid for a moment whenever Persistent
    // loads or reloads the file it watches — and opening this tab writes to
    // that file. Treating the gap as a real mode change cost a whole fade out
    // and back in for a value that never changed, twice over, which is the
    // blink that went away once the state settled. The last valid mode stays.
    readonly property string persistedMode: String(Persistent.states.cheatsheet?.timetableView ?? "")
    property string requestedMode: "week"
    property string activeMode: "week"
    property bool viewInitialised: false

    onPersistedModeChanged: root.adoptPersistedMode()

    function adoptPersistedMode() {
        if (!root.supportedModes.includes(root.persistedMode))
            return;
        root.requestedMode = root.persistedMode;
    }

    property bool sportsSubscriberAcquired: false
    property bool sportsReady: false
    readonly property bool sportsRequested: Config.options.calendar.timetable.sportsEvents
    readonly property var activeViewItem: root.activeMode === "month" ? monthViewLoader.item : weekViewLoader.item
    readonly property bool activeViewReady: root.activeViewItem?.initialLoadComplete ?? false
    readonly property bool timetableDragActive: root.activeViewItem?.timetableDragActive === true

    Keys.priority: Keys.AfterItem
    Keys.onPressed: event => {
        if (!root.activeViewItem || typeof root.activeViewItem.handleNavigationKey !== "function")
            return;
        event.accepted = root.activeViewItem.handleNavigationKey(event);
    }

    function openRequestedDate() {
        if (GlobalStates.timetableNavigationRequest <= 0)
            return;
        // Opening a concrete date uses the month grid, where the selected day
        // and its event rail are visible together. This is an explicit action,
        // so persisting the mode also keeps the header selector truthful.
        if (Persistent.states.cheatsheet.timetableView !== "month")
            Persistent.states.cheatsheet.timetableView = "month";
    }

    Component.onCompleted: {
        root.adoptPersistedMode();
        root.activeMode = root.requestedMode;
        root.openRequestedDate();
    }

    Connections {
        target: GlobalStates
        function onTimetableNavigationRequestChanged() {
            root.openRequestedDate();
        }
    }

    function syncSportsSubscription() {
        if (!root.sportsRequested) {
            sportsActivationTimer.stop();
            if (root.sportsSubscriberAcquired) {
                SportsService.releaseTimetableSubscriber();
                root.sportsSubscriberAcquired = false;
            }
            root.sportsReady = false;
            return;
        }

        if (root.activeViewReady && !root.sportsSubscriberAcquired)
            sportsActivationTimer.restart();
    }

    onActiveViewReadyChanged: {
        if (!root.activeViewReady)
            return;
        // Google colours are cached on disk, so this only reaches the network
        // once the cache is older than the configured window. It is independent
        // from the optional ESPN projection below.
        GoogleCalendarService.refreshColors();
        root.syncSportsSubscription();
    }

    onSportsRequestedChanged: {
        root.syncSportsSubscription();
    }

    Timer {
        id: sportsActivationTimer
        interval: 0
        repeat: false
        onTriggered: {
            if (!root.sportsRequested || !root.activeViewReady || root.sportsSubscriberAcquired)
                return;
            SportsService.acquireTimetableSubscriber();
            root.sportsSubscriberAcquired = true;
            root.sportsReady = true;
        }
    }

    Component.onDestruction: {
        sportsActivationTimer.stop();
        if (root.sportsSubscriberAcquired)
            SportsService.releaseTimetableSubscriber();
    }

    Rectangle {
        anchors.fill: parent
        color: Appearance.colors.colSurfaceContainer
        radius: Appearance.rounding.large
    }

    // Fade out, swap, fade in. Keeping both trees alive for a cross-fade would
    // mean paying for a month grid while the week grid is on screen, and the
    // cheatsheet already releases its whole tab tree on close for that reason.
    //
    // The fade in waits for the incoming Loader rather than following the fade
    // out on a fixed schedule: both views incubate asynchronously, so a timed
    // fade animates an empty host and the tree then appears at full opacity.
    property bool awaitingViewReveal: false
    readonly property Loader activeViewLoader: root.activeMode === "month" ? monthViewLoader : weekViewLoader

    onRequestedModeChanged: {
        if (root.requestedMode === root.activeMode)
            return;
        // Nothing has been shown yet, so there is no outgoing view to fade.
        if (!root.viewInitialised) {
            root.activeMode = root.requestedMode;
            return;
        }
        revealWatchdog.stop();
        fadeInAnim.stop();
        fadeOutAnim.restart();
    }

    function handleViewLoaded() {
        root.viewInitialised = true;
        root.revealActiveView();
    }

    function commitModeSwap() {
        root.activeMode = root.requestedMode;
        // A small tree can incubate synchronously, in which case onLoaded has
        // already fired and found nothing pending — hence the status check
        // before arming the wait.
        if (root.activeViewLoader.status === Loader.Ready) {
            root.awaitingViewReveal = false;
            fadeInAnim.start();
            return;
        }
        root.awaitingViewReveal = true;
        revealWatchdog.restart();
    }

    function revealActiveView() {
        if (!root.awaitingViewReveal)
            return;
        root.awaitingViewReveal = false;
        revealWatchdog.stop();
        fadeInAnim.start();
    }

    NumberAnimation {
        id: fadeOutAnim
        target: viewHost
        property: "switchProgress"
        to: 0
        duration: Appearance.animation.elementMoveExit.duration
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Appearance.animationCurves.emphasizedAccel
        onFinished: root.commitModeSwap()
    }

    NumberAnimation {
        id: fadeInAnim
        target: viewHost
        property: "switchProgress"
        to: 1
        duration: Appearance.animation.elementMoveEnter.duration
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
    }

    // A Loader that fails to instantiate would otherwise leave the host
    // invisible for good; an unexplained pop is recoverable, a blank tab is not.
    Timer {
        id: revealWatchdog
        interval: 900
        repeat: false
        onTriggered: root.revealActiveView()
    }

    Item {
        id: viewHost
        anchors.fill: parent
        anchors.margins: root.activeMode === "month" ? 16 : 0

        property real switchProgress: 1

        opacity: viewHost.switchProgress
        transform: Translate {
            // Month sits "further in" than week, so the swap reads as depth
            // rather than a sideways page flip.
            y: (1 - viewHost.switchProgress) * (root.activeMode === "month" ? 18 : -18)
        }

        Loader {
            id: weekViewLoader
            anchors.fill: parent
            active: root.activeMode !== "month"
            asynchronous: true
            onLoaded: root.handleViewLoaded()
            sourceComponent: WeekView {
                maxHeight: root.maxHeight
                maxContentWidth: root.maxContentWidth
                sportsEnabled: root.sportsReady
                viewMode: root.activeMode
            }
        }

        Loader {
            id: monthViewLoader
            anchors.fill: parent
            active: root.activeMode === "month"
            asynchronous: true
            onLoaded: root.handleViewLoaded()
            sourceComponent: MonthView {
                showUpcoming: Persistent.states.cheatsheet.timetableShowUpcoming
                sportsEnabled: root.sportsReady
            }
        }
    }
}
