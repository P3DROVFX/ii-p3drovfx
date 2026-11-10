import QtQuick
import QtQuick.Layouts
import qs.modules.common

/*
 * The live preview at the top of a desktop widget page: the real widgets on a
 * board of 240-unit cells, scaled to the page's width. Children are
 * WidgetPreviewSlot items placed by column and row.
 */
Rectangle {
    id: stage

    property int columns: 3
    property int rows: 1
    // A fixed scale for a stage laid out by its parent; 0 fits the width.
    property real boardScaleOverride: 0
    default property alias slots: board.data

    readonly property real padding: 20
    readonly property real cell: 240
    readonly property real gap: 12
    readonly property real boardWidth: stage.cell * stage.columns + stage.gap * (stage.columns - 1)
    readonly property real boardHeight: stage.cell * stage.rows + stage.gap * (stage.rows - 1)
    readonly property real boardScale: stage.boardScaleOverride > 0 ? stage.boardScaleOverride : Math.min(1, Math.max(0.1, (stage.width - stage.padding * 2) / stage.boardWidth))

    Layout.fillWidth: true
    implicitHeight: Math.round(stage.boardHeight * stage.boardScale) + stage.padding * 2
    radius: Appearance.rounding.verylarge
    color: Appearance.colors.colLayer1

    Item {
        id: board
        anchors.centerIn: parent
        width: stage.boardWidth
        height: stage.boardHeight
        scale: stage.boardScale
    }
}
