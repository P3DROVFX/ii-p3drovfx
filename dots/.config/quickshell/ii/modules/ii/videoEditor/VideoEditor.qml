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
        audioOutput: AudioOutput {}
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

    Connections {
        target: GlobalStates
        function onVideoEditorPathChanged() {
            if (GlobalStates.videoEditorPath !== "") {
                sizeProcess.running = true
            } else {
                root.currentFileSize = 0
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
        } else {
            player.stop()
        }
    }

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

    function save(replace) {
        if (videoOutput.contentRect.width <= 0) return
        
        let args = [
            Directories.processVideoScriptPath,
            GlobalStates.videoEditorPath,
            Math.round(cropW),
            Math.round(cropH),
            Math.round(cropX),
            Math.round(cropY),
            Math.round(startTime),
            Math.round(effectiveEndTime),
            Math.round(videoOutput.contentRect.width),
            Math.round(videoOutput.contentRect.height),
            replace ? "1" : "0",
            Math.round(compressionPercent)
        ]
        Quickshell.execDetached(args)
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
                    id: closeBtn
                    width: 52
                    height: 52
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
                            Rectangle { anchors.fill: parent; anchors.margins: 4; radius: 8; color: Appearance.colors.colLayer1 }
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
                                text: `${(root.currentFileSize / (1024*1024)).toFixed(1)} MB ➔ ${((root.currentFileSize * (root.compressionPercent/100)) / (1024*1024)).toFixed(1)} MB`
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
    }
}
