pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    // property string cliphistBinary: FileUtils.trimFileProtocol(`${Directories.home}/.cargo/bin/stash`)
    property string cliphistBinary: "cliphist"
    property real pasteDelay: 0.05
    property string pressPasteCommand: "wtype -M ctrl -k v -m ctrl"
    property bool sloppySearch: Config.options?.search.clipboard.enableSloppySearch ?? Config.options?.search.sloppy ?? false
    property bool levenshteinSearch: (Config.options?.search.levenshtein ?? false) || (Config.options?.search.algorithm === "levenshtein")
    property real scoreThreshold: 0.2
    property list<string> entries: []
    readonly property var preparedEntries: entries.map(a => ({
        name: Fuzzy.prepare(`${a.replace(/^\s*\S+\s+/, "")}`),
        entry: a
    }))

    // Computed filtered lists for 3-column clipboard panel
    readonly property var textEntries: entries.filter(e => !entryIsImage(e) && !isPinned(e))
    readonly property var imageEntries: entries.filter(e => entryIsImage(e) && !isPinned(e))

    /**
     * Classify clipboard entry content for smart rendering.
     * Returns: "hex-color", "url", "email", "phone", "json", "markdown", "filepath", "multiline", "number", or ""
     */
    function classifyEntry(entry) {
        if (!entry) return "";
        // Strip cliphist ID prefix
        const content = entry.replace(/^\s*\S+\s+/, "").trim();
        if (content.length === 0) return "";

        const detectors = Config.options?.search?.clipboard?.detectors;

        // Hex color
        if (detectors?.hexColor !== false && /^#([0-9A-Fa-f]{3,4}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$/.test(content))
            return "hex-color";

        // URL
        if (detectors?.url !== false && /^https?:\/\/\S+/.test(content))
            return "url";

        // Email
        if (detectors?.email !== false && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(content))
            return "email";

        // Phone
        if (detectors?.phone !== false && /^\+?[\d\s\-()]{7,}$/.test(content))
            return "phone";

        // JSON
        if (detectors?.json !== false && (content.startsWith("{") || content.startsWith("["))) {
            try {
                const parsed = JSON.parse(content);
                if (typeof parsed === "object") return "json";
            } catch (e) {}
        }

        // File path
        if (detectors?.filePath !== false && /^(\/|~\/)[^\s]+/.test(content))
            return "filepath";

        // Markdown
        if (detectors?.markdown !== false && /^(#{1,6}\s|>\s|\*\*|__|- \[[ x]\]|- )/.test(content))
            return "markdown";

        // Number
        if (detectors?.number !== false && /^-?[\d,. ]+$/.test(content) && content.replace(/[\s,._]/g, "").length > 0)
            return "number";

        // Multiline
        if (detectors?.multiline !== false) {
            const lineCount = (content.match(/\n/g) || []).length;
            if (lineCount >= 2) return "multiline";
        }

        return "";
    }
    function fuzzyQuery(search: string): var {
        if (search.trim() === "") {
            return entries;
        }
        if (root.sloppySearch) {
            const results = entries.slice(0, 100).map(str => ({
                entry: str,
                score: Levendist.computeTextMatchScore(str.toLowerCase(), search.toLowerCase())
            })).filter(item => item.score > root.scoreThreshold)
                .sort((a, b) => b.score - a.score)
            return results
                .map(item => item.entry)
        }

        return Fuzzy.go(search, preparedEntries, {
            limit: 100,
            key: "name"
        }).map(r => {
            return r.obj.entry
        });
    }

    function entryIsImage(entry) {
        return !!(/^\d+\t\[\[.*binary data.*\d+x\d+.*\]\]$/.test(entry))
    }

    function refresh() {
        readProc.buffer = []
        readProc.running = true
    }

    function copy(entry) {
        if (!entry) return;

        let actualEntry = entry;
        const cleanPinned = StringUtils.cleanCliphistEntry(entry);
        const isImg = entryIsImage(entry);

        // Try to find a matching entry in current history to get a valid, fresh ID
        let found = false;
        if (root.entries.indexOf(entry) !== -1) {
            found = true;
        } else {
            for (let i = 0; i < root.entries.length; i++) {
                if (StringUtils.cleanCliphistEntry(root.entries[i]) === cleanPinned) {
                    actualEntry = root.entries[i];
                    found = true;
                    break;
                }
            }
        }

        if (found) {
            if (root.cliphistBinary.includes("cliphist")) {
                Quickshell.execDetached(["bash", "-c", `printf '${StringUtils.shellSingleQuoteEscape(actualEntry)}' | ${root.cliphistBinary} decode | wl-copy`]);
            } else {
                const entryNumber = actualEntry.split("\t")[0];
                Quickshell.execDetached(["bash", "-c", `${root.cliphistBinary} decode ${entryNumber} | wl-copy`]);
            }
        } else {
            // Fallback for purged pinned items
            if (!isImg) {
                Quickshell.execDetached(["bash", "-c", `printf '%s' '${StringUtils.shellSingleQuoteEscape(cleanPinned)}' | wl-copy`]);
            } else {
                console.warn("[Cliphist] Cannot copy purged pinned image");
            }
        }
    }

    function paste(entry) {
        if (!entry) return;

        let actualEntry = entry;
        const cleanPinned = StringUtils.cleanCliphistEntry(entry);
        const isImg = entryIsImage(entry);

        let found = false;
        if (root.entries.indexOf(entry) !== -1) {
            found = true;
        } else {
            for (let i = 0; i < root.entries.length; i++) {
                if (StringUtils.cleanCliphistEntry(root.entries[i]) === cleanPinned) {
                    actualEntry = root.entries[i];
                    found = true;
                    break;
                }
            }
        }

        let copyCmd = "";
        if (found) {
            if (root.cliphistBinary.includes("cliphist")) {
                copyCmd = `printf '${StringUtils.shellSingleQuoteEscape(actualEntry)}' | ${root.cliphistBinary} decode | wl-copy`;
            } else {
                const entryNumber = actualEntry.split("\t")[0];
                copyCmd = `${root.cliphistBinary} decode ${entryNumber} | wl-copy`;
            }
        } else {
            if (!isImg) {
                copyCmd = `printf '%s' '${StringUtils.shellSingleQuoteEscape(cleanPinned)}' | wl-copy`;
            } else {
                console.warn("[Cliphist] Cannot paste purged pinned image");
                return;
            }
        }

        // Simula o colar na janela ativa com atraso para garantir que a janela recuperou o foco
        const pasteCmd = `${copyCmd} && sleep 0.35 && wtype -M ctrl -k v -m ctrl`;
        Quickshell.execDetached(["bash", "-c", pasteCmd]);
    }

    function superpaste(count, isImage = false) {
        // Find entries
        const targetEntries = entries.filter(entry => {
            if (!isImage) return true;
            return entryIsImage(entry);
        }).slice(0, count)
        const pasteCommands = [...targetEntries].reverse().map(entry => `printf '${StringUtils.shellSingleQuoteEscape(entry)}' | ${root.cliphistBinary} decode | wl-copy && sleep ${root.pasteDelay} && ${root.pressPasteCommand}`)
        // Act
        Quickshell.execDetached(["bash", "-c", pasteCommands.join(` && sleep ${root.pasteDelay} && `)]);
    }

    Process {
        id: deleteProc
        property string entry: ""
        command: ["bash", "-c", `echo '${StringUtils.shellSingleQuoteEscape(deleteProc.entry)}' | ${root.cliphistBinary} delete`]
        function deleteEntry(entry) {
            deleteProc.entry = entry;
            deleteProc.running = true;
            deleteProc.entry = "";
        }
        onExited: (exitCode, exitStatus) => {
            root.refresh();
        }
    }

    function deleteEntry(entry) {
        if (!entry) return;

        if (isPinned(entry)) {
            unpin(entry);
        }

        let actualEntry = entry;
        const cleanPinned = StringUtils.cleanCliphistEntry(entry);

        // Find matching entry in root.entries to get the real ID to delete
        let found = false;
        if (root.entries.indexOf(entry) !== -1) {
            found = true;
        } else {
            for (let i = 0; i < root.entries.length; i++) {
                if (StringUtils.cleanCliphistEntry(root.entries[i]) === cleanPinned) {
                    actualEntry = root.entries[i];
                    found = true;
                    break;
                }
            }
        }

        deleteProc.deleteEntry(actualEntry);
    }

    Process {
        id: wipeProc
        command: [root.cliphistBinary, "wipe"]
        onExited: (exitCode, exitStatus) => {
            root.refresh();
        }
    }

    function wipe() {
        wipeProc.running = true;
    }

    readonly property var pinnedEntries: Persistent.states.clipboard.pinnedEntries

    function pin(entry) {
        if (!isPinned(entry)) {
            let current = Array.from(root.pinnedEntries);
            current.push(entry);
            Persistent.states.clipboard.pinnedEntries = current;
        }
    }

    function unpin(entry) {
        let current = Array.from(root.pinnedEntries);
        let index = current.indexOf(entry);
        if (index !== -1) {
            current.splice(index, 1);
            Persistent.states.clipboard.pinnedEntries = current;
        }
    }

    function isPinned(entry) {
        for (let i = 0; i < root.pinnedEntries.length; i++) {
            if (root.pinnedEntries[i] === entry) return true;
        }
        return false;
    }

    Connections {
        target: Quickshell
        function onClipboardTextChanged() {
            delayedUpdateTimer.restart()
        }
    }

    Timer {
        id: delayedUpdateTimer
        interval: Config.options.hacks.arbitraryRaceConditionDelay
        repeat: false
        onTriggered: {
            root.refresh()
        }
    }

    Process {
        id: readProc
        property list<string> buffer: []

        command: [root.cliphistBinary, "list"]

        stdout: SplitParser {
            onRead: (line) => {
                readProc.buffer.push(line)
            }
        }

        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                root.entries = readProc.buffer
            } else {
                console.error("[Cliphist] Failed to refresh with code", exitCode, "and status", exitStatus)
            }
        }
    }

    IpcHandler {
        target: "cliphistService"

        function update(): void {
            root.refresh()
        }
    }
}
