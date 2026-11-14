import QtQuick
import Quickshell.Io

Process {
    id: probe
    property string path
    
    signal sizeDetected(int width, int height)
    
    readonly property bool isVideo: path.endsWith(".mp4") || path.endsWith(".webm") || path.endsWith(".mkv") || path.endsWith(".avi") || path.endsWith(".mov")
    // -ping reads the header only. Without it identify decodes the whole picture
    // (0.3 s for a 24 MP JPEG, ~1 s at login with one probe per screen), and the
    // wallpaper plane waits for this answer before it can decode at all.
    command: isVideo ? ["magick", "identify", "-format", "%w %h", path + "[0]"]
        : ["magick", "identify", "-ping", "-format", "%w %h", path]

    stdout: StdioCollector {
        id: collector
        onStreamFinished: {
            const output = collector.text.trim();
            if (!output) return;
            const parts = output.split(/\s+/);
            if (parts.length >= 2) {
                const w = Number(parts[0]);
                const h = Number(parts[1]);
                if (!isNaN(w) && !isNaN(h) && w > 0 && h > 0) {
                    probe.sizeDetected(w, h);
                }
            }
        }
    }
}
