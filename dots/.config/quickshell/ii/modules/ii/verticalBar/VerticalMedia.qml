import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs
import qs.modules.common.functions

import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Mpris

import qs.modules.ii.bar as Bar

MouseArea {
    id: root
    readonly property MprisPlayer activePlayer: MprisController.activePlayer
    readonly property string cleanedTitle: StringUtils.cleanMusicTitle(activePlayer?.trackTitle) || Translation.tr("No media")
    readonly property bool hasTrack: (activePlayer?.trackTitle ?? "").length > 0

    visible: hasTrack

    onHasTrackChanged: {
        if (typeof rootItem !== "undefined") {
            rootItem.toggleVisible(hasTrack);
        }
    }

    function updatePopupRect() {
        if (root.visible && root.width > 0 && root.height > 0) {
            var globalPos = root.mapToItem(null, 0, 0);
            GlobalStates.mediaPopupRect = Qt.rect(globalPos.x, globalPos.y, root.width, root.height);
        }
    }

    onVisibleChanged: if (visible) Qt.callLater(updatePopupRect)
    onWidthChanged: if (visible) Qt.callLater(updatePopupRect)
    onHeightChanged: if (visible) Qt.callLater(updatePopupRect)
    onXChanged: if (visible) Qt.callLater(updatePopupRect)
    onYChanged: if (visible) Qt.callLater(updatePopupRect)

    Connections {
        target: GlobalStates
        function onMediaControlsOpenChanged() {
            if (GlobalStates.mediaControlsOpen && root.visible) {
                root.updatePopupRect();
            }
        }
    }

    Component.onCompleted: {
        if (typeof rootItem !== "undefined") {
            rootItem.toggleVisible(hasTrack);
        }
        Qt.callLater(updatePopupRect);
    }

    Layout.fillHeight: true
    implicitHeight: hasTrack ? (mediaCircProg.implicitHeight + 10) : 0
    implicitWidth: hasTrack ? Appearance.sizes.verticalBarWidth : 0

    Timer {
        running: activePlayer?.playbackState == MprisPlaybackState.Playing
        interval: Config.options.resources.updateInterval
        repeat: true
        onTriggered: activePlayer.positionChanged()
    }

    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.MiddleButton | Qt.BackButton | Qt.ForwardButton | Qt.RightButton | Qt.LeftButton
    hoverEnabled: !Config.options.bar.tooltips.clickToShow
    onEntered: {
        GlobalStates.setMediaWidgetHovered(true);
        if (hoverEnabled) {
            var globalPos = root.mapToItem(null, 0, 0);
            GlobalStates.mediaPopupRect = Qt.rect(globalPos.x, globalPos.y, root.width, root.height);
            GlobalStates.mediaControlsOpen = true;
        }
    }
    onExited: {
        GlobalStates.setMediaWidgetHovered(false);
    }
    onPressed: (event) => {
        if (event.button === Qt.MiddleButton) {
            activePlayer.togglePlaying();
        } else if (event.button === Qt.BackButton) {
            activePlayer.previous();
        } else if (event.button === Qt.ForwardButton || event.button === Qt.RightButton) {
            activePlayer.next();
        } else if (event.button === Qt.LeftButton) {
            if (!hoverEnabled) {
                var globalPos = root.mapToItem(null, 0, 0);
                GlobalStates.mediaPopupRect = Qt.rect(globalPos.x, globalPos.y, root.width, root.height);
                GlobalStates.mediaControlsOpen = !GlobalStates.mediaControlsOpen;
            }
        }
    }
    onWheel: event => {
        if (!Config.options.bar.mediaPlayer.enableVolumeScroll)
            return;
        if (event.angleDelta.y > 0)
            MprisController.incrementVolume();
        else if (event.angleDelta.y < 0)
            MprisController.decrementVolume();
        event.accepted = true;
    }

    ClippedFilledCircularProgress {
        id: mediaCircProg
        anchors.centerIn: parent
        implicitSize: 20

        lineWidth: Appearance.rounding.unsharpen
        value: (activePlayer?.length ?? 0) > 0 ? Math.min(1, Math.max(0, activePlayer.position / activePlayer.length)) : 0
        colPrimary: Appearance.colors.colOnSecondaryContainer
        enableAnimation: false

        Item {
            anchors.centerIn: parent
            width: mediaCircProg.implicitSize
            height: mediaCircProg.implicitSize
            
            MaterialSymbol {
                anchors.centerIn: parent
                fill: 1
                text: activePlayer?.isPlaying ? "pause" : "music_note"
                iconSize: Appearance.font.pixelSize.normal
                color: Appearance.m3colors.m3onSecondaryContainer
            }
        }
    }
}
