import QtQuick
import qs.modules.common.functions as CF

// A video wallpaper played by the shell itself, inside the wallpaper plane, so
// everything that samples or transforms that plane (window blur, lock blur,
// parallax, overview zoom) treats it like a still image.
//
// Uses libmpv through the optional MpvWallpaper plugin (frames stay on the GPU),
// else QtMultimedia. The poster frame underneath stays visible until the first
// frame arrives, and `playing: false` freezes the current frame at zero cost.
Item {
    id: root

    property string source: ""
    property bool playing: true

    readonly property Item surface: mpvLoader.item ?? qtLoader.item
    readonly property bool hasVideo: surface?.hasVideo ?? false
    readonly property string backendName: surface?.backendName ?? ""

    // The file to actually open: switchwall.sh's screen-sized copy of a video
    // bigger than the screen, once it exists (videos/video-proxy.sh).
    property string playbackPath: ""
    readonly property string localSource: CF.FileUtils.trimFileProtocol(source)
    readonly property string resolvedSource: playbackPath !== "" ? CF.FileUtils.trimFileProtocol(playbackPath) : localSource

    // When the plugin is missing this Loader errors out (one warning in the log)
    // and the QtMultimedia fallback below takes over.
    Loader {
        id: mpvLoader
        anchors.fill: parent
        source: Qt.resolvedUrl("MpvVideoSurface.qml")
        onLoaded: {
            item.videoSource = Qt.binding(() => root.resolvedSource);
            item.playing = Qt.binding(() => root.playing);
        }
    }

    Loader {
        id: qtLoader
        anchors.fill: parent
        active: mpvLoader.status === Loader.Error
        source: Qt.resolvedUrl("QtVideoSurface.qml")
        onLoaded: {
            item.videoSource = Qt.binding(() => root.resolvedSource);
            item.playing = Qt.binding(() => root.playing);
        }
    }
}
