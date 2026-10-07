import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.clock.components

/**
 * Draw on screen: the pen for annotating whatever is on the screen, over every app —
 * for a recording, a call or a screen share.
 *
 * Square: the pen on a cookie. Out (the drawing tools on screen) the cookie morphs into
 * a burst and goes primary; the state is the shape, not a second glyph. A pip in the
 * current ink says there is a drawing left on some workspace.
 * Wide: the pen as the control, what the overlay is doing over a caption, and the one
 * action worth a click from the dock — rubbing every sheet out.
 */
UtilityTile {
    id: tile

    readonly property bool out: LiveDraw.trayOpen
    readonly property bool drawing: LiveDraw.trayOpen && LiveDraw.drawing
    readonly property int sheets: LiveDraw.sheetCount
    readonly property color ink: LiveDraw.color.length > 0 ? LiveDraw.color : (LiveDraw.palette[0] ?? ClockStyle.colPrimary)

    function toggle() {
        tile.host?.closePanel();
        LiveDraw.toggle();
    }

    function activate() {
        if (tile.wide)
            return false;
        tile.toggle();
        return true;
    }

    surfaceColor: tile.out ? ClockStyle.colPrimaryContainer : ClockStyle.colSurfaceHigh
    contentColor: tile.out ? ClockStyle.colOnPrimaryContainer : ClockStyle.colOnSurface

    readonly property string stateText: tile.drawing ? Translation.tr("Drawing")
        : tile.out ? Translation.tr("Pen up · clicks go through")
        : tile.sheets === 1 ? Translation.tr("A drawing is on screen")
        : tile.sheets > 1 ? Translation.tr("Drawings on %1 workspaces").arg(tile.sheets)
        : Translation.tr("Over every app")

    tooltipText: tile.out ? Translation.tr("Put the drawing tools away") : Translation.tr("Draw on the screen")
    panelSubtitle: tile.stateText
    menuActions: [
        { id: "toggle", icon: "draw", text: tile.out ? Translation.tr("Put the drawing tools away") : Translation.tr("Draw on the screen") },
        { id: "save", icon: "note_add", text: Translation.tr("Save this screen's drawing to Notes"), visible: tile.sheets > 0 },
        { id: "clear", icon: "ink_eraser", text: Translation.tr("Rub every drawing out"), visible: tile.sheets > 0 }
    ]
    function menuAction(actionId) {
        if (actionId === "toggle")
            tile.toggle();
        else if (actionId === "save")
            GlobalStates.liveDrawSaveRequest++;
        else if (actionId === "clear")
            LiveDraw.clearAll();
    }

    // ── Square ──────────────────────────────────────────────────────────
    TileBadge {
        id: badge
        anchors.centerIn: parent
        visible: !tile.wide
        width: Math.round(tile.side * 0.8)
        height: width
        renderScale: tile.renderScale
        shape: tile.out ? MaterialShape.Shape.SoftBurst : MaterialShape.Shape.Cookie7Sided
        color: tile.out ? ClockStyle.colPrimary : ClockStyle.colSecondaryContainer
        colSymbol: tile.out ? ClockStyle.colOnPrimary : ClockStyle.colOnSecondaryContainer
        fill: tile.out ? 1 : 0
        text: "draw"
        iconScale: 0.46
    }

    // The ink left behind, in the colour the pen will draw with next.
    Rectangle {
        visible: !tile.wide && tile.sheets > 0
        width: Math.max(6, Math.round(tile.side * 0.16))
        height: width
        radius: width / 2
        x: badge.x + badge.width - width * 0.9
        y: badge.y + badge.height - width * 0.9
        color: tile.ink
    }

    // ── Wide ────────────────────────────────────────────────────────────
    RowLayout {
        anchors.fill: parent
        anchors.margins: tile.pad
        visible: tile.wide
        spacing: tile.pad

        TileButton {
            implicitWidth: tile.badgeSize
            implicitHeight: tile.badgeSize
            symbol: "draw"
            filled: true
            active: tile.out
            colFilled: tile.out ? ClockStyle.colPrimary : ClockStyle.colSecondaryContainer
            colOnFilled: tile.out ? ClockStyle.colOnPrimary : ClockStyle.colOnSecondaryContainer
            tip: tile.out ? Translation.tr("Put the drawing tools away") : Translation.tr("Draw on the screen")
            onClicked: tile.toggle()
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            TileText {
                Layout.fillWidth: true
                text: Translation.tr("Draw")
                color: tile.contentColor
                font.pixelSize: Math.round(tile.height * 0.3)
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            TileCaption {
                Layout.fillWidth: true
                text: tile.stateText
                color: tile.captionColor
                font.pixelSize: tile.captionSize
            }
        }

        TileButton {
            visible: tile.sheets > 0
            implicitWidth: Math.round(tile.badgeSize * 0.72)
            implicitHeight: implicitWidth
            symbol: "ink_eraser"
            colContent: tile.contentColor
            tip: Translation.tr("Rub every drawing out")
            onClicked: LiveDraw.clearAll()
        }
    }
}
