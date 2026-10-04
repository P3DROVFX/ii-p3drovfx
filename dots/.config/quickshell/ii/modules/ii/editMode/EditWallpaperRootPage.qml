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
 * The Wallpaper catalogue's root: the picture on the screen being edited, the
 * screens and the one the colours come from, and how the picture sits.
 *
 * Opening it turns the desktop card into the picture itself
 * (EditWallpaperFramingOverlay, on the Desktop tab): the controls under
 * "Position & zoom" are the exact, keyboardless twins of what the card does by
 * hand, so either can be used and each shows what the other did.
 *
 * Which wallpaper the picker rows set follows the tab, the screen and the
 * theme, as the folder page does (EditModeDrawer.wallpaperPageTarget): the
 * lock's own on the Lockscreen tab when there is one, this screen's own when it
 * has one, the light-mode one in light mode when there is one, the shared one
 * otherwise - and the page says which.
 *
 * Writes go through WallpaperLayout and Wallpapers, both of which the mode's
 * history already hears: the per-screen list records its own entries, and a
 * shared wallpaper change is the style history's (EditModeChromeSurface).
 */
StyledFlickable {
    id: root

    property string screenName: ""
    signal openPageRequested(string page)

    contentHeight: column.implicitHeight
    clip: true

    readonly property var background: Config.options.background
    readonly property bool darkMode: Appearance.m3colors.darkmode
    readonly property bool lockTab: GlobalStates.editLockPreview
    readonly property bool separateLock: root.background.useSeparateLockscreenWallpaper ?? false
    readonly property bool separateLight: root.background.useSeparateLightModeWallpaper ?? false
    readonly property bool wallpaperEngine: root.background.useWallpaperEngine ?? false

    readonly property bool lockTarget: root.lockTab && root.separateLock
    readonly property bool ownScreen: !root.lockTab && WallpaperLayout.hasOwn(root.screenName)
    readonly property bool lightTarget: !root.lockTarget && !root.ownScreen && root.separateLight && !root.darkMode
    readonly property string targetPath: root.lockTarget
        ? FileUtils.trimFileProtocol(String(root.background.lockscreenWallpaperPath ?? ""))
        : WallpaperLayout.sourcePathFor(root.screenName)
    readonly property string targetLabel: root.lockTarget ? Translation.tr("Lock screen wallpaper")
        : root.ownScreen ? Translation.tr("This screen's own wallpaper")
        : root.lightTarget ? Translation.tr("Light mode wallpaper")
        : WallpaperLayout.multiScreen ? Translation.tr("Shared wallpaper")
        : Translation.tr("Wallpaper")

    // Whether this screen shows the picture the palette is made from, when
    // there is more than one picture to tell apart.
    readonly property bool coloursFromHere: !root.lockTarget && WallpaperLayout.distinctWallpapers && !root.ownScreen

    readonly property bool framingAvailable: !root.lockTab && WallpaperLayout.available
    readonly property var framing: WallpaperLayout.currentFraming(root.screenName)
    readonly property bool framingIdentity: WallpaperFraming.isIdentity(root.framing)

    function fileName(rawPath) {
        const path = FileUtils.trimFileProtocol(String(rawPath ?? ""));
        if (path === "")
            return Translation.tr("No wallpaper set");
        return path.substring(path.lastIndexOf("/") + 1);
    }

    ColumnLayout {
        id: column
        width: root.width
        spacing: 3

        // ── The picture ──────────────────────────────────────────────────────
        EditPanelSectionLabel {
            text: WallpaperLayout.multiScreen && !root.lockTarget
                ? root.targetLabel + " · " + root.screenName
                : root.targetLabel
        }

        // The picture at the card's proportions, with what it is said on it:
        // the file's name bottom-left, the way to change it bottom-right and,
        // top-left, whether the colours come from it. The whole picture opens
        // the folder, the same action as the button. A thumbnail rather than
        // the file: the panel is 380px wide.
        Rectangle {
            id: preview
            Layout.fillWidth: true
            Layout.leftMargin: 4
            Layout.rightMargin: 4
            implicitHeight: Math.round(width * 10 / 16)
            radius: Appearance.rounding.verylarge
            color: Appearance.colors.colLayer1

            readonly property bool showsEngine: root.wallpaperEngine && !root.ownScreen && !root.lockTarget
            // Pills along one edge share a height (settings-expressive §2.1).
            readonly property int pillHeight: 32

            ClippingRectangle {
                anchors.fill: parent
                radius: preview.radius
                color: "transparent"

                Loader {
                    anchors.fill: parent
                    active: root.targetPath !== "" && !preview.showsEngine
                    sourceComponent: ThumbnailImage {
                        sourcePath: root.targetPath
                        thumbnailService: Wallpapers
                        fillMode: Image.PreserveAspectCrop
                        cache: false
                    }
                }

                // The hover scrim: the picture answers the pointer as one
                // button.
                Rectangle {
                    anchors.fill: parent
                    color: Appearance.m3colors.m3scrim
                    opacity: previewHover.hovered ? 0.35 : 0
                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                }
            }

            MaterialSymbol {
                anchors.centerIn: parent
                visible: root.targetPath === "" || preview.showsEngine
                text: root.wallpaperEngine ? "animation" : "wallpaper"
                iconSize: Appearance.font.pixelSize.huge * 1.5
                color: Appearance.colors.colOnSurfaceVariant
            }

            HoverHandler {
                id: previewHover
                cursorShape: Qt.PointingHandCursor
            }
            TapHandler {
                onTapped: root.openPageRequested("wallpapers")
            }

            // Status, top-left: this picture is the one the palette is made
            // from, when there is more than one picture on screen.
            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.margins: 10
                visible: root.coloursFromHere
                implicitWidth: coloursRow.implicitWidth + 20
                implicitHeight: preview.pillHeight
                radius: Appearance.rounding.full
                color: Appearance.colors.colPrimaryContainer

                Row {
                    id: coloursRow
                    anchors.centerIn: parent
                    spacing: 6
                    MaterialSymbol {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "palette"
                        fill: 1
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnPrimaryContainer
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Translation.tr("Colours")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnPrimaryContainer
                    }
                }
            }

            // The name, bottom-left.
            Rectangle {
                id: nameTag
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.margins: 10
                width: Math.min(nameText.implicitWidth + 24, preview.width - changeButton.width - 30)
                height: preview.pillHeight
                radius: Appearance.rounding.full
                color: Appearance.colors.colSurfaceContainerHigh

                StyledText {
                    id: nameText
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    verticalAlignment: Text.AlignVCenter
                    text: preview.showsEngine ? Translation.tr("Wallpaper Engine scene") : root.fileName(root.targetPath)
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnSurface
                    elide: Text.ElideMiddle
                }
            }

            // The action, bottom-right: icon-only on a card this narrow
            // (settings-expressive §4, < 420px).
            RippleButton {
                id: changeButton
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 10
                implicitWidth: preview.pillHeight
                implicitHeight: preview.pillHeight
                buttonRadius: preview.pillHeight / 2
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                colRipple: Appearance.colors.colPrimaryActive
                onClicked: root.openPageRequested("wallpapers")

                contentItem: MaterialSymbol {
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: "photo_library"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnPrimary
                }

                StyledToolTip {
                    requireOverlay: false
                    text: Translation.tr("Choose from your folder")
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

        // Disabled with its reason on the Lockscreen tab: the shuffle sets the
        // desktop's wallpaper, which is not the one the page is showing.
        EditPanelRow {
            Layout.fillWidth: true
            first: false
            last: false
            rowEnabled: !root.lockTarget
            symbol: "shuffle"
            title: Translation.tr("Random from this folder")
            subtitle: root.lockTarget ? Translation.tr("Not available for the lock screen wallpaper")
                : root.ownScreen ? Translation.tr("Only this screen changes") : ""
            trailingKind: "none"
            onActivated: {
                if (root.ownScreen)
                    WallpaperLayout.randomForScreen(root.screenName);
                else
                    Wallpapers.randomFromCurrentFolder(root.darkMode);
            }
        }

        // The full selector - search, the online browser, sorting, folders -
        // opens over the mode's toolbar and the mode stays on underneath it.
        EditPanelRow {
            Layout.fillWidth: true
            first: false
            last: true
            symbol: "open_in_full"
            title: Translation.tr("Browse all wallpapers")
            subtitle: Translation.tr("Search, folders and the online browser")
            trailingKind: "chevron"
            onActivated: GlobalStates.openWallpaperSelectorFromEditMode(root.lockTarget ? "lockscreen"
                : root.ownScreen ? "screen:" + root.screenName
                : root.lightTarget ? "lightmode" : "desktop")
        }

        // ── Screens ──────────────────────────────────────────────────────────
        // One palette, many pictures: a screen can show its own, and the
        // colours come from whichever picture is the shared one. Choosing
        // another screen there swaps its picture in as the shared one; no
        // screen changes what it shows.
        EditPanelSectionLabel {
            visible: !root.lockTab && WallpaperLayout.multiScreen
            text: Translation.tr("Screens")
        }

        EditPanelNotice {
            Layout.leftMargin: 4
            Layout.rightMargin: 4
            visible: !root.lockTab && WallpaperLayout.multiScreen && !WallpaperLayout.available
            symbol: "movie"
            text: Translation.tr("A video or Wallpaper Engine scene is painting every screen, so each one shows it. Pick a picture to give screens their own.")
        }

        // The screens where they stand. The mode is on one screen at a time;
        // a click on another moves it there with the catalogue open
        // (GlobalStates.switchEditMonitor), and hovering one offers what is
        // done between two screens.
        EditWallpaperScreenMap {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            Layout.topMargin: 6
            Layout.bottomMargin: 10
            visible: !root.lockTab && WallpaperLayout.multiScreen
            screenName: root.screenName
        }

        EditPanelRow {
            Layout.fillWidth: true
            visible: !root.lockTab && WallpaperLayout.multiScreen && WallpaperLayout.available
            symbol: "monitor"
            first: true
            last: false
            title: Translation.tr("Own wallpaper on this screen")
            rowEnabled: root.ownScreen || WallpaperLayout.canDetach(root.screenName)
            subtitle: root.ownScreen ? Translation.tr("Picks above change only this screen")
                : WallpaperLayout.canDetach(root.screenName)
                    ? Translation.tr("Picks above change every screen showing the shared wallpaper")
                    : Translation.tr("The last screen showing the colour wallpaper. Take the colours from another screen first.")
            subtitleWrap: true
            trailingKind: "switch"
            switchChecked: root.ownScreen
            onActivated: {
                if (root.ownScreen) {
                    WallpaperLayout.attach(root.screenName);
                    return;
                }
                // A shared video cannot be copied to one screen: pick a
                // picture for it instead.
                if (!WallpaperLayout.detach(root.screenName))
                    root.openPageRequested("wallpapers:screen");
            }
        }

        // One picture across every screen, this screen's: each screen frames
        // its own piece of it (WallpaperLayout.spanFrom).
        EditPanelRow {
            Layout.fillWidth: true
            visible: !root.lockTab && WallpaperLayout.multiScreen && WallpaperLayout.available
            first: false
            last: true
            symbol: "panorama"
            title: Translation.tr("Span across every screen")
            rowEnabled: WallpaperLayout.spanned || WallpaperLayout.canSpanFrom(root.screenName)
            subtitle: WallpaperLayout.spanned ? Translation.tr("One picture runs from screen to screen")
                : WallpaperLayout.canSpanFrom(root.screenName)
                    ? Translation.tr("This screen's picture, cut to the screens' layout")
                    : Translation.tr("Needs a picture on this screen, not a video")
            subtitleWrap: true
            trailingKind: "switch"
            switchChecked: WallpaperLayout.spanned
            onActivated: {
                if (WallpaperLayout.spanned)
                    WallpaperLayout.unspan();
                else
                    WallpaperLayout.spanFrom(root.screenName);
            }
        }

        EditOptionChips {
            Layout.topMargin: 8
            visible: !root.lockTab && WallpaperLayout.multiScreen && WallpaperLayout.available
                && WallpaperLayout.distinctWallpapers
            label: Translation.tr("Colours from")
            compact: false
            currentValue: WallpaperLayout.colourScreen
            options: WallpaperLayout.screenNames.map(name => ({
                "displayName": name === root.screenName
                    ? Translation.tr("%1 (this one)").arg(WallpaperLayout.displayName(name))
                    : WallpaperLayout.displayName(name),
                "icon": name === root.screenName ? "desktop_windows" : "monitor",
                "value": name,
                "enabled": !WallpaperLayout.hasOwn(name) || WallpaperLayout.canMakeColourSource(name)
            }))
            onSelected: value => {
                if (WallpaperLayout.hasOwn(value))
                    WallpaperLayout.makeColourSource(value);
            }
        }

        EditPanelNotice {
            Layout.leftMargin: 4
            Layout.rightMargin: 4
            visible: !root.lockTab && WallpaperLayout.multiScreen && WallpaperLayout.available
                && WallpaperLayout.distinctWallpapers
            symbol: WallpaperLayout.colourScreen === "" ? "warning" : "palette"
            text: WallpaperLayout.colourScreen === ""
                ? Translation.tr("No screen shows the wallpaper the colours come from. Choose a screen above to take them from its picture.")
                : WallpaperLayout.sharedIsVideo
                    ? Translation.tr("The colours follow the video wallpaper. Give it a picture to take them from another screen.")
                    : Translation.tr("The colours come from one picture. Choosing another screen makes its picture the shared one; nothing on screen changes.")
        }

        // ── Position & zoom ──────────────────────────────────────────────────
        EditPanelSectionLabel {
            text: Translation.tr("Position & zoom")
        }

        EditPanelNotice {
            Layout.leftMargin: 4
            Layout.rightMargin: 4
            visible: !root.framingAvailable
            symbol: root.lockTab ? "desktop_windows" : "movie"
            text: root.lockTab
                ? Translation.tr("Moving, zooming and turning the wallpaper happens on the Desktop tab, where the card becomes the picture.")
                : Translation.tr("A video or Wallpaper Engine scene is painting the desktop, so it cannot be moved or zoomed here.")
        }

        EditPanelRow {
            Layout.fillWidth: true
            visible: root.lockTab
            first: true
            last: true
            symbol: "desktop_windows"
            title: Translation.tr("Go to the Desktop tab")
            trailingKind: "chevron"
            onActivated: GlobalStates.editTab = EditModeLogic.desktopTab
        }

        EditPanelRow {
            Layout.fillWidth: true
            visible: root.framingAvailable
            first: true
            last: true
            symbol: "zoom_in"
            title: Translation.tr("Zoom")
            subtitle: Translation.tr("100% is the full picture; the lock screen zooms out to it")
            subtitleWrap: true
            trailingKind: "stepper"
            valueText: Math.round(root.framing.zoom * 100) + "%"
            stepDownEnabled: root.framing.zoom > WallpaperFraming.zoomMin + 0.0001
            stepUpEnabled: root.framing.zoom < WallpaperFraming.zoomMax - 0.0001
            // Snapped to the tens, so a run of steps lands on round numbers
            // whatever a pinch left behind.
            onStepDown: WallpaperLayout.setZoom(root.screenName, Math.ceil(root.framing.zoom * 10 - 1.0001) / 10)
            onStepUp: WallpaperLayout.setZoom(root.screenName, Math.floor(root.framing.zoom * 10 + 1.0001) / 10)
        }

        EditOptionChips {
            Layout.topMargin: 8
            visible: root.framingAvailable
            label: Translation.tr("Orientation")
            compact: false
            currentValue: root.framing.rotation
            options: [
                { "displayName": "0°", "value": 0 },
                { "displayName": "90°", "value": 90 },
                { "displayName": "180°", "value": 180 },
                { "displayName": "270°", "value": 270 }
            ]
            onSelected: value => {
                let turns = ((value - root.framing.rotation) / 90 + 4) % 4;
                // Three quarter turns one way are one the other way.
                if (turns === 3)
                    turns = -1;
                if (turns !== 0)
                    WallpaperLayout.rotate(root.screenName, turns);
            }
        }

        EditPanelRow {
            Layout.fillWidth: true
            Layout.topMargin: 8
            visible: root.framingAvailable
            first: true
            last: false
            symbol: "flip"
            title: Translation.tr("Mirror horizontally")
            trailingKind: "switch"
            switchChecked: root.framing.flipH
            onActivated: WallpaperLayout.flip(root.screenName, "horizontal")
        }

        EditPanelRow {
            Layout.fillWidth: true
            visible: root.framingAvailable
            first: false
            last: false
            symbol: "swap_vert"
            title: Translation.tr("Mirror vertically")
            trailingKind: "switch"
            switchChecked: root.framing.flipV
            onActivated: WallpaperLayout.flip(root.screenName, "vertical")
        }

        EditPanelRow {
            Layout.fillWidth: true
            visible: root.framingAvailable
            first: false
            last: false
            rowEnabled: Math.abs(root.framing.x) > 0.0005 || Math.abs(root.framing.y) > 0.0005
            symbol: "center_focus_strong"
            title: Translation.tr("Centre the picture")
            trailingKind: "none"
            onActivated: WallpaperLayout.centre(root.screenName)
        }

        EditPanelRow {
            Layout.fillWidth: true
            visible: root.framingAvailable
            first: false
            last: true
            rowEnabled: !root.framingIdentity
            symbol: "restart_alt"
            title: Translation.tr("Reset position, zoom and orientation")
            trailingKind: "none"
            onActivated: WallpaperLayout.resetFraming(root.screenName)
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

        // Parallax, video playback, Wallpaper Engine: pages of forms, and
        // Settings is where they belong.
        EditPanelRow {
            Layout.fillWidth: true
            Layout.topMargin: 10
            symbol: "settings"
            title: Translation.tr("Background settings")
            subtitle: Translation.tr("Leaves Edit Mode")
            trailingKind: "chevron"
            onActivated: GlobalStates.openSettingsFromEditMode("wallpaper")
        }

        Item {
            Layout.fillWidth: true
            implicitHeight: 8
        }
    }
}
