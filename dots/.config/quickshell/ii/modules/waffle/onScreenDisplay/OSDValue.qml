import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.waffle.looks

WBarAttachedPanelContent {
    id: root
    required property string iconName
    property string materialSymbol: ""
    property real value
    property bool showNumber: true

    property Timer timer: Timer {
        id: autoCloseTimer
        running: true
        interval: Config.options.osd.timeout
        repeat: false
        onTriggered: {
            root.close();
        }
    }

    contentItem: WPane {
        anchors.centerIn: parent
        borderColor: Looks.colors.ambientShadow

        contentItem: Item {
            // color: Looks.colors.bg1Base
            // radius: Looks.radius.medium
            implicitWidth: root.showNumber ? 192 : 170
            implicitHeight: 46

            RowLayout {
                id: contentRow
                anchors.fill: parent
                anchors.margins: 12

                spacing: 12

                MaterialShapeWrappedMaterialSymbol {
                    id: osdIcon
                    Layout.alignment: Qt.AlignVCenter
                    iconSize: 18
                    padding: 6
                    shape: MaterialShape.Shape.Cookie7Sided
                    text: root.materialSymbol

                    rotation: root.value * 360

                    Behavior on rotation {
                        NumberAnimation {
                            duration: 350
                            easing.type: Easing.OutBack
                            easing.overshoot: 1.5
                        }
                    }

                    color: root.value > 1.0 ? Appearance.colors.colErrorContainer : Appearance.colors.colSecondaryContainer
                    colSymbol: root.value > 1.0 ? Appearance.m3colors.m3onErrorContainer : Appearance.colors.colOnSecondaryContainer

                    Behavior on color {
                        ColorAnimation { duration: 150 }
                    }
                    Behavior on colSymbol {
                        ColorAnimation { duration: 150 }
                    }
                }

                WProgressBar {
                    id: progressBar
                    value: root.value
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    Layout.rightMargin: root.showNumber ? 0 : 3
                }

                WTextWithFixedWidth {
                    visible: root.showNumber
                    text: Math.round(root.value * 100)
                    // longestText: "100"
                    implicitWidth: 16
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }
    }
}
