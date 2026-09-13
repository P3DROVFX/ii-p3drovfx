pragma Singleton
import Quickshell
import "widget_nudge.js" as Nudge

/**
 * Wrapper for widget_nudge.js (arrow-key nudging arithmetic) so it can be
 * reached through `qs.modules.common.functions`.
 */
Singleton {
    function direction(...args) {
        return Nudge.direction(...args)
    }

    function step(...args) {
        return Nudge.step(...args)
    }

    function groupDelta(...args) {
        return Nudge.groupDelta(...args)
    }
}
