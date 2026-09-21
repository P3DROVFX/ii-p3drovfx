pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.services
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

    property var parsedStats: ({ size: "", speed: "", eta: "", phase: "" })

    // Thumbnail preview
    property string thumbnailUrl: ""
    property string thumbnailTitle: ""
    property bool thumbnailLoading: false

    // Download queue
    property var downloadQueue: []
    property bool queueProcessing: false
    property int maxConcurrentDownloads: 3
    property int activeDownloads: 0

    readonly property int logLineCap: 5000
    readonly property int logCharCap: 50000

    // ── Option arrays ────────────────────────────────────────────────────────
    readonly property var videoResolutionOptions: [
        { value: "best", label: "Best" },
        { value: "2160", label: "4K (2160p)" },
        { value: "1440", label: "1440p" },
        { value: "1080", label: "1080p" },
        { value: "720", label: "720p" },
        { value: "480", label: "480p" },
        { value: "360", label: "360p" }
    ]

    readonly property var videoCodecOptions: [
        { value: "any", label: "Any" },
        { value: "h264", label: "H.264" },
        { value: "h265", label: "H.265" },
        { value: "vp9", label: "VP9" },
        { value: "av1", label: "AV1" }
    ]

    readonly property var audioBitrateOptions: [
        { value: 0, label: "Auto" },
        { value: 128, label: "128 kbps" },
        { value: 192, label: "192 kbps" },
        { value: 320, label: "320 kbps" }
    ]

    readonly property var audioCodecOptions: [
        { value: "any", label: "Any" },
        { value: "opus", label: "Opus" },
        { value: "vorbis", label: "Vorbis" },
        { value: "mp3", label: "MP3" },
        { value: "m4a", label: "M4A" }
    ]

    // ── On the island ────────────────────────────────────────────────────────
    // A download outlives the overview it was started from; the island's background-jobs
    // activity is where it can still be followed. Only while the island shows jobs at
    // all: ProgressService starts a job monitor of its own the moment it is touched.
    property bool _islandJobShown: false
    onIsDownloadingChanged: Qt.callLater(root._publishIslandJob)
    onDownloadProgressChanged: Qt.callLater(root._publishIslandJob)
    onCurrentStatusChanged: Qt.callLater(root._publishIslandJob)

    function _publishIslandJob() {
        if (root.isDownloading) {
            if (!GlobalStates.islandOwnsProgress)
                return;
            root._islandJobShown = true;
            const converting = root.currentStatus === "converting";
            ProgressService.reportShellJob("mediaDownloader", {
                appName: Translation.tr("Media downloader"),
                icon: converting ? "transform" : "download",
                percent: Math.round(root.downloadProgress * 100),
                message: converting ? Translation.tr("Converting…")
                    : root.thumbnailTitle !== "" ? root.thumbnailTitle
                    : Translation.tr("Downloading media"),
                speedText: converting ? "" : (root.parsedStats.speed ?? ""),
                etaText: converting ? "" : (root.parsedStats.eta ?? "")
            });
            return;
        }
        if (!root._islandJobShown)
            return;
        root._islandJobShown = false;
        // onExited has already set the outcome: an error status, a full bar, or a
        // cancel's reset to nothing.
        if (root.currentStatus === "error")
            ProgressService.finishShellJob("mediaDownloader", "failed", Translation.tr("Download failed"));
        else if (root.downloadProgress >= 1)
            ProgressService.finishShellJob("mediaDownloader", "completed",
                Translation.tr("Download complete"));
        else
            ProgressService.finishShellJob("mediaDownloader", "cleared");
    }

    // ── Signals ──────────────────────────────────────────────────────────────
    signal downloadFinished(string filePath)
    signal downloadFailed(string errorMsg)
    signal logAppended(string text, string kind)
    signal dependencyCheckDone()

    // ── Internal ─────────────────────────────────────────────────────────────
    property bool _deactivateRequested: false

    onActiveChanged: {
        if (root.active) {
            root._deactivateRequested = false;
            keepAliveTimer.stop();
            root.logOutput = "";
            root.parsedStats = { size: "", speed: "", eta: "", phase: "" };
            root._appendLog("Starting Media Downloader...", "info");
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
        root.parsedStats = { size: "", speed: "", eta: "", phase: "" };
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

    // ── URL Validation ───────────────────────────────────────────────────────
    function validateUrl(url) {
        if (!url || url.trim() === "") {
            return { ok: false, reason: "Enter a URL first" };
        }
        const trimmed = url.trim();
        if (!trimmed.match(/^https?:\/\/[^\s]/i)) {
            return { ok: false, reason: "URL must start with http(s)://" };
        }
        return { ok: true, reason: "" };
    }

    // ── Format Auto-Detection ────────────────────────────────────────────────
    function detectFormatFromUrl(url) {
        if (!url) return null;
        const lower = url.toLowerCase();

        // SoundCloud - often better with audio formats
        if (lower.includes("soundcloud.com")) {
            return "audio-mp3";
        }

        // Bandcamp - music platform, prefer audio
        if (lower.includes("bandcamp.com")) {
            return "audio-mp3";
        }

        // YouTube Music - audio focused
        if (lower.includes("music.youtube.com")) {
            return "audio-mp3";
        }

        // Twitch clips/vods - video
        if (lower.includes("twitch.tv") || lower.includes("clips.twitch.net")) {
            return "video-mp4";
        }

        // Instagram/TikTok - short video
        if (lower.includes("instagram.com") || lower.includes("tiktok.com")) {
            return "video-mp4";
        }

        // Twitter/X - video
        if (lower.includes("twitter.com") || lower.includes("x.com")) {
            return "video-mp4";
        }

        // Reddit - video
        if (lower.includes("reddit.com")) {
            return "video-mp4";
        }

        // Default - let user decide
        return null;
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
                    root._appendLog("✓ yt-dlp " + data.trim() + " ready", "success");
                }
            }
        }
        onExited: (code, signal) => {
            if (code !== 0) {
                root.ytdlpFound = false;
                root._appendLog("✗ yt-dlp not found", "error");
                root._appendLog("  Install: sudo pacman -S yt-dlp   (Arch)", "info");
                root._appendLog("           pip install yt-dlp        (pip)", "info");
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
                    root._appendLog("✓ ffmpeg ready (audio conversion enabled)", "success");
                }
            }
        }
        onExited: (code, signal) => {
            if (code !== 0) {
                root.ffmpegFound = false;
                root._appendLog("⚠ ffmpeg not found — audio conversion unavailable", "warn");
                root._appendLog("  Install: sudo pacman -S ffmpeg", "info");
            }
            root._finishDepCheck();
        }
    }

    function _finishDepCheck() {
        if (!root.ytdlpFound) {
            root.currentStatus = "error";
            root._appendLog("\n⚠ Cannot download: yt-dlp is required.", "error");
        } else {
            root.ready = true;
            root.currentStatus = "idle";
            root._appendLog("\nMedia Downloader ready. Enter a URL above and press Download.", "info");
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
                root._appendLog("\n✓ Download complete!", "success");
                root.downloadProgress = 1.0;
                root.currentStatus = "idle";
                root.parsedStats = { size: "", speed: "", eta: "", phase: "complete" };
                root.downloadFinished("");
                notifyProc.command = ["notify-send", "Download complete", "Media saved to " + Config.options.mediaDownloader.downloadPath, "--icon=folder-download", "--app-name=Media Downloader"];
                notifyProc.running = false;
                notifyProc.running = true;
            } else if (signal === 2) {
                root._appendLog("Download cancelled.", "warn");
                root.downloadProgress = 0.0;
                root.currentStatus = "idle";
                root.parsedStats = { size: "", speed: "", eta: "", phase: "" };
            } else {
                root._appendLog("\n✗ Download failed (exit " + code + ")", "error");
                root.currentStatus = "error";
                root.parsedStats.phase = "error";
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
        let kind = "info";
        const progressMatch = line.match(/\[download\]\s+([\d.]+)%/);
        const fullMatch = line.match(/\[download\]\s+([\d.]+)%\s+of\s+~?\s*([\d.]+\w+)\s+at\s+([\d.]+\w+\/s)\s+ETA\s+([\d:]+)/);

        if (fullMatch) {
            root.downloadProgress = parseFloat(fullMatch[1]) / 100.0;
            root.parsedStats = {
                size: fullMatch[2],
                speed: fullMatch[3],
                eta: fullMatch[4],
                phase: "downloading"
            };
            kind = "progress";
        } else if (progressMatch) {
            root.downloadProgress = parseFloat(progressMatch[1]) / 100.0;
            root.parsedStats.phase = "downloading";
            kind = "progress";
        } else if (line.includes("[ExtractAudio]") || line.includes("[ffmpeg]") || line.includes("[Merger]")) {
            root.currentStatus = "converting";
            root.parsedStats.phase = "converting";
            kind = "info";
        } else if (line.includes("[debug]") || line.includes("WARNING")) {
            kind = "warn";
        } else if (line.includes("ERROR") || line.includes("error:")) {
            kind = "error";
        }

        root._appendLog(line, kind);
    }

    function _appendLog(text, kind) {
        kind = kind || "info";
        root.logOutput = root.logOutput + text + "\n";
        if (root.logOutput.length > root.logCharCap) {
            root.logOutput = root.logOutput.slice(-root.logCharCap);
        }
        root.logAppended(text, kind);
    }

    // ── Notifications helper proc ─────────────────────────────────────────────
    Process {
        id: notifyProc
        running: false
    }

    // ── Public API ───────────────────────────────────────────────────────────
    function startDownload(url, format, downloadType, extraArgs) {
        const validation = root.validateUrl(url);
        if (!validation.ok) {
            root._appendLog("✗ " + validation.reason, "error");
            return { ok: false, reason: validation.reason };
        }

        if (!root.ready || !root.ytdlpFound) {
            root._appendLog("✗ Not ready. Check that yt-dlp is installed.", "error");
            return { ok: false, reason: "Service not ready" };
        }
        if (root.isDownloading) {
            root._appendLog("⚠ A download is already in progress.", "warn");
            return { ok: false, reason: "Download already in progress" };
        }

        root.downloadProgress = 0.0;
        root.currentStatus = "preparing";
        root.parsedStats = { size: "", speed: "", eta: "", phase: "preparing" };
        root.isDownloading = true;

        Config.options.mediaDownloader.lastUsedFormat = format;

        let cmd = ["yt-dlp", "--progress", "--newline"];

        const resolution = Config.options.mediaDownloader.videoResolution;
        const videoCodec = Config.options.mediaDownloader.videoCodec;
        const audioBitrate = Config.options.mediaDownloader.audioBitrate;
        const audioCodec = Config.options.mediaDownloader.audioCodec;

        const isAudioFormat = format.startsWith("audio-");
        const isVideoFormat = format.startsWith("video-") || format === "best";

        if (isAudioFormat) {
            cmd.push("-x");
            switch (format) {
            case "audio-mp3":
                cmd = cmd.concat(["--audio-format", "mp3"]);
                break;
            case "audio-ogg":
                cmd = cmd.concat(["--audio-format", "vorbis"]);
                break;
            case "audio-opus":
                cmd = cmd.concat(["--audio-format", "opus"]);
                break;
            case "audio-m4a":
                cmd = cmd.concat(["--audio-format", "m4a"]);
                break;
            default:
                if (audioCodec !== "any") {
                    cmd = cmd.concat(["--audio-format", audioCodec]);
                }
                break;
            }
            if (audioBitrate > 0) {
                cmd = cmd.concat(["--audio-quality", audioBitrate + "K"]);
            }
        } else if (isVideoFormat) {
            let formatStr = "bestvideo";
            if (resolution !== "best") {
                formatStr += "[height<=" + resolution + "]";
            }
            if (videoCodec !== "any") {
                const codecMap = {
                    "h264": "[vcodec^=avc1]",
                    "h265": "[vcodec^=hev]",
                    "vp9": "[vcodec^=vp9]",
                    "av1": "[vcodec^=av01]"
                };
                if (codecMap[videoCodec]) {
                    formatStr += codecMap[videoCodec];
                }
            }
            formatStr += "+bestaudio/best";

            switch (format) {
            case "video-mp4":
                formatStr = "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best";
                if (resolution !== "best") {
                    formatStr = "bestvideo[ext=mp4][height<=" + resolution + "]+bestaudio[ext=m4a]/bestvideo[height<=" + resolution + "]+bestaudio/best[height<=" + resolution + "]/best";
                }
                break;
            default:
                break;
            }
            cmd = cmd.concat(["-f", formatStr]);
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
        if (extraArgs && extraArgs.trim() !== "") {
            cmd = cmd.concat(extraArgs.trim().split(/\s+/));
        }

        if (downloadType === "playlist") {
            cmd.push("--yes-playlist");
            cmd.push(url.trim());
        } else if (downloadType === "batch") {
            const urls = url.trim().split(/\n/).map(u => u.trim()).filter(u => u !== "");
            if (urls.length === 0) {
                root._appendLog("✗ Please enter at least one URL for batch download.", "error");
                root.isDownloading = false;
                root.currentStatus = "idle";
                root.parsedStats = { size: "", speed: "", eta: "", phase: "" };
                return { ok: false, reason: "No URLs provided" };
            }
            cmd = cmd.concat(urls);
        } else {
            cmd.push("--no-playlist");
            cmd.push(url.trim());
        }

        root._appendLog("\n$ " + cmd.join(" ") + "\n", "info");
        downloadProc.command = cmd;
        downloadProc.running = false;
        downloadProc.running = true;

        return { ok: true, reason: "" };
    }

    function cancelDownload() {
        if (!root.isDownloading) return;
        root.currentStatus = "cancelling";
        root._appendLog("Cancelling...", "warn");
        downloadProc.signal(2);
    }

    function clearLog() {
        root.logOutput = "";
        root.parsedStats = { size: "", speed: "", eta: "", phase: "" };
    }

    // ── Download Queue Management ────────────────────────────────────────────
    function addToQueue(url, format, downloadType, extraArgs) {
        const validation = root.validateUrl(url);
        if (!validation.ok) {
            return { ok: false, reason: validation.reason };
        }

        const queueItem = {
            id: Date.now() + Math.random(),
            url: url.trim(),
            format: format,
            downloadType: downloadType,
            extraArgs: extraArgs || "",
            status: "queued",
            progress: 0,
            addedAt: new Date()
        };

        root.downloadQueue = root.downloadQueue.concat([queueItem]);
        root._processQueue();
        return { ok: true, reason: "", queueId: queueItem.id };
    }

    function removeFromQueue(queueId) {
        root.downloadQueue = root.downloadQueue.filter(item => item.id !== queueId);
    }

    function clearQueue() {
        root.downloadQueue = root.downloadQueue.filter(item => item.status === "downloading");
    }

    function _processQueue() {
        if (root.queueProcessing) return;
        root.queueProcessing = true;

        while (root.activeDownloads < root.maxConcurrentDownloads && root.downloadQueue.length > 0) {
            const nextItem = root.downloadQueue.find(item => item.status === "queued");
            if (!nextItem) break;

            nextItem.status = "downloading";
            root.activeDownloads++;
            root._startQueuedDownload(nextItem);
        }

        root.queueProcessing = false;
    }

    function _startQueuedDownload(queueItem) {
        const result = root.startDownload(
            queueItem.url,
            queueItem.format,
            queueItem.downloadType,
            queueItem.extraArgs
        );

        if (!result.ok) {
            queueItem.status = "error";
            root.activeDownloads--;
            root._processQueue();
        }
    }

    function _onDownloadComplete(queueId) {
        const item = root.downloadQueue.find(i => i.id === queueId);
        if (item) {
            item.status = "complete";
            item.progress = 1.0;
        }
        root.activeDownloads--;
        root._processQueue();
    }

    function _onDownloadError(queueId) {
        const item = root.downloadQueue.find(i => i.id === queueId);
        if (item) {
            item.status = "error";
        }
        root.activeDownloads--;
        root._processQueue();
    }

    // ── Thumbnail fetch ──────────────────────────────────────────────────────
    function fetchThumbnail(url) {
        if (!url || !root.ready || !root.ytdlpFound) {
            root.thumbnailUrl = "";
            root.thumbnailTitle = "";
            return;
        }
        root.thumbnailLoading = true;
        thumbnailProc.running = false;
        thumbnailProc.command = ["yt-dlp", "--dump-json", "--no-playlist", "--no-warnings", url.trim()];
        thumbnailProc.running = true;
    }

    Process {
        id: thumbnailProc
        running: false
        property string _output: ""
        stdout: SplitParser {
            onRead: data => {
                thumbnailProc._output += data + "\n";
            }
        }
        onExited: (code, signal) => {
            root.thumbnailLoading = false;
            if (code === 0 && thumbnailProc._output) {
                try {
                    const json = JSON.parse(thumbnailProc._output);
                    root.thumbnailUrl = json.thumbnail || json.thumbnails?.[json.thumbnails.length - 1]?.url || "";
                    root.thumbnailTitle = json.title || "";
                } catch (e) {
                    root.thumbnailUrl = "";
                    root.thumbnailTitle = "";
                }
            } else {
                root.thumbnailUrl = "";
                root.thumbnailTitle = "";
            }
            thumbnailProc._output = "";
        }
    }
}
