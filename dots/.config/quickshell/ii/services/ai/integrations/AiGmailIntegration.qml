pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common
import qs.services

/**
 * Read-only Gmail boundary for AI calls.
 *
 * The helper owns the API shape and metadata-before-body rule. This object
 * owns only process correlation and the one safe navigation affordance that
 * opens II's existing Email tab without changing the email service models.
 */
QtObject {
    id: root

    readonly property string scriptPath: Directories.scriptPath + "/ai/ai_gmail.py"
    readonly property bool available: EmailService.authenticated === true
    property var pendingRequests: ({})

    signal resultReady(string key, string callId, string sessionId, var outcome)

    property Component requestComponent: Component {
        id: requestComponent

        Process {
            id: worker
            property string requestKey: ""
            property string expectedCallId: ""
            property string sessionId: ""
            property string operation: ""
            stdinEnabled: true
            command: ["python3", root.scriptPath]

            stdout: StdioCollector {
                onStreamFinished: root.finishProcess(worker, text, 0)
            }
            stderr: StdioCollector {
                onStreamFinished: worker.errorText = text.trim().slice(0, 400)
            }
            property string errorText: ""
            onExited: (exitCode, exitStatus) => root.finishProcess(worker, "", exitCode)
        }
    }

    function tokenFor(accountId): string {
        const wanted = String(accountId ?? "").trim();
        if (wanted.length === 0 || wanted === String(EmailService.userEmail ?? ""))
            return String(EmailService._getBestToken() ?? "");
        for (const account of Array.from(EmailService.accounts ?? [])) {
            if (String(account?.email ?? "") === wanted)
                return String(account?.refreshToken ?? "");
        }
        return "";
    }

    function request(operation, key, callId, sessionId, args): var {
        if (!root.available)
            return { status: "unavailable", summary: "Gmail is not authenticated", data: null, retryable: false };
        const token = root.tokenFor(args?.accountId);
        if (token.length === 0)
            return { status: "error", summary: "The requested Gmail account is unavailable", data: null, retryable: false };

        const requestKey = String(key);
        if (root.pendingRequests[requestKey] !== undefined)
            return { status: "pending" };
        const worker = requestComponent.createObject(root, {
            requestKey: requestKey,
            expectedCallId: String(callId ?? ""),
            sessionId: String(sessionId ?? ""),
            operation: operation
        });
        if (!worker)
            return { status: "error", summary: "Could not start the Gmail reader", data: null, retryable: true };

        root.pendingRequests = Object.assign({}, root.pendingRequests, { [requestKey]: worker });
        worker.running = true;
        worker.write(JSON.stringify(Object.assign({}, args ?? ({}), {
            operation: operation,
            callId: String(callId ?? ""),
            token: token
        })) + "\n");
        worker.stdinEnabled = false;
        return { status: "pending" };
    }

    function finishProcess(worker, output, exitCode): void {
        if (!worker || root.pendingRequests[worker.requestKey] !== worker)
            return;
        const next = ({ });
        for (const key in root.pendingRequests) {
            if (key !== worker.requestKey)
                next[key] = root.pendingRequests[key];
        }
        root.pendingRequests = next;

        let outcome = null;
        try {
            const parsed = JSON.parse(String(output ?? "").trim());
            if (String(parsed.callId ?? "") !== worker.expectedCallId) {
                outcome = { status: "error", summary: "Gmail response correlation failed", data: null, retryable: true };
            } else if (parsed.ok !== true) {
                outcome = { status: "error", summary: String(parsed.error ?? "Gmail request failed"), data: null, retryable: exitCode !== 0 };
            } else {
                outcome = { status: "success", summary: "Gmail data loaded", data: parsed.data ?? ({}) };
            }
        } catch (error) {
            outcome = { status: "error", summary: worker.errorText || "Gmail returned invalid JSON", data: null, retryable: true };
        }
        root.resultReady(worker.requestKey, worker.expectedCallId, worker.sessionId, outcome);
        worker.destroy();
    }

    function search(key, callId, sessionId, args): var {
        return root.request("search", key, callId, sessionId, args);
    }

    function getMessage(key, callId, sessionId, args): var {
        return root.request("get", key, callId, sessionId, args);
    }

    function getThread(key, callId, sessionId, args): var {
        return root.request("thread", key, callId, sessionId, args);
    }

    function emailTabIndex(): int {
        let index = 0;
        if (Config.options.cheatsheet.enableTimetable)
            index += 1;
        index += 1;
        if (Config.options.cheatsheet.enablePeriodicTable)
            index += 1;
        if (Config.options.cheatsheet.enableAminoAcids)
            index += 1;
        if (Config.options.cheatsheet.enableCommands)
            index += 1;
        if (Config.options.cheatsheet.enableWorkspaceProfiles)
            index += 1;
        return Config.options.cheatsheet.enableGmail ? index : -1;
    }

    function openInClient(args): var {
        const index = root.emailTabIndex();
        if (index < 0)
            return { status: "error", summary: "The Gmail tab is disabled in Cheatsheet", data: null, retryable: false };
        Persistent.states.cheatsheet.tabIndex = index;
        GlobalStates.cheatsheetOpen = true;
        return {
            status: "success",
            summary: "Gmail tab opened",
            data: {
                opened: true,
                messageId: String(args?.messageId ?? ""),
                threadId: String(args?.threadId ?? ""),
                accountId: String(args?.accountId ?? EmailService.userEmail ?? "")
            }
        };
    }

    function abortAll(): void {
        const workers = Object.values(root.pendingRequests);
        root.pendingRequests = ({ });
        for (const worker of workers) {
            worker.running = false;
            worker.destroy();
        }
    }
}
