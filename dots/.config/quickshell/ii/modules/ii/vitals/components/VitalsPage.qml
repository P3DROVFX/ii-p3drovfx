import QtQuick
import qs.modules.ii.clock.components

/**
 * The contract between VitalsAppContent and a destination page. Every page is a
 * VitalsPage: the app sets the inputs, reads the outputs, and calls the functions; a page
 * overrides only what it uses. See UI-NOTES.md (phase 3) for the rules.
 */
Item {
    id: root

    // ── In: set by the app ──────────────────────────────────────────────
    /// The width the page settles at once a sheet or the rail stops moving. Decide
    /// columns, tile sizes and font sizes on this, stretch on `width`.
    property real layoutWidth: root.width
    /// Window below ClockStyle.compactMax: the rail is a bottom bar, sheets take the width.
    property bool compact: false
    /// The app's side-sheet host: `panels.show(component, props)`, `panels.close()`.
    property ClockSidePanel panels: null
    /// Wall clock in ms, refreshed every 30 s while the window is shown (nothing ticks
    /// while it is hidden). Bind relative times ("4 min ago") to this.
    property real now: Date.now()

    // ── Out: read by the app ────────────────────────────────────────────
    /// The line under the title in the app bar; it fades with the page.
    property string pageSubtitle: ""
    /// The page's main action as the FAB: {symbol, label} or null for none (it slides away).
    property var fab: null

    /// Asks the app to switch to another destination ("sleep", "heart", …).
    signal pageRequested(string page)

    /// The FAB was clicked.
    function fabTriggered(): void {
    }

    /// Esc while no sheet is open; true when the page used it.
    function handleEscape(): bool {
        return false;
    }

    /// Any other key the app does not use itself; true when the page used it.
    function handleKey(key: int, modifiers: int): bool {
        return false;
    }
}
