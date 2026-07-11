import QtQuick
import qs
import qs.services
import qs.modules.common

// Pure computed state for one monitor's bar.
// Instantiated by BarContent, which provides screen + hasActiveWindows.
// No Connections here — BarContent owns the HyprlandData watcher.
//
// Rule: all multi-line property bindings use JS blocks ({ return ...; })
// to prevent QML parser from misreading singletons (Config/GlobalStates)
// at line-start as QML child elements.
QtObject {
    id: root

    // ── Inputs ────────────────────────────────────────────────────────────────
    required property var  screen
    required property bool hasActiveWindows

    // ── Background ────────────────────────────────────────────────────────────
    readonly property bool showBarBackground: {
        return (root.hasActiveWindows && Config.options.bar.barBackgroundStyle === 2)
            || Config.options.bar.barBackgroundStyle === 1
            || Config.options.bar.barBackgroundStyle === 3;
    }

    // ── Bar style ─────────────────────────────────────────────────────────────
    readonly property bool isDynamicIsland: Config.options.bar.cornerStyle === 3

    // ── Search ────────────────────────────────────────────────────────────────
    readonly property bool isSearchActiveHere: {
        return GlobalStates.overviewOpen
            && (root.screen ? GlobalStates.activeSearchMonitor === root.screen.name : false);
    }

    readonly property bool isSearchClipboardMode:
        LauncherSearch.query.startsWith(Config.options.search.prefix.clipboard)
    readonly property bool isSearchBluetoothMode:
        LauncherSearch.query.startsWith(Config.options.search.prefix.bluetooth)
    readonly property bool isSearchTranslatorMode:
        LauncherSearch.query.startsWith(Config.options.search.prefix.translator)
    readonly property bool isSearchMediaDownloaderMode: {
        return Config.options.mediaDownloader.enabled
            && LauncherSearch.query.startsWith(Config.options.search.prefix.mediaDownloader);
    }
    readonly property bool isSearchSpecialMode: {
        return root.isSearchClipboardMode || root.isSearchBluetoothMode
            || root.isSearchTranslatorMode || root.isSearchMediaDownloaderMode;
    }

    readonly property real expectedSearchWidth: {
        return root.isSearchSpecialMode
            ? (Config.options.search.clipboard.panelWidth ?? 860) + 48
            : Config.options.search.baseWidth + 48;
    }

    // ── Frame ─────────────────────────────────────────────────────────────────
    readonly property real frameThickness: {
        return (Config.options.appearance.fakeScreenRounding === 3 && Config.options.bar.cornerStyle !== 3)
            ? Config.options.appearance.wrappedFrameThickness
            : 0;
    }
}
