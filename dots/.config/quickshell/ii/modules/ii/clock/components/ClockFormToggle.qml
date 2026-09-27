import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * An on/off row, the timetable rail's "All day": the whole row fills with the secondary
 * container when on, its shape swaps to the tertiary pair and turns, and the switch sits
 * on the same hue family as the row it belongs to.
 */
Rectangle {
    id: root

    property string symbol: ""
    property int shapeKind: MaterialShape.Shape.Sunny
    property string label: ""
    property string description: ""
    property bool checked: false

    signal toggled(bool checked)

    Layout.fillWidth: true
    implicitHeight: Math.max(56, textColumn.implicitHeight + 20)
    radius: Appearance.rounding.small
    color: root.checked ? ClockStyle.colSecondaryContainer
        : pointer.containsMouse ? ClockStyle.colFieldHover : ClockStyle.colField

    Behavior on color {
        animation: ClockStyle.motionFast.colorAnimation.createObject(this)
    }

    MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled(!root.checked)
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        spacing: 10

        MaterialShapeWrappedMaterialSymbol {
            text: root.symbol
            iconSize: 18
            padding: 9
            shape: root.shapeKind
            color: root.checked ? ClockStyle.colTertiary : ClockStyle.colPrimaryContainer
            colSymbol: root.checked ? ClockStyle.colOnTertiary : ClockStyle.colOnPrimaryContainer
            rotation: root.checked ? 30 : 0
        }

        ColumnLayout {
            id: textColumn
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                text: root.label
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.Bold
                color: root.checked ? ClockStyle.colOnSecondaryContainer : ClockStyle.colOnSurface
                elide: Text.ElideRight
            }

            StyledText {
                Layout.fillWidth: true
                visible: root.description.length > 0
                text: root.description
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: root.checked ? ClockStyle.colOnSecondaryContainer : ClockStyle.colOnSurfaceVariant
                opacity: 0.85
                elide: Text.ElideRight
            }
        }

        StyledSwitch {
            checked: root.checked
            checkable: false
            activeColor: ClockStyle.colOnSecondaryContainer
            activeThumbColor: ClockStyle.colSecondaryContainer
            onClicked: root.toggled(!root.checked)
        }
    }
}
