pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.modules.common
import qs.services
import qs.services.ai

/**
 * The one path by which the assistant searches folders the user indexed for
 * retrieval.
 *
 * `AiRagService` owns the collections, the Ollama model detection and every
 * index/status/delete process — the same singleton Settings drives to add a
 * folder, reindex it, or check its stats. This adapter only validates a
 * `rag_search` call against that state and shapes what comes back; it never
 * indexes anything and never runs a process of its own.
 */
QtObject {
    id: root

    readonly property bool ready: AiRagService.ready

    /** {id, name} for every collection actually on disk right now. */
    function collectionRefs(): var {
        return Array.from(AiRagService.collections ?? []).map(entry => ({
                    id: String(entry?.id ?? ""),
                    name: String(entry?.name ?? entry?.id ?? "")
                }));
    }

    function collectionName(id: string): string {
        const entry = AiRagService.collectionById(id);
        return String(entry?.name ?? id ?? "");
    }

    /**
     * Turns a `rag_search` call's arguments into the request `ai_rag.py`
     * expects, or `{error}` when nothing can be searched at all. Unknown
     * collection ids are dropped rather than rejected outright — the model
     * naming one that was deleted mid-conversation should still search
     * whatever remains, not fail the whole call.
     */
    function buildSearchRequest(args: var): var {
        if (!root.ready)
            return { error: Translation.tr("No indexed folders are configured. Add one in Settings first.") };
        const query = String(args?.query ?? "").trim();
        if (query.length === 0)
            return { error: Translation.tr("Nothing to search for") };
        const knownIds = Array.from(AiRagService.collections ?? []).map(entry => String(entry?.id ?? ""));
        const requestedIds = Array.from(args?.collectionIds ?? []).map(id => String(id)).filter(id => knownIds.indexOf(id) >= 0);
        const limit = Math.max(1, Math.min(10, Number(args?.limit ?? 5)));
        return {
            request: {
                indexDir: AiRagService.indexDir,
                query: query,
                embeddingModel: AiRagService.embeddingModel,
                ollamaUrl: AiRagService.ollamaUrl,
                limit: limit,
                collectionIds: requestedIds.length > 0 ? requestedIds : undefined
            },
            query: query
        };
    }

    /** One search hit, with the collection's own name attached for citing. */
    function resultRef(hit: var): var {
        if (!hit)
            return null;
        return {
            collection: root.collectionName(hit.collectionId),
            file: String(hit.file ?? ""),
            startLine: hit.startLine ?? null,
            endLine: hit.endLine ?? null,
            score: hit.score ?? null,
            snippet: String(hit.snippet ?? "")
        };
    }
}
