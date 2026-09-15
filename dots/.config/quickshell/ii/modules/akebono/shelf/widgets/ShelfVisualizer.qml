import qs.services
import qs.modules.common
import qs.modules.akebono
import QtQuick
import QtQuick.Layouts
import "../../../ii/bar/widgets/visualizer"

Item {
    id: root
    property real barHeight: 54
    property var shelf

    implicitWidth: pill.implicitWidth
    implicitHeight: barHeight * 0.7
    Layout.alignment: Qt.AlignVCenter

    ShelfPill {
        id: pill
        anchors.verticalCenter: parent.verticalCenter
        implicitWidth: viz.implicitWidth + 16
        implicitHeight: root.barHeight * 0.7

        Visualizer {
            id: viz
            anchors.centerIn: parent
            barCount: 10
            dotSize: 3
            dotSpacing: 3
            maxBarHeight: pill.height - 8
        }
    }
}