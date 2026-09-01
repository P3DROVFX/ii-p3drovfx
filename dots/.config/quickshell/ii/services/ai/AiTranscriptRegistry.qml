pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services
import qs.modules.common.functions

/**
 * Shared transcript vocabulary for every AI host.
 *
 * Rendering remains owned by each host so Search and the sidebar keep
 * independent viewport state. This singleton only normalises message blocks
 * and keyboard navigation decisions, preventing two transcript surfaces from
 * gradually growing different parsing or follow-scroll rules.
 */
Singleton {
    id: root

    readonly property list<string> rendererKinds: ["text", "code", "think", "table", "error", "config"]
    readonly property int followThreshold: 28

    function blocksForContent(content) {
        const blocks = StringUtils.splitMarkdownBlocks(String(content ?? ""));
        // Tables are pulled out of the prose here rather than in the splitter
        // so both transcripts get them, and so a host that does not know the
        // kind still has the original markdown in `content` to fall back on.
        const result = [];
        for (let i = 0; i < blocks.length; i++) {
            const block = blocks[i];
            if (block?.type !== "text") {
                result.push(block);
                continue;
            }
            const pieces = root.splitTables(String(block.content ?? ""));
            for (let at = 0; at < pieces.length; at++)
                result.push(pieces[at]);
        }
        return result;
    }

    /**
     * Splits prose into runs of text and whole tables.
     *
     * Qt's Markdown renderer draws a pipe table as a wall of pipes, and the
     * shell's own system prompt asks the model to compare things in tables —
     * so the one place it was guaranteed to be asked for was the one place it
     * could not be read.
     */
    function splitTables(text) {
        const lines = String(text ?? "").split("\n");
        const pieces = [];
        let prose = [];
        let at = 0;

        const flushProse = () => {
            const joined = prose.join("\n");
            if (joined.trim().length > 0)
                pieces.push({
                    type: "text",
                    content: joined
                });
            prose = [];
        };

        const isRow = line => /^\s*\|.*\|\s*$/.test(line);
        const isDivider = line => /^\s*\|?[\s:|-]*-[\s:|-]*\|?\s*$/.test(line) && line.indexOf("-") >= 0 && line.indexOf("|") >= 0;
        const cellsOf = line => line.trim().replace(/^\|/, "").replace(/\|$/, "").split("|").map(cell => cell.trim());

        while (at < lines.length) {
            const line = lines[at];
            const next = at + 1 < lines.length ? lines[at + 1] : "";
            if (isRow(line) && isDivider(next)) {
                flushProse();
                const header = cellsOf(line);
                const alignments = cellsOf(next).map(cell => {
                    const left = cell.startsWith(":");
                    const right = cell.endsWith(":");
                    if (left && right)
                        return "center";
                    if (right)
                        return "right";
                    return "left";
                });
                const rows = [];
                const raw = [line, next];
                at += 2;
                while (at < lines.length && isRow(lines[at])) {
                    rows.push(cellsOf(lines[at]));
                    raw.push(lines[at]);
                    at += 1;
                }
                pieces.push({
                    type: "table",
                    header: header,
                    alignments: alignments,
                    rows: rows,
                    columns: header.length,
                    content: raw.join("\n")
                });
                continue;
            }
            prose.push(line);
            at += 1;
        }
        flushProse();
        return pieces;
    }

    // ── The hello on an empty chat ────────────────────────────────────────
    // An empty chat should read like someone waiting, not like a model card.
    // The hour, the weekday and the account name steer which line greets the
    // reader, and every fresh empty state rolls again. It lives here because
    // both transcripts show one, and two copies would drift.

    readonly property string userName: {
        const raw = (Quickshell.env("USER") ?? "").trim();
        return raw.length === 0 ? "" : raw.charAt(0).toLocaleUpperCase() + raw.slice(1);
    }

    function rollLine(options) {
        if (options.length === 0)
            return "";
        return options[Math.floor(Math.random() * options.length)];
    }

    function greetingLine(): string {
        const now = new Date();
        const hour = now.getHours();
        const weekday = now.getDay(); // 0 Sunday … 6 Saturday
        const name = root.userName;
        const hey = name.length > 0 ? Translation.tr("Hey, %1").arg(name) : Translation.tr("Hey there");

        // Contextual lines: the clock and the calendar steer the roll without
        // ever making it deterministic.
        const contextual = [];
        if (hour >= 5 && hour < 12)
            contextual.push(name.length > 0 ? Translation.tr("Good morning, %1").arg(name) : Translation.tr("Good morning"));
        else if (hour >= 12 && hour < 18)
            contextual.push(name.length > 0 ? Translation.tr("Good afternoon, %1").arg(name) : Translation.tr("Good afternoon"));
        else if (hour >= 18 && hour < 23)
            contextual.push(name.length > 0 ? Translation.tr("Good evening, %1").arg(name) : Translation.tr("Good evening"));
        else {
            contextual.push(Translation.tr("Up late?"));
            contextual.push(Translation.tr("Burning the midnight oil?"));
        }
        if (weekday === 1)
            contextual.push(Translation.tr("Fresh week — where do we start?"));
        else if (weekday === 5)
            contextual.push(Translation.tr("Almost weekend. Anything to wrap up?"));
        else if (weekday === 0 || weekday === 6)
            contextual.push(Translation.tr("Weekend project time?"));

        const casual = [
            hey,
            Translation.tr("What are we making today?"),
            Translation.tr("What's on your mind?"),
            Translation.tr("Ready when you are"),
            Translation.tr("Where should we begin?"),
            Translation.tr("Ask me anything")
        ];

        return Math.random() < 0.5 ? root.rollLine(contextual) : root.rollLine(casual);
    }

    function blocksFor(message) {
        return root.blocksForContent(message?.content ?? message?.rawContent ?? "");
    }

    /**
     * The same blocks, but keeping the objects that did not change.
     *
     * A streaming answer only ever grows at its end, yet re-splitting it hands
     * every block back as a new object — and a ScriptModel reading identity
     * then throws away and rebuilds every delegate in the message on every
     * token. Reusing the leading blocks that are byte-for-byte identical
     * leaves only the last one to be rebuilt, which is the only one that
     * actually changed.
     */
    function reuseBlocks(previous, content) {
        const fresh = root.blocksForContent(content);
        const old = Array.from(previous ?? []);
        if (old.length === 0)
            return fresh;
        const limit = Math.min(old.length, fresh.length);
        for (let i = 0; i < limit; i++) {
            const before = old[i];
            const after = fresh[i];
            if (!before || !after)
                break;
            if (before.type !== after.type || before.content !== after.content)
                break;
            if (before.type === "code" && before.lang !== after.lang)
                break;
            if (before.type === "table" && String(before.content) !== String(after.content))
                break;
            fresh[i] = before;
        }
        return fresh;
    }

    function isRenderable(kind) {
        return root.rendererKinds.indexOf(String(kind ?? "")) >= 0;
    }

    /** Keep the transcript pinned only while the viewport is near its end. */
    function shouldFollow(contentY, viewportHeight, contentHeight, threshold) {
        const edge = threshold === undefined ? root.followThreshold : threshold;
        return contentY + viewportHeight >= contentHeight - edge;
    }

    /** Move focus through a stable id list without leaking host-local state. */
    function nextSelection(ids, currentId, delta) {
        const values = Array.from(ids ?? []);
        if (values.length === 0)
            return "";
        const current = values.indexOf(currentId);
        const start = current < 0 ? (delta >= 0 ? 0 : values.length - 1) : current;
        const next = Math.max(0, Math.min(values.length - 1, start + delta));
        return String(values[next]);
    }
}
