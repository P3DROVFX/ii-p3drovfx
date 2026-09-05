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

    /**
     * Every family that can be switched to, in the order a chooser should show them.
     *
     * The list lived in shell.qml, as an array the cycle shortcut walked, and nowhere else —
     * so nothing could offer the user a choice, and the only way between families was to
     * cycle through the ones in between, rebuilding each on the way. This singleton already
     * answers "which family runs"; "which families exist" belongs beside it.
     *
     * Keep in step with `Config.enumConstraints["panelFamily"]`, which is what rejects a
     * hand-edited value.
     *
     * The strings are plain English, translated by whatever draws them — the same shape
     * TouchGestureActionRegistry uses. Translation lives in qs.services, and qs.services
     * imports qs.modules.common, so a policy singleton in common cannot reach for it
     * without closing that loop.
     */
    readonly property var available: [
        {
            id: "ii",
            name: "illogical-impulse",
            summary: "Desktop",
            description: "The full desktop shell: sidebars, dock, overview and every optional surface.",
            icon: "desktop_windows"
        },
        {
            id: "tablet",
            name: "Tablet",
            summary: "Touchscreen",
            description: "Touch-first: a status bar, a home screen, an app drawer and edge gestures.",
            icon: "tablet_android"
        },
        {
            id: "waffle",
            name: "Waffle",
            summary: "Windows-like",
            description: "A taskbar, a start menu and an action centre, in the shape of a familiar desktop.",
            icon: "window"
        }
    ]

    // ── Per-family preferences ──────────────────────────────────────────────
    /**
     * The quick-toggle layout this family draws and edits.
     *
     * The families have different screens to fit the grid on — a four-column block tuned
     * for a 460px sidebar is not the arrangement anyone wants on a tablet's full-width
     * shade — so each keeps its own, and adapting one no longer rearranges the other.
     *
     * Every *write* goes to the object this returns, which is what keeps them apart.
     */
    function quickToggleLayout() {
        const toggles = Config.options?.sidebar?.quickToggles ?? null;
        if (!toggles)
            return null;
        return root.isTablet ? toggles.androidTablet : toggles.android;
    }

    /**
     * The pages to *draw*, which is not quite the same question.
     *
     * A family that has never been edited has no layout of its own, and a blank grid is a
     * worse answer than the one the user already arranged. So an untouched family borrows
     * the desktop's until its first edit, which writes a normalized set of its own and
     * ends the borrowing.
     */
    function quickTogglePages() {
        const toggles = Config.options?.sidebar?.quickToggles ?? null;
        if (!toggles)
            return [];
        const own = root.quickToggleLayout();
        if (own && own.pages && own.pages.length > 0)
            return own.pages;
        return toggles.android.pages ?? [];
    }

    function entry(familyId) {
        return root.available.find(family => family.id === familyId) ?? null;
    }

    /// Switching families rebuilds every surface, so doing it when nothing would change is
    /// pure cost. Nothing else here writes config — this is the one setter, and it must stay
    /// the only key it touches: a family may not rewrite a stored preference.
    function select(familyId) {
        if (!root.entry(familyId) || familyId === root.current)
            return;
        Config.options.panelFamily = familyId;
    }

    function cycle() {
        const index = root.available.findIndex(family => family.id === root.current);
        root.select(root.available[(index + 1) % root.available.length].id);
    }

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
