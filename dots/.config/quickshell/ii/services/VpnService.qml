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
    property string activeProfile: ""
    property string activeProvider: ""
    property string statusText: Translation.tr("Disconnected")
    property string errorMessage: ""
    property bool loading: false
    property bool operationPending: false
    property bool pendingTargetActive: false
    readonly property bool displayActive: root.operationPending ? root.pendingTargetActive : root.active
    property bool enabled: Config.options?.vpn?.enabled ?? true
    property string recentProvider: Config.options?.vpn?.recentProvider ?? "networkmanager"
    property bool autoConnect: Config.options?.vpn?.autoConnect ?? false
    property string defaultProvider: Config.options?.vpn?.defaultProvider ?? Config.options?.vpn?.backend ?? "networkmanager"
    property string defaultLocation: Config.options?.vpn?.defaultLocation ?? ""
    property bool killSwitch: Config.options?.vpn?.killSwitch ?? false
    property bool blockLan: Config.options?.vpn?.blockLan ?? false
    property bool diagnosticsEnabled: Config.options?.vpn?.enableDiagnostics ?? true
    readonly property bool killSwitchSupported: false
    readonly property bool blockLanSupported: false
    readonly property var safetyCapabilities: ({ killSwitch: { supported: false, configured: root.killSwitch }, blockLan: { supported: false, configured: root.blockLan } })
    property string diagnosticsText: ""
    property list<var> profiles: []
    property list<var> activeProfiles: []
    property list<string> availableProviders: []
    property var providerCapabilities: ({})
    property var providerDiagnostics: ({})
    property string lastErrorOutput: ""
    property int lastExitCode: -1
    property string lastExitStatus: ""
    property bool nordvpnAvailable: false
    property string nordvpnStatus: Translation.tr("Unavailable")
    property string nordvpnLocation: ""
    property bool protonvpnAvailable: false
    property string protonvpnStatus: Translation.tr("Unavailable")
    property string protonvpnLocation: ""
    signal vpnConnected(string profileName)
    signal vpnDisconnected()
    signal errorOccurred(string message)
    readonly property string envPath: Directories.home.toString().replace(/^file:\/\//, "") + "/.local/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    property var operationQueue: []
    property var currentOperation: null
    property bool refreshQueued: false
    property bool autoConnectAttempted: false
    property string importPath: ""
    property bool componentReady: false
    onEnabledChanged: { if (!root.componentReady) return; if (root.enabled) root.refresh(); else { if (Config.options?.vpn?.disconnectOnDisable && root.active) root.disconnectOnDisableNow(); root.operationQueue = []; root.currentOperation = null; root.refreshQueued = false; root.resetDisabled() } }

    Component.onCompleted: { root.componentReady = true; root.refresh() }
    Connections { target: Config; function onReadyChanged() { if (Config.ready) { root.autoConnectAttempted = false; root.refresh() } } }

    function parseNmcliLine(line: string): list<string> {
        const fields = []; let field = ""; let escaped = false
        for (let i = 0; i < line.length; ++i) {
            const c = line[i]
            if (escaped) { field += c === "n" ? "\n" : c; escaped = false }
            else if (c === "\\") escaped = true
            else if (c === ":") { fields.push(field); field = "" }
            else field += c
        }
        if (escaped) field += "\\"
        fields.push(field)
        return fields
    }
    function parseNmcli(text: string, fields: int): list<var> {
        const out = []; for (const line of String(text || "").split(/\r?\n/)) { if (!line.trim()) continue; const row = root.parseNmcliLine(line); if (row.length >= fields) out.push(row) } return out
    }
    function enqueue(kind: string, command: list<string>, data: var): void { const q = root.operationQueue.slice(); q.push({ kind: kind, command: command, data: data }); root.operationQueue = q; root.startNext() }
    function startNext(): void { if (root.currentOperation !== null || root.operationQueue.length === 0) return; const q = root.operationQueue.slice(); root.currentOperation = q.shift(); root.operationQueue = q; commandProc.command = root.currentOperation.command; commandProc.running = true }
    function finishOperation(): void { root.currentOperation = null; root.startNext() }
    function setError(message: string): void { root.operationQueue = []; root.refreshQueued = false; root.operationPending = false; root.errorMessage = message; root.loading = false; root.errorOccurred(message) }
    function resetDisabled(): void { root.available = false; root.active = false; root.activeProfile = ""; root.activeProvider = ""; root.profiles = []; root.activeProfiles = []; root.availableProviders = []; root.nordvpnAvailable = false; root.protonvpnAvailable = false; root.statusText = Translation.tr("Disabled"); root.loading = false }
    function refresh(): void { if (!root.enabled) { root.operationQueue = []; root.currentOperation = null; root.refreshQueued = false; root.resetDisabled(); return } if (root.refreshQueued) return; root.refreshQueued = true; root.loading = true; root.errorMessage = ""; root.enqueue("probeNmcli", ["which", "nmcli"], null) }
    function toggleVpn(): void {
        if (!root.enabled) {
            root.setError(Translation.tr("VPN is disabled in settings"))
            return
        }
        if (root.displayActive || root.active)
            root.disconnectVpn()
        else
            root.connectDefault()
    }
    function connectDefault(): void {
        const provider = String(Config.options?.vpn?.recentProvider || Config.options?.vpn?.defaultProvider || Config.options?.vpn?.backend || "networkmanager").toLowerCase(); const location = String(Config.options?.vpn?.defaultLocation || "")
        if (provider === "nordvpn" || provider === "protonvpn") { root.connectProvider(provider, location); return }
        const profile = String(Config.options?.vpn?.defaultProfile || ""); if (profile) { root.connectProfile(profile); return }
        if (location) for (const item of root.profiles) if (String(item.name).toLowerCase().includes(location.toLowerCase())) { root.connectProfile(item.name); return }
        if (root.profiles.length) root.connectProfile(root.profiles[0].name); else root.setError(Translation.tr("No VPN profile configured"))
    }
    function connectProfile(profileName: string): void { if (!profileName || !root.available) { root.setError(Translation.tr("NetworkManager VPN is unavailable")); return } root.recentProvider = "networkmanager"; if (Config.ready) Config.options.vpn.recentProvider = "networkmanager"; root.operationPending = true; root.pendingTargetActive = true; root.loading = true; root.errorMessage = ""; root.enqueue("connect", ["nmcli", "connection", "up", "id", profileName], { profile: profileName, provider: "networkmanager" }) }
    function connectProvider(provider: string, location: string): void { const p = provider.toLowerCase(); if (p !== "nordvpn" && p !== "protonvpn") { root.connectDefault(); return } if ((p === "nordvpn" && !root.nordvpnAvailable) || (p === "protonvpn" && !root.protonvpnAvailable)) { root.setError(Translation.tr("VPN provider is unavailable: %1").arg(provider)); return } const executable = p === "nordvpn" ? "nordvpn" : "protonvpn"; const command = [executable, "connect"]; if (location && location.trim()) command.push("--country", location.trim()); root.recentProvider = p; if (Config.ready) Config.options.vpn.recentProvider = p; root.operationPending = true; root.pendingTargetActive = true; root.loading = true; root.errorMessage = ""; root.enqueue("connect", command, { profile: location || provider, provider: p }) }
    function disconnectVpn(): void {
        if (!root.active && !root.activeProfiles.length) return
        root.operationPending = true; root.pendingTargetActive = false; root.loading = true; root.errorMessage = ""
        if (root.activeProvider === "nordvpn" && root.nordvpnAvailable) root.enqueue("disconnect", ["nordvpn", "disconnect"], { provider: "nordvpn", refresh: true })
        else if (root.activeProvider === "protonvpn" && root.protonvpnAvailable) root.enqueue("disconnect", ["protonvpn", "disconnect"], { provider: "protonvpn", refresh: true })
        else { const names = root.activeProfiles.length ? root.activeProfiles.slice() : (root.activeProfile ? [root.activeProfile] : []); if (!names.length) { root.setError(Translation.tr("No active VPN connection found")); return } for (let i = 0; i < names.length; ++i) root.enqueue("disconnect", ["nmcli", "connection", "down", "id", names[i]], { provider: "networkmanager", refresh: i === names.length - 1 }) }
    }
    function cleanImportPath(filePath: string): string { let path = String(filePath || "").replace(/^file:\/\//, ""); try { if (path.indexOf("%") >= 0) path = decodeURIComponent(path) } catch (e) {} return path }
    function disconnectOnDisableNow(): void {
        if (root.activeProvider === "nordvpn") Quickshell.execDetached(["nordvpn", "disconnect"])
        else if (root.activeProvider === "protonvpn") Quickshell.execDetached(["protonvpn", "disconnect"])
        else if (root.activeProfile) Quickshell.execDetached(["nmcli", "connection", "down", "id", root.activeProfile])
    }
    function importProfile(filePath: string): void { if (!filePath || !filePath.trim()) return; root.importPath = root.cleanImportPath(filePath); root.loading = true; root.errorMessage = ""; root.enqueue("readImport", ["cat", "--", root.importPath], null) }
    property bool filePickerLoading: false
    function openFilePicker(): void {
        if (root.filePickerLoading) return
        root.filePickerLoading = true
        filePickerProc.running = false
        filePickerProc.running = true
    }
    function detectImportType(content: string, path: string): string { const p = path.toLowerCase(); if (p.endsWith(".ovpn") || p.endsWith(".ovpn3")) return "openvpn"; if (/^\s*\[Interface\]\s*$/im.test(content) && /^\s*\[Peer\]\s*$/im.test(content)) return "wireguard"; if (/^\s*(client|remote|dev\s+tun|proto\s+)/im.test(content)) return "openvpn"; return "" }
    function deleteProfile(profileName: string): void { if (!profileName || !root.available) return; root.loading = true; root.enqueue("delete", ["nmcli", "connection", "delete", "id", profileName], null) }
    function runDiagnostics(): void { if (!root.diagnosticsEnabled) { root.setError(Translation.tr("VPN diagnostics are disabled in settings")); return } root.diagnosticsText = JSON.stringify({ available: root.available, active: root.active, provider: root.activeProvider, exitCode: root.lastExitCode, error: root.lastErrorOutput }); root.refresh() }
    function parseProviderStatus(text: string): var { let connected = false; let location = ""; for (const raw of String(text || "").split(/\r?\n/)) { const line = raw.trim(); const low = line.toLowerCase(); if (low.includes("status") && low.includes("connected") && !low.includes("disconnected")) connected = true; if (low.startsWith("country:") || low.startsWith("city:") || low.startsWith("server:") || low.startsWith("current server:")) { const value = line.substring(line.indexOf(":") + 1).trim(); if (value) location = location ? location + ", " + value : value } } return { connected: connected, status: connected ? (location || Translation.tr("Connected")) : Translation.tr("Disconnected"), location: location } }
    function parseActive(text: string): void { const names = []; let first = ""; for (const row of root.parseNmcli(text, 3)) { const type = String(row[1]).toLowerCase(); if (type.includes("vpn") || type.includes("wireguard") || type === "tun") { names.push(row[0]); if (!first) first = row[0] } } root.activeProfiles = names; if (names.length) { root.active = true; root.activeProfile = first; root.activeProvider = "networkmanager"; root.statusText = first } else if (!root.nordvpnAvailable || root.nordvpnStatus === Translation.tr("Disconnected")) { root.active = false; root.activeProfile = ""; if (!root.protonvpnAvailable || root.protonvpnStatus === Translation.tr("Disconnected")) { root.activeProvider = ""; root.statusText = Translation.tr("Disconnected") } } }

    function normalizeProviderState(): void { if (root.activeProvider === "nordvpn" && root.nordvpnStatus === Translation.tr("Disconnected")) { root.active = false; root.activeProvider = ""; root.activeProfile = ""; root.statusText = Translation.tr("Disconnected") } else if (root.activeProvider === "protonvpn" && root.protonvpnStatus === Translation.tr("Disconnected")) { root.active = false; root.activeProvider = ""; root.activeProfile = ""; root.statusText = Translation.tr("Disconnected") } }
    Process {
        id: commandProc; running: false; environment: ({ "PATH": root.envPath })
        stdout: StdioCollector { id: commandStdout }
        stderr: StdioCollector { id: commandStderr }
        onExited: (exitCode, exitStatus) => {
            const op = root.currentOperation; if (op === null) return; const out = String(commandStdout.text || ""); const err = String(commandStderr.text || ""); const kind = op.kind
            root.lastExitCode = exitCode; root.lastExitStatus = String(exitStatus); root.lastErrorOutput = err.trim()
            if (kind === "probeNmcli") { root.available = exitCode === 0 && out.trim().length > 0; root.availableProviders = root.available ? ["networkmanager"] : []; root.enqueue("probeNord", ["which", "nordvpn"], null) }
            else if (kind === "probeNord") { root.nordvpnAvailable = exitCode === 0 && out.trim().length > 0; if (root.nordvpnAvailable) root.availableProviders = root.availableProviders.concat(["nordvpn"]); root.enqueue("probeProton", ["which", "protonvpn"], null) }
            else if (kind === "probeProton") { root.protonvpnAvailable = exitCode === 0 && out.trim().length > 0; if (root.protonvpnAvailable) root.availableProviders = root.availableProviders.concat(["protonvpn"]); root.providerCapabilities = { networkmanager: { status: root.available, connect: root.available, disconnect: root.available, location: root.available }, nordvpn: { status: root.nordvpnAvailable, connect: root.nordvpnAvailable, disconnect: root.nordvpnAvailable, location: root.nordvpnAvailable }, protonvpn: { status: root.protonvpnAvailable, connect: root.protonvpnAvailable, disconnect: root.protonvpnAvailable, location: root.protonvpnAvailable } }; if (root.available) { root.enqueue("profiles", ["nmcli", "-t", "--escape", "yes", "-f", "NAME,TYPE,UUID", "connection", "show"], null); root.enqueue("active", ["nmcli", "-t", "--escape", "yes", "-f", "NAME,TYPE,DEVICE", "connection", "show", "--active"], null) } if (root.nordvpnAvailable) root.enqueue("nordStatus", ["nordvpn", "status"], null); if (root.protonvpnAvailable) root.enqueue("protonStatus", ["protonvpn", "status"], null); root.enqueue("finishRefresh", ["true"], null) }
            else if (kind === "profiles") { const result = []; for (const row of root.parseNmcli(out, 3)) { const type = String(row[1]).toLowerCase(); if (type.includes("vpn") || type.includes("wireguard") || type === "tun") result.push({ name: row[0], type: row[1], uuid: row[2] || "" }) } root.profiles = result }
            else if (kind === "finishRefresh") { root.normalizeProviderState(); root.operationPending = false; root.refreshQueued = false; root.loading = false; if (!root.available && !root.nordvpnAvailable && !root.protonvpnAvailable) root.statusText = Translation.tr("No VPN backend found"); if (root.autoConnect && !root.autoConnectAttempted && !root.active) { root.autoConnectAttempted = true; root.connectDefault() } }
            else if (kind === "nordStatus") { const p = root.parseProviderStatus(out); root.nordvpnStatus = p.status; root.nordvpnLocation = p.location; root.providerDiagnostics = Object.assign({}, root.providerDiagnostics, { nordvpn: { exitCode: exitCode, stderr: err.trim() } }); if (p.connected && !root.activeProfiles.length) { root.active = true; root.activeProvider = "nordvpn"; root.activeProfile = p.location; root.statusText = p.status } }
            else if (kind === "protonStatus") { const p = root.parseProviderStatus(out); root.protonvpnStatus = p.status; root.protonvpnLocation = p.location; root.providerDiagnostics = Object.assign({}, root.providerDiagnostics, { protonvpn: { exitCode: exitCode, stderr: err.trim() } }); if (p.connected && !root.active && !root.activeProfiles.length) { root.active = true; root.activeProvider = "protonvpn"; root.activeProfile = p.location; root.statusText = p.status } }
            else if (kind === "readImport") { if (exitCode !== 0) root.setError(err.trim() || Translation.tr("Unable to read VPN profile")); else { const type = root.detectImportType(out, root.importPath); if (!type) root.setError(Translation.tr("Could not identify profile as OpenVPN or WireGuard")); else root.enqueue("import", ["nmcli", "connection", "import", "type", type, "file", root.importPath], { type: type }) } }
            else if (kind === "import") { if (exitCode !== 0) root.setError(err.trim() || Translation.tr("Failed to import VPN profile")); else root.refresh() }
            else if (kind === "connect") { if (exitCode !== 0) root.setError(err.trim() || Translation.tr("VPN connection failed")); else { root.vpnConnected(op.data.profile || ""); root.refresh() } }
            else if (kind === "disconnect") { if (exitCode !== 0) root.setError(err.trim() || Translation.tr("VPN disconnect failed")); else { root.vpnDisconnected(); if (op.data.refresh) root.refresh() } }
            else if (kind === "delete") { if (exitCode !== 0) root.setError(err.trim() || Translation.tr("Failed to delete VPN profile")); else root.refresh() }
            root.finishOperation()
        }
    }
    Timer { id: pollTimer; interval: 10000; repeat: true; running: root.enabled && root.availableProviders.length > 0; onTriggered: if (!root.loading) root.refresh() }
    Process {
        id: filePickerProc
        running: false
        command: ["bash", "-lc", "if command -v kdialog >/dev/null 2>&1; then kdialog --getopenfilename \"$HOME\" '*.ovpn *.conf' 2>/dev/null; elif command -v zenity >/dev/null 2>&1; then zenity --file-selection --file-filter='VPN profiles | *.ovpn *.conf' 2>/dev/null; fi"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.filePickerLoading = false
                const selected = String(this.text || "").trim()
                if (selected.length > 0)
                    root.importProfile(selected)
            }
        }
        onExited: {
            if (!root.filePickerLoading) return
            root.filePickerLoading = false
        }
    }
}

