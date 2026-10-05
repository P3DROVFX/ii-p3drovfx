import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.clock.components

/**
 * Search: a door into the shell's search. Square: the magnifier on a shape of
 * the user's choosing. Wide: a search bar — the magnifier and "Search" in the
 * title face — on a pill, or straight on the dock when the background is off.
 * A click opens the search.
 */
UtilityTile {
    id: tile

    readonly property var cfg: Config.options?.dock?.utilities?.search ?? null
    readonly property string squareShape: String(tile.cfg?.squareShape ?? "Cookie9Sided")
    readonly property bool background: tile.cfg?.background ?? true

    // The wide face draws its own pill; the square keeps the tile's surface
    // unless the background is off.
    surfaceColor: tile.wide || !tile.background ? "transparent" : ClockStyle.colSurfaceHigh
    contentColor: ClockStyle.colOnSurface

    tooltipText: Translation.tr("Search")

    function activate() {
        GlobalStates.toggleSearchOnly(tile.host?.QsWindow?.window?.screen?.name ?? "");
        return true;
    }

    // ── Square ──────────────────────────────────────────────────────────
    // Without a background the shape IS the widget: the tile's full height,
    // level with the other widgets.
    TileBadge {
        anchors.centerIn: parent
        visible: !tile.wide
        width: tile.background ? Math.round(tile.side * 0.78) : tile.side
        height: width
        renderScale: tile.renderScale
        shapeName: tile.squareShape
        color: ClockStyle.colPrimaryContainer
        colSymbol: ClockStyle.colOnPrimaryContainer
        text: "search"
        iconScale: 0.5
    }

    // ── Wide: a search bar ──────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        visible: tile.wide && tile.background
        radius: height / 2
        color: tile.hovered ? ClockStyle.colSurfaceHover : ClockStyle.colSurfaceHigh
        Behavior on color {
            animation: ClockStyle.motionFast.colorAnimation.createObject(this)
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: tile.background ? tile.pad : 0
        anchors.rightMargin: tile.pad * 2
        anchors.topMargin: tile.background ? tile.pad : 0
        anchors.bottomMargin: tile.background ? tile.pad : 0
        visible: tile.wide
        spacing: Math.round(tile.pad * 1.2)

        TileBadge {
            readonly property real size: tile.background ? tile.badgeSize : tile.height
            implicitWidth: size
            implicitHeight: size
            renderScale: tile.renderScale
            shape: MaterialShape.Shape.Circle
            color: ClockStyle.colPrimaryContainer
            colSymbol: ClockStyle.colOnPrimaryContainer
            text: "search"
            iconScale: tile.background ? 0.52 : 0.46
        }
        TileText {
            Layout.fillWidth: true
            text: Translation.tr("Search")
            color: tile.background ? ClockStyle.colOnSurfaceVariant : tile.contentColor
            font.family: Appearance.font.family.title
            font.variableAxes: Appearance.font.variableAxes.titleRounded
            font.pixelSize: Math.round(tile.height * 0.34)
            elide: Text.ElideRight
        }
    }
}
