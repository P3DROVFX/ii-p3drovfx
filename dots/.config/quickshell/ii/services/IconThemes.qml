pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

Singleton {
    id: root

    property var availableThemes: []

    function refresh() {
        listThemesProcess.running = true;
    }

    Process {
        id: listThemesProcess
        command: ["bash", "-c", "ls -d /usr/share/icons/*/ ~/.local/share/icons/*/ ~/.icons/*/ 2>/dev/null | xargs -n1 basename | sort -u"]

        stdout: StdioCollector {
            id: themeCollector
            onStreamFinished: {
                let themes = themeCollector.text.split("\n").map(t => t.trim()).filter(t => t && t !== "hicolor" && t !== "default" && t !== "TemaDinamico");

                // Remove duplicates
                root.availableThemes = [...new Set(themes)];
            }
        }
    }

    function applyTheme() {
        applyProcess.running = true;
    }

    Process {
        id: applyProcess
        command: ["python3", Directories.scriptPath + "/colors/recolor_icons.py"]

        onRunningChanged: {
            if (!running && exitCode === 0) {
                // Restart quickshell
                Quickshell.execDetached({
                    command: ["quickshell", "--reload"]
                });
            }
        }
    }

    Component.onCompleted: refresh()
}
