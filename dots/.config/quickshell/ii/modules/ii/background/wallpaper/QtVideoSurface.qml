import QtQuick
import QtMultimedia

// Fallback when the MpvWallpaper plugin is not built. QtMultimedia needs no
// extra build step, but on NVIDIA it copies every decoded frame through system
// memory (its CUDA path has no GL interop), so it costs noticeably more CPU.
Item {
    id: surface

    property string videoSource: ""
    property bool playing: true
    readonly property string backendName: "qtmultimedia"
    readonly property string decoder: ""
    readonly property bool hasVideo: player.hasVideo && player.playbackState !== MediaPlayer.StoppedState
    readonly property string errorString: player.errorString

    MediaPlayer {
        id: player
        source: surface.videoSource !== "" ? "file://" + surface.videoSource : ""
        loops: MediaPlayer.Infinite
        audioOutput: null
        videoOutput: output
        onSourceChanged: if (source != "" && surface.playing) play()
    }

    onPlayingChanged: playing ? player.play() : player.pause()
    Component.onCompleted: if (player.source != "" && playing) player.play()

    VideoOutput {
        id: output
        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectCrop
    }
}
