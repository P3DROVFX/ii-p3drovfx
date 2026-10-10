pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.modules.common

DropArea {
    id: root
    required property string screenName
    property var iconsLayer: null
    property bool available: true
    enabled: available && PanelFamily.isIi && !GlobalStates.screenLocked
        && !GlobalStates.isMediaModeActiveForScreen(screenName)
        && !DesktopShortcuts.hidden
    keys: ["application/x-ii-desktop-item", "application/x-ii-desktop-shortcut", "text/uri-list"]

    function isDesktopItem(event) {
        return event.formats.indexOf("application/x-ii-desktop-item") !== -1;
    }

    function pointFor(event) {
        return root.iconsLayer ? root.iconsLayer.mapFromItem(root, event.x, event.y) : Qt.point(event.x, event.y);
    }
    function updateTarget(event) {
        if (root.iconsLayer) {
            const p = root.pointFor(event);
            root.iconsLayer.dropTargetId = root.iconsLayer.targetAt(p.x, p.y, "");
        }
    }
    // A desktop icon's own drag follows through the layer that started it,
    // which owns the merge target and the landing ghost.
    function follow(event) {
        if (root.isDesktopItem(event)) {
            if (root.iconsLayer)
                root.iconsLayer.systemDragMove(root.pointFor(event));
            return;
        }
        root.updateTarget(event);
    }
    onEntered: event => root.follow(event)
    onPositionChanged: event => root.follow(event)
    onExited: { if (iconsLayer) iconsLayer.dropTargetId = ""; }
    onDropped: event => root.handleDrop(event)
    function handleDrop(event) {
        const p = root.pointFor(event);
        if (root.isDesktopItem(event)) {
            if (root.iconsLayer && root.iconsLayer.systemDragDrop(p)) {
                event.accept(Qt.MoveAction);
                return;
            }
            try {
                const data = JSON.parse(event.getDataAsString("application/x-ii-desktop-item"));
                if (data.screen && data.screen !== root.screenName) {
                    DesktopShortcuts.moveToScreen(data.screen, root.screenName, data.ids);
                    event.accept(Qt.MoveAction);
                }
            } catch (error) {
                console.warn("[DesktopShortcuts] Invalid desktop item drop:", error);
            }
            return;
        }
        const target = root.iconsLayer?.dropTargetId ?? "";
        if (root.iconsLayer)
            root.iconsLayer.dropTargetId = "";
        const w = root.iconsLayer?.width ?? root.width;
        const h = root.iconsLayer?.height ?? root.height;
        const x = Math.max(0, Math.min(w - 100, p.x - 50));
        const y = Math.max(0, Math.min(h - 100, p.y - 50));
        if (event.formats.indexOf("application/x-ii-desktop-shortcut") !== -1) {
            try {
                const data = JSON.parse(event.getDataAsString("application/x-ii-desktop-shortcut"));
                const appIds = Array.isArray(data.apps) ? data.apps : (data.id ? [data.id] : []);
                if (appIds.length > 0 && DesktopShortcuts.addDockApps(root.screenName, appIds, x, y))
                    event.accept(Qt.CopyAction);
            } catch (error) {
                console.warn("[DesktopShortcuts] Invalid dock drop:", error);
            }
        } else if (event.hasUrls && DesktopShortcuts.importUrls(root.screenName,
            Array.from(event.urls, url => String(url)), x, y, target, w, h)) {
            event.accept(Qt.CopyAction);
        }
    }
}
