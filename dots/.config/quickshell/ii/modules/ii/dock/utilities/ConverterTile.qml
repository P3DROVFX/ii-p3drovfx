import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.clock.components
import "UnitConverter.js" as Units

/**
 * Converter: length, weight, temperature, data — type on one side, read the
 * other. Typing happens in the panel (the dock takes no keyboard). Square: the
 * category's glyph on a slanted plate. Wide: the result in large digits with
 * its unit in primary, what it came from as the caption, and swap. The
 * category and the pair are remembered.
 */
UtilityTile {
    id: tile

    readonly property var cfg: Config.options?.dock?.utilities?.converter ?? null
    readonly property string categoryId: String(Units.category(tile.cfg?.category ?? "length")?.id ?? "length")
    readonly property var category: Units.category(tile.categoryId)
    readonly property string fromId: {
        const id = String(tile.cfg?.from ?? "");
        return Units.unit(tile.categoryId, id) ? id : String(Units.defaultPair(tile.categoryId).from);
    }
    readonly property string toId: {
        const id = String(tile.cfg?.to ?? "");
        return Units.unit(tile.categoryId, id) ? id : String(Units.defaultPair(tile.categoryId).to);
    }
    readonly property string fromLabel: String(Units.unit(tile.categoryId, tile.fromId)?.label ?? "")
    readonly property string toLabel: String(Units.unit(tile.categoryId, tile.toId)?.label ?? "")

    // The last value typed in the panel; lives as long as the dock does.
    property real input: 1
    readonly property real output: Units.convert(tile.input, tile.categoryId, tile.fromId, tile.toId)

    function setCategory(id) {
        const pair = Units.defaultPair(id);
        tile.cfg.category = id;
        tile.cfg.from = pair.from;
        tile.cfg.to = pair.to;
    }
    function setUnits(from, to) {
        tile.cfg.from = from;
        tile.cfg.to = to;
    }
    function swap() {
        const value = tile.output;
        tile.setUnits(tile.toId, tile.fromId);
        if (isFinite(value))
            tile.input = value;
    }

    surfaceColor: ClockStyle.colSurfaceHigh
    contentColor: ClockStyle.colOnSurface

    tooltipText: Translation.tr("Converter · %1 %2 = %3 %4").arg(Units.format(tile.input)).arg(tile.fromLabel)
        .arg(Units.format(tile.output)).arg(tile.toLabel)
    panelSubtitle: Translation.tr(tile.category.title)
    menuActions: Units.categories.filter(c => c.id !== tile.categoryId).map(c => ({
        id: "category:" + c.id, icon: c.symbol, text: Translation.tr(c.title)
    }))
    function menuAction(actionId) {
        if (actionId.indexOf("category:") === 0)
            tile.setCategory(actionId.slice(9));
    }

    // ── Square: the category on a slanted plate ────────────────────────
    TileBadge {
        anchors.centerIn: parent
        visible: !tile.wide
        width: Math.round(tile.side * 0.74)
        height: width
        renderScale: tile.renderScale
        shape: MaterialShape.Shape.Slanted
        color: ClockStyle.colTertiaryContainer
        colSymbol: ClockStyle.colOnTertiaryContainer
        text: tile.category.symbol
        iconScale: 0.5
    }

    // ── Wide: the result large, what it came from as the caption ────────
    RowLayout {
        anchors.fill: parent
        anchors.margins: tile.pad
        visible: tile.wide
        spacing: tile.pad

        TileBadge {
            implicitWidth: tile.badgeSize
            implicitHeight: tile.badgeSize
            renderScale: tile.renderScale
            shape: MaterialShape.Shape.Slanted
            color: ClockStyle.colTertiaryContainer
            colSymbol: ClockStyle.colOnTertiaryContainer
            text: tile.category.symbol
            iconScale: 0.5
        }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: -2
            RowLayout {
                Layout.fillWidth: true
                spacing: 3
                TileValue {
                    Layout.alignment: Qt.AlignBaseline
                    Layout.maximumWidth: tile.width * 0.42
                    text: Units.format(tile.output)
                    color: tile.contentColor
                    font.pixelSize: tile.valueSize
                }
                TileCaption {
                    Layout.alignment: Qt.AlignBaseline
                    text: tile.toLabel
                    color: ClockStyle.colPrimary
                    font.capitalization: Font.MixedCase
                    font.pixelSize: Math.round(tile.captionSize * 1.15)
                }
            }
            TileCaption {
                Layout.fillWidth: true
                text: Units.format(tile.input) + " " + tile.fromLabel
                color: tile.captionColor
                font.capitalization: Font.MixedCase
                font.pixelSize: tile.captionSize
            }
        }
        TileButton {
            implicitWidth: Math.round(tile.badgeSize * 0.84)
            implicitHeight: implicitWidth
            symbol: "swap_horiz"
            tip: Translation.tr("Swap units")
            colContent: tile.contentColor
            onClicked: tile.swap()
        }
    }
}
