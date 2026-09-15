import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

import qs.modules.common
import qs.modules.common.widgets

/**
 * One non-app search result: clipboard entry, file, tool.
 *
 * A row rather than a grid tile, because these have text worth reading. Sized to the
 * family's touch minimum with room to spare — the drawer has a whole screen, and a result
 * you have to aim at is a result you will not use.
 */
Item {
    id: root

    property string symbol: ""
    property string iconPath: ""
    property string title: ""
    property string subtitle: ""

    signal activated

    implicitHeight: Math.max(Appearance.sizes.minimumTouchTarget + 16, 64)

    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.normal
        color: tapArea.pressed ? Appearance.colors.colLayer2Active : "transparent"

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        spacing: 16

        Rectangle {
            Layout.preferredWidth: 44
            Layout.preferredHeight: 44
            radius: width / 2
            color: Appearance.colors.colLayer2
            visible: root.iconPath.length === 0

            MaterialSymbol {
                anchors.centerIn: parent
                text: root.symbol
                iconSize: 22
                color: Appearance.colors.colOnLayer2
            }
        }

        IconImage {
            Layout.preferredWidth: 44
            Layout.preferredHeight: 44
            visible: root.iconPath.length > 0
            source: root.iconPath
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            StyledText {
                Layout.fillWidth: true
                text: root.title
                font.pixelSize: Appearance.font.pixelSize.normal
                color: Appearance.m3colors.m3onSurface
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            StyledText {
                Layout.fillWidth: true
                visible: root.subtitle.length > 0
                text: root.subtitle
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                elide: Text.ElideRight
                maximumLineCount: 1
            }
        }
    }

    MouseArea {
        id: tapArea
        anchors.fill: parent
        onClicked: root.activated()
    }
}
