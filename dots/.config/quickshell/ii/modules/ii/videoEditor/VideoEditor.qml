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
            volume: root.muteAudio ? 0 : 1
        }
        loops: MediaPlayer.Infinite
        
        onPositionChanged: {
            if (position >= root.effectiveEndTime - 50) {
                position = root.startTime
            }
            if (position < root.startTime) {
                position = root.startTime
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
        command: ["stat", "-c%s", GlobalStates.videoEditorPath]
        stdout: StdioCollector {
            onStreamFinished: {
                if (this.text) {
                    root.currentFileSize = parseInt(this.text.trim())
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
    }

    onVisibleChanged: {
        if (visible) {
            player.play()
            cropW = -1
            startTime = 0
            endTime = -1
            compressionPercent = 100
            isCompressMode = false
            sizeProcess.running = true
            root.loadMetadata()
        } else {
            player.stop()
            probeProcess.running = false
            thumbnailProcess.running = false
            estimateProcess.running = false
        }
    }

    onCompressionPercentChanged: root.scheduleEstimate()
    onIsCompressModeChanged: root.scheduleEstimate()
    onStartTimeChanged: root.scheduleEstimate()
    onEndTimeChanged: root.scheduleEstimate()
    onCropXChanged: root.scheduleEstimate()
    onCropYChanged: root.scheduleEstimate()
    onCropWChanged: root.scheduleEstimate()
    onCropHChanged: root.scheduleEstimate()

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

    function metadataResolution() {
        const video = root.videoMetadata.video || {}
        return Number(video.width || 0) > 0 ? `${video.width} × ${video.height}` : "—"
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

    function exportSpec(replace) {
        const uiWidth = Math.max(1, videoOutput.contentRect.width)
        const uiHeight = Math.max(1, videoOutput.contentRect.height)
        return {
            input: GlobalStates.videoEditorPath,
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
            outputPath: ""
        }
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
        estimateProcess.command = ["python3", Directories.processVideoScriptPath, "estimate", JSON.stringify(root.exportSpec(false))]
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
    }

    function save(replace) {
        if (videoOutput.contentRect.width <= 0) return

        Quickshell.execDetached(["python3", Directories.processVideoScriptPath, "export", JSON.stringify(root.exportSpec(replace))])
        GlobalStates.videoEditorOpen = false
    }

    Rectangle {
        id: mainContainer
        anchors.fill: parent
        radius: Appearance.rounding.windowRounding
        
        color: Config.options.appearance.transparency.enable ? Appearance.colors.colLayer1 : Appearance.m3colors.m3surfaceContainer
        border.width: 1
        border.color: Appearance.colors.colLayer0Border

        MouseArea {
            anchors.fill: parent
            z: -1
            onPressed: root.startSystemMove()
        }

        Keys.onSpacePressed: {
            if (player.playbackState === MediaPlayer.PlayingState) player.pause()
            else player.play()
        }
        Keys.onEscapePressed: GlobalStates.videoEditorOpen = false
        focus: root.visible

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 30
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
                    visible: root.compressionPercent < 100
                    radius: 16
                    height: 32
                    width: chipLayout.implicitWidth + 24
                    color: Appearance.colors.colPrimaryContainer
                    RowLayout {
                        id: chipLayout
                        anchors.centerIn: parent
                        spacing: 8
                        MaterialSymbol { text: "compress"; iconSize: 18; color: Appearance.colors.colOnPrimaryContainer }
                        StyledText { text: `${Math.round(100 - root.compressionPercent)}% Compression`; font.weight: Font.Bold; font.pixelSize: 14; color: Appearance.colors.colOnPrimaryContainer }
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
                                GlobalStates.videoEditorPath = this.text.trim()
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
                    visible: GlobalStates.videoEditorPath === ""
                    
                    onDropped: (drop) => {
                        if (drop.hasUrls) {
                            let url = drop.urls[0].toString()
                            if (url.startsWith("file://")) {
                                url = url.substring(7)
                            }
                            GlobalStates.videoEditorPath = decodeURI(url)
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
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
                    StyledText { text: Translation.tr("Trim Video"); font.weight: Font.Medium; color: Appearance.colors.colOnSurface }
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
                                anchors.fill: parent
                                onPressed: (mouse) => {
                                    let pos = Math.max(0, Math.min(1, mouse.x / width))
                                    player.position = pos * player.duration
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
                        Rectangle {
                            id: startHandle
                            x: (root.startTime / player.duration) * parent.width - 15
                            width: 30; height: parent.height; radius: 6; color: Appearance.colors.colPrimary
                            MaterialSymbol { anchors.centerIn: parent; text: "chevron_right"; iconSize: 18; color: Appearance.colors.colOnPrimary }
                            MouseArea {
                                anchors.fill: parent
                                onPositionChanged: (mouse) => {
                                    if (pressed) {
                                        let newX = Math.max(-15, Math.min(endHandle.x - 40, parent.x + mouse.x - width/2))
                                        root.startTime = Math.max(0, (newX + 15) / timeline.width * player.duration)
                                        player.position = root.startTime
                                    }
                                }
                                onPressed: player.pause(); onReleased: player.play()
                            }
                        }
                        Rectangle {
                            id: endHandle
                            x: (root.effectiveEndTime / player.duration) * parent.width - 15
                            width: 30; height: parent.height; radius: 6; color: Appearance.colors.colPrimary
                            MaterialSymbol { anchors.centerIn: parent; text: "chevron_left"; iconSize: 18; color: Appearance.colors.colOnPrimary }
                            MouseArea {
                                anchors.fill: parent
                                onPositionChanged: (mouse) => {
                                    if (pressed) {
                                        let newX = Math.max(startHandle.x + 40, Math.min(timeline.width - 15, parent.x + mouse.x - width/2))
                                        root.endTime = Math.min(player.duration, (newX + 15) / timeline.width * player.duration)
                                        player.position = root.endTime
                                    }
                                }
                                onPressed: player.pause(); onReleased: player.play()
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 20
                    Layout.alignment: Qt.AlignBottom

                    // Compress Tools
                    RowLayout {
                        visible: root.isCompressMode
                        Layout.fillWidth: true
                        spacing: 24
                        
                        ColumnLayout {
                            spacing: 8
                            StyledText { text: Translation.tr("Compression Quality"); font.weight: Font.Medium; color: Appearance.colors.colOnSurface }
                            StyledSlider {
                                id: compressSlider
                                Layout.preferredWidth: 300
                                from: 10
                                to: 100
                                value: root.compressionPercent
                                onValueChanged: root.compressionPercent = value
                            }
                        }

                        ColumnLayout {
                            spacing: 4
                            Layout.alignment: Qt.AlignVCenter
                            StyledText { 
                                text: Translation.tr("Estimated Size")
                                font.pixelSize: 12
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                            StyledText { 
                                text: root.estimatedOutputSize > 0
                                    ? `${root.formatBytes(root.currentFileSize)} ➔ ${root.formatBytes(root.estimatedOutputSize)}`
                                    : `${root.formatBytes(root.currentFileSize)} ➔ ${Translation.tr("calculating…")}`
                                font.pixelSize: 16
                                font.weight: Font.Bold
                                color: Appearance.colors.colOnSurface
                            }
                        }

                        Item { Layout.fillWidth: true }

                        RippleButton {
                            implicitWidth: 160
                            implicitHeight: 56
                            buttonRadius: 28
                            colBackground: Appearance.colors.colPrimary
                            contentItem: Item {
                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: 12
                                    MaterialSymbol { text: "done"; iconSize: 24; color: Appearance.colors.colOnPrimary }
                                    StyledText { text: Translation.tr("Done"); font.pixelSize: 16; font.weight: Font.Bold; color: Appearance.colors.colOnPrimary }
                                }
                            }
                            onClicked: root.isCompressMode = false
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

                                RippleButton {
                                    implicitWidth: 44
                                    implicitHeight: 44
                                    buttonRadius: 22
                                    toggled: root.muteAudio
                                    colBackground: root.muteAudio ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSurfaceContainerHighest
                                    contentItem: MaterialSymbol { anchors.centerIn: parent; text: root.muteAudio ? "volume_off" : "volume_up"; iconSize: 20; color: root.muteAudio ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurface }
                                    StyledToolTip { text: Translation.tr("Mute audio") }
                                    onClicked: root.muteAudio = !root.muteAudio
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

                            RippleButton {
                                implicitWidth: 180
                                implicitHeight: 56
                                buttonRadius: 28
                                colBackground: Appearance.colors.colSurfaceContainerHighest
                                contentItem: Item {
                                    RowLayout {
                                        anchors.centerIn: parent
                                        spacing: 12
                                        MaterialSymbol { text: "content_copy"; iconSize: 24; color: Appearance.colors.colOnSurface }
                                        StyledText { text: Translation.tr("Save Copy"); font.pixelSize: 16; font.weight: Font.Bold; color: Appearance.colors.colOnSurface }
                                    }
                                }
                                onClicked: root.save(false)
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

        Rectangle {
            id: infoPopup
            visible: root.infoPopupOpen && GlobalStates.videoEditorPath !== ""
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
