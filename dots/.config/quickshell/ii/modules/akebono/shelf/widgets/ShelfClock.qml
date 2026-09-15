pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.akebono
import QtQuick
import QtQuick.Layouts
import "../../../ii/bar/widgets/clock"

Item {
    id: root
    property real barHeight: 54
    property var shelf
    // "default" | "material" (same widget) | "expressive" | "neural" | "relief"
    property string style: "default"

    readonly property bool shelfEmpty: false
    readonly property bool paddingless: root.style !== "default"
    readonly property real pillHeight: Math.max(root.barHeight * 0.7, Appearance.sizes.baseBarHeight)

    implicitWidth: Math.max(clockHolder.item?.implicitWidth ?? 0, root.pillHeight) + (root.paddingless ? 0 : 16)
    implicitHeight: root.pillHeight

    Component.onCompleted: {
        if (root.shelf)
            root.shelf.registerClockAnchor(root);
    }
    Component.onDestruction: {
        if (root.shelf && root.shelf.clockAnchor === root)
            root.shelf.unregisterClockAnchor(root);
    }

    ShelfPill {
        anchors.fill: parent
        visible: !root.paddingless && !(Config.options.akebono?.shelf.popupsDetached ?? false)
    }

    Loader {
        id: clockHolder
        anchors.centerIn: parent
        sourceComponent: root.style === "expressive" ? expressiveComp
            : root.style === "neural" ? neuralComp
            : root.style === "relief" ? reliefComp
            : defaultComp
    }

    Component {
        id: defaultComp
        ClockWidget {
            vertical: false
            disablePopup: true
        }
    }

    Component {
        id: expressiveComp
        ExpressiveClockWidget {
            disablePopup: true
        }
    }

    Component {
        id: neuralComp
        NeuralClockWidget {
            disablePopup: true
        }
    }

    Component {
        id: reliefComp
        ReliefClockWidget {
            disablePopup: true
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.shelf?.toggleCalendar()
    }
}