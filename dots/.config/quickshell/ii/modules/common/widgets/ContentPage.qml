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
        maskSource: Rectangle {
            width: root.width
            height: root.height
            radius: Appearance.rounding.normal
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
        spacing: 30
    }

}
