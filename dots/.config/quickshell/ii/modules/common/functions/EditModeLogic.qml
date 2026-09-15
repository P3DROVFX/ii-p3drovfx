pragma Singleton
import Quickshell
import "edit_mode.js" as EditMode

/**
 * Wrapper for edit_mode.js (Edit Mode's Escape ladder, history-stack
 * arithmetic and viewport geometry) so it can be reached through
 * `qs.modules.common.functions`.
 */
Singleton {
    readonly property string desktopTab: EditMode.DESKTOP_TAB
    readonly property string lockscreenTab: EditMode.LOCKSCREEN_TAB
    readonly property int undoLimit: EditMode.UNDO_LIMIT

    function tabIndex(...args) {
        return EditMode.tabIndex(...args)
    }

    function tabAt(...args) {
        return EditMode.tabAt(...args)
    }

    function resolveEscape(...args) {
        return EditMode.resolveEscape(...args)
    }

    function undoPush(...args) {
        return EditMode.undoPush(...args)
    }

    function undoPop(...args) {
        return EditMode.undoPop(...args)
    }

    function listCopy(...args) {
        return EditMode.listCopy(...args)
    }

    // Viewport geometry
    function usableArea(...args) {
        return EditMode.usableArea(...args)
    }

    function viewportGeometry(...args) {
        return EditMode.viewportGeometry(...args)
    }

    function drawerTravel(...args) {
        return EditMode.drawerTravel(...args)
    }

    function chromeBandFraction(...args) {
        return EditMode.chromeBandFraction(...args)
    }

    function atProgress(...args) {
        return EditMode.atProgress(...args)
    }

    function cardRect(...args) {
        return EditMode.cardRect(...args)
    }

    function areaRect(...args) {
        return EditMode.areaRect(...args)
    }

    function drawerRect(...args) {
        return EditMode.drawerRect(...args)
    }

    function pointInDrawerReveal(...args) {
        return EditMode.pointInDrawerReveal(...args)
    }

    function canvasPointFromScreen(...args) {
        return EditMode.canvasPointFromScreen(...args)
    }

    function dropPosition(...args) {
        return EditMode.dropPosition(...args)
    }
    function barDropTarget(...args) {
        return EditMode.barDropTarget(...args)
    }
    function moveTargetForInsertion(...args) {
        return EditMode.moveTargetForInsertion(...args)
    }

    readonly property var sizeSteps: EditMode.SIZE_STEPS

    function steppedScale(...args) {
        return EditMode.steppedScale(...args)
    }

    function nearestSizeStep(...args) {
        return EditMode.nearestSizeStep(...args)
    }
}
