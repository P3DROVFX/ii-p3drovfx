import qs.modules.ii.bar.shared
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import "../../shared/cards"
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Mpris
import Qt5Compat.GraphicalEffects

StyledPopup {
    id: root
    popupRadius: Appearance.rounding.large
    stickyHover: true

    readonly property MprisPlayer activePlayer: MprisController.activePlayer
    readonly property string cleanedTitle: StringUtils.cleanMusicTitle(activePlayer?.trackTitle) || Translation.tr("No media")

    animate: false // We have to disable the animation if we have only one card
    contentItem: HeroCard {
        id: mediaHero
        startAnim: root.opened && root.popupOpenProgress > 0.6
        compactMode: true
        adaptiveWidth: true
        anchors.centerIn: parent
        icon: "music_note"

        title: activePlayer?.trackArtist || Translation.tr("Unknown Artist")
        subtitle: activePlayer ? activePlayer.trackTitle : Translation.tr("No media")

        pillText: activePlayer ? (activePlayer.playbackState == MprisPlaybackState.Playing ? Translation.tr("Playing") : Translation.tr("Paused")) : ""
        pillIcon: activePlayer ? (activePlayer.playbackState == MprisPlaybackState.Playing ? "play_arrow" : "pause") : ""
    }
}