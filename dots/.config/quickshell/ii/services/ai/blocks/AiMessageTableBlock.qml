pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell

/**
 * A Markdown table, as a table.
 *
 * Qt's Markdown renderer draws pipe tables as a wall of pipes, which is what
 * the shell's own system prompt keeps asking the model to produce. This draws
 * the grid instead: header row, alternating rows, columns that keep their
 * width, and horizontal scrolling when the table is wider than the bubble
 * rather than a bubble that grows past the transcript.
 */
Item {
    id: root

    /** The parsed block: {header, rows, alignments, content}. */
    property var block: null
    property var messageData: null

    readonly property var header: Array.from(root.block?.header ?? [])
    readonly property var rows: Array.from(root.block?.rows ?? [])
    readonly property var alignments: Array.from(root.block?.alignments ?? [])

    readonly property real cellPaddingX: Appearance.rounding.unsharpenmore
    readonly property real cellPaddingY: Appearance.rounding.unsharpen + 2
    readonly property real maximumColumnWidth: Appearance.font.pixelSize.small * 22

    implicitHeight: tableFrame.implicitHeight

    function alignmentOf(column: int): int {
        const value = String(root.alignments[column] ?? "left");
        if (value === "right")
            return Text.AlignRight;
        if (value === "center")
            return Text.AlignHCenter;
        return Text.AlignLeft;
    }

    /** The table as tab-separated text, which is what a spreadsheet wants. */
    function asTabSeparated(): string {
        const lines = [root.header.join("\t")];
        for (let i = 0; i < root.rows.length; i++)
            lines.push(Array.from(root.rows[i]).join("\t"));
        return lines.join("\n");
    }

    Rectangle {
        id: tableFrame
        anchors.left: parent.left
        anchors.right: parent.right
        implicitHeight: tableColumn.implicitHeight
        radius: Appearance.rounding.small
        color: Appearance.colors.colLayer2
        clip: true

        ColumnLayout {
            id: tableColumn
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 0

            Flickable {
                id: tableFlickable
                Layout.fillWidth: true
                implicitHeight: grid.implicitHeight
                contentWidth: grid.implicitWidth
                contentHeight: grid.implicitHeight
                flickableDirection: Flickable.HorizontalFlick
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentWidth > width
                clip: true

                MouseArea {
                    // Most mice only have a vertical wheel, and a table that
                    // scrolls sideways is unusable without one.
                    anchors.fill: parent
                    acceptedButtons: Qt.NoButton
                    enabled: tableFlickable.interactive
                    onWheel: wheel => {
                        const delta = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.angleDelta.x;
                        const limit = tableFlickable.contentWidth - tableFlickable.width;
                        tableFlickable.contentX = Math.max(0, Math.min(limit, tableFlickable.contentX - delta));
                        wheel.accepted = true;
                    }
                }

                GridLayout {
                    id: grid
                    columns: Math.max(1, root.header.length)
                    columnSpacing: 0
                    rowSpacing: 0

                    Repeater {
                        model: ScriptModel {
                            values: root.header
                        }

                        delegate: Rectangle {
                            id: headerCell
                            required property var modelData
                            required property int index

                            Layout.fillWidth: true
                            implicitWidth: Math.min(root.maximumColumnWidth, headerLabel.implicitWidth + root.cellPaddingX * 2)
                            implicitHeight: headerLabel.implicitHeight + root.cellPaddingY * 2
                            color: Appearance.colors.colLayer3

                            StyledText {
                                id: headerLabel
                                anchors.fill: parent
                                anchors.leftMargin: root.cellPaddingX
                                anchors.rightMargin: root.cellPaddingX
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: root.alignmentOf(headerCell.index)
                                text: headerCell.modelData
                                textFormat: Text.MarkdownText
                                wrapMode: Text.Wrap
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnLayer3
                            }
                        }
                    }

                    Repeater {
                        // One delegate per cell: a GridLayout fills row by row,
                        // so the cells are flattened with their row index kept
                        // for the banding.
                        model: ScriptModel {
                            values: {
                                const flat = [];
                                for (let row = 0; row < root.rows.length; row++) {
                                    const cells = Array.from(root.rows[row]);
                                    for (let column = 0; column < root.header.length; column++)
                                        flat.push({
                                            row: row,
                                            column: column,
                                            text: String(cells[column] ?? "")
                                        });
                                }
                                return flat;
                            }
                        }

                        delegate: Rectangle {
                            id: bodyCell
                            required property var modelData

                            Layout.fillWidth: true
                            implicitWidth: Math.min(root.maximumColumnWidth, bodyLabel.implicitWidth + root.cellPaddingX * 2)
                            implicitHeight: bodyLabel.implicitHeight + root.cellPaddingY * 2
                            color: bodyCell.modelData.row % 2 === 0
                                ? Appearance.colors.colLayer2
                                : Appearance.colors.colLayer2Hover

                            StyledText {
                                id: bodyLabel
                                anchors.fill: parent
                                anchors.leftMargin: root.cellPaddingX
                                anchors.rightMargin: root.cellPaddingX
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: root.alignmentOf(bodyCell.modelData.column)
                                text: bodyCell.modelData.text
                                textFormat: Text.MarkdownText
                                wrapMode: Text.Wrap
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnLayer2
                                onLinkActivated: link => Qt.openUrlExternally(link)
                            }
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.margins: Appearance.rounding.unsharpen
                spacing: Appearance.rounding.unsharpenmore

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("%1 rows").arg(root.rows.length)
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                }

                RippleButton {
                    id: copyTableButton
                    property bool copied: false

                    implicitWidth: Math.round(Appearance.font.pixelSize.huge * 1.4)
                    implicitHeight: implicitWidth
                    buttonRadius: Appearance.rounding.full
                    topPadding: 0
                    bottomPadding: 0
                    leftPadding: 0
                    rightPadding: 0
                    colBackground: ColorUtils.transparentize(Appearance.colors.colLayer3, 1)
                    colBackgroundHover: Appearance.colors.colLayer3Hover
                    colRipple: Appearance.colors.colLayer3Active
                    onClicked: {
                        AiOutputController.copyText(root.asTabSeparated());
                        copyTableButton.copied = true;
                        copyTableReset.restart();
                    }

                    Accessible.name: Translation.tr("Copy the table")

                    Timer {
                        id: copyTableReset
                        interval: Appearance.animation.elementMoveSlow.duration * 3
                        onTriggered: copyTableButton.copied = false
                    }

                    contentItem: MaterialSymbol {
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: copyTableButton.copied ? "inventory" : "table_view"
                        fill: 1
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnLayer2
                    }

                    StyledToolTip {
                        text: copyTableButton.copied
                            ? Translation.tr("Copied as columns")
                            : Translation.tr("Copy as columns, ready to paste into a sheet")
                    }
                }
            }
        }
    }
}
