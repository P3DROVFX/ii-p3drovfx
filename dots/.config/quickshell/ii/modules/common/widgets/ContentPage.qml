import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import Qt5Compat.GraphicalEffects

StyledFlickable {
    id: root
    anchors.fill: parent
    property real baseWidth: 600
    property bool forceWidth: false
    property real bottomContentPadding: 100

    default property alias contentData: contentColumn.data

    clip: true
    layer.enabled: true
    layer.effect: OpacityMask {
        maskSource: Item {
            id: maskRoot
            width: root.width
            height: root.height

            property bool fadeEnabled: Config.options?.appearance?.scrollFadeMask ?? true
            property color topFadeColor: (fadeEnabled && !root.atYBeginning) ? "transparent" : "white"
            property color bottomFadeColor: (fadeEnabled && !root.atYEnd) ? "transparent" : "white"

            Behavior on topFadeColor {
                ColorAnimation { duration: 200; easing.type: Easing.OutQuad }
            }
            Behavior on bottomFadeColor {
                ColorAnimation { duration: 200; easing.type: Easing.OutQuad }
            }

            Column {
                anchors.fill: parent
                spacing: 0

                Rectangle {
                    width: parent.width
                    height: Math.min(36, parent.height / 2)
                    topLeftRadius: Appearance.rounding.normal
                    topRightRadius: Appearance.rounding.normal
                    color: "transparent"
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: maskRoot.topFadeColor }
                        GradientStop { position: 1.0; color: "white" }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: Math.max(0, parent.height - Math.min(36, parent.height / 2) * 2)
                    color: "white"
                }

                Rectangle {
                    width: parent.width
                    height: Math.min(36, parent.height / 2)
                    bottomLeftRadius: Appearance.rounding.normal
                    bottomRightRadius: Appearance.rounding.normal
                    color: "transparent"
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "white" }
                        GradientStop { position: 1.0; color: maskRoot.bottomFadeColor }
                    }
                }
            }
        }
    }
    contentHeight: contentColumn.implicitHeight + root.bottomContentPadding // Add some padding at the bottom
    implicitWidth: contentColumn.implicitWidth
    flickableDirection: Flickable.VerticalFlick
    
    ColumnLayout {
        id: contentColumn
        width: root.forceWidth ? root.baseWidth : (parent ? parent.width - (anchors.leftMargin + anchors.rightMargin) : 600)
        anchors {
            top: parent.top
            left: root.forceWidth ? undefined : parent.left
            right: root.forceWidth ? undefined : parent.right
            horizontalCenter: root.forceWidth ? parent.horizontalCenter : undefined
            leftMargin: root.forceWidth ? 20 : 0
            rightMargin: root.forceWidth ? 20 : 0
            topMargin: root.forceWidth ? 20 : 0
            bottomMargin: root.forceWidth ? 20 : 0
        }
        spacing: 12
    }

}
