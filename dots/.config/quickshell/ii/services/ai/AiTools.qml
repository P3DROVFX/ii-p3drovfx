import QtQuick
import Quickshell
import qs.services
import qs.services.ai
import qs.modules.common

/**
 * This chat's view of the tools, and the record of what they did.
 *
 * What a tool *is* lives in `AiToolRegistry`, once. What lives here is what
 * changes per chat and per user: which model is answering, what the policy
 * allows right now, the standing permission the user gave each tool, and the
 * log of calls. Splitting the two is what stopped the schema sent to the
 * model, the Tools page and the dispatcher from each carrying their own
 * slightly different copy of the rules.
 *
 * Nothing here executes a tool. The broker does that, and calls back in to
 * record what happened.
 */
Scope {
    id: root

    // ── This chat's situation ─────────────────────────────────────────────
    /** API dialect of the model in use, and whether it has search of its own. */
    property string apiFormat: "openai"
    property bool searchAvailable: false
    /** Profile-level exposure; permissions below remain per-tool approvals. */
    property string functionExposure: "all"
    property bool localOnly: false
    /** Whether the current policy lets anything reach the network at all. */
    property bool online: true
    /** off | auto | on — this chat's web mode, separate from the network policy above. */
    property string webMode: ""
    /** What the model itself can do, when it has been resolved. Null means unknown. */
    property var modelCapabilities: null

    /** Everything `AiToolRegistry.availability()` needs to decide. */
    readonly property var availabilityContext: ({
            format: root.apiFormat,
            searchAvailable: root.searchAvailable,
            exposure: root.functionExposure,
            localOnly: root.localOnly,
            online: root.online,
            webMode: root.webMode,
            capabilities: root.modelCapabilities,
            services: root.serviceAvailability
        })

    /** Services a tool may depend on, by the name it declares in `requiredServices`. */
    readonly property var serviceAvailability: ({
            memory: AiMemory.enabled,
            files: Ai.filesIntegration.rootsConfigured,
            ocr: Ai.ocrAvailable,
            sports: true,
            gmail: EmailService.authenticated,
            notes: NotesService.ready,
            tasks: true,
            rag: Ai.ragIntegration.ready
        })

    // ── Registry, passed through ──────────────────────────────────────────
    // Kept as this object's own API so every existing caller keeps working;
    // the definitions themselves are the registry's.
    readonly property var definitions: AiToolRegistry.definitions

    function definitionFor(id: string): var {
        return AiToolRegistry.definitionFor(id);
    }

    function titleFor(id: string): string {
        return AiToolRegistry.titleFor(id);
    }

    function describeArgs(id: string, args: var): string {
        return AiToolRegistry.describeArgs(id, args);
    }

    /** Why a tool is not on offer right now, empty when it is. */
    function unavailableReason(id: string): string {
        const def = AiToolRegistry.definitionFor(id);
        if (!def)
            return Translation.tr("Unknown tool");
        const verdict = AiToolRegistry.availability(def, root.contextFor(id));
        return verdict.available ? "" : verdict.reason;
    }

    function isAvailable(id: string): bool {
        const def = AiToolRegistry.definitionFor(id);
        if (!def)
            return false;
        return AiToolRegistry.availability(def, root.contextFor(id)).available;
    }

    /** The shared context plus this tool's standing permission. */
    function contextFor(id: string): var {
        return Object.assign({}, root.availabilityContext, {
            permission: root.permission(id)
        });
    }

    // ── Modes ─────────────────────────────────────────────────────────────
    readonly property string mode: Config.options?.ai?.tools?.mode ?? "functions"

    function modesFor(format: string): var {
        return AiToolRegistry.modesFor(format);
    }

    readonly property var availableModes: AiToolRegistry.modesFor(root.apiFormat)
    readonly property var modeDescriptions: AiToolRegistry.modeDescriptions
    readonly property var modeLabels: AiToolRegistry.modeLabels
    readonly property var searchPayloads: AiToolRegistry.searchPayloads

    // ── Permissions ───────────────────────────────────────────────────────
    // Two lists rather than a map: JsonAdapter stores list<string> honestly,
    // where a map with tool ids for keys has no schema to repair against.
    // A tool in neither list asks.
    readonly property var permissionValues: ["allow", "ask", "deny"]
    /** Conversation-scoped choices are supplied and persisted by Ai.qml. */
    property bool perConversationScope: false
    property var conversationPermissions: ({ "alwaysAllow": [], "alwaysDeny": [] })
    signal conversationPermissionsCommitted(var permissions)

    function permissionsForScope(): var {
        if (root.perConversationScope)
            return root.conversationPermissions ?? ({ "alwaysAllow": [], "alwaysDeny": [] });
        return Config.options?.ai?.tools ?? null;
    }

    /**
     * The answers a given tool may be given.
     *
     * A tool marked `neverAutoApprove` — the generic shell, today — cannot be
     * granted standing permission at all. It is not one capability that can be
     * trusted once; it is every capability, and the command differs each time.
     */
    function permissionValuesFor(id: string): var {
        const def = AiToolRegistry.definitionFor(id);
        if (def?.neverAutoApprove === true)
            return ["ask", "deny"];
        return root.permissionValues;
    }

    function permission(id: string): string {
        const def = AiToolRegistry.definitionFor(id);
        const tools = root.permissionsForScope();
        if (!tools)
            return def?.neverAutoApprove === true ? "ask" : "ask";
        if (Array.from(tools.alwaysDeny ?? []).indexOf(id) !== -1)
            return "deny";
        if (Array.from(tools.alwaysAllow ?? []).indexOf(id) !== -1) {
            // A standing "allow" left over in the config from before this rule
            // existed is read as "ask" rather than honoured.
            return def?.neverAutoApprove === true ? "ask" : "allow";
        }
        return "ask";
    }

    function setPermission(id: string, value: string) {
        const tools = root.permissionsForScope();
        if (!tools || root.permissionValuesFor(id).indexOf(value) === -1)
            return;
        const allow = Array.from(tools.alwaysAllow ?? []).filter(entry => entry !== id);
        const deny = Array.from(tools.alwaysDeny ?? []).filter(entry => entry !== id);
        if (value === "allow")
            allow.push(id);
        else if (value === "deny")
            deny.push(id);
        if (root.perConversationScope) {
            root.conversationPermissionsCommitted({
                "alwaysAllow": allow,
                "alwaysDeny": deny
            });
            return;
        }
        tools.alwaysAllow = allow;
        tools.alwaysDeny = deny;
    }

    readonly property var permissionLabels: ({
            "allow": Translation.tr("Always"),
            "ask": Translation.tr("Ask first"),
            "deny": Translation.tr("Never")
        })

    /** Whether a settings change is shown before it is written. */
    readonly property bool reviewsConfigChanges: Config.options?.ai?.tools?.reviewConfigChanges ?? true

    // ── Wire format ───────────────────────────────────────────────────────
    /** Tools offered to a model of this dialect, minus the refused ones. */
    function enabledFor(format: string): var {
        return AiToolRegistry.definitions.filter(def => AiToolRegistry.availability(def, Object.assign({}, root.availabilityContext, {
            format: format,
            permission: root.permission(def.id)
        })).available);
    }

    function functionSchema(def: var, format: string): var {
        return AiToolRegistry.functionSchema(def, format);
    }

    function wireTools(format: string, mode: string): var {
        if (mode === "none")
            return [];
        if (mode === "search")
            return AiToolRegistry.searchPayloads[format] ?? [];
        const enabled = root.enabledFor(format);
        if (enabled.length === 0)
            return [];
        if (format === "gemini")
            return [
                {
                    functionDeclarations: enabled.map(def => AiToolRegistry.functionSchema(def, format))
                }
            ];
        return enabled.map(def => AiToolRegistry.functionSchema(def, format));
    }

    // ── Call log ──────────────────────────────────────────────────────────
    // A tool call is the one thing the assistant does that outlives the chat
    // it was asked in, so it is worth a record that is not a chat bubble.
    readonly property int logSize: Math.max(0, Config.options?.ai?.tools?.logSize ?? 50)
    property var callLog: []
    property int callSerial: 0
    signal callCheckpointChanged(var entry)

    /** Records a call as it starts and returns the handle to finish it with. */
    function noteCall(id: string, args: var): int {
        if (root.logSize === 0)
            return -1;
        root.callSerial += 1;
        const def = AiToolRegistry.definitionFor(id);
        const entry = {
            serial: root.callSerial,
            id: id,
            title: AiToolRegistry.titleFor(id),
            icon: def?.icon ?? "build",
            detail: AiToolRegistry.describeArgs(id, args),
            status: "running",
            outcome: "",
            at: Date.now(),
            network: def?.network === "required",
            writes: def?.writes === true
        };
        root.callLog = [entry].concat(Array.from(root.callLog)).slice(0, root.logSize);
        root.callCheckpointChanged(entry);
        return entry.serial;
    }

    /** status: "done" | "refused" | "failed". */
    function finishCall(serial: int, status: string, outcome: string) {
        if (serial < 0)
            return;
        root.callLog = Array.from(root.callLog).map(entry => {
            if (entry.serial !== serial)
                return entry;
            const updated = {};
            for (const key in entry) {
                updated[key] = entry[key];
            }
            updated.status = status;
            updated.outcome = outcome;
            root.callCheckpointChanged(updated);
            return updated;
        });
    }

    function clearLog() {
        root.callLog = [];
    }
}
