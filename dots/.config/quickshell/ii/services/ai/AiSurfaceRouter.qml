pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Hyprland

/**
 * Single owner for AI deep-links between the Search and sidebar surfaces.
 * Hosts consume pendingIntent and acknowledge it after the requested page is
 * actually visible; opening a surface never relies on a delayed callback.
 */
Scope {
    id: root

    property int requestSequence: 0
    property var pendingIntent: null

    signal requestOpened(var intent)
    signal requestAcknowledged(string requestId)

    // Router payloads are deliberately plain data. Do not put QML Items,
    // delegates, or other object references here: a host can be destroyed by
    // hot reload while a handoff is still waiting for its session to load.
    function normaliseAnchor(anchor) {
        const source = anchor && typeof anchor === "object" ? anchor : ({});
        const rawOffset = Number(source.offset ?? 0);
        return {
            messageId: String(source.messageId ?? ""),
            blockId: String(source.blockId ?? ""),
            offset: isFinite(rawOffset) ? Math.max(0, rawOffset) : 0,
            following: source.following === true
        };
    }

    // Rich activity blocks will gain their own ids in the renderer schema.
    // Until then, resolve the block to its containing message when a provider
    // already supplied a compatible field. A missing block remains pending so
    // the destination can retry when the streamed message arrives.
    function resolveTargetMessageId(intent) {
        const requested = String(intent?.messageId ?? "");
        const blockId = String(intent?.blockId ?? "");
        if (requested.length > 0)
            return requested;
        if (blockId.length === 0)
            return "";

        const ids = Array.from(Ai.messageIDs ?? []);
        for (let i = 0; i < ids.length; i++) {
            const id = String(ids[i]);
            const message = Ai.messageByID?.[id];
            if (!message)
                continue;
            if (String(message.blockId ?? "") === blockId || String(message.activityId ?? "") === blockId || String(message.id ?? "") === blockId)
                return id;

            const blocks = Array.from(message.blocks ?? message.thinkingBlocks ?? message.activityEvents ?? []);
            for (let j = 0; j < blocks.length; j++) {
                const block = blocks[j];
                if (String(block?.id ?? block?.blockId ?? block?.activityId ?? "") === blockId)
                    return id;
            }
        }
        return "";
    }

    function nextRequestId() {
        root.requestSequence += 1;
        return `ai-surface-${Date.now()}-${root.requestSequence}`;
    }

    function open(intent = null) {
        const requested = intent ?? ({});
        const surface = requested.surface === "sidebar" ? "sidebar" : "search";
        const monitorName = String(requested.monitorName ?? requested.screenName ?? Hyprland.focusedMonitor?.name ?? "");
        const normalized = Object.assign({}, requested, {
            requestId: root.nextRequestId(),
            surface: surface,
            monitorName: monitorName,
            sessionId: String(requested.sessionId ?? ""),
            messageId: String(requested.messageId ?? ""),
            blockId: String(requested.blockId ?? ""),
            focusIntent: String(requested.focusIntent ?? requested.focus ?? "composer"),
            scrollAnchor: root.normaliseAnchor(requested.scrollAnchor)
        });
        root.pendingIntent = normalized;
        if (surface === "sidebar") {
            GlobalStates.activeLeftSidebarMonitor = monitorName;
            Persistent.states.sidebar.policies.tab = 0;
            GlobalStates.overviewOpen = false;
            GlobalStates.policiesPanelOpen = true;
        } else {
            GlobalStates.activeSearchMonitor = monitorName;
            // Search hosts consume this prefix through their normal mode
            // detection; assigning the service query also handles an already
            // open Overview without relying on a delayed callback.
            GlobalStates.activeSearchQuery = Config.options.search.prefix.ai;
            LauncherSearch.query = Config.options.search.prefix.ai;
            GlobalStates.overviewOpen = true;
            GlobalStates.policiesPanelOpen = false;
        }
        root.requestOpened(normalized);
        return normalized.requestId;
    }

    function acknowledge(requestId: string) {
        if (!root.pendingIntent || root.pendingIntent.requestId !== requestId)
            return false;
        root.pendingIntent = null;
        root.requestAcknowledged(requestId);
        return true;
    }
}
