pragma Singleton
import Quickshell
import "widget_align.js" as Align

/**
 * Wrapper for widget_align.js (aligning and distributing a widget selection)
 * so it can be reached through `qs.modules.common.functions`.
 */
Singleton {
    readonly property var modes: Align.MODES

    function minimumMembers(...args) {
        return Align.minimumMembers(...args)
    }

    function bounds(...args) {
        return Align.bounds(...args)
    }

    function deltas(...args) {
        return Align.deltas(...args)
    }
}
