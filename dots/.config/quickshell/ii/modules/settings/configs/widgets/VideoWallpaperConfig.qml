import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings.configs.background

Item {
    id: subPageRoot
    anchors.fill: parent

    property bool showBackButton: false
    signal goBack()

    readonly property var background: Config.options.background
    readonly property bool shellBackend: (background.videoBackend ?? "mpvpaper") === "shell"
    readonly property real progressWidth: 240
    readonly property real previewMaxWidth: 400
    readonly property real previewAspect: 16 / 9
    readonly property real previewInset: 8
    readonly property real previewImageWidth: 640
    readonly property string frameVideo: !background.useWallpaperEngine && Wallpapers.isVideoFile(background.wallpaperPath ?? "") ? background.wallpaperPath : ""

    VideoPlayerSetup {
        id: setup
        active: subPageRoot.shellBackend
    }

    VideoColorFrame {
        id: frame
    }

    ContentPage {
        id: root
        anchors.fill: parent
        forceWidth: false

        BackgroundSubPageHeader {
            visible: subPageRoot.showBackButton
            title: Translation.tr("Video wallpapers")
            onBackRequested: subPageRoot.goBack()
        }

        ContentSection {
            title: Translation.tr("Playback")
            icon: "play_circle"

            ConfigSwitch {
                buttonIcon: "pause_circle"
                text: Translation.tr("Pause while windows are open")
                visible: subPageRoot.shellBackend
                checked: subPageRoot.background.videoPauseWhenWindowsOpen ?? false
                onCheckedChanged: {
                    subPageRoot.background.videoPauseWhenWindowsOpen = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Freeze the video while the workspace has any window. It always pauses behind maximized or fullscreen windows, on the always-on display and when a separate lock screen wallpaper covers it.")
                }
            }

            ConfigSwitch {
                buttonIcon: "lock"
                text: Translation.tr("Pause on the lock screen")
                visible: subPageRoot.shellBackend
                checked: subPageRoot.background.videoPauseOnLock ?? true
                onCheckedChanged: {
                    subPageRoot.background.videoPauseOnLock = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Freeze the video while the screen is locked. Turned off, it keeps playing behind the lock screen; with the lock blur on, \n the blur is then redrawn for every frame, which costs more GPU while the computer sits locked.")
                }
            }

            ConfigSwitch {
                buttonIcon: "aspect_ratio"
                text: Translation.tr("Play large videos at screen size")
                checked: subPageRoot.background.videoDownscale ?? true
                onCheckedChanged: {
                    subPageRoot.background.videoDownscale = checked;
                }
                StyledToolTip {
                    text: Translation.tr("A video taller than your screen (4K on a 1080p display) is decoded and scaled at full size every frame: about 600 MB more video memory \n and 120 MB more RAM, for no visible gain. When on, a screen-sized copy is made \n once in the background (hardware encoder when available, kept in ~/.cache/quickshell-ii/video-proxies) \n and played instead. The original file is untouched.")
                }
            }
        }

        ContentSection {
            visible: subPageRoot.shellBackend
            title: Translation.tr("Efficient player (libmpv)")
            icon: "memory"

            NoticeBox {
                Layout.fillWidth: true
                isFirst: true
                text: setup.pluginLoaded
                    ? Translation.tr("Videos are decoded by libmpv with hardware decoding, and the frames stay on the GPU.")
                    : Translation.tr("Until this plugin is built the shell plays videos with QtMultimedia. That works without setup, but costs more CPU: on NVIDIA every frame is copied through system memory.")
            }

            SetupStep {
                dynamicRadius: true
                number: 1
                done: setup.depsReady
                title: Translation.tr("Install the build tools")
                body: {
                    if (setup.buildStatus === null)
                        return Translation.tr("Checking…");
                    if (setup.depsReady)
                        return Translation.tr("CMake, a C++ compiler, libmpv and the Qt 6 development files are installed.");
                    const missing = setup.missingDeps.join(", ");
                    if ((setup.buildStatus.installCommand ?? "") === "")
                        return Translation.tr("Missing: %1. Install them with your package manager, then check again.").arg(missing);
                    if (setup.waitingForDeps)
                        return Translation.tr("Finish the install in the terminal; this step updates on its own.");
                    return Translation.tr("Missing: %1. Install them on %2:").arg(missing).arg(SystemInfo.distroName);
                }
                command: setup.depsReady ? "" : (setup.buildStatus?.installCommand ?? "")

                AppRowButton {
                    visible: !setup.depsReady && (setup.buildStatus?.installCommand ?? "") !== ""
                    filled: true
                    symbol: "download"
                    label: Translation.tr("Install")
                    onClicked: setup.installDependencies()
                }
                AppRowButton {
                    visible: !setup.depsReady
                    symbol: "refresh"
                    label: Translation.tr("Check again")
                    onClicked: setup.refreshStatus()
                }
            }

            SetupStep {
                dynamicRadius: true
                number: 2
                done: setup.pluginBuilt && !setup.building
                title: Translation.tr("Build the plugin")
                bodyColor: setup.buildFailed ? Appearance.colors.colError : Appearance.colors.colSubtext
                body: {
                    if (setup.building)
                        return setup.buildLine.length > 0 ? setup.buildLine : Translation.tr("Starting…");
                    if (setup.buildFailed)
                        return Translation.tr("The build failed: %1").arg(setup.buildLine);
                    if (setup.pluginBuilt)
                        return Translation.tr("Installed in %1. Build again after Qt updates.").arg(setup.buildStatus.installedDir);
                    return Translation.tr("Compiles plugins/mpv-wallpaper and installs it for your user. It takes about a minute, or run it yourself:");
                }
                command: setup.pluginBuilt || setup.building ? "" : setup.buildScript

                StyledProgressBar {
                    visible: setup.building
                    Layout.fillWidth: true
                    Layout.preferredWidth: subPageRoot.progressWidth
                    value: setup.buildProgress
                }
                AppRowButton {
                    visible: !setup.building
                    enabled: setup.depsReady
                    filled: !setup.pluginBuilt
                    symbol: setup.pluginBuilt ? "refresh" : "build"
                    label: setup.pluginBuilt ? Translation.tr("Rebuild") : Translation.tr("Build")
                    onClicked: setup.build()
                }
                AppRowButton {
                    visible: setup.buildFailed
                    symbol: "terminal"
                    label: Translation.tr("Build in terminal")
                    tooltip: Translation.tr("Shows the full compiler output")
                    onClicked: setup.runInTerminal([])
                }
            }

            SetupStep {
                dynamicRadius: true
                number: 3
                done: setup.pluginLoaded
                title: Translation.tr("Load it in the shell")
                body: {
                    if (setup.pluginLoaded)
                        return Translation.tr("The shell is using libmpv for video wallpapers.");
                    if (!setup.importPathReady)
                        return Translation.tr("This session does not look for plugins in %1 yet. Restarting reloads Hyprland's environment first, then the shell.").arg(setup.buildStatus?.userQmlDir ?? "~/.local/lib/qt6/qml");
                    return Translation.tr("Restart the shell to load the plugin.");
                }

                AppRowButton {
                    visible: !setup.pluginLoaded
                    enabled: setup.pluginBuilt && !setup.building
                    filled: setup.pluginBuilt
                    symbol: "restart_alt"
                    label: Translation.tr("Restart shell")
                    onClicked: setup.restartShell()
                }
            }
        }

        ContentSection {
            visible: frame.video !== ""
            title: Translation.tr("Color frame")
            icon: "palette"

            NoticeBox {
                Layout.fillWidth: true
                isFirst: true
                text: Translation.tr("The theme colors and the poster frame shown before the video plays come from one moment of the video. Pick another one if the first frame is black or does not represent it.")
            }

            ClippingRectangle {
                visible: frame.video !== ""
                Layout.preferredWidth: Math.min(parent.width, subPageRoot.previewMaxWidth)
                Layout.preferredHeight: Layout.preferredWidth / subPageRoot.previewAspect
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer3

                Image {
                    anchors.fill: parent
                    source: frame.preview !== "" ? "file://" + frame.preview : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                    sourceSize.width: subPageRoot.previewImageWidth
                }
                Rectangle {
                    anchors {
                        left: parent.left
                        bottom: parent.bottom
                        margins: subPageRoot.previewInset
                    }
                    implicitWidth: frameTimeLabel.implicitWidth + 16
                    implicitHeight: frameTimeLabel.implicitHeight + 8
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colSecondaryContainer

                    StyledText {
                        id: frameTimeLabel
                        anchors.centerIn: parent
                        text: frame.format(frame.seconds)
                        color: Appearance.colors.colOnSecondaryContainer
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
                }
            }

            RowLayout {
                visible: frame.video !== ""
                spacing: 6

                AppRowButton {
                    filled: true
                    enabled: !frame.applying && frame.seconds !== frame.appliedSeconds
                    symbol: frame.applying ? "hourglass_top" : "check"
                    label: frame.applying ? Translation.tr("Generating colors…") : Translation.tr("Apply")
                    onClicked: frame.apply()
                }
                AppRowButton {
                    visible: frame.seconds !== 0
                    symbol: "first_page"
                    label: Translation.tr("First frame")
                    onClicked: frame.seconds = 0
                }
                StyledText {
                    Layout.leftMargin: 6
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    text: frame.appliedSeconds > 0
                        ? Translation.tr("In use: %1").arg(frame.format(frame.appliedSeconds))
                        : Translation.tr("In use: first frame")
                }
            }

            ConfigSlider {
                id: frameSlider
                visible: frame.video !== ""
                buttonIcon: "timer"
                text: Translation.tr("Frame time")
                from: 0
                to: Math.max(0.1, frame.duration)
                stepSize: 0.1
                usePercentTooltip: false
                tooltipContent: frame.format(value)
                enabled: frame.duration > 0
                // A drag replaces a plain `value:` binding; this one comes back on release.
                // It also depends on the duration and is delayed, so it lands after
                // `to` has grown: applied first, the range would clamp it.
                Binding on value {
                    value: frame.duration > 0 ? frame.seconds : 0
                    when: !frameSlider.pressed
                    delayed: true
                }
                // Only a drag writes back: the range is still 0..0.1 until the
                // duration is known, and a programmatic clamp must not move the pick.
                onValueChanged: {
                    if (!pressed)
                        return;
                    const next = frame.clamp(value);
                    if (next !== frame.seconds)
                        frame.seconds = next;
                }
            }

            ConfigTextField {
                id: frameTimeField
                visible: frame.video !== ""
                icon: "schedule"
                text: Translation.tr("Timestamp")
                tooltip: Translation.tr("Seconds or minutes:seconds, e.g. 12.5 or 1:05.2. Press Enter to preview it.")
                placeholderText: "0:00.0"
                textField.onEditingFinished: {
                    const parsed = frame.parse(textField.text);
                    if (!isNaN(parsed))
                        frame.seconds = frame.clamp(parsed);
                    textField.text = frame.format(frame.seconds);
                }
                Connections {
                    target: frame
                    function onSecondsChanged() {
                        if (!frameTimeField.textField.activeFocus)
                            frameTimeField.textField.text = frame.format(frame.seconds);
                    }
                }
                Component.onCompleted: textField.text = frame.format(frame.seconds)
            }
        }
    }
}
