//@ pragma UseQApplication
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QSG_RENDER_LOOP=threaded
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs
import qs.modules.common
import qs.services
// Pulled in so the scanner registers modules the pages import by URL.
import qs.modules.ii.health.components
import qs.modules.ii.clock.components

// Sandbox-only (scripts/dev/devtools_preview.sh copies it to the shell root): renders the Dev tools page
// and the Search Tools panel for each tool in $DT_TOOLS and saves PNGs to
// $DT_OUT, then quits. Never loaded by the real shell. Not committed.
ShellRoot {
    id: shellRoot

    readonly property var toolIds: String(Quickshell.env("DT_TOOLS") ?? "").split(",").filter(id => id.length > 0)
    readonly property string outDir: String(Quickshell.env("DT_OUT") ?? "/tmp")
    readonly property var inputs: { try { return JSON.parse(Quickshell.env("DT_INPUTS") || "{}"); } catch (e) { return {}; } }
    readonly property var options: { try { return JSON.parse(Quickshell.env("DT_OPTIONS") || "{}"); } catch (e) { return {}; } }
    property int step: 0

    FloatingWindow {
        id: win
        implicitWidth: 1600
        implicitHeight: 960
        color: Appearance.colors.colLayer0

        Item {
            id: host
            width: 1546
            height: 900
            Rectangle { anchors.fill: parent; color: Appearance.colors.colLayer0 }
            Loader {
                id: pageLoader
                anchors.fill: parent
                asynchronous: false
            }
        }
        Item {
            id: panelHost
            y: 0
            x: 0
            visible: false
            width: 760
            height: 640
            Rectangle { anchors.fill: parent; color: Appearance.colors.colLayer0 }
            Loader {
                id: panelLoader
                anchors.fill: parent
                asynchronous: false
            }
        }
    }

    function log(message) {
        console.warn("DTPREVIEW " + message);
    }

    function prepare(item, id) {
        const index = item.tools.findIndex(t => t.id === id);
        if (index < 0) {
            shellRoot.log("missing tool " + id);
            return false;
        }
        item.selectTool(index);
        const opts = shellRoot.options[id] ?? {};
        for (const key in opts)
            item.setOption(key, opts[key]);
        if (shellRoot.inputs[id] !== undefined) {
            if (typeof item.setInput === "function")
                item.setInput(shellRoot.inputs[id]);
            else {
                item.inputText = shellRoot.inputs[id];
                item.execute(false);
            }
        }
        shellRoot.log(`${id} error=${JSON.stringify(item.errorText)} output=${JSON.stringify(String(item.outputText).slice(0, 160))}`);
        return true;
    }

    // One action per tick so each frame renders before its grab.
    Timer {
        id: ticker
        interval: 900
        repeat: true
        running: true
        onTriggered: {
            const ids = shellRoot.toolIds;
            const phase = shellRoot.step;
            shellRoot.step++;
            if (phase === 0) {
                pageLoader.source = Qt.resolvedUrl("modules/ii/cheatsheet/CheatsheetDevTools.qml");
                shellRoot.log("page status " + pageLoader.status);
                return;
            }
            const pageSteps = ids.length * 2;
            if (phase <= pageSteps) {
                const i = Math.floor((phase - 1) / 2);
                if ((phase - 1) % 2 === 0)
                    shellRoot.prepare(pageLoader.item, ids[i]);
                else
                    host.grabToImage(r => r.saveToFile(`${shellRoot.outDir}/${ids[i]}-page.png`));
                return;
            }
            if (phase === pageSteps + 1) {
                pageLoader.source = "";
                host.visible = false;
                panelHost.visible = true;
                panelLoader.source = Qt.resolvedUrl("modules/ii/overview/ToolsPanel.qml");
                shellRoot.log("panel status " + panelLoader.status);
                return;
            }
            const p = phase - pageSteps - 2;
            if (p < ids.length * 2) {
                const i = Math.floor(p / 2);
                if (p % 2 === 0)
                    shellRoot.prepare(panelLoader.item, ids[i]);
                else
                    panelHost.grabToImage(r => r.saveToFile(`${shellRoot.outDir}/${ids[i]}-search.png`));
                return;
            }
            shellRoot.log("done");
            ticker.stop();
            Qt.callLater(Qt.quit);
        }
    }
}
