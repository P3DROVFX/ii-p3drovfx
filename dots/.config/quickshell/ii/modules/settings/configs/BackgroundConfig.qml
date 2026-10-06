import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services

Item {
    id: backgroundRoot
    anchors.fill: parent

    property alias contentY: page.contentY
    property alias activeSubPage: subPageOverlay.activeSubPage

    ContentPage {
        id: page
        anchors.fill: parent
        forceWidth: false
        opacity: subPageOverlay.slideProgress

        // Only a video painted by another process (mpvpaper, Wallpaper Engine)
        // locks the image effects; the shell video backend keeps them.
        readonly property bool videoWallpaper: Wallpapers.videoWallpaperActive

        ContentSection {
            title: Translation.tr("Parallax Engine")
            icon: "sync_alt"

            NoticeBox {
                Layout.fillWidth: true
                visible: page.videoWallpaper
                materialIcon: "movie"
                text: Translation.tr("Video wallpaper active: window blur and parallax are disabled automatically; only the Default zoom style is available.")
            }

            ConfigSwitch {
                buttonIcon: "counter_1"
                text: Translation.tr("Depends on workspace")
                enabled: !page.videoWallpaper
                checked: Config.options.background.parallax.enableWorkspace
                configPage: Qt.resolvedUrl("widgets/ParallaxConfig.qml")
                onCheckedChanged: {
                    Config.options.background.parallax.enableWorkspace = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Click button text to configure parallax movement directions, sidebars, and intensity.")
                }
            }

            ConfigSlider {
                buttonIcon: "loupe"
                text: Translation.tr("Preferred wallpaper zoom (%)")
                enabled: !page.videoWallpaper
                usePercentTooltip: true
                from: 100
                to: 150
                stepSize: 1
                value: Math.round((Config.options.background.parallax.workspaceZoom ?? 1.07) * 100)
                onValueChanged: {
                    Config.options.background.parallax.workspaceZoom = value / 100;
                }
            }
        }

        ContentSection {
            title: Translation.tr("Wallpaper Quality & Performance")
            icon: "high_quality"

            ConfigSwitch {
                buttonIcon: "memory"
                text: Translation.tr("Downscale wallpaper to reduce VRAM usage")
                enabled: !page.videoWallpaper
                checked: Config.options.background.scaleLargeWallpapers ?? false
                onCheckedChanged: {
                    Config.options.background.scaleLargeWallpapers = checked;
                }
                StyledToolTip {
                    text: Translation.tr("When enabled, decodes large wallpapers at screen resolution to save VRAM. When disabled (default, like upstream end-4), loads wallpapers at full native resolution for maximum sharpness.")
                }
            }
        }

        ContentSection {
            id: depthSection
            title: Translation.tr("Depth Effect")
            icon: "layers"

            function sizeText(bytes) {
                return bytes >= 1e9 ? (bytes / 1e9).toFixed(1) + " GB" : Math.round(bytes / 1e6) + " MB";
            }
            function memoryText(mb) {
                return mb >= 1000 ? Translation.tr("~%1 GB").arg((mb / 1000).toFixed(mb % 1000 === 0 ? 0 : 1)) : Translation.tr("~%1 MB").arg(mb);
            }

            StyledText {
                Layout.fillWidth: true
                Layout.bottomMargin: 4
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.small
                text: Translation.tr("Cuts the subject out of the wallpaper and draws it over the desktop widgets, so a clock can sit behind a person. A model runs once per picture, in the background, then exits; on the desktop it costs one image. Nothing is downloaded until you pick a model here.")
            }

            ConfigSwitch {
                buttonIcon: "layers"
                text: Translation.tr("Subject in front of widgets")
                enabled: DepthEffect.anyInstalled && !page.videoWallpaper
                checked: Config.options.background.depthEffect.enable
                onCheckedChanged: {
                    Config.options.background.depthEffect.enable = checked;
                }
                StyledToolTip {
                    text: DepthEffect.anyInstalled
                        ? Translation.tr("Each wallpaper can use another model, or none, from Edit Mode's Wallpaper tab.")
                        : Translation.tr("Download a model below first.")
                }
            }

            ConfigSwitch {
                buttonIcon: "border_outer"
                text: Translation.tr("Widget outlines over the subject")
                enabled: DepthEffect.anyInstalled && Config.options.background.depthEffect.enable
                checked: Config.options.background.depthEffect.outline ?? false
                onCheckedChanged: {
                    Config.options.background.depthEffect.outline = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Where the subject covers a widget, the widget's outline stays drawn on top of it in the widget's own colour, with no fill.")
                }
            }

            ConfigSwitch {
                buttonIcon: "notifications"
                text: Translation.tr("Notify while cutting out")
                enabled: DepthEffect.anyInstalled
                checked: Config.options.background.depthEffect.notify ?? true
                onCheckedChanged: {
                    Config.options.background.depthEffect.notify = checked;
                }
                StyledToolTip {
                    text: Translation.tr("A notification when a model starts on a picture and when its cutout is ready. Pictures already cut out stay silent.")
                }
            }

            ContentSubsection {
                title: Translation.tr("Models")
                icon: "download"
                Layout.fillWidth: true

                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.small
                    text: Translation.tr("The first download also installs the ONNX runtime (~70 MB); removing the last model removes it and every cutout.")
                }
            }

            Repeater {
                model: DepthEffect.models
                delegate: Rectangle {
                    id: modelRow
                    required property var modelData
                    readonly property string modelId: modelRow.modelData.id
                    readonly property bool installed: DepthEffect.installed.includes(modelRow.modelId)
                    readonly property bool downloading: DepthEffect.downloadingModel === modelRow.modelId
                    readonly property bool failed: DepthEffect.errorModel === modelRow.modelId && DepthEffect.errorMessage !== ""
                    readonly property GroupPosition groupPosition: GroupPosition {
                        item: modelRow
                    }

                    Layout.fillWidth: true
                    implicitHeight: modelRowLayout.implicitHeight + 24
                    color: Appearance.colors.colLayer2
                    topLeftRadius: modelRow.groupPosition.isFirst ? Appearance.rounding.large : Appearance.rounding.verysmall
                    topRightRadius: modelRow.groupPosition.isFirst ? Appearance.rounding.large : Appearance.rounding.verysmall
                    bottomLeftRadius: modelRow.groupPosition.isLast ? Appearance.rounding.large : Appearance.rounding.verysmall
                    bottomRightRadius: modelRow.groupPosition.isLast ? Appearance.rounding.large : Appearance.rounding.verysmall

                    RowLayout {
                        id: modelRowLayout
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            margins: 16
                        }
                        spacing: 14

                        MaterialShapeWrappedMaterialSymbol {
                            Layout.alignment: Qt.AlignTop
                            text: modelRow.installed ? "check" : modelRow.modelData.icon
                            shape: modelRow.installed ? MaterialShape.Shape.Cookie9Sided : MaterialShape.Shape.Circle
                            iconSize: 20
                            padding: 8
                            color: modelRow.installed ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
                            colSymbol: modelRow.installed ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4

                            StyledText {
                                Layout.fillWidth: true
                                text: modelRow.modelData.name
                                color: Appearance.colors.colOnLayer2
                                font {
                                    family: Appearance.font.family.title
                                    variableAxes: Appearance.font.variableAxes.titleRounded
                                    pixelSize: Appearance.font.pixelSize.normal
                                }
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: modelRow.modelData.description
                                wrapMode: Text.WordWrap
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.small
                            }
                            StyledText {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                text: Translation.tr("%1 · %2 of RAM for ~%3 s per wallpaper · %4 · %5")
                                    .arg(depthSection.sizeText(modelRow.modelData.bytes))
                                    .arg(depthSection.memoryText(modelRow.modelData.peakMemoryMB))
                                    .arg(modelRow.modelData.seconds)
                                    .arg(modelRow.modelData.architecture)
                                    .arg(modelRow.modelData.license)
                            }
                            StyledProgressBar {
                                visible: modelRow.downloading
                                Layout.fillWidth: true
                                Layout.topMargin: 4
                                value: DepthEffect.downloadProgress
                            }
                            StyledText {
                                visible: modelRow.downloading || modelRow.failed
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                color: modelRow.failed ? Appearance.colors.colError : Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                text: modelRow.failed ? DepthEffect.errorMessage
                                    : DepthEffect.cancelling ? Translation.tr("Cancelling…")
                                    : (DepthEffect.downloadPhase === "runtime" ? Translation.tr("Installing the ONNX runtime… %1%")
                                        : Translation.tr("Downloading… %1%")).arg(Math.round(DepthEffect.downloadProgress * 100))
                            }
                        }

                        AppRowButton {
                            Layout.alignment: Qt.AlignVCenter
                            visible: !modelRow.installed && !modelRow.downloading
                            enabled: DepthEffect.downloadingModel === "" && DepthEffect.statusKnown
                            symbol: "download"
                            label: Translation.tr("Download")
                            onClicked: DepthEffect.download(modelRow.modelId)
                        }
                        AppRowButton {
                            Layout.alignment: Qt.AlignVCenter
                            visible: modelRow.downloading
                            enabled: !DepthEffect.cancelling
                            symbol: "close"
                            label: Translation.tr("Cancel")
                            onClicked: DepthEffect.cancelDownload()
                        }
                        AppRowButton {
                            Layout.alignment: Qt.AlignVCenter
                            visible: modelRow.installed
                            danger: true
                            symbol: "delete"
                            label: Translation.tr("Remove")
                            onClicked: DepthEffect.remove(modelRow.modelId)
                        }
                    }
                }
            }

            ContentSubsection {
                visible: DepthEffect.installedModels.length > 1
                title: Translation.tr("Default model")
                icon: "tune"
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: DepthEffect.defaultModel
                    options: DepthEffect.installedModels.map(m => ({
                        "displayName": m.name,
                        "icon": m.icon,
                        "value": m.id
                    }))
                    onSelected: newValue => {
                        Config.options.background.depthEffect.model = newValue;
                    }
                }
            }
        }

        ContentSection {
            id: videoSection
            title: Translation.tr("Video Wallpapers")
            icon: "movie"

            readonly property bool shellBackend: (Config.options.background.videoBackend ?? "mpvpaper") === "shell"
            readonly property string buildScript: FileUtils.trimFileProtocol(`${Directories.scriptPath}/videos/build-mpv-wallpaper-plugin.sh`)

            // What the build script reports (--status): distro family, missing
            // build dependencies, this distro's install command, install dir.
            property var buildStatus: null
            readonly property var missingDeps: buildStatus?.missing ?? []
            readonly property bool depsReady: buildStatus !== null && missingDeps.length === 0
            readonly property bool pluginBuilt: (buildStatus?.installedDir ?? "") !== ""
            // Importable in this shell: the probe below loads only then.
            readonly property bool pluginLoaded: mpvPluginProbe.status === Loader.Ready
            // The running shell's environment, which the plugin dir has to be in.
            readonly property bool importPathReady: (Quickshell.env("QML_IMPORT_PATH") ?? "").split(":").includes(buildStatus?.userQmlDir ?? "")

            property bool building: false
            property bool buildFailed: false
            property string buildLine: ""
            property real buildProgress: 0
            // Set after "Install" opens a terminal; the status is polled until the
            // dependencies show up, since the terminal may return immediately.
            property bool waitingForDeps: false

            function refreshStatus() {
                if (!statusProc.running)
                    statusProc.running = true;
            }

            Component.onCompleted: refreshStatus()

            Process {
                id: statusProc
                command: ["bash", videoSection.buildScript, "--status"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            videoSection.buildStatus = JSON.parse(text);
                        } catch (e) {
                            console.warn("[BackgroundConfig] build status unreadable:", text);
                        }
                        if (videoSection.waitingForDeps && videoSection.depsReady)
                            videoSection.waitingForDeps = false;
                    }
                }
            }

            Timer {
                interval: 3000
                repeat: true
                running: videoSection.waitingForDeps
                onTriggered: videoSection.refreshStatus()
            }
            Timer {
                // Stop polling eventually if the install was abandoned.
                interval: 600000
                running: videoSection.waitingForDeps
                onTriggered: videoSection.waitingForDeps = false
            }

            Process {
                id: buildProc
                command: ["bash", videoSection.buildScript]
                function readLine(data) {
                    const line = String(data).trim();
                    if (line.length === 0)
                        return;
                    const step = line.match(/^\[(\d+)\/(\d+)\]/);
                    if (step)
                        videoSection.buildProgress = Number(step[1]) / Math.max(1, Number(step[2]));
                    videoSection.buildLine = line;
                }
                stdout: SplitParser {
                    onRead: data => buildProc.readLine(data)
                }
                stderr: SplitParser {
                    onRead: data => buildProc.readLine(data)
                }
                onExited: (exitCode, exitStatus) => {
                    videoSection.building = false;
                    videoSection.buildFailed = exitCode !== 0;
                    videoSection.refreshStatus();
                }
            }

            function build() {
                if (buildProc.running)
                    return;
                videoSection.buildFailed = false;
                videoSection.buildProgress = 0;
                videoSection.buildLine = "";
                videoSection.building = true;
                buildProc.running = true;
            }

            // Steps that need sudo or show long output run in the user's terminal.
            function runInTerminal(args) {
                const terminal = Config.options?.apps?.terminal || "kitty -1";
                const cmd = terminal.split(" ").filter(part => part.length > 0);
                cmd.push("-e", "bash", "-c", 'script="$1"; shift; bash "$script" "$@"; printf "\\n[Press Enter to close] "; read -r', "ii-mpv-wallpaper", videoSection.buildScript, ...args);
                Quickshell.execDetached(cmd);
            }

            // Importable only when the MpvWallpaper plugin is installed.
            Loader {
                id: mpvPluginProbe
                visible: false
                source: Qt.resolvedUrl("../../ii/background/wallpaper/MpvWallpaperProbe.qml")
            }

            ContentSubsection {
                title: Translation.tr("Video player")
                icon: "play_circle"
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: Config.options.background.videoBackend ?? "mpvpaper"
                    onSelected: newValue => {
                        Config.options.background.videoBackend = newValue;
                    }
                    options: [
                        {
                            displayName: Translation.tr("mpvpaper"),
                            icon: "layers",
                            value: "mpvpaper"
                        },
                        {
                            displayName: Translation.tr("Shell"),
                            icon: "wallpaper",
                            value: "shell"
                        }
                    ]
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.topMargin: 2
                    wrapMode: Text.WordWrap
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.small
                    text: videoSection.shellBackend
                        ? Translation.tr("The shell plays the video inside the wallpaper, so window blur, parallax, the overview zoom and the lock screen effects work with it, and no separate mpvpaper process runs.")
                        : Translation.tr("mpvpaper draws the video on its own layer below the shell. It needs no setup, but image effects (window blur, parallax, overview designs) are turned off while it plays.")
                }
            }

            ConfigSwitch {
                buttonIcon: "pause_circle"
                text: Translation.tr("Pause while windows are open")
                visible: videoSection.shellBackend
                checked: Config.options.background.videoPauseWhenWindowsOpen ?? false
                onCheckedChanged: {
                    Config.options.background.videoPauseWhenWindowsOpen = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Freeze the video while the workspace has any window. It always pauses behind maximized or fullscreen windows, on the always-on display and when a separate lock screen wallpaper covers it.")
                }
            }

            ConfigSwitch {
                buttonIcon: "lock"
                text: Translation.tr("Pause on the lock screen")
                visible: videoSection.shellBackend
                checked: Config.options.background.videoPauseOnLock ?? true
                onCheckedChanged: {
                    Config.options.background.videoPauseOnLock = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Freeze the video while the screen is locked. Turned off, it keeps playing behind the lock screen; with the lock blur on, \n the blur is then redrawn for every frame, which costs more GPU while the computer sits locked.")
                }
            }

            ConfigSwitch {
                buttonIcon: "aspect_ratio"
                text: Translation.tr("Play large videos at screen size")
                checked: Config.options.background.videoDownscale ?? true
                onCheckedChanged: {
                    Config.options.background.videoDownscale = checked;
                }
                StyledToolTip {
                    text: Translation.tr("A video taller than your screen (4K on a 1080p display) is decoded and scaled at full size every frame: about 600 MB more video memory \n and 120 MB more RAM, for no visible gain. When on, a screen-sized copy is made \n once in the background (hardware encoder when available, kept in ~/.cache/quickshell-ii/video-proxies) \n and played instead. The original file is untouched.")
                }
            }

            // ── Color frame ── which moment of the video colors (and the
            // poster frame) come from. Only for a video desktop wallpaper.
            Item {
                id: colorFrame
                visible: false

                readonly property string video: {
                    const background = Config.options.background;
                    return !background.useWallpaperEngine && Wallpapers.isVideoFile(background.wallpaperPath ?? "") ? background.wallpaperPath : "";
                }
                readonly property real appliedSeconds: Wallpapers.videoFrameTime(colorFrame.video)
                property real seconds: 0
                property real duration: 0
                property string preview: ""
                property int previewSeq: 0
                property bool applying: false
                readonly property string previewDir: "/tmp/ii-video-color-frame"

                function format(value) {
                    const total = Math.max(0, Number(value) || 0);
                    const minutes = Math.floor(total / 60);
                    const rest = (total - minutes * 60).toFixed(1);
                    return `${minutes}:${Number(rest) < 10 ? "0" : ""}${rest}`;
                }
                // "75", "75.5", "1:15", "1:15.5" or "0:01:15" → seconds; NaN if unreadable.
                function parse(text) {
                    const parts = String(text).trim().split(":");
                    if (parts.length === 0 || parts.length > 3 || parts.some(p => !/^\d+(\.\d+)?$/.test(p)))
                        return NaN;
                    return parts.reduce((acc, part) => acc * 60 + Number(part), 0);
                }
                function clamp(value) {
                    const top = colorFrame.duration > 0 ? colorFrame.duration : value;
                    return Math.round(Math.max(0, Math.min(top, value)) * 10) / 10;
                }

                // The pick starts at what is in use, and follows it when an apply
                // (or the config loading late) changes it.
                onAppliedSecondsChanged: colorFrame.seconds = colorFrame.appliedSeconds
                onVideoChanged: Qt.callLater(colorFrame.load)
                Component.onCompleted: Qt.callLater(colorFrame.load)
                onSecondsChanged: previewDebounce.restart()

                function load() {
                    colorFrame.seconds = colorFrame.appliedSeconds;
                    colorFrame.duration = 0;
                    colorFrame.preview = "";
                    if (colorFrame.video === "")
                        return;
                    durationProc.running = false;
                    durationProc.running = true;
                    previewDebounce.restart();
                }

                Timer {
                    id: previewDebounce
                    interval: 250
                    onTriggered: {
                        if (colorFrame.video === "")
                            return;
                        colorFrame.previewSeq += 1;
                        previewProc.target = `${colorFrame.previewDir}/frame-${colorFrame.previewSeq}.jpg`;
                        previewProc.running = false;
                        previewProc.running = true;
                    }
                }
                Process {
                    id: durationProc
                    command: ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "default=nw=1:nk=1", colorFrame.video]
                    stdout: StdioCollector {
                        onStreamFinished: colorFrame.duration = Math.floor((Number(text.trim()) || 0) * 10) / 10
                    }
                }
                Process {
                    id: previewProc
                    property string target: ""
                    // One preview file at a time; a new name per pick so the Image reloads.
                    command: ["bash", "-c", 'mkdir -p "$1" && rm -f "$1"/frame-*.jpg; ffmpeg -y -ss "$2" -i "$3" -frames:v 1 -vf scale=640:-2 "$4" 2>/dev/null || ffmpeg -y -i "$3" -frames:v 1 -vf scale=640:-2 "$4" 2>/dev/null',
                        "ii-color-frame", colorFrame.previewDir, String(colorFrame.seconds), colorFrame.video, previewProc.target]
                    onExited: colorFrame.preview = previewProc.target
                }
                // Done when switchwall.sh publishes the new poster frame.
                Connections {
                    target: Config.options.background
                    function onThumbnailPathChanged() {
                        colorFrame.applying = false;
                    }
                }
                Timer {
                    running: colorFrame.applying
                    interval: 20000
                    onTriggered: colorFrame.applying = false
                }
            }

            ContentSubsection {
                visible: colorFrame.video !== ""
                title: Translation.tr("Color frame")
                icon: "palette"
                Layout.fillWidth: true

                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.small
                    text: Translation.tr("The theme colors and the poster frame shown before the video plays come from one moment of the video. Pick another one if the first frame is black or does not represent it.")
                }

                ClippingRectangle {
                    Layout.topMargin: 6
                    Layout.preferredWidth: Math.min(parent.width, 400)
                    Layout.preferredHeight: Layout.preferredWidth * 9 / 16
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer3

                    Image {
                        anchors.fill: parent
                        source: colorFrame.preview !== "" ? "file://" + colorFrame.preview : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: false
                        sourceSize.width: 640
                    }
                    Rectangle {
                        anchors {
                            left: parent.left
                            bottom: parent.bottom
                            margins: 8
                        }
                        implicitWidth: frameTimeLabel.implicitWidth + 16
                        implicitHeight: frameTimeLabel.implicitHeight + 8
                        radius: Appearance.rounding.full
                        color: Appearance.colors.colSecondaryContainer

                        StyledText {
                            id: frameTimeLabel
                            anchors.centerIn: parent
                            text: colorFrame.format(colorFrame.seconds)
                            color: Appearance.colors.colOnSecondaryContainer
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: Appearance.font.pixelSize.smaller
                        }
                    }
                }

                RowLayout {
                    Layout.topMargin: 4
                    spacing: 6

                    AppRowButton {
                        filled: true
                        enabled: !colorFrame.applying && colorFrame.seconds !== colorFrame.appliedSeconds
                        symbol: colorFrame.applying ? "hourglass_top" : "check"
                        label: colorFrame.applying ? Translation.tr("Generating colors…") : Translation.tr("Apply")
                        onClicked: {
                            colorFrame.applying = true;
                            Wallpapers.applyVideoFrameTime(colorFrame.video, colorFrame.seconds);
                        }
                    }
                    AppRowButton {
                        visible: colorFrame.seconds !== 0
                        symbol: "first_page"
                        label: Translation.tr("First frame")
                        onClicked: colorFrame.seconds = 0
                    }
                    StyledText {
                        Layout.leftMargin: 6
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        text: colorFrame.appliedSeconds > 0
                            ? Translation.tr("In use: %1").arg(colorFrame.format(colorFrame.appliedSeconds))
                            : Translation.tr("In use: first frame")
                    }
                }
            }

            ConfigSlider {
                id: frameSlider
                visible: colorFrame.video !== ""
                buttonIcon: "timer"
                text: Translation.tr("Frame time")
                from: 0
                to: Math.max(0.1, colorFrame.duration)
                stepSize: 0.1
                usePercentTooltip: false
                tooltipContent: colorFrame.format(value)
                enabled: colorFrame.duration > 0
                // A drag replaces a plain `value:` binding; this one comes back on release.
                // It also depends on the duration and is delayed, so it lands after
                // `to` has grown: applied first, the range would clamp it.
                Binding on value {
                    value: colorFrame.duration > 0 ? colorFrame.seconds : 0
                    when: !frameSlider.pressed
                    delayed: true
                }
                // Only a drag writes back: the range is still 0..0.1 until the
                // duration is known, and a programmatic clamp must not move the pick.
                onValueChanged: {
                    if (!pressed)
                        return;
                    const next = colorFrame.clamp(value);
                    if (next !== colorFrame.seconds)
                        colorFrame.seconds = next;
                }
            }

            ConfigTextField {
                id: frameTimeField
                visible: colorFrame.video !== ""
                icon: "schedule"
                text: Translation.tr("Timestamp")
                tooltip: Translation.tr("Seconds or minutes:seconds, e.g. 12.5 or 1:05.2. Press Enter to preview it.")
                placeholderText: "0:00.0"
                textField.onEditingFinished: {
                    const parsed = colorFrame.parse(textField.text);
                    if (!isNaN(parsed))
                        colorFrame.seconds = colorFrame.clamp(parsed);
                    textField.text = colorFrame.format(colorFrame.seconds);
                }
                Connections {
                    target: colorFrame
                    function onSecondsChanged() {
                        if (!frameTimeField.textField.activeFocus)
                            frameTimeField.textField.text = colorFrame.format(colorFrame.seconds);
                    }
                }
                Component.onCompleted: textField.text = colorFrame.format(colorFrame.seconds)
            }

            ContentSubsection {
                visible: videoSection.shellBackend
                title: Translation.tr("Efficient player (libmpv)")
                icon: "memory"
                Layout.fillWidth: true

                StyledText {
                    Layout.fillWidth: true
                    Layout.bottomMargin: 4
                    wrapMode: Text.WordWrap
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.small
                    text: videoSection.pluginLoaded
                        ? Translation.tr("Videos are decoded by libmpv with hardware decoding, and the frames stay on the GPU.")
                        : Translation.tr("Until this plugin is built the shell plays videos with QtMultimedia. That works without setup, but costs more CPU: on NVIDIA every frame is copied through system memory.")
                }
            }

            SetupStep {
                visible: videoSection.shellBackend
                dynamicRadius: true
                number: 1
                done: videoSection.depsReady
                title: Translation.tr("Install the build tools")
                body: {
                    if (videoSection.buildStatus === null)
                        return Translation.tr("Checking…");
                    if (videoSection.depsReady)
                        return Translation.tr("CMake, a C++ compiler, libmpv and the Qt 6 development files are installed.");
                    const missing = videoSection.missingDeps.join(", ");
                    if ((videoSection.buildStatus.installCommand ?? "") === "")
                        return Translation.tr("Missing: %1. Install them with your package manager, then check again.").arg(missing);
                    if (videoSection.waitingForDeps)
                        return Translation.tr("Finish the install in the terminal; this step updates on its own.");
                    return Translation.tr("Missing: %1. Install them on %2:").arg(missing).arg(SystemInfo.distroName);
                }
                command: videoSection.depsReady ? "" : (videoSection.buildStatus?.installCommand ?? "")

                AppRowButton {
                    visible: !videoSection.depsReady && (videoSection.buildStatus?.installCommand ?? "") !== ""
                    filled: true
                    symbol: "download"
                    label: Translation.tr("Install")
                    onClicked: {
                        videoSection.runInTerminal(["--install-deps"]);
                        videoSection.waitingForDeps = true;
                    }
                }
                AppRowButton {
                    visible: !videoSection.depsReady
                    symbol: "refresh"
                    label: Translation.tr("Check again")
                    onClicked: videoSection.refreshStatus()
                }
            }

            SetupStep {
                visible: videoSection.shellBackend
                dynamicRadius: true
                number: 2
                done: videoSection.pluginBuilt && !videoSection.building
                title: Translation.tr("Build the plugin")
                bodyColor: videoSection.buildFailed ? Appearance.colors.colError : Appearance.colors.colSubtext
                body: {
                    if (videoSection.building)
                        return videoSection.buildLine.length > 0 ? videoSection.buildLine : Translation.tr("Starting…");
                    if (videoSection.buildFailed)
                        return Translation.tr("The build failed: %1").arg(videoSection.buildLine);
                    if (videoSection.pluginBuilt)
                        return Translation.tr("Installed in %1. Build again after Qt updates.").arg(videoSection.buildStatus.installedDir);
                    return Translation.tr("Compiles plugins/mpv-wallpaper and installs it for your user. It takes about a minute, or run it yourself:");
                }
                command: videoSection.pluginBuilt || videoSection.building ? "" : videoSection.buildScript

                StyledProgressBar {
                    visible: videoSection.building
                    Layout.fillWidth: true
                    Layout.preferredWidth: 240
                    value: videoSection.buildProgress
                }
                AppRowButton {
                    visible: !videoSection.building
                    enabled: videoSection.depsReady
                    filled: !videoSection.pluginBuilt
                    symbol: videoSection.pluginBuilt ? "refresh" : "build"
                    label: videoSection.pluginBuilt ? Translation.tr("Rebuild") : Translation.tr("Build")
                    onClicked: videoSection.build()
                }
                AppRowButton {
                    visible: videoSection.buildFailed
                    symbol: "terminal"
                    label: Translation.tr("Build in terminal")
                    tooltip: Translation.tr("Shows the full compiler output")
                    onClicked: videoSection.runInTerminal([])
                }
            }

            SetupStep {
                visible: videoSection.shellBackend
                dynamicRadius: true
                number: 3
                done: videoSection.pluginLoaded
                title: Translation.tr("Load it in the shell")
                body: {
                    if (videoSection.pluginLoaded)
                        return Translation.tr("The shell is using libmpv for video wallpapers.");
                    if (!videoSection.importPathReady)
                        return Translation.tr("This session does not look for plugins in %1 yet. Restarting reloads Hyprland's environment first, then the shell.").arg(videoSection.buildStatus?.userQmlDir ?? "~/.local/lib/qt6/qml");
                    return Translation.tr("Restart the shell to load the plugin.");
                }

                AppRowButton {
                    visible: !videoSection.pluginLoaded
                    enabled: videoSection.pluginBuilt && !videoSection.building
                    filled: videoSection.pluginBuilt
                    symbol: "restart_alt"
                    label: Translation.tr("Restart shell")
                    onClicked: Quickshell.execDetached(["bash", videoSection.buildScript, "--restart-shell"])
                }
            }
        }

        ContentSection {
            title: Translation.tr("Wallpaper Transitions")
            icon: "animation"

            ConfigSwitch {
                buttonIcon: "animation"
                text: Translation.tr("Animate wallpaper changes")
                enabled: !page.videoWallpaper
                checked: Config.options.background.animateWallpaperChanges ?? true
                onCheckedChanged: {
                    Config.options.background.animateWallpaperChanges = checked;
                }
            }

            ContentSubsection {
                visible: (Config.options.background.animateWallpaperChanges ?? true) && !page.videoWallpaper
                title: Translation.tr("Transition shader effect")
                icon: "style"
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: Config.options.background.wallpaperAnimation ?? ""
                    onSelected: newValue => {
                        Config.options.background.wallpaperAnimation = newValue;
                    }
                    options: [
                        {
                            displayName: Translation.tr("Crossfade"),
                            icon: "blur_on",
                            value: ""
                        },
                        {
                            displayName: Translation.tr("Random"),
                            icon: "shuffle",
                            value: "random"
                        },
                        {
                            displayName: Translation.tr("Circle Pit"),
                            icon: "circle",
                            value: "circlePit"
                        },
                        {
                            displayName: Translation.tr("Circle Select"),
                            icon: "radio_button_checked",
                            value: "circleSelect"
                        },
                        {
                            displayName: Translation.tr("Magic"),
                            icon: "auto_awesome",
                            value: "magic"
                        },
                        {
                            displayName: Translation.tr("Peel"),
                            icon: "sticky_note_2",
                            value: "Peel"
                        },
                        {
                            displayName: Translation.tr("Transition"),
                            icon: "swap_horiz",
                            value: "transition"
                        },
                        {
                            displayName: Translation.tr("Pixelate"),
                            icon: "grid_on",
                            value: "pixelate"
                        },
                        {
                            displayName: Translation.tr("Stripes"),
                            icon: "view_column",
                            value: "stripes"
                        }
                    ]
                }
            }
        }

        ContentSection {
            title: Translation.tr("Background Overview Design")
            icon: "dashboard_customize"

            NoticeBox {
                Layout.fillWidth: true
                visible: page.videoWallpaper
                materialIcon: "movie"
                text: Translation.tr("Video wallpaper active: overview background design styles are not available.")
            }

            ConfigSwitch {
                buttonIcon: "dashboard_customize"
                text: Translation.tr("Keep overview background design always active")
                enabled: !page.videoWallpaper
                checked: Config.options.background.useBackgroundOverviewAlways ?? false
                onCheckedChanged: {
                    Config.options.background.useBackgroundOverviewAlways = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Keep overview designs (Gnome Like, Material Shape, etc.) permanently active and static on the desktop, freezing background blur to minimize resource usage.")
                }
            }

            ContentSubsection {
                visible: (Config.options.background.useBackgroundOverviewAlways ?? false) && !page.videoWallpaper
                title: Translation.tr("Background design style")
                icon: "style"
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: {
                        const style = Config.options.background.overviewBackgroundStyle;
                        const allowed = ["gnome", "material-shape", "card-lift", "camera-push", "desaturate", "directional"];
                        if (style && allowed.indexOf(style) >= 0)
                            return style;
                        return "gnome";
                    }
                    onSelected: newValue => {
                        Config.options.background.overviewBackgroundStyle = newValue;
                        Config.options.background.zoomOutStyle = newValue === "gnome" ? 0 : 2;
                    }
                    options: [
                        {
                            displayName: Translation.tr("Gnome Like"),
                            icon: "blur_on",
                            tooltip: Translation.tr("Zooms the wallpaper out with rounded corners, shadow and a blurred backing."),
                            enabled: !page.videoWallpaper,
                            value: "gnome"
                        },
                        {
                            displayName: Translation.tr("Material Shape"),
                            icon: "shapes",
                            tooltip: Translation.tr("Cuts the wallpaper with a random Material Shape focusing on center widgets with a solid primary container background."),
                            enabled: !page.videoWallpaper,
                            value: "material-shape"
                        },
                        {
                            displayName: Translation.tr("Card Lift"),
                            icon: "style",
                            tooltip: Translation.tr("Lifts the wallpaper into a rounded card with a blurred/dimmed backing."),
                            value: "card-lift"
                        },
                        {
                            displayName: Translation.tr("Camera Push"),
                            icon: "zoom_in",
                            tooltip: Translation.tr("Pushes the camera in with brightness and saturation adjustment; no blur."),
                            enabled: !page.videoWallpaper,
                            value: "camera-push"
                        },
                        {
                            displayName: Translation.tr("Desaturate"),
                            icon: "tonality",
                            tooltip: Translation.tr("Low-cost preset using desaturation and reduced brightness without blur."),
                            value: "desaturate"
                        },
                        {
                            displayName: Translation.tr("Directional"),
                            icon: "open_in_new",
                            tooltip: Translation.tr("Adds a small movement away from the configured bar position."),
                            value: "directional"
                        }
                    ]
                }
            }

            ConfigSwitch {
                visible: (Config.options.background.useBackgroundOverviewAlways ?? false)
                    && ((Config.options.background.overviewBackgroundStyle ?? "") === "material-shape")
                    && !page.videoWallpaper
                enabled: !page.videoWallpaper
                buttonIcon: "wb_twilight"
                text: Translation.tr("Material Shape drop-shadow")
                checked: Config.options.background.materialShapeShadow === true
                onCheckedChanged: {
                    Config.options.background.materialShapeShadow = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Renders a subtle outer drop shadow around the material shape mask.")
                }
            }

            ConfigSlider {
                visible: (Config.options.background.useBackgroundOverviewAlways ?? false)
                    && ((Config.options.background.overviewBackgroundStyle ?? "") === "material-shape")
                    && !page.videoWallpaper
                enabled: !page.videoWallpaper
                buttonIcon: "aspect_ratio"
                text: Translation.tr("Material Shape scale (%)")
                usePercentTooltip: true
                from: 30
                to: 200
                stepSize: 1
                value: Math.round((Config.options.background.materialShapeScale ?? 1.0) * 100)
                onValueChanged: {
                    Config.options.background.materialShapeScale = value / 100;
                }
            }
        }

        ContentSection {
            title: Translation.tr("Background Blur")
            icon: "grain"

            ConfigSwitch {
                buttonIcon: "blur_on"
                text: Translation.tr("Blur wallpaper when window open (Experimental)")
                enabled: !page.videoWallpaper
                checked: Config.options.background.blurWhenWindowsOpen
                onCheckedChanged: {
                    Config.options.background.blurWhenWindowsOpen = checked;
                }

                StyledToolTip {
                    text: Translation.tr("Experimental - Blur the wallpaper and widgets when a window is open on the current workspace.")
                }
            }

            ConfigSlider {
                buttonIcon: "lens_blur"
                text: Translation.tr("Blur intensity when a window is open")
                enabled: !page.videoWallpaper
                visible: Config.options.background.blurWhenWindowsOpen
                usePercentTooltip: true
                from: 0
                to: 100
                stepSize: 1
                value: Config.options.background.blurWhenWindowsOpenRadius ?? 80
                onValueChanged: {
                    Config.options.background.blurWhenWindowsOpenRadius = value;
                }
            }
        }

        KeyboardShortcutBox {
            Layout.fillWidth: true
            text: Translation.tr("Toggle Media Mode")
            keys: ["Super", "Z"]
        }

        ContentSection {
            title: Translation.tr("Media Mode Background")
            icon: "music_note"

            NoticeBox {
                Layout.fillWidth: true
                isFirst: true
                text: Translation.tr("These settings apply exclusively to the full-screen Media Mode background overlay.")
            }

            ConfigSwitch {
                buttonIcon: "music_note"
                text: Translation.tr("Media mode background overlay")
                checked: Config.options.background.mediaMode.showLyrics ?? true
                configPage: Qt.resolvedUrl("widgets/MediaModeBackgroundConfig.qml")
                onCheckedChanged: {
                    Config.options.background.mediaMode.showLyrics = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Click button text to configure lyrics, visualizers, album art opacity, and music video settings.")
                }
            }
        }

        ShortcutBox {
            Layout.fillWidth: true
            value: Translation.tr("Desktop Clock Widget settings")
            targetPageId: "widgets"
            targetSectionTitle: Translation.tr("Widget Manager")
        }

        ContentSection {
            icon: "link"
            title: Translation.tr("Related settings")

            Flow {
                Layout.fillWidth: true
                spacing: 8

                RelatedChip {
                    pageId: "windows"
                    label: Translation.tr("Window blur")
                    sectionHighlight: Translation.tr("Transparency & Blur")
                }

                RelatedChip {
                    pageId: "lockScreen"
                    label: Translation.tr("Lock screen blur")
                    sectionHighlight: Translation.tr("Blur style")
                }
            }
        }
    }

    ConfigSubPageHost {
        id: subPageOverlay
        anchors.fill: parent
        z: 10
    }
}
