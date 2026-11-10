pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../common/functions/recordingQuality.js" as RecordingQuality

Rectangle {
    id: root

    property bool isPreview: false
    signal closeRequested()
    signal recordRequested()

    // Symmetrical padding on all 4 sides (top, bottom, left, right = 8px)
    readonly property real toolbarPadding: 8

    // Active section requested: "", "video", "audio", "countdown", "options"
    property string activeSection: GlobalStates.recordingToolbarSection
    property alias expandedSection: root.activeSection
    readonly property string selectedMode: modeTabBar.currentMode
    onActiveSectionChanged: {
        if (GlobalStates.recordingToolbarSection !== activeSection) {
            GlobalStates.recordingToolbarSection = activeSection;
        }
        if (activeSection !== displayedSection) {
            morphAnimation.restart();
        }
    }

    // Section currently being displayed (swapped mid-morph like Dynamic Island)
    property string displayedSection: activeSection

    Connections {
        target: GlobalStates
        function onRecordingToolbarSectionChanged() {
            if (root.activeSection !== GlobalStates.recordingToolbarSection) {
                root.activeSection = GlobalStates.recordingToolbarSection;
            }
        }
    }

    function toggleSection(section: string) {
        if (root.activeSection === section) {
            root.collapseSection();
        } else {
            root.activeSection = section;
        }
    }

    function collapseSection() {
        root.activeSection = "";
    }

    readonly property var estimateScreen: root.QsWindow?.window?.screen ?? Quickshell.screens[0] ?? null
    readonly property int sourceWidth: root.estimateScreen
        ? Math.round(root.estimateScreen.width * root.estimateScreen.devicePixelRatio) : 1920
    readonly property int sourceHeight: root.estimateScreen
        ? Math.round(root.estimateScreen.height * root.estimateScreen.devicePixelRatio) : 1080
    readonly property var outputSize: RecordingQuality.outputSize(root.sourceWidth, root.sourceHeight,
        Config.options.screenRecord.resolution)
    readonly property real estimatedMbps: RecordingQuality.estimateMbps(root.outputSize[0], root.outputSize[1],
        Config.options.screenRecord.framerate, Config.options.screenRecord.quality)

    // ── Dynamic Island-inspired Morph & Crossfade (No Clip Masking) ───────────
    property real morphOpacity: 1.0

    SequentialAnimation {
        id: morphAnimation
        running: false

        // Phase 1: Dim out the old face quickly
        NumberAnimation {
            target: root
            property: "morphOpacity"
            to: 0.0
            duration: Math.round(90 * Appearance.animMultiplier)
            easing.type: Easing.InQuad
        }

        // Swap the displayed face while dim
        ScriptAction {
            script: root.displayedSection = root.activeSection
        }

        // Phase 2: Brighten in the new face smoothly as pill width settles
        NumberAnimation {
            target: root
            property: "morphOpacity"
            to: 1.0
            duration: Math.round(180 * Appearance.animMultiplier)
            easing.type: Easing.OutCubic
        }
    }

    // Target width for whichever section is active
    readonly property real targetContentWidth: {
        if (root.activeSection === "video") return videoLayout.implicitWidth;
        if (root.activeSection === "audio") return audioLayout.implicitWidth;
        if (root.activeSection === "countdown") return countdownLayout.implicitWidth;
        if (root.activeSection === "options") return optionsLayout.implicitWidth;
        return page1Layout.implicitWidth;
    }

    implicitHeight: Appearance.sizes.toolbarHeight + toolbarPadding * 2
    implicitWidth: targetContentWidth + toolbarPadding * 2
    radius: height / 2
    color: Appearance.m3colors.m3surfaceContainer

    Behavior on implicitWidth {
        NumberAnimation {
            duration: Math.round(280 * Appearance.animMultiplier)
            easing.type: Easing.OutCubic
        }
    }

    StyledRectangularShadow {
        target: root
        radius: root.radius
    }

    // ── Content Viewport (Unclipped, Fluid Crossfade) ─────────────────────────
    Item {
        id: containerItem
        anchors.fill: parent
        anchors.margins: root.toolbarPadding
        opacity: root.morphOpacity

        // ═════════════════════════════════════════════════════════════════════
        // PAGE 1 — Main Toolbar Controls
        // ═════════════════════════════════════════════════════════════════════
        RowLayout {
            id: page1Layout
            height: Appearance.sizes.toolbarHeight
            spacing: 8
            anchors.centerIn: parent
            visible: root.displayedSection === ""

            // 1. Close Button (Hidden in preview)
            RippleButton {
                visible: !root.isPreview
                implicitWidth: Appearance.sizes.toolbarHeight
                implicitHeight: Appearance.sizes.toolbarHeight
                buttonRadius: Appearance.rounding.full
                colBackground: "transparent"
                colBackgroundHover: Appearance.colors.colLayer2Hover
                colRipple: Appearance.colors.colLayer2Active
                onClicked: root.closeRequested()

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "close"
                    iconSize: 20
                    color: Appearance.colors.colOnSurfaceVariant
                }

                StyledToolTip {
                    text: Translation.tr("Close (Esc)")
                }
            }

            // 2. Mode Selector: Toolbar with ToolbarTabBar
            Toolbar {
                enableShadow: false
                colBackground: Appearance.m3colors.m3surfaceContainerHigh

                ToolbarTabBar {
                    id: modeTabBar
                    readonly property var modeKeys: ["fullscreen", "window", "region"]
                    readonly property string currentMode: modeKeys[currentIndex] ?? Config.options.screenRecord.mode ?? "fullscreen"
                    requestOnly: true

                    tabButtonList: [
                        { name: Translation.tr("Fullscreen"), icon: "desktop_windows" },
                        { name: Translation.tr("Window"), icon: "window" },
                        { name: Translation.tr("Region"), icon: "crop" }
                    ]

                    currentIndex: {
                        const currentMode = Config.options.screenRecord.mode ?? "fullscreen";
                        const idx = modeKeys.indexOf(currentMode);
                        return idx >= 0 ? idx : 0;
                    }

                    onIndexSelected: (index) => {
                        if (index >= 0 && index < modeKeys.length) {
                            Config.options.screenRecord.mode = modeKeys[index];
                        }
                    }

                    onCurrentIndexChanged: {
                        if (currentIndex >= 0 && currentIndex < modeKeys.length) {
                            const m = modeKeys[currentIndex];
                            if (Config.options.screenRecord.mode !== m) {
                                Config.options.screenRecord.mode = m;
                            }
                        }
                    }
                }
            }

            // 3. Four Section Triggers: Toolbar
            Toolbar {
                enableShadow: false
                colBackground: Appearance.m3colors.m3surfaceContainerHigh

                RowLayout {
                    id: triggerRow
                    spacing: 4

                    // Toggle 1: Video Quality & Format
                    SectionTriggerButton {
                        iconText: "tune"
                        tooltipText: Translation.tr("Video Quality & Format")
                        active: root.activeSection === "video"
                        onClicked: root.toggleSection("video")
                    }

                    // Toggle 2: Audio Settings
                    SectionTriggerButton {
                        iconText: (Config.options.screenRecord.recordMic || Config.options.screenRecord.recordAudio)
                            ? "volume_up" : "volume_off"
                        tooltipText: Translation.tr("Audio & Microphone Settings")
                        active: root.activeSection === "audio"
                        onClicked: root.toggleSection("audio")
                    }

                    // Toggle 3: Countdown Timer
                    SectionTriggerButton {
                        iconText: "timer"
                        tooltipText: Config.options.screenRecord.countdown > 0
                            ? Translation.tr("Countdown Timer (%1s)").arg(Config.options.screenRecord.countdown)
                            : Translation.tr("Countdown Timer (Off)")
                        active: root.activeSection === "countdown"
                        onClicked: root.toggleSection("countdown")
                    }

                    // Toggle 4: More Options & Folder
                    SectionTriggerButton {
                        iconText: "more_horiz"
                        tooltipText: Translation.tr("More Options & Save Folder")
                        active: root.activeSection === "options"
                        onClicked: root.toggleSection("options")
                    }
                }
            }

            // 4. Hero Record Button
            RecordActionButton {
                onClicked: root.recordRequested()
            }
        }

        // ═════════════════════════════════════════════════════════════════════
        // PAGE 2 — VIDEO QUALITY & FORMAT (3 SEPARATE TOOLBARS)
        // ═════════════════════════════════════════════════════════════════════
        RowLayout {
            id: videoLayout
            height: Appearance.sizes.toolbarHeight
            spacing: 8
            anchors.centerIn: parent
            visible: root.displayedSection === "video"

            // 1. Back Button
            BackButton {
                onClicked: root.collapseSection()
            }

            // 2. Toolbar 1: Video Format (Toolbar widget)
            Toolbar {
                enableShadow: false
                colBackground: Appearance.m3colors.m3surfaceContainerHigh

                ToolbarTabBar {
                    id: formatTabBar
                    readonly property var formatKeys: ["mp4", "mkv", "webm", "gif"]
                    requestOnly: true

                    tabButtonList: [
                        { name: "MP4" },
                        { name: "MKV" },
                        { name: "WebM" },
                        { name: "GIF" }
                    ]

                    currentIndex: {
                        const currentFmt = Config.options.screenRecord.format ?? "mp4";
                        const idx = formatKeys.indexOf(currentFmt);
                        return idx >= 0 ? idx : 0;
                    }

                    onIndexSelected: (index) => {
                        if (index >= 0 && index < formatKeys.length) {
                            Config.options.screenRecord.format = formatKeys[index];
                        }
                    }

                    onCurrentIndexChanged: {
                        if (currentIndex >= 0 && currentIndex < formatKeys.length) {
                            const fmt = formatKeys[currentIndex];
                            if (Config.options.screenRecord.format !== fmt) {
                                Config.options.screenRecord.format = fmt;
                            }
                        }
                    }
                }

                StyledToolTip {
                    text: Translation.tr("Video Format")
                }
            }

            // 3. Toolbar 2: Framerate (Toolbar widget)
            Toolbar {
                enableShadow: false
                colBackground: Appearance.m3colors.m3surfaceContainerHigh

                ToolbarTabBar {
                    id: fpsTabBar
                    readonly property var fpsValues: [30, 60, 120]
                    requestOnly: true

                    tabButtonList: [
                        { name: "30 FPS" },
                        { name: "60 FPS" },
                        { name: "120 FPS" }
                    ]

                    currentIndex: {
                        const currentFps = Config.options.screenRecord.framerate ?? 60;
                        const idx = fpsValues.indexOf(currentFps);
                        return idx >= 0 ? idx : 1;
                    }

                    onIndexSelected: (index) => {
                        if (index >= 0 && index < fpsValues.length) {
                            Config.options.screenRecord.framerate = fpsValues[index];
                        }
                    }

                    onCurrentIndexChanged: {
                        if (currentIndex >= 0 && currentIndex < fpsValues.length) {
                            const fps = fpsValues[currentIndex];
                            if (Config.options.screenRecord.framerate !== fps) {
                                Config.options.screenRecord.framerate = fps;
                            }
                        }
                    }
                }

                StyledToolTip {
                    text: Translation.tr("Recording Framerate")
                }
            }

            // 4. Toolbar 3: Quality (Toolbar widget)
            Toolbar {
                enableShadow: false
                colBackground: Appearance.m3colors.m3surfaceContainerHigh

                ToolbarTabBar {
                    id: qualityTabBar
                    readonly property var qualityKeys: ["low", "balanced", "high"]
                    requestOnly: true

                    tabButtonList: [
                        { name: Translation.tr("Low") },
                        { name: Translation.tr("Balanced") },
                        { name: Translation.tr("High") }
                    ]

                    currentIndex: {
                        const currentQ = Config.options.screenRecord.quality ?? "high";
                        const idx = qualityKeys.indexOf(currentQ);
                        return idx >= 0 ? idx : 2;
                    }

                    onIndexSelected: (index) => {
                        if (index >= 0 && index < qualityKeys.length) {
                            Config.options.screenRecord.quality = qualityKeys[index];
                        }
                    }

                    onCurrentIndexChanged: {
                        if (currentIndex >= 0 && currentIndex < qualityKeys.length) {
                            const q = qualityKeys[currentIndex];
                            if (Config.options.screenRecord.quality !== q) {
                                Config.options.screenRecord.quality = q;
                            }
                        }
                    }
                }

                StyledToolTip {
                    text: Translation.tr("Encoding Quality")
                }
            }

            // 5. Bitrate Live Badge (Toolbar widget)
            Toolbar {
                enableShadow: false
                colBackground: Appearance.m3colors.m3surfaceContainerHigh
                padding: 8

                StyledText {
                    id: bitrateText
                    Layout.alignment: Qt.AlignVCenter | Qt.AlignHCenter
                    text: `≈ ${root.estimatedMbps} Mbps`
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.bold: true
                    color: Appearance.colors.colPrimary
                }

                StyledToolTip {
                    text: Translation.tr("Estimated Bitrate: %1 Mbps").arg(root.estimatedMbps)
                }
            }

            // 6. Hero Record Button
            RecordActionButton {
                onClicked: root.recordRequested()
            }
        }

        // ═════════════════════════════════════════════════════════════════════
        // PAGE 2 — AUDIO SETTINGS
        // ═════════════════════════════════════════════════════════════════════
        RowLayout {
            id: audioLayout
            height: Appearance.sizes.toolbarHeight
            spacing: 8
            anchors.centerIn: parent
            visible: root.displayedSection === "audio"

            // 1. Back Button
            BackButton {
                onClicked: root.collapseSection()
            }

            // 2. Audio Controls Toolbar
            Toolbar {
                enableShadow: false
                colBackground: Appearance.m3colors.m3surfaceContainerHigh
                padding: 4

                RowLayout {
                    id: audioControlsRow
                    spacing: 6

                    // Microphone Toggle
                    InlineChip {
                        iconText: Config.options.screenRecord.recordMic ? "mic" : "mic_off"
                        text: Translation.tr("Microphone")
                        active: Config.options.screenRecord.recordMic
                        onClicked: Config.options.screenRecord.recordMic = !Config.options.screenRecord.recordMic
                    }

                    // System Audio Toggle
                    InlineChip {
                        iconText: Config.options.screenRecord.recordAudio ? "volume_up" : "volume_off"
                        text: Translation.tr("System Audio")
                        active: Config.options.screenRecord.recordAudio
                        onClicked: Config.options.screenRecord.recordAudio = !Config.options.screenRecord.recordAudio
                    }

                    VerticalSeparator {
                        visible: Array.from(Audio.inputDevices).length > 0
                    }

                    // Device selector button
                    RippleButton {
                        visible: Array.from(Audio.inputDevices).length > 0
                        implicitHeight: 36
                        implicitWidth: micDevRow.implicitWidth + 20
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colLayer2
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        colRipple: Appearance.colors.colLayer2Active
                        onClicked: {
                            const devs = Array.from(Audio.inputDevices);
                            if (devs.length <= 1) return;
                            const currentIndex = devs.findIndex(d => d.id === Audio.source?.id);
                            const nextIndex = (currentIndex + 1) % devs.length;
                            Audio.setDefaultSource(devs[nextIndex]);
                        }

                        RowLayout {
                            id: micDevRow
                            anchors.centerIn: parent
                            spacing: 6

                            MaterialSymbol {
                                text: "graphic_eq"
                                iconSize: 16
                                color: Appearance.colors.colOnSurfaceVariant
                            }

                            StyledText {
                                text: Audio.source
                                    ? Audio.friendlyDeviceName(Audio.source)
                                    : Translation.tr("Default Mic")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnSurface
                                elide: Text.ElideRight
                                Layout.maximumWidth: 150
                            }

                            MaterialSymbol {
                                visible: Array.from(Audio.inputDevices).length > 1
                                text: "swap_horiz"
                                iconSize: 16
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                        }

                        StyledToolTip {
                            text: Translation.tr("Switch microphone input device")
                        }
                    }
                }
            }

            // 3. Hero Record Button
            RecordActionButton {
                onClicked: root.recordRequested()
            }
        }

        // ═════════════════════════════════════════════════════════════════════
        // PAGE 2 — COUNTDOWN TIMER (TOOLBAR TAB BAR)
        // ═════════════════════════════════════════════════════════════════════
        RowLayout {
            id: countdownLayout
            height: Appearance.sizes.toolbarHeight
            spacing: 8
            anchors.centerIn: parent
            visible: root.displayedSection === "countdown"

            // 1. Back Button
            BackButton {
                onClicked: root.collapseSection()
            }

            // 2. Countdown Toolbar (Toolbar widget)
            Toolbar {
                enableShadow: false
                colBackground: Appearance.m3colors.m3surfaceContainerHigh

                ToolbarTabBar {
                    id: countdownTabBar
                    readonly property var countdownValues: [0, 3, 5, 10]
                    requestOnly: true

                    tabButtonList: [
                        { name: Translation.tr("0s (Off)") },
                        { name: "3s" },
                        { name: "5s" },
                        { name: "10s" }
                    ]

                    currentIndex: {
                        const currentVal = Config.options.screenRecord.countdown ?? 0;
                        const idx = countdownValues.indexOf(currentVal);
                        return idx >= 0 ? idx : 0;
                    }

                    onIndexSelected: (index) => {
                        if (index >= 0 && index < countdownValues.length) {
                            Config.options.screenRecord.countdown = countdownValues[index];
                        }
                    }

                    onCurrentIndexChanged: {
                        if (currentIndex >= 0 && currentIndex < countdownValues.length) {
                            const c = countdownValues[currentIndex];
                            if (Config.options.screenRecord.countdown !== c) {
                                Config.options.screenRecord.countdown = c;
                            }
                        }
                    }
                }

                StyledToolTip {
                    text: Translation.tr("Countdown Timer")
                }
            }

            // 3. Hero Record Button
            RecordActionButton {
                onClicked: root.recordRequested()
            }
        }

        // ═════════════════════════════════════════════════════════════════════
        // PAGE 2 — MORE OPTIONS & FOLDER
        // ═════════════════════════════════════════════════════════════════════
        RowLayout {
            id: optionsLayout
            height: Appearance.sizes.toolbarHeight
            spacing: 8
            anchors.centerIn: parent
            visible: root.displayedSection === "options"

            // 1. Back Button
            BackButton {
                onClicked: root.collapseSection()
            }

            // 2. Options Controls Toolbar
            Toolbar {
                enableShadow: false
                colBackground: Appearance.m3colors.m3surfaceContainerHigh
                padding: 4

                RowLayout {
                    id: optionsControlsRow
                    spacing: 6

                    // GPU
                    InlineChip {
                        iconText: "bolt"
                        text: Translation.tr("GPU")
                        active: Config.options.screenRecord.useGpu
                        onClicked: Config.options.screenRecord.useGpu = !Config.options.screenRecord.useGpu
                    }


                    // Keystrokes
                    InlineChip {
                        iconText: "keyboard"
                        text: Translation.tr("Keys")
                        active: Config.options.screenRecord.keypress.showWhileRecording
                        onClicked: Config.options.screenRecord.keypress.showWhileRecording = !Config.options.screenRecord.keypress.showWhileRecording
                    }

                    VerticalSeparator {}

                    Process {
                        id: saveFolderProcess
                        command: [
                            "python3", Directories.scriptPath + "/image_picker.py",
                            "--directory",
                            "--title", Translation.tr("Choose recording save directory"),
                            "--folder", Config.options.screenRecord.savePath || (Quickshell.env("HOME") + "/Videos")
                        ]
                        stdout: StdioCollector {
                            onStreamFinished: {
                                const out = text.trim();
                                if (!out) return;
                                try {
                                    const parsed = JSON.parse(out);
                                    if (parsed && typeof parsed === "string" && parsed.length > 0) {
                                        Config.options.screenRecord.savePath = parsed;
                                    }
                                } catch (e) {
                                    if (out.length > 0) {
                                        Config.options.screenRecord.savePath = out;
                                    }
                                }
                            }
                        }
                    }

                    // Choose Save Folder
                    RippleButton {
                        implicitHeight: 36
                        implicitWidth: folderRow.implicitWidth + 20
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colSecondaryContainer
                        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                        colRipple: Appearance.colors.colSecondaryContainerActive
                        onClicked: {
                            if (!saveFolderProcess.running) {
                                saveFolderProcess.running = true;
                            }
                        }
                        altAction: () => Qt.openUrlExternally(`file://${Config.options.screenRecord.savePath}`)

                        RowLayout {
                            id: folderRow
                            anchors.centerIn: parent
                            spacing: 6

                            MaterialSymbol {
                                text: "folder_open"
                                iconSize: 16
                                color: Appearance.colors.colOnSecondaryContainer
                            }

                            StyledText {
                                text: Translation.tr("Folder")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                        }

                        StyledToolTip {
                            text: Translation.tr("Change save directory (%1)\nRight-click to open in file manager").arg(Config.options.screenRecord.savePath)
                        }
                    }
                }
            }

            // 3. Hero Record Button
            RecordActionButton {
                onClicked: root.recordRequested()
            }
        }
    }

    // ── Auxiliary Components ─────────────────────────────────────────────────
    component BackButton: RippleButton {
        implicitWidth: Appearance.sizes.toolbarHeight
        implicitHeight: Appearance.sizes.toolbarHeight
        buttonRadius: Appearance.rounding.full
        colBackground: Appearance.m3colors.m3surfaceContainerHigh
        colBackgroundHover: Appearance.colors.colLayer2Hover
        colRipple: Appearance.colors.colLayer2Active

        MaterialSymbol {
            anchors.centerIn: parent
            text: "arrow_back"
            iconSize: 20
            color: Appearance.colors.colOnSurface
        }

        StyledToolTip {
            text: Translation.tr("Back to Main Controls (Esc)")
        }
    }

    component SectionTriggerButton: RippleButton {
        id: stb
        property string iconText: ""
        property string tooltipText: ""
        property bool active: false

        implicitWidth: 38
        implicitHeight: 38
        buttonRadius: Appearance.rounding.full

        colBackground: active
            ? Appearance.colors.colSecondaryContainer
            : "transparent"
        colBackgroundHover: active
            ? Appearance.colors.colSecondaryContainerHover
            : Appearance.colors.colLayer2Hover
        colRipple: Appearance.colors.colSecondaryContainerActive

        MaterialSymbol {
            anchors.centerIn: parent
            text: stb.iconText
            iconSize: 20
            color: stb.active
                ? Appearance.colors.colOnSecondaryContainer
                : Appearance.colors.colOnSurfaceVariant
        }

        StyledToolTip {
            text: stb.tooltipText
        }
    }

    component InlineChip: RippleButton {
        id: chip
        property bool active: false
        property string iconText: ""
        implicitHeight: 36
        implicitWidth: chipRow.implicitWidth + 18
        buttonRadius: Appearance.rounding.full

        colBackground: active
            ? Appearance.colors.colSecondaryContainer
            : Appearance.colors.colLayer2
        colBackgroundHover: active
            ? Appearance.colors.colSecondaryContainerHover
            : Appearance.colors.colLayer2Hover
        colRipple: Appearance.colors.colSecondaryContainerActive

        RowLayout {
            id: chipRow
            anchors.centerIn: parent
            spacing: 5

            MaterialSymbol {
                visible: chip.iconText.length > 0
                text: chip.iconText
                iconSize: 16
                color: chip.active
                    ? Appearance.colors.colOnSecondaryContainer
                    : Appearance.colors.colOnSurfaceVariant
            }

            StyledText {
                text: chip.text
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.bold: chip.active
                color: chip.active
                    ? Appearance.colors.colOnSecondaryContainer
                    : Appearance.colors.colOnSurface
            }
        }
    }

    component VerticalSeparator: Rectangle {
        implicitWidth: 1
        implicitHeight: 20
        color: Appearance.colors.colOutlineVariant
        opacity: 0.3
    }

    component RecordActionButton: RippleButton {
        id: recBtn
        implicitHeight: Appearance.sizes.toolbarHeight
        implicitWidth: recordContent.implicitWidth + 28
        buttonRadius: Appearance.rounding.full

        colBackground: Appearance.colors.colPrimary
        colBackgroundHover: Appearance.colors.colPrimaryHover
        colRipple: Appearance.colors.colPrimaryActive

        RowLayout {
            id: recordContent
            anchors.centerIn: parent
            spacing: 8

            MaterialSymbol {
                text: "videocam"
                iconSize: 20
                color: Appearance.colors.colOnPrimary
            }

            StyledText {
                text: Translation.tr("Record")
                font.pixelSize: Appearance.font.pixelSize.normal
                font.bold: true
                font.family: Appearance.font.family.title
                color: Appearance.colors.colOnPrimary
            }
        }

        StyledToolTip {
            text: Translation.tr("Start recording")
        }
    }
}
