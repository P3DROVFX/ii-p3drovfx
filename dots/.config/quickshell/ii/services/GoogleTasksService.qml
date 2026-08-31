pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions

Singleton {
    id: root

    // ── Auth & Credentials ────────────────────────────────────────
    property bool credentialsConfigured: false
    property bool authenticating: false
    property bool reauthorizationRequired: false

    property string activeAccountEmail: ""
    property string activeAccountAvatar: ""
    property string refreshToken: ""

    property string accessToken: ""
    property int accessTokenExpiry: 0

    readonly property bool hasRefreshToken: root.refreshToken.length > 0
    readonly property bool available: root.credentialsConfigured && root.hasRefreshToken && !root.reauthorizationRequired

    // ── Data ──────────────────────────────────────────────────────
    property list<var> taskLists: []
    property var tasks: []

    readonly property string selectedTaskListId: (Config.options.todo && Config.options.todo.googleTasks)
        ? Config.options.todo.googleTasks.taskListId
        : ""
    readonly property string selectedTaskListTitle: (Config.options.todo && Config.options.todo.googleTasks)
        ? Config.options.todo.googleTasks.taskListTitle
        : ""

    // ── State ─────────────────────────────────────────────────────
    property bool syncing: false
    property string lastErrorCode: ""
    property string lastErrorMessage: ""
    property int lastHttpStatus: 0

    // Internal execution queue
    property string _pendingAction: ""
    property var _pendingPayload: null

    property list<var> _mutationQueue: []
    property bool _mutationRunning: false
    property var _currentMutation: null

    // ── Public API ────────────────────────────────────────────────

    function startOAuth() {
        if (root.authenticating)
            return;
        root.authenticating = true;
        root.lastErrorCode = "";
        root.lastErrorMessage = "";
        oauthProcess.command = [
            "python3",
            Directories.scriptPath + "/google/oauth.py",
            "--scope",
            "https://www.googleapis.com/auth/tasks email profile",
            "--port",
            "42070"
        ];
        oauthProcess.running = false;
        oauthProcess.running = true;
    }

    function disconnect() {
        root.accessToken = "";
        root.accessTokenExpiry = 0;
        root.refreshToken = "";
        root.activeAccountEmail = "";
        root.activeAccountAvatar = "";
        root.tasks = [];
        root.taskLists = [];
        root.reauthorizationRequired = false;
        root.lastErrorCode = "";
        root.lastErrorMessage = "";

        if (Config.options.todo && Config.options.todo.googleTasks) {
            Config.options.todo.googleTasks.taskListId = "";
            Config.options.todo.googleTasks.taskListTitle = "";
        }

        KeyringStorage.setNestedField(["google_tasks_accounts"], []);
        console.log("[GoogleTasks] Disconnected and credentials cleared from Keyring.");
    }

    function selectTaskList(id, title) {
        if (Config.options.todo && Config.options.todo.googleTasks) {
            Config.options.todo.googleTasks.taskListId = id;
            Config.options.todo.googleTasks.taskListTitle = title;
        }
        root.refresh();
    }

    function refresh() {
        if (!root.available || root.syncing)
            return;

        if (!root.selectedTaskListId) {
            root.refreshTaskLists();
            return;
        }

        root.syncing = true;
        root._ensureValidToken("fetchTasks", null);
    }

    function refreshTaskLists() {
        if (!root.available)
            return;
        root._ensureValidToken("fetchTaskLists", null);
    }

    function createTask(title, dueDate = "") {
        if (!root.available || !title || !title.trim())
            return;
        const body = { "title": title.trim() };
        const due = root._normalizedDueDate(dueDate);
        if (due)
            body.due = due;
        root._enqueueMutation("create", { "body": body });
    }

    function _normalizedDueDate(value) {
        if (!value)
            return "";
        // Google Tasks stores a date-only due date as midnight UTC. Extract the
        // calendar day before parsing so a west-of-UTC locale does not move a
        // newly created task to the previous day.
        const dateOnly = String(value).match(/^(\d{4}-\d{2}-\d{2})/);
        if (dateOnly)
            return dateOnly[1] + "T00:00:00.000Z";
        const parsed = value instanceof Date ? value : new Date(value);
        if (isNaN(parsed.getTime()))
            return "";
        return Qt.formatDate(parsed, "yyyy-MM-dd") + "T00:00:00.000Z";
    }

    function _localDueDate(value) {
        const match = String(value ?? "").match(/^(\d{4})-(\d{2})-(\d{2})/);
        if (!match)
            return new Date(value);
        return new Date(Number(match[1]), Number(match[2]) - 1, Number(match[3]));
    }

    function setTaskDone(task, done) {
        if (!task || !task.id)
            return;
        root._enqueueMutation("patch", {
            "taskId": task.id,
            "body": {
                "status": done ? "completed" : "needsAction"
            }
        });
    }

    function deleteTask(task) {
        if (!task)
            return;
        const taskId = typeof task === "object" ? task.id : String(task);
        if (!taskId)
            return;
        root._enqueueMutation("delete", {
            "taskId": taskId
        });
    }

    // ── Token Management & Dispatch ───────────────────────────────

    function _hasValidAccessToken() {
        const now = Math.floor(Date.now() / 1000);
        return root.accessToken.length > 0 && now < (root.accessTokenExpiry - 30);
    }

    function _ensureValidToken(nextAction, payload) {
        if (root._hasValidAccessToken()) {
            root._runAction(nextAction, payload);
            return;
        }

        if (!root.hasRefreshToken) {
            root.syncing = false;
            root.lastErrorCode = "missing_refresh_token";
            root.lastErrorMessage = Translation.tr("Google Tasks is not authorized.");
            return;
        }

        root._pendingAction = nextAction;
        root._pendingPayload = payload;

        tokenRefreshProcess.running = false;
        tokenRefreshProcess.stdinEnabled = true;
        tokenRefreshProcess.running = true;
    }

    function _runAction(action, payload) {
        switch (action) {
        case "fetchTasks":
            root._startFetchTasks();
            break;
        case "fetchTaskLists":
            root._startFetchTaskLists();
            break;
        case "mutation":
            root._startMutation(payload);
            break;
        default:
            root.syncing = false;
            break;
        }
    }

    function _handleTokenRefreshResult(output) {
        try {
            const res = JSON.parse(output.trim());
            if (res.ok) {
                root.accessToken = res.access_token || "";
                const expiresIn = res.expires_in || 3600;
                root.accessTokenExpiry = Math.floor(Date.now() / 1000) + expiresIn;
                root.reauthorizationRequired = false;

                const nextAction = root._pendingAction;
                const nextPayload = root._pendingPayload;
                root._pendingAction = "";
                root._pendingPayload = null;

                if (nextAction) {
                    root._runAction(nextAction, nextPayload);
                }
            } else {
                root.syncing = false;
                root.lastErrorCode = res.code || "token_refresh_failed";
                root.lastErrorMessage = res.message || "";
                if (res.reauthorization_required || res.code === "invalid_grant") {
                    root.reauthorizationRequired = true;
                    console.error("[GoogleTasks] OAuth token revoked or expired. Reauthorization required.");
                }
            }
        } catch (e) {
            root.syncing = false;
            root.lastErrorCode = "parse_error";
            root.lastErrorMessage = e.message;
        }
    }

    // ── API Fetch Handlers ────────────────────────────────────────

    function _startFetchTaskLists() {
        taskListsProcess.running = false;
        taskListsProcess.stdinEnabled = true;
        taskListsProcess.running = true;
    }

    function _handleTaskListsResult(output) {
        try {
            const res = JSON.parse(output.trim());
            if (res.ok) {
                const items = res.data && res.data.items ? res.data.items : [];
                root.taskLists = items;

                // Auto-select if nothing selected yet or currently selected is not found
                let found = false;
                for (let i = 0; i < items.length; ++i) {
                    if (items[i].id === root.selectedTaskListId) {
                        found = true;
                        break;
                    }
                }

                if ((!root.selectedTaskListId || !found) && items.length > 0) {
                    const first = items[0];
                    if (Config.options.todo && Config.options.todo.googleTasks) {
                        Config.options.todo.googleTasks.taskListId = first.id || "";
                        Config.options.todo.googleTasks.taskListTitle = first.title || "";
                    }
                }

                if (root.selectedTaskListId && root.syncing) {
                    root._startFetchTasks();
                } else {
                    root.syncing = false;
                }
            } else {
                root._handleApiError(res);
            }
        } catch (e) {
            root.syncing = false;
            root.lastErrorCode = "parse_error";
            root.lastErrorMessage = e.message;
        }
    }

    function _startFetchTasks() {
        fetchTasksProcess.running = false;
        fetchTasksProcess.stdinEnabled = true;
        fetchTasksProcess.running = true;
    }

    function _normalizeTask(raw) {
        const due = raw && raw.due ? root._localDueDate(raw.due) : new Date();
        return {
            "provider": "googleTasks",
            "id": String(raw?.id || ""),
            "containerId": root.selectedTaskListId,
            "content": String(raw?.title || ""),
            "done": String(raw?.status || "") === "completed",
            "date": due,
            "hasDate": !!(raw && raw.due),
            "notes": String(raw?.notes || ""),
            "updatedAt": String(raw?.updated || ""),
            "webViewLink": String(raw?.webViewLink || "")
        };
    }

    function _handleTasksResult(output) {
        root.syncing = false;
        try {
            const res = JSON.parse(output.trim());
            if (res.ok) {
                const rawItems = res.data && res.data.items ? res.data.items : [];
                const parsed = [];
                for (let i = 0; i < rawItems.length; ++i) {
                    parsed.push(root._normalizeTask(rawItems[i]));
                }
                root.tasks = parsed;
                root.lastErrorCode = "";
                root.lastErrorMessage = "";
                console.log("[GoogleTasks] Fetched " + parsed.length + " tasks from list \"" + root.selectedTaskListTitle + "\".");
            } else {
                root._handleApiError(res);
            }
        } catch (e) {
            root.lastErrorCode = "parse_error";
            root.lastErrorMessage = e.message;
        }
    }

    function _handleApiError(res) {
        root.syncing = false;
        root.lastErrorCode = res.code || "api_error";
        root.lastErrorMessage = res.message || "";
        root.lastHttpStatus = res.http_status || 0;

        if (res.http_status === 401) {
            root.accessToken = "";
            root.accessTokenExpiry = 0;
            root._ensureValidToken("fetchTasks", null);
            return;
        }

        if (res.http_status === 404) {
            console.warn("[GoogleTasks] Selected task list not found (404), refreshing task lists...");
            root.refreshTaskLists();
            return;
        }

        console.error("[GoogleTasks] API error (" + res.code + " / " + res.http_status + "): " + res.message);
    }

    // ── Mutation Queue ────────────────────────────────────────────

    function _enqueueMutation(operation, payload) {
        const item = {
            "operation": operation,
            "taskListId": root.selectedTaskListId,
            "taskId": payload.taskId || "",
            "body": payload.body || (payload.title ? { "title": payload.title } : {})
        };
        const queue = root._mutationQueue.slice();
        queue.push(item);
        root._mutationQueue = queue;

        if (!root._mutationRunning) {
            root._processNextMutation();
        }
    }

    function _processNextMutation() {
        if (root._mutationQueue.length === 0) {
            root._mutationRunning = false;
            root._currentMutation = null;
            root.refresh();
            return;
        }

        root._mutationRunning = true;
        root._currentMutation = root._mutationQueue[0];
        root._ensureValidToken("mutation", root._currentMutation);
    }

    function _startMutation(mutation) {
        mutationProcess.command = [
            "python3",
            Directories.scriptPath + "/google_tasks/api.py",
            mutation.operation
        ];
        mutationProcess.running = false;
        mutationProcess.stdinEnabled = true;
        mutationProcess.running = true;
    }

    function _handleMutationResult(output) {
        // Shift current mutation
        const queue = root._mutationQueue.slice();
        if (queue.length > 0)
            queue.shift();
        root._mutationQueue = queue;

        try {
            const res = JSON.parse(output.trim());
            if (!res.ok) {
                console.error("[GoogleTasks] Mutation failed: " + res.message);
                root.lastErrorCode = res.code || "mutation_error";
                root.lastErrorMessage = res.message || "";
            }
        } catch (e) {
            console.error("[GoogleTasks] Mutation parse error: " + e.message);
        }

        root._processNextMutation();
    }

    // ── Keyring & Credential Loading ──────────────────────────────

    function _checkCredentials() {
        checkCredsProcess.command = ["python3", Directories.scriptPath + "/google/check_credentials.py"];
        checkCredsProcess.running = false;
        checkCredsProcess.running = true;
    }

    function _loadStoredAccount() {
        if (!KeyringStorage.loaded)
            return;

        const kr = KeyringStorage.keyringData;
        if (!kr)
            return;

        let accounts = kr.google_tasks_accounts;
        if (Array.isArray(accounts) && accounts.length > 0) {
            const acc = accounts[0];
            root.activeAccountEmail = acc.email || "";
            root.activeAccountAvatar = acc.avatar || "";
            root.refreshToken = acc.refreshToken || "";
        } else if (kr.google_tasks_refresh_token) {
            root.activeAccountEmail = kr.google_tasks_email || "";
            root.activeAccountAvatar = kr.google_tasks_avatar || "";
            root.refreshToken = kr.google_tasks_refresh_token || "";
        }

        if (root.available && Config.options.todo && Config.options.todo.provider === "googleTasks") {
            root.refresh();
        }
    }

    Component.onCompleted: {
        root._checkCredentials();
        if (KeyringStorage.loaded) {
            root._loadStoredAccount();
        }
    }

    Connections {
        target: KeyringStorage

        function onLoadedChanged() {
            if (KeyringStorage.loaded) {
                root._loadStoredAccount();
            }
        }

        function onDataChanged() {
            if (KeyringStorage.loaded) {
                root._loadStoredAccount();
            }
        }
    }

    // ── Processes ─────────────────────────────────────────────────

    Process {
        id: checkCredsProcess
        command: ["python3", Directories.scriptPath + "/google/check_credentials.py"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text.trim());
                    root.credentialsConfigured = !!data.configured;
                } catch (e) {
                    root.credentialsConfigured = false;
                }
            }
        }
    }

    Process {
        id: oauthProcess
        command: ["python3", Directories.scriptPath + "/google/oauth.py"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.authenticating = false;
                try {
                    const res = JSON.parse(text.trim());
                    if (res.ok) {
                        root.refreshToken = res.refresh_token || "";
                        root.accessToken = res.access_token || "";
                        root.accessTokenExpiry = Math.floor(Date.now() / 1000) + (res.expires_in || 3600);
                        root.activeAccountEmail = res.email || "";
                        root.activeAccountAvatar = res.picture || "";
                        root.reauthorizationRequired = false;

                        // Save account to Gnome Keyring
                        const accounts = [{
                            "email": root.activeAccountEmail,
                            "avatar": root.activeAccountAvatar,
                            "refreshToken": root.refreshToken
                        }];
                        KeyringStorage.setNestedField(["google_tasks_accounts"], accounts);

                        console.log("[GoogleTasks] Authenticated as " + root.activeAccountEmail);
                        root.refreshTaskLists();
                    } else {
                        root.lastErrorCode = res.code || "oauth_failed";
                        root.lastErrorMessage = res.message || "";
                        console.error("[GoogleTasks] OAuth failed: " + res.message);
                    }
                } catch (e) {
                    root.lastErrorCode = "parse_error";
                    root.lastErrorMessage = e.message;
                }
            }
        }
        onExited: (code, status) => {
            root.authenticating = false;
        }
    }

    Process {
        id: tokenRefreshProcess
        command: ["python3", Directories.scriptPath + "/google/token_refresh.py"]
        stdinEnabled: true
        onRunningChanged: {
            if (running) {
                write(root.refreshToken + "\n");
                stdinEnabled = false;
            }
        }
        stdout: StdioCollector {
            onStreamFinished: {
                root._handleTokenRefreshResult(text);
            }
        }
    }

    Process {
        id: taskListsProcess
        command: ["python3", Directories.scriptPath + "/google_tasks/api.py", "tasklists"]
        stdinEnabled: true
        onRunningChanged: {
            if (running) {
                write(JSON.stringify({
                    "accessToken": root.accessToken
                }) + "\n");
                stdinEnabled = false;
            }
        }
        stdout: StdioCollector {
            onStreamFinished: {
                root._handleTaskListsResult(text);
            }
        }
    }

    Process {
        id: fetchTasksProcess
        command: ["python3", Directories.scriptPath + "/google_tasks/api.py", "tasks"]
        stdinEnabled: true
        onRunningChanged: {
            if (running) {
                write(JSON.stringify({
                    "accessToken": root.accessToken,
                    "taskListId": root.selectedTaskListId
                }) + "\n");
                stdinEnabled = false;
            }
        }
        stdout: StdioCollector {
            onStreamFinished: {
                root._handleTasksResult(text);
            }
        }
    }

    Process {
        id: mutationProcess
        command: ["python3", Directories.scriptPath + "/google_tasks/api.py", "patch"]
        stdinEnabled: true
        onRunningChanged: {
            if (running && root._currentMutation) {
                write(JSON.stringify({
                    "accessToken": root.accessToken,
                    "taskListId": root._currentMutation.taskListId || root.selectedTaskListId,
                    "taskId": root._currentMutation.taskId || "",
                    "body": root._currentMutation.body || {}
                }) + "\n");
                stdinEnabled = false;
            }
        }
        stdout: StdioCollector {
            onStreamFinished: {
                root._handleMutationResult(text);
            }
        }
    }
}
