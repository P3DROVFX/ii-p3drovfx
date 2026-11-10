pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.services

/**
 * Generates a UI locale file with an LLM (scripts/ai/gemini-translate.sh).
 * Lives outside the Settings window so a run keeps going, and keeps
 * reporting, after the window closes. Nothing runs until start().
 */
Singleton {
    id: root

    // "idle" | "running" | "success" | "partial" | "error"
    property string state: "idle"
    readonly property bool running: proc.running
    property string locale: ""
    property string model: ""
    property int keysDone: 0
    property int keysTotal: 0
    property int batch: 0
    property int batches: 0
    property int keysTranslated: 0
    property int keysFailed: 0
    property string message: ""
    readonly property real progress: keysTotal > 0 ? keysDone / keysTotal : 0

    readonly property var models: [
        { "value": "gemini-3.8-flash", "title": "Gemini 3.8 Flash", "provider": "gemini" },
        { "value": "gemini-3.7-flash", "title": "Gemini 3.7 Flash", "provider": "gemini" },
        { "value": "gemini-2.5-flash-lite", "title": "Gemini 2.5 Flash-Lite", "provider": "gemini" },
        { "value": "claude-haiku-5-5", "title": "Claude Haiku 5.5", "provider": "claude" },
        { "value": "claude-sonnet-5-5", "title": "Claude Sonnet 5.5", "provider": "claude" }
    ]

    function modelInfo(id) {
        return root.models.find(m => m.value === id) ?? root.models[0];
    }

    function start(localeCode, modelId) {
        const code = String(localeCode ?? "").trim();
        if (code.length === 0 || proc.running)
            return;
        root.locale = code;
        root.model = modelId || root.models[0].value;
        root.keysDone = 0;
        root.keysTotal = 0;
        root.batch = 0;
        root.batches = 0;
        root.keysTranslated = 0;
        root.keysFailed = 0;
        root.message = "";
        root.state = "running";
        proc.command = [Directories.aiTranslationScriptPath, root.locale, root.model];
        proc.running = true;
    }

    function cancel() {
        if (!proc.running)
            return;
        proc.cancelled = true;
        proc.signal(15);
    }

    function dismiss() {
        if (!proc.running)
            root.state = "idle";
    }

    Process {
        id: proc
        property bool cancelled: false
        onStarted: cancelled = false

        stdout: SplitParser {
            onRead: data => {
                const line = String(data).trim();
                if (!line.startsWith("@@"))
                    return;
                const parts = line.slice(2).split(" ");
                const tag = parts[0];
                if (tag === "TOTAL") {
                    root.keysTotal = parseInt(parts[1]) || 0;
                    root.batches = parseInt(parts[2]) || 0;
                } else if (tag === "PROGRESS") {
                    root.keysDone = parseInt(parts[1]) || 0;
                    root.keysTotal = parseInt(parts[2]) || root.keysTotal;
                    root.batch = parseInt(parts[3]) || 0;
                    root.batches = parseInt(parts[4]) || root.batches;
                } else if (tag === "DONE") {
                    root.keysTranslated = parseInt(parts[1]) || 0;
                    root.keysFailed = parseInt(parts[2]) || 0;
                } else if (tag === "ERROR") {
                    root.message = parts.slice(1).join(" ");
                }
            }
        }

        onExited: (exitCode, exitStatus) => {
            if (proc.cancelled) {
                root.state = "idle";
                return;
            }
            Translation.rescan();
            if (exitCode === 0)
                root.state = "success";
            else if (exitCode === 2)
                root.state = "partial";
            else {
                root.state = "error";
                if (root.message.length === 0)
                    root.message = "The translation script exited with code " + exitCode + ".";
            }
        }
    }
}
