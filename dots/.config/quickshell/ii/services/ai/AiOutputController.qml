pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.services

/** Shared copy/paste boundary for AI message output and composers. */
Singleton {
    id: root

    property bool pasteInFlight: false
    property string lastError: ""
    property string pendingText: ""
    property var pendingFocusTarget: null

    signal copied
    signal pasted(bool fallback)

    function copyText(text: string): bool {
        const value = String(text ?? "");
        if (value.length === 0)
            return false;
        // Keep this synchronous so a failed paste can always leave the text
        // available in the clipboard instead of losing the user's selection.
        Quickshell.clipboardText = value;
        root.lastError = "";
        root.copied();
        return true;
    }

    function pasteText(text: string, focusTarget = null): bool {
        const value = String(text ?? "");
        if (value.length === 0 || root.pasteInFlight)
            return false;
        root.copyText(value);
        root.pendingText = value;
        root.pendingFocusTarget = focusTarget;
        root.pasteInFlight = true;
        pasteProc.running = false;
        pasteProc.running = true;
        return true;
    }

    Process {
        id: pasteProc
        command: ["bash", "-c", "command -v wtype >/dev/null 2>&1 && wtype -M ctrl -k v -m ctrl"]

        onExited: (exitCode, exitStatus) => {
            const fallback = exitCode !== 0;
            if (fallback) {
                // Clipboard was already populated by copyText(). The caller
                // can paste manually when wtype is unavailable or rejected.
                root.lastError = Translation.tr("Paste automation is unavailable; the response is in the clipboard.");
                root.copyText(root.pendingText);
            }
            root.pasteInFlight = false;
            root.pasted(fallback);
            const target = root.pendingFocusTarget;
            root.pendingFocusTarget = null;
            root.pendingText = "";
            if (target && typeof target.forceActiveFocus === "function")
                Qt.callLater(target.forceActiveFocus);
        }
    }
}
