import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland

import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.tablet.menu
import qs.services

/**
 * The overflow group's page: everything the dock could not fit, as rows big enough to hit.
 *
 * A PopupWindow rather than an in-surface panel, because the dock's layer is only as tall as
 * the dock: anything drawn above it would be cut off at the surface edge.
 *
 * Activating a row raises the window instead of re-running the launcher. Every app in here
 * is running by definition — that is the only reason it is in the dock at all — and
 * executing its desktop entry again would open a second copy of something the user was
 * trying to get back to.
 */
Loader {
    id: root

    property Item anchorItem: parent
    property var appIds: []
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

    function raiseApp(appId) {
        const normalized = TaskbarApps.normalizeAppId(appId);
        const toplevel = Array.from(ToplevelManager.toplevels?.values ?? []).find(candidate =>
            TaskbarApps.normalizeAppId(candidate?.appId ?? "") === normalized);
        if (toplevel)
            toplevel.activate();
        else
            TaskbarApps.getCachedDesktopEntry(appId)?.execute();
        root.close();
    }

    active: false
    visible: active

    sourceComponent: PopupWindow {
        id: popupWindow

        visible: true
        color: "transparent"
        readonly property real shadowMargin: Appearance.sizes.elevationMargin * 2
        readonly property real menuOffset: Appearance.sizes.elevationMargin * 2

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
                anchor.rect.x = mapped.x - popupWindow.implicitWidth / 2;
                anchor.rect.y = mapped.y - item.height / 2 - popupWindow.implicitHeight - popupWindow.menuOffset;
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
            headerText: Translation.tr("More open apps")
            headerSymbol: "apps"
            menuWidth: 340
            actions: root.appIds.map(appId => ({
                iconPath: Quickshell.iconPath(TaskbarApps.getCachedDesktopEntry(appId)?.icon
                    ?? AppSearch.guessIcon(appId), "image-missing"),
                label: TaskbarApps.getCachedDesktopEntry(appId)?.name ?? appId,
                trigger: () => root.raiseApp(appId)
            }))

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
        }
    }
}
