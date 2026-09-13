pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.notes

/**
 * Document outline / Table of Contents panel for the Notes app.
 *
 * Extracts all heading blocks (H1, H2, H3, etc.) from the active document,
 * renders an indented structural hierarchy, and jumps to any section on click.
 */
Item {
    id: root

    property var blocks: []
    signal headingClicked(string blockId)
    signal closed()

    readonly property var headings: {
        const list = [];
        const source = Array.isArray(root.blocks) ? root.blocks : [];
        for (let i = 0; i < source.length; i++) {
            const b = source[i];
            if (b && b.type === "heading") {
                list.push({
                    id: b.id,
                    level: Number(b.level || 1),
                    text: String(b.text || "").trim()
                });
            }
        }
        return list;
    }

    implicitWidth: 260

    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.large
        color: Appearance.m3colors.m3surfaceContainerHigh
        clip: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10

            // ── Header ────────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                MaterialSymbol {
                    text: "format_list_bulleted"
                    iconSize: 20
                    color: Appearance.colors.colPrimary
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Table of contents")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer0
                }

                NotesIconButton {
                    symbol: "close"
                    size: 30
                    iconSize: 18
                    tooltipText: Translation.tr("Close")
                    onTriggered: root.closed()
                }
            }

            // ── Headings List ─────────────────────────────────────────────
            ListView {
                id: headingList
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 4
                clip: true
                model: root.headings

                delegate: RippleButton {
                    id: headBtn
                    required property var modelData
                    required property int index

                    width: headingList.width
                    implicitHeight: 36
                    buttonRadius: Appearance.rounding.small
                    colBackground: Appearance.colors.colLayer1
                    colBackgroundHover: Appearance.colors.colLayer1Hover

                    onClicked: root.headingClicked(headBtn.modelData.id)

                    contentItem: RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Math.min((headBtn.modelData.level - 1) * 14 + 8, 56)
                        anchors.rightMargin: 8
                        spacing: 6

                        Rectangle {
                            Layout.preferredWidth: 20
                            Layout.preferredHeight: 18
                            radius: Appearance.rounding.verysmall
                            color: Appearance.colors.colLayer2

                            StyledText {
                                anchors.centerIn: parent
                                text: `H${headBtn.modelData.level}`
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colPrimary
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: headBtn.modelData.text && headBtn.modelData.text.length > 0
                                ? headBtn.modelData.text
                                : Translation.tr("(untitled section)")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: headBtn.modelData.level === 1 ? Font.DemiBold : Font.Normal
                            color: Appearance.colors.colOnLayer1
                            elide: Text.ElideRight
                        }
                    }
                }
            }

            // ── Empty State ───────────────────────────────────────────────
            ColumnLayout {
                visible: root.headings.length === 0
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 8

                MaterialSymbol {
                    Layout.alignment: Qt.AlignCenter
                    text: "format_list_bulleted"
                    iconSize: 32
                    color: Appearance.colors.colSubtext
                }

                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: Translation.tr("No headings yet")
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer0
                }

                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: Translation.tr("Add headings (# Title) to see the outline.")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.WordWrap
                }
            }
        }
    }
}
