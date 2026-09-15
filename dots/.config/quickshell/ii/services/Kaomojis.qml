pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property string scriptPath: `${Directories.config}/hypr/hyprland/scripts/fuzzel-kaomoji.sh`
    property string lineBeforeData: "### DATA ###"
    property list<var> list
    readonly property var preparedEntries: list.map(a => ({
        name: Fuzzy.prepare(`${a}`),
        entry: a
    }))
    function fuzzyQuery(search: string): var {
        if (!search || search.trim() === "") return root.list;

        return Fuzzy.go(search, preparedEntries, {
            all: true,
            key: "name"
        }).map(r => {
            return r.obj.entry
        });
    }

    function load() {
        fileView.reload()
    }

    function updateKaomojis(fileContent) {
        const lines = fileContent.split("\n")
        const dataIndex = lines.indexOf(root.lineBeforeData)
        if (dataIndex === -1) {
            console.warn("No data section found in kaomoji script file.")
            return
        }
        const kaomojis = lines.slice(dataIndex + 1).filter(line => line.trim() !== "")
        root.list = kaomojis.map(line => line.trim())
        warmupTimer.restart()
    }

    Timer {
        id: warmupTimer
        interval: 2000
        onTriggered: {
            const _ = root.preparedEntries
        }
    }

    FileView {
        id: fileView
        path: Qt.resolvedUrl(root.scriptPath)
        onLoadedChanged: {
            const fileContent = fileView.text()
            root.updateKaomojis(fileContent)
        }
    }
}
