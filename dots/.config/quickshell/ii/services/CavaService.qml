pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.services
import qs.modules.common
import qs.modules.common.functions

Singleton {
    id: root

    property list<real> visualizerPoints: []
    // Anything playing, not just the player the shell happens to treat as active: with
    // two players open (a paused browser tab and a playing music app) the "active" one can
    // be the paused one, and the visualizers would sit still under audible music.
    readonly property bool active: (MprisController.activePlayer?.isPlaying ?? false)
        || Mpris.players.values.some(player => player?.isPlaying === true)

    Process {
        id: cavaProc
        running: root.active
        command: ["cava", "-p", FileUtils.trimFileProtocol(Directories.scriptPath) + "/cava/raw_output_config.txt"]
        stdout: SplitParser {
            onRead: data => {
                let points = data.split(";").map(p => parseFloat(p.trim())).filter(p => !isNaN(p));
                root.visualizerPoints = points;
            }
        }
        onRunningChanged: {
            if (!running) {
                root.visualizerPoints = [];
            }
        }
    }
}
