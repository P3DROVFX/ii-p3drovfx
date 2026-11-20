pragma Singleton
import QtQuick
import Quickshell

/**
 * GlobalStates for standalone apps: every member the shared widgets read, inert.
 *
 * The shell's GlobalStates binds to Notifications and HyprlandData, which pull
 * KdeConnect, IiLink, the notification server and more. StyledToolTip (inside every
 * RippleButton) reads it, so without this stand-in any button boots those services.
 */
Singleton {
    id: root

    // Panels: none of them exist in an app.
    property bool cheatsheetOpen: false
    property bool clockAppOpen: false
    property bool healthAppOpen: false
    property bool islandDashboardOpen: false
    property bool modesOpen: false
    property bool notesAppOpen: false
    property bool osdVolumeOpen: false
    property bool overlayOpen: false
    property bool overviewOpen: false
    property bool policiesPanelOpen: false
    property bool dashboardPanelOpen: false
    property alias sidebarLeftOpen: root.policiesPanelOpen
    property alias sidebarRightOpen: root.dashboardPanelOpen
    property bool sessionOpen: false
    property bool settingsOpen: false
    property bool usageOpen: false
    property bool wallpaperSelectorOpen: false
    property bool desktopMenuOpen: false
    property bool screenLocked: false
    property bool presetHoldMotion: false

    // Edit Mode (desktop widgets) is a shell feature.
    property bool editMode: false
    property bool editBarDragActive: false
    property bool editBarMenuOpen: false
    property bool editDrawerOpen: false
    property string editDrawerSection: "widgets"
    property bool editSearchFocused: false
    property var editWidgetMenuCanvas: null
    property bool editWidgetMenuOpen: false
    signal editBarDragCancel()
    signal editSearchFocusRequested()
    signal editSearchReleaseRequested()
    function closeDesktopMenu() {}
    function closeEditBarMenu() {}
    function closeEditWidgetMenu() {}
    function editHistoryBeginBatch() {}
    function editHistoryEndBatch() {}
    function editUndo() {}
    function editRedo() {}
}
