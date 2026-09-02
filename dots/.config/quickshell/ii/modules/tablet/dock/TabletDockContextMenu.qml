import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland

import qs
import qs.modules.common
import qs.modules.common.dock
import qs.modules.common.widgets
import qs.modules.tablet.menu
import qs.services

// Tablet-local counterpart of ii's DockContextMenu. It intentionally carries the same
// actions and popup treatment, while keeping modules/tablet free of qs.modules.ii imports.
Loader {
    id: root

    property Item anchorItem: parent
    property string appId: ""
    property var appToplevels: []
    readonly property var desktopEntry: TaskbarApps.getCachedDesktopEntry(root.appId)
    property bool closing: false

    function open() {
        if (active && !closing)
            return;
        closing = false;
        active = true;
        if (item)
            item.startOpenAnimation();
    }

    function close() {
        if (!active || closing)
            return;
        closing = true;
        if (item)
            item.startCloseAnimation();
    }

    active: false
    visible: active

    sourceComponent: PopupWindow {
        id: popupWindow

        visible: true
        color: "transparent"
        readonly property real popupMargin: Appearance.sizes.elevationMargin * 2
        readonly property real shadowMargin: Appearance.sizes.elevationMargin * 2
        property real menuOffset: popupMargin

        implicitWidth: menuContent.implicitWidth + shadowMargin * 2
        implicitHeight: menuContent.implicitHeight + shadowMargin * 2

        function startOpenAnimation() {
            menuContent.scale = 1;
            menuContent.opacity = 1;
        }

        function startCloseAnimation() {
            menuContent.scale = 0.8;
            menuContent.opacity = 0;
        }

        anchor {
            adjustment: PopupAdjustment.None
            window: root.anchorItem ? root.anchorItem.QsWindow.window : null
            onAnchoring: {
                const item = root.anchorItem;
                if (!item)
                    return;
                const mapped = item.mapToItem(null, item.width / 2, item.height / 2);
                const scaledHeight = item.height * (item.scale ?? 1) / 2;
                anchor.rect.x = mapped.x - popupWindow.implicitWidth / 2;
                anchor.rect.y = mapped.y - scaledHeight - popupWindow.implicitHeight - popupWindow.menuOffset;
            }
        }

        HyprlandFocusGrab {
            active: root.active && !root.closing
            windows: [popupWindow]
            onCleared: root.close()
        }

        StyledRectangularShadow {
            target: menuContent
            opacity: menuContent.opacity
            visible: menuContent.visible
        }

        TabletMenuCard {
            id: menuContent

            anchors.centerIn: parent
            headerText: root.desktopEntry?.name ?? root.appId
            headerIconPath: Quickshell.iconPath(root.desktopEntry?.icon
                ?? AppSearch.guessIcon(root.appId), "image-missing")

            // Built here rather than as declared rows, because this is the same list the
            // drawer's long-press builds and both are fed to one card. Two menus for the
            // same gesture on two icons a centimetre apart is what this replaces.
            actions: {
                const entries = [];
                for (const action of (root.desktopEntry?.actions ?? [])) {
                    entries.push({
                        symbol: "shortcut",
                        label: action.name ?? "",
                        trigger: () => action.execute()
                    });
                }
                entries.push({
                    symbol: "launch",
                    label: Translation.tr("Launch"),
                    trigger: () => root.desktopEntry?.execute()
                });
                if (root.appId.length > 0) {
                    entries.push({
                        symbol: "live_tv",
                        label: (Config.options?.dock?.enableLivePreviewWidget ?? false)
                            ? Translation.tr("Set as Live Preview")
                            : Translation.tr("Enable Live Preview"),
                        trigger: () => {
                            Config.options.dock.enableLivePreviewWidget = true;
                            DockLivePreviewService.selectApp(root.appId);
                        }
                    });
                }
                entries.push({
                    symbol: TaskbarApps.isPinned(root.appId) ? "keep_off" : "keep",
                    label: TaskbarApps.isPinned(root.appId)
                        ? Translation.tr("Unpin") : Translation.tr("Pin"),
                    trigger: () => TaskbarApps.togglePin(root.appId)
                });
                if (root.appToplevels.length > 0) {
                    entries.push({
                        symbol: "close",
                        label: root.appToplevels.length > 1
                            ? Translation.tr("Close all windows")
                            : Translation.tr("Close window"),
                        destructive: true,
                        trigger: () => {
                            for (const toplevel of root.appToplevels)
                                toplevel.close();
                        }
                    });
                }
                return entries;
            }

            opacity: 0
            scale: 0.8

            Component.onCompleted: popupWindow.startOpenAnimation()

            Behavior on opacity {
                animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
            }
            Behavior on scale {
                animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
            }
            onOpacityChanged: {
                if (opacity === 0 && root.closing) {
                    root.active = false;
                    root.closing = false;
                }
            }

            onActionTriggered: root.close()
        }
    }
}
