import QtQuick
import QtQuick.Layouts

import qs.modules.common
import qs.modules.common.widgets

Rectangle {
    id: heroCardRoot

    Layout.fillWidth: true
    Layout.preferredHeight: implicitHeight
    Layout.preferredWidth: implicitWidth
    implicitWidth: compactMode ? 320 : 380
    implicitHeight: compactMode ? 100 : 180

    property bool adaptiveWidth: false
    property bool compactMode: false

    radius: Appearance.rounding.normal
    color: Appearance.colors.colPrimaryContainer

    property int margins: compactMode ? 16 : 24
    property int iconSize: compactMode ? 64 : 110
    property real iconFontSize: compactMode ? 32 : 48

    property string shapeString: "Cookie9Sided"
    property string icon: ""

    property string title: ""
    property string subtitle: ""
    property int titleSize: compactMode ? Appearance.font.pixelSize.hugeass * 1.5 : Appearance.font.pixelSize.hugeass * 2.5
    property int subtitleSize: compactMode ? Appearance.font.pixelSize.normal : Appearance.font.pixelSize.hugeass

    property string pillText: ""
    property string pillIcon: ""

    property color pillColor: Appearance.colors.colOnPrimary
    property color pillTextColor: Appearance.colors.colOnSecondaryContainer
    property color pillIconColor: Appearance.colors.colOnSecondaryContainer

    property color shapeColor: Appearance.colors.colPrimary
    property color symbolColor: Appearance.colors.colOnPrimary
    property color textColor: Appearance.colors.colOnPrimaryContainer

    property alias shapeContent: shapeItem.data
    property alias shapeRotation: shapeItem.rotation
    property int spacing: 16

    Item {
        width: heroCardRoot.iconSize
        height: heroCardRoot.iconSize
        anchors {
            verticalCenter: parent.verticalCenter
            left: parent.left
            margins: heroCardRoot.margins
        }

        MaterialShape {
            id: shapeItem
            shapeString: heroCardRoot.shapeString
            implicitSize: heroCardRoot.iconSize
            color: heroCardRoot.shapeColor
            anchors.centerIn: parent
        }

        MaterialSymbol {
            id: iconSymbol
            visible: heroCardRoot.icon !== "" && shapeItem.children.length === 0
            anchors.centerIn: parent
            text: heroCardRoot.icon
            iconSize: heroCardRoot.iconFontSize
            color: heroCardRoot.symbolColor
        }
    }

    Rectangle {
        visible: heroCardRoot.pillText !== "" && heroCardRoot.pillIcon !== ""
        implicitHeight: cityRow.implicitHeight + 12
        implicitWidth: cityRow.implicitWidth + 20
        radius: Appearance.rounding.full
        color: heroCardRoot.pillColor
        anchors {
            right: parent.right
            top: parent.top
            margins: heroCardRoot.margins
        }

        RowLayout {
            id: cityRow
            anchors.centerIn: parent
            spacing: 6

            MaterialSymbol {
                text: heroCardRoot.pillIcon
                iconSize: Appearance.font.pixelSize.small
                color: heroCardRoot.pillIconColor
            }
            StyledText {
                text: heroCardRoot.pillText
                font {
                    weight: Font.Bold
                    pixelSize: Appearance.font.pixelSize.small
                }
                color: heroCardRoot.pillTextColor
                elide: Text.ElideRight
                Layout.maximumWidth: 120
                Layout.topMargin: 1 // to center the text
            }
        }
    }

    StyledText {
        text: heroCardRoot.title
        font.pixelSize: heroCardRoot.titleSize
        font.family: Appearance.font.family.title
        font.weight: Font.Black
        color: heroCardRoot.textColor
        horizontalAlignment: Text.AlignRight
        anchors {
            verticalCenter: parent.verticalCenter
            verticalCenterOffset: 4
            right: parent.right
            margins: heroCardRoot.margins
        }
        width: 200
    }

    StyledText {
        text: heroCardRoot.subtitle
        anchors {
            right: parent.right
            bottom: parent.bottom
            margins: heroCardRoot.margins
        }
        font {
            pixelSize: heroCardRoot.subtitleSize
            family: Appearance.font.family.title
            weight: Font.Black
        }
        color: heroCardRoot.textColor
        horizontalAlignment: Text.AlignRight
        elide: Text.ElideRight
        width: 200
    }
}
