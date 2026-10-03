import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

// One step of a guided setup: shape badge (number, or a check once done), title,
// explanation, an optional command to copy, and actions. Consecutive steps in a
// ColumnLayout (spacing 2) read as one connected group; mark the ends with
// `first` and `last`. Inside a settings ContentSection, set `dynamicRadius`
// instead: the step then rounds like the switches around it (GroupPosition).
Rectangle {
    id: step

    required property int number
    required property bool done
    required property string title
    property string body: ""
    property color bodyColor: Appearance.colors.colSubtext
    property string command: ""
    property string commandCaption: ""
    property string secondBody: ""
    property string secondCommand: ""
    property bool first: false
    property bool last: false
    property bool dynamicRadius: false
    default property alias actions: actionRow.data

    readonly property GroupPosition groupPosition: GroupPosition {
        item: step
        enabled: step.dynamicRadius
    }
    readonly property bool roundTop: step.dynamicRadius ? step.groupPosition.isFirst : step.first
    readonly property bool roundBottom: step.dynamicRadius ? step.groupPosition.isLast : step.last

    Layout.fillWidth: true
    implicitHeight: stepRow.implicitHeight + 24
    color: Appearance.colors.colLayer2
    topLeftRadius: step.roundTop ? Appearance.rounding.large : Appearance.rounding.verysmall
    topRightRadius: step.roundTop ? Appearance.rounding.large : Appearance.rounding.verysmall
    bottomLeftRadius: step.roundBottom ? Appearance.rounding.large : Appearance.rounding.verysmall
    bottomRightRadius: step.roundBottom ? Appearance.rounding.large : Appearance.rounding.verysmall

    RowLayout {
        id: stepRow
        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
            margins: 16
        }
        spacing: 14

        MaterialShapeWrappedMaterialSymbol {
            Layout.alignment: Qt.AlignTop
            text: step.done ? "check" : ["looks_one", "looks_two", "looks_3", "looks_4", "looks_5", "looks_6"][step.number - 1] ?? "circle"
            shape: step.done ? MaterialShape.Shape.Cookie9Sided : MaterialShape.Shape.Circle
            iconSize: 20
            padding: 8
            color: step.done ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
            colSymbol: step.done ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            StyledText {
                Layout.fillWidth: true
                text: step.title
                color: Appearance.colors.colOnLayer2
                font {
                    family: Appearance.font.family.title
                    variableAxes: Appearance.font.variableAxes.titleRounded
                    pixelSize: Appearance.font.pixelSize.normal
                }
            }
            StyledText {
                visible: step.body.length > 0
                Layout.fillWidth: true
                text: step.body
                wrapMode: Text.WordWrap
                color: step.bodyColor
                font.pixelSize: Appearance.font.pixelSize.small
            }
            StyledText {
                visible: step.commandCaption.length > 0 && step.command.length > 0
                text: step.commandCaption
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.Bold
            }
            CommandChip {
                visible: step.command.length > 0
                command: step.command
            }
            StyledText {
                visible: step.secondBody.length > 0
                Layout.fillWidth: true
                text: step.secondBody
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.small
            }
            CommandChip {
                visible: step.secondCommand.length > 0
                command: step.secondCommand
            }
            RowLayout {
                id: actionRow
                visible: children.length > 0
                spacing: 6
            }
        }
    }
}
