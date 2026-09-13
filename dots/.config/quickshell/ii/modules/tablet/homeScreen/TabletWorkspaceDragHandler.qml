import QtQuick
import Quickshell
import Quickshell.Hyprland

import qs
import qs.services
import qs.modules.common

/**
 * Swiping left and right across the desktop moves between workspaces, the way swiping
 * across an Android home screen moves between pages.
 *
 * The hard part is not the swipe, it is knowing when NOT to act on one. A drag across the
 * body of the screen is almost always meant for whatever is under the finger — scrolling a
 * page, moving a slider, drawing. So this claims the gesture only when it starts somewhere
 * no window covers, which is the tablet equivalent of "on the home screen". Everywhere
 * else it goes inert for the rest of the drag and the application keeps the interaction.
 */
QtObject {
    id: handler

    /// Fraction of the screen width a swipe must cover to change workspace, unless it is
    /// fast enough to count as a fling.
    readonly property real commitFraction: 0.16
    readonly property real flingVelocity: 420
    /// A drag has to be clearly more horizontal than vertical before it means "next page".
    readonly property real horizontalBias: 1.6

    property bool _active: false
    property string _screenName: ""
    property real _dx: 0
    property real _dy: 0

    function claims(origin) {
        return origin === "surface";
    }

    function actionId(origin) {
        return handler.claims(origin) ? "none" : "";
    }

    /// True when nothing on the current workspace covers this point, i.e. the finger is on
    /// the wallpaper. Floating and tiled windows both report position and size, so one
    /// rectangle test over the workspace's windows answers it.
    function pointIsOnDesktop(screenName, px, py) {
        const monitor = Hyprland.monitors.values.find(m => m.name === screenName)
            ?? Hyprland.focusedMonitor;
        if (!monitor)
            return false;

        const workspaceId = monitor.activeWorkspace?.id ?? -1;
        const globalX = monitor.x + px;
        const globalY = monitor.y + py;

        for (const win of (HyprlandData.windowList ?? [])) {
            if ((win?.workspace?.id ?? -2) !== workspaceId)
                continue;
            if (win.hidden === true)
                continue;
            const at = win.at ?? [0, 0];
            const size = win.size ?? [0, 0];
            if (globalX >= at[0] && globalX <= at[0] + size[0]
                && globalY >= at[1] && globalY <= at[1] + size[1])
                return false;
        }
        return true;
    }

    property bool _armed: false

    function begin(origin, screenName) {
        handler._screenName = screenName ?? "";
        handler._reset();
    }

    function update(origin, screenName, travel, velocity, dx, dy) {
        handler._dx = dx ?? 0;
        handler._dy = dy ?? 0;

        // Decide once per drag, on the first move rather than in begin(): the desktop test
        // is a rectangle scan over every window on the workspace, and running it again on
        // every move event would do that at touch-report rate for no benefit — where the
        // finger went down does not change while it is down.
        if (!handler._armed) {
            handler._armed = true;
            handler._active = handler.pointIsOnDesktop(handler._screenName,
                                                       TouchGestureService.startX,
                                                       TouchGestureService.startY);
        }
    }

    function release(origin, velocity) {
        if (!handler._active) {
            handler._reset();
            return;
        }

        const screen = Quickshell.screens.find(s => s.name === handler._screenName)
            ?? Quickshell.primaryScreen;
        const needed = Math.max(1, (screen ? screen.width : 1000) * handler.commitFraction);
        const horizontal = Math.abs(handler._dx) > Math.abs(handler._dy) * handler.horizontalBias;

        if (horizontal && (Math.abs(handler._dx) >= needed || Math.abs(velocity) >= handler.flingVelocity)) {
            // Dragging the page leftwards reveals the one to its right, as on a home screen.
            //
            // The Lua dispatcher API, not the classic "workspace r+1" string: this Hyprland
            // is configured with the former, and the latter fails as a Lua syntax error
            // rather than doing nothing visible, so it is easy to ship broken.
            Hyprland.dispatch(handler._dx < 0
                ? "hl.dsp.focus({ workspace = 'r+1' })"
                : "hl.dsp.focus({ workspace = 'r-1' })");
        }
        handler._reset();
    }

    function cancel(origin) {
        handler._reset();
    }

    function _reset() {
        handler._active = false;
        handler._armed = false;
        handler._dx = 0;
        handler._dy = 0;
    }

    Component.onCompleted: TouchGestureDragRegistry.register(handler)
    Component.onDestruction: TouchGestureDragRegistry.unregister(handler)
}
