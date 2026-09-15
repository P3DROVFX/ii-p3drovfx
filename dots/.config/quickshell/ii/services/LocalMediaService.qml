pragma Singleton
pragma ComponentBehavior: Bound

import qs
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

/**
 * Shell-lifetime proxy for the local MPV/MPRIS helper.
 *
 * MediaMode is intentionally a short-lived PanelWindow.  This singleton keeps
 * the helper process and its selected session outside that visual lifecycle,
 * so closing one monitor's Media Mode neither stops audio nor starts another
 * MPV process on a second monitor.
 */
Singleton {
    id: root

    readonly property string helperPath: `${Directories.scriptPath}/media/local_player.py`
    readonly property string scannerPath: `${Directories.scriptPath}/media/library_index.py`
    readonly property string helperBusName: "org.mpris.MediaPlayer2.ii_local"
    readonly property int protocolVersion: 1

    property bool helperWanted: false
    property bool helperReady: false
    property bool applyingState: false
    property bool mprisControlClaimed: false
    property int requestSerial: 0
    property int localPlayerDiscoveryAttempts: 0
    property var pendingOpenPayload: null
    property int importSerial: 0
    property string activeImportId: ""
    property string activeImportAction: "open"
    property string scannerProcessRequestId: ""
    property string completedImportId: ""
    property bool importRunning: false
    property bool scannerProcessAlive: false
    property bool scannerStopping: false
    property var pendingImport: null
    property var scannerCommand: []
    property int importAcceptedCount: 0
    property int importSkippedCount: 0
    property string importStatus: ""
    property string lastError: ""
    property var session: ({})

    readonly property bool hasSession: Boolean(session?.sessionActive ?? false)
    readonly property string sessionKind: String(queueSnapshot?.sessionKind ?? "empty")
    readonly property bool playlistOpen: Boolean(queueSnapshot?.playlistOpen ?? false)
    property var queueSnapshot: ({})
    readonly property bool helperRunning: helperProcess.running
    readonly property bool importActive: importRunning || scannerProcessAlive

    signal stateChanged()
    signal errorOccurred(message: string)

    QtObject {
        id: localPlayer

        property string identity: "II Music"
        property string trackTitle: ""
        property string trackArtist: ""
        property string trackAlbum: ""
        property string trackArtUrl: ""
        property string trackLyricsPath: ""
        property real length: 0
        property real position: 0
        property real _lastAppliedPosition: 0
        property real volume: Persistent.states.background.mediaMode.localMediaVolume ?? 0.8
        property real rate: 1
        property int loopState: 0 // MprisLoopState: None, Playlist, Track
        property bool shuffle: false
        property bool isPlaying: false
        property bool canTogglePlaying: false
        property bool canGoNext: false
        property bool canGoPrevious: false
        property bool canSeek: false
        property bool canControl: false
        property bool volumeSupported: true
        property bool loopSupported: true
        property bool shuffleSupported: true

        function togglePlaying(): void {
            root.playPause();
        }

        function play(): void {
            root.play();
        }

        function pause(): void {
            root.pause();
        }

        function next(): void {
            root.next();
        }

        function previous(): void {
            root.previous();
        }

        function seek(positionSec: real): void {
            _lastAppliedPosition = positionSec;
            root.seek(positionSec);
        }

        onPositionChanged: {
            if (!root.applyingState && Math.abs(position - _lastAppliedPosition) > 0.05) {
                _lastAppliedPosition = position;
                root.seek(position);
            }
        }
        onVolumeChanged: {
            if (!root.applyingState) {
                Persistent.states.background.mediaMode.localMediaVolume = volume;
                root.setVolume(volume);
            }
        }
        onRateChanged: {
            if (!root.applyingState)
                root.setRate(rate);
        }
        onLoopStateChanged: {
            if (!root.applyingState)
                root.setLoopState(loopState);
        }
        onShuffleChanged: {
            if (!root.applyingState)
                root.setShuffle(shuffle);
        }
    }

    readonly property QtObject player: localPlayer

    function _request(op: string, payload = {}): void {
        if (!helperProcess.running)
            return;
        requestSerial++;
        helperProcess.write(JSON.stringify({
            protocolVersion: protocolVersion,
            requestId: `local-media-${requestSerial}`,
            op: op,
            payload: payload ?? {}
        }) + "\n");
    }

    function _applySession(nextSession: var): void {
        if (!nextSession || typeof nextSession !== "object")
            return;
        applyingState = true;
        session = nextSession;
        const track = nextSession.track ?? {};
        const artists = Array.from(track.artists ?? []);
        localPlayer.identity = String(nextSession.identity ?? "II Music");
        localPlayer.trackTitle = String(track.title ?? "");
        localPlayer.trackArtist = artists.join(", ");
        localPlayer.trackAlbum = String(track.album ?? "");
        localPlayer.trackArtUrl = String(track.artUrl ?? "");
        localPlayer.trackLyricsPath = String(track.lyricsPath ?? "");
        localPlayer.length = Math.max(0, Number(track.durationSec ?? 0));
        localPlayer._lastAppliedPosition = Math.max(0, Number(nextSession.positionSec ?? 0));
        localPlayer.position = localPlayer._lastAppliedPosition;
        localPlayer.volume = Math.max(0, Math.min(1, Number(nextSession.volume ?? 1)));
        Persistent.states.background.mediaMode.localMediaVolume = localPlayer.volume;
        localPlayer.rate = Number(nextSession.rate ?? 1);
        localPlayer.loopState = nextSession.loopStatus === "Track"
            ? 2
            : (nextSession.loopStatus === "Playlist" ? 1 : 0);
        localPlayer.shuffle = Boolean(nextSession.shuffle ?? false);
        localPlayer.isPlaying = nextSession.playbackStatus === "Playing";
        localPlayer.canControl = Boolean(nextSession.canControl ?? false);
        localPlayer.canTogglePlaying = Boolean(nextSession.canPlay ?? false) || Boolean(nextSession.canPause ?? false);
        localPlayer.canGoNext = Boolean(nextSession.canGoNext ?? false);
        localPlayer.canGoPrevious = Boolean(nextSession.canGoPrevious ?? false);
        localPlayer.canSeek = Boolean(nextSession.canSeek ?? false);

        const nextQueue = nextSession.queue ?? {};
        if (!nextSession.queue) {
            if (root.queueSnapshot && root.queueSnapshot.entries && root.queueSnapshot.entries.length > 0)
                root.queueSnapshot = ({});
        } else if (root.queueSnapshot.revision !== nextQueue.revision
            || root.queueSnapshot.currentEntryId !== nextQueue.currentEntryId
            || root.queueSnapshot.playlistOpen !== nextQueue.playlistOpen
            || root.queueSnapshot.shuffle !== nextQueue.shuffle
            || root.queueSnapshot.sessionKind !== nextQueue.sessionKind) {
            root.queueSnapshot = nextQueue;
        }

        applyingState = false;
        stateChanged();

        if (hasSession && mprisControlClaimed && !MprisController.localPlayerSelected) {
            MprisController.setMediaModeSource("local");
            if (!MprisController.activateLocalPlayer() && !localPlayerDiscoveryTimer.running) {
                localPlayerDiscoveryAttempts = 0;
                localPlayerDiscoveryTimer.start();
            }
        }
    }

    function _handleHelperLine(line: string): void {
        let message;
        try {
            message = JSON.parse(line);
        } catch (error) {
            return;
        }
        if (message.protocolVersion !== protocolVersion)
            return;

        if (message.event === "ready") {
            helperReady = true;
            _syncSettings();
            _request("snapshot");
            _sendPendingOpen();
            return;
        }
        if (message.event === "state") {
            _applySession(message.payload);
            return;
        }
        if (message.event === "raiseRequested") {
            GlobalStates.requestMediaMode("open");
            return;
        }
        if (message.ok === false) {
            lastError = String(message.error?.message ?? Translation.tr("Local music player failed"));
            errorOccurred(lastError);
            _request("snapshot");
            return;
        }
        if (message.ok === true && message.payload?.playbackStatus !== undefined) {
            _applySession(message.payload);
        }
    }

    function _queueOpen(payload: var): void {
        if (!payload || typeof payload !== "object")
            return;
        pendingOpenPayload = payload;
        mprisControlClaimed = true;
        lastError = "";
        helperWanted = true;
        if (helperReady)
            _sendPendingOpen();
    }

    function _sendPendingOpen(): void {
        if (!pendingOpenPayload)
            return;
        const payload = pendingOpenPayload;
        pendingOpenPayload = null;
        _request("open", payload);
    }

    function openFiles(paths: var, sessionKind = ""): void {
        const normalized = Array.from(paths ?? [])
            .map(path => String(path ?? "").trim())
            .filter(path => path.length > 0);
        if (normalized.length === 0)
            return;
        _queueOpen({
            paths: normalized,
            sessionKind: sessionKind.length > 0
                ? sessionKind
                : (normalized.length === 1 ? "single" : "playlist")
        });
    }

    function openEntries(entries: var, sessionKind: string): void {
        const normalized = Array.from(entries ?? [])
            .filter(entry => entry && typeof entry === "object");
        if (normalized.length === 0)
            return;
        _queueOpen({ entries: normalized, sessionKind: sessionKind });
    }

    function appendEntries(entries: var): void {
        const normalized = Array.from(entries ?? [])
            .filter(entry => entry && typeof entry === "object");
        if (normalized.length === 0)
            return;
        _request("append", { entries: normalized });
    }

    function _startPendingImport(): void {
        if (scannerProcessAlive || importRunning || !pendingImport)
            return;
        const candidate = pendingImport;
        pendingImport = null;
        activeImportId = candidate.id;
        activeImportAction = candidate.action;
        scannerProcessRequestId = candidate.id;
        completedImportId = "";
        const command = ["python3", root.scannerPath, "--request-id", candidate.id, "--cache-dir", Directories.localMediaCoverCache];
        if (candidate.kind === "folder")
            command.push("--folder", candidate.path);
        else {
            for (const path of candidate.paths)
                command.push("--path", path);
        }
        scannerCommand = command;
        scannerProcessAlive = true;
        scannerStopping = false;
        importRunning = true;
    }

    function _startImport(candidate: var): void {
        if (!candidate)
            return;
        importSerial++;
        const candidateId = `local-import-${importSerial}`;
        pendingImport = {
            id: candidateId,
            kind: candidate.kind,
            path: candidate.path ?? "",
            paths: candidate.paths ?? [],
            action: candidate.action ?? "open"
        };
        // Immediately invalidate any process that is still draining output.
        // Its final manifest must never commit after the user picked newer
        // files, even during the brief interval before Process.onExited.
        activeImportId = candidateId;
        activeImportAction = pendingImport.action;
        completedImportId = "";
        importAcceptedCount = 0;
        importSkippedCount = 0;
        importStatus = Translation.tr("Reading local music…");
        lastError = "";

        if (scannerProcessAlive) {
            scannerStopping = true;
            importRunning = false;
            return;
        }
        _startPendingImport();
    }

    function startFilesImport(paths: var, action = "open"): void {
        const normalized = Array.from(paths ?? [])
            .map(path => String(path ?? "").trim())
            .filter(path => path.length > 0);
        if (normalized.length > 0)
            _startImport({ kind: "files", paths: normalized, action: action });
    }

    function startFolderImport(path: string, action = "open"): void {
        const normalized = String(path ?? "").trim();
        if (normalized.length > 0)
            _startImport({ kind: "folder", path: normalized, action: action });
    }

    function cancelImport(): void {
        pendingImport = null;
        activeImportId = "";
        importRunning = false;
        importStatus = Translation.tr("Local music import cancelled");
        if (scannerProcessAlive)
            scannerStopping = true;
    }

    function _handleScannerLine(line: string): void {
        let message;
        try {
            message = JSON.parse(line);
        } catch (error) {
            return;
        }
        const payload = message.payload ?? {};
        const requestId = String(payload.requestId ?? "");
        if (!requestId || requestId !== activeImportId)
            return;

        if (message.event === "started") {
            importStatus = Translation.tr("Reading local music…");
            return;
        }
        if (message.event === "track") {
            importAcceptedCount = Math.max(importAcceptedCount, Number(payload.accepted ?? 0));
            importSkippedCount = Math.max(importSkippedCount, Number(payload.skipped ?? 0));
            importStatus = String(importAcceptedCount) + Translation.tr(" music tracks ready");
            return;
        }
        if (message.event === "skipped") {
            importSkippedCount++;
            return;
        }
        if (message.event === "failed") {
            completedImportId = requestId;
            importRunning = false;
            lastError = String(payload.message ?? Translation.tr("Could not read local music"));
            importStatus = lastError;
            errorOccurred(lastError);
            return;
        }
        if (message.event !== "finished")
            return;

        completedImportId = requestId;
        importRunning = false;
        const entries = Array.from(payload.entries ?? []);
        importAcceptedCount = entries.length;
        importSkippedCount = Math.max(importSkippedCount, Number(payload.skipped ?? 0));
        if (entries.length === 0) {
            importStatus = Translation.tr("No playable music found");
            return;
        }
        importStatus = String(entries.length) + Translation.tr(" music tracks ready");
        if (activeImportAction === "append" && hasSession)
            appendEntries(entries);
        else
            openEntries(entries, String(payload.sessionKind ?? (entries.length === 1 ? "single" : "playlist")));
    }

    function requestSnapshot(): void {
        _request("snapshot");
    }

    function claimMprisControl(): void {
        mprisControlClaimed = true;
        if (!hasSession)
            return;
        MprisController.setMediaModeSource("local");
        if (!MprisController.activateLocalPlayer() && !localPlayerDiscoveryTimer.running) {
            localPlayerDiscoveryAttempts = 0;
            localPlayerDiscoveryTimer.start();
        }
    }

    function releaseMprisControl(): void {
        mprisControlClaimed = false;
        localPlayerDiscoveryTimer.stop();
        MprisController.releaseLocalPlayer();
    }

    function play(): void { _request("play"); }
    function pause(): void { _request("pause"); }
    function playPause(): void { _request("playPause"); }
    function stop(): void { _request("stop"); }
    function next(): void { _request("next"); }
    function previous(): void { _request("previous"); }
    function seek(positionSec: real): void { _request("seek", { positionSec: positionSec }); }
    function setVolume(volume: real): void { _request("setVolume", { volume: volume }); }
    function setRate(rate: real): void { _request("setRate", { value: rate }); }
    function setLoopState(loopState: int): void {
        const statuses = ["None", "Playlist", "Track"];
        _request("setLoopStatus", { value: statuses[Math.max(0, Math.min(2, loopState))] });
    }
    function setShuffle(shuffle: bool): void { _request("setShuffle", { value: shuffle }); }
    function playQueueEntry(entryId: string): void { _request("playEntry", { entryId: entryId }); }
    function moveQueueEntry(entryId: string, destinationIndex: int): void {
        _request("moveEntry", { entryId: entryId, destinationIndex: destinationIndex });
    }
    function removeQueueEntries(entryIds: var): void {
        const normalized = Array.from(entryIds ?? [])
            .map(entryId => String(entryId ?? "").trim())
            .filter(entryId => entryId.length > 0);
        if (normalized.length > 0)
            _request("removeEntries", { entryIds: normalized });
    }
    function clearFutureQueueEntries(): void { _request("clearFuture"); }

    function sortQueue(criterion: string, descending: bool): void {
        _request("sortQueue", {
            criterion: String(criterion || "title"),
            descending: Boolean(descending)
        });
    }

    function setCrossfade(enable: bool, durationSec: real): void {
        _request("setCrossfade", {
            enable: Boolean(enable),
            durationSec: Math.max(0.5, Number(durationSec ?? 3))
        });
    }

    function _syncSettings(): void {
        const savedVol = Persistent.states.background.mediaMode.localMediaVolume;
        if (typeof savedVol === "number" && isFinite(savedVol)) {
            root.setVolume(savedVol);
        }
        root.setCrossfade(
            Boolean(Config.options.background.mediaMode.crossfade?.enable ?? false),
            Number(Config.options.background.mediaMode.crossfade?.durationSec ?? 3)
        );
    }

    function terminateService(): void {
        cancelImport();
        importRunning = false;
        releaseMprisControl();
        _request("shutdown");
        helperWanted = false;
        helperReady = false;
        session = ({});
        queueSnapshot = ({});
        applyingState = true;
        localPlayer.isPlaying = false;
        localPlayer.identity = "II Music";
        localPlayer.trackTitle = "";
        localPlayer.trackArtist = "";
        localPlayer.trackAlbum = "";
        localPlayer.trackArtUrl = "";
        localPlayer.trackLyricsPath = "";
        localPlayer.position = 0;
        localPlayer.length = 0;
        applyingState = false;
        stateChanged();
        terminateProcess.running = true;
    }

    Process {
        id: terminateProcess
        command: ["python3", root.helperPath, "--terminate"]
        running: false
    }

    Connections {
        target: LocalMediaSelection
        function onMusicFilesSelected(paths: var, purpose: string): void {
            root.startFilesImport(paths, purpose);
        }
        function onMusicFolderSelected(path: string, purpose: string): void {
            root.startFolderImport(path, purpose);
        }
    }

    Timer {
        id: localPlayerDiscoveryTimer
        interval: 250
        repeat: true
        onTriggered: {
            if (MprisController.activateLocalPlayer()) {
                stop();
                return;
            }
            root.localPlayerDiscoveryAttempts++;
            if (root.localPlayerDiscoveryAttempts >= 24)
                stop();
        }
    }

    Process {
        id: helperProcess
        command: [
            "python3",
            root.helperPath,
            "--volume",
            String(Persistent.states.background.mediaMode.localMediaVolume ?? 0.8)
        ]
        stdinEnabled: true
        running: root.helperWanted
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => root._handleHelperLine(line)
        }
        stderr: SplitParser {
            splitMarker: "\n"
            onRead: line => console.warn(`[LocalMedia] ${line}`)
        }
        onStarted: {
            root.helperReady = false;
        }
        onExited: exitCode => {
            root.helperReady = false;
            if (root.helperWanted) {
                root.helperWanted = false;
                if (exitCode !== 0) {
                    root.lastError = Translation.tr("Local music player stopped unexpectedly");
                    root.errorOccurred(root.lastError);
                }
            }
        }
    }

    Process {
        id: probeProcess
        command: ["python3", root.helperPath, "--probe"]
        running: false
        onExited: exitCode => {
            if (exitCode === 0 && !root.helperWanted) {
                root.mprisControlClaimed = true;
                root.helperWanted = true;
            }
        }
    }

    Component.onCompleted: {
        const isLocal = MprisController.allPlayers?.some(player => player?.dbusName === root.helperBusName)
            ?? MprisController.players?.some(player => player?.dbusName === root.helperBusName);
        if (isLocal) {
            root.mprisControlClaimed = true;
            root.helperWanted = true;
        } else {
            probeProcess.running = true;
        }
    }

    Connections {
        target: Config.options.background.mediaMode.crossfade
        function onEnableChanged(): void {
            if (root.helperReady)
                root.setCrossfade(Config.options.background.mediaMode.crossfade?.enable ?? false, Config.options.background.mediaMode.crossfade?.durationSec ?? 3);
        }
        function onDurationSecChanged(): void {
            if (root.helperReady)
                root.setCrossfade(Config.options.background.mediaMode.crossfade?.enable ?? false, Config.options.background.mediaMode.crossfade?.durationSec ?? 3);
        }
    }

    Connections {
        target: MprisController
        function onAllPlayersChanged(): void {
            if (!root.helperWanted) {
                const isLocal = MprisController.allPlayers?.some(player => player?.dbusName === root.helperBusName);
                if (isLocal) {
                    root.mprisControlClaimed = true;
                    root.helperWanted = true;
                }
            }
        }
    }

    Process {
        id: scannerProcess
        command: root.scannerCommand
        running: root.importRunning
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => root._handleScannerLine(line)
        }
        stderr: SplitParser {
            splitMarker: "\n"
            onRead: line => console.warn(`[LocalMedia import] ${line}`)
        }
        onExited: exitCode => {
            const exitedRequestId = root.scannerProcessRequestId;
            root.scannerProcessAlive = false;
            root.scannerStopping = false;
            root.importRunning = false;
            if (exitedRequestId === root.activeImportId
                && root.completedImportId !== exitedRequestId
                && !root.pendingImport) {
                root.lastError = Translation.tr("Local music import stopped unexpectedly");
                root.importStatus = root.lastError;
                root.errorOccurred(root.lastError);
            }
            if (root.pendingImport)
                Qt.callLater(root._startPendingImport);
        }
    }
}
