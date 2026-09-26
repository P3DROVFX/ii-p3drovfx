import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.editMode
import qs.modules.ii.background.shortcuts

/**
 * The desktop's right-click menu: what the desktop offers when a click lands
 * on no widget - the wallpaper picker, the catalogue for whatever was
 * clicked, the layout editor, the desktop's file operations and Settings.
 *
 * The bar and the dock ask for the same menu. Where the click landed decides
 * the rows: a bar is not a place to pick a wallpaper from, the bar's
 * catalogue row opens the bar's widgets instead of the desktop's, and the
 * dock keeps only its own way into the mode - its page in the catalogue -
 * because the dock's icons already carry their own menu.
 *
 * Drawn as Edit Mode's widget menu is (EditWidgetMenu), minus its title: one
 * grouped run of EditPanelRow pills on the same card, so the two menus the
 * desktop can open read as the same kind of object. The rows are data
 * (`rows`), filtered by origin before they are drawn, so `first`/`last` are
 * the row's place among the VISIBLE ones.
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

    readonly property int padding: 8
    implicitWidth: 268
    implicitHeight: card.implicitHeight
    width: implicitWidth
    height: implicitHeight

    // ── Enter and exit ───────────────────────────────────────────────────────
    // Edit Mode's widget menu motion, so both menus the desktop opens move
    // alike: the whole card grows out of the corner under the pointer
    // (0.85 -> 1, elementMoveEnter) while it fades in on the faster
    // elementMoveFast clock, and leaves as one piece on elementMoveExit. No
    // per-row cascade: running the rows out in reverse left the empty card
    // standing for most of the exit, which is the frame the compositor then
    // faded as a ghost after the unmap.
    //
    // Two scalars, both driven by explicit animations rather than Behaviors:
    // the exit must say when it is DONE, and a re-open mid-exit has to turn
    // around from wherever the card is.
    property real grow: 0
    property real reveal: 0
    readonly property bool _motion: !Appearance.reducedMotion

    ParallelAnimation {
        id: enterMotion
        NumberAnimation {
            target: root
            property: "grow"
            to: 1
            duration: root._motion ? Appearance.animation.elementMoveEnter.duration : 0
            easing.type: Appearance.animation.elementMoveEnter.type
            easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
        }
        NumberAnimation {
            target: root
            property: "reveal"
            to: 1
            duration: root._motion ? Appearance.animation.elementMoveFast.duration : 0
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
    }
    ParallelAnimation {
        id: exitMotion
        NumberAnimation {
            target: root
            property: "grow"
            to: 0.5
            duration: root._motion ? Appearance.animation.elementMoveExit.duration : 0
            easing.type: Appearance.animation.elementMoveExit.type
            easing.bezierCurve: Appearance.animation.elementMoveExit.bezierCurve
        }
        NumberAnimation {
            target: root
            property: "reveal"
            to: 0
            duration: root._motion ? Appearance.animation.elementMoveExit.duration : 0
            easing.type: Appearance.animation.elementMoveExit.type
            easing.bezierCurve: Appearance.animation.elementMoveExit.bezierCurve
        }
        // One more frame before the unmap, so the surface's last committed
        // buffer is the transparent one and never a half-faded card.
        onFinished: unmapDelay.restart()
    }
    Timer {
        id: unmapDelay
        interval: 32
        onTriggered: { if (root.closing) root.exitFinished(); }
    }

    function playEnter(fromStart: bool): void {
        exitMotion.stop();
        unmapDelay.stop();
        if (fromStart) {
            root.grow = 0;
            root.reveal = 0;
        }
        enterMotion.restart();
    }
    function playExit(): void {
        enterMotion.stop();
        exitMotion.restart();
    }

    // The exit is a reaction: `closing` flips while the surface is up. The
    // enter is an event — beginEnter — because the host window is built once
    // and then shown per open (DesktopMenu keeps it alive), so completion
    // only describes the first one. Re-opened mid-exit, the card turns around
    // from where it is instead of snapping back to the start.
    onClosingChanged: {
        if (root.closing)
            root.playExit();
        else if (root.reveal > 0)
            root.playEnter(false);
    }
    Component.onCompleted: {
        root.playEnter(true);
        probePaste();
        wallpaperStrip.reset();
    }
    function beginEnter() {
        // reveal is back at 0 after the exit, so the page Behavior is off
        // and the card lands straight on the menu.
        root.page = "";
        root.loadedPages = {};
        root.playEnter(true);
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
        && DesktopShortcuts.itemsFor(GlobalStates.desktopMenuScreenName).length > 0

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

    opacity: root.reveal
    scale: 0.85 + 0.15 * root.grow
    transformOrigin: Item.TopLeft
    enabled: !root.closing

    // Clicks on the card's own padding must not reach the closer behind it.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
    }

    // ── The rows ─────────────────────────────────────────────────────────────
    // Every row the menu can carry, in order; `shown` is the origin rule.
    // The desktop's file operations sit after the edit rows and before
    // Settings: they all speak of THIS screen's icons, so bar and dock
    // origins drop them. From the dock, the mode opens on the dock's own
    // page: what was clicked is what gets edited.
    readonly property bool showRecents: PanelFamily.isIi && !root.onBar && !root.onDock
        && wallpaperStrip.count > 0

    readonly property var rows: [
        {
            "key": "style",
            "shown": !root.onBar,
            "symbol": "wallpaper",
            "title": Translation.tr("Wallpaper & style")
        },
        {
            "key": "colors",
            "shown": !root.onBar,
            "symbol": "palette",
            "title": Translation.tr("Colors & themes"),
            "trailing": "chevron"
        },
        {
            "key": "presets",
            "shown": !root.onBar && !root.onDock,
            "symbol": "style",
            "title": Translation.tr("Presets"),
            "trailing": "chevron"
        },
        {
            "key": "widgets",
            "shown": !root.onDock,
            "symbol": "widgets",
            "title": root.onBar ? Translation.tr("Bar widgets") : Translation.tr("Desktop widgets")
        },
        {
            "key": "apps",
            "shown": PanelFamily.touchFirst && !root.onBar && !root.onDock,
            "symbol": "apps",
            "title": Translation.tr("Home screen apps")
        },
        {
            "key": "edit",
            "shown": true,
            "symbol": GlobalStates.editMode ? "done" : (root.onDock ? (PanelFamily.touchFirst ? "dock_to_bottom" : "dock") : "edit"),
            "title": GlobalStates.editMode ? Translation.tr("Done editing")
                : root.onDock ? (PanelFamily.touchFirst ? Translation.tr("Edit taskbar") : Translation.tr("Edit dock"))
                : Translation.tr("Edit layout")
        },
        {
            "key": "paste",
            "shown": root.pasteAvailable,
            "symbol": "content_paste",
            "title": Translation.tr("Paste")
        },
        {
            "key": "icons",
            "shown": root.hasIcons,
            "symbol": "grid_view",
            "title": Translation.tr("Desktop icons"),
            "trailing": "chevron"
        },
        {
            "key": "settings",
            "shown": true,
            "symbol": "settings",
            "title": Translation.tr("Settings")
        }
    ].filter(row => row.shown)

    function activate(key: string): void {
        if (key === "paste") {
            root.pasteNow();
            return;
        }
        if (key === "colors" || key === "presets" || key === "icons") {
            root.openPage(key);
            return;
        }
        root.dismissRequested();
        const screenName = GlobalStates.desktopMenuScreenName;
        switch (key) {
        case "style":
            GlobalStates.openEditCatalogue("style", screenName);
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

    StyledRectangularShadow {
        target: card
    }

    // ── Pages ────────────────────────────────────────────────────────────────
    // "" is the menu itself; a row can open a page of its own inside the same
    // card ("colors"). Every open starts on the menu. The card's height
    // follows the page on show, animated only once the card has landed, so
    // an open never grows the card from the last page's size.
    property string page: ""
    // Pages built this open, by name: each is built on first use and kept
    // until the next open, so going back and forth never rebuilds one.
    property var loadedPages: ({})
    function openPage(name: string): void {
        if (!root.loadedPages[name]) {
            const next = Object.assign({}, root.loadedPages);
            next[name] = true;
            root.loadedPages = next;
        }
        root.shownPage = name;
        root.page = name;
    }
    // The page on the card's right: kept through the way back, so the page
    // being left still slides out instead of vanishing.
    property string shownPage: ""
    function back(): void {
        root.page = "";
    }
    readonly property Item currentPage: root.page === "colors" && colorsLoader.item ? colorsLoader.item
        : root.page === "presets" && presetsLoader.item ? presetsLoader.item
        : root.page === "icons" && iconsLoader.item ? iconsLoader.item
        : column

    // The page change: 0 on the menu, 1 on a page. The menu slides out to
    // the left as the page comes in from the right, both fading, and the
    // page's own elements arrive a step apart (DesktopMenuColorsPage.reveal).
    readonly property real pageSlide: 36
    property real pageProgress: root.page === "" ? 0 : 1
    Behavior on pageProgress {
        enabled: !Appearance.reducedMotion && root.reveal >= 1
        animation: Appearance.animation.elementMove.numberAnimation.createObject(root)
    }

    Rectangle {
        id: card
        anchors.left: parent.left
        anchors.right: parent.right
        implicitHeight: root.currentPage.implicitHeight + root.padding * 2
        radius: Appearance.rounding.windowRounding
        color: Appearance.m3colors.m3surfaceContainer
        clip: true

        Behavior on implicitHeight {
            enabled: !Appearance.reducedMotion && root.reveal >= 1 && !root.closing
            animation: Appearance.animation.elementMove.numberAnimation.createObject(card)
        }

        ColumnLayout {
            id: column
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: root.padding
            spacing: 3
            opacity: Math.max(0, 1 - root.pageProgress * 1.6)
            visible: opacity > 0
            enabled: root.page === ""
            transform: Translate { x: -root.pageProgress * root.pageSlide }

            // The recent wallpapers, on top: the desktop's one visual choice
            // one wheel away. Only where the wallpaper row itself shows.
            DesktopMenuWallpaperStrip {
                id: wallpaperStrip
                Layout.fillWidth: true
                Layout.bottomMargin: 3
                visible: root.showRecents
            }

            Repeater {
                model: root.rows

                delegate: EditPanelRow {
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    hostRadius: Appearance.rounding.windowRounding
                    hostPadding: root.padding
                    first: index === 0
                    last: index === root.rows.length - 1
                    symbol: modelData.symbol
                    title: modelData.title
                    trailingKind: modelData.trailing ?? "none"
                    switchChecked: modelData.checked ?? false
                    onActivated: root.activate(modelData.key)
                }
            }
        }

        // Built on first use and kept for the rest of this open: the swatch
        // grid is the heavy part, and going back and forth should not
        // rebuild it. The next open drops it (beginEnter).
        Loader {
            id: colorsLoader
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: root.padding
            active: root.loadedPages["colors"] === true
            visible: root.pageProgress > 0 && root.shownPage === "colors"
            enabled: root.page === "colors"
            transform: Translate { x: (1 - root.pageProgress) * root.pageSlide }

            sourceComponent: DesktopMenuColorsPage {
                reveal: root.pageProgress
                onBackRequested: root.back()
            }
        }

        Loader {
            id: presetsLoader
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: root.padding
            active: root.loadedPages["presets"] === true
            visible: root.pageProgress > 0 && root.shownPage === "presets"
            enabled: root.page === "presets"
            transform: Translate { x: (1 - root.pageProgress) * root.pageSlide }

            sourceComponent: DesktopMenuPresetsPage {
                reveal: root.pageProgress
                onBackRequested: root.back()
                onDismissRequested: root.dismissRequested()
            }
        }

        Loader {
            id: iconsLoader
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: root.padding
            active: root.loadedPages["icons"] === true
            visible: root.pageProgress > 0 && root.shownPage === "icons"
            enabled: root.page === "icons"
            transform: Translate { x: (1 - root.pageProgress) * root.pageSlide }

            sourceComponent: DesktopMenuIconsPage {
                screenName: GlobalStates.desktopMenuScreenName
                reveal: root.pageProgress
                onBackRequested: root.back()
                onDismissRequested: root.dismissRequested()
            }
        }
    }
}
