pragma Singleton
import Quickshell
import "wallpaper_framing.js" as Framing

/**
 * Wrapper for wallpaper_framing.js (a screen's wallpaper zoom, position and
 * orientation, as arithmetic) so it can be reached through
 * `qs.modules.common.functions`.
 */
Singleton {
    readonly property real zoomMin: Framing.ZOOM_MIN
    readonly property real zoomMax: Framing.ZOOM_MAX

    function defaults(...args) {
        return Framing.defaults(...args)
    }

    function normalize(...args) {
        return Framing.normalize(...args)
    }

    function isIdentity(...args) {
        return Framing.isIdentity(...args)
    }

    function equal(...args) {
        return Framing.equal(...args)
    }

    function isSideways(...args) {
        return Framing.isSideways(...args)
    }

    function snapRotation(...args) {
        return Framing.snapRotation(...args)
    }

    function layout(...args) {
        return Framing.layout(...args)
    }

    function panTo(...args) {
        return Framing.panTo(...args)
    }

    function pointOffset(...args) {
        return Framing.pointOffset(...args)
    }

    function zoomAt(...args) {
        return Framing.zoomAt(...args)
    }

    function rotateBy(...args) {
        return Framing.rotateBy(...args)
    }

    function flip(...args) {
        return Framing.flip(...args)
    }

    function animationTarget(...args) {
        return Framing.animationTarget(...args)
    }
}
