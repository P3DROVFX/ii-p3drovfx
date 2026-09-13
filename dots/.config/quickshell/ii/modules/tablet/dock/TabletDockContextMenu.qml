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
        // Back dismisses the menu rather than the surface under it.
        TransientLayerRegistry.push("tabletDockContextMenu", () => root.close());
        if (item)
            item.startOpenAnimation();
    }

    function close() {
        if (!active || closing)
            return;
        closing = true;
        TransientLayerRegistry.remove("tabletDockContextMenu");
        if (item)
            item.startCloseAnimation();
    }

    Component.onDestruction: TransientLayerRegistry.remove("tabletDockContextMenu")

    // ── Split ───────────────────────────────────────────────────────────────
    readonly property int activeWorkspace: Number(HyprlandData.activeWorkspace?.id ?? -1)
    readonly property bool activeWorkspaceOccupied: root.activeWorkspace > 0
        && HyprlandData.hyprlandClientsForWorkspace(root.activeWorkspace).length > 0

    /// The window to move, if this app already has one. Empty means "launch it instead".
    readonly property string splitTarget: {
        if (root.appToplevels.length === 0)
            return root.desktopEntry ? "launch" : "";
        const raw = String(root.appToplevels[0]?.HyprlandToplevel?.address ?? "").trim();
        if (raw.length === 0)
            return root.desktopEntry ? "launch" : "";
        return raw.startsWith("0x") ? raw : `0x${raw}`;
    }

    function openBesideCurrent() {
        const workspace = root.activeWorkspace;
        if (workspace <= 0)
            return;
        if (root.splitTarget === "launch") {
            // A new window lands on the focused workspace on its own, so launching is the
            // whole operation — there is nothing to move yet.
            root.desktopEntry?.execute();
            return;
        }
        Hyprland.dispatch(`hl.dsp.window.move({ workspace = ${workspace}, follow = false, window = "address:${root.splitTarget}" })`);
        Hyprland.dispatch(`hl.dsp.focus({ window = "address:${root.splitTarget}" })`);
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
                /**
                 * Picking the second app of a split, with a finger, from the dock.
                 *
                 * The audit wanted this as a drag onto a half of the screen. That needs drop
                 * zones, a drag proxy and live geometry feedback — a lot of machinery for a
                 * choice this menu is already open to take. Hyprland tiles two windows that
                 * share a workspace, so the whole feature is "put this app where the other
                 * one is": raise it there if it is already running, launch it there if not.
                 *
                 * Only offered when there is something to split with. On an empty workspace
                 * this is a plain launch, which the row above already is.
                 */
                if (root.splitTarget.length > 0 && root.activeWorkspaceOccupied) {
                    entries.push({
                        symbol: "splitscreen",
                        label: Translation.tr("Open beside current app"),
                        trigger: () => root.openBesideCurrent()
                    });
                }
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
