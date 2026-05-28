pragma Singleton

import qs.modules.common
import qs.modules.common.models
import qs.modules.common.functions
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Singleton {
    id: root

    property string query: ""
    property int _mprisTrigger: 0

    function ensurePrefix(prefix) {
        if ([Config.options.search.prefix.action, Config.options.search.prefix.app, Config.options.search.prefix.clipboard, Config.options.search.prefix.emojis, Config.options.search.prefix.math, Config.options.search.prefix.shellCommand, Config.options.search.prefix.webSearch, Config.options.search.prefix.windowSearch, Config.options.search.prefix.fileBrowser, Config.options.search.prefix.fileSearch].some(i => root.query.startsWith(i))) {
            root.query = prefix + root.query.slice(1);
        } else {
            root.query = prefix + root.query;
        }
    }

    function isMathQuery(expr) {
        expr = expr.trim();
        if (expr.length === 0) return false;
        
        // Starts with math prefix '='
        if (expr.startsWith(Config.options.search.prefix.math)) return true;
        
        // Starts with basic math functions
        if (/^(sqrt|sin|cos|tan|log|ln)\b/i.test(expr)) return true;
        
        // Verify if it contains a number
        const hasNumber = /\d/.test(expr);
        if (!hasNumber) return false;
        
        // Pure number is NOT a math query by default (e.g. searching for app ID/number)
        // unless it's explicitly prefixed or contains operators/units
        if (/^[-+]?\d+(\.\d+)?$/.test(expr)) return false;
        
        // If it starts with a number, check for common math structures:
        // 1. Math operators: +, *, /, ^, %, ( or )
        if (/[+\*\/^()%]/.test(expr)) return true;
        
        // 2. Spaces around a minus or plus sign: e.g. "12 - 3", "12 -3"
        // But avoid matching words with hyphens like "3d-printer" or "1-password"
        if (/\s+[-+]\s*/.test(expr) || /\d\s*[-+]\s*\d/.test(expr)) return true;
        
        // 3. Keywords like 'to' or 'in' for unit conversion: e.g. "12 usd to eur", "100 c to f"
        // Avoid matching words that happen to contain "to" as substring
        if (/\d+\s*(?:[a-zA-Z%]+)?\s+\bto\b\s+\b[a-zA-Z%]+\b/i.test(expr)) return true;
        if (/\d+\s*\bto\b/i.test(expr)) return true;
        
        return false;
    }

    // https://specifications.freedesktop.org/menu/latest/category-registry.html
    property list<string> mainRegisteredCategories: ["AudioVideo", "Development", "Education", "Game", "Graphics", "Network", "Office", "Science", "Settings", "System", "Utility"]
    property list<string> appCategories: DesktopEntries.applications.values.reduce((acc, entry) => {
        for (const category of entry.categories) {
            if (!acc.includes(category) && mainRegisteredCategories.includes(category)) {
                acc.push(category);
            }
        }
        return acc;
    }, []).sort()

    // Load user action scripts from ~/.config/illogical-impulse/actions/
    // Uses FolderListModel to auto-reload when scripts are added/removed
    property var userActionScripts: {
        const actions = [];
        for (let i = 0; i < userActionsFolder.count; i++) {
            const fileName = userActionsFolder.get(i, "fileName");
            const filePath = userActionsFolder.get(i, "filePath");
            if (fileName && filePath) {
                const actionName = fileName.replace(/\.[^/.]+$/, ""); // strip extension
                actions.push({
                    action: actionName,
                    execute: ((path) => (args) => {
                        Quickshell.execDetached([path, ...(args ? args.split(" ") : [])]);
                    })(FileUtils.trimFileProtocol(filePath.toString()))
                });
            }
        }
        return actions;
    }

    FolderListModel {
        id: userActionsFolder
        folder: Qt.resolvedUrl(Directories.userActions)
        showDirs: false
        showHidden: false
        sortField: FolderListModel.Name
    }

    property var searchActions: [
        {
            action: "accentcolor",
            execute: args => {
                Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--noswitch", "--color", ...(args != '' ? [`${args}`] : [])]);
            }
        },
        {
            action: "dark",
            execute: () => {
                Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--mode", "dark", "--noswitch"]);
            }
        },
        {
            action: "konachanwallpaper",
            execute: () => {
                Quickshell.execDetached([Quickshell.shellPath("scripts/colors/random/random_konachan_wall.sh")]);
            }
        },
        {
            action: "light",
            execute: () => {
                Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--mode", "light", "--noswitch"]);
            }
        },
        {
            action: "superpaste",
            execute: args => {
                if (!/^(\d+)/.test(args.trim())) {
                    // Invalid if doesn't start with numbers
                    Quickshell.execDetached(["notify-send", Translation.tr("Superpaste"), Translation.tr("Usage: <tt>%1superpaste NUM_OF_ENTRIES[i]</tt>\nSupply <tt>i</tt> when you want images\nExamples:\n<tt>%1superpaste 4i</tt> for the last 4 images\n<tt>%1superpaste 7</tt> for the last 7 entries").arg(Config.options.search.prefix.action), "-a", "Shell"]);
                    return;
                }
                const syntaxMatch = /^(?:(\d+)(i)?)/.exec(args.trim());
                const count = syntaxMatch[1] ? parseInt(syntaxMatch[1]) : 1;
                const isImage = !!syntaxMatch[2];
                Cliphist.superpaste(count, isImage);
            }
        },
        {
            action: "todo",
            execute: args => {
                Todo.addTask(args);
            }
        },
        {
            action: "wallpaper",
            execute: () => {
                Hyprland.dispatch(`hl.dsp.global("quickshell:wallpaperSelectorToggle")`)
            }
        },
        {
            action: "wipeclipboard",
            execute: () => {
                Cliphist.wipe();
            }
        },
        {
            action: "genius",
            execute: args => {
                if (!args || args.trim().length === 0) {
                    Quickshell.execDetached(["notify-send", "Genius API", 
                        Translation.tr("Usage: /genius YOUR_API_KEY"), "-a", "Shell"]);
                    return;
                }
                KeyringStorage.setNestedField(["apiKeys", "genius"], args.trim());
                Quickshell.execDetached(["notify-send", "Genius API", Translation.tr("API key saved!"), "-a", "Shell"]);
            }
        },
    ]

    // Combined built-in and user actions
    property var allActions: searchActions.concat(userActionScripts)

    property string mathResult: ""
    property string confirmKey: ""
    property bool clipboardWorkSafetyActive: {
        const enabled = Config.options.workSafety.enable.clipboard;
        const sensitiveNetwork = (StringUtils.stringListContainsSubstring(Network.networkName.toLowerCase(), Config.options.workSafety.triggerCondition.networkNameKeywords));
        return enabled && sensitiveNetwork;
    }

    function containsUnsafeLink(entry) {
        if (entry == undefined)
            return false;
        const unsafeKeywords = Config.options.workSafety.triggerCondition.linkKeywords;
        return StringUtils.stringListContainsSubstring(entry.toLowerCase(), unsafeKeywords);
    }

    Timer {
        id: nonAppResultsTimer
        interval: Config.options.search.nonAppResultDelay
        onTriggered: {
            let expr = root.query;
            if (!root.isMathQuery(expr)) return;

            if (expr.startsWith(Config.options.search.prefix.math)) {
                expr = expr.slice(Config.options.search.prefix.math.length);
            }
            mathProc.calculateExpression(expr);
        }
    }

    // File browser: debounce browse calls to avoid Process flicker
    property string _fileBrowserDir: ""
    Timer {
        id: fileBrowserDebounce
        interval: 120
        onTriggered: {
            if (root._fileBrowserDir.length > 0)
                fileBrowserProc.browse(root._fileBrowserDir);
        }
    }

    // File search: debounce calls to avoid Process/Disk spelling flicker
    property string _fileSearchExpr: ""
    Timer {
        id: fileSearchDebounce
        interval: 250 // slightly longer because fd search is expensive
        onTriggered: {
            if (root._fileSearchExpr.length >= 2)
                fileProc.searchFiles(root._fileSearchExpr);
        }
    }

    onQueryChanged: {
        if (root.query.startsWith(Config.options.search.prefix.fileSearch)) {
            const fileExpr = root.query.slice(Config.options.search.prefix.fileSearch.length);
            root._fileSearchExpr = fileExpr;
            fileSearchDebounce.restart();
        } else {
            fileSearchDebounce.stop();
            root._fileSearchExpr = "";
            root.fileResults = [];
        }

        if (root.query.startsWith(Config.options.search.prefix.fileBrowser)) {
            const rawPath = root.query.slice(Config.options.search.prefix.fileBrowser.length);
            const homePath = FileUtils.trimFileProtocol(Directories.home);
            const expandedPath = rawPath.startsWith("/") ? rawPath : (homePath + "/" + rawPath);
            const lastSlash = expandedPath.lastIndexOf("/");
            const dirPath = lastSlash >= 0 ? expandedPath.slice(0, lastSlash + 1) : expandedPath;
            root._fileBrowserDir = dirPath;
            fileBrowserDebounce.restart();
        } else {
            root._fileBrowserDir = "";
            root.fileBrowserResults = [];
        }

        if (!root.isMathQuery(root.query)) {
            root.mathResult = "";
        }
        root.confirmKey = "";
    }


    Process {
        id: mathProc
        property list<string> baseCommand: ["qalc", "-t"]
        function calculateExpression(expression) {
            mathProc.running = false;
            mathProc.command = baseCommand.concat(expression);
            mathProc.running = true;
        }
        stdout: SplitParser {
            onRead: data => {
                root.mathResult = data;
            }
        }
    }

    property var fileResults: []
    Process {
        id: fileProc 
        function searchFiles(expr) {
            if (expr.length < 2) return
            fileProc.running = false;
            fileProc.command = ["fd", expr, Config.options.search.fileSearchDirectory]; 
            fileProc.running = true;
        }
        stdout: StdioCollector {
            onStreamFinished: {
                const rawResult = this.text
                const result = rawResult.split('\n')
                result.pop() // deleting the last empty line
                root.fileResults = result
            }
        }

    }

    // ========== File Browser (directory navigation) ==========
    property var fileBrowserResults: []
    Process {
        id: fileBrowserProc
        function browse(path) {
            if (path.length < 1) return;
            fileBrowserProc.running = false;
            // List directory contents, dirs first, with trailing slash for dirs
            fileBrowserProc.command = ["bash", "-c", `ls -1 -p "${path}" 2>/dev/null | head -50`];
            fileBrowserProc.running = true;
        }
        stdout: StdioCollector {
            id: fileBrowserCollector
            onStreamFinished: {
                const rawResult = fileBrowserCollector.text;
                const result = rawResult.split('\n').filter(l => l.length > 0);
                root.fileBrowserResults = result;
            }
        }
    }

    // ========== Window Search ==========
    function getWindowResults(searchString) {
        const windows = HyprlandData.windowList || [];
        if (searchString === "") return windows;
        const lower = searchString.toLowerCase();
        return windows.filter(w => {
            const title = (w.title || "").toLowerCase();
            const cls = (w.class || "").toLowerCase();
            return title.includes(lower) || cls.includes(lower);
        });
    }

    // ========== Shell Snippets ==========
    function getShellSnippetActions() {
        const snippets = Config.options?.search?.shellSnippets ?? [];
        return snippets.map(snippet => ({
            action: snippet.alias || snippet.name || "snippet",
            name: snippet.name || snippet.alias || "Shell Snippet",
            command: snippet.command || "",
            execute: (args) => {
                let cmd = snippet.command || "";
                if (args) cmd += " " + args;
                Quickshell.execDetached(["bash", "-c", cmd]);
            }
        }));
    }

    function createAppResultObject(entry) {
        return resultComp.createObject(null, {
            key: "app:" + entry.id,
            type: Translation.tr("App"),
            id: entry.id,
            name: entry.name,
            iconName: entry.icon,
            iconType: LauncherSearchResult.IconType.System,
            verb: Translation.tr("Open"),
            execute: () => {
                AppUsage.recordLaunch(entry.id);
                if (!entry.runInTerminal)
                    entry.execute();
                else {
                    Quickshell.execDetached(["bash", '-c', `${Config.options.apps.terminal} -e '${StringUtils.shellSingleQuoteEscape(entry.command.join(' '))}'`]);
                }
            },
            comment: entry.comment,
            runInTerminal: entry.runInTerminal,
            genericName: entry.genericName,
            keywords: entry.keywords,
            actions: entry.actions.map(action => {
                return resultComp.createObject(null, {
                    name: action.name,
                    iconName: action.icon,
                    iconType: LauncherSearchResult.IconType.System,
                    execute: () => {
                        if (!action.runInTerminal)
                            action.execute();
                        else {
                            Quickshell.execDetached(["bash", '-c', `${Config.options.apps.terminal} -e '${StringUtils.shellSingleQuoteEscape(action.command.join(' '))}'`]);
                        }
                    }
                });
            })
        });
    }

    property list<var> results: {
        let _ = root._mprisTrigger;
        let _apps = AppSearch.list; // Establish reactive binding to application list!
        // Search results are handled here

        ////////////////// MPRIS (empty query) //////////////////
        if (root.query === "") {
            let mprisResults = [];
            if (MprisController.activePlayer) {
                const player = MprisController.activePlayer;
                const title = player.trackTitle || Translation.tr("Unknown");
                const artist = player.trackArtist || "";
                const displayName = artist ? `${title} — ${artist}` : title;

                mprisResults.push(resultComp.createObject(null, {
                    key: "mpris:now-playing",
                    name: displayName,
                    type: Translation.tr("Now Playing"),
                    verb: MprisController.isPlaying ? Translation.tr("Pause") : Translation.tr("Play"),
                    iconName: MprisController.isPlaying ? "pause" : "play_arrow",
                    iconType: LauncherSearchResult.IconType.Material,
                    execute: () => {
                        MprisController.togglePlaying();
                    },
                    actions: [
                        resultComp.createObject(null, {
                            name: Translation.tr("Previous"),
                            iconName: "skip_previous",
                            iconType: LauncherSearchResult.IconType.Material,
                            execute: () => { MprisController.previous(); }
                        }),
                        resultComp.createObject(null, {
                            name: Translation.tr("Next"),
                            iconName: "skip_next",
                            iconType: LauncherSearchResult.IconType.Material,
                            execute: () => { MprisController.next(); }
                        })
                    ]
                }));
            }

            if (Config.options.search.alwaysListApps) {
                const appResultObjects = AppSearch.fuzzyQuery("").map(entry => root.createAppResultObject(entry));
                return mprisResults.concat(appResultObjects);
            }

            return mprisResults;
        }

        ///////////// Special cases ///////////////
        if (root.query.startsWith(Config.options.search.prefix.clipboard)) {
            // Clipboard
            const searchString = StringUtils.cleanPrefix(root.query, Config.options.search.prefix.clipboard);
            
            const pinnedMatches = Cliphist.pinnedEntries.filter(e => {
                if (searchString === "") return true;
                return e.toLowerCase().includes(searchString.toLowerCase());
            });

            const fuzzyResults = Cliphist.fuzzyQuery(searchString).filter(e => !Cliphist.isPinned(e));
            const allResults = pinnedMatches.concat(fuzzyResults);

            return allResults.map((entry, index, array) => {
                const isPinned = index < pinnedMatches.length;
                const mightBlurImage = Cliphist.entryIsImage(entry) && root.clipboardWorkSafetyActive;
                let shouldBlurImage = mightBlurImage;
                if (mightBlurImage) {
                    shouldBlurImage = shouldBlurImage && (root.containsUnsafeLink(array[index - 1]) || root.containsUnsafeLink(array[index + 1]));
                }
                const type = `#${entry.match(/^\s*(\S+)/)?.[1] || ""}`;
                const contentType = Cliphist.classifyEntry(entry);
                return resultComp.createObject(null, {
                    key: "clip:" + entry.split("\t")[0],
                    rawValue: entry,
                    name: StringUtils.cleanCliphistEntry(entry),
                    verb: "",
                    type: type,
                    pinned: isPinned,
                    category: contentType || "clipboard",
                    execute: () => {
                        Cliphist.copy(entry);
                    },
                    actions: [
                        resultComp.createObject(null, {
                            name: Translation.tr("Copy"),
                            iconName: "content_copy",
                            iconType: LauncherSearchResult.IconType.Material,
                            execute: () => {
                                Cliphist.copy(entry);
                            }
                        }),
                        resultComp.createObject(null, {
                            name: isPinned ? Translation.tr("Unpin") : Translation.tr("Pin"),
                            iconName: isPinned ? "keep_off" : "keep",
                            iconType: LauncherSearchResult.IconType.Material,
                            execute: () => {
                                if (isPinned) Cliphist.unpin(entry);
                                else Cliphist.pin(entry);
                            }
                        }),
                        resultComp.createObject(null, {
                            name: Translation.tr("Delete"),
                            iconName: "delete",
                            iconType: LauncherSearchResult.IconType.Material,
                            execute: () => {
                                Cliphist.deleteEntry(entry);
                            }
                        })
                    ],
                    blurImage: shouldBlurImage
                });
            }).filter(Boolean);
        } else if (root.query.startsWith(Config.options.search.prefix.emojis)) {
            const searchString = StringUtils.cleanPrefix(root.query, Config.options.search.prefix.emojis);
            return Emojis.fuzzyQuery(searchString).map(entry => {
                const emoji = entry.match(/^\s*(\S+)/)?.[1] || "";
                const emojiName = entry.replace(/^\s*\S+\s+/, "");
                return resultComp.createObject(null, {
                    key: "emoji:" + emoji,
                    rawValue: entry,
                    name: emojiName,
                    iconName: emoji,
                    iconType: LauncherSearchResult.IconType.Text,
                    verb: Translation.tr("Copy"),
                    type: Translation.tr("Emoji"),
                    execute: () => {
                        Quickshell.clipboardText = emoji;
                    },
                    actions: [
                        resultComp.createObject(null, {
                            name: Translation.tr("Copy emoji"),
                            iconName: "content_copy",
                            iconType: LauncherSearchResult.IconType.Material,
                            execute: () => { Quickshell.clipboardText = emoji; }
                        }),
                        resultComp.createObject(null, {
                            name: Translation.tr("Copy name"),
                            iconName: "label",
                            iconType: LauncherSearchResult.IconType.Material,
                            execute: () => { Quickshell.clipboardText = emojiName; }
                        })
                    ]
                });
            }).filter(Boolean);
        } else if (root.query.startsWith(Config.options.search.prefix.windowSearch)) {
            const searchString = root.query.slice(Config.options.search.prefix.windowSearch.length);
            const windows = getWindowResults(searchString);
            return windows.map(w => {
                return resultComp.createObject(null, {
                    key: "win:" + (w.address || w.title || w.class),
                    name: w.title || w.class || "Unknown",
                    type: Translation.tr("Window"),
                    verb: Translation.tr("Focus"),
                    iconName: AppSearch.guessIcon(w.class || ""),
                    iconType: LauncherSearchResult.IconType.System,
                    comment: `${w.class} — Workspace ${w.workspace?.id ?? "?"}`,
                    execute: () => {
                        Hyprland.dispatch(`hl.dsp.focus({window = "address:${w.address}"})`);
                    },
                    actions: [
                        resultComp.createObject(null, {
                            name: Translation.tr("Close"),
                            iconName: "close",
                            iconType: LauncherSearchResult.IconType.Material,
                            execute: () => {
                                Hyprland.dispatch(`hl.dsp.window.close({window = "address:${w.address}"})`);
                            }
                        }),
                        resultComp.createObject(null, {
                            name: Translation.tr("Move here"),
                            iconName: "move_item",
                            iconType: LauncherSearchResult.IconType.Material,
                            execute: () => {
                                const activeWsId = Hyprland.focusedMonitor?.activeWorkspace?.id;
                                if (activeWsId) {
                                    Hyprland.dispatch(`hl.dsp.window.move({ workspace = ${activeWsId}, follow = false, window = "address:${w.address}" })`);
                                } else {
                                    Hyprland.dispatch(`movetoworkspacesilent e+0,address:${w.address}`);
                                }
                            }
                        }),
                        resultComp.createObject(null, {
                            name: Translation.tr("Copy title"),
                            iconName: "content_copy",
                            iconType: LauncherSearchResult.IconType.Material,
                            execute: () => { Quickshell.clipboardText = w.title || w.class || ""; }
                        })
                    ]
                });
            }).filter(Boolean);
        } else if (root.query.startsWith(Config.options.search.prefix.fileBrowser)) {
            // File browser / directory navigation
            // Process call is debounced via onQueryChanged, results are in fileBrowserResults
            const rawPath = root.query.slice(Config.options.search.prefix.fileBrowser.length);
            const homePath = FileUtils.trimFileProtocol(Directories.home);
            const expandedPath = rawPath.startsWith("/") ? rawPath : (homePath + "/" + rawPath);
            
            // Find the directory part and the filter part
            const lastSlash = expandedPath.lastIndexOf("/");
            const dirPath = lastSlash >= 0 ? expandedPath.slice(0, lastSlash + 1) : expandedPath;
            const filter = lastSlash >= 0 ? expandedPath.slice(lastSlash + 1).toLowerCase() : "";
            
            const filtered = root.fileBrowserResults.filter(entry => {
                if (filter === "") return true;
                return entry.toLowerCase().includes(filter);
            });

            return filtered.map(entry => {
                const isDir = entry.endsWith("/");
                const fullPath = dirPath + entry;
                const isImage = !isDir && Images.isValidImageByName(fullPath);
                const fileIcon = isDir ? "folder" : (isImage ? "image" : "description");
                return resultComp.createObject(null, {
                    key: "file:" + fullPath,
                    name: isImage ? fullPath : entry,
                    type: isDir ? Translation.tr("Directory") : Translation.tr("File"),
                    verb: isDir ? Translation.tr("Browse") : Translation.tr("Open"),
                    iconName: fileIcon,
                    iconType: LauncherSearchResult.IconType.Material,
                    comment: fullPath,
                    execute: () => {
                        if (isDir) {
                            const newQuery = Config.options.search.prefix.fileBrowser + fullPath.replace(homePath, "");
                            root.query = newQuery;
                        } else {
                            Quickshell.execDetached(["xdg-open", fullPath]);
                        }
                    },
                    actions: [
                        resultComp.createObject(null, {
                            name: Translation.tr("Copy path"),
                            iconName: "content_copy",
                            iconType: LauncherSearchResult.IconType.Material,
                            execute: () => {
                                Quickshell.clipboardText = fullPath;
                            }
                        }),
                        resultComp.createObject(null, {
                            name: Translation.tr("Open in file manager"),
                            iconName: "folder_open",
                            iconType: LauncherSearchResult.IconType.Material,
                            execute: () => {
                                Quickshell.execDetached(["xdg-open", isDir ? fullPath : dirPath]);
                            }
                        })
                    ]
                });
            }).filter(Boolean);
        }




        ////////////////// Init ///////////////////
        nonAppResultsTimer.restart();
        const mathResultObject = resultComp.createObject(null, {
            key: "math:result",
            name: root.mathResult || Translation.tr("Evaluate math..."),
            verb: Translation.tr("Copy"),
            type: Translation.tr("Math result"),
            fontType: LauncherSearchResult.FontType.Monospace,
            iconName: 'calculate',
            iconType: LauncherSearchResult.IconType.Material,
            isMath: Config.options.search.enableMathPreview && !!root.mathResult,
            execute: () => {
                Quickshell.clipboardText = root.mathResult;
            }
        });
        const fileResultsObject = root.fileResults.map(entry => {
            const isImage = Images.isValidImageByName(entry);
            return resultComp.createObject(null, {
                key: "fsearch:" + entry,
                type: Translation.tr("File"),
                name: entry,
                verb: Translation.tr("Open"),
                iconName: isImage ? 'image' : 'file_open',
                iconType: LauncherSearchResult.IconType.Material,
                execute: () => {
                    Quickshell.execDetached(["xdg-open", entry]);
                },
                actions: [
                    resultComp.createObject(null, {
                        name: Translation.tr("Copy path"),
                        iconName: "content_copy",
                        iconType: LauncherSearchResult.IconType.Material,
                        execute: () => { Quickshell.clipboardText = entry; }
                    }),
                    resultComp.createObject(null, {
                        name: Translation.tr("Open folder"),
                        iconName: "folder_open",
                        iconType: LauncherSearchResult.IconType.Material,
                        execute: () => {
                            const dir = entry.substring(0, entry.lastIndexOf("/") + 1);
                            Quickshell.execDetached(["xdg-open", dir]);
                        }
                    })
                ]
            });
        })

        // MPRIS handled above (empty query case)

        const appResultObjects = AppSearch.fuzzyQuery(StringUtils.cleanPrefix(root.query, Config.options.search.prefix.app)).map(entry => root.createAppResultObject(entry));
        const commandResultObject = resultComp.createObject(null, {
            key: "cmd:shell",
            name: StringUtils.cleanPrefix(root.query, Config.options.search.prefix.shellCommand).replace("file://", ""),
            verb: Translation.tr("Run"),
            type: Translation.tr("Command"),
            fontType: LauncherSearchResult.FontType.Monospace,
            iconName: 'terminal',
            iconType: LauncherSearchResult.IconType.Material,
            execute: () => {
                let cleanedCommand = root.query.replace("file://", "");
                cleanedCommand = StringUtils.cleanPrefix(cleanedCommand, Config.options.search.prefix.shellCommand);
                if (cleanedCommand.startsWith(Config.options.search.prefix.shellCommand)) {
                    cleanedCommand = cleanedCommand.slice(Config.options.search.prefix.shellCommand.length);
                }
                Quickshell.execDetached(["bash", "-c", root.query.startsWith('sudo') ? `${Config.options.apps.terminal} fish -C '${cleanedCommand}'` : cleanedCommand]);
            }
        });
        const webSearchResultObject = resultComp.createObject(null, {
            key: "web:search",
            name: StringUtils.cleanPrefix(root.query, Config.options.search.prefix.webSearch),
            verb: Translation.tr("Search"),
            type: Translation.tr("Web search"),
            iconName: 'travel_explore',
            iconType: LauncherSearchResult.IconType.Material,
            execute: () => {
                let query = StringUtils.cleanPrefix(root.query, Config.options.search.prefix.webSearch);
                let url = Config.options.search.engineBaseUrl + query;
                for (let site of Config.options.search.excludedSites) {
                    url += ` -site:${site}`;
                }
                Qt.openUrlExternally(url);
            }
        });
        const launcherActionObjects = root.allActions.map(action => {
            const actionString = `${Config.options.search.prefix.action}${action.action}`;
            if (actionString.startsWith(root.query) || root.query.startsWith(actionString)) {
                return resultComp.createObject(null, {
                    key: "action:" + action.action,
                    name: root.query.startsWith(actionString) ? root.query : actionString,
                    verb: Translation.tr("Run"),
                    type: Translation.tr("Action"),
                    iconName: 'settings_suggest',
                    iconType: LauncherSearchResult.IconType.Material,
                    execute: () => {
                        action.execute(root.query.split(" ").slice(1).join(" "));
                    }
                });
            }
            return null;
        }).filter(Boolean);

        // Shell snippet results
        const snippetActions = getShellSnippetActions();
        const shellSnippetObjects = snippetActions.map(snippet => {
            const snippetString = `${Config.options.search.prefix.action}${snippet.action}`;
            if (snippetString.startsWith(root.query) || root.query.startsWith(snippetString)) {
                return resultComp.createObject(null, {
                    key: "snippet:" + snippet.action,
                    name: snippet.name,
                    verb: Translation.tr("Run"),
                    type: Translation.tr("Script"),
                    iconName: 'code',
                    iconType: LauncherSearchResult.IconType.Material,
                    comment: snippet.command,
                    execute: () => {
                        snippet.execute(root.query.split(" ").slice(1).join(" "));
                    }
                });
            }
            return null;
        }).filter(Boolean);

        //////// Prioritized by prefix /////////
        let result = [];

        // App/Folder/Command Aliases
        const aliases = Config.options?.search?.aliases ?? [];
        const aliasObjects = aliases.map(entry => {
            if (entry.alias && entry.alias.toLowerCase() === root.query.toLowerCase()) {
                if (entry.type === "app") {
                    const app = DesktopEntries.byId(entry.target);
                    if (app) {
                        return resultComp.createObject(null, {
                            key: "alias:" + entry.alias,
                            name: app.name,
                            iconName: app.icon,
                            iconType: LauncherSearchResult.IconType.System,
                            verb: Translation.tr("Open"),
                            type: Translation.tr("App Alias"),
                            execute: () => {
                                AppUsage.recordLaunch(app.id);
                                if (!app.runInTerminal) app.execute();
                                else Quickshell.execDetached(["bash", '-c', `${Config.options.apps.terminal} -e '${StringUtils.shellSingleQuoteEscape(app.command.join(' '))}'`]);
                            }
                        });
                    }
                } else if (entry.type === "folder") {
                    return resultComp.createObject(null, {
                        key: "alias:" + entry.alias,
                        name: entry.target,
                        iconName: "folder",
                        iconType: LauncherSearchResult.IconType.Material,
                        verb: Translation.tr("Browse"),
                        type: Translation.tr("Folder Alias"),
                        execute: () => {
                            root.query = Config.options.search.prefix.fileBrowser + entry.target;
                        }
                    });
                } else if (entry.type === "command") {
                    return resultComp.createObject(null, {
                        key: "alias:" + entry.alias,
                        name: entry.target,
                        iconName: "terminal",
                        iconType: LauncherSearchResult.IconType.Material,
                        verb: Translation.tr("Run"),
                        type: Translation.tr("Command Alias"),
                        execute: () => {
                            Quickshell.execDetached(["bash", "-c", entry.target]);
                        }
                    });
                }
            }
            return null;
        }).filter(Boolean);
        result = result.concat(aliasObjects);

        const isMath = root.isMathQuery(root.query);
        const startsWithShellCommandPrefix = root.query.startsWith(Config.options.search.prefix.shellCommand);
        const startsWithWebSearchPrefix = root.query.startsWith(Config.options.search.prefix.webSearch);

        // System Controls matches
        const systemControlResults = [];
        let queryClean = root.query.toLowerCase().trim();
        const hasColonPrefix = queryClean.startsWith(":");
        if (hasColonPrefix) {
            queryClean = queryClean.slice(1);
        }

        if (Config.options.search.enableSystemControls && (hasColonPrefix || queryClean.length >= 2)) {
            const sysCommands = [
                { cmd: "lock", label: Translation.tr("Lock Screen"), execute: () => Quickshell.execDetached(["hyprlock"]), icon: "lock", desc: Translation.tr("Lock the current session") },
                { cmd: "poweroff", label: Translation.tr("Shutdown PC"), execute: () => Quickshell.execDetached(["systemctl", "poweroff"]), icon: "power_settings_new", desc: Translation.tr("Power off the computer") },
                { cmd: "reboot", label: Translation.tr("Reboot PC"), execute: () => Quickshell.execDetached(["systemctl", "reboot"]), icon: "restart_alt", desc: Translation.tr("Restart the computer") },
                { cmd: "suspend", label: Translation.tr("Suspend PC"), execute: () => Quickshell.execDetached(["systemctl", "suspend"]), icon: "bedtime", desc: Translation.tr("Put the computer to sleep") },
                { cmd: "restart", label: Translation.tr("Restart Quickshell"), execute: () => Quickshell.reload(), icon: "refresh", desc: Translation.tr("Restart Quickshell shell seamlessly") },
            ];
            const matches = sysCommands.filter(c => c.cmd.startsWith(queryClean));
            for (const match of matches) {
                const isPendingConfirm = root.confirmKey === match.cmd;
                systemControlResults.push(resultComp.createObject(null, {
                    key: "sys:" + match.cmd,
                    name: isPendingConfirm ? match.label + " (" + Translation.tr("Are you sure?") + ")" : match.label,
                    type: Translation.tr("System Control"),
                    comment: isPendingConfirm ? Translation.tr("Press Enter again to confirm") : match.desc,
                    verb: isPendingConfirm ? Translation.tr("Confirm") : Translation.tr("Execute"),
                    iconName: match.icon,
                    iconType: LauncherSearchResult.IconType.Material,
                    execute: () => {
                        if (root.confirmKey === match.cmd) {
                            root.confirmKey = "";
                            match.execute();
                        } else {
                            root.confirmKey = match.cmd;
                        }
                    }
                }));
            }
        }

        if (systemControlResults.length > 0) {
            result = result.concat(systemControlResults);
        }
        
        if (isMath) {
            result.push(mathResultObject);
        } else if (startsWithShellCommandPrefix) {
            result.push(commandResultObject);
        } else if (startsWithWebSearchPrefix) {
            result.push(webSearchResultObject);
        }

        //////////////// Files /////////////////
        result = result.concat(fileResultsObject);

        //////////////// Apps //////////////////
        result = result.concat(appResultObjects);

        ////////// Launcher actions ////////////
        result = result.concat(launcherActionObjects);

        ////////// Shell snippets //////////////
        result = result.concat(shellSnippetObjects);

        ////////// Module shortcuts ////////////
        // Typing module names shows a shortcut to switch to that mode
        const moduleShortcuts = [
            { names: ["clipboard", "clip", "paste", "copiar"], prefix: Config.options.search.prefix.clipboard, label: Translation.tr("Clipboard"), icon: "content_paste" },
            { names: ["emoji", "emojis", "emoticon"], prefix: Config.options.search.prefix.emojis, label: Translation.tr("Emojis"), icon: "mood" },
            { names: ["window", "windows", "janela"], prefix: Config.options.search.prefix.windowSearch, label: Translation.tr("Window Search"), icon: "select_window" },
            { names: ["file", "files", "arquivo", "browse"], prefix: Config.options.search.prefix.fileBrowser, label: Translation.tr("File Browser"), icon: "folder_open" },
            { names: ["math", "calc", "calculator", "calcular"], prefix: Config.options.search.prefix.math, label: Translation.tr("Calculator"), icon: "calculate" },
            { names: ["command", "commands", "terminal", "shell"], prefix: Config.options.search.prefix.shellCommand, label: Translation.tr("Shell Command"), icon: "terminal" },
        ];

        const queryLower = root.query.toLowerCase();
        for (const mod of moduleShortcuts) {
            if (mod.names.some(n => n.startsWith(queryLower) && queryLower.length >= 2)) {
                result.push(resultComp.createObject(null, {
                    key: "shortcut:" + mod.label,
                    name: mod.label,
                    type: Translation.tr("Shortcut"),
                    verb: Translation.tr("Open"),
                    iconName: mod.icon,
                    iconType: LauncherSearchResult.IconType.Material,
                    execute: () => {
                        root.query = mod.prefix;
                    }
                }));
            }
        }

        /// Math result, command, web search ///
        if (Config.options.search.prefix.showDefaultActionsWithoutPrefix) {
            if (!startsWithShellCommandPrefix)
                result.push(commandResultObject);
            if (!isMath)
                result.push(mathResultObject);
            if (!startsWithWebSearchPrefix)
                result.push(webSearchResultObject);
        }

        // Filter out duplicate original apps/folders/commands if an alias is shown
        const activeAliases = (Config.options?.search?.aliases ?? []).filter(entry => entry.alias && entry.alias.toLowerCase() === root.query.toLowerCase());
        if (activeAliases.length > 0) {
            result = result.filter(item => {
                if (!item || !item.key) return false;
                for (const alias of activeAliases) {
                    if (alias.type === "app" && item.key === "app:" + alias.target) {
                        return false;
                    }
                    if (alias.type === "folder" && item.key.startsWith("file:")) {
                        const filePath = item.key.slice(5);
                        const targetNormalized = alias.target.startsWith("/") ? alias.target : 
                                                 alias.target.startsWith("~") ? alias.target.replace("~", Directories.home) :
                                                 Directories.home + "/" + alias.target;
                        const cleanFilePath = filePath.replace(/\/+$/, "");
                        const cleanTarget = targetNormalized.replace(/\/+$/, "");
                        if (cleanFilePath === cleanTarget) {
                            return false;
                        }
                    }
                    if (alias.type === "command" && item.key === "command:" + alias.target) {
                        return false;
                    }
                }
                return true;
            });
        }

        return result;
    }

    Connections {
        target: MprisController
        function onActivePlayerChanged() {
            root._mprisTrigger++;
        }
        function onIsPlayingChanged() {
            root._mprisTrigger++;
        }
        function onTrackChanged() {
            root._mprisTrigger++;
        }
    }

    function createResult(properties) {
        return {
            key: properties.key || "",
            type: properties.type || "",
            fontType: properties.fontType !== undefined ? properties.fontType : LauncherSearchResult.FontType.Normal,
            name: properties.name || "",
            rawValue: properties.rawValue || "",
            iconName: properties.iconName || "",
            iconType: properties.iconType !== undefined ? properties.iconType : LauncherSearchResult.IconType.None,
            verb: properties.verb || "",
            blurImage: !!properties.blurImage,
            pinned: !!properties.pinned,
            execute: properties.execute || (() => { print("Not implemented"); }),
            actions: properties.actions || [],
            id: properties.id || "",
            shown: properties.shown !== undefined ? properties.shown : true,
            comment: properties.comment || "",
            runInTerminal: !!properties.runInTerminal,
            genericName: properties.genericName || "",
            keywords: properties.keywords || [],
            isMath: !!properties.isMath,
            category: properties.category || properties.type || ""
        };
    }

    readonly property var resultComp: {
        "createObject": function(parent, properties) {
            return root.createResult(properties);
        }
    }
}
