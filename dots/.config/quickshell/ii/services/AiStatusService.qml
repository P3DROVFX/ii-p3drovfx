pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import qs
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property var cliAgents: []
    property var agents: []
    readonly property bool hasActiveAgents: agents.length > 0
    readonly property var primaryAgent: hasActiveAgents ? agents[0] : null
    readonly property int agentCount: agents.length

    property int _internalStartTime: 0

    // Wall clock in seconds, and the only thing that moves while an agent works.
    // `agents` used to be rebuilt every second just to carry a new runtime; because the
    // island keys its Repeater off that array, every widget was destroyed and recreated
    // once a second, which restarted their entry animations and their internal state.
    // Consumers now render `runtimeFor(agent)` against this tick instead.
    property int nowSeconds: Math.floor(Date.now() / 1000)

    // Live token counts for the built-in chat. Kept out of `agents` so a streaming
    // response does not count as a change to the agent set.
    readonly property int internalTokensIn: (typeof Ai !== "undefined" && Ai.tokenCount.input > 0) ? Ai.tokenCount.input : 0
    readonly property int internalTokensOut: (typeof Ai !== "undefined" && Ai.tokenCount.output > 0) ? Ai.tokenCount.output : 0

    /**
     * What an agent is doing, in words.
     *
     * The island used to show a name and a clock and nothing else, so "thinking",
     * "running a command", "waiting for you to answer" and "finished" all looked
     * identical. The CLI reports these through its hooks; the built-in chat reports the
     * same vocabulary, so one function covers both.
     */
    function statusLabel(agent) {
        if (!agent)
            return "";
        const tool = agent.tool ?? "";
        switch (agent.state) {
        case "working":
            return Translation.tr("Working");
        case "thinking":
            return Translation.tr("Thinking");
        case "streaming":
            return Translation.tr("Answering");
        case "tool":
            return tool !== "" ? Translation.tr("Running %1").arg(tool) : Translation.tr("Running a tool");
        case "asking":
            return Translation.tr("Waiting for your answer");
        case "needsAction":
            return Translation.tr("Needs your approval");
        case "compacting":
            return Translation.tr("Compacting");
        case "interrupted":
            return Translation.tr("Interrupted");
        case "done":
            return Translation.tr("Done");
        case "waitingInput":
            return Translation.tr("Waiting for you");
        case "running":
            // The CPU fallback knows only that something is happening.
            return Translation.tr("Working");
        }
        return Translation.tr("Active");
    }

    /** A token count at a glance: three significant figures at most, never a wall. */
    function formatTokens(count) {
        const value = count ?? 0;
        if (value <= 0)
            return "";
        if (value < 1000)
            return String(value);
        if (value < 1000000)
            return (value / 1000).toFixed(value < 10000 ? 1 : 0) + "k";
        return (value / 1000000).toFixed(1) + "M";
    }

    function runtimeFor(agent) {
        if (!agent)
            return 0;
        const startedAt = agent.startedAtEpoch ?? 0;
        if (startedAt > 0)
            return Math.max(0, root.nowSeconds - startedAt);
        return agent.runtime ?? 0;
    }

    // What the island actually distinguishes. Runtime and token counts are excluded on
    // purpose: they change constantly and would defeat the whole point.
    function agentsSignature(list) {
        return list.map(agent => [
            agent.id, agent.state, agent.tool ?? "", agent.requiresAttention === true, agent.name,
            agent.announce === true
        ].join(":")).join("|");
    }

    property string _agentsSignature: ""

    /**
     * The numbers that move while an agent works, keyed by agent id.
     *
     * Kept out of `agents` deliberately. That array is only reassigned when the *set*
     * changes, because the island keys a Repeater off it and a new array rebuilds every
     * delegate; token counts change several times a turn and would do exactly that. The
     * presentations read these through `metricsFor()` instead, so a growing count
     * repaints a label and nothing else.
     */
    property var agentMetrics: ({})

    readonly property var emptyMetrics: ({ tokensIn: 0, tokensOut: 0, model: "", tool: "", cwd: "" })

    function metricsFor(agent) {
        if (!agent || !agent.id)
            return root.emptyMetrics;
        return root.agentMetrics[agent.id] ?? root.emptyMetrics;
    }

    function updateMetrics(list) {
        const next = {};
        for (let i = 0; i < list.length; i++) {
            const agent = list[i];
            next[agent.id] = {
                tokensIn: agent.tokensIn ?? 0,
                tokensOut: agent.tokensOut ?? 0,
                model: agent.model ?? "",
                tool: agent.tool ?? "",
                cwd: agent.cwd ?? ""
            };
        }
        root.agentMetrics = next;
    }

    // Monitor for CLI AI agents
    Process {
        id: monitorProc
        running: Config.ready && (!Config.options?.bar?.floatingNotch?.disableAiStatus)
        command: ProcUtils.pdeath(["python3", Quickshell.shellPath("services/ai_status_monitor.py")])

        stdout: SplitParser {
            onRead: line => {
                if (!line || line.length === 0)
                    return;
                try {
                    let data = JSON.parse(line);
                    if (data && Array.isArray(data.agents)) {
                        root.cliAgents = data.agents;
                        root.updateCombinedAgents();
                    }
                } catch (e) {
                    console.warn("[AiStatusService] JSON parse error:", e.message);
                }
            }
        }
    }

    // Monitor internal built-in Ai service activity
    readonly property bool internalAiActive: AiAttentionService.active

    onInternalAiActiveChanged: {
        if (internalAiActive) {
            root._internalStartTime = Math.floor(Date.now() / 1000);
        } else {
            root._internalStartTime = 0;
        }
        root.updateCombinedAgents();
    }

    // A session resting on a finished turn shows a stopped clock, and can sit there for
    // hours; only a turn that is still running has anything to count.
    readonly property bool hasRunningClock: agents.some(agent => (agent.startedAtEpoch ?? 0) > 0)

    Timer {
        id: ticker
        interval: 1000
        repeat: true
        triggeredOnStart: true
        running: root.hasRunningClock
        onTriggered: root.nowSeconds = Math.floor(Date.now() / 1000)
    }

    function updateCombinedAgents() {
        let list = [];

        // 1. Internal built-in AI agent (if active)
        if (root.internalAiActive && typeof Ai !== "undefined") {
            let lastId = Ai.messageIDs[Ai.messageIDs.length - 1];
            let msg = Ai.messageByID[lastId];
            let nowSecs = Math.floor(Date.now() / 1000);
            let runtime = root._internalStartTime > 0 ? (nowSecs - root._internalStartTime) : 0;
            const attention = AiAttentionService.snapshot();

            list.push({
                "id": "internal_ai",
                "pid": 0,
                "name": "ii AI Chat",
                "icon": "google-gemini-symbolic",
                "color": Appearance.colors.colPrimary,
                "runtime": runtime,
                "startedAtEpoch": root._internalStartTime,
                "state": attention.needsAction ? "needsAction" : ((msg && msg.thinking) ? "thinking" : "working"),
                "tool": "",
                "priority": attention.needsAction ? 0 : 10,
                "requiresAttention": attention.needsAction,
                "deepLink": attention.deepLink,
                "source": "internal",
                "model": Ai.currentModelEntry?.title || "built-in",
                "tokensIn": Ai.tokenCount.input > 0 ? Ai.tokenCount.input : 0,
                "tokensOut": Ai.tokenCount.output > 0 ? Ai.tokenCount.output : 0
            });
        }

        // 2. Add CLI agents
        for (let i = 0; i < root.cliAgents.length; i++) {
            list.push(root.cliAgents[i]);
        }

        list.sort((left, right) => Number(left.priority ?? 20) - Number(right.priority ?? 20));

        // Always, even when the set is unchanged: this is the channel the live numbers
        // travel on.
        root.updateMetrics(list);

        const signature = root.agentsSignature(list);
        if (signature === root._agentsSignature)
            return;
        root._agentsSignature = signature;
        root.agents = list;
    }
}
