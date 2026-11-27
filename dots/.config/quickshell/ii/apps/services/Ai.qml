pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

/**
 * Slim Ai IPC bridge for standalone apps.
 */
Singleton {
    id: root

    function submit(prompt) {
        const text = String(prompt ?? "").trim();
        if (!text)
            return;
        Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "sidebarLeft", "open"]);
    }
}
