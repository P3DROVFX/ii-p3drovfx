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
    keys: ["application/x-ii-desktop-shortcut", "text/uri-list"]

    function pointFor(event) {
        return root.iconsLayer ? root.iconsLayer.mapFromItem(root, event.x, event.y) : Qt.point(event.x, event.y);
    }
    function updateTarget(event) {
        if (root.iconsLayer) {
            const p = root.pointFor(event);
            root.iconsLayer.dropTargetId = root.iconsLayer.targetAt(p.x, p.y, "");
        }
    }
    onEntered: event => root.updateTarget(event)
    onPositionChanged: event => root.updateTarget(event)
    onExited: { if (iconsLayer) iconsLayer.dropTargetId = ""; }
    onDropped: event => root.handleDrop(event)
    function handleDrop(event) {
        const p = root.pointFor(event);
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
                const apps = Array.isArray(data.apps) ? data.apps.map(id => DesktopShortcuts.application(id)).filter(app => app !== null) : [];
                const entries = data.type === "group" ? [{ id: "group:" + Date.now(), type: "group", name: data.name || "", apps: apps }] : apps;
                if (entries.length && DesktopShortcuts.add(root.screenName, entries, x, y, target, w, h))
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
