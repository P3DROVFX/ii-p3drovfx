pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common

/**
 * The elapsed recording time, laid out as individual rolling cells.
 *
 * Two rules keep it stable while it runs:
 *
 *   - The repeaters are driven by **counts**, never by the split string. A
 *     model that is a new array every second recreates every delegate, and a
 *     delegate that is recreated cannot animate its own change — the roll would
 *     silently never happen.
 *   - `stacked` re-stacks the groups for the vertical bar instead of rotating
 *     them. `01:09` becomes two rows, which is the only form that fits 36px.
 */
Item {
    id: root

    property string value: "00:00"
    property real pixelSize: 14
    property color colText: "white"
    property int weight: 700
    property real letterSpacing: 0
    property string fontFamily: Appearance.font.family.title
    property bool stacked: false
    property real stackSpacing: -2
    property bool animate: true

    readonly property var parts: root.value.split(":")
    readonly property int rowCount: root.stacked ? Math.max(1, root.parts.length) : 1

    function rowValue(row) {
        if (!root.stacked)
            return root.value;
        return root.parts[row] ?? "";
    }

    implicitWidth: rows.implicitWidth
    implicitHeight: rows.implicitHeight

    // `Grid` rather than `Column`: the rows of a stacked timer have to be
    // centred on each other, and only Grid can align its own items.
    Grid {
        id: rows
        anchors.centerIn: parent
        columns: 1
        horizontalItemAlignment: Grid.AlignHCenter
        spacing: root.stacked ? root.stackSpacing : 0

        Repeater {
            model: root.rowCount

            delegate: Row {
                id: rowItem

                required property int index
                readonly property string rowText: root.rowValue(rowItem.index)
                readonly property int cellCount: rowItem.rowText.length

                spacing: 0

                Repeater {
                    model: rowItem.cellCount

                    delegate: RecordDigitCell {
                        id: cell
                        required property int index
                        value: rowItem.rowText.charAt(cell.index)
                        pixelSize: root.pixelSize
                        colText: root.colText
                        weight: root.weight
                        letterSpacing: root.letterSpacing
                        fontFamily: root.fontFamily
                        animate: root.animate
                    }
                }
            }
        }
    }
}
