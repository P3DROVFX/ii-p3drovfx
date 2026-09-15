pragma Singleton
pragma ComponentBehavior: Bound
import qs.modules.common
import qs
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property bool available: false
    property bool active: false
    property string backendState: "NoState"
    property string nodeName: ""
    property string tailnetName: ""
    property string tailscaleIp4: ""
    property string tailscaleIp6: ""
    property string loginUrl: ""
    property string statusText: Translation.tr("Unavailable")
    property string errorMessage: ""
    property bool loading: false
    property bool enabled: Config.options?.tailscale?.enabled ?? true
    property bool autoConnect: Config.options?.tailscale?.autoConnect ?? false
    property bool stopDaemonWhenDisabled: Config.options?.tailscale?.stopDaemonWhenDisabled ?? true
    property list<var> peers: []
    property list<var> exitNodes: []
    property string currentExitNode: Config.options?.tailscale?.exitNode ?? ""
    property bool acceptDns: Config.options?.tailscale?.acceptDns ?? true
    property bool shieldsUp: Config.options?.tailscale?.shieldsUp ?? false
    property bool sshEnabled: Config.options?.tailscale?.ssh ?? false
    property list<string> advertiseRoutes: Config.options?.tailscale?.advertiseRoutes ?? []
    property bool advertiseExitNode: Config.options?.tailscale?.advertiseExitNode ?? false
    property string permissionState: "unknown"
    property string diagnosticsText: ""
    property var netcheckData: ({})
    property bool netcheckLoading: false
    property string lastPingPeer: ""
    property string lastPingResult: ""
    property bool lastPingSuccess: false
    property int lastExitCode: -1
    property string lastExitStatus: ""
    property string lastErrorOutput: ""
    signal statusUpdated()
    signal loginRequired(string url)
    signal errorOccurred(string message)
    signal peerPingFinished(string peer, bool success, string result)
    readonly property string envPath: Directories.home.toString().replace(/^file:\/\//, "") + "/.local/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    property var operationQueue: []
    property var currentOperation: null
    property bool refreshQueued: false
    property bool autoConnectAttempted: false
    property bool componentReady: false
    property bool daemonOperationPending: false

    onEnabledChanged: { if (!root.componentReady) return; if (root.enabled) { if (root.stopDaemonWhenDisabled) root.requestDaemon("start"); root.refresh() } else { if (root.active) Quickshell.execDetached(["tailscale", "down"]); if (root.stopDaemonWhenDisabled) root.requestDaemon("stop"); root.operationQueue = []; root.currentOperation = null; root.refreshQueued = false; root.resetDisabled() } }
    Component.onCompleted: { root.componentReady = true; root.refresh() }
    Connections { target: Config; function onReadyChanged() { if (Config.ready) { root.autoConnectAttempted = false; root.refresh() } } }

    function enqueue(kind: string, command: list<string>, data: var): void { const q = root.operationQueue.slice(); q.push({ kind: kind, command: command, data: data }); root.operationQueue = q; root.startNext() }
    function startNext(): void { if (root.currentOperation !== null || !root.operationQueue.length) return; const q = root.operationQueue.slice(); root.currentOperation = q.shift(); root.operationQueue = q; commandProc.command = root.currentOperation.command; commandProc.running = true }
    function finishOperation(): void { root.currentOperation = null; root.startNext() }
    function setError(message: string): void { root.operationQueue = []; root.refreshQueued = false; root.errorMessage = message; root.loading = false; root.netcheckLoading = false; root.errorOccurred(message) }
    function resetDisabled(): void { root.available = false; root.active = false; root.backendState = "NoState"; root.peers = []; root.exitNodes = []; root.statusText = Translation.tr("Disabled"); root.loading = false; root.permissionState = "disabled" }
    function refresh(): void {
        if (!root.enabled) {
            root.operationQueue = []
            root.currentOperation = null
            root.refreshQueued = false
            root.resetDisabled()
            return
        }
        if (root.refreshQueued)
            return
        root.refreshQueued = true
        root.loading = true
        root.errorMessage = ""
        root.enqueue("probe", ["which", "tailscale"], null)
    }
    function toggleTailscale(): void {
        if (!root.enabled) {
            root.setError(Translation.tr("Tailscale is disabled in settings"))
            return
        }
        if (root.backendState === "Running")
            root.disconnectTailscale()
        else
            root.connectTailscale()
    }
    function buildUpCommand(): list<string> {
        const args = ["tailscale", root.active ? "set" : "up", "--accept-dns=" + (root.acceptDns ? "true" : "false"), "--shields-up=" + (root.shieldsUp ? "true" : "false"), "--ssh=" + (root.sshEnabled ? "true" : "false")]
        if (root.advertiseRoutes.length) args.push("--advertise-routes=" + root.advertiseRoutes.join(","))
        else if (root.active) args.push("--advertise-routes=")
        if (root.advertiseExitNode) args.push("--advertise-exit-node")
        if (root.currentExitNode) args.push("--exit-node=" + root.currentExitNode)
        else if (root.active) args.push("--exit-node=")
        return args
    }
    function connectTailscale(): void {
        if (!root.available) { root.setError(Translation.tr("Tailscale is unavailable")); return }
        if (root.stopDaemonWhenDisabled)
            Quickshell.execDetached(["pkexec", "systemctl", "start", "tailscaled"])
        root.loading = true
        root.errorMessage = ""
        root.enqueue("up", root.buildUpCommand(), null)
    }
    function disconnectTailscale(): void { if (!root.available) { root.setError(Translation.tr("Tailscale is unavailable")); return } root.loading = true; root.statusText = Translation.tr("Disconnecting…"); root.errorMessage = ""; root.enqueue("down", ["tailscale", "down"], null) }
    function logout(): void { if (!root.available) { root.setError(Translation.tr("Tailscale is unavailable")); return } root.loading = true; root.errorMessage = ""; root.enqueue("logout", ["tailscale", "logout"], null) }
    function openLoginUrl(): void { if (root.loginUrl) Quickshell.execDetached(["xdg-open", root.loginUrl]); else root.setError(Translation.tr("No Tailscale login URL is available")) }
    function setExitNode(nodeNameOrIp: string): void { root.currentExitNode = nodeNameOrIp || ""; if (Config.ready) Config.options.tailscale.exitNode = root.currentExitNode; if (root.backendState === "Running") root.connectTailscale() }
    function netcheck(): void { if (!root.diagnosticsEnabled) { root.setError(Translation.tr("Tailscale diagnostics are disabled")); return } if (!root.available) { root.setError(Translation.tr("Tailscale is unavailable")); return } root.netcheckLoading = true; root.enqueue("netcheck", ["tailscale", "netcheck"], null) }
    function setAcceptDns(value: bool): void { root.acceptDns = value; if (Config.ready) Config.options.tailscale.acceptDns = value; if (root.active) root.connectTailscale() }
    function setShieldsUp(value: bool): void { root.shieldsUp = value; if (Config.ready) Config.options.tailscale.shieldsUp = value; if (root.active) root.connectTailscale() }
    function operationError(stderr: string, fallback: string): string {
        const message = String(stderr || "").trim()
        if (/prefs write access denied|Access denied.*prefs/i.test(message))
            return Translation.tr("Tailscale needs an operator. Run once: sudo tailscale set --operator=$USER")
        return message || fallback
    }
    function requestDaemon(action: string): void {
        if (root.daemonOperationPending) return
        root.daemonOperationPending = true
        daemonProc.command = ["pkexec", "systemctl", action, "tailscaled"]
        daemonProc.running = true
    }
    function setSshEnabled(value: bool): void { root.sshEnabled = value; if (Config.ready) Config.options.tailscale.ssh = value; if (root.active) root.connectTailscale() }
    function setAdvertiseRoutes(routes: list<string>): void { root.advertiseRoutes = routes; if (Config.ready) Config.options.tailscale.advertiseRoutes = routes; if (root.active) root.connectTailscale() }
    function setAdvertiseExitNode(value: bool): void { root.advertiseExitNode = value; if (Config.ready) Config.options.tailscale.advertiseExitNode = value; if (root.active) root.connectTailscale() }
    function pingPeer(peerIp: string, callback: var): void { if (!peerIp || !root.available) return; root.loading = true; root.enqueue("ping", ["tailscale", "ping", "-c", "1", peerIp], { peer: peerIp, callback: callback }) }
    function refreshDiagnostics(): void { root.netcheck() }
    function parseLoginUrl(text: string): string { const match = String(text || "").match(/https?:\/\/[^\s\"']+/); return match ? match[0].replace(/[).,]+$/, "") : "" }
    function parseStatus(out: string, err: string, exitCode: int): void {
        let data = null; const combined = String(out || "").trim()
        try { if (combined) data = JSON.parse(combined) } catch (e) { data = null }
        if (!data) { const url = root.parseLoginUrl(out + "\n" + err); if (url) { root.loginUrl = url; root.backendState = "NeedsLogin"; root.active = false; root.statusText = Translation.tr("Needs Login"); root.permissionState = "needs-login"; root.loginRequired(url) } else if (exitCode !== 0) { root.permissionState = /permission|access denied|root/i.test(err) ? "permission-denied" : "unknown"; root.backendState = "Stopped"; root.active = false; root.statusText = Translation.tr("Status unavailable"); root.errorMessage = err.trim() } return }
        root.backendState = String(data.BackendState || "NoState")
        root.active = root.backendState === "Running"
        root.loginUrl = String(data.AuthURL || "")
        root.nodeName = ""; root.tailnetName = ""; const self = data.Self || {}; root.nodeName = String(self.HostName || ""); root.tailnetName = self.DNSName ? String(self.DNSName).split(".")[1] || "" : ""
        if (root.loginUrl) root.loginRequired(root.loginUrl)
        root.tailscaleIp4 = ""; root.tailscaleIp6 = ""; for (const ip of (self.TailscaleIPs || [])) { if (String(ip).includes(":")) root.tailscaleIp6 = ip; else root.tailscaleIp4 = ip }
        const peersOut = []; const exits = []; let selectedExit = ""
        const peerMap = data.Peer || {}; for (const key in peerMap) { const p = peerMap[key] || {}; const item = { id: p.ID || key, hostname: p.HostName || p.DNSName || "Unknown", ip: p.TailscaleIPs && p.TailscaleIPs.length ? p.TailscaleIPs[0] : "", online: !!p.Online, os: p.OS || "", exitNodeOption: !!p.ExitNodeOption, isExitNode: !!p.ExitNode }; peersOut.push(item); if (item.exitNodeOption) exits.push(item); if (item.isExitNode && item.online) selectedExit = item.hostname }
        const exitStatus = data.ExitNodeStatus || {}; if (exitStatus.Online && (exitStatus.HostName || exitStatus.ID)) selectedExit = exitStatus.HostName || exitStatus.ID
        root.peers = peersOut; root.exitNodes = exits; root.currentExitNode = selectedExit
        if (!selectedExit && Config.ready && Config.options.tailscale.exitNode) Config.options.tailscale.exitNode = ""
        const health = JSON.stringify(data.Health || ""); root.permissionState = /permission|root|access denied/i.test(health) ? "permission-denied" : (root.backendState === "NeedsLogin" ? "needs-login" : "ok")
        if (root.backendState === "Running") root.statusText = root.nodeName || Translation.tr("Connected"); else if (root.backendState === "NeedsLogin") root.statusText = Translation.tr("Needs Login"); else if (root.backendState === "Stopped") root.statusText = Translation.tr("Stopped"); else root.statusText = root.backendState
        root.statusUpdated()
    }

    Process {
        id: commandProc; running: false; environment: ({ "PATH": root.envPath })
        stdout: StdioCollector { id: commandStdout }
        stderr: StdioCollector { id: commandStderr }
        onExited: (exitCode, exitStatus) => {
            const op = root.currentOperation; if (op === null) return; const out = String(commandStdout.text || ""); const err = String(commandStderr.text || ""); const kind = op.kind
            root.lastExitCode = exitCode; root.lastExitStatus = String(exitStatus); root.lastErrorOutput = err.trim()
            if (kind === "probe") { root.available = exitCode === 0 && out.trim().length > 0; if (root.available) root.enqueue("status", ["tailscale", "status", "--json"], null); else { root.backendState = "NoState"; root.statusText = Translation.tr("Unavailable"); root.refreshQueued = false; root.loading = false } }
            else if (kind === "status") { root.parseStatus(out, err, exitCode); if (exitCode !== 0 && root.errorMessage && !root.loginUrl) root.errorOccurred(root.errorMessage); root.enqueue("finish", ["true"], null) }
            else if (kind === "finish") { root.refreshQueued = false; root.loading = false; if (root.autoConnect && !root.autoConnectAttempted && !root.active && root.backendState !== "NeedsLogin") { root.autoConnectAttempted = true; root.connectTailscale() } }
            else if (kind === "down") { if (exitCode !== 0) root.setError(root.operationError(err, Translation.tr("Tailscale down failed"))); else { if (root.stopDaemonWhenDisabled) root.requestDaemon("stop"); else root.refresh() } }
            else if (kind === "logout") { if (exitCode !== 0) root.setError(root.operationError(err, Translation.tr("Tailscale logout failed"))); else { root.loginUrl = ""; root.refresh() } }
            else if (kind === "up") { if (exitCode !== 0) { const url = root.parseLoginUrl(out + "\n" + err); if (url) { root.loginUrl = url; root.loginRequired(url) }; root.setError(root.operationError(err || out, Translation.tr("Tailscale up failed"))) } else root.refresh() }
            else if (kind === "netcheck") { root.netcheckLoading = false; root.diagnosticsText = out.trim() || err.trim(); try { root.netcheckData = JSON.parse(out) } catch (e) { root.netcheckData = ({}) ; if (exitCode !== 0) root.errorMessage = err.trim() || Translation.tr("Netcheck failed") } }
            else if (kind === "ping") { const result = (out.trim() || err.trim()); const ok = exitCode === 0; root.lastPingPeer = op.data.peer; root.lastPingResult = result; root.lastPingSuccess = ok; if (op.data.callback) op.data.callback(ok, result); root.peerPingFinished(op.data.peer, ok, result) }
            root.finishOperation()
            if (kind === "ping" && root.currentOperation === null && root.operationQueue.length === 0) root.loading = false
        }
    }
    Process {
        id: daemonProc
        running: false
        stdout: StdioCollector {}
        stderr: StdioCollector { id: daemonStderr }
        onExited: (exitCode, exitStatus) => {
            root.daemonOperationPending = false
            if (exitCode !== 0) {
                root.setError(daemonStderr.text.trim() || Translation.tr("Unable to change tailscaled service state"))
                return
            }
            root.refresh()
        }
    }
    Timer { id: pollTimer; interval: 12000; repeat: true; running: root.enabled && root.available; onTriggered: if (!root.loading) root.refresh() }
}
