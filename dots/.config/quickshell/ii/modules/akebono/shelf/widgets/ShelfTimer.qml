import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import "../../../ii/bar/widgets/timer"

Item {
    id: root

    property real barHeight: 54
    property string style: "default"

    readonly property real pillHeight: root.barHeight * 0.7
    readonly property bool shelfEmpty: !timerHolder.item?.compVisible

    implicitWidth: timerHolder.item?.compVisible ? timerHolder.item?.implicitWidth ?? 0 : 0
    implicitHeight: root.pillHeight

    Loader {
        id: timerHolder
        anchors.centerIn: parent
        sourceComponent: root.style === "expressive" ? expressiveComp : defaultComp
    }

    Component {
        id: defaultComp
        TimerWidget {
            width: implicitWidth
            height: root.pillHeight
        }
    }

    Component {
        id: expressiveComp
        ExpressiveTimerWidget {
            width: implicitWidth
            height: root.pillHeight
        }
    }
}