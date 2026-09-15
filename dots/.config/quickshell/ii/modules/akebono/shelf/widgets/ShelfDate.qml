pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.akebono
import QtQuick
import QtQuick.Layouts
import "../../../ii/bar/widgets/date"

// Date chip on the shelf. Renders the bar date variant for the configured
// style; "default" sits inside a shelf pill, the expressive/neural variants
// paint their own surface. Click opens the shelf's calendar popup.
Item {
    id: root
    property real barHeight: 54
    property var shelf
    // "default" | "expressive" | "neural"
    property string style: "default"

    readonly property bool paddingless: root.style !== "default"
    readonly property real pillHeight: Math.max(root.barHeight * 0.7, Appearance.sizes.baseBarHeight)

    implicitWidth: (dateHolder.item?.implicitWidth ?? 0) + (root.paddingless ? 0 : 14)
    implicitHeight: root.pillHeight
    Layout.alignment: Qt.AlignVCenter

    ShelfPill {
        id: pill
        anchors.fill: parent
        visible: !root.paddingless
        hovered: dateMouse.containsMouse

        Component.onCompleted: root.shelf.registerClockAnchor(pill)
        Component.onDestruction: root.shelf.unregisterClockAnchor(pill)
        onXChanged: root.shelf.publishClock()
    }

    Loader {
        id: dateHolder
        anchors.centerIn: parent
        sourceComponent: root.style === "expressive" ? dateExpressive
            : root.style === "neural" ? dateNeural
            : dateDefault
    }

    Component {
        id: dateDefault
        DateWidget {
            vertical: false
            disablePopup: true
        }
    }

    Component {
        id: dateExpressive
        ExpressiveDateWidget {
            vertical: false
            disablePopup: true
        }
    }

    Component {
        id: dateNeural
        NeuralDateWidget {
            vertical: false
            disablePopup: true
        }
    }

    MouseArea {
        id: dateMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.shelf?.toggleCalendar()
    }
}