pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.bar
import qs.modules.ii.bar.shared

RowLayout {
    id: root
    spacing: 6
    property bool animateWidth: false
    property bool clipboardMode: false
    property bool activePanelMode: false
    property var activePanel: null
    property bool activePanelOwnsInput: false
    property bool activePanelQueryEmpty: false
    property bool supportsPanelSectionToggle: false
    property int clipboardWidth: 860
    property alias searchInput: searchInput
    property string searchingText
    property int currentResultIndex: 0
    property var selectedResultRef: null
    property bool isTranslatorPanelFocused: false
    property bool isMediaDownloaderPanelFocused: false
    property bool isMaterialSymbolsPanelFocused: false
    property bool showSuggestionsPanel: false
    property bool showCategoryFilter: false
    property string categoryFilterLabel: ""
    property string categoryFilterIcon: "category"
    readonly property bool selectedResultSupportsHorizontalNavigation: {
        const type = String(root.selectedResultRef?.settingRef?.type ?? "");
        return type === "bool" || type === "int" || type === "real" || type === "enum";
    }
    // True while the overview search widget is in AI chat mode — the field
    // becomes the chat composer.
    property bool aiModeActive: false
    // Do not echo a programmatic handoff back into the launcher query. The
    // query is cleared when AI takes over; echoing that assignment through the
    // hidden field creates a query/isAiMode feedback loop and drops focus.
    property bool syncingSearchText: false

    BarThemes {
        id: barThemes
    }
    property var activeTheme: barThemes.getTheme(Config.options.bar.expressiveColorTheme)

    onSearchingTextChanged: {
        if (searchInput.text !== searchingText) {
            root.syncingSearchText = true;
            searchInput.text = searchingText;
            root.syncingSearchText = false;
        }
    }

    signal navigateUp
    signal navigateDown
    signal navigateSectionUp
    signal navigateSectionDown
    signal runSecondaryAction(int index)
    signal navigateLeft
    signal navigateRight
    signal activate
    signal deleteSelected
    signal ctrlKPressed
    signal backspaceOnEmpty
    signal panelShortcut(string methodName)
    signal copySvgPressed
    signal togglePanelSection
    signal copySelected
    signal openSelectedInCheatsheet
    signal saveSelected
    signal editSelected
    signal ocrSelected
    signal copyDispatchSelected
    signal createFromQuery
    signal historyPrevious
    signal historyNext
    signal toggleFavorite
    signal cycleCategoryFilter(int step)
    // Fired when Esc is pressed while the text is empty in AI mode — asks the
    // host to leave AI chat and return to the plain search.
    signal escapeToSearch
    // Fired when Enter is pressed in AI mode — sends the text as a message.
    signal sendMessage

    function normalizedShortcut(value) {
        return String(value ?? "").replace(/\s+/g, "").replace(/control/ig, "ctrl").toLocaleLowerCase();
    }

    function configuredShortcut(actionId, fallback) {
        const entry = Array.from(Config.options.search.keybindings ?? [])
            .find(binding => String(binding?.actionId ?? "") === actionId);
        return root.normalizedShortcut(entry?.shortcut ?? fallback);
    }

    function eventShortcut(event) {
        const parts = [];
        if (event.modifiers & Qt.ControlModifier)
            parts.push("ctrl");
        if (event.modifiers & Qt.AltModifier)
            parts.push("alt");
        if (event.modifiers & Qt.ShiftModifier)
            parts.push("shift");
        if (event.modifiers & Qt.MetaModifier)
            parts.push("meta");
        let key = "";
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
            key = "enter";
        else if (event.key === Qt.Key_Up)
            key = "up";
        else if (event.key === Qt.Key_Down)
            key = "down";
        else if (event.key === Qt.Key_Left)
            key = "left";
        else if (event.key === Qt.Key_Right)
            key = "right";
        else if (event.key === Qt.Key_Tab)
            key = "tab";
        else if (event.key === Qt.Key_Delete)
            key = "delete";
        else if (event.key === Qt.Key_Space)
            key = "space";
        else if (event.key === Qt.Key_Backspace)
            key = "backspace";
        else if (event.key === Qt.Key_Home)
            key = "home";
        else if (event.key >= Qt.Key_A && event.key <= Qt.Key_Z)
            key = String.fromCharCode(event.key).toLocaleLowerCase();
        return parts.concat(key ? [key] : []).join("+");
    }

    function matchesShortcut(event, actionId, fallback) {
        return root.eventShortcut(event) === root.configuredShortcut(actionId, fallback);
    }

    function fileBrowserTextForPath(path): string {
        const home = FileUtils.trimFileProtocol(Directories.home).replace(/\/$/, "");
        const rawTarget = FileUtils.trimFileProtocol(String(path ?? ""));
        let target = rawTarget === "/" ? "/" : rawTarget.replace(/\/$/, "");
        if (target.startsWith("~/"))
            target = home + target.slice(1);
        else if (target.length === 0)
            target = home;
        else if (!target.startsWith("/"))
            target = home + "/" + target;
        const encoded = target === home
            ? "/"
            : (target.startsWith(home + "/") ? target.slice(home.length) + "/" : "/" + target + "/");
        return Config.options.search.prefix.fileBrowser + encoded;
    }

    function forceFocus() {
        if (root.activePanelOwnsInput)
            return;
        searchInput.forceActiveFocus();
    }

    enum SearchPrefixType {
        Action,
        App,
        Clipboard,
        Emojis,
        Math,
        ShellCommand,
        WebSearch,
        WindowSearch,
        Translator,
        MediaDownloader,
        MaterialSymbols,
        AiChat,
        Suggestions,
        DefaultSearch
    }

    property var searchPrefixType: {
        if (root.searchingText.startsWith(Config.options.search.prefix.action))
            return SearchBar.SearchPrefixType.Action;
        if (root.searchingText.startsWith(Config.options.search.prefix.app) || (Config.options.search.alwaysListApps && root.searchingText === ""))
            return SearchBar.SearchPrefixType.App;
        if (root.searchingText.startsWith(Config.options.search.prefix.clipboard))
            return SearchBar.SearchPrefixType.Clipboard;
        if (root.searchingText.startsWith(Config.options.search.prefix.emojis))
            return SearchBar.SearchPrefixType.Emojis;
        if (root.searchingText.startsWith(Config.options.search.prefix.math))
            return SearchBar.SearchPrefixType.Math;
        if (root.searchingText.startsWith(Config.options.search.prefix.shellCommand))
            return SearchBar.SearchPrefixType.ShellCommand;
        if (root.searchingText.startsWith(Config.options.search.prefix.webSearch))
            return SearchBar.SearchPrefixType.WebSearch;
        if (root.searchingText.startsWith(Config.options.search.prefix.windowSearch))
            return SearchBar.SearchPrefixType.WindowSearch;
        if (root.searchingText.startsWith(Config.options.search.prefix.translator))
            return SearchBar.SearchPrefixType.Translator;
        if (Config.options.mediaDownloader.enabled && root.searchingText.startsWith(Config.options.search.prefix.mediaDownloader))
            return SearchBar.SearchPrefixType.MediaDownloader;
        if (root.searchingText.startsWith(Config.options.search.prefix.materialSymbols))
            return SearchBar.SearchPrefixType.MaterialSymbols;
        if (root.aiModeActive)
            return SearchBar.SearchPrefixType.AiChat;
        if (root.showSuggestionsPanel && root.searchingText === "")
            return SearchBar.SearchPrefixType.Suggestions;
        return SearchBar.SearchPrefixType.DefaultSearch;
    }

    MaterialShapeWrappedMaterialSymbol {
        id: searchIcon
        Layout.alignment: Qt.AlignVCenter
        iconSize: Appearance.font.pixelSize.huge
        opacity: 1.0

        property string _lastText: ""
        property bool _initialized: false

        readonly property real symmetryAngle: {
            const panelStep = Number(root.activePanel?.searchRotationStep ?? 0);
            if (root.activePanelMode && panelStep > 0)
                return panelStep;
            switch (root.searchPrefixType) {
            case SearchBar.SearchPrefixType.Action:
                return 180;        // Pill
            case SearchBar.SearchPrefixType.App:
                return 90;            // Clover4Leaf
            case SearchBar.SearchPrefixType.Clipboard:
                return 90;      // Gem
            case SearchBar.SearchPrefixType.Emojis:
                return 45;         // Sunny
            case SearchBar.SearchPrefixType.Math:
                return 90;           // PuffyDiamond
            case SearchBar.SearchPrefixType.ShellCommand:
                return 90;   // PixelCircle
            case SearchBar.SearchPrefixType.WebSearch:
                return 45;      // SoftBurst
            case SearchBar.SearchPrefixType.WindowSearch:
                return 360;  // Arch
            case SearchBar.SearchPrefixType.Translator:
                return 60;     // Cookie6Sided
            case SearchBar.SearchPrefixType.MediaDownloader:
                return 40;     // Cookie9Sided
            case SearchBar.SearchPrefixType.MaterialSymbols:
                return 45;     // SoftBurst
            case SearchBar.SearchPrefixType.AiChat:
                return 90;             // Clover4Leaf
            case SearchBar.SearchPrefixType.Suggestions:
                return 45;     // SoftBurst
            default:
                return 360 / 7;                                   // Cookie7Sided
            }
        }

        // No Behavior here on purpose. MaterialShapeWrappedMaterialSymbol already
        // declares one on `rotation`, and a second declaration on the same
        // property is ambiguous — which of the two actually intercepted the write
        // was never decidable from the code. The wrapper's SmoothedAnimation is
        // the one that belongs to this kind of motion anyway.

        Connections {
            target: root

            /**
             * One writer, always forward.
             *
             * Rotation used to have three: a `+=` per keystroke, an imperative
             * 0→360 animation on every prefix change, and a hard reset to 0 when
             * the field was cleared. The imperative animation wrote the property
             * directly and yanked the angle back to 0 mid-typing; the reset
             * unwound every turn accumulated so far in one long backwards spin.
             *
             * Now every event is an addition to the same accumulator, so they
             * blend instead of fighting, and the shape's rotational symmetry
             * means each keystroke still settles on a visually upright pose.
             */
            function onSearchPrefixTypeChanged() {
                searchIcon.rotation += 360;
            }

            function onSearchingTextChanged() {
                if (!searchIcon._initialized) {
                    searchIcon._initialized = true;
                    searchIcon._lastText = root.searchingText;
                    return;
                }

                if (root.searchingText === "") {
                    // The new shape has its own symmetry, so the accumulated angle
                    // is no longer an upright pose for it. Finish the turn instead
                    // of running the spin backwards to reach the same picture.
                    searchIcon.rotation = Math.ceil(searchIcon.rotation / 360) * 360;
                } else if (root.searchingText !== searchIcon._lastText) {
                    searchIcon.rotation += searchIcon.symmetryAngle;
                }
                searchIcon._lastText = root.searchingText;
            }
        }

        shape: {
            const panelShape = String(root.activePanel?.searchShape ?? "");
            if (root.activePanelMode && panelShape.length > 0)
                return searchIcon.getShape(panelShape);
            switch (root.searchPrefixType) {
            case SearchBar.SearchPrefixType.Action:
                return MaterialShape.Shape.Pill;
            case SearchBar.SearchPrefixType.App:
                return MaterialShape.Shape.Clover4Leaf;
            case SearchBar.SearchPrefixType.Clipboard:
                return MaterialShape.Shape.Gem;
            case SearchBar.SearchPrefixType.Emojis:
                return MaterialShape.Shape.Sunny;
            case SearchBar.SearchPrefixType.Math:
                return MaterialShape.Shape.PuffyDiamond;
            case SearchBar.SearchPrefixType.ShellCommand:
                return MaterialShape.Shape.PixelCircle;
            case SearchBar.SearchPrefixType.WebSearch:
                return MaterialShape.Shape.SoftBurst;
            case SearchBar.SearchPrefixType.WindowSearch:
                return MaterialShape.Shape.Arch;
            case SearchBar.SearchPrefixType.Translator:
                return MaterialShape.Shape.Cookie6Sided;
            case SearchBar.SearchPrefixType.MediaDownloader:
                return MaterialShape.Shape.Cookie9Sided;
            case SearchBar.SearchPrefixType.MaterialSymbols:
                return MaterialShape.Shape.SoftBurst;
            case SearchBar.SearchPrefixType.AiChat:
                return MaterialShape.Shape.Clover4Leaf;
            case SearchBar.SearchPrefixType.Suggestions:
                return MaterialShape.Shape.SoftBurst;
            default:
                return MaterialShape.Shape.Cookie7Sided;
            }
        }
        text: {
            const panelIcon = String(root.activePanel?.searchIcon ?? "");
            if (root.activePanelMode && panelIcon.length > 0)
                return panelIcon;
            switch (root.searchPrefixType) {
            case SearchBar.SearchPrefixType.Action:
                return "settings_suggest";
            case SearchBar.SearchPrefixType.App:
                return "apps";
            case SearchBar.SearchPrefixType.Clipboard:
                return "content_paste_search";
            case SearchBar.SearchPrefixType.Emojis:
                return "add_reaction";
            case SearchBar.SearchPrefixType.Math:
                return "calculate";
            case SearchBar.SearchPrefixType.ShellCommand:
                return "terminal";
            case SearchBar.SearchPrefixType.WebSearch:
                return "travel_explore";
            case SearchBar.SearchPrefixType.WindowSearch:
                return "select_window";
            case SearchBar.SearchPrefixType.Translator:
                return "translate";
            case SearchBar.SearchPrefixType.MediaDownloader:
                return "download";
            case SearchBar.SearchPrefixType.MaterialSymbols:
                return "font_download";
            case SearchBar.SearchPrefixType.AiChat:
                return "auto_awesome";
            case SearchBar.SearchPrefixType.Suggestions:
                return "explore";
            case SearchBar.SearchPrefixType.DefaultSearch:
                return "search";
            default:
                return "search";
            }
        }
    }
    ToolbarTextField { // Search box
        id: searchInput
        Layout.topMargin: 4
        Layout.bottomMargin: 4
        Layout.rightMargin: 0
        Layout.fillWidth: true
        implicitHeight: 40
        implicitWidth: root.clipboardMode ? root.clipboardWidth : ((root.searchingText === "" && !Config.options.search.alwaysListApps && !root.showSuggestionsPanel) ? Appearance.sizes.searchWidthCollapsed : Appearance.sizes.searchWidth)
        focus: GlobalStates.overviewOpen
        readOnly: root.activePanelOwnsInput
        font.pixelSize: Appearance.font.pixelSize.small
        placeholderText: root.aiModeActive ? Translation.tr("Message the model — Esc to go back")
            : (root.activePanelOwnsInput ? Translation.tr("Typing test") : Translation.tr("Search, calculate or run"))

        // Placeholder fades smoothly when text is entered or mode changes
        placeholderTextColor: (root.searchingText === "" && !root.clipboardMode)
            ? Appearance.colors.colSubtext
            : ColorUtils.transparentize(Appearance.colors.colSubtext)

        Behavior on placeholderTextColor {
            ColorAnimation {
                duration: Appearance.animation.elementMoveFast.duration + Math.round(100 * Appearance.animMultiplier)
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveEffects
            }
        }

        Behavior on implicitHeight {
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration + Math.round(100 * Appearance.animMultiplier)
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveEffects
            }
        }

        onTextChanged: {
            if (!root.syncingSearchText && !root.activePanelOwnsInput)
                LauncherSearch.query = text;
        }

        onAccepted: {
            if (root.activePanelOwnsInput)
                return;
            if (root.aiModeActive) {
                root.sendMessage();
                return;
            }
            if (root.activePanelMode) {
                root.activate();
                return;
            }
            if (root.clipboardMode) {
                root.activate();
                return;
            }
            if (appResults.count > 0) {
                // The delegate became a Loader when settings results joined the
                // list, so the row that answers to `clicked` is one level down.
                // Enter stopped opening anything and only the mouse worked.
                const delegate = appResults.itemAtIndex(appResults.currentIndex);
                const row = delegate?.item ?? delegate;
                if (row && typeof row.clicked === "function")
                    row.clicked();
            }
        }

        Keys.onPressed: event => {
            if (root.activePanelOwnsInput)
                return;
            if (event.key === Qt.Key_Backspace && root.activePanelMode && root.activePanelQueryEmpty) {
                root.backspaceOnEmpty();
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_Escape) {
                // A hosted panel is a child navigation level. Its first Esc
                // returns to plain Search; only plain Search closes Overview.
                if (root.aiModeActive || root.activePanelMode)
                    root.escapeToSearch();
                else
                    GlobalStates.overviewOpen = false;
                event.accepted = true;
                return;
            }
            if ((event.key === Qt.Key_Enter || event.key === Qt.Key_Return) && root.aiModeActive && (event.modifiers & Qt.ShiftModifier)) {
                searchInput.insert(searchInput.cursorPosition, "\n");
                event.accepted = true;
                return;
            }
            if (root.matchesShortcut(event, "actions", "Ctrl+K")) {
                root.ctrlKPressed();
                event.accepted = true;
                return;
            }
            if (root.matchesShortcut(event, "favorite", "Ctrl+P") && !root.activePanelMode) {
                root.toggleFavorite();
                event.accepted = true;
                return;
            }
            if (root.matchesShortcut(event, "secondary", "Ctrl+Enter") && root.activePanelMode) {
                root.openSelectedInCheatsheet();
                event.accepted = true;
                return;
            }
            if (root.matchesShortcut(event, "copy", "Ctrl+C") && root.activePanelMode) {
                root.copySelected();
                event.accepted = true;
                return;
            }
            if (root.activePanelMode && root.matchesShortcut(event, "save", "Ctrl+S")) {
                root.saveSelected();
                event.accepted = true;
                return;
            }
            if (root.activePanelMode && root.matchesShortcut(event, "edit", "Ctrl+E")) {
                root.editSelected();
                event.accepted = true;
                return;
            }
            if (root.activePanelMode && root.matchesShortcut(event, "ocr", "Ctrl+O")) {
                root.ocrSelected();
                event.accepted = true;
                return;
            }
            if (root.activePanelMode && root.matchesShortcut(event, "create", "Ctrl+N")) {
                root.createFromQuery();
                event.accepted = true;
                return;
            }
            if (root.activePanelMode && root.matchesShortcut(event, "copyDispatch", "Ctrl+Shift+K")) {
                root.copyDispatchSelected();
                event.accepted = true;
                return;
            }
            if (root.activePanelMode && root.matchesShortcut(event, "delete", "Shift+Delete")) {
                root.deleteSelected();
                event.accepted = true;
                return;
            }
            if (root.activePanelMode && root.matchesShortcut(event, "select", "Ctrl+Space")) {
                root.panelShortcut("toggleSelection");
                event.accepted = true;
                return;
            }
            if (root.activePanelMode && root.matchesShortcut(event, "cut", "Ctrl+X")) {
                root.panelShortcut("cutSelected");
                event.accepted = true;
                return;
            }
            if (root.activePanelMode && root.matchesShortcut(event, "paste", "Ctrl+V")) {
                root.panelShortcut("pasteClipboard");
                event.accepted = true;
                return;
            }
            if (root.activePanelMode && root.matchesShortcut(event, "createFolder", "Ctrl+Shift+N")) {
                root.panelShortcut("createFolder");
                event.accepted = true;
                return;
            }
            if (root.activePanelMode && root.matchesShortcut(event, "duplicate", "Ctrl+D")) {
                root.panelShortcut("duplicateSelected");
                event.accepted = true;
                return;
            }
            if (root.activePanelMode && root.matchesShortcut(event, "toggleHidden", "Ctrl+H")) {
                root.panelShortcut("toggleHidden");
                event.accepted = true;
                return;
            }
            if (root.activePanelMode && root.matchesShortcut(event, "refresh", "Ctrl+R")) {
                root.panelShortcut("refreshDirectory");
                event.accepted = true;
                return;
            }
            if (root.activePanelMode && root.matchesShortcut(event, "stageCopy", "Ctrl+Shift+C")) {
                root.panelShortcut("stageCopy");
                event.accepted = true;
                return;
            }
            if (root.activePanelMode && root.matchesShortcut(event, "sortFiles", "Ctrl+Shift+S")) {
                root.panelShortcut("cycleSort");
                event.accepted = true;
                return;
            }
            if (root.activePanelMode && root.matchesShortcut(event, "goHome", "Ctrl+Home")) {
                root.panelShortcut("goHome");
                event.accepted = true;
                return;
            }
            if (root.activePanelMode && root.matchesShortcut(event, "forward", "Alt+Right")) {
                root.panelShortcut("navigateForward");
                event.accepted = true;
                return;
            }
            if (!root.activePanelMode && root.showCategoryFilter
                    && (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab)) {
                root.cycleCategoryFilter(event.key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier) ? -1 : 1);
                event.accepted = true;
                return;
            }
            if (root.matchesShortcut(event, "section", "Tab") && root.activePanelMode && root.supportsPanelSectionToggle) {
                root.togglePanelSection();
                event.accepted = true;
                return;
            }
            // Alt+digit rather than a bare digit: the field keeps every plain
            // key for the query itself.
            if ((event.modifiers & Qt.AltModifier) && event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
                root.runSecondaryAction(event.key - Qt.Key_1);
                event.accepted = true;
                return;
            }
            // Before the plain Up/Down handlers: those compare against "up"
            // and "down", so a modified press would otherwise fall through to
            // them as an ordinary row move.
            if (root.matchesShortcut(event, "sectionPrevious", "Ctrl+Up")) {
                root.navigateSectionUp();
                event.accepted = true;
                return;
            }
            if (root.matchesShortcut(event, "sectionNext", "Ctrl+Down")) {
                root.navigateSectionDown();
                event.accepted = true;
                return;
            }
            if (root.matchesShortcut(event, "historyPrevious", "Up")) {
                // An idle field is only "nothing to arrow through" when the
                // results list agrees — idle Suggestions and Always List Apps
                // both populate it on an empty query, and Up/Down must move
                // the selection there the same way it does for a typed query.
                if (!root.activePanelMode && searchInput.text.length === 0 && appResults.count === 0) {
                    root.historyPrevious();
                    event.accepted = true;
                    return;
                }
                root.navigateUp();
                event.accepted = true;
                return;
            } else if (root.matchesShortcut(event, "historyNext", "Down")) {
                if (!root.activePanelMode && searchInput.text.length === 0 && appResults.count === 0) {
                    root.historyNext();
                    event.accepted = true;
                    return;
                }
                root.navigateDown();
                event.accepted = true;
                return;
            }
            // Grid/list panels (Settings, Keybinds, File Browser...) use bare
            // Left/Right to move between cells. clipboardMode panels are
            // excluded here — Translator, Media Downloader and Material
            // Symbols each have a real text field where Left/Right must move
            // the cursor instead, and the dedicated handling further below
            // already makes that distinction per-panel.
            if (root.activePanelMode && !root.clipboardMode && event.key === Qt.Key_Left) {
                root.navigateLeft();
                event.accepted = true;
                return;
            }
            if (root.activePanelMode && !root.clipboardMode && event.key === Qt.Key_Right) {
                root.navigateRight();
                event.accepted = true;
                return;
            }
            if (root.selectedResultSupportsHorizontalNavigation && event.key === Qt.Key_Left) {
                root.navigateLeft();
                event.accepted = true;
                return;
            }
            if (root.selectedResultSupportsHorizontalNavigation && event.key === Qt.Key_Right) {
                root.navigateRight();
                event.accepted = true;
                return;
            }
            // Emoji picker is grid-only — no text field where Left/Right ever
            // needs to move a cursor, unlike Material Symbols below.
            const isEmojiMode = root.searchPrefixType === SearchBar.SearchPrefixType.Emojis;
            if (isEmojiMode) {
                if (event.key === Qt.Key_Left) {
                    root.navigateLeft();
                    event.accepted = true;
                    return;
                } else if (event.key === Qt.Key_Right) {
                    root.navigateRight();
                    event.accepted = true;
                    return;
                }
            }
            if (root.clipboardMode) {
                if (event.key === Qt.Key_S && (event.modifiers & Qt.ControlModifier)) {
                    root.copySvgPressed();
                    event.accepted = true;
                    return;
                }
                const isPanelFocused = root.isTranslatorPanelFocused || root.isMediaDownloaderPanelFocused || root.isMaterialSymbolsPanelFocused;
                // `searchPrefixType` reflects whether the raw text currently
                // starts with the literal prefix string — true only for the
                // instant before the hosted panel consumes it, not "is this
                // panel active". Once inside Translator/Media
                // Downloader/Material Symbols the "@"/etc. is long gone from
                // the text, so this must check the panel's own id (stable for
                // as long as the panel is open) instead — otherwise Left/Right
                // only ever reaches the text field right after retyping the
                // prefix character.
                const activePanelId = String(root.activePanel?.id ?? "");
                const isTextFieldPanel = activePanelId === "translator" || activePanelId === "mediaDownloader" || activePanelId === "materialSymbols";
                if (!isTextFieldPanel || isPanelFocused) {
                    if (event.key === Qt.Key_Left) {
                        root.navigateLeft();
                        event.accepted = true;
                        return;
                    } else if (event.key === Qt.Key_Right) {
                        root.navigateRight();
                        event.accepted = true;
                        return;
                    }
                }

                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    root.activate();
                    event.accepted = true;
                    return;
                } else if (event.key === Qt.Key_Delete && (event.modifiers & Qt.ShiftModifier)) {
                    root.deleteSelected();
                    event.accepted = true;
                    return;
                }
            }
            if (event.key === Qt.Key_Tab) {
                if (!root.selectedResultRef)
                    return;

                const activeResult = root.selectedResultRef;
                if (!activeResult)
                    return;
                const prefix = Config.options.search.prefix.fileBrowser;

                let newText = "";
                if (activeResult.key && activeResult.key.startsWith("alias:") && (activeResult.type === Translation.tr("Folder Alias") || activeResult.verb === Translation.tr("Browse"))) {
                    const target = activeResult.comment || "";
                    newText = root.fileBrowserTextForPath(target);
                } else if (searchInput.text.startsWith(prefix)) {
                    const currentPath = searchInput.text.slice(prefix.length);
                    const lastName = currentPath.lastIndexOf("/");
                    const dirBase = lastName >= 0 ? currentPath.slice(0, lastName + 1) : "";
                    const name = activeResult.name;
                    const suffix = (activeResult.type === Translation.tr("Directory") && !name.endsWith("/")) ? "/" : "";
                    newText = prefix + dirBase + name + suffix;
                } else {
                    newText = activeResult.name;
                }

                if (newText !== "") {
                    LauncherSearch.query = newText;
                    searchInput.text = newText;
                }
                event.accepted = true;
            }
        }
    }

    RippleButton {
        id: categoryFilterChip
        visible: root.showCategoryFilter
        Layout.alignment: Qt.AlignVCenter
        implicitWidth: categoryFilterContent.implicitWidth + Appearance.sizes.elevationMargin * 2
        implicitHeight: searchInput.implicitHeight
        buttonRadius: Appearance.rounding.full
        colBackground: Appearance.colors.colSecondaryContainer
        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
        colRipple: Appearance.colors.colSecondaryContainerActive
        onClicked: root.cycleCategoryFilter(1)

        contentItem: RowLayout {
            id: categoryFilterContent
            anchors.centerIn: parent
            spacing: Appearance.sizes.elevationMargin / 2

            MaterialSymbol {
                text: root.categoryFilterIcon
                iconSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colOnSecondaryContainer
            }

            StyledText {
                text: root.categoryFilterLabel
                color: Appearance.colors.colOnSecondaryContainer
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.Medium
            }

            KeyHint {
                visible: Config.options.search.appearance.showKeyHints
                keys: ["Tab"]
                surface: Appearance.colors.colSecondaryContainer
                onSurface: Appearance.colors.colOnSecondaryContainer
            }
        }

        StyledToolTip {
            text: Translation.tr("Filter result category · Tab")
        }
    }


}
