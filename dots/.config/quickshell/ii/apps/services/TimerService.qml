pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

/**
 * Slim TimerService IPC bridge for standalone apps.
 */
Singleton {
    id: root

    function addCountdown(label, durationSeconds) {
        const secs = Math.max(1, Math.round(Number(durationSeconds) || 0));
        Quickshell.execDetached([
            "qs", "-c", "ii", "ipc", "call", "clock", "open", "timer"
        ]);
        return secs > 0;
    }
}
