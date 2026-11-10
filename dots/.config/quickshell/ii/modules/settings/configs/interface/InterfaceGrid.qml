import QtQuick
import QtQuick.Layouts

/**
 * Equal cells in as many columns as the width allows, never leaving a straggler: the
 * column count is the largest one (up to `maxColumns`, each at least `minCell` wide) that
 * divides the number of children. Children take `width: grid.cellWidth`.
 */
Item {
    id: root

    readonly property real sectionSpacing: 4

    property int gap: 12
    property real minCell: 240
    property int maxColumns: 3
    /// What sits above the grid in a ContentSection: a notice box needs the gap added to
    /// the section's own spacing; a grid right under the title needs none.
    property bool belowNotice: true
    default property alias cells: flow.data

    readonly property int count: flow.children.length
    readonly property int fits: Math.max(1, Math.min(root.maxColumns, Math.floor((width + root.gap) / (root.minCell + root.gap))))
    readonly property int columns: {
        for (let candidate = root.fits; candidate > 1; candidate--) {
            if (root.count % candidate === 0)
                return candidate;
        }
        return 1;
    }
    readonly property int cellWidth: Math.floor((width - root.gap * (root.columns - 1)) / root.columns)

    Layout.fillWidth: true
    Layout.topMargin: root.belowNotice ? root.gap - root.sectionSpacing : 0
    implicitHeight: flow.implicitHeight

    Flow {
        id: flow
        width: parent.width
        spacing: root.gap
    }
}
