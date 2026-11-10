pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * How the last action on one finding went, from HealthService.actions: a loading
 * shape while it runs, then a tick, a dash for a dismissed password prompt, or the
 * error in the error colour. Takes no room when there is nothing to say.
 */
RowLayout {
    id: root

    property string findingId: ""
    property color colContent: ClockStyle.colOnSurface
    property int textSize: ClockStyle.textSmall

    readonly property var action: HealthService.action(root.findingId)
    readonly property bool busy: root.action?.state === "running" || root.action?.state === "waiting"
    readonly property bool bad: root.action?.state === "failed" || root.action?.state === "stillFailing"
    readonly property color colShown: root.bad ? ClockStyle.colError : root.colContent

    visible: root.action !== null
    spacing: ClockStyle.gapTiny

    MaterialLoadingIndicator {
        Layout.alignment: Qt.AlignVCenter
        visible: root.busy
        loading: root.busy
        implicitSize: root.textSize + 8
        color: "transparent"
        shapeColor: root.colContent
    }

    MaterialSymbol {
        Layout.alignment: Qt.AlignVCenter
        visible: !root.busy
        text: root.bad ? "error" : root.action?.state === "cancelled" ? "do_not_disturb_on" : "check_circle"
        iconSize: root.textSize + 4
        fill: 1
        color: root.colShown
    }

    StyledText {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        text: HealthService.actionText(root.action)
        wrapMode: Text.Wrap
        maximumLineCount: 3
        elide: Text.ElideRight
        font.pixelSize: root.textSize
        color: root.colShown
    }
}
