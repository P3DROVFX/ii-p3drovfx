pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

RowLayout {
    id: root
    spacing: 6
    property bool animateWidth: false
    property bool clipboardMode: false
    property int clipboardWidth: 860
    property alias searchInput: searchInput
    property string searchingText
    property int currentResultIndex: 0

    signal navigateUp()
    signal navigateDown()
    signal navigateLeft()
    signal navigateRight()
    signal activate()
    signal deleteSelected()
    signal ctrlKPressed()

    function forceFocus() {
        searchInput.forceActiveFocus();
    }

    enum SearchPrefixType { Action, App, Clipboard, Emojis, Math, ShellCommand, WebSearch, WindowSearch, FileBrowser, DefaultSearch }

    property var searchPrefixType: {
        if (root.searchingText.startsWith(Config.options.search.prefix.action)) return SearchBar.SearchPrefixType.Action;
        if (root.searchingText.startsWith(Config.options.search.prefix.app) || (Config.options.search.alwaysListApps && root.searchingText === "")) return SearchBar.SearchPrefixType.App;
        if (root.searchingText.startsWith(Config.options.search.prefix.clipboard)) return SearchBar.SearchPrefixType.Clipboard;
        if (root.searchingText.startsWith(Config.options.search.prefix.emojis)) return SearchBar.SearchPrefixType.Emojis;
        if (root.searchingText.startsWith(Config.options.search.prefix.math)) return SearchBar.SearchPrefixType.Math;
        if (root.searchingText.startsWith(Config.options.search.prefix.shellCommand)) return SearchBar.SearchPrefixType.ShellCommand;
        if (root.searchingText.startsWith(Config.options.search.prefix.webSearch)) return SearchBar.SearchPrefixType.WebSearch;
        if (root.searchingText.startsWith(Config.options.search.prefix.windowSearch)) return SearchBar.SearchPrefixType.WindowSearch;
        if (root.searchingText.startsWith(Config.options.search.prefix.fileBrowser)) return SearchBar.SearchPrefixType.FileBrowser;
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
        }

        shape: switch(searchIcon._prefixType) {
            case SearchBar.SearchPrefixType.Action: return MaterialShape.Shape.Pill;
            case SearchBar.SearchPrefixType.App: return MaterialShape.Shape.Clover4Leaf;
            case SearchBar.SearchPrefixType.Clipboard: return MaterialShape.Shape.Gem;
            case SearchBar.SearchPrefixType.Emojis: return MaterialShape.Shape.Sunny;
            case SearchBar.SearchPrefixType.Math: return MaterialShape.Shape.PuffyDiamond;
            case SearchBar.SearchPrefixType.ShellCommand: return MaterialShape.Shape.PixelCircle;
            case SearchBar.SearchPrefixType.WebSearch: return MaterialShape.Shape.SoftBurst;
            case SearchBar.SearchPrefixType.WindowSearch: return MaterialShape.Shape.Arch;
            case SearchBar.SearchPrefixType.FileBrowser: return MaterialShape.Shape.Square;
            default: return MaterialShape.Shape.Cookie7Sided;
        }
        text: switch (searchIcon._prefixType) {
            case SearchBar.SearchPrefixType.Action: return "settings_suggest";
            case SearchBar.SearchPrefixType.App: return "apps";
            case SearchBar.SearchPrefixType.Clipboard: return "content_paste_search";
            case SearchBar.SearchPrefixType.Emojis: return "add_reaction";
            case SearchBar.SearchPrefixType.Math: return "calculate";
            case SearchBar.SearchPrefixType.ShellCommand: return "terminal";
            case SearchBar.SearchPrefixType.WebSearch: return "travel_explore";
            case SearchBar.SearchPrefixType.WindowSearch: return "select_window";
            case SearchBar.SearchPrefixType.FileBrowser: return "folder_open";
            case SearchBar.SearchPrefixType.DefaultSearch: return "search";
            default: return "search";
        }
    }
    ToolbarTextField { // Search box
        id: searchInput
        Layout.topMargin: 4
        Layout.bottomMargin: 4
        Layout.fillWidth: root.clipboardMode
        implicitHeight: 40
        focus: GlobalStates.overviewOpen
        font.pixelSize: Appearance.font.pixelSize.small
        placeholderText: Translation.tr("Search, calculate or run")
        implicitWidth: root.clipboardMode
            ? root.clipboardWidth
            : ((root.searchingText === "" && !Config.options.search.alwaysListApps) ? Appearance.sizes.searchWidthCollapsed : Appearance.sizes.searchWidth)

        Behavior on implicitWidth {
            id: searchWidthBehavior
            enabled: !root.clipboardMode
            NumberAnimation {
                duration: 350
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
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
                if (event.key === Qt.Key_Left) {
                    root.navigateLeft();
                    event.accepted = true;
                    return;
                } else if (event.key === Qt.Key_Right) {
                    root.navigateRight();
                    event.accepted = true;
                    return;
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    root.activate();
                    event.accepted = true;
                    return;
                } else if (event.key === Qt.Key_Delete && (event.modifiers & Qt.ShiftModifier)) {
                    root.deleteSelected();
                    event.accepted = true;
                    return;
                }
            }
             if (event.key === Qt.Key_Tab || (event.key === Qt.Key_Right && searchInput.cursorPosition === searchInput.text.length)) {
                if (LauncherSearch.results.length === 0) return;
                
                // Get the result at the active keyboard-navigated index
                const activeIndex = (root.currentResultIndex >= 0 && root.currentResultIndex < LauncherSearch.results.length) 
                    ? root.currentResultIndex 
                    : 0;
                const activeResult = LauncherSearch.results[activeIndex];
                if (!activeResult) return;
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

    IconToolbarButton {
        Layout.topMargin: 4
        Layout.bottomMargin: 4
        onClicked: {
            GlobalStates.overviewOpen = false;
            const overviewAnimationEnabled = Config.options.overview.showOpeningAnimation

            if (!overviewAnimationEnabled) {
                Quickshell.execDetached(["qs", "-p", Quickshell.shellPath(""), "ipc", "call", "region", "search"]);
                return
            }
            lensDelayTimer.start();
        }
        text: "image_search"
        StyledToolTip {
            text: Translation.tr("Google Lens")
            y: parent.height + 3
        }
    }

    Timer {
        id: lensDelayTimer
        interval: 201
        onTriggered: {
            Quickshell.execDetached(["qs", "-p", Quickshell.shellPath(""), "ipc", "call", "region", "search"]);
        }
    }

    IconToolbarButton {
        id: songRecButton
        Layout.topMargin: 4
        Layout.bottomMargin: 4
        Layout.rightMargin: 4
        toggled: SongRec.running
        onClicked: SongRec.toggleRunning()
        text: "music_cast"

        StyledToolTip {
            text: Translation.tr("Recognize music")
            y: parent.height + 3
        }

        colText: toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurfaceVariant
        background: MaterialShape {
            RotationAnimation on rotation {
                running: songRecButton.toggled
                duration: 12000
                easing.type: Easing.Linear
                loops: Animation.Infinite
                from: 0
                to: 360
            }
            shape: {
                if (songRecButton.down) {
                    return songRecButton.toggled ? MaterialShape.Shape.Circle : MaterialShape.Shape.Square
                } else {
                    return songRecButton.toggled ? MaterialShape.Shape.SoftBurst : MaterialShape.Shape.Circle
                }
            }
            color: {
                if (songRecButton.toggled) {
                    return songRecButton.hovered ? Appearance.colors.colPrimaryHover : Appearance.colors.colPrimary
                } else {
                    return songRecButton.hovered ? Appearance.colors.colSurfaceContainerHigh : ColorUtils.transparentize(Appearance.colors.colSurfaceContainerHigh)
                }
            }
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }
    }
}
