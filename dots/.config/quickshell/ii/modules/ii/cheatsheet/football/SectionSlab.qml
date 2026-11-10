import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

// A titled slab one step up the surface ladder from the detail pane.
Rectangle {
    id: root

    property string title: ""
    property string symbol: ""
    property int shape: MaterialShape.Shape.Cookie9Sided
    property real padding: FootballStyle.panePadding
    default property alias content: body.data

    implicitHeight: column.implicitHeight + root.padding * 2
    radius: FootballStyle.radiusLarge
    color: FootballStyle.colRow

    ColumnLayout {
        id: column
        x: root.padding
        y: root.padding
        width: root.width - root.padding * 2
        spacing: FootballStyle.gap

        RowLayout {
            visible: root.title !== ""
            spacing: FootballStyle.gap
            MaterialShapeWrappedMaterialSymbol {
                visible: root.symbol !== ""
                text: root.symbol
                iconSize: 18
                padding: 8
                fill: 1
                shape: root.shape
                color: FootballStyle.colPrimaryContainer
                colSymbol: FootballStyle.colOnPrimaryContainer
            }
            StyledText {
                text: root.title.toUpperCase()
                font.pixelSize: FootballStyle.textLarger
                font.variableAxes: FootballStyle.axesHeadline
                color: FootballStyle.colOnSurface
            }
        }

        ColumnLayout {
            id: body
            Layout.fillWidth: true
            spacing: FootballStyle.gapSmall
        }
    }
}
