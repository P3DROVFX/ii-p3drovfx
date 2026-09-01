import QtQuick
import Quickshell

QtObject {
    enum IconType { Material, Text, System, Image, None }
    enum FontType { Normal, Monospace }

    // General stuff
    property string key: ""  // Stable identity key for ScriptModel tracking
    property string type: ""
    property var fontType: LauncherSearchResult.FontType.Normal
    property string name: ""
    property string rawValue: ""
    property string iconName: ""
    property var iconType: LauncherSearchResult.IconType.None
    property string verb: ""
    property bool blurImage: false
    property bool pinned: false
    property var execute: () => {
        print("Not implemented");
    }
    property var actions: []
    
    // Stuff needed for DesktopEntry 
    property string id: ""
    property bool shown: true
    property string comment: ""
    property bool runInTerminal: false
    property string genericName: ""
    property list<string> keywords: []
    property bool isMath: false
    property bool isBuiltin: false
    // Explicit alias intent is independent of the result's target kind. The
    // organizer uses this stable flag instead of translated labels or key
    // prefixes so app, folder, command and panel aliases share one section.
    property bool isAlias: false
    property bool isFallback: false
    property bool keepOverviewOpen: false
    property var settingRef: null
    property string controlKind: ""
    property var controlValue: null
    property string panelId: ""
    property bool pinnable: true
    property list<string> matchTerms: []
    property list<string> keyHints: []
    property string feedbackText: ""
    // Absolute path behind a result whose `name` is only the display label, so
    // a preview or a file action does not have to reconstruct it.
    property string filePath: ""
    // Symbol to draw when `iconType` is Image and the image cannot be loaded.
    // A thumbnail that fails is still a row that needs an icon.
    property string fallbackIconName: ""
    // Browser result origin. Kept separate from the translated `type` so the
    // Search organizer can group results without comparing localized labels.
    property string siteSource: ""

    // Media result fields
    property string trackTitle: ""
    property string trackArtist: ""
    property string trackAlbum: ""
    property string trackArtUrl: ""
    property bool isPlaying: false
    property string playerIdentity: ""
    property bool canGoPrevious: false
    property bool canGoNext: false
    property bool canTogglePlaying: false

    // Extra stuff to allow for more flexibility
    property string category: type
}
