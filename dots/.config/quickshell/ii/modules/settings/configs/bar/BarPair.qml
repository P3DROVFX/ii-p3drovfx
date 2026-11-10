import QtQuick
import QtQuick.Layouts

/**
 * Original Settings controls two to a row, one to a row on a narrow page — a ConfigRow
 * whose labels would otherwise wrap to two lines at the Settings minimum. Children bind
 * `groupHorizontal: <pair>.horizontal` so their grouped corners follow the flip. With an
 * odd number of visible controls the last one spans the row instead of leaving a hole.
 */
GridLayout {
    id: root

    property real breakWidth: 600
    readonly property bool horizontal: root.columns === 2

    Layout.fillWidth: true
    // A lone visible control takes the whole row rather than half of it.
    columns: width >= root.breakWidth && root.visibleChildren.length > 1 ? 2 : 1
    columnSpacing: 4
    rowSpacing: 4
    uniformCellWidths: root.horizontal

    function spanLast() {
        const shown = [];
        for (const child of root.children) {
            if (child.visible)
                shown.push(child);
            child.Layout.columnSpan = 1;
        }
        if (root.horizontal && shown.length % 2 === 1)
            shown[shown.length - 1].Layout.columnSpan = 2;
    }

    onVisibleChildrenChanged: Qt.callLater(root.spanLast)
    onColumnsChanged: Qt.callLater(root.spanLast)
    Component.onCompleted: root.spanLast()
}
