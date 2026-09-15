pragma ComponentBehavior: Bound

import QtQuick
import qs.services

QtObject {
    id: root

    required property var screen
    property rect region
    property bool tiledAlwaysOccludes: true

    readonly property var monitor: HyprlandData.monitors.find(m => m.name === root.screen?.name) ?? null
    readonly property int workspaceId: root.monitor?.activeWorkspace?.id ?? -1

    readonly property bool occluded: {
        const ws = root.workspaceId, r = root.region, list = HyprlandData.windowList;
        for (let i = 0; i < list.length; ++i) {
            const w = list[i];
            if (!w || w.hidden || w.mapped === false || w.workspace?.id !== ws)
                continue;
            const floating = w.floating === true;
            if (root.tiledAlwaysOccludes && !floating)
                return true;
            const wx = w.at?.[0], wy = w.at?.[1], ww = w.size?.[0], wh = w.size?.[1];
            if (wx === undefined)
                continue;
            if (wx < r.x + r.width && wx + ww > r.x && wy < r.y + r.height && wy + wh > r.y)
                return true;
        }
        return false;
    }
}
