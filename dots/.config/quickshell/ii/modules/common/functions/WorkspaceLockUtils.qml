pragma Singleton
import Quickshell
import "workspace_lock.js" as WsLock

/**
 * Wrapper for workspace_lock.js so it is exposed as a Singleton
 * through `qs.modules.common.functions`.
 */
Singleton {
    id: root

    function allocateEmptyWorkspaces(params) {
        return WsLock.allocateEmptyWorkspaces(params);
    }
}
