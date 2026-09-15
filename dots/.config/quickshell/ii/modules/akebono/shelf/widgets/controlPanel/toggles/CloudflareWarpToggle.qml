import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common.widgets

AkToggle {
    id: root
    shown: false
    icon: "cloud_lock"
    onClicked: {
        if (root.on) {
            root.on = false;
            Quickshell.execDetached(["warp-cli", "disconnect"]);
        } else {
            root.on = true;
            connectProc.running = true;
        }
    }
    Process {
        id: connectProc
        command: ["warp-cli", "connect"]
        onExited: exitCode => {
            if (exitCode !== 0)
                Quickshell.execDetached(["notify-send", Translation.tr("Cloudflare WARP"), Translation.tr("Connection failed. Please inspect manually with the <tt>warp-cli</tt> command"), "-a", "Shell"]);
        }
    }
    Process {
        running: true
        command: ["bash", "-c", "warp-cli status"]
        stdout: StdioCollector {
            id: warpStatusCollector
            onStreamFinished: {
                if (warpStatusCollector.text.length > 0)
                    root.shown = true;
                if (warpStatusCollector.text.includes("Connected"))
                    root.on = true;
                else if (warpStatusCollector.text.includes("Disconnected"))
                    root.on = false;
            }
        }
    }
    StyledToolTip {
        text: Translation.tr("Cloudflare WARP (1.1.1.1)")
    }
}
