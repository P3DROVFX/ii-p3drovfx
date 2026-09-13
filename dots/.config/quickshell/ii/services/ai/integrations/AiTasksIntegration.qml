pragma ComponentBehavior: Bound

import QtQuick
import qs.services

/**
 * Provider-neutral task contract for the assistant.
 *
 * The UI does not know whether a task lives in the local JSON file or in
 * TickTick. A provider is selected explicitly when supplied; otherwise the
 * connected TickTick account is the default and local tasks are the fallback.
 * No list is inferred from a sentence, and every external mutation carries the
 * journal operation id through to the helper callback.
 */
QtObject {
    id: root

    readonly property string localProviderId: "local"
    readonly property string tickTickProviderId: "ticktick"
    property var pendingOperations: ({})

    signal resultReady(string key, string operationId, var outcome)

    property Connections tickTickConnections: Connections {
        target: TickTickService

        function onAiOperationFinished(operationId, operation, ok, data, error) {
            const id = String(operationId ?? "");
            const job = root.pendingOperations[id];
            if (!job)
                return;
            delete root.pendingOperations[id];
            if (!ok) {
                const mutating = ["create", "update", "complete", "delete"].indexOf(String(operation)) >= 0;
                root.resultReady(job.key, id, {
                    status: mutating ? "needsInspection" : "error",
                    summary: String(error ?? qsTr("The task provider failed.")),
                    data: { provider: job.provider, operation: operation, error: String(error ?? "providerError") },
                    operationId: id,
                    retryable: false
                });
                return;
            }
            root.resultReady(job.key, id, root.providerOutcome(job, operation, data));
        }
    }

    function providerInfo(providerId) {
        const id = String(providerId ?? "");
        if (id === root.localProviderId)
            return { id: id, name: qsTr("Local tasks"), accountId: qsTr("This device"), available: true };
        if (id === root.tickTickProviderId)
            return { id: id, name: "TickTick", accountId: qsTr("Connected TickTick account"), available: TickTickService.available };
        return null;
    }

    function availableProviders() {
        const providers = [root.providerInfo(root.localProviderId)];
        if (TickTickService.available && !Ai.localOnly)
            providers.push(root.providerInfo(root.tickTickProviderId));
        return providers;
    }

    function resolveProvider(requested) {
        const wanted = String(requested ?? "").trim();
        const id = wanted.length > 0 ? wanted : (TickTickService.available && !Ai.localOnly ? root.tickTickProviderId : root.localProviderId);
        // TickTick needs its own network round trip; the local provider
        // never does. The tool itself is declared network:"optional" so it
        // can still serve the local list under Local-only, but this is the
        // one place every read and mutation funnels through, so it is where
        // that distinction actually gets enforced rather than assumed.
        if (Ai.localOnly && id !== root.localProviderId)
            return { ok: false, error: "TickTick needs the network, which the current policy does not allow. Use the local task list instead.", provider: id };
        const provider = root.providerInfo(id);
        if (!provider)
            return { ok: false, error: "Unknown task provider", provider: id };
        if (!provider.available)
            return { ok: false, error: "That task provider is not connected", provider: id };
        return { ok: true, provider: provider };
    }

    function listTaskLists(providerId) {
        const resolved = root.resolveProvider(providerId);
        if (!resolved.ok)
            return resolved;
        if (resolved.provider.id === root.localProviderId)
            return { ok: true, provider: resolved.provider, lists: Todo.aiListTaskLists() };
        return {
            ok: true,
            provider: resolved.provider,
            lists: [{
                id: TickTickService.inboxProjectId,
                name: "TickTick Inbox",
                accountId: resolved.provider.accountId
            }]
        };
    }

    function dueDate(raw) {
        const value = String(raw ?? "").trim();
        if (value.length === 0)
            return { value: null, display: qsTr("No due date") };
        const date = new Date(value);
        if (isNaN(date.getTime()))
            return { error: "Due date must be an ISO date or date-time" };
        return {
            value: date.toISOString(),
            display: date.toLocaleString()
        };
    }

    function normalizeCreate(args) {
        const resolved = root.resolveProvider(args?.provider);
        if (!resolved.ok)
            return resolved;
        const title = String(args?.title ?? "").trim();
        if (title.length === 0)
            return { ok: false, error: "A task needs a title" };
        if (title.length > 500)
            return { ok: false, error: "Task title is too long" };
        const date = root.dueDate(args?.dueDate);
        if (date.error)
            return { ok: false, error: date.error };
        const listId = String(args?.listId ?? (resolved.provider.id === root.tickTickProviderId ? TickTickService.inboxProjectId : Todo.aiListId));
        return {
            ok: true,
            provider: resolved.provider,
            providerId: resolved.provider.id,
            accountId: resolved.provider.accountId,
            listId: listId,
            listName: resolved.provider.id === root.tickTickProviderId ? "TickTick Inbox" : qsTr("Local tasks"),
            title: title,
            notes: String(args?.notes ?? "").slice(0, 4000),
            dueDate: date.value,
            dueDateDisplay: date.display,
            priority: args?.priority === undefined ? undefined : Number(args.priority)
        };
    }

    function normalizeRef(args) {
        const resolved = root.resolveProvider(args?.provider);
        if (!resolved.ok)
            return resolved;
        const taskId = String(args?.taskId ?? "").trim();
        if (taskId.length === 0)
            return { ok: false, error: "A real task id is required" };
        return {
            ok: true,
            provider: resolved.provider,
            providerId: resolved.provider.id,
            accountId: resolved.provider.accountId,
            listId: String(args?.listId ?? (resolved.provider.id === root.tickTickProviderId ? TickTickService.inboxProjectId : Todo.aiListId)),
            taskId: taskId
        };
    }

    function mapTask(raw, provider) {
        const task = raw ?? ({});
        const id = String(task.taskId ?? task.id ?? "");
        const title = String(task.title ?? task.content ?? "");
        return {
            provider: provider.id,
            accountId: provider.accountId,
            listId: String(task.listId ?? task.projectId ?? (provider.id === root.tickTickProviderId ? TickTickService.inboxProjectId : Todo.aiListId)),
            listName: provider.id === root.tickTickProviderId ? "TickTick Inbox" : qsTr("Local tasks"),
            taskId: id,
            title: title,
            notes: String(task.notes ?? task.desc ?? ""),
            dueLocal: task.dueDate ?? (task.hasDate ? new Date(task.date).toISOString() : null),
            status: task.done === true || task.status === 2 ? "completed" : "open"
        };
    }

    function listTasks(args, key) {
        const resolved = root.resolveProvider(args?.provider);
        if (!resolved.ok)
            return { status: "error", summary: resolved.error, data: resolved, retryable: true };
        if (resolved.provider.id === root.localProviderId) {
            const tasks = Todo.aiListTasks({ query: args?.query, listId: args?.listId, includeCompleted: args?.includeCompleted === true })
                .slice(0, Math.max(1, Math.min(50, Number(args?.limit ?? 50))));
            return {
                status: "success",
                summary: qsTr("%1 local tasks").arg(tasks.length),
                data: { provider: resolved.provider, tasks: tasks.map(task => root.mapTask(task, resolved.provider)) }
            };
        }
        const operationId = "tasks-list-" + String(key ?? "") + "-" + Date.now().toString(36);
        root.pendingOperations[operationId] = { key: String(key ?? ""), provider: resolved.provider, filters: args ?? ({}), operation: "list", operationId: operationId };
        if (!TickTickService.aiListTasks(operationId, args?.listId || TickTickService.inboxProjectId)) {
            delete root.pendingOperations[operationId];
            return { status: "error", summary: qsTr("TickTick is already busy"), data: null, retryable: true };
        }
        return { status: "pending" };
    }

    function searchTasks(args, key) {
        return root.listTasks(args, key);
    }

    function mutationOperation(input, key, operationId, operation, changes = null) {
        const id = String(operationId ?? "");
        const provider = input.provider;
        root.pendingOperations[id] = { key: String(key ?? ""), provider: provider, input: input, changes: changes, operation: operation, operationId: id };
        let sent = false;
        if (operation === "create")
            sent = TickTickService.aiCreateTask(id, input);
        else if (operation === "update")
            sent = TickTickService.aiUpdateTask(id, input, changes);
        else if (operation === "complete")
            sent = TickTickService.aiCompleteTask(id, input);
        else if (operation === "delete")
            sent = TickTickService.aiDeleteTask(id, input);
        if (!sent) {
            delete root.pendingOperations[id];
            return { status: "error", summary: qsTr("TickTick is already busy"), data: null, retryable: true };
        }
        return { status: "pending" };
    }

    function providerOutcome(job, operation, raw) {
        const base = job.input ?? ({});
        if (operation === "list") {
            const rawTasks = Array.from(raw?.tasks ?? []);
            const query = String(job.filters?.query ?? "").trim().toLowerCase();
            const tasks = rawTasks.map(task => root.mapTask(task, job.provider)).filter(task => {
                if (job.filters?.includeCompleted !== true && task.status === "completed")
                    return false;
                if (String(job.filters?.listId ?? "").length > 0 && String(job.filters.listId) !== task.listId)
                    return false;
                if (query.length === 0)
                    return true;
                return task.title.toLowerCase().includes(query) || task.notes.toLowerCase().includes(query);
            }).slice(0, Math.max(1, Math.min(50, Number(job.filters?.limit ?? 50))));
            return {
                status: "success",
                summary: qsTr("%1 tasks").arg(tasks.length),
                data: { provider: job.provider, tasks: tasks },
                operationId: String(job.operationId ?? ""),
                retryable: false
            };
        }
        const rawTask = raw?.task ?? raw;
        const taskSource = (rawTask?.id ?? rawTask?.taskId)
            ? rawTask
            : Object.assign({}, base, rawTask ?? ({}));
        const task = operation === "delete"
            ? root.mapTask(base, job.provider)
            : root.mapTask(taskSource, job.provider);
        return {
            status: "success",
            summary: operation === "create" ? qsTr("Task created in %1").arg(job.provider.name) : qsTr("Task updated in %1").arg(job.provider.name),
            data: { provider: job.provider, operation: operation, task: task, taskId: task.taskId },
            operationId: String(job.operationId ?? ""),
            retryable: false
        };
    }

    function createTask(args, key, operationId) {
        const input = root.normalizeCreate(args);
        if (!input.ok)
            return { status: "error", summary: input.error, data: input, retryable: true };
        if (input.providerId === root.localProviderId) {
            const result = Todo.aiCreateTask(input);
            return result.ok
                ? { status: "success", summary: qsTr("Task created locally"), data: { provider: input.provider, task: root.mapTask(result.task, input.provider), taskId: result.task.id }, operationId: operationId, retryable: false }
                : { status: "error", summary: result.error, data: result, retryable: false };
        }
        return root.mutationOperation(input, key, operationId, "create");
    }

    function updateTask(args, key, operationId) {
        const ref = root.normalizeRef(args);
        if (!ref.ok)
            return { status: "error", summary: ref.error, data: ref, retryable: true };
        const changes = {
            title: args?.title,
            notes: args?.notes,
            dueDate: args?.dueDate
        };
        if (ref.providerId === root.localProviderId) {
            const result = Todo.aiUpdateTask(ref, changes);
            return result.ok
                ? { status: "success", summary: qsTr("Task updated locally"), data: { provider: ref.provider, task: root.mapTask(result.task, ref.provider), taskId: ref.taskId }, operationId: operationId, retryable: false }
                : { status: "error", summary: result.error, data: result, retryable: false };
        }
        return root.mutationOperation(ref, key, operationId, "update", changes);
    }

    function completeTask(args, key, operationId) {
        const ref = root.normalizeRef(args);
        if (!ref.ok)
            return { status: "error", summary: ref.error, data: ref, retryable: true };
        if (ref.providerId === root.localProviderId) {
            const result = Todo.aiCompleteTask(ref);
            return result.ok
                ? { status: "success", summary: qsTr("Task completed locally"), data: { provider: ref.provider, task: root.mapTask(result.task, ref.provider), taskId: ref.taskId }, operationId: operationId, retryable: false }
                : { status: "error", summary: result.error, data: result, retryable: false };
        }
        return root.mutationOperation(ref, key, operationId, "complete");
    }

    function deleteTask(args, key, operationId) {
        const ref = root.normalizeRef(args);
        if (!ref.ok)
            return { status: "error", summary: ref.error, data: ref, retryable: true };
        if (ref.providerId === root.localProviderId) {
            const result = Todo.aiDeleteTask(ref);
            return result.ok
                ? { status: "success", summary: qsTr("Task deleted locally"), data: { provider: ref.provider, task: root.mapTask(result.task, ref.provider), taskId: ref.taskId }, operationId: operationId, retryable: false }
                : { status: "error", summary: result.error, data: result, retryable: false };
        }
        return root.mutationOperation(ref, key, operationId, "delete");
    }
}
