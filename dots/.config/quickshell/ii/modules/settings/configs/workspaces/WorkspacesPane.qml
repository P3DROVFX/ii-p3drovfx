import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * A page pane of the Workspaces page: a colLayer1 slab under the shape-icon header the
 * Colors page uses. The subtitle states the current value (or the option under the
 * pointer); `engaged` morphs the header shape. `default` content goes in the body;
 * `headerExtra` sits at the header's right end.
 */
Rectangle {
    id: root

    readonly property real padding: 20
    readonly property real bodySpacing: 18
    readonly property real headerSpacing: 14
    readonly property real iconSize: 24
    readonly property real iconPadding: 12

    property string symbol: ""
    property var shapeIdle: MaterialShape.Shape.Cookie9Sided
    property var shapeEngaged: MaterialShape.Shape.Cookie12Sided
    property bool engaged: false
    property string title: ""
    property string subtitle: ""
    default property alias content: body.data
    property alias headerExtra: headerExtraRow.data

    implicitHeight: column.implicitHeight + root.padding * 2
    radius: Appearance.rounding.verylarge
    color: Appearance.colors.colLayer1

    ColumnLayout {
        id: column
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: root.padding
        }
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            spacing: root.headerSpacing

            MaterialShapeWrappedMaterialSymbol {
                text: root.symbol
                iconSize: root.iconSize
                padding: root.iconPadding
                fill: 1
                shape: root.engaged ? root.shapeEngaged : root.shapeIdle
                color: Appearance.colors.colPrimaryContainer
                colSymbol: Appearance.colors.colOnPrimaryContainer
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
                    color: Appearance.colors.colOnLayer1
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.subtitle
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                }
            }

            RowLayout {
                id: headerExtraRow
                spacing: 8
            }
        }

        ColumnLayout {
            id: body
            Layout.fillWidth: true
            // Eases in with the body, so a pane whose body unfolds has no empty gap while closed.
            Layout.topMargin: root.bodySpacing * Math.min(1, body.implicitHeight / root.bodySpacing)
            spacing: root.bodySpacing
        }
    }
}
