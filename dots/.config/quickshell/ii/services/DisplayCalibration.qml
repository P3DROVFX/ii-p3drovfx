pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "displayCalibration/DisplayCalibrationUtils.js" as CalibrationUtils

/**
 * Hardware color controls addressed by output name.
 *
 * DDC/CI is used for contrast and RGB gain because these controls need a
 * tonal/hardware adjustment rather than another brightness multiplier. Each
 * write includes the I2C bus that belongs to one DRM connector, so changing a
 * monitor never broadcasts the value to the remaining outputs.
 */
Singleton {
    id: root

    property list<CalibrationMonitor> monitors: []
    property list<var> detectedDisplays: []
    property bool detectionComplete: false
    property bool ddcutilAvailable: true
    property bool detectionFailed: false
    property string detectionErrorDetails: ""
    property bool detectAgain: false
    property int topologyGeneration: 0
    property int activeDetectionGeneration: -1

    readonly property bool detecting: detectProcess.running

    function monitorForName(name: string): var {
        return root.monitors.find(monitor => monitor.screen && monitor.screen.name === name) || null;
    }

    function refreshMonitor(name: string): void {
        const monitor = root.monitorForName(name);
        if (monitor)
            monitor.refresh();
    }

    function rebuildMonitors(): void {
        root.topologyGeneration++;

        const previous = Array.from(root.monitors);
        root.monitors = [];
        for (let i = 0; i < previous.length; i++) {
            previous[i].dispose();
            previous[i].destroy();
        }

        const next = [];
        for (let i = 0; i < Quickshell.screens.length; i++) {
            const instance = monitorComponent.createObject(root, {
                screen: Quickshell.screens[i]
            });
            if (instance)
                next.push(instance);
        }
        root.monitors = next;
        root.detect();
    }

    function detect(): void {
        if (detectProcess.running) {
            root.detectAgain = true;
            return;
        }

        root.detectionComplete = false;
        root.detectionFailed = false;
        root.detectAgain = false;
        root.activeDetectionGeneration = root.topologyGeneration;
        // Keep the Process lifecycle deterministic when ddcutil is missing:
        // Quickshell cannot emit a normal exit code for a binary that never
        // starts, while /bin/sh can report 127 to the UI.
        detectProcess.command = ["/bin/sh", "-c", "command -v ddcutil >/dev/null 2>&1 || exit 127; exec ddcutil detect"];
        detectProcess.running = true;
    }

    function applyDetectionResult(text, errorText, exitCode): void {
        if (root.activeDetectionGeneration !== root.topologyGeneration)
            return;

        root.ddcutilAvailable = exitCode !== 127;
        root.detectionFailed = root.ddcutilAvailable && exitCode !== 0;
        root.detectionErrorDetails = root.detectionFailed ? String(errorText || "").trim() : "";
        root.detectedDisplays = CalibrationUtils.parseDetectedDisplays(text);

        for (let i = 0; i < root.monitors.length; i++) {
            const monitor = root.monitors[i];
            const match = root.detectedDisplays.find(display => monitor.screen && display.name === monitor.screen.name);
            monitor.configure(match ? match.busNum : "");
        }

        root.detectionComplete = true;
    }

    Component.onCompleted: root.rebuildMonitors()

    Connections {
        target: Quickshell
        ignoreUnknownSignals: true
        function onScreensChanged(): void {
            root.rebuildMonitors();
        }
    }

    Process {
        id: detectProcess

        stdout: StdioCollector {
            id: detectOutput
        }

        stderr: StdioCollector {
            id: detectErrorOutput
        }

        onExited: exitCode => {
            root.applyDetectionResult(detectOutput.text, detectErrorOutput.text, exitCode);
            if (root.detectAgain || root.activeDetectionGeneration !== root.topologyGeneration)
                Qt.callLater(root.detect);
        }
    }

    component CalibrationMonitor: QtObject {
        id: monitor

        required property ShellScreen screen
        property bool disposed: false
        property int generation: 0
        property string busNum: ""
        property bool isDdc: busNum.length > 0
        property bool ready: false
        property bool probing: false
        property bool refreshPending: false
        property string error: ""

        property bool contrastSupported: false
        property bool redSupported: false
        property bool greenSupported: false
        property bool blueSupported: false

        property int contrast: 0
        property int red: 0
        property int green: 0
        property int blue: 0

        property int contrastMaximum: 0
        property int redMaximum: 0
        property int greenMaximum: 0
        property int blueMaximum: 0

        property var pendingValues: ({})
        property int activeProbeGeneration: -1
        property string activeProbeBus: ""
        property int activeSetGeneration: -1
        property string activeSetBus: ""

        readonly property bool hasColorControls: redSupported || greenSupported || blueSupported
        readonly property bool hasAnyControl: contrastSupported || hasColorControls

        function cancelWork(): void {
            monitor.writeTimer.stop();
            monitor.pendingValues = {};
            monitor.refreshPending = false;
            if (probeProcess.running)
                probeProcess.running = false;
            if (setProcess.running)
                setProcess.running = false;
        }

        function dispose(): void {
            if (monitor.disposed)
                return;
            monitor.disposed = true;
            monitor.generation++;
            monitor.cancelWork();
        }

        function configure(nextBusNum: string): void {
            if (monitor.disposed)
                return;
            if (monitor.busNum === nextBusNum && monitor.ready)
                return;

            monitor.generation++;
            monitor.cancelWork();
            monitor.busNum = nextBusNum;
            monitor.ready = false;
            monitor.probing = false;
            monitor.error = "";
            monitor.contrastSupported = false;
            monitor.redSupported = false;
            monitor.greenSupported = false;
            monitor.blueSupported = false;

            if (monitor.isDdc)
                Qt.callLater(monitor.refresh);
        }

        function refresh(): void {
            if (monitor.disposed || !monitor.isDdc)
                return;
            if (setProcess.running || Object.keys(monitor.pendingValues).length > 0) {
                monitor.refreshPending = true;
                return;
            }
            if (probeProcess.running) {
                monitor.refreshPending = true;
                return;
            }

            monitor.probing = true;
            monitor.error = "";
            monitor.activeProbeGeneration = monitor.generation;
            monitor.activeProbeBus = monitor.busNum;
            probeProcess.command = ["ddcutil", "-b", monitor.busNum, "getvcp", "12", "16", "18", "1A", "--brief"];
            probeProcess.running = true;
        }

        function applyProbeResult(text, exitCode): void {
            if (monitor.disposed || !CalibrationUtils.operationMatches(monitor.activeProbeGeneration, monitor.activeProbeBus, monitor.generation, monitor.busNum))
                return;

            const values = CalibrationUtils.parseVcpValues(text);
            const contrastValue = values["12"];
            const redValue = values["16"];
            const greenValue = values["18"];
            const blueValue = values["1A"];

            monitor.contrastSupported = contrastValue !== undefined;
            monitor.redSupported = redValue !== undefined;
            monitor.greenSupported = greenValue !== undefined;
            monitor.blueSupported = blueValue !== undefined;

            if (contrastValue) {
                monitor.contrastMaximum = contrastValue.maximum;
                monitor.contrast = CalibrationUtils.percentForValue(contrastValue.current, contrastValue.maximum);
            }
            if (redValue) {
                monitor.redMaximum = redValue.maximum;
                monitor.red = CalibrationUtils.percentForValue(redValue.current, redValue.maximum);
            }
            if (greenValue) {
                monitor.greenMaximum = greenValue.maximum;
                monitor.green = CalibrationUtils.percentForValue(greenValue.current, greenValue.maximum);
            }
            if (blueValue) {
                monitor.blueMaximum = blueValue.maximum;
                monitor.blue = CalibrationUtils.percentForValue(blueValue.current, blueValue.maximum);
            }

            monitor.probing = false;
            monitor.ready = true;
            monitor.error = monitor.hasAnyControl ? "" : (exitCode === 0 ? "unsupported" : "readFailed");
        }

        function queueValue(code: string, percent, maximum): void {
            if (monitor.disposed || !monitor.isDdc || maximum <= 0)
                return;

            const nextValues = Object.assign({}, monitor.pendingValues);
            nextValues[code] = CalibrationUtils.rawValueForPercent(percent, maximum);
            monitor.pendingValues = nextValues;
            monitor.error = "";
            writeTimer.restart();
        }

        function setContrast(value): void {
            const bounded = Math.max(0, Math.min(100, Math.round(Number(value))));
            if (!monitor.contrastSupported || bounded === monitor.contrast)
                return;
            monitor.contrast = bounded;
            monitor.queueValue("12", bounded, monitor.contrastMaximum);
        }

        function setRed(value): void {
            const bounded = Math.max(0, Math.min(100, Math.round(Number(value))));
            if (!monitor.redSupported || bounded === monitor.red)
                return;
            monitor.red = bounded;
            monitor.queueValue("16", bounded, monitor.redMaximum);
        }

        function setGreen(value): void {
            const bounded = Math.max(0, Math.min(100, Math.round(Number(value))));
            if (!monitor.greenSupported || bounded === monitor.green)
                return;
            monitor.green = bounded;
            monitor.queueValue("18", bounded, monitor.greenMaximum);
        }

        function setBlue(value): void {
            const bounded = Math.max(0, Math.min(100, Math.round(Number(value))));
            if (!monitor.blueSupported || bounded === monitor.blue)
                return;
            monitor.blue = bounded;
            monitor.queueValue("1A", bounded, monitor.blueMaximum);
        }

        function flushPending(): void {
            if (monitor.disposed)
                return;
            if (setProcess.running) {
                writeTimer.restart();
                return;
            }
            if (!monitor.isDdc || Object.keys(monitor.pendingValues).length === 0)
                return;

            const values = Object.assign({}, monitor.pendingValues);
            monitor.pendingValues = {};
            monitor.activeSetGeneration = monitor.generation;
            monitor.activeSetBus = monitor.busNum;
            setProcess.command = CalibrationUtils.buildSetCommand(monitor.busNum, values);
            setProcess.running = true;
        }

        function finishDeferredRefresh(): void {
            if (monitor.disposed || !monitor.refreshPending || probeProcess.running || setProcess.running)
                return;
            monitor.refreshPending = false;
            Qt.callLater(monitor.refresh);
        }

        readonly property Timer writeTimer: Timer {
            interval: 300
            repeat: false
            onTriggered: monitor.flushPending()
        }

        readonly property Process probeProcess: Process {
            stdout: StdioCollector {
                id: probeOutput
            }

            onExited: exitCode => {
                monitor.applyProbeResult(probeOutput.text, exitCode);
                monitor.finishDeferredRefresh();
            }
        }

        readonly property Process setProcess: Process {
            onExited: exitCode => {
                const isCurrent = !monitor.disposed
                    && CalibrationUtils.operationMatches(monitor.activeSetGeneration, monitor.activeSetBus, monitor.generation, monitor.busNum);
                if (isCurrent)
                    monitor.error = exitCode === 0 ? "" : "writeFailed";
                if (isCurrent && Object.keys(monitor.pendingValues).length > 0)
                    monitor.writeTimer.restart();
                else
                    monitor.finishDeferredRefresh();
            }
        }
    }

    Component {
        id: monitorComponent
        CalibrationMonitor {}
    }
}
