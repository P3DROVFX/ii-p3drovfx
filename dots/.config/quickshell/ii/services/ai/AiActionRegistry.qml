pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs
import qs.modules.common
import qs.services

/**
 * Shared action and input vocabulary for every AI host.
 *
 * The registry deliberately contains metadata and validation only. A host
 * supplies its own callbacks, so Search and sidebar keep independent focus
 * and layout state while parsing the same commands and explaining disabled
 * actions in the same language.
 */
Singleton {
    id: root

    readonly property var actions: [
        { id: "send", icon: "arrow_upward", shortcut: "Enter", label: Translation.tr("Send"), requiresText: true },
        { id: "stop", icon: "stop", shortcut: "Esc", label: Translation.tr("Stop") },
        { id: "paste", icon: "content_paste", shortcut: "Ctrl+V", label: Translation.tr("Paste") },
        { id: "attach", icon: "attach_file", shortcut: "", label: Translation.tr("Attach files") },
        { id: "new-chat", icon: "add_comment", shortcut: "Ctrl+Shift+O", label: Translation.tr("New chat") },
        { id: "model", icon: "auto_awesome", shortcut: "", label: Translation.tr("Choose model") },
        { id: "provider", icon: "hub", shortcut: "", label: Translation.tr("Choose provider") },
        { id: "thinking", icon: "psychology", shortcut: "", label: Translation.tr("Thinking effort") },
        { id: "history", icon: "history", shortcut: "", label: Translation.tr("Chat history") },
        { id: "continue-sidebar", icon: "open_in_new", shortcut: "Ctrl+J", label: Translation.tr("Continue in sidebar") }
    ]

    readonly property var slashCommands: [
        { id: "attach", aliases: ["attach"] },
        { id: "model", aliases: ["model"] },
        { id: "provider", aliases: ["provider"] },
        { id: "tool", aliases: ["tool"] },
        { id: "prompt", aliases: ["prompt"] },
        { id: "persona", aliases: ["persona"] },
        { id: "save", aliases: ["save"] },
        { id: "load", aliases: ["load"] },
        { id: "chats", aliases: ["chats", "sessions", "history"] },
        { id: "clear", aliases: ["clear", "new", "newchat"] },
        { id: "temp", aliases: ["temp", "temperature"] },
        { id: "think", aliases: ["think", "thinking"] },
        { id: "web", aliases: ["web"] },
        { id: "tools", aliases: ["tools", "functions"] },
        { id: "effort", aliases: ["effort", "response", "reasoning"] },
        { id: "key", aliases: ["key"] }
    ]

    function definition(actionId: string): var {
        return root.actions.find(action => action.id === actionId) ?? null;
    }

    function commandDefinition(name: string): var {
        const needle = String(name ?? "").trim().toLowerCase();
        return root.slashCommands.find(command => command.aliases.indexOf(needle) >= 0) ?? null;
    }

    /** Parse exactly one command format for Search and sidebar. */
    function parseInput(text: string, prefix = "/"): var {
        const value = String(text ?? "");
        const trimmed = value.trim();
        if (!trimmed.startsWith(prefix) || trimmed.length <= prefix.length)
            return { kind: "prompt", text: value };

        const parts = trimmed.slice(prefix.length).split(/\s+/);
        const commandName = parts.shift();
        const definition = root.commandDefinition(commandName);
        if (!definition)
            return { kind: "unknown-command", name: commandName, args: parts, text: value };
        return {
            kind: "command",
            id: definition.id,
            name: definition.aliases[0],
            args: parts,
            text: value
        };
    }

    function availability(actionId: string, context = ({})): var {
        const action = root.definition(actionId);
        if (!action)
            return { enabled: false, reason: Translation.tr("This action is unavailable.") };
        if (action.sidebarOnly && context.surface !== "sidebar")
            return { enabled: false, reason: Translation.tr("This action is available in the sidebar.") };
        if (action.requiresText && context.text !== undefined && String(context.text).trim().length === 0)
            return { enabled: false, reason: Translation.tr("Write a message first.") };
        if (actionId === "send" && context.busy)
            return { enabled: false, reason: Translation.tr("The model is already responding.") };
        if (actionId === "stop" && !context.busy)
            return { enabled: false, reason: Translation.tr("Nothing is running.") };
        if (actionId === "paste" && context.canPaste === false)
            return { enabled: false, reason: Translation.tr("The clipboard has no pasteable content.") };
        return { enabled: true, reason: "" };
    }

    function tooltip(actionId: string, context = ({})): string {
        const action = root.definition(actionId);
        if (!action)
            return "";
        const status = root.availability(actionId, context);
        if (!status.enabled && status.reason.length > 0)
            return `${action.label}: ${status.reason}`;
        return action.shortcut.length > 0 ? `${action.label} (${action.shortcut})` : action.label;
    }
}
