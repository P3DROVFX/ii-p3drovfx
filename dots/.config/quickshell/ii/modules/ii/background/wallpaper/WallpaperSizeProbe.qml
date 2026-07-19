import QtQuick
import Quickshell.Io

Process {
    id: probe
    property string path
    
    signal sizeDetected(int width, int height)
    
    command: ["magick", "identify", "-format", "%w %h", path]
    
    stdout: StdioCollector {
        id: collector
        onStreamFinished: {
            const output = collector.text.trim();
            if (!output) return;
            const parts = output.split(" ");
            if (parts.length >= 2) {
                const w = Number(parts[0]);
                const h = Number(parts[1]);
                if (!isNaN(w) && !isNaN(h)) {
                    probe.sizeDetected(w, h);
                }
            }
        }
    }
}
