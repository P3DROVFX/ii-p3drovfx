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
        title: Translation.tr("Theme")
        icon: "palette"

        ConfigLightDarkToggle {
            Layout.fillWidth: true
            text: Translation.tr("Light / Dark Theme")
        }

        ColumnLayout {
            Layout.fillWidth: true

            ColumnLayout {
                Layout.fillWidth: true

                Item {
                    id: colorGridItem
                    z: 1
                    // No fillHeight source since the wallpaper selector moved out;
                    // size to content and cap so the flickable still scrolls.
                    Layout.preferredHeight: Math.min(contentLayout.implicitHeight, 420)
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
        title: Translation.tr("Night Light")

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
        title: Translation.tr("App theming")
        icon: "format_paint"

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

        ContentSubsection {
            title: Translation.tr("Terminal colors")
            icon: "terminal"
            Layout.fillWidth: true

            ConfigSwitch {
                buttonIcon: "dark_mode"
                text: Translation.tr("Force dark mode in terminal")
                checked: Config.options.appearance.wallpaperTheming.terminalGenerationProps.forceDarkMode
                onCheckedChanged: {
                    Config.options.appearance.wallpaperTheming.terminalGenerationProps.forceDarkMode = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Ignored if terminal theming is not enabled above")
                }
            }

            ConfigSpinBox {
                icon: "contrast"
                text: Translation.tr("Terminal: Harmony %")
                value: Config.options.appearance.wallpaperTheming.terminalGenerationProps.harmony * 100
                from: 0
                to: 100
                stepSize: 1
                onValueChanged: {
                    Config.options.appearance.wallpaperTheming.terminalGenerationProps.harmony = value / 100;
                }
            }

            ConfigSpinBox {
                icon: "tune"
                text: Translation.tr("Terminal: Harmonize threshold")
                value: Config.options.appearance.wallpaperTheming.terminalGenerationProps.harmonizeThreshold
                from: 0
                to: 100
                stepSize: 1
                onValueChanged: {
                    Config.options.appearance.wallpaperTheming.terminalGenerationProps.harmonizeThreshold = value;
                }
            }

            ConfigSpinBox {
                icon: "brightness_high"
                text: Translation.tr("Terminal: Foreground boost %")
                value: Config.options.appearance.wallpaperTheming.terminalGenerationProps.termFgBoost * 100
                from: 0
                to: 100
                stepSize: 1
                onValueChanged: {
                    Config.options.appearance.wallpaperTheming.terminalGenerationProps.termFgBoost = value / 100;
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
        title: Translation.tr("Device lighting (OpenRGB)")
        icon: "lightbulb"
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

        ContentSubsection {
            title: Translation.tr("Detected Devices")
            icon: "memory"
            visible: openRgbSection.openRgbRefreshing || (openRgbSection.openRgbDevices || []).length > 0

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
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: (openRgbSection.openRgbDevices || []).length === 0 && !openRgbSection.openRgbRefreshing && openRgbSection.openRgbError.length === 0
            materialIcon: "warning"
            text: Translation.tr("No OpenRGB devices detected. Ensure the server is running.")
        }

        ContentSubsection {
            title: Translation.tr("Integration Settings")
            icon: "settings"

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
    }


    ContentSection {
        icon: "link"
        title: Translation.tr("Related settings")

        Flow {
            Layout.fillWidth: true
            spacing: 8

            RelatedChip {
                pageId: "displays"
                label: Translation.tr("Displays")
            }
        }
    }
}
