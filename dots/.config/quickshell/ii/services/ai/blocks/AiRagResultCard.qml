import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * One chunk `rag_search` found in a folder the user indexed. Read-only: the
 * point of a retrieval hit is what it says, not an action to take on it.
 */
Rectangle {
    id: root

    required property var hit

    readonly property string collectionName: String(root.hit?.collection ?? "")
    readonly property string file: String(root.hit?.file ?? "")
    readonly property var startLine: root.hit?.startLine ?? null
    readonly property var endLine: root.hit?.endLine ?? null
    readonly property string snippet: String(root.hit?.snippet ?? "")
    readonly property string lineRange: {
        if (root.startLine === null)
            return "";
        return root.endLine !== null && root.endLine !== root.startLine
            ? `:${root.startLine}-${root.endLine}`
            : `:${root.startLine}`;
    }

    implicitHeight: column.implicitHeight + 20
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer2

    ColumnLayout {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        spacing: 4

        RowLayout {
            Layout.fillWidth: true
            spacing: Appearance.rounding.unsharpenmore

            MaterialSymbol {
                Layout.alignment: Qt.AlignVCenter
                text: "description"
                iconSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colOnLayer2
            }

            StyledText {
                Layout.fillWidth: true
                text: `${root.file}${root.lineRange}`
                elide: Text.ElideMiddle
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer2
            }

            StyledText {
                visible: root.collectionName.length > 0
                text: root.collectionName
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }

        StyledText {
            visible: root.snippet.length > 0
            Layout.fillWidth: true
            text: root.snippet
            wrapMode: Text.Wrap
            maximumLineCount: 4
            elide: Text.ElideRight
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
    }
}
