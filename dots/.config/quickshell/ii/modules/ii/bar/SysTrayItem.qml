pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import Qt5Compat.GraphicalEffects
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

MouseArea {
    id: root
    required property SystemTrayItem item
    property bool targetMenuOpen: false

    property real dragStartX: 0
    property real dragStartY: 0
    property bool dragged: false

    Rectangle {
        anchors.centerIn: parent
        width: parent.width + 12
        height: parent.height + 12
        visible: root.containsMouse || root.pressed
        color: Appearance.colors.colLayer1Hover
        radius: Config.options.bar.barGroupStyle === 0 ? Appearance.rounding.full : (Config.options.bar.barGroupStyle === 1 ? Appearance.rounding.windowRounding : Appearance.rounding.small)
        z: -1
    }

    signal menuOpened(qsWindow: var)
    signal menuClosed

    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: Qt.PointingHandCursor
    implicitWidth: 20
    implicitHeight: 20
    onPressed: event => {
        if (event.button === Qt.LeftButton) {
            dragStartX = event.x;
            dragStartY = event.y;
            dragged = false;
        } else if (event.button === Qt.RightButton) {
            if (item.hasMenu) {
                if (menu.active && menu.item && typeof menu.item.close === "function")
                    menu.item.close();
                else
                    menu.open();
            }
        }
        event.accepted = true;
    }

    onPositionChanged: event => {
        if (pressed && (pressedButtons & Qt.LeftButton)) {
            var dx = event.x - dragStartX;
            var dy = event.y - dragStartY;
            var dist = Math.sqrt(dx*dx + dy*dy);
            if (dist > 25 && !dragged) {
                dragged = true;
                TrayService.togglePin(root.item.id);
            }
        }
    }

    onReleased: event => {
        if (event.button === Qt.LeftButton) {
            if (!dragged) {
                item.activate();
            }
            dragged = false;
        }
        event.accepted = true;
    }
    onEntered: {
        tooltip.text = TrayService.getTooltipForItem(root.item);
    }

    Loader {
        id: menu
        function open() {
            menu.active = true;
        }
        active: false

        sourceComponent: SysTrayMenu {
            Component.onCompleted: this.open()
            trayItemMenuHandle: root.item.menu
            trayItemId: root.item.id

            anchor {
                window: root.QsWindow.window

                rect: {
                    var gap = Appearance.sizes.elevationMargin; // SysTrayItem menu gap
                    var pos = root.mapToItem(null, 0, 0);

                    if (Config.options.bar.vertical) {
                        return Qt.rect(Config.options.bar.bottom ? pos.x - gap : pos.x + gap, pos.y, root.width, root.height);
                    } else {
                        return Qt.rect(pos.x, Config.options.bar.bottom ? pos.y - gap : pos.y + gap, root.width, root.height);
                    }
                }

                edges: {
                    if (Config.options.bar.vertical) {
                        return Config.options.bar.bottom ? (Edges.Left | Edges.Middle) : (Edges.Right | Edges.Middle);
                    } else {
                        return Config.options.bar.bottom ? (Edges.Top | Edges.Center) : (Edges.Bottom | Edges.Center);
                    }
                }

                gravity: {
                    if (Config.options.bar.vertical) {
                        return Config.options.bar.bottom ? Edges.Left : Edges.Right;
                    } else {
                        return Config.options.bar.bottom ? Edges.Top : Edges.Bottom;
                    }
                }
            }

            onMenuOpened: window => root.menuOpened(window)
            onMenuClosed: {
                root.menuClosed();
                menu.active = false;
            }
        }
    }

    Item {
        id: trayIconContainer
        anchors.centerIn: parent
        width: parent.width
        height: parent.height

        MaterialShape {
            id: iconMask
            width: Math.max(1, trayIconContainer.width)
            height: Math.max(1, trayIconContainer.height)
            shapeString: Config.options.appearance.icons.shapeMask
            visible: false
        }

        layer.enabled: Config.options.appearance.icons.enableShapeMask
        layer.effect: OpacityMask {
            maskSource: iconMask
        }

        IconImage {
            id: trayIcon
            visible: !Config.options.tray.monochromeIcons
            source: root.item.icon
            anchors.fill: parent
        }

        Loader {
            active: Config.options.tray.monochromeIcons
            anchors.fill: trayIcon
            sourceComponent: Item {
                Desaturate {
                    id: desaturatedIcon
                    visible: false // There's already color overlay
                    anchors.fill: parent
                    source: trayIcon
                    desaturation: 0.8 // 1.0 means fully grayscale
                }
                ColorOverlay {
                    anchors.fill: desaturatedIcon
                    source: desaturatedIcon
                    color: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.9)
                }
            }
        }
    }

    PopupToolTip {
        id: tooltip
        extraVisibleCondition: root.containsMouse
        alternativeVisibleCondition: extraVisibleCondition
        anchorEdges: (!Config.options.bar.bottom && !Config.options.bar.vertical) ? Edges.Bottom : Edges.Top
    }
}
