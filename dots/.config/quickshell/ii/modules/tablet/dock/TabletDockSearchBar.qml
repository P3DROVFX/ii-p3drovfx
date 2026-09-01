import QtQuick
import QtQuick.Layouts
import Quickshell

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * The search pill on the left of the dock.
 *
 * Shaped like the desktop's Android search widget — an outer capsule holding an inner pill
 * — so the two read as the same control in two places. It searches nothing itself: it is a
 * door, and it opens the app drawer with the field already focused, because the drawer's
 * search is where results belong on this family.
 */
Item {
    id: root

    property real barHeight: Appearance.sizes.minimumTouchTarget

    signal activated

    implicitHeight: root.barHeight

    Rectangle {
        id: capsule
        anchors.fill: parent
        radius: height / 2
        color: Appearance.colors.colLayer1

        Rectangle {
            id: innerPill
            anchors.fill: parent
            anchors.margins: Math.round(root.barHeight * 0.08)
            radius: height / 2
            color: tapArea.pressed ? Appearance.colors.colLayer2Active : Appearance.colors.colLayer2

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Math.round(root.barHeight * 0.34)
                anchors.rightMargin: Math.round(root.barHeight * 0.28)
                spacing: Math.round(root.barHeight * 0.24)

                MaterialSymbol {
                    text: "search"
                    iconSize: Math.round(root.barHeight * 0.46)
                    color: Appearance.colors.colOnLayer2
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Search")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                }

                MaterialSymbol {
                    text: "apps"
                    iconSize: Math.round(root.barHeight * 0.42)
                    color: Appearance.colors.colOnLayer2
                    opacity: 0.75
                }
            }
        }
    }

    MouseArea {
        id: tapArea
        anchors.fill: parent
        onClicked: root.activated()
    }
}
