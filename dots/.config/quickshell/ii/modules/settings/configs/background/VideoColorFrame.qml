import QtQuick
import Quickshell.Io
import qs.modules.common
import qs.services

/**
 * Headless state of the colour-frame picker: which moment of the desktop video the theme
 * colours and poster frame come from, the video's length and a throwaway JPEG of the picked
 * moment. The picked time follows what is applied until the user moves it.
 */
Item {
    id: root

    readonly property int previewDelay: 250
    readonly property int applyTimeout: 20000
    readonly property int previewWidth: 640
    readonly property real secondsPerMinute: 60
    readonly property real tenth: 10
    readonly property string previewDir: "/tmp/ii-video-color-frame"

    readonly property string video: {
        const background = Config.options.background;
        return !background.useWallpaperEngine && Wallpapers.isVideoFile(background.wallpaperPath ?? "") ? background.wallpaperPath : "";
    }
    readonly property real appliedSeconds: Wallpapers.videoFrameTime(root.video)
    property real seconds: 0
    property real duration: 0
    property string preview: ""
    property int previewSeq: 0
    property bool applying: false

    function format(value) {
        const total = Math.max(0, Number(value) || 0);
        const minutes = Math.floor(total / root.secondsPerMinute);
        const rest = (total - minutes * root.secondsPerMinute).toFixed(1);
        return `${minutes}:${Number(rest) < root.tenth ? "0" : ""}${rest}`;
    }

    // "75", "75.5", "1:15", "1:15.5" or "0:01:15" → seconds; NaN if unreadable.
    function parse(text) {
        const parts = String(text).trim().split(":");
        if (parts.length === 0 || parts.length > 3 || parts.some(p => !/^\d+(\.\d+)?$/.test(p)))
            return NaN;
        return parts.reduce((acc, part) => acc * root.secondsPerMinute + Number(part), 0);
    }

    function clamp(value) {
        const top = root.duration > 0 ? root.duration : value;
        return Math.round(Math.max(0, Math.min(top, value)) * root.tenth) / root.tenth;
    }

    function apply() {
        root.applying = true;
        Wallpapers.applyVideoFrameTime(root.video, root.seconds);
    }

    function load() {
        root.seconds = root.appliedSeconds;
        root.duration = 0;
        root.preview = "";
        if (root.video === "")
            return;
        durationProc.running = false;
        durationProc.running = true;
        previewDebounce.restart();
    }

    // The pick starts at what is in use, and follows it when an apply (or the config
    // loading late) changes it.
    onAppliedSecondsChanged: root.seconds = root.appliedSeconds
    onVideoChanged: Qt.callLater(root.load)
    onSecondsChanged: previewDebounce.restart()
    Component.onCompleted: Qt.callLater(root.load)

    Timer {
        id: previewDebounce
        interval: root.previewDelay
        onTriggered: {
            if (root.video === "")
                return;
            root.previewSeq += 1;
            previewProc.target = `${root.previewDir}/frame-${root.previewSeq}.jpg`;
            previewProc.running = false;
            previewProc.running = true;
        }
    }

    Process {
        id: durationProc
        command: ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "default=nw=1:nk=1", root.video]
        stdout: StdioCollector {
            onStreamFinished: root.duration = Math.floor((Number(text.trim()) || 0) * root.tenth) / root.tenth
        }
    }

    Process {
        id: previewProc
        property string target: ""
        // One preview file at a time; a new name per pick so the Image reloads.
        command: ["bash", "-c", 'mkdir -p "$1" && rm -f "$1"/frame-*.jpg; ffmpeg -y -ss "$2" -i "$3" -frames:v 1 -vf scale=' + root.previewWidth + ':-2 "$4" 2>/dev/null || ffmpeg -y -i "$3" -frames:v 1 -vf scale=' + root.previewWidth + ':-2 "$4" 2>/dev/null',
            "ii-color-frame", root.previewDir, String(root.seconds), root.video, previewProc.target]
        onExited: root.preview = previewProc.target
    }

    // Done when switchwall.sh publishes the new poster frame.
    Connections {
        target: Config.options.background
        function onThumbnailPathChanged() {
            root.applying = false;
        }
    }
    Timer {
        running: root.applying
        interval: root.applyTimeout
        onTriggered: root.applying = false
    }
}
