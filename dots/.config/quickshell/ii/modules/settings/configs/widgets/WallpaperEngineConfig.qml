import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Item {
    id: subPageRoot
    anchors.fill: parent

    property bool showBackButton: false
    signal goBack()

    ContentPage {
        id: page
        anchors.fill: parent
        forceWidth: false

        RowLayout {
            visible: subPageRoot.showBackButton
            spacing: 12

            RippleButton {
                implicitWidth: implicitHeight
                implicitHeight: 40
                topLeftRadius: Appearance.rounding.full
                topRightRadius: Appearance.rounding.full
                bottomLeftRadius: Appearance.rounding.full
                bottomRightRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive
                onClicked: subPageRoot.goBack()

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "arrow_back"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }

            StyledText {
                text: Translation.tr("Linux Wallpaper Engine")
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                color: Appearance.colors.colOnLayer0
            }
        }

        Process {
            id: checkEngineProc
            property bool installed: false
            command: ["which", "linux-wallpaperengine"]
            onExited: (exitCode, exitStatus) => {
                checkEngineProc.installed = (exitCode === 0);
            }
            Component.onCompleted: {
                if (Config.options.background.useWallpaperEngine) {
                    exec(["which", "linux-wallpaperengine"]);
                }
            }
        }

        Process {
            id: runListWpeProc
            command: ["python3", Directories.scriptPath + "/colors/list_wpe_wallpapers.py"]
            onExited: (exitCode, exitStatus) => {
                if (exitCode === 0) {
                    wpeWallpapersFileView.reload();
                }
            }
            Component.onCompleted: {
                if (Config.options.background.useWallpaperEngine) {
                    exec(["python3", Directories.scriptPath + "/colors/list_wpe_wallpapers.py"]);
                }
            }
        }

        Connections {
            target: Config.options.background
            function onUseWallpaperEngineChanged() {
                if (Config.options.background.useWallpaperEngine) {
                    checkEngineProc.exec(["which", "linux-wallpaperengine"]);
                    runListWpeProc.exec(["python3", Directories.scriptPath + "/colors/list_wpe_wallpapers.py"]);
                }
            }
        }

        FileView {
            id: wpeWallpapersFileView
            path: Config.options.background.useWallpaperEngine ? "file:///tmp/wpe_installed_wallpapers.json" : ""
            onLoaded: {
                if (!Config.options.background.useWallpaperEngine) return;
                try {
                    var raw = wpeWallpapersFileView.text().trim();
                    if (raw === "") return;
                    var list = JSON.parse(raw);
                    wpeWallpapersModel.clear();
                    for (var i = 0; i < list.length; i++) {
                        wpeWallpapersModel.append(list[i]);
                    }
                } catch (e) {
                    console.log("Error parsing installed WPE wallpapers: " + e);
                }
            }
        }

        ListModel {
            id: wpeWallpapersModel
        }

        ContentSection {
            title: Translation.tr("Linux Wallpaper Engine")
            icon: "wallpaper"

            ConfigSwitch {
                buttonIcon: "play_circle"
                text: Translation.tr("Enable Wallpaper Engine")
                checked: Config.options.background.useWallpaperEngine
                onCheckedChanged: {
                    if (Config.options.background.useWallpaperEngine === checked) return;
                    Config.options.background.useWallpaperEngine = checked;
                    Config.saveOptionsNow();
                    if (checked) {
                        if (Config.options.background.wallpaperEngineId) {
                            Wallpapers.apply(Config.options.background.wallpaperEngineId);
                        }
                    } else {
                        Quickshell.execDetached(["bash", "-c", "pkill -f linux-wallpaperengine; sleep 0.3; pkill -9 -f linux-wallpaperengine 2>/dev/null; true"]);
                        if (Config.options.background.wallpaperPath) {
                            Wallpapers.apply(Config.options.background.wallpaperPath);
                        }
                    }
                }
            }

            // Warning NoticeBox
            NoticeBox {
                Layout.fillWidth: true
                visible: Config.options.background.useWallpaperEngine
                materialIcon: "warning"
                text: "<b>" + Translation.tr("Experimental Feature!") + "</b><br>" +
                      Translation.tr("Bugs and performance issues are expected. Not all features of the ii shell (such as background animations) are supported by the live Wallpaper Engine window, and it will consume significantly more CPU/GPU resources.")

                RippleButton {
                    buttonText: Translation.tr("GitHub Repository")
                    colBackground: Appearance.colors.colPrimary
                    colBackgroundHover: Appearance.colors.colPrimaryHover
                    onClicked: {
                        Quickshell.execDetached(["xdg-open", "https://github.com/Almamu/linux-wallpaperengine"]);
                    }
                }
            }

            // Dependency warning card
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: warningLayout.implicitHeight + 24
                color: Qt.rgba(Appearance.colors.colError.r, Appearance.colors.colError.g, Appearance.colors.colError.b, 0.1)
                border.color: Appearance.colors.colError
                border.width: 1
                radius: Appearance.rounding.normal
                visible: Config.options.background.useWallpaperEngine && !checkEngineProc.installed

                ColumnLayout {
                    id: warningLayout
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 6

                    RowLayout {
                        spacing: 8
                        MaterialSymbol {
                            text: "warning"
                            color: Appearance.colors.colError
                            iconSize: 20
                        }
                        StyledText {
                            text: Translation.tr("Dependency missing!")
                            font.bold: true
                            color: Appearance.colors.colError
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer1
                        text: Translation.tr("The command 'linux-wallpaperengine' was not found in your PATH.\nTo install it: \n1. Build it from: https://github.com/Almamu/linux-wallpaperengine\n2. Copy the build/output contents to ~/.local/lib/linux-wallpaperengine/\n3. Create a wrapper script in ~/.local/bin/linux-wallpaperengine that runs it with --no-sandbox.")
                    }
                }
            }

            // Helper guide NoticeBox
            NoticeBox {
                Layout.fillWidth: true
                materialIcon: "help"
                text: "<b>" + Translation.tr("How to Install & Use:") + "</b><br>" +
                      Translation.tr("1. Clone/compile the engine from GitHub: Almamu/linux-wallpaperengine.<br>") +
                      Translation.tr("2. Place outputs in <b>~/.local/lib/linux-wallpaperengine/</b>.<br>") +
                      Translation.tr("3. Add wrapper at <b>~/.local/bin/linux-wallpaperengine</b> with <b>--no-sandbox</b>.<br>") +
                      Translation.tr("4. Enter a Wallpaper Workshop ID (e.g., <b>2441947759</b>) below and enable.")
            }

            // Wallpaper ID input with Apply Button
            ConfigTextField {
                id: wpeIdField
                visible: Config.options.background.useWallpaperEngine
                text: Translation.tr("Wallpaper Workshop ID or Path")
                icon: "badge"
                placeholderText: "e.g., 2441947759"
                inputText: Config.options.background.wallpaperEngineId
                textField.onEditingFinished: {
                    if (Config.options.background.wallpaperEngineId === textField.text) return;
                    Config.options.background.wallpaperEngineId = textField.text;
                    if (Config.options.background.useWallpaperEngine && textField.text) {
                        Wallpapers.apply(textField.text);
                    }
                }

                rightAction: RippleButton {
                    implicitWidth: 36
                    implicitHeight: 36
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colPrimaryContainer
                    colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                    colRipple: Appearance.colors.colPrimaryContainerActive
                    onClicked: {
                        var newText = wpeIdField.textField.text;
                        if (Config.options.background.wallpaperEngineId === newText) return;
                        Config.options.background.wallpaperEngineId = newText;
                        if (Config.options.background.useWallpaperEngine && newText) {
                            Wallpapers.apply(newText);
                        }
                    }
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "play_arrow"
                        iconSize: 18
                        color: Appearance.colors.colOnPrimaryContainer
                    }
                    StyledToolTip {
                        text: Translation.tr("Apply Wallpaper")
                    }
                }
            }

            // Custom Assets Path input
            ConfigTextField {
                visible: Config.options.background.useWallpaperEngine
                text: Translation.tr("Custom Assets Folder Path (Optional)")
                icon: "folder"
                placeholderText: Translation.tr("Leave empty for auto-detection")
                inputText: Config.options.background.wallpaperEngineAssetsPath
                textField.onEditingFinished: {
                    if (Config.options.background.wallpaperEngineAssetsPath === textField.text) return;
                    Config.options.background.wallpaperEngineAssetsPath = textField.text;
                    if (Config.options.background.useWallpaperEngine && Config.options.background.wallpaperEngineId) {
                        Wallpapers.apply(Config.options.background.wallpaperEngineId);
                    }
                }
            }

            // Horizontal list of installed wallpapers (2-row GridView)
            ContentSubsection {
                visible: Config.options.background.useWallpaperEngine && wpeWallpapersModel.count > 0
                title: Translation.tr("Installed Wallpapers")
                icon: "collections"
                Layout.fillWidth: true

                Item {
                    Layout.fillWidth: true
                    implicitHeight: 330

                    Process {
                        id: downloadProc
                        property string wallpaperId: ""
                    }

                    GridView {
                        id: wpeGrid
                        anchors.fill: parent
                        cellWidth: 200
                        cellHeight: 160
                        flow: GridView.FlowTopToBottom
                        clip: true
                        model: wpeWallpapersModel
                        interactive: true

                        Behavior on contentX {
                            NumberAnimation { duration: 300; easing.type: Easing.OutQuad }
                        }

                        delegate: Rectangle {
                            id: presetItem
                            width: 188
                            height: 148
                            radius: Appearance.rounding.large
                            color: Appearance.colors.colLayer0
                            border.color: isActive ? Appearance.colors.colPrimary : (presetButton.down ? Appearance.colors.colPrimaryActive : (presetButton.hovered ? Appearance.colors.colPrimaryHover : "transparent"))
                            border.width: 2

                            readonly property bool isActive: Config.options.background.wallpaperEngineId === model.id
                            readonly property bool previewActive: wpeGrid.visible
                                                                   && presetItem.visible
                                                                   && presetItem.x + presetItem.width >= wpeGrid.contentX
                                                                   && presetItem.x <= wpeGrid.contentX + wpeGrid.width
                                                                   && presetItem.y + presetItem.height >= wpeGrid.contentY
                                                                   && presetItem.y <= wpeGrid.contentY + wpeGrid.height

                            Behavior on border.color {
                                ColorAnimation {
                                    duration: Appearance.animation.elementMoveFast.duration
                                    easing.type: Appearance.animation.elementMoveFast.type
                                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                                }
                            }
                            scale: presetButton.down ? 0.96 : (presetButton.hovered ? 1.02 : 1)
                            Behavior on scale {
                                NumberAnimation {
                                    duration: Appearance.animation.elementMoveFast.duration
                                    easing.type: Appearance.animation.elementMoveFast.type
                                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                                }
                            }

                            RippleButton {
                                id: presetButton
                                anchors.fill: parent
                                buttonRadius: Appearance.rounding.large
                                colBackground: "transparent"
                                colBackgroundHover: "transparent"
                                colRipple: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.8)
                                onClicked: {
                                    if (Config.options.background.wallpaperEngineId === model.id) return;
                                    Config.options.background.wallpaperEngineId = model.id;
                                    Wallpapers.apply(model.id);
                                }
                            }

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 6

                                Item {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true

                                    AnimatedImage {
                                        id: previewImage
                                        anchors.fill: parent
                                        source: presetItem.previewActive && model.preview ? Qt.resolvedUrl(model.preview) : ""
                                        fillMode: Image.PreserveAspectCrop
                                        playing: presetItem.previewActive
                                        visible: presetItem.previewActive && status === Image.Ready
                                        layer.enabled: presetItem.previewActive && status === Image.Ready
                                        layer.effect: OpacityMask {
                                            maskSource: Rectangle {
                                                width: previewImage.width
                                                height: previewImage.height
                                                radius: Appearance.rounding.normal
                                            }
                                        }
                                    }

                                    ThumbnailImage {
                                        id: previewFrameImage
                                        anchors.fill: parent
                                        visible: presetItem.previewActive && (!model.preview || previewImage.status === Image.Error) && !!model.file
                                        sourcePath: presetItem.previewActive ? (model.file || "") : ""
                                        thumbnailService: Wallpapers
                                        generateThumbnail: presetItem.previewActive && visible
                                        cache: false
                                        fillMode: Image.PreserveAspectCrop
                                        clip: true
                                        layer.enabled: true
                                        layer.effect: OpacityMask {
                                            maskSource: Rectangle {
                                                width: previewFrameImage.width
                                                height: previewFrameImage.height
                                                radius: Appearance.rounding.normal
                                            }
                                        }
                                    }

                                    StyledImage {
                                        anchors.fill: parent
                                        visible: presetItem.previewActive && !previewImage.visible && (!previewFrameImage.visible || previewFrameImage.status !== Image.Ready)
                                        source: presetItem.previewActive ? `${Directories.assetsPath}/images/default_wallpaper.png` : ""
                                        fillMode: Image.PreserveAspectCrop
                                    }

                                    // Active Badge / Checkmark
                                    Rectangle {
                                        anchors {
                                            top: parent.top
                                            right: parent.right
                                            margins: 6
                                        }
                                        width: 24
                                        height: 24
                                        radius: 12
                                        color: Appearance.colors.colPrimary
                                        visible: presetItem.isActive
                                        z: 5

                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: "done"
                                            iconSize: 14
                                            color: Appearance.colors.colOnPrimary
                                        }
                                    }

                                    // Download Button — saves video/preview to ~/Pictures/Wallpapers
                                    Rectangle {
                                        anchors {
                                            top: parent.top
                                            left: parent.left
                                            margins: 6
                                        }
                                        width: 26
                                        height: 26
                                        radius: 13
                                        color: Qt.rgba(0, 0, 0, 0.55)
                                        visible: presetButton.hovered && !downloadProc.running
                                        z: 5

                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: "download"
                                            iconSize: 15
                                            color: "#ffffff"
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                const scriptPath = `${Directories.scriptPath}/colors/download_wpe_wallpaper.py`;
                                                downloadProc.command = ["python3", scriptPath, model.id, "--quality", "full"];
                                                downloadProc.running = true;
                                            }
                                        }
                                    }

                                    // Download progress indicator
                                    Rectangle {
                                        anchors {
                                            top: parent.top
                                            left: parent.left
                                            margins: 6
                                        }
                                        width: 26
                                        height: 26
                                        radius: 13
                                        color: Qt.rgba(0, 0, 0, 0.55)
                                        visible: downloadProc.running
                                        z: 5

                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: "downloading"
                                            iconSize: 15
                                            color: Appearance.colors.colPrimary
                                        }
                                    }
                                }

                                Item {
                                    Layout.fillWidth: true
                                    implicitHeight: 20

                                    StyledText {
                                        anchors {
                                            left: parent.left
                                            right: parent.right
                                            verticalCenter: parent.verticalCenter
                                            leftMargin: 4
                                            rightMargin: 4
                                        }
                                        text: model.title
                                        color: Appearance.colors.colOnLayer1
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        font.weight: presetItem.isActive ? Font.Bold : Font.Normal
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }
                    }

                    // Left Arrow Floating Button
                    RippleButton {
                        anchors {
                            left: parent.left
                            verticalCenter: parent.verticalCenter
                            leftMargin: -12
                        }
                        width: 40
                        height: 40
                        z: 10
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colLayer0
                        colBackgroundHover: Appearance.colors.colLayer0Hover
                        colRipple: Appearance.colors.colLayer0Active
                        visible: wpeGrid.contentX > 0

                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            text: "chevron_left"
                            iconSize: 24
                            color: Appearance.colors.colOnLayer0
                        }

                        onClicked: {
                            wpeGrid.contentX = Math.max(0, wpeGrid.contentX - 400);
                        }
                    }

                    // Right Arrow Floating Button
                    RippleButton {
                        anchors {
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            rightMargin: -12
                        }
                        width: 40
                        height: 40
                        z: 10
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colLayer0
                        colBackgroundHover: Appearance.colors.colLayer0Hover
                        colRipple: Appearance.colors.colLayer0Active
                        visible: wpeGrid.contentWidth > wpeGrid.width && wpeGrid.contentX < wpeGrid.contentWidth - wpeGrid.width - 10

                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            text: "chevron_right"
                            iconSize: 24
                            color: Appearance.colors.colOnLayer0
                        }

                        onClicked: {
                            wpeGrid.contentX = Math.min(wpeGrid.contentWidth - wpeGrid.width, wpeGrid.contentX + 400);
                        }
                    }
                }
            }

            // Performance & Behavior Settings
            ContentSubsectionLabel {
                text: Translation.tr("Performance & Behavior")
                visible: Config.options.background.useWallpaperEngine
            }

            ConfigSwitch {
                visible: Config.options.background.useWallpaperEngine
                buttonIcon: "pause_circle_outline"
                text: Translation.tr("Pause animations when windows are open")
                checked: Config.options.background.wpePauseWhenWindowsOpen
                onCheckedChanged: {
                    if (Config.options.background.wpePauseWhenWindowsOpen === checked) return;
                    Config.options.background.wpePauseWhenWindowsOpen = checked;
                }
            }

            ConfigSwitch {
                visible: Config.options.background.useWallpaperEngine
                buttonIcon: "pause_circle"
                text: Translation.tr("No Fullscreen Pause")
                checked: Config.options.background.wpeNoFullscreenPause
                onCheckedChanged: {
                    if (Config.options.background.wpeNoFullscreenPause === checked) return;
                    Config.options.background.wpeNoFullscreenPause = checked;
                    if (Config.options.background.useWallpaperEngine && Config.options.background.wallpaperEngineId) {
                        Wallpapers.apply(Config.options.background.wallpaperEngineId);
                    }
                }
            }

            ConfigSpinBox {
                visible: Config.options.background.useWallpaperEngine
                icon: "speed"
                text: Translation.tr("Framerate Limit (FPS)")
                value: Config.options.background.wpeFps ?? 30
                from: 15
                to: 144
                stepSize: 5
                onValueChanged: {
                    if (Config.options.background.wpeFps === value) return;
                    Config.options.background.wpeFps = value;
                    if (Config.options.background.useWallpaperEngine && Config.options.background.wallpaperEngineId) {
                        Wallpapers.apply(Config.options.background.wallpaperEngineId);
                    }
                }
            }

            // Display & Interaction Settings
            ContentSubsectionLabel {
                text: Translation.tr("Display & Interaction")
                visible: Config.options.background.useWallpaperEngine
            }

            ConfigSwitch {
                visible: Config.options.background.useWallpaperEngine
                buttonIcon: "mouse"
                text: Translation.tr("Disable Mouse Interaction")
                checked: Config.options.background.wpeDisableMouse
                onCheckedChanged: {
                    if (Config.options.background.wpeDisableMouse === checked) return;
                    Config.options.background.wpeDisableMouse = checked;
                    if (Config.options.background.useWallpaperEngine && Config.options.background.wallpaperEngineId) {
                        Wallpapers.apply(Config.options.background.wallpaperEngineId);
                    }
                }
            }

            ConfigSwitch {
                visible: Config.options.background.useWallpaperEngine
                buttonIcon: "blur_off"
                text: Translation.tr("Disable Parallax Effect")
                checked: Config.options.background.wpeDisableParallax
                onCheckedChanged: {
                    if (Config.options.background.wpeDisableParallax === checked) return;
                    Config.options.background.wpeDisableParallax = checked;
                    if (Config.options.background.useWallpaperEngine && Config.options.background.wallpaperEngineId) {
                        Wallpapers.apply(Config.options.background.wallpaperEngineId);
                    }
                }
            }

            ConfigTextField {
                visible: Config.options.background.useWallpaperEngine
                text: Translation.tr("Screen Span (e.g. HDMI-A-1,eDP-1)")
                icon: "settings_overscan"
                placeholderText: Translation.tr("Stretch single wallpaper across monitors (Optional)")
                inputText: Config.options.background.wpeScreenSpan
                textField.onEditingFinished: {
                    if (Config.options.background.wpeScreenSpan === textField.text) return;
                    Config.options.background.wpeScreenSpan = textField.text;
                    if (Config.options.background.useWallpaperEngine && Config.options.background.wallpaperEngineId) {
                        Wallpapers.apply(Config.options.background.wallpaperEngineId);
                    }
                }
            }

            ContentSubsection {
                visible: Config.options.background.useWallpaperEngine
                title: Translation.tr("Wallpaper scaling")
                icon: "aspect_ratio"
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: Config.options.background.wpeScaling ?? "default"
                    onSelected: newValue => {
                        if (Config.options.background.wpeScaling === newValue) return;
                        Config.options.background.wpeScaling = newValue;
                        if (Config.options.background.useWallpaperEngine && Config.options.background.wallpaperEngineId) {
                            Wallpapers.apply(Config.options.background.wallpaperEngineId);
                        }
                    }
                    options: [
                        { displayName: Translation.tr("Default"), value: "default", icon: "select_all" },
                        { displayName: Translation.tr("Stretch"), value: "stretch", icon: "aspect_ratio" },
                        { displayName: Translation.tr("Fit"), value: "fit", icon: "fit_screen" },
                        { displayName: Translation.tr("Fill"), value: "fill", icon: "crop_free" }
                    ]
                }
            }

            // Silent mode toggle
            ConfigSwitch {
                buttonIcon: "volume_off"
                text: Translation.tr("Silent Mode")
                visible: Config.options.background.useWallpaperEngine
                checked: Config.options.background.wpeSilent
                onCheckedChanged: {
                    if (Config.options.background.wpeSilent === checked) return;
                    Config.options.background.wpeSilent = checked;
                    if (Config.options.background.useWallpaperEngine && Config.options.background.wallpaperEngineId) {
                        Wallpapers.apply(Config.options.background.wallpaperEngineId);
                    }
                }
            }

            // Audio Settings (hidden when Silent Mode is active)
            ContentSubsectionLabel {
                text: Translation.tr("Audio Settings")
                visible: Config.options.background.useWallpaperEngine && !Config.options.background.wpeSilent
            }

            ConfigSlider {
                visible: Config.options.background.useWallpaperEngine && !Config.options.background.wpeSilent
                buttonIcon: "volume_down"
                text: Translation.tr("Volume Level")
                usePercentTooltip: true
                from: 0
                to: 100
                stepSize: 1
                value: Config.options.background.wpeVolume ?? 50
                onValueChanged: {
                    if (Config.options.background.wpeVolume === Math.round(value)) return;
                    Config.options.background.wpeVolume = Math.round(value);
                    if (Config.options.background.useWallpaperEngine && Config.options.background.wallpaperEngineId) {
                        Wallpapers.apply(Config.options.background.wallpaperEngineId);
                    }
                }
            }

            ConfigSwitch {
                visible: Config.options.background.useWallpaperEngine && !Config.options.background.wpeSilent
                buttonIcon: "music_off"
                text: Translation.tr("Don't Auto Mute")
                checked: Config.options.background.wpeNoAutoMute
                onCheckedChanged: {
                    if (Config.options.background.wpeNoAutoMute === checked) return;
                    Config.options.background.wpeNoAutoMute = checked;
                    if (Config.options.background.useWallpaperEngine && Config.options.background.wallpaperEngineId) {
                        Wallpapers.apply(Config.options.background.wallpaperEngineId);
                    }
                }
            }

            ConfigSwitch {
                visible: Config.options.background.useWallpaperEngine && !Config.options.background.wpeSilent
                buttonIcon: "graphic_eq"
                text: Translation.tr("Disable Audio Reactive Features")
                checked: Config.options.background.wpeNoAudioProcessing
                onCheckedChanged: {
                    if (Config.options.background.wpeNoAudioProcessing === checked) return;
                    Config.options.background.wpeNoAudioProcessing = checked;
                    if (Config.options.background.useWallpaperEngine && Config.options.background.wallpaperEngineId) {
                        Wallpapers.apply(Config.options.background.wallpaperEngineId);
                    }
                }
            }
        }


    }
}
