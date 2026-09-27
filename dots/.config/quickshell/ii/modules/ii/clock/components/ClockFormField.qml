import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * A text field as the timetable's event rail draws its Title row: an expressive shape
 * with the icon, a small caption, and the input under it on one filled surface.
 */
Rectangle {
    id: root

    property string symbol: "title"
    property int shapeKind: MaterialShape.Shape.Cookie7Sided
    property string caption: ""
    property string placeholder: ""
    property alias text: input.text
    property alias input: input

    signal accepted()

    function focusInput(): void {
        input.forceActiveFocus();
        input.selectAll();
    }

    Layout.fillWidth: true
    implicitHeight: 66
    radius: Appearance.rounding.small
    color: input.activeFocus ? ClockStyle.colFieldHover : ClockStyle.colField

    Behavior on color {
        animation: ClockStyle.motionFast.colorAnimation.createObject(this)
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.IBeamCursor
        onClicked: input.forceActiveFocus()
    }

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
            rotation: input.activeFocus ? 20 : 0
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                text: root.caption
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.weight: Font.Bold
                color: ClockStyle.colOnSurfaceVariant
            }

            StyledTextInput {
                id: input
                Layout.fillWidth: true
                clip: true
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.Bold
                color: ClockStyle.colOnSurface
                onAccepted: root.accepted()

                StyledText {
                    anchors.fill: parent
                    visible: input.text.length === 0
                    verticalAlignment: Text.AlignVCenter
                    text: root.placeholder
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnLayer1Inactive
                }
            }
        }
    }
}
