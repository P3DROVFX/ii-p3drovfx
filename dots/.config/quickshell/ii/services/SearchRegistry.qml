pragma Singleton

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    property list<var> sections: []

    property string currentSearch: ""
    onCurrentSearchChanged: {
        console.log("Current found search result string:", currentSearch);
    }

    function startIndexing() {
        sections = [];
        let basePath = FileUtils.trimFileProtocol(Directories.config) + "/quickshell/ii/modules/settings/configs/";
        
        let widgetFiles = [
            "ActiveWindowConfig.qml", "MediaPlayerConfig.qml", "UtilButtonsConfig.qml",
            "KeyboardLayoutConfig.qml", "SystemMonitorConfig.qml", "IndicatorsConfig.qml",
            "SportsConfig.qml", "BluetoothConfig.qml", "SystemTrayConfig.qml",
            "DesktopClockWidgetConfig.qml", "DesktopWeatherWidgetConfig.qml",
            "DesktopMediaWidgetConfig.qml", "BatteryConfig.qml", "CoreAudioConfig.qml",
            "CorePowerConfig.qml", "CoreTimeDateConfig.qml", "CoreLanguageConfig.qml",
            "CoreAlertsConfig.qml", "CoreMediaConfig.qml", "CorePoliciesConfig.qml",
            "CoreNetworkConfig.qml", "CoreFilesConfig.qml", "CoreWeatherConfig.qml",
            "CoreTerminalConfig.qml", "CoreWaffleConfig.qml", "GameOverlayConfig.qml",
            "BTDeviceImagesConfig.qml", "DashboardButtonConfig.qml", "MediaDownloaderConfig.qml"
        ];
        
        
        let files = [basePath + "ColorsThemesConfig.qml", basePath + "BarConfig.qml", basePath + "BackgroundConfig.qml", basePath + "InterfaceFontsConfig.qml", basePath + "PresetsConfig.qml", basePath + "SidebarsConfig.qml", basePath + "DockConfig.qml", basePath + "WorkspacesConfig.qml", basePath + "OverviewConfig.qml", basePath + "WidgetsConfig.qml", basePath + "DynamicIslandConfig.qml", basePath + "OverlaysConfig.qml", basePath + "RegionSelectorConfig.qml", basePath + "AppSearchConfig.qml", basePath + "CheatSheetConfig.qml", basePath + "HyprlandRulesConfig.qml", basePath + "MonitorsConfig.qml", basePath + "CoreServicesConfig.qml", basePath + "SoundsConfig.qml", basePath + "LockScreenConfig.qml", basePath + "AboutConfig.qml", basePath + "UserProfileConfig.qml"];
        
        for (let w of widgetFiles) files.push(basePath + "widgets/" + w);
        
        pageFile.start(files);
        listPresetsSearchProc.running = false;
        listPresetsSearchProc.running = true;
    }

    Component.onCompleted: startIndexing()

    Connections {
        target: Translation
        function onLanguageCodeChanged() {
            startIndexing();
        }
    }

    FileView {
        id: pageFile
        blockLoading: true

        property var files: []
        property int currentIndex: 0

        function start(filesArray) {
            files = filesArray;
            currentIndex = 0;
            loadNext();
        }

        function loadNext() {
            if (currentIndex >= files.length)
                return;
            path = files[currentIndex];
        }

        onLoaded: {
            root.indexQmlFile(text(), currentIndex);
            currentIndex++;
            Qt.callLater(() => loadNext());
        }
    }

    Process {
        id: listPresetsSearchProc
        command: ["bash", "-c", Directories.scriptPath + "/presets.sh list"]
        stdout: SplitParser {
            onRead: data => {
                let str = data.trim();
                if (!str)
                    return;
                try {
                    let obj = JSON.parse(str);
                    if (obj && obj.name) {
                        root.addDynamicPresetName(obj.name);
                    }
                } catch (e) {
                    // Ignore parse errors
                }
            }
        }
    }

    function addDynamicPresetName(name) {
        for (let i = 0; i < sections.length; i++) {
            let section = sections[i];
            if (section.pageIndex === 4) {
                if (section.searchStrings.indexOf(name) === -1) {
                    section.searchStrings.push(name);
                    let combined = (section.title + " " + section.searchStrings.join(" ")).toLowerCase();
                    section._tokens = tokenize(combined);
                    section._searchText = combined;
                }
            }
        }
    }

    function extractImports(text) {
        let imports = "";
        let lines = text.split("\n");
        for (let line of lines) {
            line = line.trim();
            if (line.startsWith("import ")) {
                imports += line + "\n";
            }
        }
        return imports;
    }

    function extractWidgets(text) {
        let items = [];
        let types = ["ConfigSwitch", "ConfigSpinBox", "ConfigSelectionArray", "ConfigTextField", "ConfigSlider", "ConfigComboBox", "ConfigWallpaperSelector", "ConfigLightDarkToggle", "ConfigPresetsView"];
        for (let t of types) {
            let blocks = extractBlocks(text, t);
            for (let b of blocks) {
                let textProp = extractProperty(b.inner, "text") || extractProperty(b.inner, "title") || extractProperty(b.inner, "tooltip");
                items.push({
                    type: t,
                    text: textProp,
                    full: b.full
                });
            }
        }
        return items;
    }

    function indexQmlFile(qmlText, pageIndex) {
        if (!qmlText) return;
        
        let fileImports = extractImports(qmlText);
        let sectionsExtracted = extractBlocks(qmlText, "ContentSection");

        for (let sectionBlock of sectionsExtracted) {
            let sectionText = sectionBlock.inner;
            let title = extractProperty(sectionText, "title");
            let icon = extractProperty(sectionText, "icon");

            let searchStrings = [];
            let sectionItems = [];
            let sectionSubsections = [];

            // 1. extract subsections
            let subsections = extractBlocks(sectionText, "ContentSubsection");
            for (let subBlock of subsections) {
                let subTitle = extractProperty(subBlock.inner, "title");
                let subIcon = extractProperty(subBlock.inner, "icon");
                
                let subItems = extractWidgets(subBlock.inner);

                sectionSubsections.push({
                    title: subTitle,
                    icon: subIcon,
                    items: subItems,
                    full: subBlock.full
                });

                // remove the subsection from sectionText to avoid double counting
                sectionText = sectionText.replace(subBlock.full, "");
            }

            // 2. extract remaining widgets from sectionText
            sectionItems = sectionItems.concat(extractWidgets(sectionText));

            // collect all search strings for scoring (excluding individual item texts to prevent them from matching the whole section)
            if (title) searchStrings.push(title);
            for (let sub of sectionSubsections) {
                if (sub.title) searchStrings.push(sub.title);
            }

            registerSection({
                pageIndex: pageIndex,
                title: title || "Unknown",
                icon: icon || "",
                searchStrings: searchStrings,
                items: sectionItems,
                subsections: sectionSubsections,
                fileImports: fileImports
            });
        }
    }

    function extractBlocks(text, type) {
        let results = [];
        let i = 0;

        while (i < text.length) {
            let index = text.indexOf(type, i);
            if (index === -1) break;
            
            // Check if it's a whole word match (to avoid partial matches if any)
            let prevChar = index > 0 ? text[index - 1] : ' ';
            if (/[a-zA-Z0-9_]/.test(prevChar)) {
                i = index + type.length;
                continue;
            }

            let braceStart = text.indexOf("{", index);
            if (braceStart === -1) break;
            
            // Validate that between type and brace there are only spaces or nothing
            let between = text.substring(index + type.length, braceStart).trim();
            if (between !== "") {
                i = index + type.length;
                continue;
            }

            let depth = 1;
            let j = braceStart + 1;
            let inString = false;
            let stringChar = "";

            while (j < text.length && depth > 0) {
                let ch = text[j];

                if (!inString && (ch === '"' || ch === "'")) {
                    inString = true;
                    stringChar = ch;
                } else if (inString && ch === stringChar) {
                    // Check for escape character
                    if (text[j-1] !== '\\') {
                        inString = false;
                    }
                } else if (!inString) {
                    if (ch === "{") depth++;
                    else if (ch === "}") depth--;
                }

                j++;
            }

            let block = text.substring(braceStart + 1, j - 1);
            let fullMatch = text.substring(index, j);
            results.push({ inner: block, full: fullMatch });

            i = j;
        }

        return results;
    }

    function extractProperty(block, prop) {
        let m;
        m = block.match(new RegExp(prop + "\\s*:\\s*Translation\\.tr\\(\\s*[\"']([^\"']+)[\"']\\s*\\)"));
        if (m) return m[1];
        m = block.match(new RegExp(prop + "\\s*:\\s*\"([^\"]+)\""));
        if (m) return m[1];
        m = block.match(new RegExp(prop + "\\s*:\\s*'([^']+)'"));
        if (m) return m[1];
        return "";
    }

    function tokenize(text) {
        if (!text || typeof text !== "string") return [];
        return text.toLowerCase().replace(/[^a-z0-9\sğüşöçıİ_\-\.]/g, " ").split(/[\s_\-\.]+/).filter(function (t) {
            return t.length > 1;
        });
    }

    function fuzzyMatch(word, query) {
        let wi = 0; let qi = 0; let score = 0;
        word = word.toLowerCase(); query = query.toLowerCase();
        while (wi < word.length && qi < query.length) {
            if (word[wi] === query[qi]) { score += 10; qi++; }
            wi++;
        }
        if (qi === query.length) return score;
        return 0;
    }

    function registerSection(data) {
        const titleKey = data.title;
        const searchStringsKeys = [...data.searchStrings];

        data.title = Translation.tr(titleKey);
        data.searchStrings = searchStringsKeys.map(s => Translation.tr(s));

        let combined = (titleKey + " " + searchStringsKeys.join(" ") + " " + data.title + " " + data.searchStrings.join(" ")).toLowerCase();
        data._tokens = tokenize(combined);
        data._searchText = combined;

        sections.push(data);
    }

    function getMatchScore(text, query, queryTokens) {
        if (!text) return 0;
        let score = 0;
        let lower = text.toLowerCase();
        
        let tokens = tokenize(lower);
        
        for (let qToken of queryTokens) {
            for (let sToken of tokens) {
                if (sToken === qToken) {
                    score += 500;
                } else if (sToken.startsWith(qToken)) {
                    score += 200;
                }
            }
        }
        return score;
    }

    function getDynamicSearchResults(query) {
        if (!query || query.trim() === "") return [];
        query = query.toLowerCase().trim();
        let queryTokens = tokenize(query);
        let results = [];

        for (let section of sections) {
            let sectionMatches = false;
            let sectionScore = 0;

            let matchedItems = [];
            let matchedSubsections = [];

            let sectionTitleScore = getMatchScore(section.title, query, queryTokens);
            let searchStringScore = 0;
            for (let sStr of section.searchStrings) {
                let sScore = getMatchScore(sStr, query, queryTokens);
                if (sScore > 0) {
                    searchStringScore = Math.max(searchStringScore, sScore);
                }
            }

            let sectionTitleMatched = (sectionTitleScore > 0 || searchStringScore > 0);
            if (sectionTitleMatched) {
                sectionMatches = true;
                sectionScore += Math.max(sectionTitleScore, searchStringScore);
            }

            for (let item of section.items) {
                let itemScore = getMatchScore(item.text, query, queryTokens);
                if (itemScore > 0 || sectionTitleMatched) {
                    matchedItems.push(item);
                    if (itemScore > 0) {
                        sectionScore += itemScore;
                    }
                    sectionMatches = true;
                }
            }

            for (let sub of section.subsections) {
                let subTitleScore = getMatchScore(sub.title, query, queryTokens);
                let subMatchedItems = [];
                let subMatches = false;

                if (subTitleScore > 0) {
                    sectionScore += subTitleScore;
                }

                for (let item of sub.items) {
                    let itemScore = getMatchScore(item.text, query, queryTokens);
                    if (itemScore > 0 || subTitleScore > 0 || sectionTitleMatched) {
                        subMatchedItems.push(item);
                        if (itemScore > 0) {
                            sectionScore += itemScore;
                        }
                        subMatches = true;
                        sectionMatches = true;
                    }
                }

                if (subMatches) {
                    matchedSubsections.push({
                        title: sub.title,
                        icon: sub.icon,
                        items: subMatchedItems
                    });
                }
            }

            if (sectionMatches) {
                results.push({
                    title: section.title,
                    icon: section.icon,
                    fileImports: section.fileImports,
                    items: matchedItems,
                    subsections: matchedSubsections,
                    score: sectionScore
                });
            }
        }
        
        results.sort((a, b) => b.score - a.score);
        return results;
    }
    
    function getResultsRanked(text) {
        return getSearchResult(text);
    }
    
    // Fallback for old behaviour just in case
    function getSearchResult(query) {
        if (!query || query.trim() === "") return [];
        let dyn = getDynamicSearchResults(query);
        let flat = [];
        for (let r of dyn) {
            flat.push({ pageIndex: 0, matchedString: r.title, score: r.score }); // dummy for old compatibility if needed
        }
        return flat;
    }
}
