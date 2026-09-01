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
        onTriggered: {
            root.updateCombinedAgents();
        }
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

        root.agents = list.sort((left, right) => Number(left.priority ?? 20) - Number(right.priority ?? 20));
    }
}
