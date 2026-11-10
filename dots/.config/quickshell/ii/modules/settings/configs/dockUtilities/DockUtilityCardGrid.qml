import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "../../../ii/dock/utilities/DockUtilityCatalog.js" as DockUtilityCatalog

/**
 * Every utility widget, by group, as cards. Columns come from the width
 * (260 px minimum, rows as even as the count allows) and every
 * card carries its own width. Cards are only built once the width is known:
 * building them at width 0 laid them out in one column and re-dealt them a
 * frame later, which read as the whole page flickering in.
 */
ColumnLayout {
    id: grid

    signal configureRequested(var info)

    readonly property real gap: 10
    readonly property real minCard: 260
    readonly property bool ready: grid.width > 0

    spacing: 22

    Repeater {
        model: grid.ready ? DockUtilityCatalog.groups.filter(group => DockUtilityCatalog.kindsInGroup(group.id).length > 0) : []
        delegate: ColumnLayout {
            id: groupColumn
            required property var modelData
            readonly property var kinds: DockUtilityCatalog.kindsInGroup(groupColumn.modelData.id)
            readonly property int maxCols: Math.max(1, Math.floor((grid.width + grid.gap) / (grid.minCard + grid.gap)))
            readonly property int rows: Math.ceil(groupColumn.kinds.length / groupColumn.maxCols)
            // Rows as even as the count allows: 7 over three rows is 3 + 2 + 2, never 3 + 3 + 1.
            function widthAt(index) {
                const base = Math.floor(groupColumn.kinds.length / groupColumn.rows);
                const extra = groupColumn.kinds.length % groupColumn.rows;
                let start = 0;
                for (let row = 0; row < groupColumn.rows; row++) {
                    const inRow = base + (row < extra ? 1 : 0);
                    if (index < start + inRow)
                        return Math.floor((grid.width - grid.gap * (inRow - 1)) / inRow);
                    start += inRow;
                }
                return grid.width;
            }
            Layout.fillWidth: true
            spacing: 10

            StyledText {
                Layout.leftMargin: 4
                text: Translation.tr(groupColumn.modelData.title)
                font.family: Appearance.font.family.title
                font.variableAxes: Appearance.font.variableAxes.titleRounded
                font.pixelSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnLayer0
            }

            Flow {
                Layout.fillWidth: true
                spacing: grid.gap

                Repeater {
                    model: groupColumn.kinds
                    delegate: DockUtilityCard {
                        required property var modelData
                        required property int index
                        info: modelData
                        width: groupColumn.widthAt(index)
                        height: implicitHeight
                        onConfigureRequested: grid.configureRequested(modelData)
                    }
                }
            }
        }
    }
}
