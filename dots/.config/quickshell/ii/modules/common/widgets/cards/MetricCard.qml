import QtQuick
import QtQuick.Layouts

import qs.modules.common
import qs.modules.common.widgets

Rectangle {
    id: root

    radius: Appearance.rounding.normal
    color: Appearance.colors.colSurfaceContainerHigh
    implicitWidth: root.elideText ? 0 : rowLayout.implicitWidth + 24
    implicitHeight: rowLayout.implicitHeight + 20
    Layout.fillWidth: true
    Layout.minimumWidth: root.elideText ? 0 : root.implicitWidth

    property alias title: title.text
    property alias value: value.text
    property string symbol: ""
    property string shapeString: "Slanted"
    property color accentColor: Appearance.colors.colPrimaryContainer
    property color symbolColor: Appearance.colors.colOnPrimaryContainer
    property bool elideText: false
    
    // Internal animation control
    property bool startAnim: false
    property int animDelay: 0
    
    onStartAnimChanged: {
        if (startAnim) {
            // Reset internal elements
            iconShape.scale = 0.8;
            iconShape.rotation = -10;
            title.opacity = 0.0;
            value.opacity = 0.0;
            
            Qt.callLater(function() {
                iconAnim.start();
                titleAnim.start();
                valueAnim.start();
            });
        }
    }

    RowLayout {
        id: rowLayout
        spacing: 12
        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
            leftMargin: 12
            rightMargin: 12
        }

        MaterialShape {
            id: iconShape
            shapeString: root.shapeString
            implicitSize: 36
            color: root.accentColor

            MaterialSymbol {
                id: symbolIcon
                anchors.centerIn: parent
                text: root.symbol
                fill: 0
                iconSize: Appearance.font.pixelSize.normal
                color: root.symbolColor
            }
            
            SequentialAnimation {
                id: iconAnim
                PauseAnimation { duration: root.animDelay + 60 }
                ParallelAnimation {
                    NumberAnimation { target: iconShape; property: "scale"; from: 0.8; to: 1.0; duration: 350; easing.type: Easing.OutBack }
                    NumberAnimation { target: iconShape; property: "rotation"; from: -10; to: 0; duration: 350; easing.type: Easing.OutCubic }
                }
            }
        }

        ColumnLayout {
            spacing: -2
            Layout.fillWidth: root.elideText
            Layout.minimumWidth: 0

            StyledText {
                id: title
                Layout.fillWidth: root.elideText
                Layout.minimumWidth: 0
                elide: root.elideText ? Text.ElideRight : Text.ElideNone
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnSurfaceVariant
                font.weight: Font.DemiBold
                
                SequentialAnimation {
                    id: titleAnim
                    PauseAnimation { duration: root.animDelay + 120 }
                    NumberAnimation { target: title; property: "opacity"; from: 0.0; to: 1.0; duration: 250 }
                }
            }

            StyledText {
                id: value
                Layout.fillWidth: root.elideText
                Layout.minimumWidth: 0
                elide: root.elideText ? Text.ElideRight : Text.ElideNone
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnSurface
                font.weight: Font.Bold
                
                SequentialAnimation {
                    id: valueAnim
                    PauseAnimation { duration: root.animDelay + 180 }
                    NumberAnimation { target: value; property: "opacity"; from: 0.0; to: 1.0; duration: 250 }
                }
            }
            
            Item {
                Layout.fillWidth: true
            }
        }
    }
}
