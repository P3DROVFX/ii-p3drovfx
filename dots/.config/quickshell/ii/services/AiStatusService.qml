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
            agent.id, agent.state, agent.requiresAttention === true, agent.name
        ].join(":")).join("|");
    }

    property string _agentsSignature: ""

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

    Timer {
        id: ticker
        interval: 1000
        repeat: true
        running: root.hasActiveAgents
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
                "state": attention.needsAction ? "needsAction" : ((msg && msg.thinking) ? "thinking" : "streaming"),
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

        const signature = root.agentsSignature(list);
        if (signature === root._agentsSignature)
            return;
        root._agentsSignature = signature;
        root.agents = list;
    }
}
