pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.services

// Lyrics state machine shared by the classic and Immersive frontends: synced,
// plain, searching, instrumental and not-found presentations over one surface.
Item {
    id: root
    required property var context
    property color activeColor: context.dynamicAccentColor
    property color onAccentContainerColor: context.dynamicOnAccentContainer
    property color textColor: Appearance.colors.colOnLayer0
    property color subtextColor: Appearance.colors.colSubtext
    property color surfaceColor: Appearance.colors.colLayer2
    property color surfaceHoverColor: Appearance.colors.colLayer2Hover
    property color surfaceActiveColor: Appearance.colors.colLayer2Active
    property color onSurfaceColor: Appearance.colors.colOnLayer2
    property real fontScale: 1

    readonly property bool providerAllowsSynced: Config.options.lyricsService.lyricsProvider === "auto"
                                                 || Config.options.lyricsService.lyricsProvider === "lrclib"
    readonly property bool hasSyncedLines: LyricsService.syncedLines.length > 0 && !context.forcePlainLyrics
                                           && (LyricsService.usingLocalLyrics || providerAllowsSynced)
    readonly property bool geniusEnabled: Config.options.lyricsService.enableGenius
    readonly property bool lrclibEnabled: Config.options.lyricsService.enableLrclib
    readonly property bool ytmusicEnabled: Config.options.lyricsService.enableYtmusic
    readonly property bool anyProviderEnabled: geniusEnabled || lrclibEnabled || ytmusicEnabled

    // Four mutually exclusive "no scrolling lyrics" answers, only the
    // last of which is actually a failure.
    readonly property bool hasPlainLyrics: !hasSyncedLines && LyricsService.hasPlainLyrics
    readonly property bool instrumental: !hasSyncedLines && !hasPlainLyrics && LyricsService.instrumental
    readonly property bool searching: !hasSyncedLines && !hasPlainLyrics && !instrumental
                                      && (LyricsService.localLyricsLoading || (anyProviderEnabled
                                                                               && LyricsService.searching))
    readonly property bool notFound: !hasSyncedLines && !hasPlainLyrics && !instrumental && !searching

    readonly property string statusLabel: {
        if (hasSyncedLines)
            return LyricsService.usingCustomLyrics ? Translation.tr("Custom LRC") : (LyricsService.usingLocalLyrics
                                                                                     ? Translation.tr("Local LRC")
                                                                                     : Translation.tr(
                                                                                         "Synced LRC"));
        if (LyricsService.usingLocalLyrics)
            return Translation.tr("Local text");
        if (LyricsService.plainLyrics && LyricsService.plainLyrics.trim().length > 0) {
            const p = Config.options.lyricsService.lyricsProvider;
            if (p === "ytmusic")
                return Translation.tr("YouTube Music");
            if (p === "genius")
                return Translation.tr("Genius");
            if (p === "lrclib")
                return Translation.tr("LRCLib Plain");
            return Translation.tr("Plain Text");
        }
        if (instrumental)
            return Translation.tr("Instrumental");
        if (searching)
            return Translation.tr("Searching...");
        return Translation.tr("No lyrics");
    }

    Component.onCompleted: {
        // Local sidecars use the same parser and state surface as
        // online lyrics, even if every remote provider is disabled.
        if (context.localSource || geniusEnabled || lrclibEnabled || ytmusicEnabled)
            LyricsService.initiliazeLyrics();
    }

    FadeLoader {
        shown: root.hasPlainLyrics
        anchors.fill: parent
        sourceComponent: LyricsFlickable {
            anchors.fill: parent
            player: root.context.player
            textColor: root.textColor
            fontPixelSize: Appearance.font.pixelSize.hugeass * 1.2 * root.context.lyricsScaleMultiplier
                           * root.fontScale
        }
    }

    FadeLoader {
        shown: root.searching
        anchors.fill: parent
        sourceComponent: MediaModeLyricsSkeleton {
            anchors.fill: parent
            largeFontSize: Appearance.font.pixelSize.hugeass * 1.3 * root.context.lyricsScaleMultiplier
                           * root.fontScale
            activeColor: root.activeColor
            textColor: root.textColor
            dimTextColor: root.subtextColor
        }
    }

    FadeLoader {
        shown: root.instrumental || root.notFound
        anchors.fill: parent
        sourceComponent: MediaModeLyricsFallback {
            anchors.fill: parent
            mode: root.instrumental ? "instrumental" : "notFound"
            largeFontSize: Appearance.font.pixelSize.hugeass * 1.3 * root.context.lyricsScaleMultiplier
                           * root.fontScale
            activeColor: root.activeColor
            onAccentContainerColor: root.onAccentContainerColor
            textColor: root.textColor
            subtextColor: root.subtextColor
            surfaceColor: root.surfaceColor
            surfaceHoverColor: root.surfaceHoverColor
            surfaceActiveColor: root.surfaceActiveColor
            onSurfaceColor: root.onSurfaceColor
            artFilePath: root.context.displayedArtFilePath
            player: root.context.player
            visualizerPoints: root.context.visualizerPoints
            playing: root.context.player?.isPlaying ?? false
        }
    }

    FadeLoader {
        shown: root.hasSyncedLines
        anchors.fill: parent
        sourceComponent: MediaModeLyrics {
            anchors.fill: parent
            player: root.context.player
            // Resting size; the centred line renders at
            // focusedFontSizeMultiplier times this.
            largeFontSize: Appearance.font.pixelSize.hugeass * 1.3 * root.context.lyricsScaleMultiplier
                           * root.fontScale
            activeColor: root.activeColor
            textColor: root.textColor
            dimTextColor: root.subtextColor
        }
    }
}
