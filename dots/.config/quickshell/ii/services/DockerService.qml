pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

/**
 * Docker integration service for the ii panel.
 * Listens to docker events for real-time updates. Polls every 60s as fallback.
 */
Singleton {
    id: root

    // ── State ──────────────────────────────────────────────────────────────
    property bool dockerAvailable: false
    property bool dockerRunning: false         // systemd service active
    property bool isLoading: false             // only true during explicit user-triggered refreshes
    property var containers: []
    property int runningCount: 0
    property real totalMemoryMb: 0             // total RAM used by all running containers (MB)

    property string _lastSerializedContainers: ""
    property var _memStats: ({})             // id → MB map

    // ── Boot ───────────────────────────────────────────────────────────────
    Component.onCompleted: {
        _silentRefresh();
        eventsProc.running = true;
    }

    // ── Public API ─────────────────────────────────────────────────────────
    // Called by the user-facing refresh button — shows loading indicator
    function refresh() {
        root.isLoading = true;
        _startAvailabilityCheck();
        _startServiceCheck();
    }

    // Called when the popup opens — refreshes uptime display without spinner
    function refreshForPopup() {
        _silentRefresh();
        _startMemStats();
    }

    // Called by timers / events — silent, no loading spinner
    function _silentRefresh() {
        _startAvailabilityCheck();
        _startServiceCheck();
    }

    // ── Availability / docker info ─────────────────────────────────────────
    function _startAvailabilityCheck() {
        availabilityProc.running = false;
        availabilityProc.running = true;
    }

    Process {
        id: availabilityProc
        command: ["docker", "info"]
        running: false
        stdout: StdioCollector {}
        onExited: code => {
            root.dockerAvailable = (code === 0);
            if (root.dockerAvailable) {
                _startFetch();
            } else {
                _applyEmptyContainers();
                root.isLoading = false;
            }
        }
    }

    // ── Systemd service status ─────────────────────────────────────────────
    function _startServiceCheck() {
        serviceStatusProc.running = false;
        serviceStatusProc.running = true;
    }

    Process {
        id: serviceStatusProc
        // Use /bin/sh to invoke the real system systemctl (avoids AppImage PATH sandbox)
        command: ["/bin/sh", "-c", "/usr/bin/systemctl is-active docker 2>/dev/null"]
        running: false
        stdout: StdioCollector {}
        onExited: code => {
            root.dockerRunning = (code === 0);
        }
    }

    // ── Event watcher — drives real-time container state changes ───────────
    property Timer debounce: Timer {
        interval: 500
        repeat: false
        onTriggered: root._silentRefresh()
    }

    Process {
        id: eventsProc
        command: ["docker", "events", "--format", "json", "--filter", "type=container"]
        running: false
        stdout: SplitParser {
            onRead: data => {
                try {
                    const ev = JSON.parse(data);
                    const act = ev.Status || ev.status || "";
                    if (["start", "stop", "die", "died", "kill", "restart", "pause", "unpause", "create", "destroy", "remove", "cleanup"].includes(act)) {
                        root.debounce.restart();
                    }
                } catch (_) {}
            }
        }
        onRunningChanged: {
            if (!running)
                restartEventsTimer.restart();
        }
    }

    Timer {
        id: restartEventsTimer
        interval: 5000
        repeat: false
        onTriggered: {
            if (root.dockerAvailable)
                eventsProc.running = true;
        }
    }

    // ── Background poll (60s fallback) — silent ────────────────────────────
    Timer {
        interval: 60000
        running: true
        repeat: true
        onTriggered: root._silentRefresh()
    }

    // ── Fetch containers ───────────────────────────────────────────────────
    function _startFetch() {
        fetchProc.running = false;
        fetchProc.running = true;
    }

    function _applyEmptyContainers() {
        if (root._lastSerializedContainers !== "[]") {
            root._lastSerializedContainers = "[]";
            root.containers = [];
        }
        root.runningCount = 0;
    }

    Process {
        id: fetchProc
        command: ["sh", "-c", "docker container inspect $(docker container ls -aq) 2>/dev/null || echo '[]'"]
        running: false
        stdout: StdioCollector {
            id: fetchOut
        }
        onExited: code => {
            root.isLoading = false;
            try {
                const raw = JSON.parse(fetchOut.text || "[]");
                const parsed = raw.map(c => {
                    const state = c.State?.Status || "";
                    const ports = [];
                    const pb = c.NetworkSettings?.Ports || {};
                    for (const [cp, hbs] of Object.entries(pb)) {
                        if (hbs)
                            hbs.forEach(b => {
                                if (b.HostPort)
                                    ports.push({
                                        containerPort: cp,
                                        hostPort: b.HostPort,
                                        hostIp: b.HostIp || "0.0.0.0"
                                    });
                            });
                    }
                    const labels = c.Config?.Labels || {};
                    return {
                        id: c.Id || "",
                        shortId: (c.Id || "").slice(0, 12),
                        name: (c.Name || "").replace(/^\//, ""),
                        image: c.Config?.Image || "",
                        state: state,
                        isRunning: c.State?.Running || false,
                        isPaused: c.State?.Paused || false,
                        startedAt: c.State?.StartedAt || "",
                        ports: ports,
                        composeProject: labels["com.docker.compose.project"] || "",
                        composeService: labels["com.docker.compose.service"] || "",
                        composeWorkingDir: labels["com.docker.compose.project.working_dir"] || "",
                        composeConfigFiles: labels["com.docker.compose.project.config_files"] || "compose.yaml"
                    };
                }).filter(c => c !== null).sort((a, b) => {
                    const p = {
                        running: 0,
                        paused: 1
                    };
                    return (p[a.state] ?? 2) - (p[b.state] ?? 2) || a.name.localeCompare(b.name);
                });

                const serialized = JSON.stringify(parsed);
                if (root._lastSerializedContainers !== serialized) {
                    root._lastSerializedContainers = serialized;
                    root.containers = parsed;
                }
                root.runningCount = parsed.filter(c => c.isRunning).length;
            } catch (e) {
                console.error("DockerService: parse error", e);
                _applyEmptyContainers();
            }
        }
    }

    // ── Memory stats (docker stats --no-stream) ────────────────────────────
    function _startMemStats() {
        if (!root.dockerAvailable || root.runningCount === 0)
            return;
        memStatsProc.running = false;
        memStatsProc.running = true;
    }

    Process {
        id: memStatsProc
        // Output: <id12> <mem_usage_bytes>
        command: ["sh", "-c", "docker stats --no-stream --format '{{.ID}} {{.MemUsage}}' 2>/dev/null || true"]
        running: false
        stdout: StdioCollector {
            id: memStatsOut
        }
        onExited: {
            try {
                const lines = (memStatsOut.text || "").trim().split("\n");
                const map = {};
                let total = 0;
                lines.forEach(line => {
                    const parts = line.trim().split(/\s+/);
                    if (parts.length < 2)
                        return;
                    const shortId = parts[0];
                    // mem format: "123.4MiB / 7.8GiB" — take first number + unit
                    const memStr = parts[1] || "0B";
                    let mb = 0;
                    const m = memStr.match(/^([\d.]+)([kKmMgGtT]i?B?)$/i);
                    if (m) {
                        const v = parseFloat(m[1]);
                        const u = m[2].toLowerCase();
                        if (u.startsWith('k'))
                            mb = v / 1024;
                        else if (u.startsWith('m'))
                            mb = v;
                        else if (u.startsWith('g'))
                            mb = v * 1024;
                        else if (u.startsWith('t'))
                            mb = v * 1024 * 1024;
                        else
                            mb = v / (1024 * 1024);
                    }
                    map[shortId] = mb;
                    total += mb;
                });
                // Attach memMb to each container object
                const updated = root.containers.map(c => {
                    const mb = map[c.shortId] ?? map[c.id?.slice(0, 12)] ?? 0;
                    return Object.assign({}, c, {
                        memMb: mb
                    });
                });
                root._memStats = map;
                root.totalMemoryMb = total;
                root.containers = updated;
            } catch (e) {
                console.warn("DockerService: mem stats parse error", e);
            }
        }
    }

    // ── Container actions ──────────────────────────────────────────────────
    function containerAction(id, action) {
        const cmds = {
            start: ["docker", "start", id],
            stop: ["docker", "stop", id],
            restart: ["docker", "restart", id],
            pause: ["docker", "pause", id],
            unpause: ["docker", "unpause", id]
        };
        if (cmds[action]) {
            Quickshell.execDetached(cmds[action]);
            Qt.callLater(() => root.debounce.restart());
        }
    }

    // ── Terminal launch — kitty-first with correct flags ───────────────────
    function openLogs(containerId) {
        // kitty: `kitty --hold -- <cmd>` keeps window open after process exits
        // alacritty: `alacritty --hold -e <cmd>`
        // foot: `foot -e <cmd>` (no --hold, process stays via TTY)
        const script = ["if command -v kitty >/dev/null 2>&1; then", "  kitty --hold -- docker logs -f " + containerId, "elif command -v alacritty >/dev/null 2>&1; then", "  alacritty --hold -e docker logs -f " + containerId, "elif command -v foot >/dev/null 2>&1; then", "  foot -e sh -c 'docker logs -f " + containerId + "; read -p \"Press Enter...\"'", "elif command -v wezterm >/dev/null 2>&1; then", "  wezterm start -- sh -c 'docker logs -f " + containerId + "; read -p \"Press Enter...\"'", "elif command -v gnome-terminal >/dev/null 2>&1; then", "  gnome-terminal -- sh -c 'docker logs -f " + containerId + "; read -p \"Press Enter...\"'", "fi"].join("\n");
        Quickshell.execDetached(["sh", "-c", script]);
    }

    function openShell(containerId) {
        // Open an interactive shell inside the container
        const script = ["if command -v kitty >/dev/null 2>&1; then", "  kitty -- docker exec -it " + containerId + " sh", "elif command -v alacritty >/dev/null 2>&1; then", "  alacritty -e docker exec -it " + containerId + " sh", "elif command -v foot >/dev/null 2>&1; then", "  foot -e docker exec -it " + containerId + " sh", "elif command -v wezterm >/dev/null 2>&1; then", "  wezterm start -- docker exec -it " + containerId + " sh", "elif command -v gnome-terminal >/dev/null 2>&1; then", "  gnome-terminal -- docker exec -it " + containerId + " sh", "fi"].join("\n");
        Quickshell.execDetached(["sh", "-c", script]);
    }

    function openInBrowser(port) {
        if (!port)
            return;
        Qt.openUrlExternally("http://localhost:" + port);
    }

    // ── Service toggle via pkexec ──────────────────────────────────────────
    function toggleDockerService(enable) {
        root.isLoading = true;
        serviceToggleProc.command = ["/bin/sh", "-c", enable ? "pkexec /usr/bin/systemctl start docker.service docker.socket" : "pkexec /usr/bin/systemctl stop docker.service docker.socket"];
        serviceToggleProc.running = false;
        serviceToggleProc.running = true;
    }

    Process {
        id: serviceToggleProc
        running: false
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: code => {
            // Give the service time to fully start/stop, then re-check status
            toggleCheckTimer.restart();
        }
    }

    Timer {
        id: toggleCheckTimer
        interval: 2000
        repeat: false
        onTriggered: root.refresh()
    }
}
