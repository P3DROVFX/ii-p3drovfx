import QtQuick
import Quickshell

import qs
import qs.modules.common
import qs.modules.tablet.appDrawer

/**
 * The bottom edge, in the shape Android gives it.
 *
 *   swipe up            → Home
 *   swipe up from Home  → the app drawer, following the finger
 *   swipe up and hold   → Recents
 *
 * This edge used to open the drawer unconditionally. That was defensible — the home screen
 * is a bare workspace, so "go home" had little to show for itself — but it spent the most
 * used gesture on Android on the second most useful destination, and it made "up and hold"
 * impossible: both gestures start on the same edge, and with the drawer already committed
 * to following the finger there was nothing left to distinguish them with.
 *
 * Two things had to land before this could: Home became a workspace you can name rather than
 * "whichever one is free" (otherwise the gesture leads somewhere different every time), and
 * the drag registry learned to let one handler own an edge for a whole drag.
 *
 * The hold is detected by the finger going *still*, not by elapsed time. A slow drag is
 * still a drag; a stopped one is a hold. Since the service only calls update() when the
 * contact actually moves, a timer restarted on each move fires exactly when movement stops.
 */
QtObject {
    id: handler

    /// "android" (above) or "drawer" (the old behaviour: this edge only opens the drawer).
    readonly property string mode: Config.options?.tablet?.gestures?.bottomEdge ?? "android"
    readonly property bool androidMode: handler.mode === "android"

    /// How far the finger travels before a release counts, and how fast counts regardless.
    readonly property real commitFraction: 0.10
    readonly property real flingVelocity: 380
    /// A hold below this is a tap that wobbled, not a deliberate stop.
    readonly property real holdMinimumTravel: 90
    /// Movement smaller than this does not restart the hold clock; a finger resting on glass
    /// still reports a pixel or two.
    readonly property real holdSlop: 6
    readonly property int holdMs: 280

    property string _screenName: ""
    property bool _startedOnHome: false
    property real _travel: 0
    property real _lastHoldTravel: 0
    property bool _recentsArmed: false
    /// Where the drag started, so a drag begun with the drawer already open gets the
    /// controller's cheaper close threshold.
    property real _startProgress: 0

    readonly property Timer _holdTimer: Timer {
        interval: handler.holdMs
        repeat: false
        onTriggered: handler._armRecents()
    }

    function claims(origin) {
        return origin === "bottomEdge";
    }

    /// Names the drag for the feedback overlay. The service reads this once, at the start,
    /// so it can only describe where the gesture is heading if nothing changes — which is
    /// the honest answer before the finger has done anything.
    function actionId(origin) {
        if (!handler.claims(origin))
            return "";
        if (!handler.androidMode)
            return "overview";
        return TabletNavigation.onHomeScreen() ? "overview" : "home";
    }

    function _armRecents() {
        if (handler._recentsArmed)
            return;
        handler._recentsArmed = true;
        // The drawer was following the finger; it is not where this gesture is going any more.
        if (handler._drawerFollows())
            TabletAppDrawerGestureController.cancelTracking();
    }

    /// Whether the drawer should be riding this drag. Only from the home screen in Android
    /// mode, because everywhere else the drag means Home and the drawer is not involved.
    function _drawerFollows() {
        return !handler.androidMode || handler._startedOnHome;
    }

    function begin(origin, screenName) {
        handler._screenName = screenName ?? "";
        handler._startedOnHome = TabletNavigation.onHomeScreen();
        handler._travel = 0;
        handler._lastHoldTravel = 0;
        handler._recentsArmed = false;
        handler._holdTimer.stop();

        if (handler._drawerFollows()) {
            handler._startProgress = TabletAppDrawerGestureController.progress;
            TabletAppDrawerGestureController.startTracking(handler._screenName);
        } else {
            handler._startProgress = 0;
        }
    }

    function update(origin, screenName, travel, velocity) {
        handler._screenName = screenName ?? handler._screenName;
        handler._travel = travel;

        if (handler._drawerFollows() && !handler._recentsArmed) {
            const screen = Quickshell.screens.find(s => s.name === handler._screenName)
                ?? Quickshell.primaryScreen;
            const distance = TabletAppDrawerGestureController.dragDistance(screen ? screen.height : 1000);
            TabletAppDrawerGestureController.updateProgress(
                handler._startProgress + travel / distance, velocity);
        }

        if (!handler.androidMode)
            return;

        // Restart the clock only on real movement, so it runs out while the finger is still.
        if (travel < handler.holdMinimumTravel) {
            handler._holdTimer.stop();
            handler._lastHoldTravel = travel;
            return;
        }
        if (Math.abs(travel - handler._lastHoldTravel) > handler.holdSlop) {
            handler._lastHoldTravel = travel;
            handler._holdTimer.restart();
        }
    }

    function release(origin, velocity) {
        handler._holdTimer.stop();

        if (handler._recentsArmed) {
            TabletNavigation.recents(handler._screenName);
            handler._reset();
            return;
        }

        if (handler._drawerFollows()) {
            TabletAppDrawerGestureController.endTracking(velocity, handler._startProgress);
            handler._reset();
            return;
        }

        const screen = Quickshell.screens.find(s => s.name === handler._screenName)
            ?? Quickshell.primaryScreen;
        const needed = Math.max(1, (screen ? screen.height : 1000) * handler.commitFraction);
        if (handler._travel >= needed || velocity >= handler.flingVelocity)
            TabletNavigation.home(handler._screenName);
        handler._reset();
    }

    function cancel(origin) {
        handler._holdTimer.stop();
        if (handler._drawerFollows())
            TabletAppDrawerGestureController.cancelTracking();
        handler._reset();
    }

    function _reset() {
        handler._travel = 0;
        handler._lastHoldTravel = 0;
        handler._recentsArmed = false;
    }

    Component.onCompleted: TouchGestureDragRegistry.register(handler)
    Component.onDestruction: TouchGestureDragRegistry.unregister(handler)
}
