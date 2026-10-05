import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.clock.components

/**
 * Favorites: the sites opened every day, one click each. Square: one site
 * fills the tile; two to four sit in a 2×2 grid, like a folder. Wide: as many
 * as fit in a row at the tile's full height. Each icon opens its site; the
 * rest of the tile opens the list. Empty, a bookmark on a clover.
 */
UtilityTile {
    id: tile

    readonly property var sites: Array.from(Config.options?.dock?.utilities?.favorites?.sites ?? [])
        .filter(site => site && String(site.url ?? "").length > 0)

    function open(site) {
        let url = String(site.url).trim();
        if (!/^[a-z][a-z0-9+.-]*:/i.test(url))
            url = "https://" + url;
        Qt.openUrlExternally(url);
    }

    surfaceColor: ClockStyle.colSurfaceHigh
    contentColor: ClockStyle.colOnSurface

    tooltipText: tile.sites.length === 0 ? Translation.tr("Favorites · add your sites in Settings")
        : Translation.tr("Favorites · %1 sites").arg(tile.sites.length)
    panelSubtitle: tile.sites.length === 1 ? Translation.tr("1 site") : Translation.tr("%1 sites").arg(tile.sites.length)

    component SiteButton: Item {
        id: button
        property var site
        property real cornerRadius: Math.round(width * 0.3)
        property real iconScale: 0.62
        SiteIcon {
            iconScale: button.iconScale
            anchors.fill: parent
            url: button.site?.url ?? ""
            title: button.site?.title ?? ""
            radius: button.cornerRadius
            renderScale: tile.renderScale
            scale: siteArea.pressed ? 0.95 : 1
            Behavior on scale {
                animation: ClockStyle.motionFast.numberAnimation.createObject(this)
            }
        }
        MouseArea {
            id: siteArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tile.open(button.site)
        }
        StyledToolTip {
            text: button.site?.title || button.site?.url || ""
            extraVisibleCondition: siteArea.containsMouse
        }
    }

    // ── Square ──────────────────────────────────────────────────────────
    Grid {
        id: squareGrid
        visible: !tile.wide && tile.sites.length > 0
        readonly property int shown: Math.min(4, tile.sites.length)
        readonly property real inset: Math.round(tile.side * 0.08)
        readonly property real cell: squareGrid.shown === 1
            ? Math.round(tile.side * 0.76)
            : Math.floor((tile.side - squareGrid.inset * 2 - squareGrid.spacing) / 2)
        anchors.centerIn: parent
        columns: squareGrid.shown === 1 ? 1 : 2
        spacing: Math.max(2, Math.round(tile.side * 0.05))
        Repeater {
            model: tile.sites.slice(0, 4)
            delegate: SiteButton {
                required property var modelData
                width: squareGrid.cell
                height: squareGrid.cell
                site: modelData
                // Small cells: the favicon nearly fills its plate.
                iconScale: squareGrid.shown === 1 ? 0.62 : 0.8
                cornerRadius: Math.round(squareGrid.cell * 0.28)
            }
        }
    }

    TileBadge {
        anchors.centerIn: parent
        visible: tile.sites.length === 0 && !tile.wide
        width: Math.round(tile.side * 0.74)
        height: width
        renderScale: tile.renderScale
        shape: MaterialShape.Shape.Clover4Leaf
        color: ClockStyle.colTertiaryContainer
        colSymbol: ClockStyle.colOnTertiaryContainer
        text: "bookmark_add"
    }

    // ── Wide ────────────────────────────────────────────────────────────
    // As many as fit, centred, so both ends keep the same margin.
    Row {
        id: wideRow
        visible: tile.wide && tile.sites.length > 0
        readonly property real cell: tile.badgeSize
        readonly property int fits: Math.max(1, Math.floor((tile.width - tile.pad * 2 + wideRow.spacing) / (wideRow.cell + wideRow.spacing)))
        anchors.centerIn: parent
        spacing: tile.pad
        Repeater {
            model: tile.sites.slice(0, wideRow.fits)
            delegate: SiteButton {
                required property var modelData
                width: wideRow.cell
                height: wideRow.cell
                site: modelData
                cornerRadius: Math.max(4, tile.radius - tile.pad)
            }
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: tile.pad
        visible: tile.wide && tile.sites.length === 0
        spacing: tile.pad
        TileBadge {
            implicitWidth: tile.badgeSize
            implicitHeight: tile.badgeSize
            renderScale: tile.renderScale
            shape: MaterialShape.Shape.Clover4Leaf
            color: ClockStyle.colTertiaryContainer
            colSymbol: ClockStyle.colOnTertiaryContainer
            text: "bookmark_add"
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            TileText {
                Layout.fillWidth: true
                text: Translation.tr("Favorites")
                color: tile.contentColor
                font.pixelSize: Math.round(tile.height * 0.27)
                font.weight: Font.DemiBold
            }
            TileCaption {
                Layout.fillWidth: true
                text: Translation.tr("Add in Settings")
                color: tile.captionColor
                font.pixelSize: tile.captionSize
            }
        }
    }
}
