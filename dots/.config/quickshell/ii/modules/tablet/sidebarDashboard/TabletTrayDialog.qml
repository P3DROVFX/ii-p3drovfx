import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.tray

/**
 * Touch-sized system tray. The bar's tray is a row of 20px icons, which is unusable with a
 * finger, so the shade lists the same items as full-width rows: tap to activate, and a
 * separate trailing button for the item's own menu.
 */
WindowDialog {
    id: root

    property real rowHeight: 64
    signal itemActivated

    readonly property var trayItems: TrayService.allItems
    readonly property real listSpacing: Math.round(root.rowHeight * 0.16)

    preferredDialogWidth: Math.round(Math.min(root.width * 0.6, Math.max(420, root.rowHeight * 8)))
    backgroundHeight: Math.min(root.height * 0.8, header.implicitHeight + closeRow.implicitHeight + itemList.implicitHeight + Appearance.rounding.large * 2 + 32)

    StyledText {
        id: header
        Layout.fillWidth: true
        text: Translation.tr("Active apps")
        color: Appearance.colors.colOnSurface
        font.pixelSize: Math.round(Appearance.font.pixelSize.huge * 1.05)
        font.family: Appearance.font.family.title
        font.weight: 600
    }

    StyledListView {
        id: itemList
        Layout.fillWidth: true
        Layout.fillHeight: true
        implicitHeight: Math.max(root.rowHeight, contentHeight)
        clip: true
        spacing: root.listSpacing
        model: ScriptModel {
            values: root.trayItems
        }

        delegate: Rectangle {
            id: entry
            required property SystemTrayItem modelData

            width: itemList.width
            height: root.rowHeight
            radius: Appearance.rounding.large
            color: entryArea.pressed ? Appearance.colors.colLayer2Active : entryArea.containsMouse ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(entry)
            }

            readonly property string label: entry.modelData?.tooltipTitle || entry.modelData?.title || entry.modelData?.id || ""

            MouseArea {
                id: entryArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    entry.modelData?.activate();
                    root.itemActivated();
                }
            }

            RowLayout {
                anchors {
                    fill: parent
                    leftMargin: Math.round(root.rowHeight * 0.26)
                    rightMargin: Math.round(root.rowHeight * 0.18)
                }
                spacing: Math.round(root.rowHeight * 0.26)

                IconImage {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: Math.round(root.rowHeight * 0.46)
                    Layout.preferredHeight: Math.round(root.rowHeight * 0.46)
                    source: entry.modelData?.icon ?? ""
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    text: entry.label
                    elide: Text.ElideRight
                    color: Appearance.colors.colOnLayer2
                    font.pixelSize: Math.round(Appearance.font.pixelSize.normal * 1.1)
                    font.weight: 500
                }

                TabletTouchButton {
                    Layout.alignment: Qt.AlignVCenter
                    visible: entry.modelData?.hasMenu ?? false
                    diameter: Math.round(root.rowHeight * 0.68)
                    buttonIcon: "more_vert"
                    colBackground: "transparent"
                    onClicked: entryMenu.toggle()
                }
            }

            // The menu is its own Wayland popup, so it has to be added to the shared focus
            // grab: otherwise the first click inside it counts as a click outside the shade
            // and closes everything.
            Loader {
                id: entryMenu
                active: false

                function toggle() {
                    if (entryMenu.active)
                        entryMenu.close();
                    else
                        entryMenu.open();
                }
                function open() {
                    if (!entry.QsWindow?.window)
                        return;
                    entryMenu.active = true;
                }
                function close() {
                    if (!entryMenu.active)
                        return;
                    if (entryMenu.item)
                        entryMenu.item.close();
                    entryMenu.active = false;
                }

                sourceComponent: SysTrayMenu {
                    id: menuWindow
                    trayItemMenuHandle: entry.modelData ? entry.modelData.menu : null
                    trayItem: entry.modelData
                    trayItemId: entry.modelData ? (entry.modelData.id || "") : ""

                    Component.onCompleted: {
                        const hostWindow = entry.QsWindow?.window ?? null;
                        if (!hostWindow)
                            return;
                        const pos = entry.mapToItem(null, 0, 0);
                        menuWindow.anchor.window = hostWindow;
                        menuWindow.anchor.rect = Qt.rect(pos.x, pos.y + entry.height, entry.width, 1);
                        menuWindow.anchor.edges = Edges.Bottom | Edges.Left;
                        menuWindow.anchor.gravity = Edges.Bottom | Edges.Right;
                        menuWindow.open();
                    }

                    onMenuOpened: window => GlobalFocusGrab.addPersistent(window)
                    onMenuClosed: {
                        GlobalFocusGrab.removePersistent(menuWindow);
                        entryMenu.active = false;
                    }
                }
            }

            Component.onDestruction: entryMenu.close()
        }
    }

    RowLayout {
        id: closeRow
        Layout.fillWidth: true

        Item {
            Layout.fillWidth: true
        }

        DialogButton {
            buttonText: Translation.tr("Close")
            implicitHeight: Math.round(root.rowHeight * 0.7)
            padding: Math.round(root.rowHeight * 0.35)
            onClicked: root.dismiss()
        }
    }
}
