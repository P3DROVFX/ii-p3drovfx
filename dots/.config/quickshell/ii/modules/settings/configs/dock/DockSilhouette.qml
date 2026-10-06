pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common
import qs.modules.common.widgets

/**
 * A dock style's silhouette against the bottom edge of a screen, for the style
 * cards (a light tray on the dark screen, so it reads on any card): the tray's outline as Dock.qml draws it (floating off the edge, islands,
 * hugging it, the notch, full width with or without the inward corners) with dots
 * standing for the icons. `swell` (0..1) lifts and widens the tray a little.
 */
Item {
    id: root

    property string styleName: "floating"
    property real swell: 0

    readonly property bool attached: ["hug", "dynamic_island", "full_width", "full_width_concave"].indexOf(root.styleName) >= 0
    readonly property bool fullWidth: root.styleName === "full_width" || root.styleName === "full_width_concave"
    readonly property real trayHeight: Math.round(18 + 3 * root.swell)
    readonly property real trayWidth: root.fullWidth ? root.width : Math.round(root.width * (0.64 + 0.06 * root.swell))
    readonly property real trayY: root.height - root.trayHeight - (root.attached ? 0 : Math.round(6 + 2 * root.swell))
    property color trayColor: Appearance.colors.colOnSurfaceVariant
    property color dotColor: Appearance.colors.colLayer0
    property color accentColor: Appearance.colors.colPrimary
    readonly property real dot: 5

    // Floating, hug, full width: one tray.
    Rectangle {
        visible: root.styleName !== "islands" && root.styleName !== "transparent" && root.styleName !== "dynamic_island"
        x: (root.width - width) / 2
        y: root.trayY
        width: root.trayWidth
        height: root.trayHeight
        color: root.trayColor
        topLeftRadius: root.fullWidth ? 0 : root.trayHeight / 2
        topRightRadius: root.fullWidth ? 0 : root.trayHeight / 2
        bottomLeftRadius: root.attached ? 0 : root.trayHeight / 2
        bottomRightRadius: root.attached ? 0 : root.trayHeight / 2
    }

    // Full width · rounded: the screen curves into the tray at both sides.
    Repeater {
        model: root.styleName === "full_width_concave" ? 2 : 0
        delegate: RoundCorner {
            required property int index
            implicitSize: 9
            color: root.trayColor
            corner: index === 0 ? RoundCorner.CornerEnum.BottomLeft : RoundCorner.CornerEnum.BottomRight
            x: index === 0 ? 0 : root.width - width
            y: root.trayY - height + 1
        }
    }

    // The notch, flared into the bottom edge.
    Notch {
        id: notch
        visible: root.styleName === "dynamic_island"
        x: (root.width - width) / 2
        y: root.trayY
        width: root.trayWidth
        height: root.trayHeight
        bodyWidth: width
        bodyHeight: height
        disableBehaviors: true
        topRadius: 7
        bottomRadius: root.trayHeight / 2
        fillColor: root.trayColor
        transform: Scale {
            yScale: -1
            origin.y: notch.height / 2
        }
    }

    // Islands: apps, a widget, the actions — each on its own.
    Row {
        visible: root.styleName === "islands"
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.trayY
        spacing: 4
        Repeater {
            // [share of the width, icons, a widget?]
            model: [[0.34, 3, false], [0.2, 1, true], [0.12, 1, false]]
            delegate: Rectangle {
                id: island
                required property var modelData
                width: Math.round(root.width * island.modelData[0] * (1 + 0.08 * root.swell))
                height: root.trayHeight
                radius: height / 2
                color: root.trayColor
                Row {
                    anchors.centerIn: parent
                    spacing: 5
                    Repeater {
                        model: island.modelData[1]
                        delegate: Rectangle {
                            width: island.modelData[2] ? root.dot * 3 : root.dot
                            height: root.dot
                            radius: root.dot / 2
                            color: island.modelData[2] ? root.accentColor : root.dotColor
                            opacity: island.modelData[2] ? 1 : 0.7
                        }
                    }
                }
            }
        }
    }

    // The icons.
    Row {
        visible: root.styleName !== "islands"
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.trayY + (root.trayHeight - root.dot) / 2
        spacing: root.styleName === "islands" ? 6 : 5
        Repeater {
            model: 6
            delegate: Rectangle {
                required property int index
                width: index === 3 ? root.dot * 3 : root.dot
                height: root.dot
                radius: root.dot / 2
                color: index === 3 ? root.accentColor : root.dotColor
                opacity: index === 3 ? 1 : 0.7
            }
        }
    }
}
