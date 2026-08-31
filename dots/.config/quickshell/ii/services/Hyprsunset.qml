pragma Singleton

import QtQuick
import qs.modules.common
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

/**
 * Per-output color controller with automatic night-light mode.
 *
 * hyprsunset exposes one gamma value for the whole compositor. The shell needs
 * brightness/gamma to follow the monitor under the pointer, so the service owns
 * the Hyprland CTM manager and keeps one gamma value per output instead.
 */
Singleton {
    id: root
    signal gammaChangeAttempt()

    readonly property real gammaLowerLimit: 25
    readonly property string targetMonitorName: Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : (Quickshell.screens.length > 0 ? Quickshell.screens[0].name : "")
    property var gammaByMonitor: ({})
    property bool controllerReady: false
    property bool controllerWanted: true

    property string from: (Config.options && Config.options.light && Config.options.light.night && Config.options.light.night.from) ? Config.options.light.night.from : "19:00" 
    property string to: (Config.options && Config.options.light && Config.options.light.night && Config.options.light.night.to) ? Config.options.light.night.to : "06:30"
    property bool automatic: (Config.options && Config.options.light && Config.options.light.night && Config.options.light.night.automatic) && (Config ? Config.ready : true)
    property int colorTemperature: (Config.options && Config.options.light && Config.options.light.night && Config.options.light.night.colorTemperature) ? Config.options.light.night.colorTemperature : 5000
    // `gamma` remains the public API used by existing controls, but now means
    // the value for the monitor currently followed by Hyprland's pointer focus.
    readonly property int gamma: root.gammaForMonitor(root.targetMonitorName)
    property bool shouldBeOn
    property bool firstEvaluation: true
    property bool temperatureActive: false
    property int defaultColorTemperature: 0

    property int fromHour: Number(from.split(":")[0])
    property int fromMinute: Number(from.split(":")[1])
    property int toHour: Number(to.split(":")[0])
    property int toMinute: Number(to.split(":")[1])

    property int clockHour: DateTime.clock.hours
    property int clockMinute: DateTime.clock.minutes

    property var manualActive
    property real manualActiveAt: 0 // Epoch ms of the last manual toggle

    // "never" | "session" | "always" — see Config.options.light.night.persistManual
    readonly property string persistScope: (Config.options && Config.options.light && Config.options.light.night && Config.options.light.night.persistManual) ? Config.options.light.night.persistManual : "always"
    readonly property string _sessionId: Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || ""
    property bool restored: false
    property bool _stateApplied: false // A persisted temperature has been pushed to the daemon

    onClockMinuteChanged: reEvaluate()
    onAutomaticChanged: {
        // Ignore the initial settle of the binding, which happens while Config is still loading
        if (!root.restored)
            return;
        root.manualActive = undefined;
        root.manualActiveAt = 0;
        root.firstEvaluation = true;
        root.persistState();
        if (!root.automatic) {
            root.disableTemperature();
        }
        reEvaluate();
    }

    function inBetween(t, from, to) {
        if (from < to) {
            return (t >= from && t <= to);
        } else {
            // Wrapped around midnight
            return (t >= from || t <= to);
        }
    }

    function minutesOfDay(timestamp) {
        const d = new Date(timestamp);
        return d.getHours() * 60 + d.getMinutes();
    }

    function crossedBoundary(fromMinutes, toMinutes, boundary) {
        if (fromMinutes === toMinutes)
            return false;
        // Walking forward from fromMinutes to toMinutes, possibly wrapping past midnight
        return boundary !== fromMinutes && inBetween(boundary, fromMinutes, toMinutes);
    }

    /**
     * Whether a manual override set at `setAt` (epoch ms) has been overtaken by a
     * schedule boundary since. Only meaningful while automatic mode is on.
     */
    function overrideExpired(setAt) {
        if (!setAt)
            return true;
        const now = Date.now();
        if (now <= setAt)
            return false;
        if (now - setAt >= 24 * 60 * 60 * 1000)
            return true;
        const startMinutes = root.minutesOfDay(setAt);
        const nowMinutes = clockHour * 60 + clockMinute;
        return crossedBoundary(startMinutes, nowMinutes, fromHour * 60 + fromMinute) || crossedBoundary(startMinutes, nowMinutes, toHour * 60 + toMinute);
    }

    function reEvaluate() {
        const t = clockHour * 60 + clockMinute;
        const from = fromHour * 60 + fromMinute;
        const to = toHour * 60 + toMinute;

        // A manual toggle overrides automatic mode only until the next start/end time.
        // With automatic mode off there is no schedule to fall back to, so it never expires.
        if (root.automatic && root.manualActive !== undefined && root.overrideExpired(root.manualActiveAt)) {
            root.manualActive = undefined;
            root.manualActiveAt = 0;
            root.persistState();
        }
        root.shouldBeOn = inBetween(t, from, to);
        if (firstEvaluation) {
            firstEvaluation = false;
            root.ensureState();
        }
    }

    onShouldBeOnChanged: ensureState()
    function ensureState() {
        // console.log("[Hyprsunset] Ensuring state:", root.shouldBeOn, "Automatic mode:", root.automatic);
        if (!root.automatic || root.manualActive !== undefined)
            return;
        if (root.shouldBeOn) {
            root.enableTemperature();
        } else {
            root.disableTemperature();
        }
    }

    function gammaForMonitor(name: string): int {
        const value = root.gammaByMonitor && root.gammaByMonitor[name] !== undefined ? root.gammaByMonitor[name] : undefined;
        return value === undefined ? 100 : Math.max(root.gammaLowerLimit, Math.min(100, Number(value)));
    }

    function gammaForScreen(screen): int {
        return root.gammaForMonitor(screen && screen.name ? screen.name : root.targetMonitorName);
    }

    function sendControllerCommand(command: string): void {
        if (!root.controllerReady || !colorControllerProc.running)
            return;
        colorControllerProc.write(`${command}\n`);
    }

    function syncControllerState(): void {
        root.sendControllerCommand(`temperature ${root.temperatureActive ? root.colorTemperature : root.defaultColorTemperature}`);
        for (const screen of Quickshell.screens) {
            root.sendControllerCommand(`set ${screen.name} ${root.gammaForMonitor(screen.name) / 100}`);
        }
    }

    function startHyprsunset() {
        root.controllerWanted = true;
        if (!colorControllerProc.running)
            colorControllerProc.running = true;
    }

    Process {
        id: colorControllerProc
        command: [Directories.gammaControlScriptPath]
        stdinEnabled: true
        running: true

        stdout: SplitParser {
            onRead: data => {
                if (data.trim() !== "READY")
                    return;
                root.controllerReady = true;
                root.syncControllerState();
            }
        }

        stderr: SplitParser {
            onRead: data => console.warn(`[Hyprsunset] ${data}`)
        }

        onRunningChanged: {
            if (!running)
                root.controllerReady = false;
        }

        onExited: {
            root.controllerReady = false;
            if (root.controllerWanted)
                controllerRestartTimer.restart();
        }
    }

    Timer {
        id: controllerRestartTimer
        interval: 1500
        repeat: false
        onTriggered: root.startHyprsunset()
    }

    Connections {
        target: Quickshell
        ignoreUnknownSignals: true
        function onScreensChanged() {
            if (root.controllerReady)
                root.syncControllerState();
        }
    }

    function load() {
        root.startHyprsunset();
        root.ensureState();
    }

    function enableTemperature() {
        root.temperatureActive = true;

        root.startHyprsunset();
        root.sendControllerCommand(`temperature ${root.colorTemperature}`);
    }

    function disableTemperature() {
        root.temperatureActive = false;
        root.sendControllerCommand(`temperature ${root.defaultColorTemperature}`);
    }

    function applyGammaForMonitor(monitorName: string, gamma, notify): void {
        if (!monitorName)
            return;

        const nextGamma = Math.max(root.gammaLowerLimit, Math.min(100, Number(gamma)));
        const nextValues = Object.assign({}, root.gammaByMonitor);
        nextValues[monitorName] = nextGamma;
        root.gammaByMonitor = nextValues;

        if (notify)
            root.gammaChangeAttempt();

        root.startHyprsunset();
        root.sendControllerCommand(`set ${monitorName} ${nextGamma / 100}`);
    }

    function applyGamma(gamma, notify): void {
        root.applyGammaForMonitor(root.targetMonitorName, gamma, notify);
    }

    function setGammaForMonitor(monitorName: string, gamma): void {
        root.applyGammaForMonitor(monitorName, gamma, true);
        root.persistState();
    }

    function setGamma(gamma): void {
        root.setGammaForMonitor(root.targetMonitorName, gamma);
    }

    function fetchState() {
        root.startHyprsunset();
    }

    function toggleTemperature(active = undefined) {
        if (root.manualActive === undefined) {
            root.manualActive = root.temperatureActive;
        }

        root.manualActive = active !== undefined ? active : !root.manualActive;
        root.manualActiveAt = Date.now();
        if (root.manualActive) {
            root.enableTemperature();
        } else {
            root.disableTemperature();
        }
        root.persistState();
    }

    function persistState() {
        if (!Persistent.ready)
            return;
        Persistent.states.nightLight.hasManual = (root.manualActive !== undefined);
        Persistent.states.nightLight.manualActive = root.manualActive ?? false;
        Persistent.states.nightLight.manualSetAt = root.manualActiveAt;
        Persistent.states.nightLight.gamma = root.gamma;
        Persistent.states.nightLight.gammaByMonitorJson = JSON.stringify(root.gammaByMonitor);
        Persistent.states.nightLight.sessionId = root._sessionId;
    }

    function restoreState() {
        root.restored = true;
        if (root.persistScope === "never")
            return;

        const stored = Persistent.states.nightLight;
        if (root.persistScope === "session" && (stored.sessionId || "") !== root._sessionId)
            return;

        let storedGammaByMonitor = {};
        try {
            storedGammaByMonitor = JSON.parse(stored.gammaByMonitorJson || "{}");
        } catch (error) {
            storedGammaByMonitor = {};
        }

        // Migrate the old single global gamma once, assigning it only to the
        // current target monitor instead of immediately dimming every output.
        if (Object.keys(storedGammaByMonitor).length === 0 && Number(stored.gamma ?? 100) !== 100 && root.targetMonitorName) {
            storedGammaByMonitor[root.targetMonitorName] = Number(stored.gamma);
        }
        root.gammaByMonitor = storedGammaByMonitor;
        root.syncControllerState();

        if (!stored.hasManual)
            return;
        // Don't resurrect an override the schedule has already moved past
        if (root.automatic && root.overrideExpired(stored.manualSetAt))
            return;

        root.manualActive = stored.manualActive;
        root.manualActiveAt = stored.manualSetAt;
        root._stateApplied = true;
        if (root.manualActive) {
            root.enableTemperature();
        } else {
            root.disableTemperature();
        }
    }

    Timer {
        id: restoreTimer
        interval: 0
        repeat: false
        onTriggered: {
            if (root.restored)
                return;
            if (!Persistent.ready || !Config.ready)
                return;
            root.restoreState();
        }
    }

    Connections {
        target: Persistent
        function onReadyChanged() { restoreTimer.restart() }
    }

    Connections {
        target: Config
        function onReadyChanged() { restoreTimer.restart() }
    }

    // Both singletons may already be ready by the time this one loads
    Component.onCompleted: restoreTimer.restart()

    // Change temp
    Connections {
        target: (Config.options && Config.options.light && Config.options.light.night) ? Config.options.light.night : null
        function onColorTemperatureChanged() {
            if (!root.temperatureActive) return;
            root.sendControllerCommand(`temperature ${Config.options.light.night.colorTemperature}`);
        }
    }
}
