import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * The Style catalogue's root: the wallpaper, light or dark, the colour scheme,
 * the wallpaper's variants - and the way to the settings pages that hold the
 * rest.
 *
 * The mode is where the desktop gets arranged, and the wallpaper and the
 * palette are the two things that decide whether an arrangement looks right.
 * Until now both lived a window away, in the selector and in Settings, and
 * the card - a live preview of the very desktop - could not show either
 * change. Everything on this page applies at once and the card follows.
 *
 * Which wallpaper is being chosen depends on where the mode is looking. On
 * the Lockscreen tab, with a separate lock wallpaper enabled, the page edits
 * that one; in light mode with a separate light wallpaper enabled, that one;
 * otherwise the desktop's own. The page says which, so a pick never lands
 * somewhere the card is not showing.
 *
 * Preferences, not layout edits, but they are recorded all the same: a
 * wallpaper or a scheme is a choice you want to walk back from as readily as
 * a moved widget, so the chrome surface watches the keys and pushes a
 * history entry for each change (EditModeChromeSurface's style history).
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
    readonly property bool lockTarget: GlobalStates.editLockPreview && root.separateLock
    readonly property bool lightTarget: !root.lockTarget && root.separateLight && !root.darkMode
    readonly property string targetPath: FileUtils.trimFileProtocol(String(
        (root.lockTarget ? root.background.lockscreenWallpaperPath
            : root.lightTarget ? root.background.lightModeWallpaperPath
            : root.background.wallpaperPath) ?? ""))
    readonly property string targetName: root.fileName(root.targetPath)
    readonly property string targetDisplayName: root.wallpaperEngine
        ? Translation.tr("Wallpaper Engine scene") : root.targetName
    readonly property bool separateLock: root.background.useSeparateLockscreenWallpaper ?? false
    readonly property bool separateLight: root.background.useSeparateLightModeWallpaper ?? false

    function fileName(rawPath) {
        const path = FileUtils.trimFileProtocol(String(rawPath ?? ""));
        if (path === "")
            return Translation.tr("No wallpaper set");
        return path.substring(path.lastIndexOf("/") + 1);
    }
    readonly property string targetLabel: root.lockTarget ? Translation.tr("Lock screen wallpaper")
        : root.lightTarget ? Translation.tr("Light mode wallpaper") : Translation.tr("Wallpaper")
    readonly property bool wallpaperEngine: root.background.useWallpaperEngine ?? false

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

        // ── Wallpaper ────────────────────────────────────────────────────────
        EditPanelSectionLabel {
            Layout.topMargin: 10
            text: root.targetLabel
        }

        // The wallpaper itself, at the card's own proportions, and a click on
        // it opens the folder. A thumbnail rather than the file: the desktop's
        // wallpaper is a full-resolution image and the panel is 380px wide.
        Rectangle {
            id: preview
            Layout.fillWidth: true
            Layout.leftMargin: 4
            Layout.rightMargin: 4
            implicitHeight: Math.round(width * 10 / 16)
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1

            ClippingRectangle {
                anchors.fill: parent
                radius: preview.radius
                color: "transparent"

                Loader {
                    anchors.fill: parent
                    active: root.targetPath !== "" && !root.wallpaperEngine
                    sourceComponent: ThumbnailImage {
                        sourcePath: root.targetPath
                        thumbnailService: Wallpapers
                        fillMode: Image.PreserveAspectCrop
                        cache: false
                    }
                }
            }

            MaterialSymbol {
                anchors.centerIn: parent
                visible: root.targetPath === "" || root.wallpaperEngine
                text: root.wallpaperEngine ? "animation" : "wallpaper"
                iconSize: 36
                color: Appearance.colors.colOnSurfaceVariant
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openPageRequested("wallpapers")
            }
        }

        // Keep the wallpaper name in the same separate surface used by the
        // preset cards instead of laying text over the image.
        Rectangle {
            id: wallpaperNameCard
            Layout.fillWidth: true
            Layout.leftMargin: 4
            Layout.rightMargin: 4
            Layout.topMargin: 6
            implicitHeight: Math.max(52, wallpaperNameRow.implicitHeight + 20)
            radius: Appearance.rounding.normal
            color: Appearance.colors.colSurfaceContainerLow

            RowLayout {
                id: wallpaperNameRow
                anchors.fill: parent
                anchors.margins: 10
                spacing: 10

                Rectangle {
                    Layout.preferredWidth: 30
                    Layout.preferredHeight: 30
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colSecondaryContainer

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: root.wallpaperEngine ? "animation" : "wallpaper"
                        iconSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnSecondaryContainer
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.targetDisplayName
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer1
                    elide: Text.ElideMiddle
                }
            }
        }

        EditPanelRow {
            Layout.fillWidth: true
            Layout.topMargin: 6
            first: true
            last: false
            symbol: "photo_library"
            title: Translation.tr("Choose from your folder")
            subtitle: Wallpapers.effectiveDirectory.replace(FileUtils.trimFileProtocol(Directories.home), "~")
            trailingKind: "chevron"
            onActivated: root.openPageRequested("wallpapers")
        }

        // A disabled row with no reason on it reads as a bug, and this one
        // is only ever disabled on the Lockscreen tab: the shuffle sets the
        // desktop's wallpaper, which is not the one the page is showing.
        EditPanelRow {
            Layout.fillWidth: true
            first: false
            last: false
            rowEnabled: !root.lockTarget
            symbol: "shuffle"
            title: Translation.tr("Random from this folder")
            subtitle: root.lockTarget ? Translation.tr("Not available for the lock screen wallpaper") : ""
            trailingKind: "none"
            onActivated: Wallpapers.randomFromCurrentFolder(root.darkMode)
        }

        // The full selector - search, the online browser, sorting, folders -
        // is a strip across the top of the screen. It opens over the mode's
        // toolbar and the mode stays on underneath it.
        EditPanelRow {
            Layout.fillWidth: true
            first: false
            last: true
            symbol: "open_in_full"
            title: Translation.tr("Browse all wallpapers")
            subtitle: Translation.tr("Search, folders and the online browser")
            trailingKind: "chevron"
            onActivated: GlobalStates.openWallpaperSelectorFromEditMode(root.lockTarget ? "lockscreen"
                : root.lightTarget ? "lightmode" : "desktop")
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

        // ── Variants ─────────────────────────────────────────────────────────
        EditPanelSectionLabel {
            text: Translation.tr("Variants")
        }

        // Each switch is followed by the row that picks the variant's own
        // wallpaper, so neither needs a tab or a theme change to get to.
        EditPanelRow {
            Layout.fillWidth: true
            first: true
            last: false
            symbol: "lock"
            title: Translation.tr("Separate lock screen wallpaper")
            trailingKind: "switch"
            switchChecked: root.separateLock
            onActivated: Config.options.background.useSeparateLockscreenWallpaper = !root.separateLock
        }

        EditPanelRow {
            Layout.fillWidth: true
            visible: root.separateLock
            first: false
            last: false
            symbol: "wallpaper"
            title: Translation.tr("Lock screen wallpaper")
            subtitle: root.fileName(root.background.lockscreenWallpaperPath)
            trailingKind: "chevron"
            onActivated: root.openPageRequested("wallpapers:lockscreen")
        }

        EditPanelRow {
            Layout.fillWidth: true
            first: false
            last: !root.separateLight
            symbol: "light_mode"
            title: Translation.tr("Separate light mode wallpaper")
            trailingKind: "switch"
            switchChecked: root.separateLight
            onActivated: Config.options.background.useSeparateLightModeWallpaper = !root.separateLight
        }

        EditPanelRow {
            Layout.fillWidth: true
            visible: root.separateLight
            first: false
            last: true
            symbol: "wallpaper"
            title: Translation.tr("Light mode wallpaper")
            subtitle: root.fileName(root.background.lightModeWallpaperPath)
            trailingKind: "chevron"
            onActivated: root.openPageRequested("wallpapers:lightmode")
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
