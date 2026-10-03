import QtQuick
import MpvWallpaper

// Loaded by URL from VideoWallpaper: when the optional MpvWallpaper plugin is not
// installed this file fails to compile and VideoWallpaper falls back to
// QtVideoSurface. Keep every `import MpvWallpaper` behind such a Loader.
MpvItem {
    id: surface

    property string videoSource: ""
    property bool playing: true
    readonly property string backendName: "libmpv"
    readonly property string decoder: hwdec !== "" && hwdec !== "no" ? hwdec : "software"

    source: videoSource
    paused: !playing
}
