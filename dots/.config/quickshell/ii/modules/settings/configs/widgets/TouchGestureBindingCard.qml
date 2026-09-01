import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Rectangle {
    id: root

    property string title: ""
    property string description: ""
    property string origin: ""
    property string directionIcon: ""
    property string actionId: "none"
    property bool isHighlighted: false

    signal actionSelected(string newAction)
    signal cardHovered(string origin)

    radius: Appearance.rounding.normal
    color: isHighlighted
        ? Appearance.colors.colLayer3
        : Appearance.colors.colLayer2
    implicitHeight: layout.implicitHeight + 24
    Layout.fillWidth: true

    readonly property var currentAction: TouchGestureActionRegistry.actionById(actionId)

    Behavior on color {
        ColorAnimation { duration: 150 }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        onEntered: root.cardHovered(root.origin)
    }

    ColumnLayout {
        id: layout
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 12
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Rectangle {
                implicitWidth: 36
                implicitHeight: 36
                radius: Appearance.rounding.full
                color: Appearance.colors.colLayer3

                MaterialSymbol {
                    anchors.centerIn: parent
                    iconSize: Appearance.font.pixelSize.normal
                    text: root.directionIcon
                    color: Appearance.m3colors.m3primary
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                StyledText {
                    text: root.title
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnLayer2
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }

                StyledText {
                    text: root.description
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }
            }
        }

        StyledComboBox {
            id: actionPicker
            Layout.fillWidth: true
            buttonIcon: (root.currentAction && root.currentAction.icon) ? root.currentAction.icon : "block"
            // Only what this family can actually do. Offering an action whose surface the
            // family never loads produces a binding that recognises the swipe and then does
            // nothing, which reads as a broken touchscreen.
            readonly property var availableActions:
                TouchGestureActionRegistry.availableActionsForFamily(PanelFamily.current)

            model: availableActions.map(function(a) { return Translation.tr(a.name); })
            currentIndex: {
                for (var i = 0; i < actionPicker.availableActions.length; ++i) {
                    if (actionPicker.availableActions[i].id === root.actionId) {
                        return i;
                    }
                }
                return 0;
            }
            onActivated: function(index) {
                var act = actionPicker.availableActions[index];
                if (act) {
                    root.actionSelected(act.id);
                }
            }
        }
    }
}
