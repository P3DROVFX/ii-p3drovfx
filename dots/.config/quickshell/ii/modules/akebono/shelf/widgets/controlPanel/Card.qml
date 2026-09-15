import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.akebono

Squircle {
    id: card
    default property alias content: cardCol.data
    radius: 22
    smoothing: AkebonoAppearance.squircleSmoothing
    color: Appearance.colors.colLayer2
    implicitHeight: cardCol.implicitHeight + 26

    ColumnLayout {
        id: cardCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 15
        anchors.rightMargin: 15
        spacing: 12
    }
}
