pragma Singleton
import QtQuick
import Quickshell

/**
 * Single source of truth for the settings window's pages.
 *
 * Pages are addressed by stable string `id` — never by array index.
 * `name` holds the untranslated string key; display code (SettingsWindow,
 * Sidebar) applies Translation.tr so language switches stay reactive.
 *
 * Fields per page:
 *  - id:         stable identifier used by deep links and navigation helpers
 *  - name:       untranslated display name key
 *  - icon:       Material Symbol name
 *  - component:  page file, relative to the ii config root
 *  - subPages:   widget config files opened from this page, relative to
 *                modules/settings/configs/ (used for search indexing)
 *  - aliases:    extra untranslated search terms (old page names etc.)
 *  - hidden:     not shown in the sidebar, excluded from keyboard cycling.
 *                Hidden pages must stay at the END of the list.
 *  - searchable: set false to skip the file during search indexing
 */
Singleton {
    // Group 1 – Look & Feel
    // Group 2 – Modules
    // Group 3 – Desktop & Windows
    // Group 4 – Tools
    // Group 5 – System & Services
    // Hidden pages — keep at the end of the list

    id: root

    readonly property var pages: [{
        "id": "colors",
        "name": "Colors & Themes",
        "icon": "palette",
        "component": "modules/settings/configs/ColorsThemesConfig.qml",
        "subPages": [],
        "aliases": []
    }, {
        "id": "bar",
        "name": "Bar",
        "icon": "space_bar",
        "component": "modules/settings/configs/BarConfig.qml",
        "subPages": ["widgets/ActiveWindowConfig.qml", "widgets/MediaPlayerConfig.qml", "widgets/UtilButtonsConfig.qml", "widgets/KeyboardLayoutConfig.qml", "widgets/SystemMonitorConfig.qml", "widgets/IndicatorsConfig.qml", "widgets/SportsConfig.qml", "widgets/BluetoothConfig.qml", "widgets/SystemTrayConfig.qml", "widgets/BatteryConfig.qml", "widgets/DashboardButtonConfig.qml", "widgets/BTDeviceImagesConfig.qml", "widgets/CorePoliciesConfig.qml", "widgets/CoreTimeDateConfig.qml", "widgets/CoreWeatherConfig.qml", "widgets/CorePowerConfig.qml", "widgets/WaffleTweaksConfig.qml"],
        "aliases": ["Bar & Status Bar", "Status Bar", "Shell mode", "Waffle"]
    }, {
        "id": "wallpaper",
        "name": "Wallpaper",
        "icon": "wallpaper",
        "component": "modules/settings/configs/WallpaperConfig.qml",
        "subPages": [],
        "aliases": ["Backgrounds", "Wallpaper Engine"]
    }, {
        "id": "interfaceFonts",
        "name": "Interface & Fonts",
        "icon": "font_download",
        "component": "modules/settings/configs/InterfaceFontsConfig.qml",
        "subPages": [],
        "aliases": ["Base Icon Themes", "Decorative Options"]
    }, {
        "id": "presets",
        "name": "Presets",
        "icon": "auto_awesome",
        "component": "modules/settings/configs/PresetsConfig.qml",
        "subPages": [],
        "aliases": []
    }, {
        "id": "sidebars",
        "name": "Sidebars",
        "icon": "side_navigation",
        "component": "modules/settings/configs/SidebarsConfig.qml",
        "subPages": [],
        "aliases": ["Sidebars & Panels", "Panels"]
    }, {
        "id": "dock",
        "name": "Dock",
        "icon": "dock_to_bottom",
        "component": "modules/settings/configs/DockConfig.qml",
        "subPages": [],
        "aliases": []
    }, {
        "id": "workspaces",
        "name": "Workspaces",
        "icon": "workspaces",
        "component": "modules/settings/configs/WorkspacesConfig.qml",
        "subPages": [],
        "aliases": ["Tint workspaces icons"]
    }, {
        "id": "overview",
        "name": "Overview",
        "icon": "grid_view",
        "component": "modules/settings/configs/OverviewConfig.qml",
        "subPages": [],
        "aliases": []
    }, {
        "id": "widgets",
        "name": "Desktop Widgets",
        "icon": "widgets",
        "component": "modules/settings/configs/WidgetsConfig.qml",
        "subPages": ["widgets/DesktopClockWidgetConfig.qml", "widgets/DesktopWeatherWidgetConfig.qml", "widgets/DesktopMediaWidgetConfig.qml"],
        "aliases": []
    }, {
        "id": "dynamicIsland",
        "name": "Dynamic Island",
        "icon": "water_drop",
        "component": "modules/settings/configs/DynamicIslandConfig.qml",
        "subPages": [],
        "aliases": []
    }, {
        "id": "overlays",
        "name": "Overlays & OSD",
        "icon": "picture_in_picture",
        "component": "modules/settings/configs/OverlaysConfig.qml",
        "subPages": ["widgets/GameOverlayConfig.qml"],
        "aliases": ["System Overlays", "Media overlay", "Game overlay"]
    }, {
        "id": "screenCapture",
        "name": "Screenshots & Recording",
        "icon": "screenshot_region",
        "component": "modules/settings/configs/ScreenCaptureConfig.qml",
        "subPages": [],
        "aliases": ["Region Selector", "Screenshot", "Screen recording", "Google Lens", "wf-recorder", "OBS"]
    }, {
        "id": "notifications",
        "name": "Notifications",
        "icon": "notifications",
        "component": "modules/settings/configs/NotificationsConfig.qml",
        "subPages": [],
        "aliases": []
    }, {
        "id": "launcher",
        "name": "Launcher",
        "icon": "search",
        "component": "modules/settings/configs/LauncherConfig.qml",
        "subPages": [],
        "aliases": ["App Search", "Search Prefixes", "App Aliases"]
    }, {
        "id": "clipboard",
        "name": "Clipboard",
        "icon": "content_paste",
        "component": "modules/settings/configs/ClipboardConfig.qml",
        "subPages": [],
        "aliases": ["Clipboard History Search"]
    }, {
        "id": "cheatSheet",
        "name": "Cheat Sheet",
        "icon": "help",
        "component": "modules/settings/configs/CheatSheetConfig.qml",
        "subPages": [],
        "aliases": []
    }, {
        "id": "windows",
        "name": "Windows",
        "icon": "rule",
        "component": "modules/settings/configs/WindowsConfig.qml",
        "subPages": [],
        "aliases": ["Hyprland Rules", "Transparency", "Blur", "Gaps", "Borders"]
    }, {
        "id": "monitors",
        "name": "Monitors",
        "icon": "monitor",
        "component": "modules/settings/configs/MonitorsConfig.qml",
        "subPages": [],
        "aliases": []
    }, {
        "id": "coreServices",
        "name": "Core Services",
        "icon": "settings_suggest",
        "component": "modules/settings/configs/CoreServicesConfig.qml",
        "subPages": ["widgets/CoreAudioConfig.qml", "widgets/CorePowerConfig.qml", "widgets/CoreTimeDateConfig.qml", "widgets/CoreLanguageConfig.qml", "widgets/CoreAlertsConfig.qml", "widgets/CoreMediaConfig.qml", "widgets/CorePoliciesConfig.qml", "widgets/CoreNetworkConfig.qml", "widgets/CoreFilesConfig.qml", "widgets/CoreWeatherConfig.qml", "widgets/MediaDownloaderConfig.qml"],
        "aliases": []
    }, {
        "id": "lockScreen",
        "name": "Lock Screen",
        "icon": "lock",
        "component": "modules/settings/configs/LockScreenConfig.qml",
        "subPages": [],
        "aliases": []
    }, {
        "id": "about",
        "name": "About & Updates",
        "icon": "info",
        "component": "modules/settings/configs/AboutConfig.qml",
        "subPages": [],
        "aliases": []
    }, {
        "id": "profile",
        "name": "User Profile",
        "icon": "account_circle",
        "component": "modules/settings/configs/UserProfileConfig.qml",
        "subPages": [],
        "aliases": ["Sidebar header"],
        "hidden": true
    }, {
        "id": "search",
        "name": "Search Results",
        "icon": "search",
        "component": "modules/settings/configs/SearchPage.qml",
        "subPages": [],
        "aliases": [],
        "hidden": true,
        "searchable": false
    }]
    readonly property var groups: [{
        "id": "lookAndFeel",
        "name": "Look & Feel",
        "pageIds": ["colors", "bar", "wallpaper", "interfaceFonts", "presets"]
    }, {
        "id": "modules",
        "name": "Modules",
        "pageIds": ["sidebars", "dock", "dynamicIsland"]
    }, {
        "id": "desktopWindows",
        "name": "Desktop & Windows",
        "pageIds": ["widgets", "workspaces", "overview", "windows", "lockScreen"]
    }, {
        "id": "tools",
        "name": "Tools",
        "pageIds": ["launcher", "clipboard", "screenCapture", "notifications", "overlays", "cheatSheet"]
    }, {
        "id": "systemServices",
        "name": "System & Services",
        "pageIds": ["monitors", "coreServices", "about"]
    }]

    function pageIndexById(id) {
        for (let i = 0; i < pages.length; i++) {
            if (pages[i].id === id)
                return i;

        }
        return -1;
    }

    function pageById(id) {
        const i = pageIndexById(id);
        return i >= 0 ? pages[i] : null;
    }

}
