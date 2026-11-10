import QtQuick
import qs.modules.common

/**
 * The plate of an extended app group: one big folder in the group's shape
 * and colour holding a 2x2 grid of members. The first three are full-size
 * icons a click opens directly; the fourth spot is the fourth app when the
 * group holds exactly four, else a mini group of the rest that opens the
 * group's popup. The group's name is the tile's own label, under the plate,
 * as for every other icon.
 *
 * It only draws. The tile owns the gesture and asks `spotAt()` which spot a
 * click landed on, so dragging, selection and the context menu stay the
 * tile's, exactly as for every other icon.
 */
Item {
    id: root
    required property var entry
    required property string shape
    required property color fill
    // The colour that reads on `fill`, for the hover plate and empty spots.
    required property color onFill
    property string mask: "none"
    property bool glass: false
    property color rim: "transparent"
    // Where the pointer is, in this item's coordinates, and whether it is.
    property point hoverPoint: Qt.point(0, 0)
    property bool hovering: false

    readonly property var apps: root.entry.apps ?? []
    // More than four members: the last spot gathers the rest.
    readonly property bool overflow: root.apps.length > 4
    readonly property bool round: root.shape === "circle" || root.shape === "cookie" || root.shape === "clover"
    readonly property real pad: root.width * 0.11
    readonly property real gap: root.width * 0.06
    readonly property real spotSize: (root.width - root.pad * 2 - root.gap) / 2

    function spotRect(i) {
        return Qt.rect(root.pad + (i % 2) * (root.spotSize + root.gap),
            root.pad + Math.floor(i / 2) * (root.spotSize + root.gap), root.spotSize, root.spotSize);
    }
    // 0..3, row by row; -1 off the spots (the rim and the gutters), so a
    // click between two apps never opens the wrong one.
    function spotAt(x, y) {
        const slack = root.gap / 2;
        for (let i = 0; i < 4; ++i) {
            const r = root.spotRect(i);
            if (x >= r.x - slack && x < r.x + r.width + slack && y >= r.y - slack && y < r.y + r.height + slack)
                return i;
        }
        return -1;
    }
    readonly property int hoveredSpot: root.hovering ? root.spotAt(root.hoverPoint.x, root.hoverPoint.y) : -1

    // The plate. A circle or a cookie this size would cut its own corner
    // spots, so the round shapes become a deeply rounded square.
    Rectangle {
        anchors.fill: parent
        radius: root.width * (root.round ? 0.36 : root.shape === "squircle" ? 0.28 : 0.2)
        color: root.fill
        border.width: root.glass ? 1 : 0
        border.color: root.rim
    }
    // The hovered spot's own plate, gliding between spots.
    Rectangle {
        readonly property rect r: root.spotRect(Math.max(0, root.hoveredSpot))
        readonly property real grow: root.gap * 0.4
        x: r.x - grow
        y: r.y - grow
        width: r.width + grow * 2
        height: r.height + grow * 2
        radius: root.round ? width / 2 : width * 0.3
        color: Qt.alpha(root.onFill, 0.12)
        opacity: root.hoveredSpot >= 0 ? 1 : 0
        visible: opacity > 0.001
        Behavior on x {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        Behavior on y {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
    }

    Repeater {
        model: 4
        delegate: Item {
            id: spot
            required property int index
            readonly property rect r: root.spotRect(index)
            readonly property bool mini: spot.index === 3 && root.overflow
            readonly property var app: spot.mini ? null : (root.apps[spot.index] ?? null)
            x: r.x
            y: r.y
            width: r.width
            height: r.height
            scale: root.hoveredSpot === spot.index ? 1.06 : 1
            Behavior on scale {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            DesktopGroupIcon {
                anchors.centerIn: parent
                width: parent.width * 0.9
                height: width
                visible: spot.app !== null
                app: spot.app
                mask: root.mask
            }
            DesktopGroupFace {
                anchors.fill: parent
                visible: spot.mini
                apps: spot.mini ? root.apps.slice(3, 7) : []
                shape: root.round ? "circle" : "squircle"
                fill: Qt.alpha(root.onFill, 0.1)
                mask: root.mask
            }
            // An empty spot is a faint ring, a place for the next app.
            Rectangle {
                anchors.centerIn: parent
                width: parent.width * 0.78
                height: width
                visible: spot.app === null && !spot.mini
                radius: root.round || root.mask === "circle" ? width / 2 : width * 0.28
                color: "transparent"
                border.width: 2
                border.color: Qt.alpha(root.onFill, 0.2)
            }
        }
    }
}
