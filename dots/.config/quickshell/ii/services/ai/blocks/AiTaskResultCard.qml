pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets

/** Compact TaskRef projection for list/search results. */
Item {
    id: root

    required property var card
    implicitHeight: surface.implicitHeight

    Rectangle {
        id: surface
        anchors.left: parent.left
        anchors.right: parent.right
        implicitHeight: content.implicitHeight + Appearance.rounding.normal * 2
        radius: Appearance.rounding.large
        color: Appearance.colors.colLayer2

        ColumnLayout {
            id: content
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Appearance.rounding.normal
            spacing: Appearance.rounding.unsharpenmore

            RowLayout {
                Layout.fillWidth: true
                MaterialSymbol {
                    text: "checklist"
                    fill: 1
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.m3colors.m3primary
                }
                StyledText {
                    Layout.fillWidth: true
                    text: String(root.card?.summary ?? Translation.tr("Tasks"))
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer2
                }
            }

            Repeater {
                model: ScriptModel { values: Array.from(root.card?.data?.tasks ?? []).slice(0, 50) }
                delegate: ColumnLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: Appearance.rounding.unsharpenmore / 2

                    StyledText {
                        Layout.fillWidth: true
                        text: (modelData?.status === "completed" ? "✓ " : "") + String(modelData?.title ?? "")
                        wrapMode: Text.Wrap
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer2
                    }
                    StyledText {
                        Layout.fillWidth: true
                        visible: String(modelData?.dueLocal ?? "").length > 0
                        text: Translation.tr("Due: %1").arg(String(modelData?.dueLocal ?? ""))
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }
            }
        }
    }
}
