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
        { id: "overview", name: "Overview / Search", icon: "grid_view" },
        { id: "overviewClipboard", name: "Clipboard History", icon: "content_paste" },
        { id: "overviewEmoji", name: "Emoji Picker", icon: "mood" },
        { id: "sidebarLeft", name: "Left Sidebar", icon: "left_panel_open" },
        { id: "sidebarRight", name: "Right Sidebar", icon: "right_panel_open" },
        { id: "cheatsheet", name: "Cheat Sheet", icon: "keyboard" },
        { id: "osk", name: "On-screen Keyboard", icon: "keyboard_alt" },
        { id: "overlay", name: "Game / Widget Overlay", icon: "layers" },
        { id: "session", name: "Session / Power Menu", icon: "power_settings_new" },
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
        { id: "colorPicker", name: "Color Picker (#HEX)", icon: "colorize" },
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
        { id: "scratchpad", name: "Toggle Scratchpad", icon: "inventory_2" },
        { id: "closeWindow", name: "Close Active Window", icon: "close" },
        { id: "toggleFullscreen", name: "Toggle Window Fullscreen", icon: "fullscreen" },
        { id: "toggleFloating", name: "Toggle Window Floating", icon: "picture_in_picture" }
    ]

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

        case "settings":
            GlobalStates.toggleSettings();
            break;

        case "welcome":
            GlobalStates.toggleWelcome();
            break;

        case "usage":
            GlobalStates.usageOpen = !GlobalStates.usageOpen;
            break;

        case "modes":
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
