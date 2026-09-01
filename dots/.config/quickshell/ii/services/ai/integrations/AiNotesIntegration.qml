pragma ComponentBehavior: Bound

import QtQuick
import qs.services

/** UI-independent notes adapter for reviewed assistant actions. */
QtObject {
    id: root

    readonly property int maximumTextLength: 4000

    function boundedText(value): string {
        return String(value ?? "").trim().slice(0, root.maximumTextLength);
    }

    function markdown(value): string {
        const text = root.boundedText(value);
        return text.replace(/\r\n/g, "\n").replace(/[ \t]+\n/g, "\n");
    }

    function references(): var {
        return Array.from(NotesService.snapshot().tabs ?? []).map((tab, index) => ({
            index: index,
            title: String(tab.title ?? "Tab " + (index + 1)),
            icon: String(tab.icon ?? "article")
        }));
    }

    function previewAppend(args): var {
        const index = Number(args?.tabIndex);
        const text = root.markdown(args?.text);
        const notes = root.references();
        if (!Number.isInteger(index) || index < 0 || index >= notes.length)
            return { ok: false, error: "unknownNote" };
        if (text.length === 0)
            return { ok: false, error: "emptyText" };
        return {
            ok: true,
            operation: "append",
            tabIndex: index,
            title: notes[index].title,
            text: text,
            destination: `Notes / ${notes[index].title}`,
            provenance: root.safeProvenance(args?.provenance)
        };
    }

    function previewCreate(args): var {
        const title = String(args?.title ?? "AI note").trim().slice(0, 120) || "AI note";
        const text = root.markdown(args?.text);
        if (text.length === 0)
            return { ok: false, error: "emptyText" };
        return {
            ok: true,
            operation: "create",
            title: title,
            text: text,
            destination: `Notes / ${title}`,
            provenance: root.safeProvenance(args?.provenance)
        };
    }

    function append(args): var {
        const preview = root.previewAppend(args);
        if (!preview.ok)
            return preview;
        return NotesService.append(preview.tabIndex, preview.text, preview.provenance);
    }

    function create(args): var {
        const preview = root.previewCreate(args);
        if (!preview.ok)
            return preview;
        return NotesService.create(preview.title, preview.text, preview.provenance);
    }

    function safeProvenance(value): var {
        const candidate = value ?? ({});
        return {
            sessionId: String(candidate.sessionId ?? "").slice(0, 120),
            messageId: String(candidate.messageId ?? "").slice(0, 120)
        };
    }
}
