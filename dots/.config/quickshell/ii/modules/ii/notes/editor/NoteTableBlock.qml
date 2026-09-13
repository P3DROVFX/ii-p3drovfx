pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.notes

/**
 * A table.
 *
 * Cells are edited in place and the grid is always a rectangle — the model guarantees
 * that, so nothing here has to cope with a short row. Tab moves to the next cell rather
 * than indenting, which is what a table means by Tab, and Tab in the last cell adds a row:
 * filling a table in should never require reaching for a button.
 */
Item {
    id: root

    property var editor: null
    property var block: null
    property int blockIndex: 0

    readonly property int columns: root.block ? root.block.columns : 2
    readonly property var rows: root.block ? root.block.rows : []
    readonly property bool hasHeader: root.block ? root.block.header : true

    implicitHeight: Math.ceil((panel.height + 16) / NotesMetrics.paperLineHeight) * NotesMetrics.paperLineHeight

    function cellIndex(row, column): int {
        return row * root.columns + column;
    }

    function setCell(row, column, value): void {
        const next = root.rows.map(item => Array.from(item));
        if (row < 0 || row >= next.length || column < 0 || column >= next[row].length)
            return;
        if (next[row][column] === value)
            return;
        next[row][column] = value;
        // Not structural: the cell already shows what was typed, and rebuilding the grid
        // would take the caret out of it.
        root.editor.apply([{ op: "update", id: root.block.id, patch: { rows: next } }], false);
    }

    function addRow(): void {
        const next = root.rows.map(item => Array.from(item));
        next.push(new Array(root.columns).fill(""));
        root.editor.apply([{ op: "update", id: root.block.id, patch: { rows: next } }]);
    }

    function addColumn(): void {
        const next = root.rows.map(item => Array.from(item).concat([""]));
        root.editor.apply([{ op: "update", id: root.block.id,
                             patch: { columns: root.columns + 1, rows: next } }]);
    }

    function removeRow(): void {
        if (root.rows.length <= 1)
            return;
        const next = root.rows.map(item => Array.from(item));
        next.pop();
        root.editor.apply([{ op: "update", id: root.block.id, patch: { rows: next } }]);
    }

    function removeColumn(): void {
        if (root.columns <= 1)
            return;
        const next = root.rows.map(item => Array.from(item).slice(0, root.columns - 1));
        root.editor.apply([{ op: "update", id: root.block.id,
                             patch: { columns: root.columns - 1, rows: next } }]);
    }

    Rectangle {
        id: panel
        x: NotesMetrics.readingPadding
        y: Math.round((root.implicitHeight - height) / 2)
        width: Math.max(200, Math.min(NotesMetrics.readingWidth,
            root.width - NotesMetrics.readingPadding * 2))
        height: layout.implicitHeight + 20
        radius: Appearance.rounding.normal
        color: Appearance.m3colors.m3surfaceContainerLowest
        clip: true

        ColumnLayout {
            id: layout
            anchors.fill: parent
            anchors.margins: 10
            spacing: 6

            GridLayout {
                Layout.fillWidth: true
                columns: root.columns
                rowSpacing: 2
                columnSpacing: 2

                Repeater {
                    model: root.rows.length * root.columns

                    delegate: Rectangle {
                        id: cell
                        required property int index
                        readonly property int rowIndex: Math.floor(cell.index / root.columns)
                        readonly property int columnIndex: cell.index % root.columns
                        readonly property bool isHeader: root.hasHeader && cell.rowIndex === 0

                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.preferredHeight: Math.max(34, cellText.implicitHeight + 12)
                        radius: Appearance.rounding.verysmall
                        color: cell.isHeader
                            ? Appearance.colors.colLayer2
                            : (cellText.activeFocus ? Appearance.colors.colLayer1Hover : "transparent")

                        Behavior on color {
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                        }

                        TextEdit {
                            id: cellText
                            anchors.fill: parent
                            anchors.margins: 6
                            text: root.rows[cell.rowIndex] !== undefined
                                ? root.rows[cell.rowIndex][cell.columnIndex] ?? ""
                                : ""
                            wrapMode: TextEdit.Wrap
                            selectByMouse: true
                            textFormat: TextEdit.PlainText
                            renderType: Text.NativeRendering
                            color: Appearance.colors.colOnLayer0
                            font {
                                family: Appearance.font.family.main
                                pixelSize: Appearance.font.pixelSize.small
                                weight: cell.isHeader ? Font.DemiBold : Font.Normal
                            }
                            selectedTextColor: Appearance.m3colors.m3onSecondaryContainer
                            selectionColor: Appearance.colors.colSecondaryContainer

                            onActiveFocusChanged: {
                                if (activeFocus)
                                    root.editor.activeBlockId = root.block.id;
                                else
                                    root.setCell(cell.rowIndex, cell.columnIndex, cellText.text);
                            }

                            Keys.onPressed: event => {
                                if (event.key === Qt.Key_Tab) {
                                    root.setCell(cell.rowIndex, cell.columnIndex, cellText.text);
                                    if (cell.index === root.rows.length * root.columns - 1)
                                        root.addRow();
                                    else
                                        cellText.nextItemInFocusChain().forceActiveFocus();
                                    event.accepted = true;
                                }
                            }
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 0

                NotesIconButton {
                    symbol: "add_row_below"
                    size: 32
                    iconSize: 17
                    tooltipText: Translation.tr("Add a row")
                    onTriggered: root.addRow()
                }

                NotesIconButton {
                    symbol: "add_column_right"
                    size: 32
                    iconSize: 17
                    tooltipText: Translation.tr("Add a column")
                    onTriggered: root.addColumn()
                }

                NotesIconButton {
                    symbol: "delete_sweep"
                    size: 32
                    iconSize: 17
                    tooltipText: Translation.tr("Remove the last row")
                    enabled: root.rows.length > 1
                    onTriggered: root.removeRow()
                }

                Item {
                    Layout.fillWidth: true
                }

                NotesIconButton {
                    symbol: "delete"
                    size: 32
                    iconSize: 17
                    tooltipText: Translation.tr("Remove this table")
                    onTriggered: root.editor.removeBlock(root.block.id)
                }
            }
        }
    }
}
