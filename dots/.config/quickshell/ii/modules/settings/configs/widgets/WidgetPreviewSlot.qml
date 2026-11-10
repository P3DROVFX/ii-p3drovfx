import QtQuick

/*
 * One widget's place on a WidgetPreviewStage, in cells. The widget inside is
 * centred and scaled to fill the place, whatever its Widget Size.
 */
Item {
    id: slot

    property int column: 0
    property int row: 0
    property int columnSpan: 1
    property int rowSpan: 1
    readonly property real cell: 240
    readonly property real gap: 12

    x: slot.column * (slot.cell + slot.gap)
    y: slot.row * (slot.cell + slot.gap)
    width: slot.cell * slot.columnSpan + slot.gap * (slot.columnSpan - 1)
    height: slot.cell * slot.rowSpan + slot.gap * (slot.rowSpan - 1)
}
