pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions
import qs.services

/**
 * The one path by which the assistant reaches the filesystem by itself.
 *
 * Every other file a conversation ever sees was chosen by hand, through the
 * existing picker (`Ai.pickFiles()`) or a region capture. This adapter adds
 * exactly one more way in, and it is opt-in: `Config.options.ai.files.roots`
 * starts empty, and until the user names a directory there, `files_search`
 * has nothing to look in and says so rather than falling back to the home
 * directory.
 *
 * Nothing here reads a file itself. `scripts/ai/ai_attach.py` — already the
 * one place that turns a path into bytes for a request — does the search, the
 * metadata probe and the extraction; this adapter only shapes what comes back
 * and decides which paths may be asked about at all.
 */
QtObject {
    id: root

    readonly property string scriptPath: Directories.aiAttachScriptPath
    readonly property var roots: Array.from(Config.options?.ai?.files?.roots ?? [])
    readonly property bool rootsConfigured: root.roots.length > 0

    // Bytes of extracted text a single files_attach may return. Separate from
    // the tool's own token ceiling because this is measured before the
    // broker's cut, and a generous byte cap here still lets the broker's
    // token budget be the one that actually decides what the model sees.
    readonly property int maxAttachCharacters: 20000
    readonly property int maxPreviewCharacters: 800

    /**
     * The realpath of a root, or null if it is not currently a directory.
     * Matches `canonical_root` in ai_attach.py so the two never disagree
     * about what counts as "inside" a configured root.
     */
    function canonicalRoot(path: string): var {
        const trimmed = FileUtils.trimFileProtocol(String(path ?? "")).trim();
        return trimmed.length > 0 ? trimmed : null;
    }

    /** Whether a path — already resolved — sits inside a configured root. */
    function withinConfiguredRoots(path: string): bool {
        const target = String(path ?? "");
        if (target.length === 0)
            return false;
        return root.roots.some(configuredRoot => {
            const base = String(configuredRoot ?? "").replace(/\/+$/, "");
            return base.length > 0 && (target === base || target.startsWith(base + "/"));
        });
    }

    /**
     * Whether a path may be looked at at all: inside a configured root, or
     * already sitting in the conversation's own attachment queue — which
     * means a person picked it explicitly through the file dialog. A path the
     * model names out of thin air, matching neither, is refused before it is
     * ever opened.
     */
    function pathAllowed(path: string): bool {
        const target = String(path ?? "");
        if (target.length === 0)
            return false;
        if (root.withinConfiguredRoots(target))
            return true;
        return Array.from(Ai.attachments ?? []).some(file => String(file?.path ?? "") === target)
            || Array.from(Ai.pendingAttachmentPaths ?? []).indexOf(target) >= 0;
    }

    function humanSize(bytes: int): string {
        if (bytes >= 1024 * 1024)
            return Translation.tr("%1 MB").arg((bytes / (1024 * 1024)).toFixed(1));
        if (bytes >= 1024)
            return Translation.tr("%1 kB").arg(Math.round(bytes / 1024));
        return Translation.tr("%1 B").arg(bytes);
    }

    /**
     * Adds one folder to the opt-in list, trimmed and de-duplicated.
     *
     * The whole array is copied, changed, and reassigned rather than mutated
     * in place — a `list<string>` on a `JsonObject` only persists and only
     * notifies bindings when the property itself is set to a new value.
     */
    function addRoot(path: string): bool {
        const cleanPath = FileUtils.trimFileProtocol(String(path ?? "")).trim().replace(/\/+$/, "");
        if (cleanPath.length === 0)
            return false;
        const current = Array.from(Config.options?.ai?.files?.roots ?? []);
        if (current.indexOf(cleanPath) >= 0)
            return false;
        Config.options.ai.files.roots = [...current, cleanPath];
        return true;
    }

    function removeRoot(index: int): void {
        const current = Array.from(Config.options?.ai?.files?.roots ?? []);
        if (index < 0 || index >= current.length)
            return;
        current.splice(index, 1);
        Config.options.ai.files.roots = current;
    }

    /** A FileRef, trimmed to what a model can act on: no absolute-path noise. */
    function modelRef(entry: var): var {
        if (!entry)
            return null;
        return {
            path: String(entry.path ?? ""),
            name: String(entry.name ?? ""),
            kind: String(entry.kind ?? ""),
            size: root.humanSize(Number(entry.bytes ?? 0)),
            modifiedAt: entry.modifiedAt ? new Date(Number(entry.modifiedAt) * 1000).toISOString() : ""
        };
    }
}
