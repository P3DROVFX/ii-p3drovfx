import QtQuick
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * The wallpapers, as big as the page allows: the desktop image as the hero, and the
 * lock screen and light-mode variants beside it (below it on a narrow page). A variant
 * that is off is an empty card that turns it on — the two switches this replaced.
 */
Item {
    id: root

    readonly property int gap: 12
    readonly property bool wide: root.width >= 620
    readonly property int sideWidth: Math.round(Math.max(200, Math.min(320, root.width * 0.3)))
    readonly property int mainWidth: root.wide ? root.width - root.gap - root.sideWidth : root.width
    readonly property int mainHeight: Math.round(Math.max(220, Math.min(460, root.mainWidth / 1.7)))
    readonly property int variantHeight: root.wide ? Math.floor((root.mainHeight - root.gap) / 2) : 150

    readonly property var background: Config.options.background
    readonly property bool systemPicker: Config.options.wallpaperSelector.useSystemFileDialog

    implicitHeight: root.wide ? root.mainHeight : root.mainHeight + root.gap + root.variantHeight

    function openSelector(action: string) {
        Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "wallpaperSelector", action]);
    }

    function pickDesktop() {
        if (root.systemPicker)
            Wallpapers.openFallbackPicker(Appearance.m3colors.darkmode, false);
        else
            root.openSelector("toggle");
    }

    function pickLockscreen() {
        const wasSet = root.background.useSeparateLockscreenWallpaper;
        root.background.useSeparateLockscreenWallpaper = true;
        // Turning it back on shows the image it had; only an empty one needs the picker.
        if (wasSet || !root.background.lockscreenWallpaperPath) {
            if (root.systemPicker)
                Wallpapers.openFallbackPicker(Appearance.m3colors.darkmode, true);
            else
                root.openSelector("toggleLockscreen");
        }
    }

    function pickLightMode() {
        const wasSet = root.background.useSeparateLightModeWallpaper;
        root.background.useSeparateLightModeWallpaper = true;
        if (wasSet || !root.background.lightModeWallpaperPath)
            root.openSelector("toggleLightmode");
    }

    function swapLockscreen() {
        const desktopWall = root.background.wallpaperPath;
        const lockWall = root.background.lockscreenWallpaperPath;
        if (!desktopWall || !lockWall)
            return;
        root.background.wallpaperPath = lockWall;
        Wallpapers.applyLockscreen(desktopWall);
        Wallpapers.apply(lockWall);
    }

    function swapLightMode() {
        const darkWall = root.background.wallpaperPath;
        const lightWall = root.background.lightModeWallpaperPath;
        if (!darkWall || !lightWall)
            return;
        root.background.wallpaperPath = lightWall;
        root.background.lightModeWallpaperPath = darkWall;
        if (Appearance.m3colors.darkmode)
            Wallpapers.apply(darkWall, true);
        else
            Wallpapers.applyLightModeWallpaper(lightWall);
    }

    ColorsWallpaperCard {
        x: 0
        y: 0
        width: root.mainWidth
        height: root.mainHeight
        hero: true
        targetMode: "desktop"
        title: Translation.tr("Desktop")
        symbol: "desktop_windows"
        onPickRequested: root.pickDesktop()
    }

    ColorsWallpaperCard {
        x: root.wide ? root.mainWidth + root.gap : 0
        y: root.wide ? 0 : root.mainHeight + root.gap
        width: root.wide ? root.sideWidth : Math.floor((root.width - root.gap) / 2)
        height: root.variantHeight
        targetMode: "lockscreen"
        title: Translation.tr("Lock screen")
        symbol: "lock"
        isSet: root.background.useSeparateLockscreenWallpaper
        emptyHint: Translation.tr("Same as the desktop. Click to pick another")
        emptyShape: MaterialShape.Shape.Cookie7Sided
        emptyShapeHover: MaterialShape.Shape.Cookie12Sided
        swapTooltip: Translation.tr("Swap Desktop & Lockscreen")
        onPickRequested: root.pickLockscreen()
        onSwapRequested: root.swapLockscreen()
        onRemoveRequested: root.background.useSeparateLockscreenWallpaper = false
    }

    ColorsWallpaperCard {
        x: root.wide ? root.mainWidth + root.gap : Math.ceil((root.width + root.gap) / 2)
        y: root.wide ? root.variantHeight + root.gap : root.mainHeight + root.gap
        width: root.wide ? root.sideWidth : Math.floor((root.width - root.gap) / 2)
        height: root.wide ? root.mainHeight - root.variantHeight - root.gap : root.variantHeight
        targetMode: "lightmode"
        title: Translation.tr("Light mode")
        symbol: "light_mode"
        isSet: root.background.useSeparateLightModeWallpaper
        emptyHint: Translation.tr("Same as dark mode. Click to pick another")
        emptyShape: MaterialShape.Shape.Sunny
        emptyShapeHover: MaterialShape.Shape.VerySunny
        swapTooltip: Translation.tr("Swap Dark & Light")
        onPickRequested: root.pickLightMode()
        onSwapRequested: root.swapLightMode()
        onRemoveRequested: root.background.useSeparateLightModeWallpaper = false
    }
}
