import QtQuick
import QtTest
import "../../modules/tablet/dock/TabletDockVisibility.js" as DockVisibility

TestCase {
    name: "TabletDockVisibility"

    // A tablet doing the ordinary thing: config loaded, screen awake, nothing pinned,
    // no shade open, and a window on the workspace.
    function busy(overrides) {
        const state = {
            showAppRow: true,
            autoHideOnOccupiedWorkspace: false,
            keepNavigationVisible: true,
            showNavigation: true,
            showSearchBar: true,
            showWorkspaceArrows: true,
            pinned: false,
            anySidebarOpen: false,
            workspaceEmpty: false,
            configReady: true,
            screenLocked: false
        };
        for (const key in (overrides || {}))
            state[key] = overrides[key];
        return state;
    }

    // ── The reported bug ──────────────────────────────────────────────────

    function test_the_launcher_row_survives_opening_an_app() {
        // The whole point of the default change: the taskbar is persistent, so a
        // window on the workspace takes nothing off the dock.
        verify(DockVisibility.appsRevealed(busy()));
        verify(DockVisibility.searchRevealed(busy()));
        verify(DockVisibility.navigationRevealed(busy()));
        verify(DockVisibility.workspaceArrowsRevealed(busy()));
        verify(DockVisibility.surfaceVisible(busy()));
    }

    function test_auto_hide_still_works_when_asked_for() {
        const hiding = busy({ autoHideOnOccupiedWorkspace: true });
        verify(!DockVisibility.appsRevealed(hiding));
        verify(!DockVisibility.searchRevealed(hiding));
        // Navigation is the way off a device with no keyboard; it outlives the row.
        verify(DockVisibility.navigationRevealed(hiding));
        verify(DockVisibility.dockRevealed(hiding));

        const empty = busy({ autoHideOnOccupiedWorkspace: true, workspaceEmpty: true });
        verify(DockVisibility.appsRevealed(empty));
    }

    function test_pinning_beats_auto_hide_but_not_switching_the_row_off() {
        verify(DockVisibility.appsRevealed(busy({ autoHideOnOccupiedWorkspace: true, pinned: true })));
        verify(!DockVisibility.appsRevealed(busy({ pinned: true, showAppRow: false })));
    }

    // ── The rest of the table ─────────────────────────────────────────────

    function test_an_open_shade_covers_the_row_but_pinning_holds_it() {
        verify(!DockVisibility.appsRevealed(busy({ anySidebarOpen: true })));
        verify(DockVisibility.appsRevealed(busy({ anySidebarOpen: true, pinned: true })));
    }

    function test_navigation_can_be_tied_to_the_row() {
        const tied = busy({ autoHideOnOccupiedWorkspace: true, keepNavigationVisible: false });
        verify(!DockVisibility.navigationRevealed(tied));
        // Nothing left to draw, so there is no surface and no arrows either.
        verify(!DockVisibility.dockRevealed(tied));
        verify(!DockVisibility.workspaceArrowsRevealed(tied));
        verify(!DockVisibility.surfaceVisible(tied));
    }

    function test_search_never_outlives_the_row() {
        verify(!DockVisibility.searchRevealed(busy({ showAppRow: false })));
        verify(!DockVisibility.searchRevealed(busy({ showSearchBar: false })));
    }

    function test_the_surface_waits_for_config_and_yields_to_the_lock_screen() {
        verify(!DockVisibility.surfaceVisible(busy({ configReady: false })));
        verify(!DockVisibility.surfaceVisible(busy({ screenLocked: true })));
        // Still "revealed" underneath — the lock is covering it, not switching it off.
        verify(DockVisibility.dockRevealed(busy({ screenLocked: true })));
    }

    function test_missing_preferences_fall_back_to_a_persistent_taskbar() {
        // What the dock sees before Config.options.tablet exists.
        verify(DockVisibility.appsRevealed({ configReady: true, workspaceEmpty: false }));
        verify(DockVisibility.navigationRevealed({}));
    }
}
