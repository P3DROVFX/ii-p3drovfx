pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Emojis.
 */
Singleton {
    id: root
    property string emojiScriptPath: `${Directories.config}/hypr/hyprland/scripts/fuzzel-emoji.sh`
	property string lineBeforeData: "### DATA ###"
    property bool levenshteinSearch: (Config.options?.search.levenshtein ?? false) || (Config.options?.search.algorithm === "levenshtein")
    property var list: []
    // Keep the legacy string list for existing fuzzy consumers, and expose
    // structured entries for the Search panel's category grid.
    property var entries: []
    property var entriesByCategory: ({
        all: [], people: [], nature: [], food: [], objects: [], symbols: []
    })
    property var entryByRaw: ({})
    property var preparedEntries: []
    property var preparedEntriesByCategory: ({
        all: [], people: [], nature: [], food: [], objects: [], symbols: []
    })
    property bool loaded: false
    property bool loading: false
    property bool entriesPrepared: false
    property bool entriesPreparing: false
    property int preparationIndex: 0
    property var preparationBuffer: []
    property var preparationCategoryBuffer: ({})
    property int structureIndex: 0
    property var structureBuffer: []
    property var structureCategoryBuffer: ({})
    property var structureEntryMapBuffer: ({})

    onListChanged: {
        preparationTimer.stop();
        root.entriesPrepared = false;
        // Building the fuzzy index is much more expensive than displaying a
        // virtualized grid. Keep opening the panel cheap and start indexing
        // only after the user actually types a query.
        root.entriesPreparing = false;
        root.preparationIndex = 0;
        root.preparationBuffer = [];
        root.preparedEntries = [];
        root.preparedEntriesByCategory = ({
            all: [], people: [], nature: [], food: [], objects: [], symbols: []
        });
    }

    function ensurePrepared(): void {
        if (root.entriesPrepared || root.entriesPreparing || root.entries.length === 0)
            return;
        root.entriesPreparing = true;
        root.preparationIndex = 0;
        root.preparationBuffer = [];
        root.preparationCategoryBuffer = ({
            people: [], nature: [], food: [], objects: [], symbols: []
        });
        preparationTimer.restart();
    }

    function entriesForCategory(category: string, recentEntries: var): var {
        const wanted = String(category ?? "all");
        if (wanted === "recent") {
            const result = [];
            for (const raw of Array.from(recentEntries ?? [])) {
                const entry = root.entryByRaw[String(raw)];
                if (entry)
                    result.push(entry);
            }
            return result;
        }
        return root.entriesByCategory[wanted] ?? root.entriesByCategory.all ?? [];
    }

    /**
     * Return the panel-ready entries without cloning and joining both service
     * lists on every binding reevaluation. The first query uses a bounded
     * substring pass while the fuzzy index is prepared incrementally.
     */
    function queryEntries(search: string, category: string, limit: int, recentEntries: var): var {
        const maximum = Math.max(1, Number(limit) || 100);
        const normalized = String(search ?? "").trim().toLocaleLowerCase();
        const source = root.entriesForCategory(category, recentEntries);
        if (normalized.length === 0)
            return source.slice(0, maximum);

        root.ensurePrepared();
        if (root.levenshteinSearch) {
            const threshold = Config.options?.search.scoreThreshold ?? 0.2;
            return source.slice(0, Math.max(maximum, 240)).map(entry => ({
                entry: entry,
                score: Levendist.computeTextMatchScore(entry.raw.toLocaleLowerCase(), normalized)
            })).filter(item => item.score > threshold)
                .sort((left, right) => right.score - left.score)
                .slice(0, maximum)
                .map(item => item.entry);
        }

        if (!root.entriesPrepared) {
            const result = [];
            for (const entry of source) {
                if (entry.raw.toLocaleLowerCase().includes(normalized))
                    result.push(entry);
                if (result.length >= maximum)
                    break;
            }
            return result;
        }

        const wanted = String(category ?? "all");
        const prepared = wanted === "recent"
            ? source.map(entry => ({ name: Fuzzy.prepare(entry.raw), entry: entry }))
            : (root.preparedEntriesByCategory[wanted] ?? root.preparedEntries);
        return Fuzzy.go(search, prepared, {
            limit: maximum,
            key: "name"
        }).map(result => result.obj.entry);
    }

    function fuzzyQuery(search: string): var {
        if (!search || search.trim() === "") {
            return root.list;
        }
        return root.queryEntries(search, "all", 100, []).map(entry => entry.raw);
    }

    function load() {
        if (root.loaded || root.loading)
            return;
        root.loading = true;
        emojiFileView.reload()
    }

    function categoryFor(entry: string): string {
        const text = String(entry ?? "").toLowerCase();
        if (/(face|heart|emotion|kiss|cat|monkey|skull|ghost|alien|robot)/.test(text)) return "people";
        if (/(hand|person|woman|man|baby|body|gesture|thumb|fist|leg|ear|eye|mouth)/.test(text)) return "people";
        if (/(animal|plant|flower|tree|nature|weather|moon|sun|earth|water|fire)/.test(text)) return "nature";
        if (/(food|drink|fruit|vegetable|meat|bread|cake|coffee|beer|wine)/.test(text)) return "food";
        if (/(symbol|arrow|number|letter|sign|flag|keycap|button|warning|check)/.test(text)) return "symbols";
        return "objects";
    }

    function entryFor(raw: string): var {
        return root.entryByRaw[String(raw)] ?? null;
    }

    function updateEmojis(fileContent) {
        const lines = fileContent.split("\n")
        const dataIndex = lines.indexOf(root.lineBeforeData)
        if (dataIndex === -1) {
            console.warn("No data section found in emoji script file.")
            return
        }
        const emojis = lines.slice(dataIndex + 1).filter(line => line.trim() !== "")
        root.list = emojis.map(line => line.trim())
        root.entries = [];
        root.entriesByCategory = ({
            all: [], people: [], nature: [], food: [], objects: [], symbols: []
        });
        root.entryByRaw = ({});
        root.structureIndex = 0;
        root.structureBuffer = [];
        root.structureCategoryBuffer = ({
            people: [], nature: [], food: [], objects: [], symbols: []
        });
        root.structureEntryMapBuffer = ({});
        structureTimer.restart();
    }

    FileView { 
        id: emojiFileView
        path: Qt.resolvedUrl(root.emojiScriptPath)
        onLoaded: {
            const fileContent = emojiFileView.text()
            root.updateEmojis(fileContent)
        }
    }

    Timer {
        id: structureTimer
        interval: 8
        repeat: false
        onTriggered: {
            const batchSize = 64;
            const end = Math.min(root.list.length, root.structureIndex + batchSize);
            for (let index = root.structureIndex; index < end; index++) {
                const raw = root.list[index];
                const entry = {
                    raw: raw,
                    emoji: raw.match(/^\s*(\S+)/)?.[1] ?? "",
                    name: raw.replace(/^\s*\S+\s+/, ""),
                    category: root.categoryFor(raw)
                };
                root.structureBuffer.push(entry);
                root.structureCategoryBuffer[entry.category].push(entry);
                root.structureEntryMapBuffer[raw] = entry;
            }
            root.structureIndex = end;
            if (root.structureIndex < root.list.length) {
                structureTimer.restart();
                return;
            }
            root.entries = root.structureBuffer;
            root.entriesByCategory = ({
                all: root.structureBuffer,
                people: root.structureCategoryBuffer.people,
                nature: root.structureCategoryBuffer.nature,
                food: root.structureCategoryBuffer.food,
                objects: root.structureCategoryBuffer.objects,
                symbols: root.structureCategoryBuffer.symbols
            });
            root.entryByRaw = root.structureEntryMapBuffer;
            root.structureBuffer = [];
            root.structureCategoryBuffer = ({});
            root.structureEntryMapBuffer = ({});
            root.loaded = true;
            root.loading = false;
            console.log(`[Emojis] Loaded ${root.entries.length} emojis incrementally`);
        }
    }

    Timer {
        id: preparationTimer
        interval: 16
        repeat: false
        onTriggered: {
            if (!root.entriesPreparing)
                return;

            const batchSize = 48;
            const end = Math.min(root.entries.length, root.preparationIndex + batchSize);
            for (let index = root.preparationIndex; index < end; index++) {
                const entry = root.entries[index];
                const prepared = {
                    name: Fuzzy.prepare(entry.raw),
                    entry: entry
                };
                root.preparationBuffer.push(prepared);
                root.preparationCategoryBuffer[entry.category].push(prepared);
            }
            root.preparationIndex = end;

            if (root.preparationIndex >= root.entries.length) {
                root.preparedEntries = root.preparationBuffer;
                root.preparedEntriesByCategory = ({
                    all: root.preparationBuffer,
                    people: root.preparationCategoryBuffer.people,
                    nature: root.preparationCategoryBuffer.nature,
                    food: root.preparationCategoryBuffer.food,
                    objects: root.preparationCategoryBuffer.objects,
                    symbols: root.preparationCategoryBuffer.symbols
                });
                root.preparationBuffer = [];
                root.preparationCategoryBuffer = ({});
                root.entriesPreparing = false;
                root.entriesPrepared = true;
                console.log(`[Emojis] Prepared ${root.preparedEntries.length} entries incrementally`);
                return;
            }
            preparationTimer.restart();
        }
    }
}
