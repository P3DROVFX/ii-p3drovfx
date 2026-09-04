// .pragma library

/**
 * WorkspaceLock utility: Calculates distinct closest empty workspaces for each monitor
 * during lockscreen activation or editMode desktop clearance.
 *
 * Avoids jumping to virtual INT32_MAX zones (e.g. 2147483647 - ws) while ensuring
 * multi-monitor setups do not collide or leave secondary monitors frozen.
 *
 * @param {Object} params
 * @param {Array} params.monitors - List of { name, activeWorkspaceId, index } or monitor names
 * @param {Array} params.windowList - Hyprland window list (from HyprlandData.windowList)
 * @param {Array} params.allMonitors - Hyprland monitor list (from HyprlandData.monitors)
 * @param {boolean} params.useWorkspaceMap - Whether workspace mapping per monitor is enabled
 * @param {Array} params.workspaceMap - Monitor workspace offset array (e.g. [0, 9])
 * @param {number} params.workspacesShown - Workspaces per group (default 10)
 * @returns {Object} Mapping of monitorName -> targetEmptyWorkspaceId
 */
function allocateEmptyWorkspaces(params) {
    params = params || {};
    const monitors = params.monitors || [];
    const windowList = params.windowList || [];
    const allMonitors = params.allMonitors || [];
    const useWorkspaceMap = !!params.useWorkspaceMap;
    const workspaceMap = params.workspaceMap || [];
    const workspacesShown = params.workspacesShown || 10;

    // 1. Gather all occupied / unavailable workspace IDs
    const unavailable = {};

    // Workspaces with windows (ignoring special workspaces with id <= 0)
    for (let i = 0; i < windowList.length; ++i) {
        const win = windowList[i];
        if (win && win.workspace && win.workspace.id > 0) {
            unavailable[win.workspace.id] = true;
        }
    }

    // Workspaces currently active on any monitor
    for (let i = 0; i < allMonitors.length; ++i) {
        const m = allMonitors[i];
        if (m && m.activeWorkspace && m.activeWorkspace.id > 0) {
            unavailable[m.activeWorkspace.id] = true;
        }
    }

    const result = {};
    const allocated = {};

    for (let mIdx = 0; mIdx < monitors.length; ++mIdx) {
        const mon = monitors[mIdx];
        const monName = typeof mon === "string" ? mon : (mon.name || "");
        if (!monName) continue;

        let curWs = 1;
        if (typeof mon === "object" && mon.activeWorkspaceId !== undefined && mon.activeWorkspaceId > 0) {
            curWs = mon.activeWorkspaceId;
        } else {
            const mData = allMonitors.find(function(m) { return m.name === monName; });
            curWs = (mData && mData.activeWorkspace && mData.activeWorkspace.id > 0) ? mData.activeWorkspace.id : 1;
        }

        // Clamp if already on an absurd legacy lock workspace ID
        if (curWs > 1000000) {
            curWs = 1;
        }

        let screenIndex = mIdx;
        if (typeof mon === "object" && mon.index !== undefined && mon.index >= 0) {
            screenIndex = mon.index;
        } else {
            const foundIdx = allMonitors.findIndex(function(m) { return m.name === monName; });
            if (foundIdx !== -1) screenIndex = foundIdx;
        }

        let startWs = 1;
        let endWs = 100;
        if (useWorkspaceMap && workspaceMap.length > 0) {
            const offset = (workspaceMap.length > screenIndex)
                ? workspaceMap[screenIndex]
                : (screenIndex * workspacesShown);
            startWs = offset + 1;
            endWs = (workspaceMap.length > screenIndex + 1)
                ? workspaceMap[screenIndex + 1]
                : (offset + workspacesShown);
        }

        let candidate = 0;

        // Try searching inside preferred range first if useWorkspaceMap is enabled
        if (useWorkspaceMap) {
            const anchor = (curWs >= startWs && curWs <= endWs) ? curWs : startWs;
            const maxRange = Math.max(endWs - startWs + 1, 1);
            for (let d = 1; d <= maxRange; ++d) {
                const right = anchor + d;
                if (right <= endWs && !unavailable[right] && !allocated[right]) {
                    candidate = right;
                    break;
                }
                const left = anchor - d;
                if (left >= startWs && !unavailable[left] && !allocated[left]) {
                    candidate = left;
                    break;
                }
            }
        }

        // If not using workspaceMap or range was fully occupied, search outward from curWs
        if (candidate === 0) {
            const anchor = curWs >= 1 ? curWs : 1;
            for (let d = 1; d <= 200; ++d) {
                const right = anchor + d;
                if (right >= 1 && !unavailable[right] && !allocated[right]) {
                    candidate = right;
                    break;
                }
                const left = anchor - d;
                if (left >= 1 && !unavailable[left] && !allocated[left]) {
                    candidate = left;
                    break;
                }
            }
        }

        // Fallback to highest occupied + offset if everything in range is somehow taken
        if (candidate === 0) {
            let maxOccupied = 1;
            for (const k in unavailable) {
                const num = Number(k);
                if (num > maxOccupied && num < 1000000) maxOccupied = num;
            }
            candidate = maxOccupied + 1 + mIdx;
        }

        allocated[candidate] = true;
        unavailable[candidate] = true;
        result[monName] = candidate;
    }

    return result;
}
