import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import Qt5Compat.GraphicalEffects
import qs.services
import qs.modules.common
import qs.modules.common.tray
import qs.modules.common.widgets
import qs.modules.common.functions

MouseArea {
    id: root
    required property SystemTrayItem item
    property bool targetMenuOpen: false

    property real dragStartX: 0
    property real dragStartY: 0
    property bool dragged: false
    // Cleared while a click/menu is in flight so the tooltip PopupWindow is destroyed
    // before activate/menu/pin can tear down this item underneath its anchor.
    property bool suppressTooltip: false

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
        root.suppressTooltip = true;
        if (event.button === Qt.LeftButton) {
            dragStartX = event.x;
            dragStartY = event.y;
            dragged = false;
        } else if (event.button === Qt.RightButton) {
            if (root.item && root.item.hasMenu) {
                if (menu.active)
                    menu.close();
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
            if (dist > 25 && !dragged && root.item) {
                dragged = true;
                TrayService.togglePin(root.item);
            }
        }
    }

    onReleased: event => {
        if (event.button === Qt.LeftButton) {
            if (!dragged && root.item) {
                root.item.activate();
            }
            dragged = false;
        }
        root.suppressTooltip = false;
        event.accepted = true;
    }
    onCanceled: root.suppressTooltip = false
    onExited: root.suppressTooltip = false
    onEntered: {
        if (root.item)
            tooltip.text = TrayService.getTooltipForItem(root.item);
    }

    // The menu window anchors to this item, so it must never outlive the window this item
    // lives in — inside the tray overflow popup that window is destroyed on close.
    readonly property var hostWindow: root.QsWindow ? root.QsWindow.window : null
    onHostWindowChanged: {
        if (!root.hostWindow)
            menu.close();
    }
    Component.onDestruction: menu.close()

    Loader {
        id: menu
        function open() {
            // Without a host window there is nothing to anchor to, and PopupAnchor
            // dereferences what it is given without a null check.
            if (!root.hostWindow)
                return;
            menu.active = true;
        }
        function close() {
            if (!menu.active)
                return;
            if (menu.item && typeof menu.item.close === "function")
                menu.item.close();
            menu.active = false;
        }
        active: false

        sourceComponent: SysTrayMenu {
            id: menuWindow
            // Snapshot anchor geometry once. Live bindings re-evaluate while the host
            // window (or this menu) is being destroyed and hand PopupAnchor a half-dead
            // item, which segfaults inside onItemWindowChanged.
            Component.onCompleted: {
                menuWindow.anchor.window = root.hostWindow;

                var gap = Appearance.sizes.elevationMargin;
                var pos = root.mapToItem(null, 0, 0);
                if (BarPlacement.vertical) {
                    menuWindow.anchor.rect = Qt.rect(BarPlacement.bottom ? pos.x - gap : pos.x + gap, pos.y, root.width, root.height);
                    menuWindow.anchor.edges = BarPlacement.bottom ? (Edges.Left | Edges.Middle) : (Edges.Right | Edges.Middle);
                    menuWindow.anchor.gravity = BarPlacement.bottom ? Edges.Left : Edges.Right;
                } else {
                    menuWindow.anchor.rect = Qt.rect(pos.x, BarPlacement.bottom ? pos.y - gap : pos.y + gap, root.width, root.height);
                    menuWindow.anchor.edges = BarPlacement.bottom ? (Edges.Top | Edges.Center) : (Edges.Bottom | Edges.Center);
                    menuWindow.anchor.gravity = BarPlacement.bottom ? Edges.Top : Edges.Bottom;
                }

                menuWindow.open();
            }
            trayItemMenuHandle: root.item ? root.item.menu : null
            trayItem: root.item
            trayItemId: root.item ? (root.item.id || "") : ""

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
            visible: true
            source: (root.item && root.item.icon) ? root.item.icon : ""
            anchors.centerIn: parent
            width: Math.min(parent.width, 20)
            height: Math.min(parent.height, 20)
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
        extraVisibleCondition: root.containsMouse && !root.suppressTooltip && !menu.active
        alternativeVisibleCondition: extraVisibleCondition
        anchorEdges: (!BarPlacement.bottom && !BarPlacement.vertical) ? Edges.Bottom : Edges.Top
    }
}
