pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions

Singleton {
    id: root

    // ── State ────────────────────────────────────────────────────────────────
    property bool ytdlpFound: false
    property bool ffmpegFound: false
    property bool ready: false
    property bool active: false

    property string currentStatus: "idle"
    property real downloadProgress: 0.0
    property string logOutput: ""
    property bool isDownloading: false

    // ── Signals ──────────────────────────────────────────────────────────────
    signal downloadFinished(string filePath)
    signal downloadFailed(string errorMsg)
    signal logAppended(string text)
    signal dependencyCheckDone()

    // ── Internal ─────────────────────────────────────────────────────────────
    property bool _deactivateRequested: false

    onActiveChanged: {
        if (root.active) {
            root._deactivateRequested = false;
            keepAliveTimer.stop();
            root.logOutput = "";
            root._appendLog("Starting Media Downloader...");
            root.currentStatus = "checking";
            ytdlpCheck.running = false;
            ytdlpCheck.running = true;
        } else {
            if (root.isDownloading) {
                root._deactivateRequested = true;
            } else {
                root._doDeactivate();
            }
        }
    }

    function _doDeactivate() {
        if (downloadProc.running) {
            downloadProc.signal(2);
        }
        root.logOutput = "";
        root.downloadProgress = 0.0;
        root.currentStatus = "idle";
        root.ready = false;
        root.ytdlpFound = false;
        root.ffmpegFound = false;
        root.isDownloading = false;
        root._deactivateRequested = false;
    }

    Timer {
        id: keepAliveTimer
        interval: 60000
        repeat: false
        onTriggered: {
            if (root._deactivateRequested) {
                root._doDeactivate();
            }
        }
    }

    // ── yt-dlp check ─────────────────────────────────────────────────────────
    Process {
        id: ytdlpCheck
        command: ["bash", "-c", "yt-dlp --version 2>&1"]
        running: false
        stdout: SplitParser {
            onRead: data => {
                if (data.trim()) {
                    root.ytdlpFound = true;
                    root._appendLog("✓ yt-dlp " + data.trim() + " ready");
                }
            }
        }
        onExited: (code, signal) => {
            if (code !== 0) {
                root.ytdlpFound = false;
                root._appendLog("✗ yt-dlp not found");
                root._appendLog("  Install: sudo pacman -S yt-dlp   (Arch)");
                root._appendLog("           pip install yt-dlp        (pip)");
            }
            ffmpegCheck.running = false;
            ffmpegCheck.running = true;
        }
    }

    Process {
        id: ffmpegCheck
        command: ["bash", "-c", "ffmpeg -version 2>&1 | head -1"]
        running: false
        stdout: SplitParser {
            onRead: data => {
                if (data.includes("ffmpeg")) {
                    root.ffmpegFound = true;
                    root._appendLog("✓ ffmpeg ready (audio conversion enabled)");
                }
            }
        }
        onExited: (code, signal) => {
            if (code !== 0) {
                root.ffmpegFound = false;
                root._appendLog("⚠  ffmpeg not found — audio conversion unavailable");
                root._appendLog("  Install: sudo pacman -S ffmpeg");
            }
            root._finishDepCheck();
        }
    }

    function _finishDepCheck() {
        if (!root.ytdlpFound) {
            root.currentStatus = "error";
            root._appendLog("\n⚠  Cannot download: yt-dlp is required.");
        } else {
            root.ready = true;
            root.currentStatus = "idle";
            root._appendLog("\nMedia Downloader ready. Enter a URL above and press Download.");
        }
        root.dependencyCheckDone();
    }

    // ── Download process ─────────────────────────────────────────────────────
    Process {
        id: downloadProc
        running: false
        stdout: SplitParser {
            onRead: data => root._parseDownloadLine(data)
        }
        stderr: SplitParser {
            onRead: data => root._parseDownloadLine(data)
        }
        onExited: (code, signal) => {
            root.isDownloading = false;
            if (code === 0) {
                root._appendLog("\n✓ Download complete!");
                root.downloadProgress = 1.0;
                root.currentStatus = "idle";
                root.downloadFinished("");
                notifyProc.command = ["notify-send", "Download complete", "Media saved to " + Config.options.mediaDownloader.downloadPath, "--icon=folder-download", "--app-name=Media Downloader"];
                notifyProc.running = false;
                notifyProc.running = true;
            } else if (signal === 2) {
                root._appendLog("Download cancelled.");
                root.downloadProgress = 0.0;
                root.currentStatus = "idle";
            } else {
                root._appendLog("\n✗ Download failed (exit " + code + ")");
                root.currentStatus = "error";
                root.downloadFailed("Exit code: " + code);
                notifyProc.command = ["notify-send", "Download failed", "Exit code: " + code, "--icon=dialog-error", "--app-name=Media Downloader", "--urgency=critical"];
                notifyProc.running = false;
                notifyProc.running = true;
            }
            if (root._deactivateRequested) {
                keepAliveTimer.start();
            }
        }
    }

    function _parseDownloadLine(line) {
        root._appendLog(line);
        const match = line.match(/\[download\]\s+([\d.]+)%/);
        if (match) {
            root.downloadProgress = parseFloat(match[1]) / 100.0;
        }
    }

    function _appendLog(text) {
        root.logOutput = root.logOutput + text + "\n";
    }

    // ── Notifications helper proc ─────────────────────────────────────────────
    Process {
        id: notifyProc
        running: false
    }

    // ── Public API ───────────────────────────────────────────────────────────
    function startDownload(url, format, downloadType, extraArgs) {
        if (!root.ready || !root.ytdlpFound) {
            root._appendLog("✗ Not ready. Check that yt-dlp is installed.");
            return;
        }
        if (root.isDownloading) {
            root._appendLog("⚠  A download is already in progress.");
            return;
        }
        if (!url || url.trim() === "") {
            root._appendLog("✗ Please enter a URL.");
            return;
        }

        root.downloadProgress = 0.0;
        root.currentStatus = "downloading";
        root.isDownloading = true;

        // Save last used format
        Config.options.mediaDownloader.lastUsedFormat = format;

        let cmd = ["yt-dlp", "--progress", "--newline"];

        switch (format) {
        case "audio-mp3":
            cmd = cmd.concat(["-x", "--audio-format", "mp3"]);
            break;
        case "audio-ogg":
            cmd = cmd.concat(["-x", "--audio-format", "vorbis"]);
            break;
        case "audio-opus":
            cmd = cmd.concat(["-x", "--audio-format", "opus"]);
            break;
        case "video-mp4":
            cmd = cmd.concat(["-f", "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best"]);
            break;
        default:
            break;
        }

        if (Config.options.mediaDownloader.embedMetadata) cmd.push("--embed-metadata");
        if (Config.options.mediaDownloader.proxy !== "") cmd = cmd.concat(["--proxy", Config.options.mediaDownloader.proxy]);
        if (Config.options.mediaDownloader.rateLimit > 0) cmd = cmd.concat(["--rate-limit", Config.options.mediaDownloader.rateLimit + "K"]);
        if (Config.options.mediaDownloader.throttleBypass) cmd = cmd.concat(["--throttled-rate", "100K"]);
        if (Config.options.mediaDownloader.useAria2c) cmd = cmd.concat(["--downloader", "aria2c"]);

        const outPath = Config.options.mediaDownloader.downloadPath;
        cmd = cmd.concat(["-o", outPath + "/%(title)s.%(ext)s"]);

        if (Config.options.mediaDownloader.extraArgs.trim() !== "") {
            cmd = cmd.concat(Config.options.mediaDownloader.extraArgs.trim().split(/\s+/));
        }
        if (extraArgs.trim() !== "") {
            cmd = cmd.concat(extraArgs.trim().split(/\s+/));
        }

        if (downloadType === "playlist") {
            cmd.push("--yes-playlist");
        } else         if (downloadType === "batch") {
            const urls = url.trim().split(/\n/).map(u => u.trim()).filter(u => u !== "");
            if (urls.length === 0) {
                root._appendLog("✗ Please enter at least one URL for batch download.");
                root.isDownloading = false;
                root.currentStatus = "idle";
                return;
            }
            cmd = cmd.concat(urls);
        } else if (downloadType === "playlist") {
            cmd.push("--yes-playlist");
            cmd.push(url.trim());
        } else {
            cmd.push("--no-playlist");
            cmd.push(url.trim());
        }

        root._appendLog("\n$ " + cmd.join(" ") + "\n");
        downloadProc.command = cmd;
        downloadProc.running = false;
        downloadProc.running = true;
    }

    function cancelDownload() {
        if (!root.isDownloading) return;
        root.currentStatus = "cancelling";
        root._appendLog("Cancelling...");
        downloadProc.signal(2);
    }

    function clearLog() {
        root.logOutput = "";
    }
}
