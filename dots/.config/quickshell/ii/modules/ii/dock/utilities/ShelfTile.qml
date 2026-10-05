import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.clock.components
import "UtilityFiles.js" as UtilityFiles

/**
 * Shelf: a place to leave files halfway through a drag and pick them up
 * later. Drop files on it; drag the widget off the dock to hand them all over,
 * or take them one by one from the panel. Square: empty, the shelf glyph on a
 * square that morphs into a burst while files hover over it; holding files,
 * the newest one as a card on a short deck, with the count. Wide: the deck,
 * the newest name, the count, and clear.
 */
UtilityTile {
    id: tile

    readonly property var items: Persistent.ready ? Array.from(Persistent.states.dockUtilities.shelf ?? []) : []
    readonly property int count: tile.items.length
    readonly property string newest: tile.count > 0 ? tile.items[tile.count - 1] : ""

    function dropFiles(urls) {
        Persistent.states.dockUtilities.shelf = UtilityFiles.dedupe(tile.items.concat(urls));
    }
    function remove(path) {
        Persistent.states.dockUtilities.shelf = tile.items.filter(item => item !== path);
    }
    function clear() {
        Persistent.states.dockUtilities.shelf = [];
    }
    function exportPaths() {
        return tile.items;
    }

    surfaceColor: tile.dropHovering ? ClockStyle.colPrimaryContainer : ClockStyle.colSurfaceHigh
    contentColor: tile.dropHovering ? ClockStyle.colOnPrimaryContainer : ClockStyle.colOnSurface

    tooltipText: tile.count === 0 ? Translation.tr("Shelf · drop files here")
        : tile.count === 1 ? Translation.tr("Shelf · 1 item · drag off the dock to use it")
        : Translation.tr("Shelf · %1 items · drag off the dock to use them").arg(tile.count)
    panelSubtitle: tile.count === 1 ? Translation.tr("1 item") : Translation.tr("%1 items").arg(tile.count)
    panelWidth: 380
    menuActions: [
        { id: "clear", icon: "clear_all", text: Translation.tr("Clear shelf"), visible: tile.count > 0 }
    ]
    function menuAction(actionId) {
        if (actionId === "clear")
            tile.clear();
    }

    // The newest file as a card, with up to two plain cards behind it.
    component Deck: Item {
        id: deck
        readonly property real card: Math.round(Math.min(deck.width, deck.height) * 0.78)
        readonly property real step: Math.max(2, Math.round(deck.card * 0.1))
        Repeater {
            model: Math.min(2, tile.count - 1)
            delegate: Rectangle {
                required property int index
                readonly property int depth: index + 1
                z: -depth
                width: deck.card
                height: deck.card
                x: (deck.width - deck.card) / 2 + deck.step * depth
                y: (deck.height - deck.card) / 2 - deck.step * depth
                radius: Math.round(deck.card * 0.24)
                color: ColorUtils.applyAlpha(Appearance.colors.colSecondary, 0.35 - depth * 0.12)
            }
        }
        FileThumb {
            width: deck.card
            height: deck.card
            x: (deck.width - deck.card) / 2
            y: (deck.height - deck.card) / 2
            path: tile.newest
            radius: Math.round(deck.card * 0.24)
            renderScale: tile.renderScale
            colPlate: ClockStyle.colSecondaryContainer
            colSymbol: ClockStyle.colOnSecondaryContainer
        }
    }

    component EmptyBadge: TileBadge {
        renderScale: tile.renderScale
        // The drop target swells into a burst while files hover over it.
        shape: tile.dropHovering ? MaterialShape.Shape.SoftBurst : MaterialShape.Shape.Square
        color: tile.dropHovering ? ClockStyle.colPrimary : ClockStyle.colSecondaryContainer
        colSymbol: tile.dropHovering ? ClockStyle.colOnPrimary : ClockStyle.colOnSecondaryContainer
        text: tile.dropHovering ? "file_download" : "shelves"
        iconScale: 0.5
    }

    // ── Square ──────────────────────────────────────────────────────────
    Item {
        anchors.fill: parent
        visible: !tile.wide

        EmptyBadge {
            anchors.centerIn: parent
            visible: tile.count === 0 || tile.dropHovering
            width: Math.round(tile.side * 0.7)
            height: width
        }
        Deck {
            anchors.fill: parent
            anchors.margins: Math.round(tile.side * 0.06)
            visible: tile.count > 0 && !tile.dropHovering
        }
        Rectangle {
            visible: tile.count > 1 && !tile.dropHovering
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: Math.round(tile.side * 0.06)
            width: Math.max(height, countText.implicitWidth + Math.round(height * 0.5))
            height: Math.round(tile.side * 0.32)
            radius: height / 2
            color: ClockStyle.colPrimary
            TileValue {
                id: countText
                anchors.centerIn: parent
                text: String(tile.count)
                color: ClockStyle.colOnPrimary
                font.pixelSize: Math.round(parent.height * 0.72)
            }
        }
    }

    // ── Wide ────────────────────────────────────────────────────────────
    RowLayout {
        anchors.fill: parent
        anchors.margins: tile.pad
        anchors.rightMargin: tile.pad * (tile.count > 0 ? 1 : 2)
        visible: tile.wide
        spacing: tile.pad

        Item {
            implicitWidth: tile.badgeSize
            implicitHeight: tile.badgeSize
            EmptyBadge {
                anchors.fill: parent
                visible: tile.count === 0 || tile.dropHovering
            }
            Deck {
                anchors.fill: parent
                visible: tile.count > 0 && !tile.dropHovering
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 0
            TileText {
                Layout.fillWidth: true
                text: tile.dropHovering ? Translation.tr("Drop to keep")
                    : tile.count === 0 ? Translation.tr("Shelf") : UtilityFiles.baseName(tile.newest)
                color: tile.contentColor
                font.pixelSize: Math.round(tile.height * 0.27)
                font.weight: Font.DemiBold
                elide: Text.ElideMiddle
            }
            TileCaption {
                Layout.fillWidth: true
                text: tile.count === 0 ? Translation.tr("Drop files here")
                    : tile.count === 1 ? Translation.tr("1 item") : Translation.tr("%1 items").arg(tile.count)
                color: tile.captionColor
                font.pixelSize: tile.captionSize
            }
        }

        TileButton {
            visible: tile.count > 0 && !tile.dropHovering
            implicitWidth: Math.round(tile.badgeSize * 0.84)
            implicitHeight: implicitWidth
            symbol: "clear_all"
            tip: Translation.tr("Clear shelf")
            colContent: tile.contentColor
            onClicked: tile.clear()
        }
    }
}
