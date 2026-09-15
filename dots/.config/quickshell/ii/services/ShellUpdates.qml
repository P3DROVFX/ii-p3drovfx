pragma Singleton

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/*
 * Fork/source update state for this Quickshell config.
 *
 * The Settings "Update" page used to own this: it read the .active-* state
 * files and probed the remote itself, so nothing knew whether an update existed
 * unless that page happened to be open. The bar indicator needs the same answer
 * without it, so the whole probe lives here and AboutConfig binds to it.
 */
Singleton {
    id: root

    readonly property string setupScript: FileUtils.trimFileProtocol(Directories.home + "/.local/share/ii-p3drovfx/setup-ii-p3drovfx.sh")
    readonly property string stateDir: FileUtils.trimFileProtocol(Directories.home + "/.config/quickshell/ii")

    property string activeRemote: ""
    property string activeBranch: "main"
    property string activeFork: "p3drovfx"
    property string activeCommit: ""
    property string remoteCommit: ""

    // How far the remote branch is ahead of the local checkout. 0 means
    // "unknown" as much as "level": the count comes from the GitHub compare
    // API, which is unavailable for other hosts, offline, or rate-limited.
    // Callers show a bare icon rather than a "0" when hasUpdate has no count.
    property int commitsBehind: 0
    property bool checking: false

    readonly property bool hasUpdate: activeCommit !== "" && remoteCommit !== "" && activeCommit !== remoteCommit

    readonly property real lastCheck: Config.options?.update?.lastAutoCheck ?? 0

    readonly property int autoCheckPeriodMs: {
        switch (Config.options?.update?.autoCheckInterval ?? "daily") {
        case "10min":
            return 10 * 60 * 1000;
        case "hourly":
            return 60 * 60 * 1000;
        case "daily":
            return 24 * 60 * 60 * 1000;
        case "weekly":
            return 7 * 24 * 60 * 60 * 1000;
        default:
            return 0; // disabled
        }
    }

    // Whether the state read currently in flight should chain into the network
    // probe. Re-reading state after an update action must not spend a request.
    property bool _probeAfterState: false

    function load() {
        root.reloadState();
    }

    // Re-read the .active-* files only. Cheap, no network.
    function reloadState() {
        if (root.checking) return;
        root._probeAfterState = false;
        stateReadProc.running = true;
    }

    // Full check: state files, then remote HEAD, then the commit count.
    function refresh() {
        if (root.checking) return;
        root.checking = true;
        root._probeAfterState = true;
        watchdog.restart();
        stateReadProc.running = true;
    }

    // minAgeMs overrides how stale the last check must be to earn a new one;
    // it defaults to the configured period.
    function maybeAutoCheck(minAgeMs) {
        if (root.autoCheckPeriodMs <= 0) return;
        const age = minAgeMs ?? root.autoCheckPeriodMs;
        const now = Date.now();
        // A timestamp in the future (clock jump, hand-edited config) would
        // otherwise wedge the check until real time caught up with it.
        if (root.lastCheck <= now && now - root.lastCheck < age) return;
        root.refresh();
    }

    // owner/repo out of an https or ssh GitHub remote; "" for anything else.
    function githubSlug(remote) {
        if (!remote) return "";
        const m = remote.match(/github\.com[:\/]+([^\/]+)\/([^\/]+?)(?:\.git)?\/?$/);
        return m ? `${m[1]}/${m[2]}` : "";
    }

    function _finishCheck() {
        watchdog.stop();
        root.checking = false;
        print(`[ShellUpdates] ${root.activeFork}@${root.activeBranch}: local ${root.activeCommit.substring(0, 7) || "?"}, remote ${root.remoteCommit.substring(0, 7) || "?"}, hasUpdate ${root.hasUpdate}, behind ${root.commitsBehind}`);
        stamp.restart();
    }

    // Recording the check writes config.json, and so does the bar indicator
    // showing itself — two writes in the same tick, and the first one's own
    // reload overwrites the second. A short delay keeps them apart.
    Timer {
        id: stamp
        interval: 500
        onTriggered: {
            if (!Config.options?.update) return;
            // A probe that never reached the remote should not buy a whole
            // period of silence; back the stamp off so it retries shortly.
            const reached = root.remoteCommit !== "";
            Config.options.update.lastAutoCheck = reached ? Date.now() : Date.now() - Math.max(0, root.autoCheckPeriodMs - 15 * 60 * 1000);
        }
    }

    // Every stage chains from its own stdout rather than from exited, so the
    // order is deterministic; this only catches a stage that never produces a
    // stream at all, which would otherwise latch `checking` forever.
    Timer {
        id: watchdog
        interval: 90000
        onTriggered: {
            root._probeAfterState = false;
            root.checking = false;
        }
    }

    Process {
        id: stateReadProc
        command: ["bash", "-c", 'dir="$1"; out=""; ' + 'for f in .active-remote .active-branch .active-fork .active-commit; do ' + '[ -f "$dir/$f" ] && out+="$(cat "$dir/$f")"; out+="---"; done; ' + 'printf %s "$out"', "ii-state-read", root.stateDir]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.split("---");
                root.activeRemote = (parts[0] ?? "").trim();
                root.activeBranch = (parts[1] ?? "").trim() || "main";
                root.activeFork = (parts[2] ?? "").trim() || "p3drovfx";
                root.activeCommit = (parts[3] ?? "").trim();

                if (!root._probeAfterState) return;
                root._probeAfterState = false;
                if (root.activeRemote === "" || root.activeCommit === "") {
                    root._finishCheck();
                    return;
                }
                remoteHeadProc.running = true;
            }
        }
    }

    Process {
        id: remoteHeadProc
        command: ["bash", "-c", 'git ls-remote --heads "$1" "$2" 2>/dev/null | awk \'{print $1; exit}\'', "ii-remote-head", root.activeRemote, root.activeBranch]
        stdout: StdioCollector {
            onStreamFinished: {
                // An unreachable remote prints nothing; keeping the last known
                // SHA would claim an update that was never confirmed.
                root.remoteCommit = text.trim();
                if (!root.hasUpdate || root.githubSlug(root.activeRemote) === "") {
                    root.commitsBehind = 0;
                    root._finishCheck();
                    return;
                }
                compareProc.running = true;
            }
        }
    }

    // Commit count via the GitHub compare API. The response carries the whole
    // diff — hundreds of KB — so grep pulls the one field out inside the pipe
    // rather than handing all of it to QML. The JSON comes back pretty-printed,
    // hence the whitespace in the pattern.
    Process {
        id: compareProc
        command: ["bash", "-c", 'curl -sfL --max-time 15 -H "Accept: application/vnd.github+json" ' + '"https://api.github.com/repos/$1/compare/$2...$3" ' + '| grep -m1 -oE \'"ahead_by"[[:space:]]*:[[:space:]]*[0-9]+\' | grep -oE \'[0-9]+\'', "ii-compare", root.githubSlug(root.activeRemote), root.activeCommit, root.remoteCommit]
        stdout: StdioCollector {
            onStreamFinished: {
                const n = parseInt(text.trim());
                root.commitsBehind = isNaN(n) ? 0 : n;
                root._finishCheck();
            }
        }
    }

    // The setup script rewrites these when it swaps fork or branch, and the
    // indicator has to drop the moment an update lands.
    FileView {
        path: `${root.stateDir}/.active-commit`
        watchChanges: true
        printErrors: false
        onFileChanged: root.reloadState()
    }

    // A QML live-reload re-creates this singleton, so a plain timer would spend a
    // probe on every file save. PersistentProperties survives reloads within the
    // same process, which makes this exactly one check per shell process.
    PersistentProperties {
        id: session
        reloadableId: "shellUpdatesSession"
        property bool startupCheckDone: false
    }

    // Every shell start checks, whatever the interval — a machine that was off
    // all week should not have to wait another week to hear about it. The few
    // seconds of delay keep the request out of the startup rush.
    Timer {
        running: Config.ready && !session.startupCheckDone
        interval: 8000
        onTriggered: {
            session.startupCheckDone = true;
            root.maybeAutoCheck(0); // 0: any age qualifies, but "disabled" still wins
        }
    }

    // Ticks far more often than any period, since it only compares timestamps;
    // the shortest setting is 10 minutes and would drift badly on a coarse tick.
    Timer {
        running: Config.ready && root.autoCheckPeriodMs > 0
        interval: 60 * 1000
        repeat: true
        onTriggered: root.maybeAutoCheck()
    }

    Component.onCompleted: root.reloadState()
}
