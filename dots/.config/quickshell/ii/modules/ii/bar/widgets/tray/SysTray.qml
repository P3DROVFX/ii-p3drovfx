import qs.modules.ii.bar.shared
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.SystemTray
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: sysTrayRoot
    implicitWidth: gridLayout.implicitWidth
    implicitHeight: gridLayout.implicitHeight
    property bool vertical: false
    property bool invertSide: false
    property bool trayOverflowOpen: false
    property bool showSeparator: true
    property bool showOverflowMenu: true
    property bool circleItems: false
    property var activeMenu: null

    property list<var> pinnedItems: TrayService.pinnedItems
    property list<var> unpinnedItems: TrayService.unpinnedItems
    onPinnedItemsChanged: updateVisibility()
    onUnpinnedItemsChanged: updateVisibility()

    function updateVisibility() {
        const hasAnyItems = pinnedItems.length > 0 || unpinnedItems.length > 0;
        sysTrayRoot.visible = hasAnyItems;

        if (unpinnedItems.length === 0) {
            closeOverflowMenu();
        }
    }

    function grabFocus() {
        focusGrab.active = true;
    }

    function setExtraWindowAndGrabFocus(window) {
        if (sysTrayRoot.activeMenu && sysTrayRoot.activeMenu !== window) {
            if (typeof sysTrayRoot.activeMenu.close === "function")
                sysTrayRoot.activeMenu.close();
            sysTrayRoot.activeMenu = null;
        }
        sysTrayRoot.activeMenu = window;
        sysTrayRoot.grabFocus();
    }

    function releaseFocus() {
        focusGrab.active = false;
    }

    function closeOverflowMenu() {
        focusGrab.active = false;
    }

    onTrayOverflowOpenChanged: {
        if (sysTrayRoot.trayOverflowOpen) {
            sysTrayRoot.grabFocus();
        }
    }

    HyprlandFocusGrab {
        id: focusGrab
        active: false
        windows: [trayOverflowLayout.QsWindow?.window, sysTrayRoot.activeMenu]
        onCleared: {
            sysTrayRoot.trayOverflowOpen = false;
            if (sysTrayRoot.activeMenu) {
                sysTrayRoot.activeMenu.close();
                sysTrayRoot.activeMenu = null;
            }
        }
    }

    GridLayout {
        id: gridLayout
        columns: sysTrayRoot.vertical ? 1 : -1
        anchors.fill: parent
        rowSpacing: sysTrayRoot.circleItems ? 4 : 8
        columnSpacing: sysTrayRoot.circleItems ? 4 : 15

        RippleButton {
            id: trayOverflowButton
            visible: sysTrayRoot.showOverflowMenu && sysTrayRoot.unpinnedItems.length > 0
            toggled: sysTrayRoot.trayOverflowOpen
            property bool containsMouse: hovered

            downAction: () => sysTrayRoot.trayOverflowOpen = !sysTrayRoot.trayOverflowOpen

            Layout.fillHeight: !sysTrayRoot.vertical
            Layout.fillWidth: sysTrayRoot.vertical
            background.implicitWidth: 24
            background.implicitHeight: 24
            background.anchors.centerIn: this
            colBackgroundToggled: Appearance.colors.colSecondaryContainer
            colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
            colRippleToggled: Appearance.colors.colSecondaryContainerActive

            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                iconSize: Appearance.font.pixelSize.larger
                text: "expand_more"
                horizontalAlignment: Text.AlignHCenter
                color: sysTrayRoot.trayOverflowOpen ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
                rotation: (sysTrayRoot.trayOverflowOpen ? 180 : 0) - (90 * sysTrayRoot.vertical) + (180 * sysTrayRoot.invertSide)
                Behavior on rotation {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }

            StyledPopup {
                id: overflowPopup
                hoverTarget: trayOverflowButton
                active: sysTrayRoot.trayOverflowOpen && sysTrayRoot.unpinnedItems.length > 0

                GridLayout {
                    id: trayOverflowLayout
                    anchors.centerIn: parent
                    columns: Math.ceil(Math.sqrt(sysTrayRoot.unpinnedItems.length))
                    columnSpacing: 10
                    rowSpacing: 10

                    Repeater {
                        model: sysTrayRoot.unpinnedItems

                        delegate: SysTrayItem {
                            required property SystemTrayItem modelData
                            item: modelData
                            Layout.fillHeight: !sysTrayRoot.vertical
                            Layout.fillWidth: sysTrayRoot.vertical
                            onMenuClosed: sysTrayRoot.releaseFocus()
                            onMenuOpened: qsWindow => sysTrayRoot.setExtraWindowAndGrabFocus(qsWindow)
                        }
                    }
                }
            }
        }

        Repeater {
            model: ScriptModel {
                values: sysTrayRoot.pinnedItems
            }

            delegate: Item {
                id: circleDelegate
                required property SystemTrayItem modelData
                property bool useCircle: sysTrayRoot.circleItems
                Layout.fillHeight: !sysTrayRoot.vertical && !useCircle
                Layout.fillWidth: sysTrayRoot.vertical && !useCircle
                implicitWidth: useCircle ? 26 : trayItem.implicitWidth
                implicitHeight: useCircle ? 26 : trayItem.implicitHeight

                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width
                    height: parent.height
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colPrimaryContainer
                    visible: circleDelegate.useCircle
                }

                SysTrayItem {
                    id: trayItem
                    anchors.centerIn: parent
                    item: circleDelegate.modelData
                    onMenuClosed: sysTrayRoot.releaseFocus()
                    onMenuOpened: qsWindow => {
                        sysTrayRoot.setExtraWindowAndGrabFocus(qsWindow);
                    }
                }
            }
        }
    }
}
