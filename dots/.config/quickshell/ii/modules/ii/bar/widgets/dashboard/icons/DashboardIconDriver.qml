pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.models.hyprland

/**
 * Turns real service state into icon cues.
 *
 * There are three dashboard buttons (expressive, default, vertical) showing the
 * same indicators, so the mapping from "bluetooth just connected" to "play the
 * connected cue" lives here once. Each button hands the driver the icons it
 * actually built; anything it left out stays null and is skipped.
 *
 * The settings page fires the very same cues through DashboardIconCues, so the
 * test buttons exercise this path rather than a parallel one.
 */
Item {
    id: root

    property Item wifiIcon: null
    property Item bluetoothIcon: null
    property Item volumeIcon: null
    property Item micIcon: null
    property Item notificationIcon: null
    property Item caffeineIcon: null
    property Item vpnIcon: null
    property Item tailscaleIcon: null
    property Item pomodoroIcon: null
    property Item stopwatchIcon: null
    property Item easyEffectsIcon: null
    property Item dnsIcon: null
    property Item gameModeIcon: null
    property Item songRecIcon: null
    property Item alarmIcon: null
    property Item countdownIcon: null

    visible: false

    // Every binding below evaluates once at load. Without this gate the bar
    // would play half a dozen animations at startup for states that never
    // changed.
    property bool driverReady: false

    Timer {
        running: true
        interval: 1400
        repeat: false
        onTriggered: {
            root.refreshCountdownState(false);
            root.driverReady = true;
        }
    }

    // ── Wi-Fi ───────────────────────────────────────────────────────────────
    readonly property string wifiCue: {
        if (Network.ethernet)
            return "wired";
        switch (Network.wifiStatus) {
        case "connected":
            return "connected";
        case "connecting":
            return "searching";
        case "disabled":
            return "disabled";
        default:
            return "disconnected";
        }
    }
    onWifiCueChanged: {
        if (root.driverReady && root.wifiIcon && root.wifiCue !== "wired")
            root.wifiIcon.play(root.wifiCue);
    }

    // ── Bluetooth ───────────────────────────────────────────────────────────
    readonly property string bluetoothCue: {
        if (!BluetoothStatus.enabled)
            return "disabled";
        if (BluetoothStatus.connected)
            return "connected";
        if (BluetoothStatus.discovering)
            return "scanning";
        return "idle";
    }
    property string previousBluetoothCue: "idle"
    onBluetoothCueChanged: {
        const previous = root.previousBluetoothCue;
        root.previousBluetoothCue = root.bluetoothCue;
        if (!root.driverReady || !root.bluetoothIcon)
            return;
        if (root.bluetoothCue === "idle") {
            // Leaving "connected" is a device walking away, and leaving
            // "disabled" is the adapter coming back — both are events. A scan
            // merely ending is not, so that one just settles.
            if (previous === "connected")
                root.bluetoothIcon.play("disconnected");
            else if (previous === "disabled")
                root.bluetoothIcon.play("enabled");
            else
                root.bluetoothIcon.play("settle");
            return;
        }
        root.bluetoothIcon.play(root.bluetoothCue);
    }

    // ── Volume ──────────────────────────────────────────────────────────────
    //
    // Audio state is pushed, not bound. A declarative binding that reaches
    // `Audio.sink.audio.volume` throws while a PipeWire node exists with its
    // channel volumes still unpopulated, and a binding that throws evaluates to
    // undefined — which lands on a typed `real` as "Unable to assign
    // [undefined] to double" on every reload, no matter how it is guarded.
    property real sinkVolume: 0
    property bool sinkMuted: false
    property real previousSinkVolume: 0

    function refreshSinkState(): void {
        let volume = 0;
        let muted = false;
        try {
            const audio = Audio.sink ? Audio.sink.audio : null;
            if (audio) {
                muted = audio.muted === true;
                const value = audio.volume;
                if (typeof value === "number" && !isNaN(value))
                    volume = value;
            }
        } catch (error) {
            // The node is not ready yet; the defaults above stand.
        }
        root.sinkMuted = muted;
        root.sinkVolume = volume;
        if (root.volumeIcon)
            root.volumeIcon.waves = muted ? 0 : (volume > 0.45 ? 2 : 1);
    }

    onSinkMutedChanged: {
        if (root.driverReady && root.volumeIcon)
            root.volumeIcon.play(root.sinkMuted ? "mute" : "unmute");
    }

    onSinkVolumeChanged: {
        const previous = root.previousSinkVolume;
        root.previousSinkVolume = root.sinkVolume;
        if (!root.driverReady || root.sinkMuted || !root.volumeIcon)
            return;
        // Ignore the noise a slider produces while it is being dragged.
        if (Math.abs(root.sinkVolume - previous) < 0.005)
            return;
        root.volumeIcon.play(root.sinkVolume > previous ? "up" : "down");
    }

    Connections {
        target: Audio
        function onSinkChanged() {
            root.refreshSinkState();
        }
    }

    Connections {
        target: {
            const sink = Audio.sink;
            return sink ? sink.audio : null;
        }
        ignoreUnknownSignals: true
        function onVolumeChanged() {
            root.refreshSinkState();
        }
        function onMutedChanged() {
            root.refreshSinkState();
        }
    }

    Component.onCompleted: root.refreshSinkState()

    // ── Microphone ──────────────────────────────────────────────────────────
    readonly property bool sourceMuted: {
        const audio = Audio.source ? Audio.source.audio : null;
        return audio ? audio.muted === true : false;
    }
    onSourceMutedChanged: {
        if (root.driverReady && root.micIcon)
            root.micIcon.play(root.sourceMuted ? "mute" : "unmute");
    }

    // ── Keep awake ──────────────────────────────────────────────────────────
    readonly property bool caffeineOn: Idle.inhibit ?? false
    onCaffeineOnChanged: {
        if (root.driverReady && root.caffeineIcon)
            root.caffeineIcon.play(root.caffeineOn ? "on" : "off");
    }

    // ── VPN ─────────────────────────────────────────────────────────────────
    readonly property bool vpnOn: VpnService.active
    onVpnOnChanged: {
        if (root.driverReady && root.vpnIcon)
            root.vpnIcon.play(root.vpnOn ? "connected" : "disconnected");
    }

    // ── Tailscale ───────────────────────────────────────────────────────────
    readonly property bool tailscaleOn: TailscaleService.active
    onTailscaleOnChanged: {
        if (root.driverReady && root.tailscaleIcon)
            root.tailscaleIcon.play(root.tailscaleOn ? "connected" : "disconnected");
    }

    // ── Pomodoro ────────────────────────────────────────────────────────────
    readonly property bool pomodoroRunning: TimerService.pomodoroRunning
    onPomodoroRunningChanged: {
        if (root.driverReady && root.pomodoroIcon)
            root.pomodoroIcon.play(root.pomodoroRunning ? "start" : "pause");
    }

    // A lap boundary is the event worth animating, not the seconds ticking.
    readonly property bool pomodoroBreak: TimerService.pomodoroBreak
    onPomodoroBreakChanged: {
        if (root.driverReady && root.pomodoroIcon)
            root.pomodoroIcon.play("complete");
    }

    // ── Stopwatch ───────────────────────────────────────────────────────────
    readonly property bool stopwatchRunning: TimerService.stopwatchRunning
    onStopwatchRunningChanged: {
        if (root.driverReady && root.stopwatchIcon)
            root.stopwatchIcon.play(root.stopwatchRunning ? "start" : "stop");
    }

    readonly property int stopwatchLapCount: (TimerService.stopwatchLaps ?? []).length
    property int previousLapCount: 0
    onStopwatchLapCountChanged: {
        const previous = root.previousLapCount;
        root.previousLapCount = root.stopwatchLapCount;
        if (!root.driverReady || !root.stopwatchIcon)
            return;
        root.stopwatchIcon.play(root.stopwatchLapCount > previous ? "lap" : "reset");
    }

    // ── Countdown timers ───────────────────────────────────────────────────
    // TimerService replaces the persisted list for every transition. Comparing
    // aggregate counts lets one handler distinguish create, pause, resume,
    // complete and remove without polling the individual timer objects.
    readonly property var countdownItems: Array.from(TimerService.countdowns ?? [])
    readonly property int countdownCount: root.countdownItems.length
    readonly property int countdownRunningCount: root.countdownItems.filter(item => !item?.paused && !item?.notified).length
    readonly property int countdownPausedCount: root.countdownItems.filter(item => item?.paused && !item?.notified).length
    readonly property int countdownFinishedCount: root.countdownItems.filter(item => item?.notified).length
    readonly property bool countdownRunning: root.countdownRunningCount > 0
    readonly property bool countdownPaused: !root.countdownRunning && root.countdownPausedCount > 0
    readonly property bool countdownFinished: !root.countdownRunning && !root.countdownPaused && root.countdownFinishedCount > 0

    property int previousCountdownCount: 0
    property int previousCountdownRunningCount: 0
    property int previousCountdownPausedCount: 0
    property int previousCountdownFinishedCount: 0
    property bool countdownVisible: root.countdownCount > 0

    Timer {
        id: countdownHideTimer
        interval: 720
        repeat: false
        onTriggered: root.countdownVisible = root.countdownCount > 0
    }

    function refreshCountdownState(allowCue = true): void {
        const count = root.countdownCount;
        const running = root.countdownRunningCount;
        const paused = root.countdownPausedCount;
        const finished = root.countdownFinishedCount;
        const previousCount = root.previousCountdownCount;
        const previousRunning = root.previousCountdownRunningCount;
        const previousPaused = root.previousCountdownPausedCount;
        const previousFinished = root.previousCountdownFinishedCount;

        root.previousCountdownCount = count;
        root.previousCountdownRunningCount = running;
        root.previousCountdownPausedCount = paused;
        root.previousCountdownFinishedCount = finished;

        if (count > 0) {
            countdownHideTimer.stop();
            root.countdownVisible = true;
        } else if (previousCount > 0) {
            // removedAnim closes the hourglass before the Revealer takes its
            // space away; hiding immediately would cut that gesture in half.
            root.countdownVisible = true;
            countdownHideTimer.restart();
        } else {
            root.countdownVisible = false;
        }

        if (!allowCue || !root.driverReady || !root.countdownIcon)
            return;

        if (count > previousCount)
            root.countdownIcon.play("start");
        else if (count < previousCount)
            root.countdownIcon.play("removed");
        else if (finished > previousFinished)
            root.countdownIcon.play("complete");
        else if (paused > previousPaused)
            root.countdownIcon.play("pause");
        else if (running > previousRunning)
            root.countdownIcon.play("resume");
    }

    onCountdownItemsChanged: root.refreshCountdownState()

    // ── EasyEffects ─────────────────────────────────────────────────────────
    readonly property bool easyEffectsActive: EasyEffects.active
    onEasyEffectsActiveChanged: {
        if (root.driverReady && root.easyEffectsIcon)
            root.easyEffectsIcon.play(root.easyEffectsActive ? "on" : "off");
    }

    // ── Encrypted DNS ───────────────────────────────────────────────────────
    readonly property string dnsCue: {
        if (DnsOverTls.busy)
            return "switching";
        return DnsOverTls.active ? "on" : "off";
    }
    onDnsCueChanged: {
        if (root.driverReady && root.dnsIcon)
            root.dnsIcon.play(root.dnsCue);
    }

    // ── Game mode ───────────────────────────────────────────────────────────
    //
    // The quick toggle owns no shared state for this — it reads the same
    // Hyprland option, so the driver reads it too rather than inventing a
    // second source of truth.
    HyprlandConfigOption {
        id: animationsEnabled
        key: "animations:enabled"
    }
    readonly property bool gameModeOn: !animationsEnabled.value
    onGameModeOnChanged: {
        if (root.driverReady && root.gameModeIcon)
            root.gameModeIcon.play(root.gameModeOn ? "on" : "off");
    }

    // ── Identify Music ──────────────────────────────────────────────────────
    readonly property bool songRecRunning: SongRec.running
    onSongRecRunningChanged: {
        if (root.driverReady && root.songRecIcon)
            root.songRecIcon.play(root.songRecRunning ? "listening" : "found");
    }

    // ── System alarms ──────────────────────────────────────────────────────
    // The list length is intentionally separate from enabled/ringing state:
    // a disabled alarm is still a definition and keeps the indicator visible,
    // while removing any definition is an event even if others remain.
    readonly property int alarmCount: Persistent.ready ? Persistent.states.alarms.length : 0
    property int previousAlarmCount: 0
    property bool alarmVisible: root.alarmCount > 0

    Timer {
        id: alarmHideTimer
        interval: 620
        repeat: false
        onTriggered: root.alarmVisible = root.alarmCount > 0
    }

    onAlarmCountChanged: {
        const previous = root.previousAlarmCount;
        root.previousAlarmCount = root.alarmCount;

        if (root.alarmCount > 0) {
            alarmHideTimer.stop();
            root.alarmVisible = true;
        } else if (previous > 0) {
            // Keep the last icon alive until removedAnim has folded and
            // settled all of its parts (roughly 550 ms).
            root.alarmVisible = true;
            alarmHideTimer.restart();
        }

        if (!root.driverReady || !root.alarmIcon)
            return;
        if (root.alarmCount > previous)
            root.alarmIcon.play("open");
        else if (root.alarmCount < previous)
            root.alarmIcon.play("removed");
    }

    readonly property bool alarmRinging: GlobalStates.alarmRinging
    onAlarmRingingChanged: {
        if (!root.driverReady || !root.alarmIcon)
            return;
        if (root.alarmRinging)
            root.alarmIcon.play("ringing");
        else
            root.alarmIcon.play("stopped");
    }

    // ── Notifications ───────────────────────────────────────────────────────
    readonly property bool notificationsSilent: Notifications.silent
    onNotificationsSilentChanged: {
        if (root.driverReady && root.notificationIcon)
            root.notificationIcon.play(root.notificationsSilent ? "silence" : "unsilence");
    }

    readonly property int unreadCount: Notifications.unread
    property int previousUnreadCount: 0
    onUnreadCountChanged: {
        const previous = root.previousUnreadCount;
        root.previousUnreadCount = root.unreadCount;
        if (root.driverReady && root.notificationIcon && root.unreadCount > previous)
            root.notificationIcon.play("arrive");
    }
}
