import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * The search field, built like the Cheatsheet mail sidebar's.
 *
 * An outlined pill rather than a filled box: the rail it sits in is already a filled
 * surface, and a second fill on top of it reads as a dent. The outline brightens on hover
 * and focus, and the surface behind it takes a five-percent tint on hover — the same two
 * signals, in the same order, that the mail sidebar gives.
 */
Rectangle {
    id: root

    property alias text: input.text
    property bool expanded: true
    property string placeholder: ""

    signal accepted(string text)
    signal cleared()

    implicitHeight: 56
    // Capped rather than a raw half-height: the project's rule for anything this tall.
    radius: NotesMetrics.pillRadius(root.implicitHeight)
    color: "transparent"
    border.width: 1
    border.color: hoverArea.containsMouse || input.activeFocus
        ? Appearance.colors.colOutline
        : Appearance.colors.colOutlineVariant

    Behavior on border.color {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(root)
    }

    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        color: Appearance.colors.colOnSurface
        opacity: hoverArea.containsMouse ? 0.05 : 0

        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
    }

    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.IBeamCursor
        onClicked: input.forceActiveFocus()

        // On hover, and only on hover. `StyledToolTip` reads `parent.hovered`, which a
        // `MouseArea` does not have, and an undefined read counts as hovered — so this
        // help line sat permanently on screen beside the rail, unhovered and unasked for.
        StyledToolTip {
            text: Translation.tr("Words search everything. Narrow it with tag:, notebook:, has:image, has:ink, is:favourite")
            extraVisibleCondition: hoverArea.containsMouse && input.text.length === 0
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: root.expanded ? 22 : 0
        anchors.rightMargin: root.expanded ? 8 : 0
        spacing: 8

        MaterialSymbol {
            Layout.fillWidth: !root.expanded
            horizontalAlignment: Text.AlignHCenter
            text: "search"
            iconSize: Appearance.font.pixelSize.huge
            color: Appearance.colors.colOnSurfaceVariant
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.expanded

            TextInput {
                id: input
                anchors.fill: parent
                verticalAlignment: TextInput.AlignVCenter
                font.family: Appearance.font.family.main
                font.pixelSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colOnSurface
                selectedTextColor: Appearance.m3colors.m3onSecondaryContainer
                selectionColor: Appearance.colors.colSecondaryContainer
                clip: true

                Keys.onReturnPressed: root.accepted(input.text)
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: root.placeholder
                font.pixelSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colOnSurfaceVariant
                visible: input.text.length === 0 && !input.activeFocus
            }
        }

        // Appears only when there is something to clear, and grows into place rather than
        // popping — the same treatment the mail sidebar gives its send button.
        Rectangle {
            id: clearButton
            Layout.preferredWidth: 40
            Layout.preferredHeight: 40
            Layout.alignment: Qt.AlignVCenter
            radius: Appearance.rounding.full
            color: clearArea.pressed ? Appearance.colors.colPrimaryActive
                : clearArea.containsMouse ? Appearance.colors.colPrimaryHover
                : Appearance.colors.colPrimary
            visible: root.expanded && input.text.length > 0

            scale: input.text.length === 0 ? 0
                : (clearArea.pressed ? 0.9 : clearArea.containsMouse ? 1.05 : 1.0)

            Behavior on scale {
                animation: Appearance.animation.clickBounce.numberAnimation.createObject(clearButton)
            }
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(clearButton)
            }

            MaterialSymbol {
                anchors.centerIn: parent
                text: "close"
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnPrimary
            }

            MouseArea {
                id: clearArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    input.text = "";
                    root.cleared();
                }
            }
        }
    }
}
