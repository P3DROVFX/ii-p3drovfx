import qs.modules.common
import qs.modules.common.widgets
import qs.modules.akebono.shelf.widgets
import qs.modules.common.dashboardWidgets.calendar
import QtQuick

Item {
    id: root
    property var shelf
    signal closeRequested()

    implicitWidth: 340
    implicitHeight: 336

    CalendarWidget {
        anchors.fill: parent
        anchors.margins: 14
        anchors.bottomMargin: 16
        entranceAnimationsEnabled: false
    }
}
