pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

/**
 * Normalized plan quotas and credit balances for supported AI clients.
 *
 * The Python helper owns provider dialects and credential-safe I/O. This
 * singleton owns user filtering, selection, refresh cadence and presentation
 * helpers, so changing Settings never launches a second subprocess by itself.
 */
Singleton {
    id: root

    property var providers: []
    property var items: []
    property bool refreshing: false
    property bool available: false
    property string errorMessage: ""
    property real lastUpdated: 0
    // Ephemeral by design: clicking the bar cycles the visible quota target
    // without turning that momentary choice into a persisted preference.
    // Antigravity model pools are targets of their own.
    property string activeTargetId: ""

    property string _lastSerialized: ""
    property bool _refreshQueued: false
    property bool _forceQueued: false

    readonly property var _cfg: Config.options?.bar?.aiPlanUsage ?? null
    readonly property bool enabled: root._cfg?.enabled ?? true
    readonly property bool autoRefresh: root._cfg?.autoRefresh ?? true
    readonly property int refreshInterval: Math.max(60000, root._cfg?.refreshInterval ?? 300000)
    readonly property bool claudeNetworkEnabled: root._cfg?.claudeNetworkEnabled ?? true
    readonly property string providerSignature: JSON.stringify(
        Array.from(root._cfg?.enabledProviders ?? ["chatgpt", "claude", "antigravity"]))

    readonly property int availableProviderCount: root.providers.filter(provider => provider.available).length
    readonly property var displayProviders: {
        const result = [];
        for (const provider of root.providers) {
            const providerId = String(provider.id ?? "");
            if (providerId !== "antigravity") {
                result.push(Object.assign({}, provider, {
                    providerId: providerId,
                    targetId: providerId
                }));
                continue;
            }

            const groupedItems = {};
            const discoveredGroups = [];
            for (const item of Array.from(provider.items ?? [])) {
                const groupId = String(item.groupId ?? "models") || "models";
                if (!groupedItems[groupId]) {
                    groupedItems[groupId] = [];
                    discoveredGroups.push(groupId);
                }
                groupedItems[groupId].push(item);
            }

            // Keep the two known Antigravity pools in a stable carousel order.
            const orderedGroups = ["gemini", "other"];
            for (const groupId of discoveredGroups) {
                if (orderedGroups.indexOf(groupId) < 0)
                    orderedGroups.push(groupId);
            }
            const presentGroups = orderedGroups.filter(groupId => groupedItems[groupId]);
            if (presentGroups.length === 0) {
                result.push(Object.assign({}, provider, {
                    providerId: "antigravity",
                    targetId: "antigravity"
                }));
                continue;
            }
            for (const groupId of presentGroups) {
                const groupItems = groupedItems[groupId];
                result.push(Object.assign({}, provider, {
                    id: "antigravity:" + groupId,
                    providerId: "antigravity",
                    targetId: "antigravity:" + groupId,
                    groupId: groupId,
                    name: "Antigravity · " + root.antigravityGroupName(groupId, groupItems),
                    available: groupItems.length > 0,
                    items: groupItems
                }));
            }
        }
        return result;
    }
    readonly property var cycleProviderIds: {
        const enabled = root.enabledProviderIds();
        const enabledTargets = root.displayProviders.filter(provider => {
            return enabled.indexOf(String(provider.providerId ?? provider.id ?? "")) >= 0;
        });
        const ready = enabledTargets.filter(provider => provider.available === true);
        const targets = ready.length > 0 ? ready : enabledTargets;
        return targets.map(provider => String(provider.targetId ?? provider.id ?? ""));
    }
    readonly property string displayedProviderId: {
        const providerIds = root.cycleProviderIds;
        if (providerIds.length === 0)
            return "";
        return providerIds.indexOf(root.activeTargetId) >= 0
            ? root.activeTargetId
            : String(providerIds[0]);
    }
    readonly property var selectedItems: {
        const provider = root.displayProviderById(root.displayedProviderId);
        const selected = [];
        const seen = {};
        if (!provider)
            return selected;

        const providerItems = Array.from(provider.items ?? []);
        const kindOrder = ["balance", "short", "weekly", "daily", "monthly"];
        for (const kind of kindOrder) {
            let best = null;
            for (const item of providerItems) {
                if (String(item.windowKind ?? "") !== kind)
                    continue;
                if (!best || Number(item.remainingPercent) < Number(best.remainingPercent))
                    best = item;
            }
            if (best && !seen[String(best.id)]) {
                selected.push(Object.assign({available: true}, best));
                seen[String(best.id)] = true;
            }
            if (selected.length >= 2)
                break;
        }
        if (selected.length === 0) {
            selected.push(root.windowPlaceholder(provider, "short"));
            selected.push(root.windowPlaceholder(provider, "weekly"));
        }
        return selected.slice(0, 2);
    }

    function enabledProviderIds(): var {
        return Array.from(root._cfg?.enabledProviders ?? ["chatgpt", "claude", "antigravity"]);
    }

    function providerById(providerId: string): var {
        for (const provider of root.providers) {
            if (String(provider.id) === providerId)
                return provider;
        }
        return null;
    }

    function displayProviderById(targetId: string): var {
        for (const provider of root.displayProviders) {
            if (String(provider.targetId ?? provider.id ?? "") === targetId)
                return provider;
        }
        return null;
    }

    function antigravityGroupName(groupId: string, groupItems): string {
        if (groupId === "gemini")
            return Translation.tr("Gemini");
        if (groupId === "other")
            return Translation.tr("Claude & GPT");
        const firstItem = Array.from(groupItems ?? [])[0];
        const reported = String(firstItem?.groupName ?? "");
        return reported.length > 0 ? reported : Translation.tr("Models");
    }

    function providerName(providerId: string): string {
        switch (providerId) {
        case "chatgpt": return "ChatGPT";
        case "claude": return "Claude";
        case "antigravity": return "Antigravity";
        case "zai": return "Z.AI GLM";
        case "kimi": return "Kimi Code";
        case "opencode": return "OpenCode Go";
        case "openrouter": return "OpenRouter";
        default: return Translation.tr("AI service");
        }
    }

    function providerIcon(providerId: string): string {
        switch (providerId) {
        case "chatgpt": return "openai-symbolic.svg";
        case "claude": return "bootstrap_claude.svg";
        case "antigravity": return "material-symbols_antigravity.svg";
        case "zai": return "Zai.png";
        case "kimi": return "MoonshotAI.png";
        case "opencode": return "opencode-logo-light.svg";
        case "openrouter": return "openrouter-symbolic.svg";
        default: return "material-symbols_antigravity.svg";
        }
    }

    function cycleProvider(): void {
        const providerIds = root.cycleProviderIds;
        if (providerIds.length <= 1)
            return;
        const currentIndex = Math.max(0, providerIds.indexOf(root.displayedProviderId));
        root.activeTargetId = String(providerIds[(currentIndex + 1) % providerIds.length]);
    }

    function windowPlaceholder(provider, kind: string): var {
        if (!provider)
            return null;
        if (["short", "daily", "weekly", "monthly"].indexOf(kind) < 0)
            kind = "short";
        const providerId = String(provider.providerId ?? provider.id ?? "");
        const targetId = String(provider.targetId ?? provider.id ?? providerId);
        const groupId = String(provider.groupId ?? "");
        const label = kind === "weekly" ? Translation.tr("Weekly")
            : kind === "daily" ? Translation.tr("Daily")
            : kind === "monthly" ? Translation.tr("Monthly")
            : Translation.tr("Short window");
        return {
            id: targetId + ":" + kind,
            providerId: providerId,
            providerName: String(provider.name ?? root.providerName(providerId)),
            providerIcon: root.providerIcon(providerId),
            groupId: groupId,
            groupName: groupId.length > 0 ? root.antigravityGroupName(groupId, []) : "",
            windowKind: kind,
            windowLabel: label,
            windowMinutes: 0,
            usedPercent: 0,
            remainingPercent: 0,
            resetsAt: 0,
            available: false
        };
    }

    function displayPercent(item): real {
        if (!item || item.available === false)
            return 0;
        const showUsed = String(item.metricKind ?? "quota") !== "credits"
            && (root._cfg?.percentMode ?? "remaining") === "used";
        return Math.max(0, Math.min(100,
            Number(showUsed ? item.usedPercent : item.remainingPercent) || 0));
    }

    function displayFraction(item): real {
        return root.displayPercent(item) / 100;
    }

    function percentText(item): string {
        if (!item || item.available === false)
            return "—";
        if (String(item.metricKind ?? "quota") === "credits")
            return root.creditAmountText(item, true);
        return String(Math.round(root.displayPercent(item))) + "%";
    }

    function creditAmountText(item, compact = false): string {
        const amount = Math.max(0, Number(item?.remainingAmount) || 0);
        const currency = String(item?.currency ?? "USD").toUpperCase();
        const prefix = currency === "USD" ? "$" : currency + " ";
        if (compact && amount >= 1000)
            return prefix + (amount / 1000).toFixed(amount >= 10000 ? 0 : 1) + "k";
        const decimals = compact ? (amount >= 100 ? 0 : amount >= 10 ? 1 : 2) : 2;
        return prefix + amount.toFixed(decimals);
    }

    function isLow(item): bool {
        if (!item || item.available === false)
            return false;
        const threshold = Math.max(0, Math.min(100, root._cfg?.lowRemainingThreshold ?? 20));
        return Number(item.remainingPercent) <= threshold;
    }

    function metricLabel(item = null): string {
        if (String(item?.metricKind ?? "quota") === "credits")
            return Translation.tr("remaining");
        return (root._cfg?.percentMode ?? "remaining") === "used"
            ? Translation.tr("used")
            : Translation.tr("remaining");
    }

    function itemTitle(item): string {
        if (!item)
            return Translation.tr("AI quota");
        const group = String(item.groupName ?? "");
        return group.length > 0
            ? String(item.providerName) + " · " + group
            : String(item.providerName);
    }

    function itemSubtitle(item): string {
        if (!item)
            return "";
        return String(item.windowLabel ?? "") + " · " + root.metricLabel(item);
    }

    function formatReset(resetsAt): string {
        const timestamp = Number(resetsAt) || 0;
        if (timestamp <= 0)
            return Translation.tr("Reset time unavailable");
        const seconds = Math.max(0, Math.round((timestamp - Date.now()) / 1000));
        if (seconds <= 0)
            return Translation.tr("Reset due");
        const minutes = Math.ceil(seconds / 60);
        if (minutes < 60)
            return Translation.tr("Resets in %1 min").arg(String(minutes));
        const hours = Math.floor(minutes / 60);
        const remainingMinutes = minutes % 60;
        if (hours < 24)
            return Translation.tr("Resets in %1 h %2 min").arg(String(hours)).arg(String(remainingMinutes));
        const days = Math.floor(hours / 24);
        const remainingHours = hours % 24;
        return Translation.tr("Resets in %1 d %2 h").arg(String(days)).arg(String(remainingHours));
    }

    function refresh(force = false): void {
        if (!root.enabled)
            return;
        if (root.refreshing) {
            root._refreshQueued = true;
            root._forceQueued = root._forceQueued || force;
            return;
        }
        const providerIds = root.enabledProviderIds();
        if (providerIds.length === 0) {
            root.providers = [];
            root.items = [];
            root.available = false;
            root.errorMessage = Translation.tr("Enable at least one AI service in Settings.");
            return;
        }
        root.refreshing = true;
        root.errorMessage = "";
        let command = [
            "python3",
            Directories.scriptPath + "/ai_plan_usage.py",
            "--providers",
            providerIds.join(","),
            "--claude-network",
            root.claudeNetworkEnabled ? "true" : "false"
        ];
        if (force)
            command.push("--force");
        collectProcess.exec(command);
    }

    function ensureFresh(): void {
        if (root.lastUpdated <= 0 || Date.now() - root.lastUpdated >= root.refreshInterval)
            root.refresh(false);
    }

    function applyPayload(payload): void {
        const nextProviders = Array.isArray(payload.providers) ? payload.providers : [];
        const nextItems = Array.isArray(payload.items) ? payload.items : [];
        const serialized = JSON.stringify({providers: nextProviders, items: nextItems});
        if (serialized !== root._lastSerialized) {
            root._lastSerialized = serialized;
            root.providers = nextProviders;
            root.items = nextItems;
        }
        root.available = payload.ok === true;
        root.lastUpdated = Number(payload.generatedAt) || Date.now();
        if (!root.available) {
            const errors = nextProviders
                .map(provider => String(provider.error ?? ""))
                .filter(message => message.length > 0);
            root.errorMessage = errors.length > 0
                ? errors.join(" · ")
                : Translation.tr("No plan quota is available yet.");
        }
    }

    onEnabledChanged: {
        if (root.enabled)
            configRefreshTimer.restart();
        else {
            root._refreshQueued = false;
            root._forceQueued = false;
        }
    }
    onProviderSignatureChanged: configRefreshTimer.restart()
    onClaudeNetworkEnabledChanged: configRefreshTimer.restart()

    Component.onCompleted: {
        if (root.enabled)
            root.refresh(false);
    }

    Timer {
        id: refreshTimer
        interval: root.refreshInterval
        repeat: true
        running: root.enabled && root.autoRefresh
        onTriggered: root.refresh(false)
    }

    Timer {
        id: configRefreshTimer
        interval: 80
        repeat: false
        onTriggered: {
            if (root.enabled)
                root.refresh(false);
        }
    }

    Process {
        id: collectProcess

        stdout: StdioCollector {
            id: collectOutput
        }

        onExited: exitCode => {
            root.refreshing = false;
            try {
                const payload = JSON.parse(collectOutput.text || "{}");
                root.applyPayload(payload);
                if (exitCode !== 0 && !root.available)
                    root.errorMessage = Translation.tr("AI quota collector exited with code %1.").arg(String(exitCode));
            } catch (error) {
                root.available = false;
                root.errorMessage = Translation.tr("AI quota collector returned invalid data.");
                console.error("[AiPlanUsage] Invalid collector payload:", error);
            }
            if (root._refreshQueued) {
                const force = root._forceQueued;
                root._refreshQueued = false;
                root._forceQueued = false;
                Qt.callLater(function() { root.refresh(force); });
            }
        }
    }
}
