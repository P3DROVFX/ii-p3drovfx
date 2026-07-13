import QtQuick
import QtQuick.Layouts

import qs.modules.common
import qs.modules.common.widgets

Rectangle {
    id: root

    Layout.fillWidth: true
    implicitHeight: 64
    radius: Appearance.rounding.full

    color: containerColor

    property string shapeString: "Circle"
    property int shapeSize: 40
    property string icon: ""

    property color containerColor: Appearance.colors.colSecondaryContainer
    property color shapeColor: Appearance.colors.colSecondary
    property color symbolColor: Appearance.colors.colOnSecondary
    property color textColor: Appearance.colors.colOnSecondaryContainer

    default property alias shapeContent: shapeItem.children
    property alias text: pillText.text
    property alias textContent: textContainer.children

    MaterialShape {
        id: shapeItem
        shapeString: root.shapeString
        implicitSize: root.shapeSize
        color: root.shapeColor
        anchors {
            left: parent.left
            leftMargin: 12
            verticalCenter: parent.verticalCenter
        }

        MaterialSymbol {
            id: iconSymbol
            visible: root.icon !== "" && shapeItem.children.length <= 1
            anchors.centerIn: parent
            text: root.icon
            iconSize: Appearance.font.pixelSize.large
            color: root.symbolColor
        }
    }

    Item {
        id: textContainer
        anchors {
            verticalCenter: parent.verticalCenter
            horizontalCenter: parent.horizontalCenter
            horizontalCenterOffset: 9
        }

        StyledText {
            id: pillText
            anchors.centerIn: parent
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            font.weight: Font.Bold
            color: root.textColor
            visible: text !== "" && textContainer.children.length <= 1
        }
    }
}

