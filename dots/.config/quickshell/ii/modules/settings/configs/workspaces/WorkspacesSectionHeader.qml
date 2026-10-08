import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * A heading between the page's blocks: a shaped glyph, the title in the rounded
 * face and a line under it.
 */
RowLayout {
    id: root

    property string symbol: ""
    property string title: ""
    property string summary: ""
    property var shape: MaterialShape.Shape.Cookie9Sided
    property color colGlyph: Appearance.colors.colPrimaryContainer
    property color colOnGlyph: Appearance.colors.colOnPrimaryContainer

    readonly property real glyphSize: 20
    readonly property real glyphPadding: 9

    Layout.fillWidth: true
    Layout.topMargin: 12
    Layout.leftMargin: 4
    spacing: 12

    MaterialShapeWrappedMaterialSymbol {
        text: root.symbol
        iconSize: root.glyphSize
        padding: root.glyphPadding
        fill: 1
        shape: root.shape
        color: root.colGlyph
        colSymbol: root.colOnGlyph
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 0
        StyledText {
            Layout.fillWidth: true
            text: root.title
            font.family: Appearance.font.family.title
            font.variableAxes: Appearance.font.variableAxes.titleRounded
            font.pixelSize: Appearance.font.pixelSize.huge
            color: Appearance.colors.colOnLayer0
            elide: Text.ElideRight
        }
        StyledText {
            Layout.fillWidth: true
            visible: root.summary !== ""
            text: root.summary
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            wrapMode: Text.WordWrap
        }
    }
}
