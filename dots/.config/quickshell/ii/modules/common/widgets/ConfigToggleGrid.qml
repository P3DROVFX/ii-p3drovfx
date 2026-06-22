import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

GridLayout {
    id: root
    Layout.fillWidth: true

    property var model: []
    property var currentValues: ({ })
    property int gridColumns: Math.max(1, Math.floor(parent ? parent.width / 280 : 280))
    property int cardSpacing: 12

    signal itemChanged(string key, var value)

    columns: root.gridColumns
    columnSpacing: root.cardSpacing
    rowSpacing: root.cardSpacing

    Repeater {
        model: root.model

        delegate: Rectangle {
            id: card
            Layout.fillWidth: true
            Layout.minimumWidth: 210
            implicitHeight: rowLayout.implicitHeight + 24
            radius: pressed ? Appearance.rounding.large : Appearance.rounding.normal
            color: pressed
                ? Appearance.colors.colLayer2Active
                : (hoverHandler.hovered
                    ? Appearance.colors.colLayer2Hover
                    : Appearance.colors.colLayer2)
            border.width: 0

            required property var modelData
            readonly property string itemKey: modelData.key || ""
            property bool pressed: false

            Behavior on color {
                ColorAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Appearance.animation.elementMoveFast.type
                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                }
            }

            Behavior on radius {
                NumberAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Appearance.animation.elementMoveFast.type
                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                }
            }

            Behavior on scale {
                NumberAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Appearance.animation.elementMoveFast.type
                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                }
            }

            scale: pressed ? 0.98 : (hoverHandler.hovered ? 1.01 : 1.0)
            transformOrigin: Item.Center

            MouseArea {
                anchors.fill: parent
                hoverEnabled: false
                cursorShape: Qt.ArrowCursor
                onPressed: card.pressed = true
                onReleased: card.pressed = false
                onCanceled: card.pressed = false
            }

            RowLayout {
                id: rowLayout
                anchors {
                    fill: parent
                    leftMargin: 14
                    rightMargin: 14
                    topMargin: 12
                    bottomMargin: 12
                }
                spacing: 12

                MaterialShapeWrappedMaterialSymbol {
                    id: iconShape
                    Layout.alignment: Qt.AlignVCenter
                    iconSize: Appearance.font.pixelSize.normal
                    shape: MaterialShape.Shape.Circle
                    padding: 9
                    fill: card.modelData.icon ? 1 : 0
                    color: Appearance.colors.colSurfaceContainerHigh
                    colSymbol: Appearance.colors.colOnSurfaceVariant
                    text: card.modelData.icon || ""
                }

                StyledText {
                    Layout.alignment: Qt.AlignVCenter
                    text: card.modelData.name || ""
                    font.weight: Font.DemiBold
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnLayer2
                    verticalAlignment: Text.AlignVCenter
                }

                Item { Layout.fillWidth: true }

                ConfigSelectionArray {
                    Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                    currentValue: root.currentValues[card.itemKey]
                    onSelected: newValue => root.itemChanged(card.itemKey, newValue)
                    options: card.modelData.options || []
                }
            }

            HoverHandler {
                id: hoverHandler
            }
        }
    }
}
