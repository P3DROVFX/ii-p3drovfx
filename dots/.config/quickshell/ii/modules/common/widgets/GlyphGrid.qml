import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

GridView {
    id: root

    property var entries: []
    property bool listMode: false
    property int cellSize: 56
    property int cellAspect: 54
    property int glyphSize: 26

    signal chosen(glyph: string)
    signal dismissRequested()
    signal textTyped(text: string)
    signal backspaceRequested()
    signal topEdgeReached()

    readonly property int columns: Math.max(1, Math.round(width / cellWidth))
    readonly property int listSpacing: Math.round(root.glyphSize * 0.4)

    clip: true
    cellWidth: root.listMode ? width : Math.floor(width / Math.max(1, Math.floor(width / root.cellSize)))
    cellHeight: root.cellAspect
    boundsBehavior: Flickable.StopAtBounds
    highlightMoveDuration: 120

    onEntriesChanged: {
        glyphModel.values = root.entries;
        root.positionViewAtBeginning();
    }
    Component.onCompleted: glyphModel.values = root.entries

    model: ScriptModel {
        id: glyphModel
        objectProp: "idx"
    }

    ScrollBar.vertical: StyledScrollBar {}

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            root.dismissRequested();
            event.accepted = true;
        } else if (event.key === Qt.Key_Up && root.currentIndex < root.columns) {
            root.topEdgeReached();
            event.accepted = true;
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (root.currentItem)
                root.chosen(root.currentItem.glyph);
            event.accepted = true;
        } else if (event.key === Qt.Key_Backspace) {
            root.backspaceRequested();
            event.accepted = true;
        } else if (event.text && event.text.length > 0) {
            root.textTyped(event.text);
            event.accepted = true;
        }
    }

    delegate: Item {
        id: cell
        required property var modelData
        readonly property string glyph: cell.modelData.glyph
        width: root.cellWidth
        height: root.cellHeight

        RippleButton {
            anchors.centerIn: parent
            implicitWidth: root.cellWidth - 4
            implicitHeight: root.cellHeight - 4
            buttonRadius: Appearance.rounding.small
            colBackground: (root.activeFocus && cell.GridView.isCurrentItem) ? Appearance.colors.colLayer2Hover : "transparent"
            colBackgroundHover: Appearance.colors.colLayer2Hover
            onClicked: root.chosen(cell.glyph)

            contentItem: RowLayout {
                spacing: root.listSpacing

                StyledText {
                    Layout.leftMargin: root.listMode ? root.listSpacing : 0
                    Layout.fillWidth: !root.listMode
                    Layout.maximumWidth: root.listMode ? cell.width * 0.5 : cell.width
                    horizontalAlignment: root.listMode ? Text.AlignLeft : Text.AlignHCenter
                    elide: Text.ElideRight
                    fontSizeMode: Text.HorizontalFit
                    minimumPixelSize: Math.round(root.glyphSize * 0.55)
                    text: cell.glyph
                    font.pixelSize: root.glyphSize
                    color: Appearance.colors.colOnLayer0
                }

                StyledText {
                    visible: root.listMode
                    Layout.fillWidth: true
                    Layout.rightMargin: root.listSpacing
                    horizontalAlignment: Text.AlignRight
                    elide: Text.ElideRight
                    text: cell.modelData.label
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }

            StyledToolTip {
                extraVisibleCondition: !root.listMode
                text: cell.modelData.label
            }
        }
    }
}
