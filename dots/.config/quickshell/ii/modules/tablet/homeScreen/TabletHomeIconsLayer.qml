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
 * Supports regular apps, App Pairs (split-screen shortcuts), and App Folders.
 * Dropping an icon onto another automatically creates or merges into a Folder.
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

    // Currently hovered target during a drag gesture
    property string dropTargetId: ""

    Repeater {
        id: iconRepeater
        model: root.icons

        delegate: Item {
            id: iconItem
            required property var modelData

            readonly property string itemId: iconItem.modelData.id
            readonly property string itemType: iconItem.modelData.type ?? "app"
            readonly property var itemApps: iconItem.modelData.apps ?? []
            readonly property string itemName: iconItem.modelData.name ?? ""
            readonly property var entry: iconItem.itemType === "app" ? TaskbarApps.getCachedDesktopEntry(iconItem.itemId) : null

            readonly property bool isDropTarget: root.dropTargetId === iconItem.itemId && !iconItem.dragging

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
                scale: iconItem.dragging ? 1.1 : (iconItem.isDropTarget ? 1.15 : (tapArea.pressed ? 0.92 : 1))
                z: iconItem.dragging ? 10 : 0

                Behavior on scale {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(visual)
                }

                // Drop target highlight ring
                Rectangle {
                    visible: iconItem.isDropTarget
                    anchors.centerIn: parent
                    width: root.iconSize + 16
                    height: root.iconSize + 16
                    radius: width / 2
                    color: Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, 0.2)
                    border.width: 2
                    border.color: Appearance.colors.colPrimary
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 4
                    spacing: 4

                    // Visual type 1: Standard single App
                    IconImage {
                        visible: iconItem.itemType === "app"
                        Layout.alignment: Qt.AlignHCenter
                        implicitSize: root.iconSize
                        source: Quickshell.iconPath(TaskbarApps.getCachedIcon(iconItem.itemId), "image-missing")
                    }

                    // Visual type 2: App Pair (Split badge: solid circle)
                    Rectangle {
                        visible: iconItem.itemType === "pair"
                        Layout.alignment: Qt.AlignHCenter
                        implicitWidth: root.iconSize
                        implicitHeight: root.iconSize
                        radius: root.iconSize / 2
                        color: Appearance.colors.colLayer1
                        border.width: 1
                        border.color: Appearance.colors.colLayer0Border
                        clip: true

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 4
                            spacing: 2

                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true

                                IconImage {
                                    anchors.centerIn: parent
                                    implicitSize: Math.round(root.iconSize * 0.46)
                                    source: Quickshell.iconPath(TaskbarApps.getCachedIcon(iconItem.itemApps[0] ?? ""), "image-missing")
                                }
                            }

                            Rectangle {
                                Layout.fillHeight: true
                                Layout.preferredWidth: 1
                                color: Appearance.colors.colOutlineVariant
                                opacity: 0.5
                            }

                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true

                                IconImage {
                                    anchors.centerIn: parent
                                    implicitSize: Math.round(root.iconSize * 0.46)
                                    source: Quickshell.iconPath(TaskbarApps.getCachedIcon(iconItem.itemApps[1] ?? ""), "image-missing")
                                }
                            }
                        }
                    }

                    // Visual type 3: App Folder (2x2 preview: squircle)
                    Rectangle {
                        visible: iconItem.itemType === "folder"
                        Layout.alignment: Qt.AlignHCenter
                        implicitWidth: root.iconSize
                        implicitHeight: root.iconSize
                        radius: Math.round(root.iconSize * 0.28)
                        color: Appearance.m3colors.m3surfaceContainer
                        border.width: 1
                        border.color: Appearance.colors.colLayer0Border

                        Grid {
                            anchors.centerIn: parent
                            columns: 2
                            spacing: 3

                            Repeater {
                                model: iconItem.itemApps.slice(0, 4)

                                delegate: IconImage {
                                    required property string modelData
                                    implicitSize: Math.round((root.iconSize - 16) / 2)
                                    source: Quickshell.iconPath(TaskbarApps.getCachedIcon(modelData), "image-missing")
                                }
                            }
                        }
                    }

                    // Label below icon
                    StyledText {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: {
                            if (iconItem.itemType === "folder")
                                return iconItem.itemName || Translation.tr("Folder");
                            if (iconItem.itemType === "pair") {
                                if (iconItem.itemName)
                                    return iconItem.itemName;
                                const e1 = TaskbarApps.getCachedDesktopEntry(iconItem.itemApps[0]);
                                const e2 = TaskbarApps.getCachedDesktopEntry(iconItem.itemApps[1]);
                                return (e1?.name ?? iconItem.itemApps[0] ?? "") + " & " + (e2?.name ?? iconItem.itemApps[1] ?? "");
                            }
                            return iconItem.entry?.name ?? iconItem.itemId;
                        }
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: "white"
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        style: Text.Outline
                        styleColor: Qt.rgba(0, 0, 0, 0.55)
                    }
                }
            }

            MouseArea {
                id: tapArea
                anchors.fill: parent
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
                    const step = Math.max(1, root.gridStep);
                    iconItem.dragX = Math.round((iconItem.x + dx) / step) * step;
                    iconItem.dragY = Math.round((iconItem.y + dy) / step) * step;

                    // Proximity check for grouping into a folder
                    let foundTarget = "";
                    const threshold = root.cellSize * 0.65;
                    for (let i = 0; i < root.icons.length; i++) {
                        const other = root.icons[i];
                        if (other.id !== iconItem.itemId) {
                            const dist = Math.hypot(iconItem.dragX - other.x, iconItem.dragY - other.y);
                            if (dist < threshold) {
                                foundTarget = other.id;
                                break;
                            }
                        }
                    }
                    root.dropTargetId = foundTarget;
                }

                onReleased: {
                    longPressTimer.stop();
                    if (!iconItem.dragging)
                        return;
                    iconItem.dragging = false;
                    if (root.dropTargetId) {
                        const targetId = root.dropTargetId;
                        root.dropTargetId = "";
                        TabletHomeIcons.combineIntoFolder(root.workspaceId, targetId, iconItem.itemId, iconItem.dragX, iconItem.dragY);
                    } else {
                        TabletHomeIcons.move(root.workspaceId, iconItem.itemId,
                                             Math.max(0, Math.min(root.width - root.cellSize, iconItem.dragX)),
                                             Math.max(0, Math.min(root.height - root.cellSize, iconItem.dragY)));
                    }
                }

                onClicked: {
                    if (iconItem.dragging)
                        return;
                    if (longPressTimer.fired)
                        return;
                    if (iconItem.editing) {
                        iconItem.editing = false;
                        return;
                    }

                    if (iconItem.itemType === "folder") {
                        folderDialog.folderData = iconItem.modelData;
                    } else if (iconItem.itemType === "pair") {
                        TabletHomeIcons.launchPair(iconItem.itemApps[0], iconItem.itemApps[1]);
                    } else {
                        iconItem.entry?.execute();
                    }
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

            // Remove badge when long-pressed
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
                        TabletHomeIcons.remove(root.workspaceId, iconItem.itemId);
                    }
                }
            }

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
                        TabletHomeIcons.moveToWorkspace(root.workspaceId, badge.targetWorkspace, iconItem.itemId);
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

    TabletFolderDialog {
        id: folderDialog
        workspaceId: root.workspaceId
    }
}
