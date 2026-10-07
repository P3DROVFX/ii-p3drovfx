import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.models

/*
 * What the Poster, Deck and Halo media widgets share: the active player, its
 * cover (downloaded once into Directories.coverArt), the colour roles and the
 * gate that keeps the wave and the position clock still while windows cover
 * the desktop.
 *
 * Colours are WidgetColorScheme roles; `dynamicColors` swaps them for a scheme
 * adapted from the cover, the same pipeline as the other media widgets.
 */
Item {
    id: root

    property bool dynamicColors: false
    // The host's own visibility; nothing ticks for a widget nobody sees.
    property bool active: true
    // Previews (Settings) sit in a window of their own: windows on the desktop
    // say nothing about whether they are seen.
    property bool ignoreWindows: false

    readonly property MprisPlayer player: MprisController.activePlayer
    readonly property bool hasPlayer: root.player !== null
    readonly property bool isPlaying: root.player?.isPlaying ?? false
    readonly property string title: root.hasPlayer
        ? (StringUtils.cleanMusicTitle(root.player.trackTitle) || Translation.tr("Unknown title"))
        : Translation.tr("Nothing playing")
    readonly property string artist: root.hasPlayer ? (root.player.trackArtist || Translation.tr("Unknown artist"))
                                                     : Translation.tr("Play something to see it here")
    readonly property string playerName: root.player?.identity ?? ""

    // ── Position ──
    readonly property real length: MprisController.trackLengthOf(root.player)
    readonly property bool hasLength: MprisController.hasTrackLength(root.player)
    readonly property real position: MprisController.trackPositionOf(root.player)
    readonly property real progress: MprisController.trackProgressOf(root.player)
    readonly property string positionText: StringUtils.friendlyTimeForSeconds(root.position)
    readonly property string lengthText: root.hasLength ? StringUtils.friendlyTimeForSeconds(root.length) : "–:––"

    // Desktop-widget CPU contract (AndroidMediaWidget, ExpressiveMediaWidget):
    // motion runs only while nothing covers the widget, or while the media UI
    // is open in front of the user.
    readonly property bool hasActiveWindows: {
        const monName = Hyprland.focusedMonitor?.name ?? "";
        var activeWsId = 0;
        if (GlobalStates.screenLocked && GlobalStates.lockSavedWorkspaces?.[monName])
            activeWsId = GlobalStates.lockSavedWorkspaces[monName];
        else if (GlobalStates.editMode && GlobalStates.editModeMonitor === monName && GlobalStates._editSavedWorkspace > 0)
            activeWsId = GlobalStates._editSavedWorkspace;
        else {
            activeWsId = Hyprland.focusedMonitor?.activeWorkspace?.id ?? (HyprlandData.activeWorkspace ? HyprlandData.activeWorkspace.id : 1);
            if (activeWsId > 1000000)
                activeWsId = 2147483647 - activeWsId;
        }
        if (!HyprlandData || !HyprlandData.windowList)
            return false;
        return HyprlandData.windowList.some(w => w.workspace && w.workspace.id === activeWsId);
    }
    readonly property bool onScreen: root.active && (root.ignoreWindows || !root.hasActiveWindows || GlobalStates.mediaControlsOpen)
    readonly property bool animate: root.isPlaying && root.onScreen

    Timer {
        running: root.animate
        interval: 1000
        repeat: true
        onTriggered: root.player?.positionChanged()
    }

    function togglePlaying() { root.player?.togglePlaying(); }
    function previous() { MprisController.previous(); }
    function next() { MprisController.next(); }
    function seek(fraction) { MprisController.seekFraction(root.player, fraction); }

    // ── Cover ──
    readonly property string artUrl: root.hasPlayer ? MprisController.artUrl : ""
    readonly property bool isLocalArt: root.artUrl.startsWith("file://") || root.artUrl.startsWith("/")
    readonly property string artFilePath: `${Directories.coverArt}/${Qt.md5(root.artUrl)}`
    property bool artDownloaded: false
    readonly property string artSource: {
        if (root.artUrl === "")
            return "";
        if (root.isLocalArt)
            return root.artUrl;
        return root.artDownloaded ? Qt.resolvedUrl(root.artFilePath) : "";
    }

    function refreshArt() {
        if (root.artUrl === "" || root.isLocalArt) {
            root.artDownloaded = root.isLocalArt;
            return;
        }
        root.artDownloaded = false;
        artDownloader.targetUrl = root.artUrl;
        artDownloader.targetPath = root.artFilePath;
        artDownloader.running = true;
    }
    onArtFilePathChanged: root.refreshArt()
    Component.onCompleted: root.refreshArt()

    Process {
        id: artDownloader
        property string targetUrl
        property string targetPath
        command: ["bash", "-c", `[ -f '${targetPath}' ] || (curl -4 -sSL '${targetUrl}' -o '${targetPath}.tmp' && mv '${targetPath}.tmp' '${targetPath}')`]
        onExited: exitCode => {
            if (artDownloader.targetPath === root.artFilePath)
                root.artDownloaded = exitCode === 0;
        }
    }

    // ── Colours ──
    readonly property bool useAlbumColors: root.dynamicColors && root.artSource !== ""

    ColorQuantizer {
        id: colorQuantizer
        source: root.useAlbumColors ? root.artSource : ""
        depth: 0
        rescaleSize: 1
    }

    readonly property color artDominantColor: {
        if (!root.useAlbumColors)
            return Appearance.colors.colPrimary;
        const raw = colorQuantizer?.colors[0] ?? Appearance.colors.colPrimary;
        return ColorUtils.mix(raw, Appearance.colors.colPrimaryContainer, 0.8) || Appearance.m3colors.m3secondaryContainer;
    }

    property QtObject albumScheme: AdaptedMaterialScheme {
        color: root.artDominantColor
    }

    readonly property color colCard: root.useAlbumColors ? root.albumScheme.colPrimaryContainer : WidgetColorScheme.cardBgColor
    readonly property color colText: root.useAlbumColors ? root.albumScheme.colOnPrimaryContainer : WidgetColorScheme.textColorOnBg
    readonly property color colSubtext: root.useAlbumColors ? ColorUtils.transparentize(root.albumScheme.colOnPrimaryContainer, 0.4) : WidgetColorScheme.subtextColorOnBg
    readonly property color colAccent: root.useAlbumColors ? root.albumScheme.colPrimary : WidgetColorScheme.accentColor
    readonly property color colOnAccent: root.useAlbumColors ? root.albumScheme.colOnPrimary : WidgetColorScheme.onAccentColor
    readonly property color colTonal: root.useAlbumColors ? root.albumScheme.colSecondaryContainer : WidgetColorScheme.pillFillColor
    readonly property color colOnTonal: root.useAlbumColors ? root.albumScheme.colOnSecondaryContainer : WidgetColorScheme.textColorOnPillFill
    readonly property color colTrack: root.useAlbumColors ? ColorUtils.transparentize(root.albumScheme.colOnPrimaryContainer, 0.75) : WidgetColorScheme.pillBgColor
    readonly property color colInner: root.useAlbumColors ? root.albumScheme.colSecondaryContainer : WidgetColorScheme.innerShapeColor
    readonly property color colChip: root.useAlbumColors ? root.albumScheme.colOnPrimaryContainer : WidgetColorScheme.highlightCircleColor
    readonly property color colOnChip: root.useAlbumColors ? root.albumScheme.colPrimaryContainer : WidgetColorScheme.highlightTextColor
}
