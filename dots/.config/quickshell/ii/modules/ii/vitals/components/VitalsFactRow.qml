import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * A read-only row in a Vitals sheet: the timetable rail's form row (shape icon, small bold
 * caption, bold value) without the pointer, since nothing opens from it. Sheets give each
 * row its own shape so a column of facts does not read as a column of identical dots.
 */
Rectangle {
    id: root

    property string symbol: ""
    property int shapeKind: MaterialShape.Shape.Cookie12Sided
    property string caption: ""
    property string value: ""

    Layout.fillWidth: true
    implicitHeight: 58
    radius: Appearance.rounding.small
    color: ClockStyle.colField

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 12
        spacing: 10

        MaterialShapeWrappedMaterialSymbol {
            text: root.symbol
            iconSize: 18
            padding: 9
            shape: root.shapeKind
            color: ClockStyle.colPrimaryContainer
            colSymbol: ClockStyle.colOnPrimaryContainer
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                text: root.caption
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.weight: Font.Bold
                color: ClockStyle.colOnSurfaceVariant
            }

            StyledText {
                Layout.fillWidth: true
                text: root.value
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.Bold
                color: ClockStyle.colOnSurface
            }
        }
    }
}
