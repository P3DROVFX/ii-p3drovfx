import QtQuick
import Quickshell.Wayland
import ".."

/**
 * No input for `sec` seconds, as reported by the compositor's idle
 * notifier. Keep Awake (an idle inhibitor) counts as activity unless
 * `ignoreInhibitors` is set, so a movie with the inhibitor on is not "away".
 */
ModeCondition {
    id: root
    readonly property int sec: Math.max(5, Number(root.params?.sec) || 300)
    readonly property bool ignoreInhibitors: root.params?.ignoreInhibitors === true

    readonly property IdleMonitor monitor: IdleMonitor {
        enabled: true
        timeout: root.sec
        respectInhibitors: !root.ignoreInhibitors
    }

    satisfied: root.monitor.isIdle
    reason: root.satisfied ? "idle" : "active"
}
