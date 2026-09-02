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

    readonly property var background: Config.options.background
    readonly property bool darkMode: Appearance.m3colors.darkmode
    readonly property bool lockTarget: GlobalStates.editLockPreview && (root.background.useSeparateLockscreenWallpaper ?? false)
    readonly property bool lightTarget: !root.lockTarget && (root.background.useSeparateLightModeWallpaper ?? false) && !root.darkMode
    readonly property string targetPath: FileUtils.trimFileProtocol(String(
        (root.lockTarget ? root.background.lockscreenWallpaperPath
            : root.lightTarget ? root.background.lightModeWallpaperPath
            : root.background.wallpaperPath) ?? ""))
    readonly property string targetName: {
        const path = root.targetPath;
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

        // ── Wallpaper ────────────────────────────────────────────────────────
        EditPanelSectionLabel {
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
            border.width: 1
            border.color: Appearance.colors.colLayer0Border

            ClippingRectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: preview.radius - 1
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

            // The name, on a scrim along the bottom edge so it reads over
            // any picture.
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 1
                height: nameLabel.implicitHeight + 14
                bottomLeftRadius: preview.radius - 1
                bottomRightRadius: preview.radius - 1
                color: ColorUtils.transparentize(Appearance.m3colors.m3surfaceContainer, 0.2)

                StyledText {
                    id: nameLabel
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    verticalAlignment: Text.AlignVCenter
                    text: root.wallpaperEngine ? Translation.tr("Wallpaper Engine scene") : root.targetName
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnSurface
                    elide: Text.ElideMiddle
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

        EditPanelRow {
            Layout.fillWidth: true
            first: false
            last: false
            rowEnabled: !root.lockTarget
            symbol: "shuffle"
            title: Translation.tr("Random from this folder")
            trailingKind: "none"
            onActivated: Wallpapers.randomFromCurrentFolder(root.darkMode)
        }

        // The full selector - search, the online browser, sorting, folders -
        // is a strip across the top of the screen, where the mode's own
        // toolbar sits. Handing off means leaving the mode.
        EditPanelRow {
            Layout.fillWidth: true
            first: false
            last: true
            symbol: "open_in_full"
            title: Translation.tr("Browse all wallpapers")
            subtitle: Translation.tr("Leaves Edit Mode")
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

        EditPanelRow {
            Layout.fillWidth: true
            first: true
            last: false
            symbol: "lock"
            title: Translation.tr("Separate lock screen wallpaper")
            subtitle: (root.background.useSeparateLockscreenWallpaper ?? false)
                ? Translation.tr("Pick it from the Lock screen tab") : ""
            trailingKind: "switch"
            switchChecked: root.background.useSeparateLockscreenWallpaper ?? false
            onActivated: Config.options.background.useSeparateLockscreenWallpaper = !(root.background.useSeparateLockscreenWallpaper ?? false)
        }

        EditPanelRow {
            Layout.fillWidth: true
            first: false
            last: true
            symbol: "light_mode"
            title: Translation.tr("Separate light mode wallpaper")
            subtitle: (root.background.useSeparateLightModeWallpaper ?? false)
                ? Translation.tr("Pick it while the theme is light") : ""
            trailingKind: "switch"
            switchChecked: root.background.useSeparateLightModeWallpaper ?? false
            onActivated: Config.options.background.useSeparateLightModeWallpaper = !(root.background.useSeparateLightModeWallpaper ?? false)
        }

        // App theming, scheduling, Wallpaper Engine, the online browser: pages
        // of forms, and Settings is where they belong.
        EditPanelRow {
            Layout.fillWidth: true
            Layout.topMargin: 10
            symbol: "settings"
            title: Translation.tr("All colour settings")
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
