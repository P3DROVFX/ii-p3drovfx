import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import Quickshell

Item {
    id: root
    anchors.fill: parent
    property bool isExpanded: false

    // Contracted view: simple "Copied" banner
    RowLayout {
        id: contractedLayout
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        spacing: 8
        opacity: !root.isExpanded ? 1.0 : 0.0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 150 } }

        MaterialSymbol {
            Layout.alignment: Qt.AlignVCenter
            text: "assignment"
            iconSize: 16
            color: Appearance.colors.colPrimary
        }

        StyledText {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.bold: true
            color: Appearance.colors.colOnSurface
            text: Translation.tr("Copied!")
            elide: Text.ElideRight
            maximumLineCount: 1
            wrapMode: Text.NoWrap
        }
    }

    // Expanded view: displays full clipboard content preview
    ColumnLayout {
        id: expandedLayout
        anchors.fill: parent
        anchors.margins: 12
        spacing: 6
        opacity: root.isExpanded ? 1.0 : 0.0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 150 } }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            MaterialSymbol {
                text: "assignment"
                iconSize: 14
                color: Appearance.colors.colPrimary
            }

            StyledText {
                text: Translation.tr("Clipboard")
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.bold: true
                color: Appearance.colors.colPrimary
                Layout.fillWidth: true
            }

            StyledText {
                text: Translation.tr("Recent")
                font.pixelSize: 9
                color: Appearance.colors.colSubtext
            }
        }

        // Preview box for text content
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Appearance.rounding.small
            color: Appearance.colors.colSurfaceContainerLow
            border.width: 0
            border.color: Appearance.colors.colLayer0Border

            ScrollView {
                anchors.fill: parent
                anchors.margins: 8
                clip: true

                StyledText {
                    width: parent.width
                    text: {
                        const entry = Cliphist.entries[0];
                        if (!entry) return "";
                        if (Cliphist.entryIsImage(entry)) {
                            return Translation.tr("Image copied");
                        }
                        return entry.replace(/^\s*\S+\s+/, "").trim();
                    }
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnSurface
                    wrapMode: Text.Wrap
                    maximumLineCount: 5
                    elide: Text.ElideRight
                }
            }
        }
    }
}
