pragma Singleton

import qs.modules.common
import qs.modules.common.functions
import Quickshell

/**
 * - Eases fuzzy searching for applications by name
 * - Guesses icon name for window class name
 * - Supports frecency ranking and alias resolution
 */
Singleton {
    id: root
    property bool sloppySearch: Config.options?.search.sloppy ?? false
    property bool frecencySearch: Config.options?.search.frecency ?? false
    property real scoreThreshold: 0.2
    property var substitutions: ({
        "code-url-handler": "visual-studio-code",
        "Code": "visual-studio-code",
        "gnome-tweaks": "org.gnome.tweaks",
        "pavucontrol-qt": "pavucontrol",
        "wps": "wps-office2019-kprometheus",
        "wpsoffice": "wps-office2019-kprometheus",
        "footclient": "foot",
        "jetbrains-studio": "android-studio",
        "zen": "zen-browser",
    })
    property var regexSubstitutions: [
        {
            "regex": /^steam_app_(\d+)$/,
            "replace": "steam_icon_$1"
        },
        {
            "regex": /Minecraft.*/,
            "replace": "minecraft"
        },
        {
            "regex": /.*polkit.*/,
            "replace": "system-lock-screen"
        },
        {
            "regex": /gcr.prompter/,
            "replace": "system-lock-screen"
        }
    ]

    // Deduped list to fix double icons
    readonly property list<DesktopEntry> list: Array.from(DesktopEntries.applications.values)
        .filter((app, index, self) => 
            index === self.findIndex((t) => (
                t.id === app.id
            ))
    )
    
    readonly property var preppedNames: list.map(a => ({
        name: Fuzzy.prepare(`${a.name} `),
        entry: a
    }))

    readonly property var preppedIcons: list.map(a => ({
        name: Fuzzy.prepare(`${a.icon} `),
        entry: a
    }))



    /**
     * Frecency search: combines fuzzy matching with app launch frequency
     */
    function frecencyQuery(search: string): var {
        if (search === "") {
            // When empty, show all apps sorted by frecency then alphabetical
            const scored = list.map(obj => ({
                entry: obj,
                score: AppUsage.getScore(obj.id)
            }));
            // Split: apps with score > 0 sorted by score desc, then rest alphabetically
            const used = scored.filter(item => item.score > 0)
                .sort((a, b) => b.score - a.score);
            const unused = scored.filter(item => item.score === 0)
                .sort((a, b) => a.entry.name.localeCompare(b.entry.name));
            return used.concat(unused).map(item => item.entry);
        }

        // Use Fuzzy.go to get matches with scores
        const fuzzyResults = Fuzzy.go(search, preppedNames, {
            all: false,
            key: "name"
        });

        if (fuzzyResults.length === 0) return [];

        // Find max score for normalization
        let maxFuzzy = 0;
        for (let i = 0; i < fuzzyResults.length; i++) {
            if (fuzzyResults[i].score > maxFuzzy) maxFuzzy = fuzzyResults[i].score;
        }

        const results = fuzzyResults.map(r => {
            const entry = r.obj.entry;
            const fuzzyScore = r.score;
            const normalizedFuzzy = maxFuzzy > 0 ? fuzzyScore / maxFuzzy : 1;
            const usageScore = AppUsage.getScore(entry.id);
            // Normalize usage score (log scale to prevent single high-freq app dominating)
            const normalizedUsage = usageScore > 0 ? Math.min(1, Math.log(usageScore + 1) / Math.log(100)) : 0;
            
            // Boost score if the app name starts with the search string
            const startsWithQuery = entry.name.toLowerCase().startsWith(search.toLowerCase());
            const prefixBonus = startsWithQuery ? 1.0 : 0.0;
            
            return {
                entry: entry,
                combinedScore: normalizedFuzzy * 0.6 + normalizedUsage * 0.4 + prefixBonus,
                isAlias: false
            };
        });

        return results
            .sort((a, b) => b.combinedScore - a.combinedScore)
            .map(item => item.entry);
    }

    function fuzzyQuery(search) { // Idk why list<DesktopEntry> doesn't work
        if (search === "") {
            if (root.frecencySearch) {
                return frecencyQuery(search);
            }
            return Array.from(list).sort((a, b) => a.name.localeCompare(b.name));
        }

        // Frecency mode: combine fuzzy with usage frequency
        if (root.frecencySearch) {
            return frecencyQuery(search);
        }

        // Sloppy mode: levenshtein distance
        if (root.sloppySearch) {
            const results = list.map(obj => ({
                entry: obj,
                score: Levendist.computeScore(obj.name.toLowerCase(), search.toLowerCase())
            })).filter(item => item.score > root.scoreThreshold)
                .sort((a, b) => b.score - a.score)
            return results
                .map(item => item.entry)
        }

        // Default: fuzzy sort
        return Fuzzy.go(search, preppedNames, {
            all: true,
            key: "name"
        }).map(r => {
            return r.obj.entry
        });
    }

    function iconExists(iconName) {
        if (!iconName || iconName.length == 0) return false;
        return (Quickshell.iconPath(iconName, true).length > 0) 
            && !iconName.includes("image-missing");
    }

    function getReverseDomainNameAppName(str) {
        return str.split('.').slice(-1)[0]
    }

    function getKebabNormalizedAppName(str) {
        return str.toLowerCase().replace(/\s+/g, "-");
    }

    function getUndescoreToKebabAppName(str) {
        return str.toLowerCase().replace(/_/g, "-");
    }

    function guessIcon(str) {
        if (!str || str.length == 0) return "image-missing";

        // Try common substitutions first
        if (substitutions[str]) return substitutions[str];
        if (substitutions[str.toLowerCase()]) return substitutions[str.toLowerCase()];
        
        // Handle common variations for user's requested apps
        if (str.includes("android-studio")) return "android-studio";
        if (str.includes("zen-browser") || str.includes("zen")) return "zen";

        // Try to see if there's a themed icon matching the name (for absolute path icons)
        // This is important for apps like Zen Browser where the .desktop has an absolute path
        // but the theme script generates a themed icon with the desktop entry's ID
        let nameWithoutExt = str;
        if (str.endsWith(".desktop")) nameWithoutExt = str.slice(0, -8);
        if (iconExists(nameWithoutExt)) return nameWithoutExt;

        // Quickshell's desktop entry lookup
        const entry = DesktopEntries.byId(str);
        if (entry) {
            // Even if we have an entry, check if its ID (basename) has a themed version
            // because the entry.icon might be an absolute path
            const entryId = entry.id.endsWith(".desktop") ? entry.id.slice(0, -8) : entry.id;
            if (iconExists(entryId)) return entryId;
            return entry.icon;
        }

        // Regex substitutions
        for (let i = 0; i < regexSubstitutions.length; i++) {
            const substitution = regexSubstitutions[i];
            const replacedName = str.replace(
                substitution.regex,
                substitution.replace,
            );
            if (replacedName != str) return replacedName;
        }

        // Icon exists -> return as is
        if (iconExists(str)) return str;


        // Simple guesses
        const lowercased = str.toLowerCase();
        if (iconExists(lowercased)) return lowercased;

        const reverseDomainNameAppName = getReverseDomainNameAppName(str);
        if (iconExists(reverseDomainNameAppName)) return reverseDomainNameAppName;

        const lowercasedDomainNameAppName = reverseDomainNameAppName.toLowerCase();
        if (iconExists(lowercasedDomainNameAppName)) return lowercasedDomainNameAppName;

        const kebabNormalizedGuess = getKebabNormalizedAppName(str);
        if (iconExists(kebabNormalizedGuess)) return kebabNormalizedGuess;

        const undescoreToKebabGuess = getUndescoreToKebabAppName(str);
        if (iconExists(undescoreToKebabGuess)) return undescoreToKebabGuess;

        // Search in desktop entries
        const iconSearchResults = Fuzzy.go(str, preppedIcons, {
            all: true,
            key: "name"
        }).map(r => {
            return r.obj.entry
        });
        if (iconSearchResults.length > 0) {
            const guess = iconSearchResults[0].icon
            if (iconExists(guess)) return guess;
        }

        const nameSearchResults = root.fuzzyQuery(str);
        if (nameSearchResults.length > 0) {
            const guess = nameSearchResults[0].icon
            if (iconExists(guess)) return guess;
        }

        // Quickshell's desktop entry lookup
        const heuristicEntry = DesktopEntries.heuristicLookup(str);
        if (heuristicEntry) return heuristicEntry.icon;

        // Give up
        return "application-x-executable";
    }
}