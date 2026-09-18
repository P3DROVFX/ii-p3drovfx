pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs

/**
 * Shared policy for the Default/Connect shell modes.
 *
 * Keep capability checks here so Settings, Welcome and future setup flows do
 * not drift into slightly different interpretations of the same constraints.
 * This object only reads Config and performs explicit writes through setMode().
 */
QtObject {
    id: root

    readonly property string effectiveMode: Config.ready
        ? (Config.options.sidebar.sidebarStyle || "default")
        : "default"

    readonly property bool barCenterActive: Config.ready
        && Config.options.bar.floatingNotch.centerInBar
    readonly property bool floatingNotchActive: Config.ready
        && Config.options.bar.floatingNotch.enable
    readonly property bool transparentBarBackground: Config.ready
        && Config.options.bar.barBackgroundStyle === 0
    readonly property bool edgeRoundingActive: Config.ready
        && Config.options.appearance.fakeScreenRounding === 4

    readonly property bool dynamicIslandHorizontal: Config.ready
        && Config.options.bar.cornerStyle === 3
        && !Config.options.bar.vertical

    // The island in the bar centre only works where the bar leaves it a centre to sit
    // in. Hug spans the screen and its widget groups live at the edges, and the Dynamic
    // Island bar style flanks it by reserving the island's own width. Float and Rect do
    // neither: they own the full width with no notion of a reserved centre, so the
    // island either collided with the widgets or hid them for nothing. The combination
    // is therefore refused rather than half-supported.
    readonly property var centerInBarStyles: [0, 3]
    readonly property bool centerInBarStyleSupported: Config.ready
        && root.centerInBarStyles.indexOf(Config.options.bar.cornerStyle) !== -1
    readonly property bool centerInBarActive: Config.ready
        && Config.options.bar.floatingNotch.centerInBar
    readonly property string centerInBarBlockedReasonKey: root.centerInBarStyleSupported
        ? ""
        : "Dynamic Island in bar center needs the Hug or Dynamic Island bar style."
    readonly property string barStyleBlockedByCenterInBarReasonKey: root.centerInBarActive
        ? "Float and Rect are unavailable while Dynamic Island in bar center is on."
        : ""

    // Float and the Wrapped Frame are mutually exclusive. The frame closes a
    // ring against the screen edges and expects the bar to be welded to it; a
    // floating bar never reaches that edge and keeps its own drop shadow, so
    // the two silhouettes end up drawn over each other. Refused from both
    // sides, and the pair is never repaired behind the user's back.
    readonly property bool floatStyleActive: Config.ready
        && Config.options.bar.cornerStyle === 1
    readonly property bool wrappedFrameActive: Config.ready
        && Config.options.appearance.fakeScreenRounding === 3

    // Top and bottom Dynamic Island bars share the top-layer space Connect
    // owns. Keep the existing bar choice intact and refuse Connect instead of
    // silently replacing the user's Dynamic Island style.
    readonly property bool canSelectConnect: Config.ready
        && !root.dynamicIslandHorizontal
    // The island now draws search in either shell mode, so a floating island no longer
    // pins the session to Connect: that restriction existed only because search lived in
    // the Connect top layer.
    readonly property bool canSelectDefault: Config.ready

    readonly property bool shouldForceDefault: Config.ready
        && root.effectiveMode === "connect"
        && !root.canSelectConnect

    readonly property bool barPositionLocked: root.barCenterActive
    readonly property bool osdStyleEditable: root.effectiveMode !== "connect"
    readonly property bool connectModeActive: root.effectiveMode === "connect"

    // A very low Ignore Alpha makes the compositor discard most of the
    // drop-shadow pixels, so the shadow would flicker or vanish while still
    // costing GPU. Block it instead of rendering garbage.
    readonly property bool lowIgnoreAlphaBlocksDropShadow: Config.ready
        && (Config.options.appearance.ignoreAlpha ?? 1) < 0.3

    // A transparent Connect bar cannot use its drop shadow without changing
    // the apparent color of the shared colLayer0 surface.
    readonly property bool barDropShadowBlocked:
        (root.connectModeActive && Config.options.appearance.transparency.enable)
        || root.lowIgnoreAlphaBlocksDropShadow

    readonly property string defaultBlockedReasonKey: ""
    readonly property string connectBlockedReasonKey: root.dynamicIslandHorizontal
        ? "Connect mode is unavailable while Dynamic Island is at the top or bottom."
        : ""
    readonly property string barPositionBlockedReasonKey:
        "The bar stays at the top while Dynamic Island is centered in it."
    readonly property string floatStyleBlockedReasonKey: root.wrappedFrameActive
        ? "Float cannot be combined with the Wrapped Frame. Turn the frame off to float the bar."
        : ""
    readonly property string wrappedFrameBlockedReasonKey: root.floatStyleActive
        ? "The Wrapped Frame cannot be combined with the Float corner style. Change the corner style to use it."
        : ""

    function setMode(mode: string): bool {
        if (!Config.ready || (mode !== "default" && mode !== "connect"))
            return false;
        if (mode === "default" && !root.canSelectDefault)
            return false;
        if (mode === "connect" && !root.canSelectConnect)
            return false;
        if (mode === "connect") {
            Config.options.bar.barBackgroundStyle = 1;
        }
        Config.options.sidebar.sidebarStyle = mode;
        return true;
    }

    function setBarPosition(value: int): bool {
        if (!Config.ready || root.barPositionLocked)
            return false;
        const isVertical = (value & 2) !== 0;
        // If moving Dynamic Island to top or bottom while in Connect mode,
        // automatically switch Shell mode to Default.
        if (!isVertical && Config.options.bar.cornerStyle === 3 && root.effectiveMode === "connect") {
            Config.options.sidebar.sidebarStyle = "default";
        }
        const bottom = (value & 1) !== 0;
        // GlobalStates runs the slide and writes the placement itself once the
        // shell is off screen. It returns false when there is nothing to move,
        // in which case the write still has to happen here.
        if (!GlobalStates.requestBarPlacement(bottom, isVertical)) {
            Config.options.bar.bottom = bottom;
            Config.options.bar.vertical = isVertical;
        }
        return true;
    }
}
