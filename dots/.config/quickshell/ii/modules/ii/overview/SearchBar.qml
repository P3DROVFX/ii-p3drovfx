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

RowLayout {
    id: root
    spacing: 6
    property bool animateWidth: false
    property bool clipboardMode: false
    property int clipboardWidth: 860
    property alias searchInput: searchInput
    property string searchingText
    property int currentResultIndex: 0
    property bool isTranslatorPanelFocused: false
    property bool isMediaDownloaderPanelFocused: false
    property bool isMaterialSymbolsPanelFocused: false

    BarThemes {
        id: barThemes
    }
    property var activeTheme: barThemes.getTheme(Config.options.bar.expressiveColorTheme)

    onSearchingTextChanged: {
        if (searchInput.text !== searchingText) {
            searchInput.text = searchingText;
        }
    }

    signal navigateUp
    signal navigateDown
    signal navigateLeft
    signal navigateRight
    signal activate
    signal deleteSelected
    signal ctrlKPressed
    signal copySvgPressed

    function forceFocus() {
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
        FileBrowser,
        Translator,
        MediaDownloader,
        MaterialSymbols,
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
        if (root.searchingText.startsWith(Config.options.search.prefix.fileBrowser))
            return SearchBar.SearchPrefixType.FileBrowser;
        if (root.searchingText.startsWith(Config.options.search.prefix.translator))
            return SearchBar.SearchPrefixType.Translator;
        if (Config.options.mediaDownloader.enabled && root.searchingText.startsWith(Config.options.search.prefix.mediaDownloader))
            return SearchBar.SearchPrefixType.MediaDownloader;
        if (root.searchingText.startsWith(Config.options.search.prefix.materialSymbols))
            return SearchBar.SearchPrefixType.MaterialSymbols;
        return SearchBar.SearchPrefixType.DefaultSearch;
    }

    MaterialShapeWrappedMaterialSymbol {
        id: searchIcon
        Layout.alignment: Qt.AlignVCenter
        iconSize: Appearance.font.pixelSize.huge
        opacity: 1.0
        scale: 1.0

        property int _prefixType: root.searchPrefixType
        property int _lastPrefixType: root.searchPrefixType
        property string _lastText: ""
        property bool _initialized: false

        readonly property real symmetryAngle: {
            switch (searchIcon._prefixType) {
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
            case SearchBar.SearchPrefixType.FileBrowser:
                return 90;    // Square
            case SearchBar.SearchPrefixType.Translator:
                return 60;     // Cookie6Sided
            case SearchBar.SearchPrefixType.MediaDownloader:
                return 40;     // Cookie9Sided
            case SearchBar.SearchPrefixType.MaterialSymbols:
                return 45;     // SoftBurst
            default:
                return 360 / 7;                                   // Cookie7Sided
            }
        }

        Behavior on rotation {
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Easing.OutBack
            }
        }

        function triggerTransition() {
            iconFadeOut.stop();
            iconFadeIn.stop();
            iconFadeOut.start();
        }

        SequentialAnimation {
            id: iconFadeOut
            ParallelAnimation {
                NumberAnimation {
                    target: searchIcon
                    property: "opacity"
                    to: 0
                    duration: Appearance.animation.elementMoveFast.duration / 2
                    easing.type: Easing.InQuad
                }
                NumberAnimation {
                    target: searchIcon
                    property: "scale"
                    to: 0.7
                    duration: Appearance.animation.elementMoveFast.duration / 2
                    easing.type: Easing.InQuad
                }
            }
            ScriptAction {
                script: {
                    searchIcon._prefixType = root.searchPrefixType;
                    searchIcon.rotation = 0; // Reset rotation so new shape starts correctly oriented
                    iconFadeIn.start();
                }
            }
        }

        SequentialAnimation {
            id: iconFadeIn
            ParallelAnimation {
                NumberAnimation {
                    target: searchIcon
                    property: "opacity"
                    to: 1.0
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Easing.OutQuad
                }
                NumberAnimation {
                    target: searchIcon
                    property: "scale"
                    to: 1.0
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Easing.OutQuad
                }
            }
        }

        Connections {
            target: root
            function onSearchPrefixTypeChanged() {
                if (root.searchPrefixType !== searchIcon._prefixType) {
                    searchIcon.triggerTransition();
                }
            }
            function onSearchingTextChanged() {
                if (!searchIcon._initialized) {
                    searchIcon._initialized = true;
                    searchIcon._lastText = root.searchingText;
                    searchIcon.rotation = 0;
                    return;
                }

                if (root.searchingText === "") {
                    searchIcon.rotation = 0;
                } else if (root.searchingText !== searchIcon._lastText) {
                    searchIcon.rotation += searchIcon.symmetryAngle;
                }
                searchIcon._lastText = root.searchingText;
            }
        }

        shape: switch (searchIcon._prefixType) {
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
        case SearchBar.SearchPrefixType.FileBrowser:
            return MaterialShape.Shape.Square;
        case SearchBar.SearchPrefixType.Translator:
            return MaterialShape.Shape.Cookie6Sided;
        case SearchBar.SearchPrefixType.MediaDownloader:
            return MaterialShape.Shape.Cookie9Sided;
        case SearchBar.SearchPrefixType.MaterialSymbols:
            return MaterialShape.Shape.SoftBurst;
        default:
            return MaterialShape.Shape.Cookie7Sided;
        }
        text: switch (searchIcon._prefixType) {
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
        case SearchBar.SearchPrefixType.FileBrowser:
            return "folder_open";
        case SearchBar.SearchPrefixType.Translator:
            return "translate";
        case SearchBar.SearchPrefixType.MediaDownloader:
            return "download";
        case SearchBar.SearchPrefixType.MaterialSymbols:
            return "font_download";
        case SearchBar.SearchPrefixType.DefaultSearch:
            return "search";
        default:
            return "search";
        }
    }
    ToolbarTextField { // Search box
        id: searchInput
        Layout.topMargin: 4
        Layout.bottomMargin: 4
        Layout.rightMargin: 0
        Layout.fillWidth: true
        implicitHeight: 40
        implicitWidth: root.clipboardMode ? root.clipboardWidth : ((root.searchingText === "" && !Config.options.search.alwaysListApps) ? Appearance.sizes.searchWidthCollapsed : Appearance.sizes.searchWidth)
        focus: GlobalStates.overviewOpen
        font.pixelSize: Appearance.font.pixelSize.small
        placeholderText: Translation.tr("Search, calculate or run")

        // Placeholder fades smoothly when text is entered or mode changes
        placeholderTextColor: (root.searchingText === "" && !root.clipboardMode) ? Appearance.colors.colSubtext : Qt.rgba(Appearance.colors.colSubtext.r, Appearance.colors.colSubtext.g, Appearance.colors.colSubtext.b, 0)

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

        onTextChanged: LauncherSearch.query = text

        onAccepted: {
            if (root.clipboardMode) {
                root.activate();
                return;
            }
            if (appResults.count > 0) {
                let currentItem = appResults.itemAtIndex(appResults.currentIndex);
                if (currentItem && currentItem.clicked) {
                    currentItem.clicked();
                }
            }
        }

        Keys.onPressed: event => {
            if (event.key === Qt.Key_K && (event.modifiers & Qt.ControlModifier)) {
                root.ctrlKPressed();
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_Up) {
                root.navigateUp();
                event.accepted = true;
                return;
            } else if (event.key === Qt.Key_Down) {
                root.navigateDown();
                event.accepted = true;
                return;
            }
                if (root.clipboardMode) {
                    if (event.key === Qt.Key_S && (event.modifiers & Qt.ControlModifier)) {
                        root.copySvgPressed();
                        event.accepted = true;
                        return;
                    }
                    const isPanelFocused = root.isTranslatorPanelFocused || root.isMediaDownloaderPanelFocused || root.isMaterialSymbolsPanelFocused;
                    if ((root.searchPrefixType !== SearchBar.SearchPrefixType.Translator && root.searchPrefixType !== SearchBar.SearchPrefixType.MediaDownloader && root.searchPrefixType !== SearchBar.SearchPrefixType.MaterialSymbols) || isPanelFocused) {
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
                if (LauncherSearch.results.length === 0)
                    return;

                // Get the result at the active keyboard-navigated index
                const activeIndex = (root.currentResultIndex >= 0 && root.currentResultIndex < LauncherSearch.results.length) ? root.currentResultIndex : 0;
                const activeResult = LauncherSearch.results[activeIndex];
                if (!activeResult)
                    return;
                const prefix = Config.options.search.prefix.fileBrowser;

                let newText = "";
                if (activeResult.key && activeResult.key.startsWith("alias:") && (activeResult.type === Translation.tr("Folder Alias") || activeResult.verb === Translation.tr("Browse"))) {
                    const target = activeResult.comment || "";
                    newText = prefix + target + (target.endsWith("/") ? "" : "/");
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


}
