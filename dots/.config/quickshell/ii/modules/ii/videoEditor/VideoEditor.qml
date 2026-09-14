pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtMultimedia
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

FloatingWindow {
    id: root
    visible: GlobalStates.videoEditorOpen
    
    color: "transparent"
    width: 1200
    height: 800

    MediaPlayer {
        id: player
        autoPlay: true
        // Only resolve the source once the editor is actually visible. Otherwise,
        // setting videoEditorPath from the record.sh IPC handler triggers
        // autoPlay in the background while the user is still looking at the
        // "Edit Video?" popup, causing the recorded audio to loop invisibly
        // (loops: MediaPlayer.Infinite) with no visible window to stop it.
        source: root.visible && GlobalStates.videoEditorPath !== "" ? "file://" + encodeURI(GlobalStates.videoEditorPath) : ""
        videoOutput: videoOutput
        audioOutput: AudioOutput {
            volume: root.muteAudio ? 0 : root.previewVolume
        }
        loops: MediaPlayer.Infinite
        
        onPositionChanged: {
            if (player.position >= root.effectiveEndTime - 50) {
                player.position = root.startTime
            }
            if (player.position < root.startTime) {
                player.position = root.startTime
            }
        }
        
        onErrorChanged: {
            if (error !== MediaPlayer.NoError) {
                console.error("[VideoEditor] MediaPlayer Error:", errorString)
            }
        }
    }

    Process {
        id: sizeProcess
        running: false
        command: GlobalStates.videoEditorPath !== "" ? ["stat", "-c%s", GlobalStates.videoEditorPath] : ["true"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (this.text && this.text.trim().length > 0) {
                    root.currentFileSize = parseInt(this.text.trim()) || 0
                }
            }
        }
    }

    Process {
        id: probeProcess
        running: false
        stdout: SplitParser {
            onRead: data => root.handleProbeLine(data)
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0 || Number(root.videoMetadata.duration || 0) <= 0) root.metadataLoading = false
        }
    }

    Process {
        id: thumbnailProcess
        running: false
        stdout: SplitParser {
            onRead: data => root.handleThumbnailLine(data)
        }
    }

    Process {
        id: estimateProcess
        running: false
        stdout: SplitParser {
            onRead: data => {
                try {
                    const result = JSON.parse(String(data || "").trim())
                    if (result.ok) {
                        root.estimatedOutputSize = Number(result.estimatedSize || 0)
                        root.estimatedOutputLow = Number(result.low || 0)
                        root.estimatedOutputHigh = Number(result.high || 0)
                    }
                } catch (error) {
                    console.warn("[VideoEditor] Invalid estimate response:", data)
                }
            }
        }
    }

    Process {
        id: losslessProcess
        running: false
        stdout: SplitParser {
            onRead: data => root.handleExportLine(data)
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0 && root.renderState === "rendering") {
                root.renderState = "error"
                if (!root.renderErrorMessage) root.renderErrorMessage = Translation.tr("Lossless cut process exited with error.")
            }
        }
    }

    Process {
        id: exportProcess
        running: false
        stdout: SplitParser {
            onRead: data => root.handleExportLine(data)
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0 && root.renderState === "rendering") {
                root.renderState = "error"
                if (!root.renderErrorMessage) root.renderErrorMessage = Translation.tr("Export process exited with error.")
            }
        }
    }

    Timer {
        id: estimateTimer
        interval: Appearance.animation.elementMoveFast.duration
        repeat: false
        onTriggered: root.startEstimate()
    }

    Connections {
        target: GlobalStates
        function onVideoEditorPathChanged() {
            if (GlobalStates.videoEditorPath !== "") {
                sizeProcess.running = true
                root.loadMetadata()
            } else {
                root.currentFileSize = 0
                root.loadMetadata()
            }
        }
        function onVideoEditorMockRender(state, progress, format, errorMsg) {
            player.pause()
            root.renderState = state || "rendering"
            root.renderProgress = Number(progress >= 0 ? progress : 0)
            root.renderFormat = format || "mp4"
            root.renderDuration = 94.5
            root.renderElapsed = root.renderProgress * root.renderDuration
            root.renderOutputPath = `/home/pedro/Videos/render_export_mock.${root.renderFormat}`
            root.renderOutputSize = 14580000
            root.renderErrorMessage = errorMsg || ""
            root.renderPageOpen = true
        }
        function onVideoEditorBackRequested() {
            if (root.renderState === "rendering") {
                root.cancelExport()
            }
            root.renderPageOpen = false
            if (player.playbackState !== MediaPlayer.PlayingState) player.play()
        }
    }

    onVisibleChanged: {
        if (visible) {
            if (GlobalStates.videoEditorRenderPageOpen) {
                root.renderState = GlobalStates.videoEditorRenderState
                root.renderProgress = GlobalStates.videoEditorRenderProgress
                root.renderFormat = GlobalStates.videoEditorRenderFormat
                root.renderErrorMessage = GlobalStates.videoEditorRenderError
                root.renderDuration = 94.5
                root.renderElapsed = root.renderProgress * root.renderDuration
                root.renderOutputPath = `/home/pedro/Videos/render_export_mock.${root.renderFormat}`
                root.renderOutputSize = 14580000
                root.renderPageOpen = true
            } else {
                root.renderPageOpen = false
                root.renderState = "rendering"
                root.renderProgress = 0.0
                root.renderElapsed = 0.0
                root.renderDuration = 0.0
                root.renderOutputPath = ""
                root.renderErrorMessage = ""
            }
            cropW = -1
            startTime = 0
            endTime = -1
            compressionPercent = 100
            isCompressMode = false
            if (GlobalStates.videoEditorPath !== "") {
                player.play()
                sizeProcess.running = true
                root.loadMetadata()
            } else {
                player.stop()
                root.videoMetadata = ({})
                root.thumbnailPaths = []
                root.currentFileSize = 0
            }
        } else {
            GlobalStates.videoEditorRenderPageOpen = false
            player.stop()
            probeProcess.running = false
            thumbnailProcess.running = false
            estimateProcess.running = false
            exportProcess.running = false
        }
    }

    onCompressionPercentChanged: root.scheduleEstimate()
    onIsCompressModeChanged: root.scheduleEstimate()
    onCompressFormatChanged: root.scheduleEstimate()
    onGifScaleChanged: root.scheduleEstimate()
    onGifFpsChanged: root.scheduleEstimate()
    onGifDitherChanged: root.scheduleEstimate()
    onGifStatsModeChanged: root.scheduleEstimate()
    onGifColorsChanged: root.scheduleEstimate()
    onStartTimeChanged: root.scheduleEstimate()
    onEndTimeChanged: root.scheduleEstimate()
    onCropXChanged: root.scheduleEstimate()
    onCropYChanged: root.scheduleEstimate()
    onCropWChanged: root.scheduleEstimate()
    onCropHChanged: root.scheduleEstimate()

    // Timeline hover tooltip state
    property real timelineHoverPos: 0      // 0..1 fraction of timeline width
    property bool timelineHoverActive: false

    property real cropX: 0
    property real cropY: 0
    property real cropW: -1 
    property real cropH: -1
    property real startTime: 0
    property real endTime: -1
    readonly property real effectiveEndTime: endTime === -1 ? player.duration : endTime

    property real currentFileSize: 0
    property real compressionPercent: 100
    property bool isCompressMode: false
    property string compressFormat: "mp4"
    property real gifScale: 0.50
    property int gifFps: 15
    property string gifDither: "bayer"
    property int gifBayerScale: 3
    property string gifStatsMode: "diff"
    property int gifColors: 256
    property string gifDiffMode: "rectangle"

    property var videoMetadata: ({})
    property list<var> thumbnailPaths: []
    property bool metadataLoading: false
    property bool infoPopupOpen: false
    property real estimatedOutputSize: 0
    property real estimatedOutputLow: 0
    property real estimatedOutputHigh: 0
    property int rotation: 0
    property bool flipHorizontal: false
    property bool flipVertical: false
    property bool muteAudio: false
    property real previewVolume: 1.0
    property string outputResolution: "original" // "original", "1080p", "720p", "480p"

    property bool renderPageOpen: false
    property string renderState: "rendering"
    property real renderProgress: 0.0
    property real renderElapsed: 0.0
    property real renderDuration: 0.0
    property string renderFormat: "mp4"
    property string renderOutputPath: ""
    property int renderOutputSize: 0
    property string renderErrorMessage: ""

    function formatBytes(bytes) {
        const size = Number(bytes || 0)
        if (size <= 0) return "—"
        const units = ["B", "KiB", "MiB", "GiB"]
        const index = Math.min(units.length - 1, Math.floor(Math.log(size) / Math.log(1024)))
        return `${(size / Math.pow(1024, index)).toFixed(index === 0 ? 0 : 1)} ${units[index]}`
    }

    function formatDuration(seconds) {
        const total = Math.max(0, Math.round(Number(seconds || 0)))
        const hours = Math.floor(total / 3600)
        const minutes = Math.floor((total % 3600) / 60)
        const remainder = total % 60
        const pad = value => ("0" + value).slice(-2)
        return hours > 0 ? `${pad(hours)}:${pad(minutes)}:${pad(remainder)}` : `${pad(minutes)}:${pad(remainder)}`
    }

    function formatTimecode(ms) {
        const total = Math.max(0, ms)
        const h = Math.floor(total / 3600000)
        const m = Math.floor((total % 3600000) / 60000)
        const s = Math.floor((total % 60000) / 1000)
        const cs = Math.floor((total % 1000) / 10)
        const pad2 = v => ("0" + v).slice(-2)
        if (h > 0) return `${pad2(h)}:${pad2(m)}:${pad2(s)}.${pad2(cs)}`
        return `${pad2(m)}:${pad2(s)}.${pad2(cs)}`
    }

    function metadataResolution() {
        const video = root.videoMetadata.video || {}
        return Number(video.width || 0) > 0 ? `${video.width} × ${video.height}` : "—"
    }

    function effectiveGifWidth() {
        const sourceW = Number((root.videoMetadata.video || {}).width || 1920)
        return Math.max(2, Math.round((sourceW * root.gifScale) / 2) * 2)
    }

    function effectiveGifHeight() {
        const sourceH = Number((root.videoMetadata.video || {}).height || 1080)
        return Math.max(2, Math.round((sourceH * root.gifScale) / 2) * 2)
    }

    function gifDitherLabel(dither) {
        if (dither === "floyd_steinberg") return "Floyd-Steinberg"
        if (dither === "sierra2_4a") return "Sierra"
        if (dither === "none") return Translation.tr("No Dither")
        return Translation.tr("Bayer Dither")
    }

    function metadataFps() {
        const fps = Number((root.videoMetadata.video || {}).fps || 0)
        return fps > 0 ? `${fps.toFixed(fps % 1 === 0 ? 0 : 2)} FPS` : "—"
    }

    function metadataBitrate() {
        const bitrate = Number((root.videoMetadata.format || {}).bitrate || (root.videoMetadata.video || {}).bitrate || 0)
        if (bitrate <= 0) return "—"
        return bitrate >= 1000000 ? `${(bitrate / 1000000).toFixed(2)} Mbps` : `${Math.round(bitrate / 1000)} kbps`
    }

    function crfForCompressionPercent() {
        return Math.round(18 + (100 - Math.max(10, Math.min(100, root.compressionPercent))) * 0.35)
    }

    function exportSpec(replace, format = "mp4") {
        const uiWidth = Math.max(1, videoOutput.contentRect.width)
        const uiHeight = Math.max(1, videoOutput.contentRect.height)
        return {
            input: GlobalStates.videoEditorPath,
            format: format || "mp4",
            startSeconds: root.startTime / 1000,
            endSeconds: root.effectiveEndTime / 1000,
            crop: {
                x: root.cropW > 0 ? root.cropX : 0,
                y: root.cropH > 0 ? root.cropY : 0,
                w: root.cropW > 0 ? root.cropW : uiWidth,
                h: root.cropH > 0 ? root.cropH : uiHeight,
                uiW: uiWidth,
                uiH: uiHeight
            },
            crf: root.crfForCompressionPercent(),
            preset: "fast",
            rotation: root.rotation,
            flipHorizontal: root.flipHorizontal,
            flipVertical: root.flipVertical,
            mute: root.muteAudio,
            replaceOriginal: replace,
            outputPath: "",
            outputResolution: root.outputResolution,
            gifFps: root.gifFps,
            gifScale: root.gifScale,
            gifWidth: 0,
            gifDither: root.gifDither,
            gifBayerScale: root.gifBayerScale,
            gifStatsMode: root.gifStatsMode,
            gifColors: root.gifColors,
            gifDiffMode: root.gifDiffMode
        }
    }

    function losslessSpec(replace) {
        return {
            input: GlobalStates.videoEditorPath,
            format: "mp4",
            startSeconds: root.startTime / 1000,
            endSeconds: root.effectiveEndTime / 1000,
            crop: { x: 0, y: 0, w: -1, h: -1, uiW: 1, uiH: 1 },
            crf: 23,
            preset: "fast",
            rotation: 0,
            flipHorizontal: false,
            flipVertical: false,
            mute: false,
            replaceOriginal: replace,
            outputPath: "",
            gifFps: 15, gifScale: 0.5, gifWidth: 0,
            gifDither: "bayer", gifBayerScale: 3,
            gifStatsMode: "diff", gifColors: 256, gifDiffMode: "rectangle"
        }
    }

    function loadNewVideo(newPath) {
        if (!newPath || typeof newPath !== "string") return
        const cleanPath = newPath.trim()
        if (cleanPath.length === 0) return

        player.stop()
        probeProcess.running = false
        thumbnailProcess.running = false
        estimateProcess.running = false
        if (exportProcess.running) {
            root.cancelExport()
        }

        root.renderPageOpen = false
        root.renderState = "rendering"
        root.renderProgress = 0.0
        root.renderElapsed = 0.0
        root.renderDuration = 0.0
        root.renderOutputPath = ""
        root.renderErrorMessage = ""
        root.cropX = 0
        root.cropY = 0
        root.cropW = -1
        root.cropH = -1
        root.startTime = 0
        root.endTime = -1
        root.rotation = 0
        root.flipHorizontal = false
        root.flipVertical = false
        root.compressionPercent = 100
        root.isCompressMode = false
        root.infoPopupOpen = false
        root.videoMetadata = ({})
        root.thumbnailPaths = []
        root.estimatedOutputSize = 0
        root.estimatedOutputLow = 0
        root.estimatedOutputHigh = 0

        GlobalStates.videoEditorPath = cleanPath
        sizeProcess.running = true
        root.loadMetadata()
        player.play()
    }

    function loadMetadata() {
        if (GlobalStates.videoEditorPath === "") {
            root.videoMetadata = ({})
            root.thumbnailPaths = []
            root.metadataLoading = false
            return
        }
        root.metadataLoading = true
        root.videoMetadata = ({})
        root.thumbnailPaths = []
        root.estimatedOutputSize = 0
        root.estimatedOutputLow = 0
        root.estimatedOutputHigh = 0
        probeProcess.running = false
        probeProcess.command = ["python3", Directories.processVideoScriptPath, "probe", GlobalStates.videoEditorPath]
        probeProcess.running = true
    }

    function handleProbeLine(line) {
        const text = String(line || "").trim()
        if (!text) return
        try {
            const data = JSON.parse(text)
            if (data.ok) {
                root.videoMetadata = data
                root.currentFileSize = Number(data.size || root.currentFileSize)
                root.metadataLoading = false
                thumbnailProcess.running = false
                thumbnailProcess.command = ["python3", Directories.processVideoScriptPath, "thumbnails", GlobalStates.videoEditorPath, "8", Directories.tempImages]
                thumbnailProcess.running = true
                root.scheduleEstimate()
            }
        } catch (error) {
            console.warn("[VideoEditor] Invalid probe response:", text)
        }
    }

    function handleThumbnailLine(line) {
        try {
            const data = JSON.parse(String(line || "").trim())
            if (data.event !== "thumbnail") return
            const paths = root.thumbnailPaths.slice()
            paths[data.index] = data.path
            root.thumbnailPaths = paths
        } catch (error) {
            console.warn("[VideoEditor] Invalid thumbnail response:", line)
        }
    }

    function scheduleEstimate() {
        if (root.metadataLoading || root.videoMetadata.duration === undefined || root.isCompressMode === false) return
        root.estimatedOutputSize = 0
        root.estimatedOutputLow = 0
        root.estimatedOutputHigh = 0
        estimateTimer.restart()
    }

    function startEstimate() {
        if (GlobalStates.videoEditorPath === "" || Number(root.videoMetadata.duration || 0) <= 0) return
        estimateProcess.running = false
        const targetFmt = root.isCompressMode ? root.compressFormat : "mp4"
        estimateProcess.command = ["python3", Directories.processVideoScriptPath, "estimate", JSON.stringify(root.exportSpec(false, targetFmt))]
        estimateProcess.running = true
    }

    function applyPreset(ratio) {
        let vW = videoOutput.contentRect.width
        let vH = videoOutput.contentRect.height
        if (vW <= 0 || vH <= 0) return

        if (ratio === -1) {
            cropW = vW
            cropH = vH
            cropX = 0
            cropY = 0
            return
        }
        
        if (vW / vH > ratio) {
            cropH = vH
            cropW = vH * ratio
        } else {
            cropW = vW
            cropH = vW / ratio
        }
        cropX = (vW - cropW) / 2
        cropY = (vH - cropH) / 2
    }

    function resetTransformations() {
        root.rotation = 0
        root.flipHorizontal = false
        root.flipVertical = false
        root.muteAudio = false
        root.outputResolution = "original"
    }

    function handleExportLine(line) {
        const text = String(line || "").trim()
        if (!text) return
        try {
            const data = JSON.parse(text)
            if (data.event === "started") {
                root.renderState = "rendering"
                root.renderDuration = Number(data.duration || root.renderDuration)
                root.renderOutputPath = String(data.outputPath || "")
                root.renderFormat = String(data.format || root.renderFormat)
                root.renderProgress = 0.0
            } else if (data.event === "progress") {
                root.renderProgress = Math.max(root.renderProgress, Math.min(1.0, Number(data.value || 0)))
                root.renderElapsed = Number(data.elapsed || 0)
            } else if (data.event === "finished") {
                root.renderProgress = 1.0
                root.renderState = "done"
                root.renderOutputPath = String(data.outputPath || root.renderOutputPath)
                root.renderOutputSize = Number(data.size || 0)
                root.renderFormat = String(data.format || root.renderFormat)
            } else if (data.event === "error") {
                root.renderState = "error"
                root.renderErrorMessage = String(data.message || Translation.tr("Rendering failed."))
            }
        } catch (error) {
            console.warn("[VideoEditor] Invalid export response:", text)
        }
    }

    function cancelExport() {
        if (exportProcess.running) {
            exportProcess.running = false
        }
        if (losslessProcess.running) {
            losslessProcess.running = false
        }
        root.renderPageOpen = false
        if (player.playbackState !== MediaPlayer.PlayingState) player.play()
    }

    function losslessCut(replace) {
        player.pause()
        root.renderState = "rendering"
        root.renderProgress = 0.0
        root.renderElapsed = 0.0
        root.renderDuration = Math.max(0.1, (root.effectiveEndTime - root.startTime) / 1000)
        root.renderFormat = "mp4"
        root.renderOutputPath = ""
        root.renderOutputSize = 0
        root.renderErrorMessage = ""
        root.renderPageOpen = true

        losslessProcess.running = false
        losslessProcess.command = ["python3", Directories.processVideoScriptPath, "lossless_cut", JSON.stringify(root.losslessSpec(replace))]
        losslessProcess.running = true
    }

    function save(replace, format = "mp4") {
        if (videoOutput.contentRect.width <= 0) return

        player.pause()
        root.renderState = "rendering"
        root.renderProgress = 0.0
        root.renderElapsed = 0.0
        root.renderDuration = Math.max(0.1, (root.effectiveEndTime - root.startTime) / 1000)
        root.renderFormat = format || "mp4"
        root.renderOutputPath = ""
        root.renderOutputSize = 0
        root.renderErrorMessage = ""
        root.renderPageOpen = true

        exportProcess.running = false
        exportProcess.command = ["python3", Directories.processVideoScriptPath, "export", JSON.stringify(root.exportSpec(replace, format))]
        exportProcess.running = true
    }

    Rectangle {
        id: mainContainer
        anchors.fill: parent
        radius: Appearance.rounding.windowRounding
        
        color: Config.options.appearance.transparency.enable ? Appearance.colors.colLayer1 : Appearance.m3colors.m3surfaceContainer
        border.width: 1
        border.color: Appearance.colors.colLayer0Border


        Keys.onSpacePressed: {
            if (root.renderPageOpen) return
            if (player.playbackState === MediaPlayer.PlayingState) player.pause()
            else player.play()
        }
        Keys.onEscapePressed: {
            if (root.renderPageOpen) {
                root.renderPageOpen = false
                if (player.playbackState !== MediaPlayer.PlayingState) player.play()
            } else {
                GlobalStates.videoEditorOpen = false
            }
        }
        Keys.onPressed: (event) => {
            if (root.renderPageOpen) return
            if (GlobalStates.videoEditorPath === "") return
            const fps = Number((root.videoMetadata.video || {}).fps || 30)
            const frameMs = Math.max(16, Math.round(1000 / fps))
            if (event.key === Qt.Key_Left) {
                player.pause()
                player.position = Math.max(root.startTime, player.position - frameMs)
                event.accepted = true
            } else if (event.key === Qt.Key_Right) {
                player.pause()
                player.position = Math.min(root.effectiveEndTime, player.position + frameMs)
                event.accepted = true
            } else if (event.key === Qt.Key_I) {
                root.startTime = player.position
                event.accepted = true
            } else if (event.key === Qt.Key_O) {
                root.endTime = player.position
                event.accepted = true
            } else if (event.key === Qt.Key_Home) {
                player.position = root.startTime
                event.accepted = true
            } else if (event.key === Qt.Key_End) {
                player.position = root.effectiveEndTime
                event.accepted = true
            }
        }
        focus: root.visible

        // ── EDITOR PAGE (slides left when render page opens, like AiChat) ──
        Item {
            id: editorView
            anchors.fill: parent
            anchors.margins: 30
            opacity: root.renderPageOpen ? 0 : 1
            visible: opacity > 0.001
            enabled: !root.renderPageOpen

            transform: Translate {
                x: root.renderPageOpen ? -60 : 0
                Behavior on x {
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                    }
                }
            }
            Behavior on opacity {
                NumberAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                }
            }

            ColumnLayout {
                anchors.fill: parent
                spacing: 20

            RowLayout {
                Layout.fillWidth: true
                spacing: 16
                MaterialSymbol {
                    text: "movie_edit"
                    iconSize: 42
                    color: Appearance.colors.colPrimary
                }
                StyledText {
                    text: Translation.tr("Video Editor")
                    font.pixelSize: 32
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnSurface
                }
                Item { Layout.fillWidth: true }
                
                Rectangle {
                    visible: root.isCompressMode ? true : (root.compressionPercent < 100)
                    radius: 16
                    height: 32
                    width: chipLayout.implicitWidth + 24
                    color: Appearance.colors.colPrimaryContainer
                    RowLayout {
                        id: chipLayout
                        anchors.centerIn: parent
                        spacing: 8
                        MaterialSymbol {
                            text: (root.isCompressMode && root.compressFormat === "gif") ? "gif" : "compress"
                            iconSize: 18
                            color: Appearance.colors.colOnPrimaryContainer
                        }
                        StyledText {
                            text: {
                                if (root.isCompressMode && root.compressFormat === "gif") {
                                    return `GIF • ${root.gifFps} FPS • ${Math.round(root.gifScale * 100)}% • ${root.gifDitherLabel(root.gifDither)}`
                                }
                                return `${Math.round(100 - root.compressionPercent)}% Compression`
                            }
                            font.weight: Font.Bold
                            font.pixelSize: 14
                            color: Appearance.colors.colOnPrimaryContainer
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                RippleButton {
                    id: infoButton
                    enabled: GlobalStates.videoEditorPath !== "" && !root.metadataLoading
                    Layout.preferredWidth: 52
                    Layout.preferredHeight: 52
                    Layout.minimumWidth: 52
                    Layout.minimumHeight: 52
                    buttonRadius: 26
                    colBackground: root.infoPopupOpen ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSurfaceContainerHighest
                    contentItem: Item {
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "info"
                            iconSize: 24
                            color: root.infoPopupOpen ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurface
                        }
                    }
                    onClicked: root.infoPopupOpen = !root.infoPopupOpen
                }
                
                RippleButton {
                    id: closeBtn
                    Layout.leftMargin: Appearance.rounding.verysmall
                    Layout.preferredWidth: 52
                    Layout.preferredHeight: 52
                    Layout.minimumWidth: 52
                    Layout.minimumHeight: 52
                    buttonRadius: 26
                    colBackground: Appearance.colors.colSurfaceContainerHighest
                    contentItem: Item {
                        MaterialSymbol { 
                            anchors.centerIn: parent
                            text: "close"
                            iconSize: 24
                            color: Appearance.colors.colOnSurface 
                        }
                    }
                    onClicked: GlobalStates.videoEditorOpen = false
                }
            }

            Item {
                id: videoContainer
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                Process {
                    id: filePickerProcess
                    running: false
                    command: ["bash", "-c", "if command -v kdialog &> /dev/null; then FILE=$(kdialog --getopenfilename \"$HOME\" \"*.mp4 *.mkv *.webm *.avi *.mov\" 2>/dev/null); elif command -v zenity &> /dev/null; then FILE=$(zenity --file-selection --file-filter=\"Videos | *.mp4 *.mkv *.webm *.avi *.mov\" 2>/dev/null); fi; if [ -n \"$FILE\" ] && [ -f \"$FILE\" ]; then echo \"$FILE\"; fi"]
                    stdout: StdioCollector {
                        onStreamFinished: {
                            if (this.text && this.text.trim().length > 0) {
                                root.loadNewVideo(this.text.trim())
                            }
                        }
                    }
                }

                VideoOutput {
                    id: videoOutput
                    visible: GlobalStates.videoEditorPath !== ""
                    anchors.centerIn: parent
                    width: parent.width
                    height: parent.height
                    fillMode: VideoOutput.PreserveAspectFit
                    transform: [
                        Rotation {
                            angle: root.rotation
                            origin.x: videoOutput.width / 2
                            origin.y: videoOutput.height / 2
                        },
                        Scale {
                            xScale: root.flipHorizontal ? -1 : 1
                            yScale: root.flipVertical ? -1 : 1
                            origin.x: videoOutput.width / 2
                            origin.y: videoOutput.height / 2
                        }
                    ]

                    Item {
                        anchors.fill: parent
                        visible: root.cropW !== -1
                        Rectangle { x: videoOutput.contentRect.x; y: videoOutput.contentRect.y; width: videoOutput.contentRect.width; height: root.cropY; color: "#aa000000" }
                        Rectangle { x: videoOutput.contentRect.x; y: videoOutput.contentRect.y + root.cropY + root.cropH; width: videoOutput.contentRect.width; height: videoOutput.contentRect.height - (root.cropY + root.cropH); color: "#aa000000" }
                        Rectangle { x: videoOutput.contentRect.x; y: videoOutput.contentRect.y + root.cropY; width: root.cropX; height: root.cropH; color: "#aa000000" }
                        Rectangle { x: videoOutput.contentRect.x + root.cropX + root.cropW; y: videoOutput.contentRect.y + root.cropY; width: videoOutput.contentRect.width - (root.cropX + root.cropW); height: root.cropH; color: "#aa000000" }
                    }

                    Rectangle {
                        id: cropBox
                        visible: root.cropW !== -1
                        x: videoOutput.contentRect.x + root.cropX
                        y: videoOutput.contentRect.y + root.cropY
                        width: root.cropW
                        height: root.cropH
                        color: "transparent"
                        border.color: Appearance.colors.colPrimary
                        border.width: 2

                        MouseArea {
                            anchors.fill: parent
                            onPositionChanged: (mouse) => {
                                if (pressed) {
                                    let newX = Math.max(videoOutput.contentRect.x, Math.min(videoOutput.contentRect.x + videoOutput.contentRect.width - parent.width, parent.x + mouse.x - width/2))
                                    let newY = Math.max(videoOutput.contentRect.y, Math.min(videoOutput.contentRect.y + videoOutput.contentRect.height - parent.height, parent.y + mouse.y - height/2))
                                    root.cropX = newX - videoOutput.contentRect.x
                                    root.cropY = newY - videoOutput.contentRect.y
                                }
                            }
                        }

                        Rectangle {
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            width: 32
                            height: 32
                            radius: 16
                            color: Appearance.colors.colPrimary
                            MaterialSymbol { anchors.centerIn: parent; text: "expand_content"; iconSize: 20; color: Appearance.colors.colOnPrimary }
                            
                            MouseArea {
                                anchors.fill: parent
                                onPositionChanged: (mouse) => {
                                    if (pressed) {
                                        let newW = Math.max(50, parent.parent.width + mouse.x)
                                        let newH = Math.max(50, parent.parent.height + mouse.y)
                                        if (parent.parent.x + newW <= videoOutput.contentRect.x + videoOutput.contentRect.width) root.cropW = newW
                                        if (parent.parent.y + newH <= videoOutput.contentRect.y + videoOutput.contentRect.height) root.cropH = newH
                                    }
                                }
                            }
                        }
                    }
                }

                DropArea {
                    id: dropArea
                    anchors.fill: parent
                    z: 90
                    
                    onDropped: (drop) => {
                        if (drop.hasUrls && drop.urls.length > 0) {
                            let url = drop.urls[0].toString()
                            if (url.startsWith("file://")) {
                                url = url.substring(7)
                            }
                            const decoded = decodeURI(url)
                            if (decoded) {
                                root.loadNewVideo(decoded)
                            }
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        visible: GlobalStates.videoEditorPath === "" || dropArea.containsDrag
                        color: dropArea.containsDrag ? Appearance.colors.colSurfaceContainerHigh : "transparent"
                        radius: 16
                        border.color: dropArea.containsDrag ? Appearance.colors.colPrimary : Appearance.colors.colOutline
                        border.width: 2

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 16

                            MaterialSymbol {
                                text: "upload_file"
                                iconSize: 64
                                color: Appearance.colors.colOnSurfaceVariant
                                Layout.alignment: Qt.AlignHCenter
                            }

                            StyledText {
                                text: Translation.tr("Drag and drop a video here")
                                font.pixelSize: 20
                                font.weight: Font.Medium
                                color: Appearance.colors.colOnSurface
                                Layout.alignment: Qt.AlignHCenter
                            }

                            StyledText {
                                text: Translation.tr("or")
                                font.pixelSize: 16
                                color: Appearance.colors.colOnSurfaceVariant
                                Layout.alignment: Qt.AlignHCenter
                            }

                            RippleButton {
                                implicitWidth: 180
                                implicitHeight: 48
                                buttonRadius: 24
                                colBackground: Appearance.colors.colPrimary
                                Layout.alignment: Qt.AlignHCenter
                                contentItem: Item {
                                    RowLayout {
                                        anchors.centerIn: parent
                                        spacing: 8
                                        MaterialSymbol { text: "folder_open"; iconSize: 20; color: Appearance.colors.colOnPrimary }
                                        StyledText { text: Translation.tr("Browse Files"); font.pixelSize: 16; font.weight: Font.Bold; color: Appearance.colors.colOnPrimary }
                                    }
                                }
                                onClicked: filePickerProcess.running = true
                            }
                        }
                    }
                }

                RippleButton {
                    visible: GlobalStates.videoEditorPath !== ""
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.margins: 16
                    width: 56
                    height: 56
                    buttonRadius: 28
                    colBackground: "#aa000000"
                    contentItem: Item {
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: player.playbackState === MediaPlayer.PlayingState ? "pause" : "play_arrow"
                            iconSize: 32
                            color: "white"
                        }
                    }
                    onClicked: {
                        if (player.playbackState === MediaPlayer.PlayingState) player.pause()
                        else player.play()
                    }
                }
            }

            ColumnLayout {
                visible: GlobalStates.videoEditorPath !== ""
                Layout.fillWidth: true
                spacing: 24

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    // ── Trim header + timecode row ──
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText {
                            text: Translation.tr("Trim Video")
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnSurface
                        }
                        Item { Layout.fillWidth: true }

                        // Frame step buttons
                        RippleButton {
                            implicitWidth: 32; implicitHeight: 32; buttonRadius: 16
                            colBackground: Appearance.colors.colSurfaceContainerHighest
                            contentItem: MaterialSymbol { anchors.centerIn: parent; text: "skip_previous"; iconSize: 18; color: Appearance.colors.colOnSurface }
                            StyledToolTip { text: Translation.tr("Go to start (Home)") }
                            onClicked: player.position = root.startTime
                        }
                        Item { Layout.preferredWidth: 4 }
                        RippleButton {
                            implicitWidth: 32; implicitHeight: 32; buttonRadius: 16
                            colBackground: Appearance.colors.colSurfaceContainerHighest
                            contentItem: MaterialSymbol { anchors.centerIn: parent; text: "navigate_before"; iconSize: 18; color: Appearance.colors.colOnSurface }
                            StyledToolTip { text: Translation.tr("Previous frame (←)") }
                            onClicked: {
                                const fps = Number((root.videoMetadata.video || {}).fps || 30)
                                player.pause()
                                player.position = Math.max(root.startTime, player.position - Math.max(16, Math.round(1000 / fps)))
                            }
                        }
                        Item { Layout.preferredWidth: 4 }
                        RippleButton {
                            implicitWidth: 32; implicitHeight: 32; buttonRadius: 16
                            colBackground: Appearance.colors.colSurfaceContainerHighest
                            contentItem: MaterialSymbol { anchors.centerIn: parent; text: "navigate_next"; iconSize: 18; color: Appearance.colors.colOnSurface }
                            StyledToolTip { text: Translation.tr("Next frame (→)") }
                            onClicked: {
                                const fps = Number((root.videoMetadata.video || {}).fps || 30)
                                player.pause()
                                player.position = Math.min(root.effectiveEndTime, player.position + Math.max(16, Math.round(1000 / fps)))
                            }
                        }
                        Item { Layout.preferredWidth: 4 }
                        RippleButton {
                            implicitWidth: 32; implicitHeight: 32; buttonRadius: 16
                            colBackground: Appearance.colors.colSurfaceContainerHighest
                            contentItem: MaterialSymbol { anchors.centerIn: parent; text: "skip_next"; iconSize: 18; color: Appearance.colors.colOnSurface }
                            StyledToolTip { text: Translation.tr("Go to end (End)") }
                            onClicked: player.position = root.effectiveEndTime
                        }
                        Item { Layout.preferredWidth: 12 }

                        // In/Out point buttons — styled as mini handles for visual association
                        RippleButton {
                            implicitWidth: 44; implicitHeight: 32; buttonRadius: 8
                            colBackground: Appearance.colors.colSurfaceContainerHighest
                            StyledToolTip { text: Translation.tr("Set in point here (I)") }
                            onClicked: root.startTime = player.position
                            contentItem: Item {
                                Row {
                                    anchors.centerIn: parent
                                    spacing: 0
                                    // mini left-handle indicator
                                    Rectangle {
                                        width: 3; height: 20; radius: 2
                                        color: Appearance.colors.colPrimary
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    Item { width: 2; height: 1 }
                                    MaterialSymbol {
                                        text: "chevron_right"
                                        iconSize: 18
                                        color: Appearance.colors.colOnSurface
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }
                            }
                        }
                        Item { Layout.preferredWidth: 4 }
                        RippleButton {
                            implicitWidth: 44; implicitHeight: 32; buttonRadius: 8
                            colBackground: Appearance.colors.colSurfaceContainerHighest
                            StyledToolTip { text: Translation.tr("Set out point here (O)") }
                            onClicked: root.endTime = player.position
                            contentItem: Item {
                                Row {
                                    anchors.centerIn: parent
                                    spacing: 0
                                    MaterialSymbol {
                                        text: "chevron_left"
                                        iconSize: 18
                                        color: Appearance.colors.colOnSurface
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    Item { width: 2; height: 1 }
                                    // mini right-handle indicator
                                    Rectangle {
                                        width: 3; height: 20; radius: 2
                                        color: Appearance.colors.colPrimary
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }
                            }
                        }
                        Item { Layout.preferredWidth: 12 }

                        // Timecode display
                        Rectangle {
                            radius: Appearance.rounding.small
                            height: 32
                            width: timecodeLayout.implicitWidth + 20
                            color: Appearance.colors.colSurfaceContainerHighest
                            RowLayout {
                                id: timecodeLayout
                                anchors.centerIn: parent
                                spacing: 6
                                StyledText {
                                    text: root.formatTimecode(player.position)
                                    font.pixelSize: 13
                                    font.weight: Font.Bold
                                    color: Appearance.colors.colOnSurface
                                    font.family: Appearance.font.family.monospace
                                }
                                StyledText {
                                    text: "/"
                                    font.pixelSize: 13
                                    color: Appearance.colors.colOnSurfaceVariant
                                }
                                StyledText {
                                    text: root.formatTimecode(player.duration)
                                    font.pixelSize: 13
                                    color: Appearance.colors.colOnSurfaceVariant
                                    font.family: Appearance.font.family.monospace
                                }
                            }
                        }
                    }

                    Item {
                        id: timeline
                        Layout.fillWidth: true
                        Layout.preferredHeight: 50
                        Rectangle {
                            anchors.fill: parent
                            radius: 12
                            color: Appearance.colors.colSurfaceContainer
                            border.width: 1
                            border.color: Appearance.colors.colLayer0Border
                            Rectangle {
                                id: timelineTrack
                                anchors.fill: parent
                                anchors.margins: 4
                                radius: 8
                                color: Appearance.colors.colLayer1

                                Row {
                                    anchors.fill: parent
                                    visible: root.thumbnailPaths.length > 0
                                    clip: true
                                    Repeater {
                                        model: root.thumbnailPaths
                                        delegate: Item {
                                            required property var modelData
                                            width: timelineTrack.width / Math.max(1, root.thumbnailPaths.length)
                                            height: timelineTrack.height
                                            clip: true
                                            Image {
                                                anchors.fill: parent
                                                source: modelData ? "file://" + encodeURI(modelData) : ""
                                                fillMode: Image.PreserveAspectCrop
                                                asynchronous: true
                                                smooth: true
                                            }
                                        }
                                    }
                                }
                            }
                            MouseArea {
                                id: timelineMouseArea
                                anchors.fill: parent
                                hoverEnabled: true
                                onPressed: (mouse) => {
                                    let pos = Math.max(0, Math.min(1, mouse.x / width))
                                    player.position = pos * player.duration
                                }
                                onPositionChanged: (mouse) => {
                                    root.timelineHoverPos = Math.max(0, Math.min(1, mouse.x / width))
                                    root.timelineHoverActive = true
                                }
                                onExited: root.timelineHoverActive = false
                            }

                            // Hover tooltip
                            Rectangle {
                                id: timelineTooltip
                                visible: root.timelineHoverActive && player.duration > 0
                                x: Math.max(0, Math.min(parent.width - width, root.timelineHoverPos * parent.width - width / 2))
                                y: -36
                                z: 10
                                width: tooltipText.implicitWidth + 16
                                height: 28
                                radius: Appearance.rounding.small
                                color: Appearance.colors.colSurfaceContainerHighest
                                StyledText {
                                    id: tooltipText
                                    anchors.centerIn: parent
                                    text: root.formatTimecode(root.timelineHoverPos * player.duration)
                                    font.pixelSize: 12
                                    font.weight: Font.Bold
                                    color: Appearance.colors.colOnSurface
                                }
                            }
                        }
                        Rectangle {
                            x: (root.startTime / player.duration) * parent.width
                            width: ((root.effectiveEndTime - root.startTime) / player.duration) * parent.width
                            height: parent.height
                            color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.3)
                        }
                        Rectangle {
                            x: (player.position / player.duration) * parent.width - 2
                            width: 4; height: parent.height; color: Appearance.colors.colSecondary
                        }
                        // In/out time labels under handles
                        StyledText {
                            id: startTimeLabel
                            x: Math.max(0, Math.min(timeline.width - implicitWidth - 4, (root.startTime / player.duration) * timeline.width - implicitWidth / 2))
                            y: timeline.height + 2
                            text: root.formatTimecode(root.startTime)
                            font.pixelSize: 10
                            color: Appearance.colors.colPrimary
                            font.weight: Font.Bold
                        }
                        StyledText {
                            id: endTimeLabel
                            x: Math.max(0, Math.min(timeline.width - implicitWidth - 4, (root.effectiveEndTime / player.duration) * timeline.width - implicitWidth / 2))
                            y: timeline.height + 2
                            text: root.formatTimecode(root.effectiveEndTime)
                            font.pixelSize: 10
                            color: Appearance.colors.colPrimary
                            font.weight: Font.Bold
                        }

                        Rectangle {
                            id: startHandle
                            x: (root.startTime / player.duration) * parent.width - 15
                            width: 30; height: parent.height; radius: 6
                            color: Appearance.colors.colPrimary
                            z: 10
                            MaterialSymbol { anchors.centerIn: parent; text: "chevron_right"; iconSize: 18; color: Appearance.colors.colOnPrimary; z: 0 }
                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -6
                                propagateComposedEvents: false
                                cursorShape: Qt.SizeHorCursor
                                onPositionChanged: (mouse) => {
                                    if (pressed) {
                                        let newX = Math.max(-15, Math.min(endHandle.x - 40, startHandle.x + mouse.x - startHandle.width/2 - 6))
                                        root.startTime = Math.max(0, (newX + 15) / timeline.width * player.duration)
                                        player.position = root.startTime
                                    }
                                }
                                onPressed: (mouse) => { mouse.accepted = true; player.pause() }
                                onReleased: player.play()
                            }
                        }
                        Rectangle {
                            id: endHandle
                            x: (root.effectiveEndTime / player.duration) * parent.width - 15
                            width: 30; height: parent.height; radius: 6
                            color: Appearance.colors.colPrimary
                            z: 10
                            MaterialSymbol { anchors.centerIn: parent; text: "chevron_left"; iconSize: 18; color: Appearance.colors.colOnPrimary; z: 0 }
                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -6
                                propagateComposedEvents: false
                                cursorShape: Qt.SizeHorCursor
                                onPositionChanged: (mouse) => {
                                    if (pressed) {
                                        let newX = Math.max(startHandle.x + 40, Math.min(timeline.width - 15, endHandle.x + mouse.x - endHandle.width/2 - 6))
                                        root.endTime = Math.min(player.duration, (newX + 15) / timeline.width * player.duration)
                                        player.position = root.endTime
                                    }
                                }
                                onPressed: (mouse) => { mouse.accepted = true; player.pause() }
                                onReleased: player.play()
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 20
                    Layout.alignment: Qt.AlignBottom

                    // Compress Tools
                    ColumnLayout {
                        visible: root.isCompressMode
                        Layout.fillWidth: true
                        spacing: 12

                        // Top Row: Format Selector + Live Size Estimation + Action Buttons
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 16

                            // Format Selector Segmented Pills
                            RowLayout {
                                spacing: 8
                                
                                RippleButton {
                                    id: mp4TabBtn
                                    implicitWidth: 140
                                    implicitHeight: 40
                                    buttonRadius: 20
                                    property bool isActive: root.compressFormat === "mp4"
                                    colBackground: isActive ? Appearance.colors.colPrimary : Appearance.colors.colSurfaceContainerHighest
                                    contentItem: Item {
                                        RowLayout {
                                            anchors.centerIn: parent
                                            spacing: 6
                                            MaterialSymbol {
                                                text: "movie"
                                                iconSize: 18
                                                color: mp4TabBtn.isActive ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurface
                                            }
                                            StyledText {
                                                text: Translation.tr("Video (MP4)")
                                                font.pixelSize: 13
                                                font.weight: Font.DemiBold
                                                color: mp4TabBtn.isActive ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurface
                                            }
                                        }
                                    }
                                    onClicked: root.compressFormat = "mp4"
                                }

                                RippleButton {
                                    id: gifTabBtn
                                    implicitWidth: 150
                                    implicitHeight: 40
                                    buttonRadius: 20
                                    property bool isActive: root.compressFormat === "gif"
                                    colBackground: isActive ? Appearance.colors.colPrimary : Appearance.colors.colSurfaceContainerHighest
                                    contentItem: Item {
                                        RowLayout {
                                            anchors.centerIn: parent
                                            spacing: 6
                                            MaterialSymbol {
                                                text: "gif"
                                                iconSize: 20
                                                color: gifTabBtn.isActive ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurface
                                            }
                                            StyledText {
                                                text: Translation.tr("GIF Animation")
                                                font.pixelSize: 13
                                                font.weight: Font.DemiBold
                                                color: gifTabBtn.isActive ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurface
                                            }
                                        }
                                    }
                                    onClicked: root.compressFormat = "gif"
                                }
                            }

                            // Dynamic Estimated Size Pill
                            Rectangle {
                                id: estPill
                                radius: 20
                                Layout.preferredHeight: 40
                                Layout.preferredWidth: estContentRow.implicitWidth + 36
                                color: Appearance.colors.colSurfaceContainerHigh

                                RowLayout {
                                    id: estContentRow
                                    anchors.fill: parent
                                    anchors.leftMargin: 18
                                    anchors.rightMargin: 18
                                    spacing: 8

                                    MaterialSymbol {
                                        Layout.alignment: Qt.AlignVCenter
                                        text: "data_usage"
                                        iconSize: 18
                                        color: Appearance.colors.colPrimary
                                    }
                                    StyledText {
                                        Layout.alignment: Qt.AlignVCenter
                                        text: Translation.tr("Estimated Size") + ":"
                                        font.pixelSize: 12
                                        color: Appearance.colors.colOnSurfaceVariant
                                    }
                                    StyledText {
                                        id: estSizeText
                                        Layout.alignment: Qt.AlignVCenter
                                        text: root.estimatedOutputSize > 0
                                            ? `${root.formatBytes(root.currentFileSize)} ➔ ${root.formatBytes(root.estimatedOutputSize)}`
                                            : `${root.formatBytes(root.currentFileSize)} ➔ ${Translation.tr("calculating…")}`
                                        font.pixelSize: 13
                                        font.weight: Font.Bold
                                        color: Appearance.colors.colOnSurface
                                    }
                                }
                            }

                            Item { Layout.fillWidth: true }

                            // Action Button: Export Direct or Done
                            RippleButton {
                                implicitWidth: 160
                                implicitHeight: 44
                                buttonRadius: 22
                                colBackground: Appearance.colors.colPrimary
                                contentItem: Item {
                                    RowLayout {
                                        anchors.centerIn: parent
                                        spacing: 8
                                        MaterialSymbol {
                                            text: root.compressFormat === "gif" ? "gif" : "done"
                                            iconSize: 20
                                            color: Appearance.colors.colOnPrimary
                                        }
                                        StyledText {
                                            text: root.compressFormat === "gif" ? Translation.tr("Export GIF") : Translation.tr("Done")
                                            font.pixelSize: 14
                                            font.weight: Font.Bold
                                            color: Appearance.colors.colOnPrimary
                                        }
                                    }
                                }
                                onClicked: {
                                    if (root.compressFormat === "gif") {
                                        root.save(false, "gif")
                                    } else {
                                        root.isCompressMode = false
                                    }
                                }
                            }

                            RippleButton {
                                visible: root.compressFormat === "gif"
                                implicitWidth: 100
                                implicitHeight: 44
                                buttonRadius: 22
                                colBackground: Appearance.colors.colSurfaceContainerHighest
                                contentItem: Item {
                                    StyledText {
                                        anchors.centerIn: parent
                                        text: Translation.tr("Done")
                                        font.pixelSize: 14
                                        font.weight: Font.Bold
                                        color: Appearance.colors.colOnSurface
                                    }
                                }
                                onClicked: root.isCompressMode = false
                            }
                        }

                        // Bottom Section: MP4 Controls
                        RowLayout {
                            visible: root.compressFormat === "mp4"
                            Layout.fillWidth: true
                            spacing: 24

                            ColumnLayout {
                                spacing: 4
                                StyledText { text: Translation.tr("Compression Quality"); font.weight: Font.Medium; color: Appearance.colors.colOnSurface }
                                StyledSlider {
                                    id: compressSlider
                                    Layout.preferredWidth: 360
                                    from: 10
                                    to: 100
                                    value: root.compressionPercent
                                    onValueChanged: root.compressionPercent = value
                                }
                            }

                            Rectangle {
                                radius: 12
                                Layout.preferredHeight: 36
                                Layout.preferredWidth: crfText.implicitWidth + 24
                                color: Appearance.colors.colSurfaceContainerHighest
                                StyledText {
                                    id: crfText
                                    anchors.centerIn: parent
                                    text: `CRF ${root.crfForCompressionPercent()} • ${Math.round(root.compressionPercent)}%`
                                    font.pixelSize: 12
                                    font.weight: Font.Medium
                                    color: Appearance.colors.colOnSurfaceVariant
                                }
                            }

                            Item { Layout.fillWidth: true }
                        }

                        // Bottom Section: Resolution (MP4 only)
                        RowLayout {
                            visible: root.compressFormat === "mp4"
                            Layout.fillWidth: true
                            spacing: 16

                            StyledText {
                                text: Translation.tr("Output Resolution")
                                font.weight: Font.Medium
                                color: Appearance.colors.colOnSurface
                                Layout.alignment: Qt.AlignVCenter
                            }

                            RowLayout {
                                spacing: 6
                                Repeater {
                                    model: [
                                        { id: "original", label: Translation.tr("Original") },
                                        { id: "1080p",    label: "1080p" },
                                        { id: "720p",     label: "720p" },
                                        { id: "480p",     label: "480p" }
                                    ]
                                    delegate: RippleButton {
                                        required property var modelData
                                        property bool isActive: root.outputResolution === modelData.id
                                        implicitWidth: resLabel.implicitWidth + 24
                                        implicitHeight: 32
                                        buttonRadius: 16
                                        colBackground: isActive ? Appearance.colors.colPrimary : Appearance.colors.colSurfaceContainerHighest
                                        StyledToolTip {
                                            visible: modelData.id === "original"
                                            text: Translation.tr("Keep source resolution")
                                        }
                                        contentItem: StyledText {
                                            id: resLabel
                                            anchors.centerIn: parent
                                            text: modelData.label
                                            font.pixelSize: 13
                                            font.weight: Font.DemiBold
                                            color: isActive ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurface
                                        }
                                        onClicked: root.outputResolution = modelData.id
                                    }
                                }
                            }

                            Item { Layout.fillWidth: true }
                        }

                        // Bottom Section: GIF Controls (Resolution, FPS, Dither, Palette)
                        RowLayout {
                            visible: root.compressFormat === "gif"
                            Layout.fillWidth: true
                            spacing: 16

                            // Group 1: Resolution / Scale
                            ColumnLayout {
                                spacing: 6
                                RowLayout {
                                    Layout.preferredHeight: 20
                                    spacing: 6
                                    StyledText {
                                        Layout.alignment: Qt.AlignVCenter
                                        text: Translation.tr("Resolution")
                                        font.pixelSize: 12
                                        font.weight: Font.Medium
                                        color: Appearance.colors.colOnSurface
                                    }
                                    StyledText {
                                        Layout.alignment: Qt.AlignVCenter
                                        text: `(${root.effectiveGifWidth()} × ${root.effectiveGifHeight()})`
                                        font.pixelSize: 11
                                        color: Appearance.colors.colPrimary
                                        font.weight: Font.Bold
                                    }
                                }
                                RowLayout {
                                    spacing: 6
                                    Repeater {
                                        model: [
                                            { label: "100%", scale: 1.0 },
                                            { label: "75%", scale: 0.75 },
                                            { label: "50%", scale: 0.50 },
                                            { label: "33%", scale: 0.33 },
                                            { label: "25%", scale: 0.25 }
                                        ]
                                        delegate: RippleButton {
                                            id: scaleBtn
                                            required property var modelData
                                            implicitWidth: 56
                                            implicitHeight: 34
                                            buttonRadius: 17
                                            property bool isActive: Math.abs(root.gifScale - scaleBtn.modelData.scale) < 0.02
                                            colBackground: isActive ? Appearance.colors.colPrimary : Appearance.colors.colSurfaceContainerHighest
                                            contentItem: Item {
                                                StyledText {
                                                    anchors.centerIn: parent
                                                    text: scaleBtn.modelData.label
                                                    font.pixelSize: 12
                                                    font.weight: scaleBtn.isActive ? Font.Bold : Font.Medium
                                                    color: scaleBtn.isActive ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurface
                                                }
                                            }
                                            onClicked: root.gifScale = scaleBtn.modelData.scale
                                        }
                                    }
                                }
                            }

                            // Group 2: FPS
                            ColumnLayout {
                                spacing: 6
                                RowLayout {
                                    Layout.preferredHeight: 20
                                    StyledText {
                                        Layout.alignment: Qt.AlignVCenter
                                        text: Translation.tr("FPS")
                                        font.pixelSize: 12
                                        font.weight: Font.Medium
                                        color: Appearance.colors.colOnSurface
                                    }
                                }
                                RowLayout {
                                    spacing: 6
                                    Repeater {
                                        model: [10, 12, 15, 20, 24, 30]
                                        delegate: RippleButton {
                                            id: fpsBtn
                                            required property int modelData
                                            implicitWidth: 46
                                            implicitHeight: 34
                                            buttonRadius: 17
                                            property bool isActive: root.gifFps === fpsBtn.modelData
                                            colBackground: isActive ? Appearance.colors.colPrimary : Appearance.colors.colSurfaceContainerHighest
                                            contentItem: Item {
                                                StyledText {
                                                    anchors.centerIn: parent
                                                    text: `${fpsBtn.modelData}`
                                                    font.pixelSize: 12
                                                    font.weight: fpsBtn.isActive ? Font.Bold : Font.Medium
                                                    color: fpsBtn.isActive ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurface
                                                }
                                            }
                                            onClicked: root.gifFps = fpsBtn.modelData
                                        }
                                    }
                                }
                            }

                            // Group 3: Dither Method / Quality
                            ColumnLayout {
                                spacing: 6
                                RowLayout {
                                    Layout.preferredHeight: 20
                                    StyledText {
                                        Layout.alignment: Qt.AlignVCenter
                                        text: Translation.tr("Dither / Quality")
                                        font.pixelSize: 12
                                        font.weight: Font.Medium
                                        color: Appearance.colors.colOnSurface
                                    }
                                }
                                RowLayout {
                                    spacing: 6
                                    Repeater {
                                        model: [
                                            { id: "bayer", label: Translation.tr("Bayer") },
                                            { id: "floyd_steinberg", label: "Floyd-S" },
                                            { id: "sierra2_4a", label: "Sierra" },
                                            { id: "none", label: Translation.tr("None") }
                                        ]
                                        delegate: RippleButton {
                                            id: ditherBtn
                                            required property var modelData
                                            implicitWidth: Math.max(68, dText.implicitWidth + 24)
                                            implicitHeight: 34
                                            buttonRadius: 17
                                            property bool isActive: root.gifDither === ditherBtn.modelData.id
                                            colBackground: isActive ? Appearance.colors.colPrimary : Appearance.colors.colSurfaceContainerHighest
                                            contentItem: Item {
                                                StyledText {
                                                    id: dText
                                                    anchors.centerIn: parent
                                                    text: ditherBtn.modelData.label
                                                    font.pixelSize: 12
                                                    font.weight: ditherBtn.isActive ? Font.Bold : Font.Medium
                                                    color: ditherBtn.isActive ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurface
                                                }
                                            }
                                            onClicked: root.gifDither = ditherBtn.modelData.id
                                        }
                                    }
                                }
                            }

                            // Group 4: Colors
                            ColumnLayout {
                                spacing: 6
                                RowLayout {
                                    Layout.preferredHeight: 20
                                    StyledText {
                                        Layout.alignment: Qt.AlignVCenter
                                        text: Translation.tr("Colors")
                                        font.pixelSize: 12
                                        font.weight: Font.Medium
                                        color: Appearance.colors.colOnSurface
                                    }
                                }
                                RowLayout {
                                    spacing: 6
                                    Repeater {
                                        model: [256, 128, 64, 32]
                                        delegate: RippleButton {
                                            id: colorsBtn
                                            required property int modelData
                                            implicitWidth: 48
                                            implicitHeight: 34
                                            buttonRadius: 17
                                            property bool isActive: root.gifColors === colorsBtn.modelData
                                            colBackground: isActive ? Appearance.colors.colPrimary : Appearance.colors.colSurfaceContainerHighest
                                            contentItem: Item {
                                                StyledText {
                                                    anchors.centerIn: parent
                                                    text: `${colorsBtn.modelData}`
                                                    font.pixelSize: 12
                                                    font.weight: colorsBtn.isActive ? Font.Bold : Font.Medium
                                                    color: colorsBtn.isActive ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurface
                                                }
                                            }
                                            onClicked: root.gifColors = colorsBtn.modelData
                                        }
                                    }
                                }
                            }

                            Item { Layout.fillWidth: true }
                        }
                    }

                    // Default Tools
                    RowLayout {
                        visible: !root.isCompressMode
                        Layout.fillWidth: true
                        spacing: 20

                        ColumnLayout {
                            spacing: 8
                            StyledText { text: Translation.tr("Aspect Ratio"); font.weight: Font.Medium; color: Appearance.colors.colOnSurface }
                            RowLayout {
                                spacing: 8
                                Repeater {
                                    model: [
                                        { name: "Free", ratio: -1, icon: "aspect_ratio" },
                                        { name: "16:9", ratio: 1.7777777777777777, icon: "rectangle" },
                                        { name: "9:16", ratio: 0.5625, icon: "smartphone" },
                                        { name: "4:3", ratio: 1.3333333333333333, icon: "desktop_windows" },
                                        { name: "1:1", ratio: 1, icon: "square" }
                                    ]
                                    delegate: RippleButton {
                                        id: ratioBtn
                                        required property var modelData
                                        implicitWidth: 100
                                        implicitHeight: 44
                                        buttonRadius: 22
                                        property bool isActive: root.cropW !== -1 && Math.abs((root.cropW/root.cropH) - ratioBtn.modelData.ratio) < 0.01 || (root.cropW === videoOutput.contentRect.width && ratioBtn.modelData.ratio === -1)
                                        colBackground: isActive ? Appearance.colors.colPrimary : Appearance.colors.colSurfaceContainerHighest
                                        contentItem: Item {
                                            RowLayout {
                                                anchors.centerIn: parent
                                                spacing: 8
                                                MaterialSymbol { text: ratioBtn.modelData.icon; iconSize: 18; color: ratioBtn.isActive ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurface }
                                                StyledText { text: ratioBtn.modelData.name; font.weight: Font.Medium; color: ratioBtn.isActive ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurface }
                                            }
                                        }
                                        onClicked: root.applyPreset(ratioBtn.modelData.ratio)
                                    }
                                }
                            }

                            RowLayout {
                                spacing: 8
                                Layout.topMargin: 4

                                RippleButton {
                                    implicitWidth: 44
                                    implicitHeight: 44
                                    buttonRadius: 22
                                    colBackground: Appearance.colors.colSurfaceContainerHighest
                                    contentItem: MaterialSymbol { anchors.centerIn: parent; text: "restart_alt"; iconSize: 20; color: Appearance.colors.colOnSurface }
                                    StyledToolTip { text: Translation.tr("Reset transformations") }
                                    onClicked: root.resetTransformations()
                                }

                                RippleButton {
                                    implicitWidth: 44
                                    implicitHeight: 44
                                    buttonRadius: 22
                                    colBackground: root.rotation !== 0 ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSurfaceContainerHighest
                                    contentItem: MaterialSymbol { anchors.centerIn: parent; text: "rotate_right"; iconSize: 20; color: root.rotation !== 0 ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurface }
                                    StyledToolTip { text: Translation.tr("Rotate 90°") }
                                    onClicked: root.rotation = (root.rotation + 90) % 360
                                }

                                RippleButton {
                                    implicitWidth: 44
                                    implicitHeight: 44
                                    buttonRadius: 22
                                    toggled: root.flipHorizontal
                                    colBackground: root.flipHorizontal ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSurfaceContainerHighest
                                    contentItem: MaterialSymbol { anchors.centerIn: parent; text: "flip"; iconSize: 20; color: root.flipHorizontal ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurface }
                                    StyledToolTip { text: Translation.tr("Flip horizontal") }
                                    onClicked: root.flipHorizontal = !root.flipHorizontal
                                }

                                RippleButton {
                                    implicitWidth: 44
                                    implicitHeight: 44
                                    buttonRadius: 22
                                    toggled: root.flipVertical
                                    colBackground: root.flipVertical ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSurfaceContainerHighest
                                    contentItem: MaterialSymbol { anchors.centerIn: parent; text: "flip"; iconSize: 20; color: root.flipVertical ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurface }
                                    StyledToolTip { text: Translation.tr("Flip vertical") }
                                    onClicked: root.flipVertical = !root.flipVertical
                                }

                                // Volume control: icon + slider
                                RowLayout {
                                    spacing: 4

                                    RippleButton {
                                        implicitWidth: 44
                                        implicitHeight: 44
                                        buttonRadius: 22
                                        toggled: root.muteAudio
                                        colBackground: root.muteAudio ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSurfaceContainerHighest
                                        contentItem: MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: {
                                                if (root.muteAudio || root.previewVolume === 0) return "volume_off"
                                                if (root.previewVolume < 0.4) return "volume_down"
                                                return "volume_up"
                                            }
                                            iconSize: 20
                                            color: root.muteAudio ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurface
                                        }
                                        StyledToolTip { text: root.muteAudio ? Translation.tr("Unmute preview") : Translation.tr("Mute preview") }
                                        onClicked: root.muteAudio = !root.muteAudio
                                    }

                                    StyledSlider {
                                        id: volumeSlider
                                        Layout.preferredWidth: 90
                                        from: 0.0
                                        to: 1.0
                                        value: root.muteAudio ? 0 : root.previewVolume
                                        enabled: !root.muteAudio
                                        opacity: root.muteAudio ? 0.4 : 1.0
                                        Behavior on opacity { NumberAnimation { duration: 150 } }
                                        onValueChanged: {
                                            if (!root.muteAudio) root.previewVolume = value
                                        }
                                    }
                                }
                            }
                        }

                        Item { Layout.fillWidth: true }

                        RowLayout {
                            spacing: 12
                            Layout.alignment: Qt.AlignBottom
                            
                            RippleButton {
                                implicitWidth: 160
                                implicitHeight: 56
                                buttonRadius: 28
                                colBackground: Appearance.colors.colSurfaceContainerHighest
                                contentItem: Item {
                                    RowLayout {
                                        anchors.centerIn: parent
                                        spacing: 12
                                        MaterialSymbol { text: "compress"; iconSize: 24; color: Appearance.colors.colOnSurface }
                                        StyledText { text: Translation.tr("Compress"); font.pixelSize: 16; font.weight: Font.Bold; color: Appearance.colors.colOnSurface }
                                    }
                                }
                                onClicked: root.isCompressMode = true
                            }

                            MaterialSplitButton {
                                buttonHeight: 56
                                colBackground: Appearance.colors.colSurfaceContainerHighest
                                colForeground: Appearance.colors.colOnSurface
                                colBackgroundHover: Appearance.colors.colSurfaceContainerHigh
                                colBackgroundActive: Appearance.colors.colSurfaceContainer
                                colRipple: Appearance.colors.colSurfaceContainer
                                text: Translation.tr("Save Copy")
                                icon: "content_copy"
                                popupDirection: "up"
                                model: [
                                    {
                                        id: "mp4",
                                        label: Translation.tr("Video (MP4)"),
                                        icon: "movie",
                                        description: Translation.tr("Standard video export")
                                    },
                                    {
                                        id: "mp3",
                                        label: Translation.tr("Audio (MP3)"),
                                        icon: "music_note",
                                        description: Translation.tr("Extract audio track")
                                    },
                                    {
                                        id: "gif",
                                        label: Translation.tr("GIF Animation"),
                                        icon: "gif",
                                        description: Translation.tr("High-quality animated GIF")
                                    }
                                ]
                                onClicked: root.save(false, "mp4")
                                onActionSelected: (id, item) => {
                                    root.save(false, id);
                                }
                            }

                            RippleButton {
                                implicitWidth: 220
                                implicitHeight: 56
                                buttonRadius: 28
                                colBackground: Appearance.colors.colPrimary
                                contentItem: Item {
                                    RowLayout {
                                        anchors.centerIn: parent
                                        spacing: 12
                                        MaterialSymbol { text: "check_circle"; iconSize: 24; color: Appearance.colors.colOnPrimary }
                                        StyledText { text: Translation.tr("Save and Replace"); font.pixelSize: 16; font.weight: Font.Bold; color: Appearance.colors.colOnPrimary }
                                    }
                                }
                                onClicked: root.save(true)
                            }
                        }
                    }
                }
            }
        }
        }

        // ── RENDER SUBPAGE (slides in from right, like AiChat) ──
        VideoEditorRenderPage {
            id: renderPageView
            anchors.fill: parent
            anchors.margins: 30
            opacity: root.renderPageOpen ? 1 : 0
            visible: opacity > 0.001
            enabled: root.renderPageOpen

            transform: Translate {
                x: root.renderPageOpen ? 0 : 60
                Behavior on x {
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                    }
                }
            }
            Behavior on opacity {
                NumberAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                }
            }

            renderState: root.renderState
            renderProgress: root.renderProgress
            renderElapsed: root.renderElapsed
            renderDuration: root.renderDuration
            renderFormat: root.renderFormat
            renderGifDither: root.gifDitherLabel(root.gifDither)
            renderGifColors: root.gifColors
            renderOutputPath: root.renderOutputPath
            renderOutputSize: root.renderOutputSize
            renderErrorMessage: root.renderErrorMessage
            previewSource: root.thumbnailPaths.length > 0 ? root.thumbnailPaths[0] : ""
            videoPath: GlobalStates.videoEditorPath
            videoWidth: root.renderFormat === "gif" ? root.effectiveGifWidth() : Number((root.videoMetadata.video || {}).width || 0)
            videoHeight: root.renderFormat === "gif" ? root.effectiveGifHeight() : Number((root.videoMetadata.video || {}).height || 0)
            videoFps: root.renderFormat === "gif" ? `${root.gifFps} FPS` : root.metadataFps()
            videoBitrate: root.metadataBitrate()
            originalSize: Number(root.videoMetadata.size || root.currentFileSize)
            muteAudio: root.muteAudio

            onCloseRequested: GlobalStates.videoEditorOpen = false
            onBackRequested: {
                if (root.renderState === "rendering") {
                    root.cancelExport()
                }
                root.renderPageOpen = false
                if (player.playbackState !== MediaPlayer.PlayingState) player.play()
            }
            onCancelRequested: {
                root.cancelExport()
                root.renderPageOpen = false
                if (player.playbackState !== MediaPlayer.PlayingState) player.play()
            }
            onOpenFileRequested: {
                const path = root.renderOutputPath || GlobalStates.videoEditorPath
                if (path) Quickshell.execDetached(["xdg-open", path])
            }
            onOpenFolderRequested: {
                const path = root.renderOutputPath || GlobalStates.videoEditorPath
                if (path) {
                    const dir = FileUtils.parentDirectory(path)
                    Quickshell.execDetached(["xdg-open", dir])
                }
            }
            onCopyPathRequested: {
                const path = root.renderOutputPath || GlobalStates.videoEditorPath
                if (path) Quickshell.clipboardText = path
            }
        }

        Rectangle {
            id: infoPopup
            visible: !root.renderPageOpen && root.infoPopupOpen && GlobalStates.videoEditorPath !== ""
            z: 20
            anchors.top: parent.top
            anchors.topMargin: 30 + infoButton.height + 8
            anchors.right: parent.right
            anchors.rightMargin: 30
            width: 300
            height: infoLayout.implicitHeight + 40
            radius: Appearance.rounding.large
            color: Appearance.colors.colSurfaceContainerHigh

            StyledRectangularShadow { target: infoPopup }

            ColumnLayout {
                id: infoLayout
                anchors.fill: parent
                anchors.margins: 20
                spacing: 8

                StyledText {
                    text: Translation.tr("Original video")
                    font.pixelSize: 17
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnSurface
                }

                RowLayout {
                    Layout.fillWidth: true
                    StyledText { text: Translation.tr("Duration"); color: Appearance.colors.colOnSurfaceVariant; Layout.fillWidth: true }
                    StyledText { text: root.formatDuration(root.videoMetadata.duration !== undefined ? root.videoMetadata.duration : player.duration / 1000); color: Appearance.colors.colOnSurface; font.weight: Font.Medium }
                }
                RowLayout {
                    Layout.fillWidth: true
                    StyledText { text: Translation.tr("FPS"); color: Appearance.colors.colOnSurfaceVariant; Layout.fillWidth: true }
                    StyledText { text: root.metadataFps(); color: Appearance.colors.colOnSurface; font.weight: Font.Medium }
                }
                RowLayout {
                    Layout.fillWidth: true
                    StyledText { text: Translation.tr("Resolution"); color: Appearance.colors.colOnSurfaceVariant; Layout.fillWidth: true }
                    StyledText { text: root.metadataResolution(); color: Appearance.colors.colOnSurface; font.weight: Font.Medium }
                }
                RowLayout {
                    Layout.fillWidth: true
                    StyledText { text: Translation.tr("Bitrate"); color: Appearance.colors.colOnSurfaceVariant; Layout.fillWidth: true }
                    StyledText { text: root.metadataBitrate(); color: Appearance.colors.colOnSurface; font.weight: Font.Medium }
                }
                RowLayout {
                    Layout.fillWidth: true
                    StyledText { text: Translation.tr("Size"); color: Appearance.colors.colOnSurfaceVariant; Layout.fillWidth: true }
                    StyledText { text: root.formatBytes(root.videoMetadata.size || root.currentFileSize); color: Appearance.colors.colOnSurface; font.weight: Font.Medium }
                }
            }
        }
    }
}
