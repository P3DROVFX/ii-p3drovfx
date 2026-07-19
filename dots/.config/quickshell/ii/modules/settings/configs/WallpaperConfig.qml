import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services

ContentPage {
    id: page

    forceWidth: false

    ContentSection {
        title: Translation.tr("Wallpaper")
        icon: "wallpaper"

        ConfigWallpaperSelector {
            Layout.fillWidth: true
            text: Translation.tr("Wallpaper Selector")
        }

        ConfigSwitch {
            buttonIcon: "folder_shared"
            text: Translation.tr("Use system file picker")
            checked: Config.options.wallpaperSelector.useSystemFileDialog
            onCheckedChanged: {
                Config.options.wallpaperSelector.useSystemFileDialog = checked;
            }

            StyledToolTip {
                text: Translation.tr("Uses xdg-desktop-portal instead of the built-in quickshell picker")
            }

        }

    }

    ContentSection {
        title: Translation.tr("Parallax Engine")
        icon: "sync_alt"

        ConfigSwitch {
            buttonIcon: "unfold_more_double"
            text: Translation.tr("Vertical movement")
            checked: Config.options.background.parallax.vertical
            onCheckedChanged: {
                HyprlandSettings.changeAnimation("workspaces", checked ? "slidevert" : "slide");
                Config.options.background.parallax.vertical = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "counter_1"
            text: Translation.tr("Depends on workspace")
            checked: Config.options.background.parallax.enableWorkspace
            onCheckedChanged: {
                Config.options.background.parallax.enableWorkspace = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "loop"
            text: Translation.tr("Loop wallpaper")
            checked: Config.options.background.parallax.loop
            onCheckedChanged: {
                Config.options.background.parallax.loop = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "swap_horiz"
            text: Translation.tr("Invert horizontal movement")
            checked: Config.options.background.parallax.invertHorizontal
            onCheckedChanged: {
                Config.options.background.parallax.invertHorizontal = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "swap_vert"
            text: Translation.tr("Invert vertical movement")
            checked: Config.options.background.parallax.invertVertical
            onCheckedChanged: {
                Config.options.background.parallax.invertVertical = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "side_navigation"
            text: Translation.tr("Depends on sidebars")
            checked: Config.options.background.parallax.enableSidebar
            onCheckedChanged: {
                Config.options.background.parallax.enableSidebar = checked;
            }
        }

        ConfigSlider {
            buttonIcon: "speed"
            text: Translation.tr("Parallax movement intensity")
            visible: Config.options.background.parallax.enableWorkspace
            usePercentTooltip: false
            from: 1
            to: 10
            stepSize: 1
            value: Config.options.background.parallax.intensity ?? 4
            onValueChanged: {
                Config.options.background.parallax.intensity = value;
            }
        }

        ConfigSlider {
            buttonIcon: "loupe"
            text: Translation.tr("Preferred wallpaper zoom (%)")
            from: 100
            to: 150
            stepSize: 1
            value: Config.options.background.parallax.workspaceZoom * 100
            onValueChanged: {
                Config.options.background.parallax.workspaceZoom = value / 100;
            }
        }

    }

    ContentSection {
        title: Translation.tr("Transition Animations")
        icon: "animation"

        ConfigSwitch {
            buttonIcon: "blur_on"
            text: Translation.tr("Animate wallpaper changes")
            checked: Config.options.background.animateWallpaperChanges
            onCheckedChanged: {
                Config.options.background.animateWallpaperChanges = checked;
            }
        }

        ContentSubsection {
            visible: Config.options.background.animateWallpaperChanges
            title: Translation.tr("Transition style")
            icon: "style"
            Layout.fillWidth: true

            ConfigSelectionArray {
                currentValue: Config.options.background.wallpaperAnimation
                onSelected: (newValue) => {
                    Config.options.background.wallpaperAnimation = newValue;
                }
                options: [{
                    "displayName": Translation.tr("Random"),
                    "icon": "shuffle",
                    "value": "random"
                }, {
                    "displayName": Translation.tr("Crossfade"),
                    "icon": "blur_on",
                    "value": ""
                }, {
                    "displayName": Translation.tr("Circle Pit"),
                    "icon": "circle",
                    "value": "circlePit"
                }, {
                    "displayName": Translation.tr("Circle Select"),
                    "icon": "radio_button_checked",
                    "value": "circleSelect"
                }, {
                    "displayName": Translation.tr("Magic"),
                    "icon": "auto_awesome",
                    "value": "magic"
                }, {
                    "displayName": Translation.tr("Peel"),
                    "icon": "sticky_note_2",
                    "value": "Peel"
                }, {
                    "displayName": Translation.tr("Transition"),
                    "icon": "swap_horiz",
                    "value": "transition"
                }, {
                    "displayName": Translation.tr("Pixelate"),
                    "icon": "grid_on",
                    "value": "pixelate"
                }, {
                    "displayName": Translation.tr("Stripes"),
                    "icon": "view_column",
                    "value": "stripes"
                }]
            }

        }

        ConfigSwitch {
            buttonIcon: "blur_circular"
            text: Translation.tr("Blur wallpaper when a window is open")
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

        ConfigSwitch {
            buttonIcon: "gradient"
            text: Translation.tr("Gradient blur effect on wallpaper")
            checked: Config.options.background.gradientBlur.enable
            onCheckedChanged: {
                Config.options.background.gradientBlur.enable = checked;
            }

            StyledToolTip {
                text: Translation.tr("Apply a gradient blur effect across the wallpaper for a smooth transition from sharp to blurred.")
            }

        }

        ConfigSlider {
            buttonIcon: "lens_blur"
            text: Translation.tr("Gradient blur intensity")
            visible: Config.options.background.gradientBlur.enable
            usePercentTooltip: true
            from: 0
            to: 100
            stepSize: 1
            value: Config.options.background.gradientBlur.radius ?? 50
            onValueChanged: {
                Config.options.background.gradientBlur.radius = value;
            }
        }

        ContentSubsection {
            visible: Config.options.background.gradientBlur.enable
            title: Translation.tr("Gradient blur direction")
            icon: "swap_vert"
            Layout.fillWidth: true

            ConfigSelectionArray {
                currentValue: Config.options.background.gradientBlur.direction ?? "top-to-bottom"
                onSelected: (newValue) => {
                    Config.options.background.gradientBlur.direction = newValue;
                }
                options: [{
                    "displayName": Translation.tr("Top → Bottom"),
                    "icon": "arrow_downward",
                    "value": "top-to-bottom"
                }, {
                    "displayName": Translation.tr("Bottom → Top"),
                    "icon": "arrow_upward",
                    "value": "bottom-to-top"
                }, {
                    "displayName": Translation.tr("Left → Right"),
                    "icon": "arrow_forward",
                    "value": "left-to-right"
                }, {
                    "displayName": Translation.tr("Right → Left"),
                    "icon": "arrow_back",
                    "value": "right-to-left"
                }]
            }

        }

        ConfigSwitch {
            buttonIcon: "zoom_in_map"
            text: Translation.tr("Zoom animation when overview/cheatsheet is open (Beta)")
            checked: Config.options.background.zoomOutEnabled
            onCheckedChanged: {
                Config.options.background.zoomOutEnabled = checked;
            }

            StyledToolTip {
                text: Translation.tr("Experimental - Scale windows with wallpaper when Overview/Cheatsheet is opened, this is a work in progress, expect bugs and a lags on low end hardware.")
            }

        }

        ContentSubsection {
            visible: Config.options.background.zoomOutEnabled
            title: Translation.tr("Zoom background style")
            icon: "style"
            Layout.fillWidth: true

            ConfigSelectionArray {
                currentValue: Config.options.background.zoomOutStyle
                onSelected: (newValue) => {
                    Config.options.background.zoomOutStyle = newValue;
                }
                options: [{
                    "displayName": Translation.tr("Gnome Like"),
                    "icon": "blur_on",
                    "value": 0
                }, {
                    "displayName": Translation.tr("Default"),
                    "icon": "grid_view",
                    "value": 1
                }, {
                    "displayName": Translation.tr("Zoom In"),
                    "icon": "zoom_in",
                    "value": 2
                }]
            }

        }

        ConfigSwitch {
            visible: Config.options.background.zoomOutEnabled && Config.options.background.zoomOutStyle === 0
            buttonIcon: "open_with"
            text: Translation.tr("Experimental - Scale windows with wallpaper")
            checked: Config.options.background.windowZoomOnOverview
            onCheckedChanged: {
                Config.options.background.windowZoomOnOverview = checked;
            }

            StyledToolTip {
                text: Translation.tr("Shows scaled ScreencopyView of windows zooming out with the wallpaper when the overview opens.\nWindows on the active workspace follow the wallpaper zoom animation.\nWorkspace switching slides the window previews alongside the workspace animation.")
            }

        }

        ConfigSwitch {
            visible: Config.options.background.zoomOutEnabled && Config.options.background.zoomOutStyle === 0 && Config.options.background.windowZoomOnOverview
            buttonIcon: "videocam"
            text: Translation.tr("Keep screencopy live (no freeze)")
            checked: Config.options.background.windowZoomLiveCapture
            onCheckedChanged: {
                Config.options.background.windowZoomLiveCapture = checked;
            }

            StyledToolTip {
                text: Translation.tr("When enabled, window previews stay live instead of freezing on overview open.\nDisable for better performance (freezes capture on open).")
            }

        }

    }

    ContentSection {
        title: Translation.tr("Media Mode Background")
        icon: "music_note"

        ConfigSwitch {
            buttonIcon: "animation"
            text: Translation.tr("Enable background animation")
            checked: Config.options.background.mediaMode.backgroundAnimation.enable
            onCheckedChanged: {
                Config.options.background.mediaMode.backgroundAnimation.enable = checked;
            }
        }

        ConfigSpinBox {
            enabled: Config.options.background.mediaMode.backgroundAnimation.enable
            icon: "speed"
            text: Translation.tr("Speed scale")
            value: Config.options.background.mediaMode.backgroundAnimation.speedScale
            from: 0
            to: 100
            stepSize: 5
            onValueChanged: {
                Config.options.background.mediaMode.backgroundAnimation.speedScale = value;
            }

            MouseArea {
                id: spinBoxMouseArea

                z: -1
                anchors.fill: parent
                hoverEnabled: true
            }

            StyledToolTip {
                extraVisibleCondition: spinBoxMouseArea.containsMouse
                text: Translation.tr("1: very slow | 10: default | 20: 2x speed...")
            }

        }

        ConfigSpinBox {
            icon: "opacity"
            text: Translation.tr("Background album art opacity (%)")
            value: Config.options.background.mediaMode.backgroundOpacity
            from: 0
            to: 100
            stepSize: 10
            onValueChanged: {
                Config.options.background.mediaMode.backgroundOpacity = value;
            }
        }

        ContentSubsection {
            title: Translation.tr("Background shape")
            icon: "category"
            Layout.fillWidth: true

            ConfigSelectionArray {
                currentValue: Config.options.background.mediaMode.backgroundShape
                onSelected: (newValue) => {
                    Config.options.background.mediaMode.backgroundShape = newValue;
                }
                options: (["Circle", "Square", "Slanted", "Arch", "Arrow", "SemiCircle", "Oval", "Pill", "Triangle", "Diamond", "ClamShell", "Pentagon", "Gem", "Sunny", "VerySunny", "Cookie4Sided", "Cookie6Sided", "Cookie7Sided", "Cookie9Sided", "Cookie12Sided", "Ghostish", "Clover4Leaf", "Clover8Leaf", "Burst", "SoftBurst", "Flower", "Puffy", "PuffyDiamond", "PixelCircle", "Bun", "Heart"]).map((icon) => {
                    return {
                        "displayName": "",
                        "shape": icon,
                        "value": icon
                    };
                })
            }

        }

        ConfigSwitch {
            buttonIcon: "format_color_fill"
            text: Translation.tr("Change shell color to match album art")
            checked: Config.options.background.mediaMode.changeShellColor
            onCheckedChanged: {
                Config.options.background.mediaMode.changeShellColor = checked;
            }
        }

        ContentSubsection {
            title: Translation.tr("Text highlight style")
            icon: "highlight"
            Layout.fillWidth: true

            ConfigSelectionArray {
                currentValue: Config.options.background.mediaMode.syllable.textHighlightStyle
                onSelected: (newValue) => {
                    Config.options.background.mediaMode.syllable.textHighlightStyle = newValue;
                }
                options: [{
                    "displayName": Translation.tr("Vertical"),
                    "icon": "vertical_distribute",
                    "value": 0
                }, {
                    "displayName": Translation.tr("Horizontal"),
                    "icon": "horizontal_distribute",
                    "value": 1
                }]
            }

        }

        ConfigSwitch {
            buttonIcon: "monitor"
            text: Translation.tr("Toggle per monitor")
            checked: Config.options.background.mediaMode.togglePerMonitor
            onCheckedChanged: {
                Config.options.background.mediaMode.togglePerMonitor = checked;
            }
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
            exec(["which", "linux-wallpaperengine"]);
        }
    }

    Process {
        id: runListWpeProc

        command: ["python3", Directories.scriptPath + "/colors/list_wpe_wallpapers.py"]
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0)
                wpeWallpapersFileView.reload();

        }
        Component.onCompleted: {
            exec(["python3", Directories.scriptPath + "/colors/list_wpe_wallpapers.py"]);
        }
    }

    FileView {
        id: wpeWallpapersFileView

        path: "file:///tmp/wpe_installed_wallpapers.json"
        onLoaded: {
            try {
                var raw = wpeWallpapersFileView.text().trim();
                if (raw === "")
                    return ;

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
                if (Config.options.background.useWallpaperEngine === checked)
                    return ;

                Config.options.background.useWallpaperEngine = checked;
                if (checked) {
                    if (Config.options.background.wallpaperEngineId)
                        Wallpapers.apply(Config.options.background.wallpaperEngineId);

                } else {
                    Quickshell.execDetached(["bash", "-c", "pkill -f linux-wallpaperengine; sleep 0.3; pkill -9 -f linux-wallpaperengine 2>/dev/null; true"]);
                }
            }
        }

        // Warning NoticeBox
        NoticeBox {
            Layout.fillWidth: true
            visible: Config.options.background.useWallpaperEngine
            materialIcon: "warning"
            text: "<b>" + Translation.tr("Experimental Feature!") + "</b><br>" + Translation.tr("Bugs and performance issues are expected. Not all features of the ii shell (such as background animations) are supported by the live Wallpaper Engine window, and it will consume significantly more CPU/GPU resources.")

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
            text: "<b>" + Translation.tr("How to Install & Use:") + "</b><br>" + Translation.tr("1. Clone/compile the engine from GitHub: Almamu/linux-wallpaperengine.<br>") + Translation.tr("2. Place outputs in <b>~/.local/lib/linux-wallpaperengine/</b>.<br>") + Translation.tr("3. Add wrapper at <b>~/.local/bin/linux-wallpaperengine</b> with <b>--no-sandbox</b>.<br>") + Translation.tr("4. Enter a Wallpaper Workshop ID (e.g., <b>2441947759</b>) below and enable.")
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
                if (Config.options.background.wallpaperEngineId === textField.text)
                    return ;

                Config.options.background.wallpaperEngineId = textField.text;
                if (Config.options.background.useWallpaperEngine && textField.text)
                    Wallpapers.apply(textField.text);

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
                    if (Config.options.background.wallpaperEngineId === newText)
                        return ;

                    Config.options.background.wallpaperEngineId = newText;
                    if (Config.options.background.useWallpaperEngine && newText)
                        Wallpapers.apply(newText);

                }

                StyledToolTip {
                    text: Translation.tr("Apply Wallpaper")
                }

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "play_arrow"
                    iconSize: 18
                    color: Appearance.colors.colOnPrimaryContainer
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
                if (Config.options.background.wallpaperEngineAssetsPath === textField.text)
                    return ;

                Config.options.background.wallpaperEngineAssetsPath = textField.text;
                if (Config.options.background.useWallpaperEngine && Config.options.background.wallpaperEngineId)
                    Wallpapers.apply(Config.options.background.wallpaperEngineId);

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
                        NumberAnimation {
                            duration: 300
                            easing.type: Easing.OutQuad
                        }

                    }

                    delegate: Rectangle {
                        id: presetItem

                        readonly property bool isActive: Config.options.background.wallpaperEngineId === model.id

                        width: 188
                        height: 148
                        radius: Appearance.rounding.large
                        color: Appearance.colors.colLayer0
                        border.color: isActive ? Appearance.colors.colPrimary : (presetButton.down ? Appearance.colors.colPrimaryActive : (presetButton.hovered ? Appearance.colors.colPrimaryHover : "transparent"))
                        border.width: 2
                        scale: presetButton.down ? 0.96 : (presetButton.hovered ? 1.02 : 1)

                        RippleButton {
                            id: presetButton

                            anchors.fill: parent
                            buttonRadius: Appearance.rounding.large
                            colBackground: "transparent"
                            colBackgroundHover: "transparent"
                            colRipple: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.8)
                            onClicked: {
                                if (Config.options.background.wallpaperEngineId === model.id)
                                    return ;

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
                                    source: model.preview ? "file://" + model.preview : ""
                                    fillMode: Image.PreserveAspectCrop
                                    playing: wpeGrid.visible
                                    layer.enabled: true

                                    layer.effect: OpacityMask {

                                        maskSource: Rectangle {
                                            width: previewImage.width
                                            height: previewImage.height
                                            radius: Appearance.rounding.normal
                                        }

                                    }

                                }

                                // Active Badge / Checkmark
                                Rectangle {
                                    width: 24
                                    height: 24
                                    radius: 12
                                    color: Appearance.colors.colPrimary
                                    visible: presetItem.isActive
                                    z: 5

                                    anchors {
                                        top: parent.top
                                        right: parent.right
                                        margins: 6
                                    }

                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "done"
                                        iconSize: 14
                                        color: Appearance.colors.colOnPrimary
                                    }

                                }

                                // Download Button — saves video/preview to ~/Pictures/Wallpapers
                                Rectangle {
                                    width: 26
                                    height: 26
                                    radius: 13
                                    color: Qt.rgba(0, 0, 0, 0.55)
                                    visible: presetButton.hovered && !downloadProc.running
                                    z: 5

                                    anchors {
                                        top: parent.top
                                        left: parent.left
                                        margins: 6
                                    }

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
                                    width: 26
                                    height: 26
                                    radius: 13
                                    color: Qt.rgba(0, 0, 0, 0.55)
                                    visible: downloadProc.running
                                    z: 5

                                    anchors {
                                        top: parent.top
                                        left: parent.left
                                        margins: 6
                                    }

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
                                    text: model.title
                                    color: Appearance.colors.colOnLayer1
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.weight: presetItem.isActive ? Font.Bold : Font.Normal
                                    elide: Text.ElideRight

                                    anchors {
                                        left: parent.left
                                        right: parent.right
                                        verticalCenter: parent.verticalCenter
                                        leftMargin: 4
                                        rightMargin: 4
                                    }

                                }

                            }

                        }

                        Behavior on border.color {
                            ColorAnimation {
                                duration: Appearance.animation.elementMoveFast.duration
                                easing.type: Appearance.animation.elementMoveFast.type
                                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                            }

                        }

                        Behavior on scale {
                            NumberAnimation {
                                duration: Appearance.animation.elementMoveFast.duration
                                easing.type: Appearance.animation.elementMoveFast.type
                                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                            }

                        }

                    }

                }

                // Left Arrow Floating Button
                RippleButton {
                    width: 40
                    height: 40
                    z: 10
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colLayer0
                    colBackgroundHover: Appearance.colors.colLayer0Hover
                    colRipple: Appearance.colors.colLayer0Active
                    visible: wpeGrid.contentX > 0
                    onClicked: {
                        wpeGrid.contentX = Math.max(0, wpeGrid.contentX - 400);
                    }

                    anchors {
                        left: parent.left
                        verticalCenter: parent.verticalCenter
                        leftMargin: -12
                    }

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "chevron_left"
                        iconSize: 24
                        color: Appearance.colors.colOnLayer0
                    }

                }

                // Right Arrow Floating Button
                RippleButton {
                    width: 40
                    height: 40
                    z: 10
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colLayer0
                    colBackgroundHover: Appearance.colors.colLayer0Hover
                    colRipple: Appearance.colors.colLayer0Active
                    visible: wpeGrid.contentWidth > wpeGrid.width && wpeGrid.contentX < wpeGrid.contentWidth - wpeGrid.width - 10
                    onClicked: {
                        wpeGrid.contentX = Math.min(wpeGrid.contentWidth - wpeGrid.width, wpeGrid.contentX + 400);
                    }

                    anchors {
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        rightMargin: -12
                    }

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "chevron_right"
                        iconSize: 24
                        color: Appearance.colors.colOnLayer0
                    }

                }

            }

        }

        // Performance & Behavior Settings
        ContentSubsection {
            visible: Config.options.background.useWallpaperEngine
            title: Translation.tr("Performance & Behavior")
            icon: "speed"
            Layout.fillWidth: true

            ConfigSwitch {
                buttonIcon: "pause_circle_outline"
                text: Translation.tr("Pause animations when windows are open")
                checked: Config.options.background.wpePauseWhenWindowsOpen
                onCheckedChanged: {
                    if (Config.options.background.wpePauseWhenWindowsOpen === checked)
                        return ;

                    Config.options.background.wpePauseWhenWindowsOpen = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "pause_circle"
                text: Translation.tr("No Fullscreen Pause")
                checked: Config.options.background.wpeNoFullscreenPause
                onCheckedChanged: {
                    if (Config.options.background.wpeNoFullscreenPause === checked)
                        return ;

                    Config.options.background.wpeNoFullscreenPause = checked;
                    if (Config.options.background.useWallpaperEngine && Config.options.background.wallpaperEngineId)
                        Wallpapers.apply(Config.options.background.wallpaperEngineId);

                }
            }

            ConfigSpinBox {
                icon: "speed"
                text: Translation.tr("Framerate Limit (FPS)")
                value: Config.options.background.wpeFps ?? 30
                from: 15
                to: 144
                stepSize: 5
                onValueChanged: {
                    if (Config.options.background.wpeFps === value)
                        return ;

                    Config.options.background.wpeFps = value;
                    if (Config.options.background.useWallpaperEngine && Config.options.background.wallpaperEngineId)
                        Wallpapers.apply(Config.options.background.wallpaperEngineId);

                }
            }

        }

        // Display & Interaction Settings
        ContentSubsection {
            visible: Config.options.background.useWallpaperEngine
            title: Translation.tr("Display & Interaction")
            icon: "monitor"
            Layout.fillWidth: true

            ConfigSwitch {
                buttonIcon: "mouse"
                text: Translation.tr("Disable Mouse Interaction")
                checked: Config.options.background.wpeDisableMouse
                onCheckedChanged: {
                    if (Config.options.background.wpeDisableMouse === checked)
                        return ;

                    Config.options.background.wpeDisableMouse = checked;
                    if (Config.options.background.useWallpaperEngine && Config.options.background.wallpaperEngineId)
                        Wallpapers.apply(Config.options.background.wallpaperEngineId);

                }
            }

            ConfigSwitch {
                buttonIcon: "blur_off"
                text: Translation.tr("Disable Parallax Effect")
                checked: Config.options.background.wpeDisableParallax
                onCheckedChanged: {
                    if (Config.options.background.wpeDisableParallax === checked)
                        return ;

                    Config.options.background.wpeDisableParallax = checked;
                    if (Config.options.background.useWallpaperEngine && Config.options.background.wallpaperEngineId)
                        Wallpapers.apply(Config.options.background.wallpaperEngineId);

                }
            }

            ConfigTextField {
                text: Translation.tr("Screen Span (e.g. HDMI-A-1,eDP-1)")
                icon: "settings_overscan"
                placeholderText: Translation.tr("Stretch single wallpaper across monitors (Optional)")
                inputText: Config.options.background.wpeScreenSpan
                textField.onEditingFinished: {
                    if (Config.options.background.wpeScreenSpan === textField.text)
                        return ;

                    Config.options.background.wpeScreenSpan = textField.text;
                    if (Config.options.background.useWallpaperEngine && Config.options.background.wallpaperEngineId)
                        Wallpapers.apply(Config.options.background.wallpaperEngineId);

                }
            }

            StyledText {
                text: Translation.tr("Wallpaper scaling")
                font.bold: true
                color: Appearance.colors.colOnLayer2
                Layout.leftMargin: 4
            }

            ConfigSelectionArray {
                currentValue: Config.options.background.wpeScaling ?? "default"
                onSelected: (newValue) => {
                    if (Config.options.background.wpeScaling === newValue)
                        return ;

                    Config.options.background.wpeScaling = newValue;
                    if (Config.options.background.useWallpaperEngine && Config.options.background.wallpaperEngineId)
                        Wallpapers.apply(Config.options.background.wallpaperEngineId);

                }
                options: [{
                    "displayName": Translation.tr("Default"),
                    "value": "default",
                    "icon": "select_all"
                }, {
                    "displayName": Translation.tr("Stretch"),
                    "value": "stretch",
                    "icon": "aspect_ratio"
                }, {
                    "displayName": Translation.tr("Fit"),
                    "value": "fit",
                    "icon": "fit_screen"
                }, {
                    "displayName": Translation.tr("Fill"),
                    "value": "fill",
                    "icon": "crop_free"
                }]
            }

        }

        // Silent mode toggle
        ConfigSwitch {
            buttonIcon: "volume_off"
            text: Translation.tr("Silent Mode")
            visible: Config.options.background.useWallpaperEngine
            checked: Config.options.background.wpeSilent
            onCheckedChanged: {
                if (Config.options.background.wpeSilent === checked)
                    return ;

                Config.options.background.wpeSilent = checked;
                if (Config.options.background.useWallpaperEngine && Config.options.background.wallpaperEngineId)
                    Wallpapers.apply(Config.options.background.wallpaperEngineId);

            }
        }

        // Audio Settings (hidden when Silent Mode is active)
        ContentSubsection {
            visible: Config.options.background.useWallpaperEngine && !Config.options.background.wpeSilent
            title: Translation.tr("Audio Settings")
            icon: "volume_up"
            Layout.fillWidth: true

            ConfigSlider {
                buttonIcon: "volume_down"
                text: Translation.tr("Volume Level")
                usePercentTooltip: true
                from: 0
                to: 100
                stepSize: 1
                value: Config.options.background.wpeVolume ?? 50
                onValueChanged: {
                    if (Config.options.background.wpeVolume === Math.round(value))
                        return ;

                    Config.options.background.wpeVolume = Math.round(value);
                    if (Config.options.background.useWallpaperEngine && Config.options.background.wallpaperEngineId)
                        Wallpapers.apply(Config.options.background.wallpaperEngineId);

                }
            }

            ConfigSwitch {
                buttonIcon: "music_off"
                text: Translation.tr("Don't Auto Mute")
                checked: Config.options.background.wpeNoAutoMute
                onCheckedChanged: {
                    if (Config.options.background.wpeNoAutoMute === checked)
                        return ;

                    Config.options.background.wpeNoAutoMute = checked;
                    if (Config.options.background.useWallpaperEngine && Config.options.background.wallpaperEngineId)
                        Wallpapers.apply(Config.options.background.wallpaperEngineId);

                }
            }

            ConfigSwitch {
                buttonIcon: "graphic_eq"
                text: Translation.tr("Disable Audio Reactive Features")
                checked: Config.options.background.wpeNoAudioProcessing
                onCheckedChanged: {
                    if (Config.options.background.wpeNoAudioProcessing === checked)
                        return ;

                    Config.options.background.wpeNoAudioProcessing = checked;
                    if (Config.options.background.useWallpaperEngine && Config.options.background.wallpaperEngineId)
                        Wallpapers.apply(Config.options.background.wallpaperEngineId);

                }
            }

        }

    }

    ContentSection {
        title: Translation.tr("Wallpaper Browser")
        icon: "download"

        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("Wallpaper Browser download path")
            text: Config.options.wallpapers.paths.download
            wrapMode: TextEdit.Wrap
            onTextChanged: {
                Config.options.wallpapers.paths.download = text;
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
