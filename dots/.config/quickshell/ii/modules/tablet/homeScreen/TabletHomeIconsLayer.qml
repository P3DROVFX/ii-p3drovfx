pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * App icons laid out on the wallpaper, one screen's worth.
 *
 * Not a surface of its own. It is injected into the desktop widget canvas
 * (BackgroundWidgetsWindow.canvasOverlay) because that surface already owns the whole
 * screen's input region on the Bottom layer — a second desktop surface underneath it
 * renders fine and can never be touched, which is exactly what happened when this was its
 * own PanelWindow. Sharing the canvas also means the icons inherit its coordinate space,
 * parallax and lock choreography, and sit on the same grid as the widgets, which is what
 * "icons and widgets coexist on one grid" was supposed to mean.
 */
Item {
    id: root

    readonly property int workspaceId: TabletHomeIcons.currentWorkspace

    /// Re-read whenever the store changes or the home screen does.
    readonly property var icons: {
        TabletHomeIcons.revision;
        return TabletHomeIcons.iconsFor(root.workspaceId);
    }

    readonly property real iconSize: Math.max(52, Math.min(76, Math.round(height * 0.062)))
    readonly property real cellSize: Math.round(root.iconSize * 1.75)
    readonly property real gridStep: Appearance.sizes.widgetGridStep

    // No mask and no input region of its own: the canvas above decides what is touchable,
    // and an Item only receives what lands on its children. That is why the icons no longer
    // need the region bookkeeping the standalone window required.

    Repeater {
        id: iconRepeater
        model: root.icons

        delegate: Item {
            id: iconItem
            required property var modelData

            readonly property string appId: iconItem.modelData.id
            readonly property var entry: TaskbarApps.getCachedDesktopEntry(iconItem.appId)

            x: iconItem.modelData.x
            y: iconItem.modelData.y
            width: root.cellSize
            height: root.cellSize

            // Where the icon is being dragged to, before it is committed to the store.
            property real dragX: iconItem.modelData.x
            property real dragY: iconItem.modelData.y
            property bool dragging: false

            Item {
                id: visual
                width: parent.width
                height: parent.height
                x: iconItem.dragging ? iconItem.dragX - iconItem.x : 0
                y: iconItem.dragging ? iconItem.dragY - iconItem.y : 0
                scale: iconItem.dragging ? 1.1 : (tapArea.pressed ? 0.92 : 1)
                z: iconItem.dragging ? 10 : 0

                Behavior on scale {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(visual)
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 4
                    spacing: 4

                    IconImage {
                        Layout.alignment: Qt.AlignHCenter
                        implicitSize: root.iconSize
                        source: Quickshell.iconPath(TaskbarApps.getCachedIcon(iconItem.appId), "image-missing")
                    }

                    StyledText {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: iconItem.entry?.name ?? iconItem.appId
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: "white"
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        // The wallpaper underneath is arbitrary, so the label carries its
                        // own contrast rather than trusting the theme's surface colours.
                        style: Text.Outline
                        styleColor: Qt.rgba(0, 0, 0, 0.55)
                    }
                }
            }

            MouseArea {
                id: tapArea
                anchors.fill: parent

                // The widget canvas this layer sits on is itself a MouseArea, and a parent
                // MouseArea steals the grab from a child as soon as the pointer moves. Without
                // this the press and the long-press worked but every drag was lost on the
                // first pixel of motion.
                preventStealing: true

                property real grabX: 0
                property real grabY: 0

                onPressed: mouse => {
                    tapArea.grabX = mouse.x;
                    tapArea.grabY = mouse.y;
                    longPressTimer.fired = false;
                    longPressTimer.restart();
                }

                onPositionChanged: mouse => {
                    if (!tapArea.pressed)
                        return;
                    const dx = mouse.x - tapArea.grabX;
                    const dy = mouse.y - tapArea.grabY;
                    if (!iconItem.dragging && Math.abs(dx) + Math.abs(dy) < 12)
                        return;
                    longPressTimer.stop();
                    iconItem.dragging = true;
                    // Snap while dragging rather than on drop, so the icon visibly lands on
                    // the grid and the user can see where it will end up.
                    const step = Math.max(1, root.gridStep);
                    iconItem.dragX = Math.round((iconItem.x + dx) / step) * step;
                    iconItem.dragY = Math.round((iconItem.y + dy) / step) * step;
                }

                onReleased: {
                    longPressTimer.stop();
                    if (!iconItem.dragging)
                        return;
                    iconItem.dragging = false;
                    TabletHomeIcons.move(root.workspaceId, iconItem.appId,
                                         Math.max(0, Math.min(root.width - root.cellSize, iconItem.dragX)),
                                         Math.max(0, Math.min(root.height - root.cellSize, iconItem.dragY)));
                }

                onClicked: {
                    if (iconItem.dragging)
                        return;
                    // A long press always ends with a click. Without this the same gesture
                    // that armed the remove badge immediately disarmed it again, so the
                    // badge could never be tapped.
                    if (longPressTimer.fired)
                        return;
                    if (iconItem.editing) {
                        iconItem.editing = false;
                        return;
                    }
                    iconItem.entry?.execute();
                }

                Timer {
                    id: longPressTimer
                    property bool fired: false
                    interval: 550
                    onTriggered: {
                        longPressTimer.fired = true;
                        iconItem.editing = true;
                    }
                }
            }

            // Long-press arms a remove badge rather than deleting outright. A finger has no
            // right-click, and a press held a moment too long must not silently lose an
            // icon — so removal always takes a second, deliberate tap. The badge disarms
            // itself so the home screen does not sit in a half-edit state forever.
            property bool editing: false

            Timer {
                running: iconItem.editing
                interval: 4000
                onTriggered: iconItem.editing = false
            }

            Rectangle {
                anchors.right: visual.right
                anchors.top: visual.top
                anchors.rightMargin: 2
                anchors.topMargin: 2
                width: 26
                height: 26
                radius: height / 2
                color: Appearance.m3colors.m3error
                z: 20

                visible: iconItem.editing
                scale: iconItem.editing ? 1 : 0.4
                Behavior on scale {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "close"
                    iconSize: 16
                    color: Appearance.m3colors.m3onError
                }

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -6
                    onClicked: {
                        iconItem.editing = false;
                        TabletHomeIcons.remove(root.workspaceId, iconItem.appId);
                    }
                }
            }

            /**
             * Send the icon to the page either side, while the badge state is armed.
             *
             * Dragging it to the screen edge until the page turns is the gesture Android
             * uses, and it is a much harder thing than it looks here: the icon would have to
             * survive a workspace switch mid-drag, on a surface that is rebuilt per
             * workspace. These reuse the state a long press already arms, so moving an icon
             * costs one more tap and no new gesture — and no risk to the drag path, which
             * has already cost this file three separate input bugs.
             */
            component PageMoveBadge: Rectangle {
                id: badge

                required property int delta
                required property string symbol

                width: 26
                height: 26
                radius: height / 2
                color: Appearance.colors.colPrimary
                z: 20

                readonly property int targetWorkspace: root.workspaceId + badge.delta

                visible: iconItem.editing && badge.targetWorkspace >= 1
                scale: iconItem.editing ? 1 : 0.4
                Behavior on scale {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: badge.symbol
                    iconSize: 16
                    color: Appearance.colors.colOnPrimary
                }

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -6
                    onClicked: {
                        iconItem.editing = false;
                        TabletHomeIcons.moveToWorkspace(root.workspaceId, badge.targetWorkspace,
                                                        iconItem.appId);
                    }
                }
            }

            PageMoveBadge {
                anchors.left: visual.left
                anchors.top: visual.top
                anchors.leftMargin: 2
                anchors.topMargin: 2
                delta: -1
                symbol: "chevron_left"
            }

            PageMoveBadge {
                anchors.left: visual.left
                anchors.bottom: visual.bottom
                anchors.leftMargin: 2
                anchors.bottomMargin: 2
                delta: 1
                symbol: "chevron_right"
            }
        }
    }
}
