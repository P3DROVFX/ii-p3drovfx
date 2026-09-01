pragma Singleton

import Quickshell
import qs

/**
 * Which panel family is running, and what that family pins.
 *
 * `Config.options.panelFamily` is a persisted string. Reading it directly spreads
 * `=== "tablet"` comparisons through the bar, the settings pages and the gesture
 * service, and every one of those is a place a new family has to be remembered.
 * Ask this singleton instead.
 *
 * The distinction that matters to shared code is almost never "is this the tablet"
 * but "is this family touch-first" or "does this family pin the bar" — those are
 * the questions with a stable meaning when a fourth family appears. Prefer the
 * capability properties over `isTablet`.
 */
Singleton {
    id: root

    readonly property string current: Config.options?.panelFamily ?? "ii"

    readonly property bool isIi: root.current === "ii"
    readonly property bool isTablet: root.current === "tablet"
    readonly property bool isWaffle: root.current === "waffle"

    // ── Capabilities ────────────────────────────────────────────────────────
    // Every finger-driven surface: no hover intent, larger hit targets, gestures
    // instead of corner triggers.
    readonly property bool touchFirst: root.isTablet

    // The bar is a status bar at the top of the screen and the user cannot move it.
    readonly property bool pinsBarToTop: root.isTablet

    // Some families present shell tools as regular xdg toplevels instead of layer-shell
    // overlays. Shared routing uses this capability so a tool can keep its desktop
    // implementation without leaking desktop overlay state into a touch-first family.
    readonly property bool nativeAppWindows: root.isTablet

    // The family curates its own panel set, so the desktop shell's optional
    // surfaces (dock, dynamic island, screen corners, wrapped frame) are not
    // offered at all. Settings uses this to hide the sections outright rather
    // than showing switches that do nothing.
    readonly property bool restrictedCustomization: root.isTablet
}
