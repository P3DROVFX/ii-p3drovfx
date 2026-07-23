import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

ContentPage {
    id: pageRoot
    forceWidth: false

    property bool showRestartFab: false

    Connections {
        target: Config.options.appearance.palette
        function onTypeChanged() {
            pageRoot.showRestartFab = true;
        }
    }

    Connections {
        target: Appearance.m3colors
        function onDarkmodeChanged() {
            pageRoot.showRestartFab = true;
        }
    }

    FloatingActionButton {
        id: restartFab
        parent: pageRoot.parent
        anchors {
            right: parent ? parent.right : undefined
            bottom: parent ? parent.bottom : undefined
            margins: 30
        }
        z: 100
        iconText: "restart_alt"
        buttonText: Translation.tr("Restart Shell")
        expanded: false
        visible: opacity > 0
        opacity: pageRoot.showRestartFab ? 1 : 0
        scale: opacity

        Behavior on opacity {
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }

        colBackground: Appearance.colors.colTertiaryContainer
        colBackgroundHover: Appearance.colors.colTertiaryContainerHover
        colRipple: Appearance.colors.colTertiaryContainerActive
        colOnBackground: Appearance.colors.colOnTertiaryContainer

        onClicked: {
            Quickshell.execDetached(["bash", "-c", "qs kill -c ii && qs -c ii &"]);
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: restartFab.expanded = true
            onExited: restartFab.expanded = false
        }
    }

    ContentSection {
        title: Translation.tr("Appearance Preferences")
        icon: "palette"

        RowLayout {
            Layout.fillWidth: true

            ConfigWallpaperSelector {
                text: Translation.tr("Wallpaper Selector")
            }

            ColumnLayout {
                Layout.fillHeight: true
                Layout.fillWidth: true

                ConfigLightDarkToggle {
                    text: Translation.tr("Light / Dark Theme")
                }

                Item {
                    id: colorGridItem
                    z: 1
                    Layout.fillHeight: true
                    Layout.fillWidth: true

                    StyledFlickable {
                        id: flickable
                        anchors.fill: parent
                        contentHeight: contentLayout.implicitHeight
                        contentWidth: width
                        clip: true

                        ColumnLayout {
                            id: contentLayout
                            width: flickable.width

                            Repeater {
                                model: [
                                    {
                                        customTheme: false,
                                        builtInTheme: false
                                    },
                                    {
                                        customTheme: false,
                                        builtInTheme: true
                                    },
                                    {
                                        customTheme: true,
                                        builtInTheme: false
                                    }
                                ]

                                delegate: ColorPreviewGrid {
                                    customTheme: modelData.customTheme
                                    builtInTheme: modelData.builtInTheme
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    ContentSection {
        title: Translation.tr("Color Engine")
        icon: "science"

        ContentSubsection {
            title: Translation.tr("Color generation mode")
            icon: "settings_brightness"
            tooltip: Translation.tr("ii-vynx: uses the original switchwall pipeline.\n\nFork: uses the fork's color generation pipeline, use this if vynx doesn't work.")
            Layout.fillWidth: true

            ConfigSelectionArray {
                currentValue: Config.options.appearance.colorEngine ?? "vynx"
                onSelected: newValue => {
                    Config.options.appearance.colorEngine = newValue;
                }
                options: [
                    {
                        displayName: Translation.tr("ii-vynx"),
                        value: "vynx",
                        icon: "verified"
                    },
                    {
                        displayName: Translation.tr("Fork"),
                        value: "fork",
                        icon: "build"
                    }
                ]
            }
        }
    }

    ContentSection {
        icon: "nightlight"
        title: Translation.tr("Scheduling (Dark Mode & Night Light)")

        ConfigSwitch {
            buttonIcon: "dark_mode"
            text: Translation.tr("Automatic Dark Mode")
            checked: Config.options.light.darkMode.automatic
            onCheckedChanged: {
                Config.options.light.darkMode.automatic = checked;
            }
        }

        MaterialTextArea {
            enabled: Config.options.light.darkMode.automatic
            Layout.fillWidth: true
            placeholderText: Translation.tr("Dark Mode start time (e.g. 18:00)")
            text: Config.options.light.darkMode.from
            wrapMode: TextEdit.NoWrap
            onTextChanged: {
                Config.options.light.darkMode.from = text;
            }
        }

        MaterialTextArea {
            enabled: Config.options.light.darkMode.automatic
            Layout.fillWidth: true
            placeholderText: Translation.tr("Dark Mode end time (e.g. 06:00)")
            text: Config.options.light.darkMode.to
            wrapMode: TextEdit.NoWrap
            onTextChanged: {
                Config.options.light.darkMode.to = text;
            }
        }

        ConfigSwitch {
            buttonIcon: "nightlight_round"
            text: Translation.tr("Automatic Night Light")
            checked: Config.options.light.night.automatic
            onCheckedChanged: {
                Config.options.light.night.automatic = checked;
            }
        }

        MaterialTextArea {
            enabled: Config.options.light.night.automatic
            Layout.fillWidth: true
            placeholderText: Translation.tr("Night Light start time (e.g. 19:00)")
            text: Config.options.light.night.from
            wrapMode: TextEdit.NoWrap
            onTextChanged: {
                Config.options.light.night.from = text;
            }
        }

        MaterialTextArea {
            enabled: Config.options.light.night.automatic
            Layout.fillWidth: true
            placeholderText: Translation.tr("Night Light end time (e.g. 06:00)")
            text: Config.options.light.night.to
            wrapMode: TextEdit.NoWrap
            onTextChanged: {
                Config.options.light.night.to = text;
            }
        }

        ConfigSlider {
            buttonIcon: "wb_twilight"
            text: Translation.tr("Night Light Color Temperature")
            usePercentTooltip: false
            from: 1000
            to: 10000
            stepSize: 100
            value: Config.options.light.night.colorTemperature ?? 5000
            onValueChanged: {
                Config.options.light.night.colorTemperature = Math.round(value);
            }
        }

        ConfigSwitch {
            buttonIcon: "flash_off"
            text: Translation.tr("Anti-flashbang light filter")
            checked: Config.options.light.antiFlashbang.enable
            onCheckedChanged: {
                Config.options.light.antiFlashbang.enable = checked;
            }
        }
    }

    ContentSection {
        title: Translation.tr("Wallpaper Theming & Matugen Integration")
        icon: "wallpaper"

        ConfigSwitch {
            buttonIcon: "desktop_windows"
            text: Translation.tr("Shell & utilities")
            checked: Config.options.appearance.wallpaperTheming.enableAppsAndShell
            onCheckedChanged: {
                Config.options.appearance.wallpaperTheming.enableAppsAndShell = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "widgets"
            text: Translation.tr("Qt apps")
            checked: Config.options.appearance.wallpaperTheming.enableQtApps
            onCheckedChanged: {
                Config.options.appearance.wallpaperTheming.enableQtApps = checked;
            }
            StyledToolTip {
                text: Translation.tr("Shell & utilities theming must also be enabled")
            }
        }

        ConfigSwitch {
            buttonIcon: "terminal"
            text: Translation.tr("Terminal")
            checked: Config.options.appearance.wallpaperTheming.enableTerminal
            onCheckedChanged: {
                Config.options.appearance.wallpaperTheming.enableTerminal = checked;
            }
            StyledToolTip {
                text: Translation.tr("Shell & utilities theming must also be enabled")
            }
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

        ConfigSwitch {
            buttonIcon: "lock"
            text: Translation.tr("Separate Lockscreen Wallpaper")
            checked: Config.options.background.useSeparateLockscreenWallpaper
            onCheckedChanged: {
                Config.options.background.useSeparateLockscreenWallpaper = checked;
                if (checked && !Config.options.background.lockscreenWallpaperPath) {
                    Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "wallpaperSelector", "toggleLockscreen"]);
                }
            }
            StyledToolTip {
                text: Translation.tr("Use a different wallpaper on the lockscreen with custom Matugen color scheme transition")
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: Config.options.background.useSeparateLockscreenWallpaper

            ConfigWallpaperSelector {
                targetMode: "lockscreen"
                text: Translation.tr("Lockscreen Wallpaper Selector")
            }

            ColumnLayout {
                Layout.fillHeight: true
                Layout.fillWidth: true
                spacing: 8

                RippleButtonWithIcon {
                    useDynamicRadius: true
                    Layout.fillWidth: true
                    materialIcon: "wallpaper"
                    mainText: Translation.tr("Select Lockscreen Wallpaper")
                    onClicked: {
                        Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "wallpaperSelector", "toggleLockscreen"]);
                    }
                }

                RippleButtonWithIcon {
                    useDynamicRadius: true
                    Layout.fillWidth: true
                    materialIcon: "swap_horiz"
                    mainText: Translation.tr("Swap Desktop & Lockscreen Wallpapers")
                    onClicked: {
                        const desktopWall = Config.options.background.wallpaperPath;
                        const lockWall = Config.options.background.lockscreenWallpaperPath;
                        if (desktopWall && lockWall) {
                            Config.options.background.wallpaperPath = lockWall;
                            Wallpapers.applyLockscreen(desktopWall);
                            Wallpapers.apply(lockWall);
                        }
                    }
                }
            }
        }

        ConfigSwitch {
            buttonIcon: "palette"
            text: Translation.tr("OpenRGB integration")
            checked: Config.options.appearance.openrgb.enable
            onCheckedChanged: {
                Config.options.appearance.openrgb.enable = checked;
            }
        }
    }
    ContentSection {
        id: openRgbSection
        title: Translation.tr("Open RGB integration")
        icon: "palette"
        visible: Config.options.appearance.openrgb.enable

        property var openRgbConfig: ({
            enable: false,
            applyOnStartup: false,
            devices: []
        })
        property var openRgbDevices: []
        property string openRgbListScript: FileUtils.trimFileProtocol(`${Directories.scriptPath}/colors/openrgb-list-devices.sh`)
        property string openRgbError: ""
        property bool openRgbRefreshing: false

        function defaultOpenRgbConfig() {
            return {
                enable: false,
                applyOnStartup: true,
                devices: []
            };
        }

        function refreshOpenRgbConfig() {
            const appearance = JSON.parse(JSON.stringify(Config.options.appearance || {}));
            openRgbConfig = Object.assign(defaultOpenRgbConfig(), appearance.openrgb || {});
            openRgbDevices = openRgbConfig.devices || [];
        }

        function updateDevice(deviceId, patch) {
            const devices = [...(openRgbDevices || [])];
            const index = devices.findIndex(device => device.id === deviceId);
            if (index === -1) {
                devices.push(Object.assign({
                    id: deviceId,
                    name: patch.name ?? "",
                    enabled: patch.enabled ?? false
                }, patch));
            } else {
                devices[index] = Object.assign({}, devices[index], patch);
            }
            openRgbDevices = devices;
            openRgbConfig.devices = devices;
            Config.setNestedValue("appearance.openrgb.devices", devices);
        }

        function refreshDevices() {
            openRgbError = "";
            openRgbRefreshing = true;
            openRgbDeviceProc.command = ["bash", openRgbListScript];
            openRgbDeviceProc.running = false;
            openRgbDeviceProc.running = true;
        }

        Component.onCompleted: refreshOpenRgbConfig()

        Connections {
            target: Config
            function onReadyChanged() {
                if (Config.ready)
                    openRgbSection.refreshOpenRgbConfig();
            }
        }

        Process {
            id: openRgbDeviceProc
            stdout: StdioCollector {
                onStreamFinished: {
                    openRgbRefreshing = false;
                    if (text.length === 0) {
                        openRgbError = Translation.tr("OpenRGB did not return any data.");
                        return;
                    }
                    try {
                        const payload = JSON.parse(text);
                        if (!payload.ok) {
                            openRgbError = payload.error || Translation.tr("Failed to query OpenRGB devices.");
                            return;
                        }
                        const devices = payload.devices || [];
                        const existing = openRgbDevices || [];
                        const merged = devices.map(device => {
                            const match = existing.find(prev => prev.id === device.id);
                            return {
                                id: device.id,
                                name: device.name,
                                enabled: match ? match.enabled : false
                            };
                        });
                        Config.options.appearance.openrgb.devices = merged;
                        openRgbSection.refreshOpenRgbConfig();
                    } catch (e) {
                        openRgbError = Translation.tr("Failed to parse OpenRGB response.");
                    }
                }
            }
            stderr: StdioCollector {
                onStreamFinished: {
                    openRgbRefreshing = false;
                    const trimmed = text.trim();
                    if (trimmed.length > 0) {
                        openRgbError = trimmed;
                    }
                }
            }
        }

        RippleButtonWithIcon {
            id: openRgbRefreshButton
            useDynamicRadius: true
            Layout.fillWidth: true
            materialIcon: "refresh"
            mainText: openRgbSection.openRgbRefreshing ? Translation.tr("Refreshing...") : Translation.tr("Refresh devices")
            enabled: !openRgbSection.openRgbRefreshing
            onClicked: {
                openRgbSection.refreshDevices();
            }
        }

        NoticeBox {
            id: openRgbErrorBox
            Layout.fillWidth: true
            visible: openRgbSection.openRgbError.length > 0
            materialIcon: "error"
            text: openRgbSection.openRgbError
        }

        ContentSubsectionLabel {
            text: Translation.tr("Detected Devices")
            visible: openRgbSection.openRgbRefreshing || (openRgbSection.openRgbDevices || []).length > 0
        }

        StyledText {
            visible: openRgbSection.openRgbRefreshing
            text: Translation.tr("Querying OpenRGB server...")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colOnLayer2
            Layout.margins: 8
        }

        Repeater {
            model: openRgbSection.openRgbDevices || []
            ConfigSwitch {
                required property var modelData
                required property int index
                buttonIcon: "memory"
                text: modelData.name && modelData.name.length > 0 ? modelData.name : Translation.tr("Device %1").arg(modelData.id)
                checked: modelData.enabled === true
                onCheckedChanged: {
                    openRgbSection.updateDevice(modelData.id, {
                        enabled: checked,
                        name: modelData.name
                    });
                }
            }
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: (openRgbSection.openRgbDevices || []).length === 0 && !openRgbSection.openRgbRefreshing && openRgbSection.openRgbError.length === 0
            materialIcon: "warning"
            text: Translation.tr("No OpenRGB devices detected. Ensure the server is running.")
        }

        ContentSubsectionLabel {
            text: Translation.tr("Integration Settings")
        }

        ConfigSpinBox {
            icon: "av_timer"
            text: Translation.tr("Fade duration (ms)")
            value: Config.options.appearance.openrgb.fadeDuration * 1000
            from: 0
            to: 10000
            stepSize: 100
            onValueChanged: {
                Config.options.appearance.openrgb.fadeDuration = value / 1000;
            }
        }

        ConfigSwitch {
            buttonIcon: "power_settings_new"
            text: Translation.tr("Apply on startup")
            checked: Config.options.appearance.openrgb.applyOnStartup
            onCheckedChanged: {
                Config.options.appearance.openrgb.applyOnStartup = checked;
            }
            StyledToolTip {
                text: Translation.tr("Runs the OpenRGB apply script after startup once config is loaded.")
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
            if (exitCode === 0) {
                wpeWallpapersFileView.reload();
            }
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
                if (checked) {
                    if (Config.options.background.wallpaperEngineId) {
                        Wallpapers.apply(Config.options.background.wallpaperEngineId);
                    }
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
}
