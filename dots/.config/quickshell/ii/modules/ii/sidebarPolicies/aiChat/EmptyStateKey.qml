pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

/**
 * One line of the empty state: what the key is, and what it does.
 *
 * Shared between the sidebar chat and the Search AI panel, so a hint added
 * to one empty state does not have to be re-typeset for the other.
 */
Rectangle {
    id: root

    property var keys: []
    property string label: ""
    /** Set when pressing the row does the same thing the key does. */
    property bool actionable: false

    signal triggered

    implicitHeight: Math.round(Appearance.font.pixelSize.huge * 1.6)
    radius: Appearance.rounding.full
    color: rowMouse.containsMouse && root.actionable ? Appearance.colors.colLayer2Hover : "transparent"

    Behavior on color {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
    }

    MouseArea {
        id: rowMouse
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.actionable
        cursorShape: root.actionable ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.triggered()
    }

    RowLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Appearance.rounding.unsharpenmore
        anchors.rightMargin: Appearance.rounding.small
        spacing: Appearance.rounding.unsharpenmore

        Repeater {
            model: ScriptModel {
                values: root.keys
            }

            delegate: Rectangle {
                id: keyCap
                required property var modelData

                implicitWidth: Math.max(keyCapLabel.implicitWidth + Appearance.rounding.small, root.implicitHeight * 0.66)
                implicitHeight: Math.round(root.implicitHeight * 0.66)
                radius: Appearance.rounding.verysmall
                color: Appearance.colors.colLayer2

                StyledText {
                    id: keyCapLabel
                    anchors.centerIn: parent
                    text: keyCap.modelData
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnLayer2
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            text: root.label
            elide: Text.ElideRight
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
    }
}
