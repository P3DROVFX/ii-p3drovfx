pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.SystemTray
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.bar.widgets.tray

/**
 * The system tray, expanded inside the auxiliary bubble's card.
 *
 * Every program the bar's tray would show — pinned first, then the rest — lined up in
 * a grid of cells, five a row, each program inside its own chip. The card asks for the
 * width the grid needs, so the side margins are the same fourteen pixels as the top
 * and bottom ones whatever the count; the chip's radius is the card's own radius minus
 * that margin, so the two corners stay concentric.
 *
 * What each program *does* is not reimplemented here: the cells host the bar's own
 * `SysTrayItem`, so a left click activates, a right click opens the item's menu, a
 * drag pins or unpins, and the tooltip, the monochrome option and the icon-shape mask
 * all behave exactly as they do in the bar. The item's own hover pill is switched off
 * — the chip is the single surface under the pointer, coloured from the item's hover
 * state.
 *
 * The chips arrive in a cascade — left to right, top to bottom, each a step behind the
 * one before it — and leave in the mirror of it, driven by `cardExpanded`, which the
 * bubble keeps bound while the Loader is still alive fading out. The stagger is a
 * `PauseAnimation` inside a per-cell `SequentialAnimation`: an animation has no
 * `delay` property, and assigning one throws on the first cell and leaves the card
 * empty. The animations are one-shot and imperative: nothing loops while the card
 * sits open.
 *
 * The menus that item opens are their own windows, so two things the bar does around
 * them are done here too: a focus grab that folds a menu when the click lands
 * elsewhere, and `holdsOpen`, which the bubble reads to keep the card standing while a
 * menu is alive — the pointer is on the menu, and a card folding under it would take
 * its anchor down with it.
 *
 * Like every expanded face: the face declares its own box from its content and never
 * from the card it is given; the descriptor in IslandRegistry is the fallback.
 */
Item {
    id: root

    // ── Content ──────────────────────────────────────────────────────────────
    readonly property var items: TrayService.pinnedItems.concat(TrayService.unpinnedItems)

    // ── Geometry: declared, so the box answers to the count and not to the card ──
    readonly property real cellSize: 44
    readonly property real gridSpacing: 8
    readonly property real margin: 14
    readonly property int maxColumns: 5
    readonly property int columns: Math.min(maxColumns, Math.max(1, items.length))
    readonly property int rows: Math.ceil(items.length / columns)

    readonly property real preferredExpandedWidth: 2 * margin + columns * cellSize
        + (columns - 1) * gridSpacing
    readonly property real preferredExpandedHeight: 2 * margin + rows * cellSize
        + (rows - 1) * gridSpacing

    /** The card's own corner at this height, and the concentric chip inside it. */
    readonly property real cardRadius: Math.min(Appearance.rounding.large, preferredExpandedHeight / 2)
    readonly property real cellRadius: Math.max(8, cardRadius - margin)

    readonly property color cellIdle: Appearance.colors.colSurfaceContainerHigh
    readonly property color cellHover: Appearance.colors.colSurfaceContainerHighest
    readonly property color cellActive: ColorUtils.mix(cellIdle, Appearance.colors.colOnSurface, 0.14)

    // ── The cascade ──────────────────────────────────────────────────────────
    /** Driven by AuxiliaryBubble while this face is alive; see `playCascade`. */
    property bool cardExpanded: false
    readonly property int cascadeStaggerMs: 30
    readonly property int cascadeDurationMs: 180

    function playCascade(entering) {
        const count = cells.count;
        for (let i = 0; i < count; i++) {
            const cell = cells.itemAt(i);
            if (!cell)
                continue;
            // In: first cell first. Out: the mirror, so the card peels from its far end.
            const step = entering ? i : (count - 1 - i);
            cell.cascadeAnim.stop();
            cell.cascadePause.duration = step * root.cascadeStaggerMs;
            cell.cascadeMove.from = cell.reveal;
            cell.cascadeMove.to = entering ? 1 : 0;
            cell.cascadeAnim.start();
        }
    }

    onCardExpandedChanged: root.playCascade(root.cardExpanded)

    // The face is only loaded when the card is opening (or holding its fade), so a
    // cell arriving with the card already open — a program joining the tray — rides
    // straight in on the next turn, and never sits invisible in a closed card.
    Component.onCompleted: {
        if (root.cardExpanded)
            root.playCascade(true);
    }

    // ── Menu bookkeeping, as the bar's tray keeps it ─────────────────────────
    property var activeMenu: null
    /** Read by AuxiliaryBubble: a live menu holds the card open. */
    readonly property bool holdsOpen: root.activeMenu !== null

    function closeActiveMenu() {
        if (!root.activeMenu)
            return;
        if (typeof root.activeMenu.close === "function")
            root.activeMenu.close();
        root.activeMenu = null;
    }

    function setMenuOpen(window) {
        if (root.activeMenu && root.activeMenu !== window)
            root.closeActiveMenu();
        root.activeMenu = window;
        focusGrab.wanted = true;
    }

    HyprlandFocusGrab {
        id: focusGrab
        property bool wanted: false

        // One window at a time; the grab answers "did the click land outside it?".
        active: wanted && root.activeMenu !== null
        windows: [root.activeMenu]
        onCleared: root.closeActiveMenu()
    }

    Component.onDestruction: root.closeActiveMenu()

    GridLayout {
        id: grid
        anchors.centerIn: parent
        columns: root.columns
        columnSpacing: root.gridSpacing
        rowSpacing: root.gridSpacing

        Repeater {
            id: cells
            model: ScriptModel {
                values: root.items
            }

            delegate: Rectangle {
                id: cell
                required property SystemTrayItem modelData

                /** 0 = folded away, 1 = in place; the cascade animates this alone. */
                property real reveal: 0

                // An Animation has no `delay`: the stagger lives in a PauseAnimation
                // ahead of the move inside one SequentialAnimation per cell.
                property PauseAnimation cascadePause: PauseAnimation {}
                property NumberAnimation cascadeMove: NumberAnimation {
                    target: cell
                    property: "reveal"
                    duration: root.cascadeDurationMs
                    easing.type: Easing.OutCubic
                }
                property SequentialAnimation cascadeAnim: SequentialAnimation {
                    animations: [cell.cascadePause, cell.cascadeMove]
                }

                Layout.preferredWidth: root.cellSize
                Layout.preferredHeight: root.cellSize
                radius: root.cellRadius
                color: trayItem.pressed ? root.cellActive
                    : (trayItem.containsMouse ? root.cellHover : root.cellIdle)
                opacity: cell.reveal
                scale: 0.7 + 0.3 * cell.reveal

                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }

                Component.onCompleted: {
                    if (root.cardExpanded)
                        cell.reveal = 1;
                }

                SysTrayItem {
                    id: trayItem
                    anchors.fill: parent
                    anchors.margins: 10
                    item: cell.modelData
                    hoverBackground: false
                    onMenuOpened: qsWindow => root.setMenuOpen(qsWindow)
                    onMenuClosed: root.activeMenu = null
                }
            }
        }
    }
}
