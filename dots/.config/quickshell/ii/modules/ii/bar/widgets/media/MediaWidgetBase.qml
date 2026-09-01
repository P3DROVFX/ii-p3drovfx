pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * Everything a bar media widget needs that is not its design.
 *
 * Player state, the cover-art download, the popup rectangle bookkeeping and the
 * mouse contract (middle = play/pause, back/right/forward = seek tracks, wheel =
 * volume) were copied verbatim between `Media.qml` and `NeuralMedia.qml`. New
 * styles inherit them from here instead, so a fix to the artwork cache or the
 * popup anchor lands in one place.
 *
 * A derived widget declares its visuals as children and sets `implicitWidth` /
 * `implicitHeight`. The MouseArea lives at the bottom of the stacking order and
 * still receives everything, because Rectangles and Text do not accept events.
 */
Item {
    id: root

    property bool vertical: false
    // Set on instances that live outside the bar (the settings preview). They
    // must not move `GlobalStates.mediaPopupRect`, or hovering a preview would
    // re-anchor the real media popup onto the settings window.
    property bool previewMode: false

    readonly property MprisPlayer activePlayer: MprisController.activePlayer
    readonly property string cleanedTitle: StringUtils.cleanMusicTitle(activePlayer?.trackTitle) || Translation.tr("No media")
    readonly property string trackArtist: activePlayer?.trackArtist ?? ""
    readonly property bool hasTrack: (activePlayer?.trackTitle ?? "").length > 0
    readonly property bool playing: activePlayer?.isPlaying ?? false
    readonly property real progress: (activePlayer?.length ?? 0) > 0
        ? Math.min(1, Math.max(0, activePlayer.position / activePlayer.length))
        : 0

    // Lyrics are a horizontal-bar feature. A 44px column cannot hold a line of
    // text at any size worth reading, so the vertical form never asks for them
    // rather than showing them badly.
    readonly property bool lyricsEnabled: Config.options.bar.mediaPlayer.lyrics.enable && !root.vertical
    readonly property bool showLyrics: root.lyricsEnabled && LyricsService.hasSyncedLines
    readonly property string lyricsStyle: Config.options.bar.mediaPlayer.lyrics.style
    readonly property bool useGradientMask: Config.options.bar.mediaPlayer.lyrics.useGradientMask

    readonly property bool useFixedSize: Config.options.bar.mediaPlayer.useFixedSize
    readonly property int customSize: Config.options.bar.mediaPlayer.customSize
    readonly property int lyricsCustomSize: Config.options.bar.mediaPlayer.lyrics.customSize
    readonly property int maxSize: Config.options.bar.mediaPlayer.maxSize

    readonly property real thickness: root.vertical
        ? Appearance.sizes.verticalBarWidth - 8
        : Appearance.sizes.baseBarHeight - 8

    visible: root.hasTrack

    onHasTrackChanged: {
        if (typeof rootItem !== "undefined")
            rootItem.toggleVisible(root.hasTrack);
    }

    // ── Cover art ────────────────────────────────────────────────────────────
    readonly property string artUrl: MprisController.artUrl
    readonly property bool isLocalArt: root.artUrl.startsWith("file://")
    readonly property string artFilePath: `${Directories.coverArt}/${Qt.md5(root.artUrl)}`
    property bool artDownloaded: false
    readonly property string artSource: {
        if (!root.artUrl)
            return "";
        if (root.isLocalArt)
            return root.artUrl;
        return root.artDownloaded ? Qt.resolvedUrl(root.artFilePath) : "";
    }

    onArtFilePathChanged: {
        if (!root.artUrl || root.artUrl.length === 0) {
            root.artDownloaded = false;
            return;
        }
        if (root.isLocalArt) {
            root.artDownloaded = true;
            return;
        }
        root.artDownloaded = false;
        artDownloader.running = true;
    }

    Process {
        id: artDownloader
        command: ["bash", "-c", `[ -f '${root.artFilePath}' ] || (curl -4 -sSL '${root.artUrl}' -o '${root.artFilePath}.tmp' && mv '${root.artFilePath}.tmp' '${root.artFilePath}')`]
        onExited: root.artDownloaded = true
    }

    // ── Popup anchor ─────────────────────────────────────────────────────────
    function updatePopupRect() {
        if (root.previewMode || !root.visible || root.width <= 0 || root.height <= 0)
            return;
        const globalPos = root.mapToItem(null, 0, 0);
        GlobalStates.mediaPopupRect = Qt.rect(globalPos.x, globalPos.y, root.width, root.height);
    }

    onVisibleChanged: if (root.visible) Qt.callLater(root.updatePopupRect)
    onWidthChanged: if (root.visible) Qt.callLater(root.updatePopupRect)
    onHeightChanged: if (root.visible) Qt.callLater(root.updatePopupRect)
    onXChanged: if (root.visible) Qt.callLater(root.updatePopupRect)
    onYChanged: if (root.visible) Qt.callLater(root.updatePopupRect)

    Connections {
        target: GlobalStates

        function onMediaControlsOpenChanged() {
            if (GlobalStates.mediaControlsOpen && root.visible)
                root.updatePopupRect();
        }
    }

    Component.onCompleted: {
        LyricsService.initiliazeLyrics();
        if (typeof rootItem !== "undefined")
            rootItem.toggleVisible(root.hasTrack);
        Qt.callLater(root.updatePopupRect);
    }

    // Mpris only emits position on demand for most players, so a ticking clock
    // is what keeps a progress ring honest while a track plays.
    Timer {
        running: root.playing
        interval: Config.options.resources.updateInterval
        repeat: true
        onTriggered: root.activePlayer?.positionChanged()
    }

    MouseArea {
        id: mediaMouseArea
        anchors.fill: parent
        hoverEnabled: !Config.options.bar.tooltips.clickToShow
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.MiddleButton | Qt.BackButton | Qt.ForwardButton | Qt.RightButton | Qt.LeftButton

        onEntered: {
            if (root.previewMode)
                return;
            GlobalStates.setMediaWidgetHovered(true);
            if (!hoverEnabled)
                return;
            root.updatePopupRect();
            GlobalStates.mediaControlsOpen = true;
        }
        onExited: if (!root.previewMode) GlobalStates.setMediaWidgetHovered(false)

        onPressed: event => {
            if (root.previewMode)
                return;
            if (event.button === Qt.MiddleButton)
                root.activePlayer?.togglePlaying();
            else if (event.button === Qt.BackButton)
                root.activePlayer?.previous();
            else if (event.button === Qt.ForwardButton || event.button === Qt.RightButton)
                root.activePlayer?.next();
            else if (event.button === Qt.LeftButton && !hoverEnabled) {
                root.updatePopupRect();
                GlobalStates.mediaControlsOpen = !GlobalStates.mediaControlsOpen;
            }
        }

        onWheel: event => {
            if (root.previewMode || !Config.options.bar.mediaPlayer.enableVolumeScroll)
                return;
            if (event.angleDelta.y > 0)
                MprisController.incrementVolume();
            else if (event.angleDelta.y < 0)
                MprisController.decrementVolume();
            event.accepted = true;
        }
    }
}
