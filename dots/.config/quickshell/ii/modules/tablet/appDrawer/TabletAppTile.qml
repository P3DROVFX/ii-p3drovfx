import QtQuick
import Quickshell
import Quickshell.Widgets

import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * One app in the drawer: icon over a label, sized for a fingertip.
 *
 * The desktop launcher's tile is 100x110 with a 48px icon and grows on hover. Neither
 * number survives a touchscreen — the whole tile is the target here, and there is no hover
 * to grow on, so the press feedback has to be the press itself.
 */
Item {
    id: root

    /// A desktop entry, or null for a shell surface listed as an app.
    required property var entry
    /// Set instead of `entry` for a shell surface: it has no .desktop file, so its name and
    /// Material symbol are supplied directly.
    property string systemName: ""
    property string systemIcon: ""
    readonly property bool isSystem: root.systemIcon.length > 0

    property real iconSize: 56

    signal activated
    /// The configurable touch hold. It may still use the legacy direct add-to-home action.
    signal held
    /// A pointer context click always requests the menu, independent of the touch preference.
    signal contextRequested

    /// A held tile that then moves is picked up and dragged out of the drawer. Scene
    /// coordinates, i.e. the drawer surface's own.
    property bool dragEnabled: false
    readonly property bool dragging: tapArea.dragging
    signal dragStarted(real sceneX, real sceneY)
    signal dragMoved(real sceneX, real sceneY)
    /// (-1, -1) when the gesture was taken away rather than released.
    signal dragEnded(real sceneX, real sceneY)

    /// Room for two lines whether or not the name needs them.
    ///
    /// The label used to size the tile's contents, so a two-line name pushed its own icon
    /// up and broke the row it was in — one long name and the whole row read as crooked.
    /// The block is a fixed height now: short names leave the second line empty, and names
    /// too long for two lines elide.
    readonly property real labelHeight: Math.ceil(labelMetrics.height * 2)
    readonly property real contentSpacing: 6

    implicitWidth: 96
    implicitHeight: 116

    FontMetrics {
        id: labelMetrics
        font: label.font
    }

    // A press ripple is the only feedback a finger gets: no cursor, no hover state. It has
    // to start on press rather than on release, or the tile feels dead for the whole time
    // the finger is down.
    Rectangle {
        id: pressPlate
        anchors.centerIn: parent
        width: root.width
        height: root.height
        radius: Appearance.rounding.large
        color: Appearance.colors.colLayer2
        opacity: tapArea.pressed && !tapArea.dragging ? 1 : 0
        scale: tapArea.pressed ? 1 : 0.9

        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        Behavior on scale {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
    }

    // Anchors rather than a layout: the icon's position is a property of the tile, not
    // something negotiated with whatever the label happens to need this frame.
    Item {
        id: content
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - 12
        height: root.iconSize + root.contentSpacing + root.labelHeight

        Item {
            id: iconHolder
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            width: root.iconSize
            height: root.iconSize
            // Android shrinks the icon under the finger rather than lighting up a
            // background; the plate behind is a softer version of the same idea. Scale
            // leaves the anchor geometry alone, so the label below does not move with it.
            scale: tapArea.pressed ? 0.92 : 1
            // The icon has left with the finger; its place in the grid stays marked.
            opacity: tapArea.dragging ? 0.3 : 1
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            Behavior on scale {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            /**
             * The application's icon, and something to show when there is not one.
             *
             * A tile that paints nothing is indistinguishable from a tile that failed to
             * load, and both read as the drawer being broken. The theme lookup can come back
             * with nothing for plenty of ordinary reasons — an app with no icon at all, a
             * name the guesser cannot map, a theme still warming up after a reload — so the
             * fallback is a first-letter plate rather than an empty square.
             */
            IconImage {
                id: appIcon
                anchors.fill: parent
                visible: !root.isSystem && appIcon.status === Image.Ready
                source: Quickshell.iconPath(AppSearch.guessIcon(root.entry?.id ?? ""), "image-missing")
            }

            Rectangle {
                anchors.fill: parent
                visible: !root.isSystem && !appIcon.visible
                radius: width * 0.28
                color: Appearance.colors.colSecondaryContainer

                StyledText {
                    anchors.centerIn: parent
                    text: (root.entry?.name ?? "?").trim().charAt(0).toLocaleUpperCase()
                    font.pixelSize: Math.round(root.iconSize * 0.44)
                    font.family: Appearance.font.family.title
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }

            // A shell surface has no application icon, so it gets a symbol on a tinted
            // round plate — visibly a system thing rather than a badly-themed app.
            Rectangle {
                anchors.fill: parent
                visible: root.isSystem
                radius: width * 0.28
                color: Appearance.colors.colPrimaryContainer

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.systemIcon
                    iconSize: Math.round(root.iconSize * 0.52)
                    color: Appearance.colors.colOnPrimaryContainer
                }
            }
        }

        StyledText {
            id: label
            anchors.top: iconHolder.bottom
            anchors.topMargin: root.contentSpacing
            anchors.left: parent.left
            anchors.right: parent.right
            height: root.labelHeight
            text: root.isSystem ? Translation.tr(root.systemName) : (root.entry?.name ?? "")
            font.pixelSize: Appearance.font.pixelSize.smaller
            horizontalAlignment: Text.AlignHCenter
            // Top, not centre: a one-line name has to start where the first of two lines
            // would, or short and long names sit at different heights again.
            verticalAlignment: Text.AlignTop
            elide: Text.ElideRight
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            color: Appearance.m3colors.m3onSurface
        }
    }

    MouseArea {
        id: tapArea
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        // Once the hold has fired the finger owns the tile. Before it, a move is the grid's
        // scroll; after it, letting the grid steal the move would end the drag as it began.
        preventStealing: root.dragEnabled && holdTimer.fired

        property bool dragging: false
        property real pressX: 0
        property real pressY: 0
        readonly property real dragThreshold: 12

        onClicked: event => {
            if (event.button === Qt.RightButton) {
                holdTimer.stop();
                holdTimer.fired = true;
                root.contextRequested();
                return;
            }
            if (holdTimer.fired)
                return;
            root.activated();
        }
        onPressed: event => {
            holdTimer.fired = false;
            tapArea.dragging = false;
            tapArea.pressX = event.x;
            tapArea.pressY = event.y;
            if (event.button === Qt.LeftButton)
                holdTimer.restart();
        }
        onPositionChanged: event => {
            if (!root.dragEnabled || !holdTimer.fired || !(event.buttons & Qt.LeftButton))
                return;
            const scene = tapArea.mapToItem(null, event.x, event.y);
            if (!tapArea.dragging) {
                if (Math.hypot(event.x - tapArea.pressX, event.y - tapArea.pressY) < tapArea.dragThreshold)
                    return;
                tapArea.dragging = true;
                root.dragStarted(scene.x, scene.y);
            }
            root.dragMoved(scene.x, scene.y);
        }
        onReleased: event => {
            holdTimer.stop();
            if (!tapArea.dragging)
                return;
            tapArea.dragging = false;
            const scene = tapArea.mapToItem(null, event.x, event.y);
            root.dragEnded(scene.x, scene.y);
        }
        onCanceled: {
            holdTimer.stop();
            if (!tapArea.dragging)
                return;
            tapArea.dragging = false;
            root.dragEnded(-1, -1);
        }

        Timer {
            id: holdTimer
            property bool fired: false
            interval: 550
            onTriggered: {
                holdTimer.fired = true;
                root.held();
            }
        }
    }
}
