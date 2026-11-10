import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.editMode
import qs.modules.ii.contextMenu
import qs.modules.ii.background.shortcuts

/**
 * The desktop's right-click menu: what the desktop offers when a click lands
 * on no widget - the wallpaper picker, the catalogue for whatever was
 * clicked, the layout editor, the desktop's file operations and Settings.
 *
 * The bar and the dock ask for the same menu. Where the click landed decides
 * which entries apply: a bar is not a place to pick a wallpaper from, the
 * bar's catalogue entry opens the bar's widgets instead of the desktop's,
 * and the dock keeps only its own way into the mode - its page in the
 * catalogue - because the dock's icons already carry their own menu.
 *
 * The entries that apply go through ContextMenus.arrange("desktop"), which
 * puts them in the user's order, drops the hidden ones, adds their own
 * command entries and - in the compact style - splits off the icon bar.
 * Comfortable draws the rows as Edit Mode's widget menu does, one grouped
 * run of EditPanelRow pills; compact as 34 px rows on a card as narrow as
 * they allow.
 *
 * A row with a page opens it inside the card (inline) or on a second card
 * beside it (cascade, ContextMenus.cascade).
 */
Item {
    id: root

    // The exit runs HERE, inside the live surface: GlobalStates only flags
    // `closing`, the card plays itself out and `exitFinished` lets the host
    // unmap the window. Same contract as ItemContextDialog's closeRequested.
    property bool closing: false
    signal exitFinished()

    signal dismissRequested()

    // "desktop", "bar" or "dock".
    property string origin: "desktop"
    readonly property bool onBar: root.origin === "bar"
    readonly property bool onDock: root.origin === "dock"

    // The surface the card sits on, for placing a cascaded page beside it.
    property real surfaceWidth: 0
    property real surfaceHeight: 0

    readonly property bool dense: ContextMenus.compact
    readonly property bool cascade: ContextMenus.cascade
    readonly property real padding: root.dense ? ContextMenus.compactPadding : ContextMenus.comfortablePadding

    // ── Width ────────────────────────────────────────────────────────────────
    // Comfortable keeps its fixed card. Compact fits the rows and the bar,
    // within ContextMenus' bounds; the wallpaper strip takes the full width.
    // An inline page with a grid on it widens the card while it shows.
    readonly property real naturalWidth: Math.max(list.implicitWidth, iconBar.implicitWidth) + root.padding * 2
    readonly property real menuWidth: !root.dense ? 268
        : root.showRecents ? ContextMenus.compactMaxWidth
        : Math.max(ContextMenus.compactMinWidth, Math.min(ContextMenus.compactMaxWidth, Math.ceil(root.naturalWidth)))
    function pageWidthFor(name: string): real {
        if (!root.dense)
            return 268;
        return name === "colors" || name === "presets"
            ? Math.max(root.menuWidth, ContextMenus.compactPageWidth) : root.menuWidth;
    }
    readonly property real cardWidth: root.cascade || root.page === "" ? root.menuWidth : root.pageWidthFor(root.page)

    implicitWidth: root.cardWidth
    implicitHeight: card.implicitHeight
    width: implicitWidth
    height: implicitHeight
    Behavior on implicitWidth {
        enabled: !Appearance.reducedMotion && motion.reveal >= 1 && !root.closing
        animation: Appearance.animation.elementMove.numberAnimation.createObject(root)
    }

    // ── Enter and exit ───────────────────────────────────────────────────────
    // ContextMenuMotion: the card grows out of the corner under the pointer
    // and leaves as one piece; the compact style runs the shorter version.
    // No per-row cascade: running the rows out in reverse left the empty
    // card standing for most of the exit, which is the frame the compositor
    // then faded as a ghost after the unmap.
    ContextMenuMotion {
        id: motion
        closing: root.closing
        onExitFinished: root.exitFinished()
    }

    Component.onCompleted: {
        motion.playEnter(true);
        probePaste();
        wallpaperStrip.reset();
    }
    // The enter is an event — beginEnter — because the host window is built
    // once and then shown per open (DesktopMenu keeps it alive), so
    // completion only describes the first one.
    function beginEnter() {
        // reveal is back at 0 after the exit, so the page Behavior is off
        // and the card lands straight on the menu.
        root.page = "";
        root.shownPage = "";
        root.loadedPages = {};
        motion.playEnter(true);
        probePaste();
        wallpaperStrip.reset();
    }

    // ── Desktop file operations ────────────────────────────────────────────
    // Paste: the desktop half of the item menu's Copy. When the clipboard
    // carries a file-URI list (a file manager's copy, or our own), the menu
    // offers to place those files as shortcuts on THIS screen. Probed on
    // open only — wl-paste lives milliseconds and a menu is a rare gesture;
    // never a timer, never a clipboard watcher. A payload over 4 KiB is not
    // a file list, it is someone's text: rejected without parsing.
    property var pasteUrls: []
    readonly property bool pasteAvailable: root.pasteUrls.length > 0
        && !root.onBar && !root.onDock
    readonly property bool hasIcons: PanelFamily.isIi && !root.onBar && !root.onDock

    Process {
        id: pasteProbe
        command: ["wl-paste", "-n"]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = text;
                if (t.length === 0 || t.length > 4096) {
                    root.pasteUrls = [];
                    return;
                }
                const lines = t.split("\n").map(s => s.trim()).filter(s => s.length > 0);
                const urls = lines.filter(s => s.startsWith("file://") || s.startsWith("/"));
                root.pasteUrls = lines.length > 0 && urls.length === lines.length ? urls : [];
            }
        }
        onExited: (exitCode) => { if (exitCode !== 0) root.pasteUrls = []; }
    }
    function probePaste() {
        if (root.origin !== "desktop" || !PanelFamily.isIi) {
            root.pasteUrls = [];
            return;
        }
        if (!pasteProbe.running)
            pasteProbe.running = true;
    }
    function pasteNow() {
        if (root.pasteUrls.length === 0)
            return;
        const screen = Quickshell.screens.find(s => s.name === GlobalStates.desktopMenuScreenName);
        DesktopShortcuts.importUrls(GlobalStates.desktopMenuScreenName, root.pasteUrls,
            GlobalStates.desktopMenuX, GlobalStates.desktopMenuY, "",
            screen?.width ?? 1920, screen?.height ?? 1080);
        root.pasteUrls = [];
        root.dismissRequested();
    }

    // The user's menu size on top of the motion; the host clamps by
    // `visualWidth`/`visualHeight`, the extent on screen.
    readonly property real zoom: ContextMenus.scale
    readonly property real visualWidth: root.width * root.zoom
    readonly property real visualHeight: root.height * root.zoom
    opacity: motion.reveal
    scale: motion.scale * root.zoom
    transformOrigin: Item.TopLeft
    enabled: !root.closing

    // Clicks on the card's own padding must not reach the closer behind it.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
    }

    // ── The entries ──────────────────────────────────────────────────────────
    // Every entry that applies from where the click landed; the user's
    // arrangement (ContextMenus) decides order, visibility and the bar. The
    // desktop's file operations speak of THIS screen's icons, so bar and
    // dock origins drop them. From the dock, the mode opens on the dock's
    // own page: what was clicked is what gets edited.
    readonly property bool showRecents: PanelFamily.isIi && !root.onBar && !root.onDock
        && wallpaperStrip.count > 0 && ContextMenus.isShown("desktop", "recents")

    readonly property var liveEntries: [
        {
            "id": "colors",
            "shown": !root.onBar,
            "symbol": "palette",
            "title": Translation.tr("Colors & themes"),
            "submenu": true
        },
        {
            "id": "presets",
            "shown": !root.onBar && !root.onDock,
            "symbol": "style",
            "title": Translation.tr("Presets"),
            "submenu": true
        },
        {
            "id": "style",
            "shown": !root.onBar,
            "symbol": "wallpaper",
            "title": Translation.tr("Wallpaper & style")
        },
        {
            "id": "widgets",
            "shown": !root.onDock,
            "symbol": "widgets",
            "title": root.onBar ? Translation.tr("Bar widgets") : Translation.tr("Desktop widgets")
        },
        {
            "id": "apps",
            "shown": PanelFamily.touchFirst && !root.onBar && !root.onDock,
            "symbol": "apps",
            "title": Translation.tr("Home screen apps")
        },
        {
            "id": "edit",
            "shown": true,
            "symbol": GlobalStates.editMode ? "done" : (root.onDock ? (PanelFamily.touchFirst ? "dock_to_bottom" : "dock") : "edit"),
            "title": GlobalStates.editMode ? Translation.tr("Done editing")
                : root.onDock ? (PanelFamily.touchFirst ? Translation.tr("Edit taskbar") : Translation.tr("Edit dock"))
                : Translation.tr("Edit layout")
        },
        {
            "id": "new",
            "shown": !root.onBar && !root.onDock,
            "symbol": "add",
            "title": Translation.tr("New"),
            "submenu": true
        },
        {
            "id": "paste",
            "shown": root.pasteAvailable,
            "symbol": "content_paste",
            "title": Translation.tr("Paste")
        },
        {
            "id": "icons",
            "shown": root.hasIcons,
            "symbol": DesktopShortcuts.hidden ? "visibility_off" : "grid_view",
            "title": Translation.tr("Desktop icons"),
            "submenu": true
        },
        {
            "id": "settings",
            "shown": true,
            "symbol": "settings",
            "title": Translation.tr("Settings")
        }
    ].filter(entry => entry.shown)

    readonly property var arranged: ContextMenus.arrange("desktop", root.liveEntries)

    function activate(entry: var, from: Item): void {
        if (entry.custom) {
            root.dismissRequested();
            ContextMenus.runCustom(entry, "");
            return;
        }
        const key = entry.id;
        if (key === "paste") {
            root.pasteNow();
            return;
        }
        if (key === "colors" || key === "presets" || key === "icons" || key === "new") {
            // A second click on the row whose page is already beside the
            // menu folds it away again.
            if (root.cascade && root.page === key)
                root.back();
            else
                root.openPage(key, from);
            return;
        }
        root.dismissRequested();
        const screenName = GlobalStates.desktopMenuScreenName;
        switch (key) {
        case "style":
            // The wallpaper has a catalogue of its own; Style is one tap
            // away from it.
            GlobalStates.openEditCatalogue("wallpaper", screenName);
            break;
        case "widgets":
            GlobalStates.openEditCatalogue(root.onBar ? "bar" : "widgets", screenName);
            break;
        case "apps":
            GlobalStates.openEditCatalogue("apps", screenName);
            break;
        case "edit":
            if (GlobalStates.editMode)
                GlobalStates.closeEditMode();
            else if (root.onDock)
                GlobalStates.openEditCatalogue("dock", screenName, "appearance");
            else
                GlobalStates.openEditMode(screenName);
            break;
        case "settings":
            GlobalStates.openSettingsFromEditMode("");
            break;
        }
    }

    // Cascade: resting on a row for a moment opens its page beside the menu,
    // or folds the open one away when the row has none - the way desktop
    // submenus follow the pointer. A click does the same at once.
    Timer {
        id: hoverIntent
        interval: 220
        property var entry: null
        property Item row: null
        onTriggered: {
            if (!root.cascade || root.closing || !hoverIntent.entry)
                return;
            if (hoverIntent.entry.submenu) {
                if (root.page !== hoverIntent.entry.id)
                    root.openPage(hoverIntent.entry.id, hoverIntent.row);
            } else if (root.page !== "") {
                root.back();
            }
        }
    }

    StyledRectangularShadow {
        target: card
    }

    // ── Pages ────────────────────────────────────────────────────────────────
    // "" is the menu itself; an entry can open a page of its own ("colors").
    // Every open starts on the menu. The card's height follows the page on
    // show, animated only once the card has landed, so an open never grows
    // the card from the last page's size.
    property string page: ""
    // Pages built this open, by name: each is built on first use and kept
    // until the next open, so going back and forth never rebuilds one.
    property var loadedPages: ({})
    // Where the row that opened the page sits, for the cascade card's top.
    property real anchorY: 0
    function openPage(name: string, from: Item): void {
        if (!root.loadedPages[name]) {
            const next = Object.assign({}, root.loadedPages);
            next[name] = true;
            root.loadedPages = next;
        }
        if (from)
            root.anchorY = from.mapToItem(root, 0, 0).y;
        root.shownPage = name;
        root.page = name;
    }
    // The page on show: kept through the way back, so the page being left
    // still slides (or fades) out instead of vanishing.
    property string shownPage: ""
    function back(): void {
        root.page = "";
    }
    function pageItem(name: string): Item {
        return name === "colors" ? colorsLoader.item
            : name === "presets" ? presetsLoader.item
            : name === "icons" ? iconsLoader.item
            : name === "new" ? newLoader.item
            : null;
    }
    readonly property Item currentPage: (!root.cascade && root.page !== "" && root.pageItem(root.page)) || column

    // The inline page change: 0 on the menu, 1 on a page. The menu slides
    // out to the left as the page comes in from the right, both fading, and
    // the page's own elements arrive a step apart (DesktopMenuColorsPage.reveal).
    // Compact moves half as far.
    readonly property real pageSlide: root.dense ? 16 : 36
    property real pageProgress: root.cascade || root.page === "" ? 0 : 1
    Behavior on pageProgress {
        enabled: !Appearance.reducedMotion && motion.reveal >= 1
        NumberAnimation {
            duration: root.dense ? Appearance.animation.elementMoveFast.duration : Appearance.animation.elementMove.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: root.dense ? Appearance.animation.elementMoveFast.bezierCurve : Appearance.animation.elementMove.bezierCurve
        }
    }
    // The cascade card's own arrival: 0 hidden, 1 settled beside the menu.
    property real sideProgress: root.cascade && root.page !== "" ? 1 : 0
    Behavior on sideProgress {
        enabled: !Appearance.reducedMotion && motion.reveal >= 1
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(root)
    }
    readonly property real pageReveal: root.cascade ? root.sideProgress : root.pageProgress

    Rectangle {
        id: card
        anchors.left: parent.left
        anchors.right: parent.right
        implicitHeight: root.currentPage.implicitHeight + root.padding * 2
        radius: Appearance.rounding.windowRounding
        color: Appearance.m3colors.m3surfaceContainer
        clip: true

        Behavior on implicitHeight {
            enabled: !Appearance.reducedMotion && motion.reveal >= 1 && !root.closing
            animation: Appearance.animation.elementMove.numberAnimation.createObject(card)
        }

        ColumnLayout {
            id: column
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: root.padding
            spacing: root.dense ? 4 : 3
            opacity: Math.max(0, 1 - root.pageProgress * 1.6)
            visible: opacity > 0
            enabled: root.cascade || root.page === ""
            transform: Translate { x: -root.pageProgress * root.pageSlide }

            // The recent wallpapers, on top: the desktop's one visual choice
            // one wheel away. Only where the wallpaper row itself shows.
            DesktopMenuWallpaperStrip {
                id: wallpaperStrip
                Layout.fillWidth: true
                Layout.bottomMargin: root.dense ? 0 : 3
                dense: root.dense
                visible: root.showRecents
            }

            ContextMenuIconBar {
                id: iconBar
                Layout.fillWidth: true
                entries: root.arranged.bar
                hostPadding: root.padding
                onActivated: (entry, button) => root.activate(entry, button)
            }

            ContextMenuList {
                id: list
                Layout.fillWidth: true
                visible: root.arranged.rows.length > 0
                rows: root.arranged.rows
                dense: root.dense
                // The comfortable menu has always been one run of pills.
                separators: root.dense
                hostPadding: root.padding
                openId: root.cascade ? root.page : ""
                onActivated: (entry, row) => {
                    hoverIntent.stop();
                    root.activate(entry, row);
                }
                onHovered: (entry, row) => {
                    if (!root.cascade)
                        return;
                    hoverIntent.entry = entry;
                    hoverIntent.row = row;
                    hoverIntent.restart();
                }
            }
        }
    }

    // ── The cascade card ─────────────────────────────────────────────────────
    // The page beside the menu, top level with the row that opened it, on
    // whichever side has room, held inside the surface.
    Item {
        id: side
        readonly property real gap: ContextMenus.cascadeGap
        readonly property Item content: root.cascade ? root.pageItem(root.shownPage) : null
        // In the card's own (unzoomed) units; the surface is in screen units.
        readonly property bool flip: root.surfaceWidth > 0
            && root.x + (root.width + side.gap + side.width) * root.zoom + 8 > root.surfaceWidth
        visible: root.cascade && root.sideProgress > 0 && side.content !== null
        width: root.pageWidthFor(root.shownPage)
        height: sideCard.implicitHeight
        x: side.flip ? -side.gap - side.width : root.width + side.gap
        y: {
            const want = root.anchorY - root.padding;
            if (root.surfaceHeight <= 0)
                return want;
            return Math.max((8 - root.y) / root.zoom,
                Math.min(want, (root.surfaceHeight - root.y - 8) / root.zoom - side.height));
        }
        opacity: root.sideProgress
        scale: 0.95 + 0.05 * root.sideProgress
        transformOrigin: side.flip ? Item.TopRight : Item.TopLeft

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            hoverEnabled: true
            // The pointer reaching the page keeps it open.
            onEntered: hoverIntent.stop()
        }

        StyledRectangularShadow {
            target: sideCard
        }

        Rectangle {
            id: sideCard
            anchors.left: parent.left
            anchors.right: parent.right
            implicitHeight: (side.content?.implicitHeight ?? 0) + root.padding * 2
            radius: Appearance.rounding.windowRounding
            color: Appearance.m3colors.m3surfaceContainer
            clip: true

            Behavior on implicitHeight {
                enabled: !Appearance.reducedMotion && root.sideProgress >= 1
                animation: Appearance.animation.elementMove.numberAnimation.createObject(sideCard)
            }
        }
    }

    // Built on first use and kept for the rest of this open: the swatch grid
    // is the heavy part, and going back and forth should not rebuild it. The
    // next open drops it (beginEnter). Inline, a page sits on the menu's own
    // card; cascaded, on the card beside it.
    Loader {
        id: colorsLoader
        parent: root.cascade ? sideCard : card
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: root.padding
        active: root.loadedPages["colors"] === true
        visible: root.shownPage === "colors" && (root.cascade ? root.sideProgress > 0 : root.pageProgress > 0)
        enabled: root.page === "colors"
        transform: Translate { x: root.cascade ? 0 : (1 - root.pageProgress) * root.pageSlide }

        sourceComponent: DesktopMenuColorsPage {
            reveal: root.pageReveal
            onBackRequested: root.back()
        }
    }

    Loader {
        id: presetsLoader
        parent: root.cascade ? sideCard : card
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: root.padding
        active: root.loadedPages["presets"] === true
        visible: root.shownPage === "presets" && (root.cascade ? root.sideProgress > 0 : root.pageProgress > 0)
        enabled: root.page === "presets"
        transform: Translate { x: root.cascade ? 0 : (1 - root.pageProgress) * root.pageSlide }

        sourceComponent: DesktopMenuPresetsPage {
            reveal: root.pageReveal
            onBackRequested: root.back()
            onDismissRequested: root.dismissRequested()
        }
    }

    Loader {
        id: iconsLoader
        parent: root.cascade ? sideCard : card
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: root.padding
        active: root.loadedPages["icons"] === true
        visible: root.shownPage === "icons" && (root.cascade ? root.sideProgress > 0 : root.pageProgress > 0)
        enabled: root.page === "icons"
        transform: Translate { x: root.cascade ? 0 : (1 - root.pageProgress) * root.pageSlide }

        sourceComponent: DesktopMenuIconsPage {
            screenName: GlobalStates.desktopMenuScreenName
            reveal: root.pageReveal
            onBackRequested: root.back()
            onDismissRequested: root.dismissRequested()
        }
    }

    Loader {
        id: newLoader
        parent: root.cascade ? sideCard : card
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: root.padding
        active: root.loadedPages["new"] === true
        visible: root.shownPage === "new" && (root.cascade ? root.sideProgress > 0 : root.pageProgress > 0)
        enabled: root.page === "new"
        transform: Translate { x: root.cascade ? 0 : (1 - root.pageProgress) * root.pageSlide }

        sourceComponent: DesktopMenuNewPage {
            screenName: GlobalStates.desktopMenuScreenName
            targetX: GlobalStates.desktopMenuX
            targetY: GlobalStates.desktopMenuY
            reveal: root.pageReveal
            onBackRequested: root.back()
            onDismissRequested: root.dismissRequested()
        }
    }
}
