pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.akebono
import QtQuick
import QtQuick.Layouts
import "../../../ii/bar/widgets/power"

// Power chip on the shelf. Renders the same bar power variant the bar uses for
// the configured power style; only "default" sits inside a shelf pill (dot,
// solid and expressive draw their own). Every variant already toggles the
// session popup on press, exactly what the shelf chip should do.
Item {
    id: root
    property real barHeight: 54
    property var shelf
    // "default" | "solid" | "dot" | "expressive"
    property string style: "default"

    readonly property bool paddingless: root.style !== "default"
    readonly property real pillHeight: Math.max(root.barHeight * 0.7, Appearance.sizes.baseBarHeight)

    implicitWidth: (powerHolder.item?.implicitWidth ?? 0) + (root.paddingless ? 0 : 14)
    implicitHeight: root.pillHeight
    Layout.alignment: Qt.AlignVCenter

    ShelfPill {
        id: pill
        anchors.fill: parent
        visible: !root.paddingless
        hovered: powerHover.hovered
    }

    Loader {
        id: powerHolder
        anchors.centerIn: parent
        sourceComponent: root.style === "solid" ? powerSolid
            : root.style === "dot" ? powerDot
            : root.style === "expressive" ? powerExpressive
            : powerDefault
    }

    Component {
        id: powerDefault
        PowerButton {
            vertical: false
        }
    }

    Component {
        id: powerSolid
        SolidPowerButton {
            vertical: false
        }
    }

    Component {
        id: powerDot
        DotPowerButton {
            vertical: false
        }
    }

    Component {
        id: powerExpressive
        ExpressivePowerButton {
            vertical: false
        }
    }

    HoverHandler {
        id: powerHover
        cursorShape: Qt.PointingHandCursor
    }
}