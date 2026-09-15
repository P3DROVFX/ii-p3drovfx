import qs.modules.common
import qs.modules.common.widgets
import qs.modules.akebono
import QtQuick
import "../../../ii/bar/widgets/indicators"

Item {
    id: root

    property real barHeight: 54
    readonly property real pillHeight: root.barHeight * 0.7

    readonly property bool shelfEmpty: !(recordIndicator.activelyRecording || recordIndicator.isLoading)

    implicitWidth: recordIndicator.shown ? root.pillHeight : 0
    implicitHeight: root.pillHeight

    ShelfPill {
        id: pill
        anchors.fill: parent
    }

    RecordIndicator {
        id: recordIndicator
        anchors.centerIn: parent
        height: root.pillHeight
    }
}