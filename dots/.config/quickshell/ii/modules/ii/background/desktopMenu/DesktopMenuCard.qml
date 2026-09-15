import QtQuick
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * The desktop's right-click menu: the ported end-4 style card with a wallpaper
 * carousel on top and a row list below, adapted to the shell's current
 * openDesktopMenu(origin, x, y, screenName) plumbing (see DesktopMenu.qml).
 *
 * Rows: Wallpaper & style (hover submenu), DropShelf, Edit layout, Widgets and
 * Settings. The bar and the dock ask for the same card, but desktop-only rows
 * are hidden there.
 */
Item {
    id: root

    signal dismissRequested()

    // "desktop", "bar" or "dock".
    property string origin: "desktop"
    readonly property bool onBar: root.origin === "bar"
    readonly property bool onDock: root.origin === "dock"

    readonly property real padding: 8
    implicitWidth: 348
    implicitHeight: column.implicitHeight
    width: implicitWidth
    height: implicitHeight
    clip: false

    // ── Wallpaper & style sub-menu placement ────────────────────────────────
    // The submenu floats beside the Wallpaper & style row: to the right of the
    // card, or flipped to its left when the card sits close to the right screen
    // edge. The clamp works purely in the card's own coordinates plus the
    // screen frame passed by the menu surface (see DesktopMenu.qml): the card
    // is a direct child of that full-screen surface, so the card's own x/y are
    // already screen coordinates and nothing here depends on root.window, whose
    // value is not reliably the menu surface in this shell. The submenu's
    // extent is walked from its own rendered geometry (see submenuDrawnHeight)
    // so the clamp survives whatever the engine reports for layout-bound sizes.
    readonly property real submenuWidth: 308

    // Screen frame, passed as live bindings by the owning menu surface.
    property real screenWidth: root.width + root.submenuWidth + 16
    property real screenHeight: root.implicitHeight

    property real submenuAnchorY: 0

    readonly property real submenuX: {
        const needed = root.x + root.width + 8 + root.submenuWidth
        const fitsRight = needed <= root.screenWidth - 8
        const x = fitsRight ? root.width + 8 : -root.submenuWidth - 8
        // When flipped and the card hugs the left edge, keep the submenu on screen.
        return Math.max(x, 8 - root.x)
    }

    property real submenuY: submenuAnchorY

    // Tallest drawn extent measured this open. The first rendered frame can be
    // shorter than the settled content, and during the loader's entry scale the
    // boxes are drawn at a fraction of their final size, so once a real
    // measurement arrives the clamp sticks to it rather than shrinking back.
    property real submenuMeasuredH: 0

    // The submenu's drawn height, taken from rendered scene geometry instead of
    // layout-reported sizes: every painted box is located in the item's own
    // space by mapping onto the item itself (no window involved) and the
    // tallest bottom wins. The loader item's own height, implicit height and
    // childrenRect can each read zero here while the content still draws at
    // full size; the boxes that actually render are what must fit on screen.
    function submenuDrawnHeight() {
        const item = submenuLoader.item
        if (!item) return 0
        let bottom = 0
        const walk = o => {
            if (!o || typeof o.mapToItem !== "function" || o.visible === false) return
            if (o !== item) {
                const p = o.mapToItem(item, 0, 0)
                const w = o.width
                const h = o.height
                if (w > 0 || h > 0)
                    bottom = Math.max(bottom, p.y + h)
            }
            const children = o.children
            if (children)
                for (let i = 0; i < children.length; i++)
                    walk(children[i])
        }
        walk(item)
        return bottom
    }

    // The height the clamp judges overflow against: whatever the item reports
    // through its own size properties and what the scene walk actually drew,
    // held to a monotone high-water mark while the submenu stays open.
    function submenuClampHeight() {
        const item = submenuLoader.item
        if (!item) return 0
        const reported = Math.max(item.height, item.implicitHeight, item.childrenRect.height)
        const h = Math.max(root.submenuDrawnHeight(), reported)
        if (h > root.submenuMeasuredH)
            root.submenuMeasuredH = h
        return root.submenuMeasuredH
    }

    // Re-anchor and re-clamp the submenu into the screen. Sampled (not bound)
    // because the reliable drawn height only arrives once the opened submenu
    // has rendered its first frame; a binding against an early zero would
    // compute no overflow and leave the submenu running off the bottom.
    function applySubmenuPosition() {
        const h = root.submenuClampHeight()
        if (h <= 0) {
            submenuY = root.submenuAnchorY
            return
        }
        const margin = 8
        // The card is a direct child of the full-screen menu surface, so its
        // own y *is* its position on screen (window coordinates == screen).
        const cardTop = root.y
        const overflow = cardTop + root.submenuAnchorY + h - (root.screenHeight - margin)
        submenuY = overflow <= 0
            ? root.submenuAnchorY
            : Math.max(root.submenuAnchorY - overflow, margin - cardTop)
    }

    function openSubmenuFor(rowItem) {
        root.submenuMeasuredH = 0
        submenuAnchorY = rowItem ? rowItem.mapToItem(root, 0, 0).y : 0
        submenuLoader.active = true
        submenuPositionTimer.restart()
        submenuCloseTimer.stop()
    }

    function onSubmenuSizeChanged() {
        root.applySubmenuPosition()
    }

    Timer {
        id: submenuPositionTimer
        interval: 16
        repeat: true
        onTriggered: {
            // `running` is set directly - the timer's own id is not in scope
            // from inside its own signal handler (QML ids resolve downward
            // only), so an id-based stop() here would be undefined. Sample for
            // as long as the submenu is open so late layout and dynamic content
            // (the Centered wallpaper toggle) re-clamp live.
            if (!submenuLoader.active)
                running = false
            else
                root.applySubmenuPosition()
        }
    }

    Timer {
        id: submenuCloseTimer
        interval: 250
        onTriggered: submenuLoader.active = false
    }

    // Clicks on the card's own padding must not reach the closer behind it.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
    }

    // No unified background behind the sections: the carousel block and the row
    // list each own a rounded surface of their own, so the desktop shows through
    // around them - the ported menu's look, and what this card was restored for.
    ColumnLayout {
        id: column
        anchors.fill: parent
        anchors.margins: root.padding
        spacing: 4

            // ── Wallpaper carousel ─────────────────────────────────────────────
            Rectangle {
                visible: !root.onBar && !root.onDock
                Layout.fillWidth: true
                implicitHeight: 160
                radius: Appearance.rounding.large
                color: Appearance.colors.colLayer0
                clip: true

                Carousel {
                    anchors.fill: parent
                    anchors.margins: 10
                    model: root.carouselModel
                    onWallpaperSelected: path => {
                        Wallpapers.select(path, Appearance.m3colors.darkmode)
                        root.dismissRequested()
                    }
                }
            }

            // ── Action rows ───────────────────────────────────────────────────
            GroupedList {
                Layout.fillWidth: true
                itemVerticalPadding: 12
                bgcolor: Appearance.colors.colLayer0
                // Shell-driven and matching the shell's card corners: the outer
                // corners of the list take the same very-large rounding as the
                // carousel block above them.
                bigRadius: Appearance.rounding.large

                RippleButton {
                    id: wallpaperRow
                    visible: !root.onBar && !root.onDock
                    Layout.fillWidth: true
                    implicitHeight: 40
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colLayer2
                    contentItem: RowLayout {
                        anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                        spacing: 12
                        MaterialSymbol { text: "format_paint"; iconSize: Appearance.font.pixelSize.larger; color: Appearance.colors.colOnLayer1 }
                        StyledText { Layout.fillWidth: true; text: Translation.tr("Wallpaper & style"); font.pixelSize: Appearance.font.pixelSize.normal; color: Appearance.colors.colOnLayer1 }
                        MaterialSymbol { text: "chevron_right"; iconSize: Appearance.font.pixelSize.normal; color: Appearance.colors.colOnLayer1; opacity: 0.4 }
                    }
                    HoverHandler {
                        onHoveredChanged: {
                            if (hovered)
                                root.openSubmenuFor(wallpaperRow)
                            else
                                submenuCloseTimer.restart()
                        }
                    }
                    onClicked: root.dismissRequested()
                }

                RippleButton {
                    id: dropShelfRow
                    visible: !root.onBar && !root.onDock
                    Layout.fillWidth: true
                    implicitHeight: 40
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colLayer2
                    contentItem: RowLayout {
                        anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                        spacing: 12
                        MaterialSymbol { text: "stacks"; iconSize: Appearance.font.pixelSize.larger; color: Appearance.colors.colOnLayer1 }
                        StyledText { Layout.fillWidth: true; text: Translation.tr("DropShelf"); font.pixelSize: Appearance.font.pixelSize.normal; color: Appearance.colors.colOnLayer1 }
                        StyledText {
                            visible: DropShelf.items.length > 0
                            text: `${DropShelf.items.length}`
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnLayer1
                            opacity: 0.6
                        }
                    }
                    onClicked: {
                        // Spawn the shelf next to this row (where the click landed)
                        // instead of at the menu's open point, which is far above
                        // it. The row's center in card space plus the card's own
                        // position is its spot on screen (the card is a direct
                        // child of the full-screen menu surface).
                        const pt = dropShelfRow.mapToItem(root, dropShelfRow.width / 2, dropShelfRow.height / 2)
                        GlobalStates.dropShelfX = root.x + pt.x
                        GlobalStates.dropShelfY = root.y + pt.y
                        root.dismissRequested()
                        GlobalStates.dropShelfOpen = true
                    }
                }

                // Edit layout: taken from the shell's original menu, kept in the
                // ported card. On the dock the mode opens on the dock's own page.
                RippleButton {
                    Layout.fillWidth: true
                    implicitHeight: 40
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colLayer2
                    contentItem: RowLayout {
                        anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                        spacing: 12
                        MaterialSymbol {
                            text: GlobalStates.editMode ? "done" : (root.onDock ? (PanelFamily.touchFirst ? "dock_to_bottom" : "dock") : "edit")
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colOnLayer1
                            fill: GlobalStates.editMode ? 1 : 0
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: GlobalStates.editMode ? Translation.tr("Done editing")
                                : root.onDock ? (PanelFamily.touchFirst ? Translation.tr("Edit taskbar") : Translation.tr("Edit dock"))
                                : Translation.tr("Edit layout")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnLayer1
                        }
                    }
                    onClicked: {
                        root.dismissRequested()
                        if (GlobalStates.editMode) {
                            GlobalStates.closeEditMode()
                            return
                        }
                        if (root.onDock) {
                            GlobalStates.openEditCatalogue("dock", GlobalStates.desktopMenuScreenName, "appearance")
                            return
                        }
                        GlobalStates.openEditMode(GlobalStates.desktopMenuScreenName)
                    }
                }

                RippleButton {
                    visible: !root.onDock
                    Layout.fillWidth: true
                    implicitHeight: 40
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colLayer2
                    contentItem: RowLayout {
                        anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                        spacing: 12
                        MaterialSymbol { text: "widgets"; iconSize: Appearance.font.pixelSize.larger; color: Appearance.colors.colOnLayer1 }
                        StyledText {
                            Layout.fillWidth: true
                            text: root.onBar ? Translation.tr("Bar widgets") : Translation.tr("Widgets")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnLayer1
                        }
                        MaterialSymbol { text: "chevron_right"; iconSize: Appearance.font.pixelSize.normal; color: Appearance.colors.colOnLayer1; opacity: 0.4 }
                    }
                    onClicked: {
                        root.dismissRequested()
                        const section = root.onBar ? "bar" : "widgets"
                        GlobalStates.openEditCatalogue(section, GlobalStates.desktopMenuScreenName)
                    }
                }

                RippleButton {
                    Layout.fillWidth: true
                    implicitHeight: 40
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colLayer2
                    contentItem: RowLayout {
                        anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                        spacing: 12
                        MaterialSymbol { text: "settings"; iconSize: Appearance.font.pixelSize.larger; color: Appearance.colors.colOnLayer1 }
                        StyledText { Layout.fillWidth: true; text: Translation.tr("Settings"); font.pixelSize: Appearance.font.pixelSize.normal; color: Appearance.colors.colOnLayer1 }
                        MaterialSymbol { text: "chevron_right"; iconSize: Appearance.font.pixelSize.normal; color: Appearance.colors.colOnLayer1; opacity: 0.4 }
                    }
                    onClicked: {
                        root.dismissRequested()
                        GlobalStates.openSettings()
                    }
                }
            }
        }

    // ── Wallpaper & style sub-menu, floating beside the card ─────────────────
    Loader {
        id: submenuLoader
        active: false
        width: root.submenuWidth
        x: root.submenuX
        y: root.submenuY
        scale: active ? 1.0 : 0.9
        opacity: active ? 1.0 : 0.0
        transformOrigin: Item.Center

        Behavior on scale {
            enabled: !Appearance.reducedMotion
            animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(submenuLoader)
        }
        Behavior on opacity {
            enabled: !Appearance.reducedMotion
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(submenuLoader)
        }

        // No backing card: the submenu floats as its own rounded sections, as
        // in the ported menu. Size it to its content so item.height (which the
        // placement above clamps against) matches what is actually drawn.
        sourceComponent: WallpaperSubmenu {
            width: root.submenuWidth
            height: implicitHeight
        }

        onItemChanged: {
            if (submenuLoader.item)
                submenuLoader.item.childrenRectChanged.connect(root.onSubmenuSizeChanged)
            submenuPositionTimer.restart()
        }
        onActiveChanged: {
            if (active)
                submenuPositionTimer.restart()
        }

        HoverHandler {
            onHoveredChanged: {
                if (hovered) submenuCloseTimer.stop()
                else if (wallpaperRow.hovered) submenuCloseTimer.stop()
                else submenuCloseTimer.restart()
            }
        }
    }

    // ── Wallpaper folder images for the carousel strip ───────────────────────
    FolderListModel {
        id: wallpaperFolder
        folder: {
            const wallPath = Config.options.background.wallpaperPath
            if (!wallPath || wallPath.length === 0) return ""
            const lastSlash = wallPath.lastIndexOf("/")
            return "file://" + wallPath.substring(0, lastSlash)
        }
        showDirs: false
        nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp"]
    }

    property int carouselExtraCount: 5
    property var randomWallpapers: {
        const current = FileUtils.trimFileProtocol(Config.options.background.wallpaperPath)
        let all = []
        for (let i = 0; i < wallpaperFolder.count; i++) {
            const fp = FileUtils.trimFileProtocol(wallpaperFolder.get(i, "filePath").toString())
            if (fp !== current) all.push(fp)
        }
        for (let i = all.length - 1; i > 0; i--) {
            const j = Math.floor(Math.random() * (i + 1))
            ;[all[i], all[j]] = [all[j], all[i]]
        }
        return all.slice(0, carouselExtraCount)
    }

    property var carouselModel: {
        const current = FileUtils.trimFileProtocol(Config.options.background.wallpaperPath)
        if (!current || current.length === 0)
            return randomWallpapers.map(p => root.displayPathFor(p))
        return [root.displayPathFor(current), ...randomWallpapers.map(p => root.displayPathFor(p))]
    }

    function displayPathFor(path) {
        if (!path) return path
        return /\.(mp4|webm|mkv|avi|mov)$/i.test(path)
            ? Config.options.background.thumbnailPath
            : path
    }
}