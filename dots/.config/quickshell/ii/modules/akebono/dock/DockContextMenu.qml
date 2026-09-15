pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root

    property var entry: null
    property bool showing: false
    property real boundsWidth: 0
    property real boundsHeight: 0
    property real clickX: 0
    property real clickY: 0
    property bool openAbove: true

    readonly property bool running: root.entry && root.entry.toplevels.length > 0
    readonly property var desktopEntry: root.entry ? (DesktopEntries.byId(root.entry.appId) ?? DesktopEntries.heuristicLookup(root.entry.appId)) : null

    visible: showing
    z: 100

    function show(e, x, y) {
        root.entry = e;
        root.clickX = x;
        root.clickY = y;
        root.showing = true;
    }

    function dismiss() {
        root.showing = false;
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.showing
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: root.dismiss()
    }

    Rectangle {
        id: menuBg
        x: Math.min(Math.max(8, root.clickX - width / 2), Math.max(8, root.boundsWidth - width - 8))
        y: root.openAbove
            ? Math.max(8, root.clickY - height - 8)
            : Math.min(root.boundsHeight - height - 8, root.clickY + 8)
        width: 220
        implicitHeight: col.implicitHeight + 12
        height: implicitHeight
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer2
        clip: true
        scale: root.showing ? 1 : 0.9
        opacity: root.showing ? 1 : 0
        transformOrigin: root.openAbove ? Item.Bottom : Item.Top

        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

        ColumnLayout {
            id: col
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0

            ContextMenuItem {
                iconName: "open_in_new"
                label: "New window"
                onClicked: {
                    root.desktopEntry?.execute();
                    root.dismiss();
                }
            }

            ContextMenuItem {
                iconName: TaskbarApps.isPinned(root.entry?.appId ?? "") ? "keep_off" : "keep"
                label: TaskbarApps.isPinned(root.entry?.appId ?? "") ? "Unpin from dock" : "Pin to dock"
                onClicked: {
                    if (root.entry) TaskbarApps.togglePin(root.entry.appId);
                    root.dismiss();
                }
            }

            ContextMenuItem {
                visible: root.running
                iconName: "close"
                danger: true
                label: (root.entry && root.entry.toplevels.length > 1) ? "Close all windows" : "Close"
                onClicked: {
                    if (root.entry)
                        for (const t of root.entry.toplevels)
                            t.close();
                    root.dismiss();
                }
            }
        }
    }

    component ContextMenuItem: Item {
        id: menuItem
        property string iconName: ""
        property string label: ""
        property bool danger: false
        signal clicked()

        Layout.fillWidth: true
        Layout.preferredHeight: visible ? 40 : 0

        Rectangle {
            anchors.fill: parent
            anchors.leftMargin: 6
            anchors.rightMargin: 6
            radius: Appearance.rounding.small
            color: itemMouse.containsMouse
                ? (menuItem.danger ? Qt.alpha(Appearance.colors.colError, 0.1) : Appearance.colors.colLayer2Hover)
                : "transparent"

            MouseArea {
                id: itemMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: menuItem.clicked()
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 10

                MaterialSymbol {
                    text: menuItem.iconName
                    iconSize: Appearance.font.pixelSize.large
                    color: menuItem.danger ? Appearance.colors.colError : Appearance.colors.colOnLayer2
                }

                StyledText {
                    Layout.fillWidth: true
                    text: menuItem.label
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: menuItem.danger ? Appearance.colors.colError : Appearance.colors.colOnLayer2
                    elide: Text.ElideRight
                }
            }
        }
    }
}
