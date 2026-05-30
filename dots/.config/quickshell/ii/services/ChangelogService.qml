pragma Singleton

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property alias loading: repoProc.running
    readonly property alias commits: commitsModel

    readonly property string repoPath: FileUtils.trimFileProtocol(Directories.home) + "/Downloads/ii-vynx"

    ListModel {
        id: commitsModel
    }

    Component.onCompleted: {
        refresh();
    }

    function refresh() {
        repoProc.running = true;
    }

    function generateSmartId(hash, title) {
        let lowerTitle = title.toLowerCase().trim();
        let prefix = "G";
        
        if (lowerTitle.startsWith("feat") || lowerTitle.includes("feat")) {
            prefix = "A";
        } else if (lowerTitle.startsWith("fix") || lowerTitle.includes("fix") || lowerTitle.includes("bug")) {
            prefix = "B";
        } else if (lowerTitle.startsWith("refactor") || lowerTitle.includes("refactor") || lowerTitle.includes("perf")) {
            prefix = "C";
        } else if (lowerTitle.startsWith("style") || lowerTitle.includes("style") || lowerTitle.includes("ui") || lowerTitle.includes("theme") || lowerTitle.includes("layout") || lowerTitle.includes("color")) {
            prefix = "D";
        } else if (lowerTitle.startsWith("docs") || lowerTitle.includes("docs") || lowerTitle.includes("readme") || lowerTitle.includes("wiki")) {
            prefix = "E";
        } else if (lowerTitle.startsWith("chore") || lowerTitle.includes("chore") || lowerTitle.startsWith("build") || lowerTitle.startsWith("ci") || lowerTitle.startsWith("test")) {
            prefix = "F";
        }
        
        let suffix = hash.substring(0, 4).toUpperCase();
        return prefix + "-" + suffix;
    }

    function parseCommits(text, model) {
        model.clear();
        if (!text || text.trim() === "") {
            return;
        }
        
        let commitsRaw = text.split("\u001e");
        for (let i = 0; i < commitsRaw.length; i++) {
            let raw = commitsRaw[i];
            if (raw.trim() === "") continue;
            
            let parts = raw.split("\u001f");
            if (parts.length < 3) continue;
            
            let hash = parts[0].trim();
            let title = parts[1].trim();
            let date = parts[2].trim();
            let desc = parts.length > 3 ? parts[3].trim() : "";
            
            let smartId = generateSmartId(hash, title);
            
            model.append({
                "hash": hash,
                "title": title,
                "description": desc,
                "smartId": smartId,
                "date": date
            });
        }
    }

    Process {
        id: repoProc
        command: ["git", "-C", root.repoPath, "log", "-n", "10", "--pretty=format:%h%x1f%s%x1f%ar%x1f%b%x1e"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.parseCommits(text, commitsModel);
            }
        }
    }
}
