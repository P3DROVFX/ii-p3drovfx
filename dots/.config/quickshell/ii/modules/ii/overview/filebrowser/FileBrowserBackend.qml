pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions

Item {
    id: root

    readonly property string helperPath: FileUtils.trimFileProtocol(Quickshell.shellPath("scripts/file_browser_helper.py"))
    property string currentPath: ""
    property string pendingListPath: ""
    property string pendingInspectPath: ""
    property var entries: []
    property var metadata: null
    property bool loading: false
    property bool inspecting: false
    property bool operating: false
    property bool truncated: false
    property string errorText: ""
    property string operationName: ""
    property bool shuttingDown: false

    signal directoryLoaded(string path)
    signal previewLoaded(string path)
    signal operationFinished(bool success, string operation, string message, var affected)

    Component.onDestruction: {
        root.shuttingDown = true;
        listProcess.running = false;
        inspectProcess.running = false;
        operationProcess.running = false;
    }

    function parseReply(text, expectedOperation): var {
        const raw = String(text ?? "").trim();
        if (raw.length === 0)
            return { ok: false, operation: expectedOperation, error: qsTr("The file helper returned no data") };
        try {
            return JSON.parse(raw);
        } catch (error) {
            return { ok: false, operation: expectedOperation, error: qsTr("The file helper returned invalid data") };
        }
    }

    function listDirectory(path, showHidden = false, sortMode = "name", descending = false): void {
        const target = String(path ?? "");
        if (target.length === 0)
            return;
        root.pendingListPath = target;
        root.loading = true;
        root.errorText = "";
        listProcess.running = false;
        const command = ["python3", root.helperPath, "list", target, "--sort", sortMode, "--limit", "5000"];
        if (showHidden)
            command.push("--hidden");
        if (descending)
            command.push("--descending");
        listProcess.command = command;
        listProcess.running = true;
    }

    function inspect(path): void {
        const target = String(path ?? "");
        if (target.length === 0) {
            inspectProcess.running = false;
            root.pendingInspectPath = "";
            root.metadata = null;
            root.inspecting = false;
            return;
        }
        root.pendingInspectPath = target;
        root.inspecting = true;
        inspectProcess.running = false;
        inspectProcess.command = ["python3", root.helperPath, "inspect", target, "--max-bytes", "131072"];
        inspectProcess.running = true;
    }

    function operate(action, options): bool {
        if (root.operating)
            return false;
        const data = options ?? ({});
        const command = ["python3", root.helperPath, "operate", String(action ?? "")];
        if (String(data.path ?? "").length > 0)
            command.push("--path", String(data.path));
        if (String(data.destination ?? "").length > 0)
            command.push("--destination", String(data.destination));
        if (String(data.name ?? "").length > 0)
            command.push("--name", String(data.name));
        if (data.paths !== undefined)
            command.push("--paths-json", JSON.stringify(Array.from(data.paths ?? [])));
        root.operationName = String(action ?? "");
        root.operating = true;
        operationProcess.running = false;
        operationProcess.command = command;
        operationProcess.running = true;
        return true;
    }

    Process {
        id: listProcess

        stdout: StdioCollector {
            id: listCollector
            onStreamFinished: {
                if (root.shuttingDown)
                    return;
                const reply = root.parseReply(listCollector.text, "list");
                const replyPath = String(reply.requestedPath ?? reply.path ?? "");
                if (replyPath.length > 0 && replyPath !== root.pendingListPath)
                    return;
                root.loading = false;
                if (!reply.ok) {
                    root.entries = [];
                    root.truncated = false;
                    root.errorText = String(reply.error ?? qsTr("Could not read this directory"));
                    return;
                }
                root.currentPath = String(reply.path ?? root.pendingListPath);
                root.entries = Array.from(reply.entries ?? []);
                root.truncated = reply.truncated === true;
                root.errorText = "";
                root.directoryLoaded(root.currentPath);
            }
        }
    }

    Process {
        id: inspectProcess

        stdout: StdioCollector {
            id: inspectCollector
            onStreamFinished: {
                if (root.shuttingDown)
                    return;
                const reply = root.parseReply(inspectCollector.text, "inspect");
                const replyPath = String(reply.requestedPath ?? reply.path ?? "");
                if (replyPath.length > 0 && replyPath !== root.pendingInspectPath)
                    return;
                root.inspecting = false;
                if (!reply.ok) {
                    root.metadata = null;
                    return;
                }
                root.metadata = reply.entry ?? null;
                root.previewLoaded(root.pendingInspectPath);
            }
        }
    }

    Process {
        id: operationProcess

        stdout: StdioCollector {
            id: operationCollector
            onStreamFinished: {
                if (root.shuttingDown)
                    return;
                const reply = root.parseReply(operationCollector.text, root.operationName);
                root.operating = false;
                const message = reply.ok
                    ? qsTr("File operation completed")
                    : String(reply.error ?? qsTr("File operation failed"));
                root.operationFinished(reply.ok === true, root.operationName, message, Array.from(reply.affected ?? []));
            }
        }
    }
}
