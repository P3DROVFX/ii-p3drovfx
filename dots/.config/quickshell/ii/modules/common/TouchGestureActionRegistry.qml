pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common

Singleton {
    id: root

    readonly property var actions: [
        // Navigation & Core Shell
        { id: "none", name: "None", icon: "block" },
        { id: "overview", name: "Overview / Search", icon: "grid_view", families: ["ii", "waffle"] },
        { id: "overviewClipboard", name: "Clipboard History", icon: "content_paste", families: ["ii", "waffle"] },
        { id: "overviewEmoji", name: "Emoji Picker", icon: "mood", families: ["ii", "waffle"] },
        { id: "sidebarLeft", name: "Left Sidebar", icon: "left_panel_open", families: ["ii", "waffle"] },
        { id: "sidebarRight", name: "Right Sidebar", icon: "right_panel_open" },
        { id: "back", name: "Back", icon: "arrow_back", families: ["tablet"] },
        { id: "appDrawer", name: "App Drawer", icon: "apps", families: ["tablet"] },
        { id: "recents", name: "Recent Apps", icon: "overview", families: ["tablet"] },
        { id: "home", name: "Home Screen", icon: "home", families: ["tablet"] },
        // Shows hub mode on demand instead of waiting for the charge-and-idle trigger,
        // which is the only way anyone can see what the preference does before choosing
        // it. See GlobalStates.hubModePreview.
        { id: "hubMode", name: "Hub Mode (Display)", icon: "dock", families: ["tablet"] },
        // Marked prominent: the bubble draws it as the wide tile at the top of its sheet.
        // A pen comes out mid-thought and the control for it has to be the one you cannot
        // miss, not the fourth icon in a grid.
        { id: "liveDraw", name: "Draw on Screen", icon: "draw", families: ["tablet"], prominent: true },
        // Pen mode only: it means something for as long as a barrel button is held, which
        // no gesture or bubble tile can express. Listed so the binding UI can offer it.
        { id: "dragWindow", name: "Drag Window (hold)", icon: "drag_pan", families: ["tablet"], penOnly: true },
        { id: "workspaceNext", name: "Next Workspace", icon: "chevron_right" },
        { id: "workspacePrev", name: "Previous Workspace", icon: "chevron_left" },
        { id: "cheatsheet", name: "Cheat Sheet", icon: "keyboard" },
        { id: "osk", name: "On-screen Keyboard", icon: "keyboard_alt" },
        // Tablet: the game/widget overlay is a desktop surface, permanently out.
        { id: "overlay", name: "Game / Widget Overlay", icon: "layers" , families: ["ii", "waffle"] },
        { id: "session", name: "Session / Power Menu", icon: "power_settings_new" },
        { id: "shellSwitcher", name: "Switch Shell", icon: "swap_horiz" },
        { id: "settings", name: "Settings", icon: "settings" },
        { id: "welcome", name: "Welcome Window", icon: "waving_hand" },
        { id: "usage", name: "App Usage Stats", icon: "query_stats" },
        { id: "modes", name: "Modes & Routines", icon: "tune" },
        { id: "barToggle", name: "Toggle Bar", icon: "dock_to_bottom" },
        { id: "oledSaver", name: "OLED Saver (Blackout)", icon: "brightness_empty" },
        { id: "lock", name: "Lock Screen", icon: "lock" },

        // Screen Capture & Intelligence Utilities
        { id: "regionScreenshot", name: "Screen Snip (Region)", icon: "crop_free" },
        { id: "fullscreenScreenshot", name: "Screenshot (Fullscreen)", icon: "fullscreen" },
        { id: "regionSearch", name: "Google Lens (Search Image)", icon: "image_search" },
        { id: "regionOcr", name: "Character Recognition (OCR)", icon: "document_scanner" },
        { id: "screenTranslate", name: "Translate Screen Content", icon: "g_translate" },
        // Tablet: a desktop utility, permanently out.
        { id: "colorPicker", name: "Color Picker (#HEX)", icon: "colorize" , families: ["ii", "waffle"] },
        { id: "regionRecord", name: "Record Region", icon: "videocam" },
        { id: "regionRecordWithSound", name: "Record Region (with Sound)", icon: "video_camera_front" },

        // Media & Audio Controls
        { id: "mediaControls", name: "Media Player Popup", icon: "music_note" },
        { id: "mediaPlayPause", name: "Play / Pause Track", icon: "play_arrow" },
        { id: "mediaNext", name: "Next Track", icon: "skip_next" },
        { id: "mediaPrev", name: "Previous Track", icon: "skip_previous" },
        { id: "audioMute", name: "Toggle Audio Mute", icon: "volume_off" },
        { id: "micMute", name: "Toggle Mic Mute", icon: "mic_off" },
        { id: "brightnessUp", name: "Brightness +5%", icon: "brightness_high" },
        { id: "brightnessDown", name: "Brightness -5%", icon: "brightness_low" },

        // Personalization & Appearance
        { id: "wallpaperSelector", name: "Wallpaper Selector", icon: "wallpaper" },
        { id: "wallpaperRandom", name: "Random Wallpaper", icon: "shuffle" },
        { id: "toggleLightDark", name: "Toggle Light / Dark", icon: "dark_mode" },

        // Window & Workspace Management
        // Tablet: desktop window management. Returns as an app window in Fase 5.
        { id: "scratchpad", name: "Toggle Scratchpad", icon: "inventory_2" , families: ["ii", "waffle"] },
        { id: "closeWindow", name: "Close Active Window", icon: "close" },
        { id: "toggleFullscreen", name: "Toggle Window Fullscreen", icon: "fullscreen" },
        { id: "toggleFloating", name: "Toggle Window Floating", icon: "picture_in_picture" }
    ]

    /**
     * Whether the running family can actually perform this action.
     *
     * A binding pointing at a surface the family does not load is worse than an unbound
     * gesture: the swipe is recognised, it commits, and nothing happens — which reads as
     * the touchscreen being broken rather than as a setting being wrong. Actions without
     * a `families` field work everywhere, which is nearly all of them.
     */
    function availableForFamily(action, family) {
        if (!action)
            return false;
        if (!action.families)
            return true;
        return action.families.indexOf(family ?? "ii") !== -1;
    }

    /**
     * Actions a family can perform, for a binding UI to offer.
     *
     * `penOnly` actions are left out unless asked for. "Drag window" means something for
     * as long as a stylus barrel button is held, and a swipe or a bubble tile has no way
     * to express a hold — offering it there would produce a binding that recognises the
     * gesture and then does nothing.
     */
    function availableActionsForFamily(family, includePenOnly) {
        return root.actions.filter(a => root.availableForFamily(a, family)
            && (includePenOnly === true || a.penOnly !== true));
    }

    function actionById(actionId) {
        return actions.find(action => action.id === actionId)
            ?? actions[0];
    }

    // Repeating a gesture on a target that is already open closes it again. Targets
    // that live on one monitor at a time are moved to the swiped screen instead of
    // closing when they are open somewhere else, so the gesture is never a no-op on
    // the screen it was made on.
    function shouldCloseOnScreen(isOpen, activeMonitor, screenName) {
        if (!isOpen)
            return false;
        if (!screenName || !activeMonitor)
            return true;
        return activeMonitor === screenName;
    }

    function trigger(actionId, screenName) {
        switch (actionId) {
        case "overview":
            if (shouldCloseOnScreen(GlobalStates.overviewOpen, GlobalStates.activeSearchMonitor, screenName))
                GlobalStates.overviewOpen = false;
            else
                GlobalStates.openSearch(screenName);
            break;

        case "back":
            // The family installs what back means here; shared code cannot import one to
            // ask. Doing nothing is correct on a family that never installed a handler.
            if (GlobalStates.navigateBackHandler)
                GlobalStates.navigateBackHandler();
            break;

        case "appDrawer":
            GlobalStates.toggleAppDrawer(screenName);
            break;

        case "hubMode":
            GlobalStates.toggleHubModePreview();
            break;

        case "liveDraw":
            // The family owns the ink; shared code cannot import the store to reach it.
            // Doing nothing is correct on a family that installed no handler.
            if (GlobalStates.liveDrawHandler)
                GlobalStates.liveDrawHandler();
            break;

        case "recents":
            GlobalStates.toggleRecents(screenName);
            break;

        case "home":
            // Which workspace is "home" is the family's to answer — the icons on it are
            // stored per workspace, so landing on any free one shows a blank screen and
            // strands the arrangement. Falling back to an empty workspace keeps a family
            // that installed no handler behaving as it did.
            GlobalStates.appDrawerOpen = false;
            GlobalStates.recentsOpen = false;
            if (GlobalStates.navigateHomeHandler)
                GlobalStates.navigateHomeHandler(screenName);
            else
                Hyprland.dispatch("hl.dsp.focus({ workspace = 'empty' })");
            break;

        case "workspaceNext":
            Hyprland.dispatch("hl.dsp.focus({ workspace = 'r+1' })");
            break;

        case "workspacePrev":
            Hyprland.dispatch("hl.dsp.focus({ workspace = 'r-1' })");
            break;

        case "overviewClipboard":
            GlobalStates.openSearch(screenName, "clipboard");
            break;

        case "overviewEmoji":
            GlobalStates.openSearch(screenName, "emoji");
            break;

        case "sidebarLeft":
            if (shouldCloseOnScreen(GlobalStates.sidebarLeftOpen, GlobalStates.activeLeftSidebarMonitor, screenName))
                GlobalStates.sidebarLeftOpen = false;
            else
                GlobalStates.openLeftSidebar(screenName);
            break;

        case "sidebarRight":
            if (shouldCloseOnScreen(GlobalStates.sidebarRightOpen, GlobalStates.activeRightSidebarMonitor, screenName))
                GlobalStates.sidebarRightOpen = false;
            else
                GlobalStates.openRightSidebar(screenName);
            break;

        case "cheatsheet":
            GlobalStates.toggleCheatsheet();
            break;

        case "osk":
            GlobalStates.oskOpen = !GlobalStates.oskOpen;
            break;

        case "overlay":
            GlobalStates.overlayOpen = !GlobalStates.overlayOpen;
            break;

        case "session":
            GlobalStates.sessionOpen = !GlobalStates.sessionOpen;
            break;

        case "shellSwitcher":
            GlobalStates.shellSwitcherOpen = !GlobalStates.shellSwitcherOpen;
            break;

        case "settings":
            GlobalStates.toggleSettings();
            break;

        case "welcome":
            GlobalStates.toggleWelcome();
            break;

        case "usage":
            if (PanelFamily.nativeAppWindows)
                GlobalStates.toggleTabletApp("usage");
            else
                GlobalStates.usageOpen = !GlobalStates.usageOpen;
            break;

        case "modes":
            if (PanelFamily.nativeAppWindows)
                GlobalStates.toggleTabletApp("modes");
            else
                GlobalStates.modesOpen = !GlobalStates.modesOpen;
            break;

        case "barToggle":
            GlobalStates.barOpen = !GlobalStates.barOpen;
            break;

        case "oledSaver":
            GlobalStates.oledSaverOpen = !GlobalStates.oledSaverOpen;
            break;

        case "lock":
            GlobalStates.screenLocked = true;
            Quickshell.execDetached(["bash", "-c", "loginctl lock-session 2>/dev/null || true"]);
            break;

        case "regionScreenshot":
            Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "region", "screenshot"]);
            break;

        case "fullscreenScreenshot":
            Quickshell.execDetached(["bash", "-c", "mkdir -p $(xdg-user-dir PICTURES)/Screenshots && grim -o \"$(hyprctl activeworkspace -j | jq -r '.monitor')\" $(xdg-user-dir PICTURES)/Screenshots/Screenshot_\"$(date '+%Y-%m-%d_%H.%M.%S')\".png && grim -o \"$(hyprctl activeworkspace -j | jq -r '.monitor')\" - | wl-copy"]);
            break;

        case "regionSearch":
            Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "region", "search"]);
            break;

        case "regionOcr":
            Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "region", "ocr"]);
            break;

        case "screenTranslate":
            GlobalStates.screenTranslatorOpen = true;
            break;

        case "colorPicker":
            GlobalStates.launchColorPicker();
            break;

        case "regionRecord":
            Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "region", "record"]);
            break;

        case "regionRecordWithSound":
            Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "region", "recordWithSound"]);
            break;

        case "mediaControls":
            GlobalStates.mediaControlsOpen = !GlobalStates.mediaControlsOpen;
            break;

        case "mediaPlayPause":
            Quickshell.execDetached(["playerctl", "play-pause"]);
            break;

        case "mediaNext":
            Quickshell.execDetached(["bash", "-c", "playerctl next || playerctl position `bc <<< \"100 * $(playerctl metadata mpris:length) / 1000000 / 100\"`"]);
            break;

        case "mediaPrev":
            Quickshell.execDetached(["playerctl", "previous"]);
            break;

        case "audioMute":
            Quickshell.execDetached(["wpctl", "set-mute", "@DEFAULT_SINK@", "toggle"]);
            break;

        case "micMute":
            Quickshell.execDetached(["wpctl", "set-mute", "@DEFAULT_SOURCE@", "toggle"]);
            break;

        case "brightnessUp":
            Quickshell.execDetached(["bash", "-c", "qs -c ii ipc call brightness increment 2>/dev/null || brightnessctl s 5%+"]);
            break;

        case "brightnessDown":
            Quickshell.execDetached(["bash", "-c", "qs -c ii ipc call brightness decrement 2>/dev/null || brightnessctl s 5%-"]);
            break;

        case "wallpaperSelector":
            GlobalStates.wallpaperSelectorOpen = !GlobalStates.wallpaperSelectorOpen;
            break;

        case "wallpaperRandom":
            Wallpapers.randomFromCurrentFolder();
            break;

        case "toggleLightDark":
            MaterialThemeLoader.toggleLightDark();
            break;

        case "scratchpad":
            Hyprland.dispatch("hl.dsp.workspace.toggle_special('special')");
            break;

        case "closeWindow":
            Hyprland.dispatch("hl.dsp.window.close()");
            break;

        case "toggleFullscreen":
            Hyprland.dispatch("hl.dsp.window.fullscreen({ mode = 'fullscreen', action = 'toggle' })");
            break;

        case "toggleFloating":
            Hyprland.dispatch("hl.dsp.window.float({ action = 'toggle' })");
            break;

        case "none":
        default:
            break;
        }
    }
}
