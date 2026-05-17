pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    enum MonitorSource { Monitor, Input }

    property var monitorSource: SongRec.MonitorSource.Monitor
    property int timeoutInterval: (Config.options && Config.options.musicRecognition && Config.options.musicRecognition.interval) ? Config.options.musicRecognition.interval : 10
    property int timeoutDuration: (Config.options && Config.options.musicRecognition && Config.options.musicRecognition.timeout) ? Config.options.musicRecognition.timeout : 30
    readonly property bool running: recognizeMusicProc.running

    function toggleRunning(running) {
        if (recognizeMusicProc.running && !running === true) root.manuallyStopped = true;
        if (running != undefined) {
            recognizeMusicProc.running = running
        } else {
            recognizeMusicProc.running = !root.running
        }
        musicReconizedProc.running = false
    }

    function toggleMonitorSource(source) {
        if (source !== undefined) {
            root.monitorSource = source
            return
        }
        root.monitorSource = (root.monitorSource === SongRec.MonitorSource.Monitor) ? SongRec.MonitorSource.Input : SongRec.MonitorSource.Monitor
    }
    function monitorSourceToString(source) {
        if (source === SongRec.MonitorSource.Monitor) {
            return "monitor"
        } else {
            return "input"
        }
    }
    readonly property string monitorSourceString: monitorSourceToString(monitorSource)
    property var recognizedTrack: ({ title:"", subtitle:"", url:""})
    property bool manuallyStopped: false

    function handleRecognition(jsonText) {
        if (!jsonText || jsonText.trim() === "") {
            Quickshell.execDetached(["notify-send", Translation.tr("Music Recognition"), Translation.tr("No match found. Try again or check your audio output."), "-a", "Shell"])
            return
        }
        try {
            var obj = JSON.parse(jsonText)
            if (!obj.track || !obj.track.title) {
                Quickshell.execDetached(["notify-send", Translation.tr("Music Recognition"), Translation.tr("Could not identify this song. Try a different audio source."), "-a", "Shell"])
                return
            }
            root.recognizedTrack = {
                title: obj.track.title,
                subtitle: obj.track.subtitle,
                url: obj.track.url
            }
            musicReconizedProc.running = true
        } catch(e) {
            Quickshell.execDetached(["notify-send", Translation.tr("Music Recognition"), Translation.tr("Recognition failed. Try again."), "-a", "Shell"])
        }
    }

    Process {
        id: recognizeMusicProc
        running: false
        command: [`${Directories.scriptPath}/musicRecognition/recognize-music.sh`, "-i", root.timeoutInterval, "-t", root.timeoutDuration, "-s", root.monitorSourceString]
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.manuallyStopped) {
                    root.manuallyStopped = false
                    return
                }
                handleRecognition(this.text)
            }
        }
        onRunningChanged: {
            if (running) {
                Quickshell.execDetached(["notify-send", Translation.tr("Music Recognition"), Translation.tr("Listening..."), "-t", "3000", "-a", "Shell"])
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 1) {
                Quickshell.execDetached(["notify-send", Translation.tr("Music Recognition"), Translation.tr("Make sure you have songrec installed"), "-a", "Shell"])
            }
        }
    }

    Process {
        id: musicReconizedProc
        running: false
        command: [
            "notify-send",
            Translation.tr("Music Recognized"), 
            root.recognizedTrack.title + " - " + root.recognizedTrack.subtitle, 
            "-A", "Shazam",
            "-A", "YouTube",
            "-a", "Shell"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                if (this.text === "") return
                if (this.text == 0) {
                    Qt.openUrlExternally(root.recognizedTrack.url);
                } else {
                    Qt.openUrlExternally("https://www.youtube.com/results?search_query=" + root.recognizedTrack.title + " - " + root.recognizedTrack.subtitle);
                }
            }
        }
    }
}