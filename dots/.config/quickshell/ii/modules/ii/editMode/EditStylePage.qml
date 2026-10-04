import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * The Style catalogue's root: the presets, light or dark, the colour scheme -
 * and the way to the settings pages that hold the rest.
 *
 * The wallpaper used to live here too. It has a catalogue of its own now
 * (EditWallpaperRootPage): each screen's picture, which one the colours come
 * from, and its framing are more than a section of this page could hold.
 *
 * Preferences, not layout edits, but they are recorded all the same: a scheme
 * or a theme is a choice you want to walk back from as readily as a moved
 * widget, so the chrome surface watches the keys and pushes a history entry
 * for each change (EditModeChromeSurface's style history).
 */
StyledFlickable {
    id: root

    contentHeight: column.implicitHeight
    clip: true

    signal openPageRequested(string page)
    // The presets block's name field, relayed to the panel that holds the keyboard.
    signal fieldFocusRequested(Item field)
    signal fieldFocusReleased()

    readonly property var background: Config.options.background
    readonly property bool darkMode: Appearance.m3colors.darkmode

    readonly property string schemeType: String(Config.options.appearance.palette.type ?? "scheme-auto")
    function schemeName(type) {
        if (type.startsWith("scheme-")) {
            const words = type.substring(7).split("-").join(" ");
            return words.charAt(0).toUpperCase() + words.slice(1);
        }
        return type.charAt(0).toUpperCase() + type.slice(1);
    }

    // The same two calls Settings' light/dark toggle makes: the switch script
    // changes the mode, and the separate light wallpaper, when there is one,
    // goes with it.
    function setDarkMode(dark) {
        if (dark === root.darkMode)
            return;
        if (root.background.useSeparateLightModeWallpaper) {
            const path = dark ? root.background.wallpaperPath : root.background.lightModeWallpaperPath;
            if (path && path !== "") {
                if (dark)
                    Wallpapers.apply(path, true);
                else
                    Wallpapers.applyLightModeWallpaper(path);
                return;
            }
        }
        Quickshell.execDetached(["bash", "-c", `${Directories.wallpaperSwitchScriptPath} --mode ${dark ? "dark" : "light"} --noswitch`]);
    }

    ColumnLayout {
        id: column
        width: root.width
        spacing: 3

        // ── Presets ──────────────────────────────────────────────────────────
        EditStylePresets {
            Layout.fillWidth: true
            onFieldFocusRequested: field => root.fieldFocusRequested(field)
            onFieldFocusReleased: root.fieldFocusReleased()
        }

        // ── Colours ──────────────────────────────────────────────────────────
        EditOptionChips {
            Layout.topMargin: 10
            label: Translation.tr("Theme")
            compact: false
            currentValue: root.darkMode ? "dark" : "light"
            options: [
                { "displayName": Translation.tr("Light"), "icon": "light_mode", "value": "light" },
                { "displayName": Translation.tr("Dark"), "icon": "dark_mode", "value": "dark" }
            ]
            onSelected: value => root.setDarkMode(value === "dark")
        }

        EditPanelRow {
            Layout.fillWidth: true
            Layout.topMargin: 6
            first: true
            last: true
            symbol: "palette"
            title: Translation.tr("Colour scheme")
            subtitle: root.schemeName(root.schemeType)
            trailingKind: "chevron"
            onActivated: root.openPageRequested("colours")
        }

        // App theming, scheduling, Wallpaper Engine, the online browser: pages
        // of forms, and Settings is where they belong.
        EditPanelRow {
            Layout.fillWidth: true
            Layout.topMargin: 10
            symbol: "settings"
            title: Translation.tr("Colours & Themes settings")
            subtitle: Translation.tr("Leaves Edit Mode")
            trailingKind: "chevron"
            onActivated: GlobalStates.openSettingsFromEditMode("colors")
        }

        Item {
            Layout.fillWidth: true
            implicitHeight: 8
        }
    }
}
