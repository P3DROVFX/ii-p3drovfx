pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
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

    function detectDistroKey(value: string): string {
        const distro = String(value || "").toLowerCase();
        if (["fedora", "rhel", "centos", "rocky", "almalinux"].indexOf(distro) >= 0)
            return "fedora";
        if (["arch", "artix", "manjaro", "endeavouros", "cachyos"].indexOf(distro) >= 0)
            return "arch";
        if (["debian", "ubuntu", "linuxmint", "pop", "popos", "zorin", "elementary", "kali", "raspbian"].indexOf(distro) >= 0)
            return "ubuntu";
        if (["opensuse", "opensuse-leap", "opensuse-tumbleweed", "sles"].indexOf(distro) >= 0)
            return "opensuse";
        if (["gentoo", "funtoo"].indexOf(distro) >= 0)
            return "gentoo";
        if (distro === "nixos")
            return "nixos";
        if (distro === "void")
            return "void";
        return "generic";
    }

    property string selectedDistro: detectDistroKey(SystemInfo.distroId)

    readonly property var distroOptions: [
        { displayName: Translation.tr("Fedora / RHEL"), value: "fedora" },
        { displayName: Translation.tr("Arch Linux"), value: "arch" },
        { displayName: Translation.tr("Debian / Ubuntu"), value: "ubuntu" },
        { displayName: Translation.tr("openSUSE"), value: "opensuse" },
        { displayName: Translation.tr("Gentoo"), value: "gentoo" },
        { displayName: Translation.tr("NixOS"), value: "nixos" },
        { displayName: Translation.tr("Void Linux"), value: "void" },
        { displayName: Translation.tr("Generic Linux"), value: "generic" }
    ]

    function openrgbPkgCommandFor(key: string): string {
        switch (key) {
            case "fedora":
                return "sudo dnf install -y openrgb openrgb-udev-rules";
            case "arch":
                return "sudo pacman -S --needed openrgb";
            case "ubuntu":
                return "sudo add-apt-repository -y ppa:thopiekar/openrgb && sudo apt update && sudo apt install -y openrgb";
            case "opensuse":
                return "sudo zypper install openrgb";
            case "gentoo":
                return "sudo emerge --ask app-misc/openrgb";
            case "nixos":
                return "# Add to your /etc/nixos/configuration.nix:\nservices.hardware.openrgb.enable = true;\n# Then rebuild: sudo nixos-rebuild switch";
            case "void":
                return "sudo xbps-install -S openrgb";
            default:
                return "# Install OpenRGB package from your distribution package manager\n# or download the AppImage/tarball from https://openrgb.org/";
        }
    }

    function pythonPkgCommandFor(key: string): string {
        switch (key) {
            case "fedora":
                return "sudo dnf install -y python3-scipy && pip install --user openrgb-python";
            case "arch":
                return "sudo pacman -S --needed python-openrgb python-scipy";
            case "ubuntu":
                return "sudo apt install -y python3-scipy && pip install --user openrgb-python --break-system-packages";
            case "opensuse":
                return "sudo zypper install -y python3-scipy && pip install --user openrgb-python";
            case "gentoo":
                return "sudo emerge --ask dev-python/scipy && pip install --user openrgb-python";
            case "nixos":
                return "nix-shell -p python3Packages.scipy python3Packages.openrgb-python";
            default:
                return "pip install --user openrgb-python scipy";
        }
    }

    function serverStartCommandFor(key: string): string {
        return "openrgb --server --startminimized";
    }

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
                text: Translation.tr("OpenRGB integration")
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                color: Appearance.colors.colOnLayer0
            }
        }

        // ── Main Section ─────────────────────────────────────────────────────────
        ContentSection {
            id: openRgbSection
            title: Translation.tr("OpenRGB Integration")
            icon: "palette"

            property var openRgbConfig: ({
                enable: false,
                applyOnStartup: true,
                fadeDuration: 0.5,
                devices: []
            })
            property var openRgbDevices: []
            property string openRgbListScript: FileUtils.trimFileProtocol(`${Directories.scriptPath}/colors/openrgb-list-devices.sh`)
            property string openRgbError: ""
            property bool openRgbRefreshing: false
            property bool binaryInstalled: false
            property bool pythonModuleInstalled: false
            property bool serverRunning: false
            property bool statusChecked: false

            function defaultOpenRgbConfig() {
                return {
                    enable: false,
                    applyOnStartup: true,
                    fadeDuration: 0.5,
                    devices: []
                };
            }

            function refreshOpenRgbConfig() {
                const openrgb = Config.options.appearance && Config.options.appearance.openrgb ? Config.options.appearance.openrgb : null;
                openRgbConfig = Object.assign(defaultOpenRgbConfig(), openrgb || {});
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

            Component.onCompleted: {
                refreshOpenRgbConfig();
                refreshDevices();
            }

            Connections {
                target: Config
                function onReadyChanged() {
                    if (Config.ready) {
                        openRgbSection.refreshOpenRgbConfig();
                    }
                }
            }

            Process {
                id: openRgbDeviceProc
                stdout: StdioCollector {
                    onStreamFinished: {
                        openRgbSection.openRgbRefreshing = false;
                        openRgbSection.statusChecked = true;
                        if (text.length === 0) {
                            openRgbSection.openRgbError = Translation.tr("OpenRGB did not return any data.");
                            return;
                        }
                        try {
                            const payload = JSON.parse(text);
                            openRgbSection.binaryInstalled = payload.binaryInstalled === true;
                            openRgbSection.pythonModuleInstalled = payload.pythonModuleInstalled === true;
                            openRgbSection.serverRunning = payload.serverRunning === true;

                            if (!payload.ok && payload.error) {
                                openRgbSection.openRgbError = payload.error;
                            }

                            const devices = payload.devices || [];
                            const existing = openRgbSection.openRgbDevices || [];
                            const merged = devices.map(device => {
                                const match = existing.find(prev => prev.id === device.id);
                                return {
                                    id: device.id,
                                    name: device.name,
                                    enabled: match ? match.enabled : false
                                };
                            });
                            Config.setNestedValue("appearance.openrgb.devices", merged);
                            openRgbSection.refreshOpenRgbConfig();
                        } catch (e) {
                            openRgbSection.openRgbError = Translation.tr("Failed to parse OpenRGB response.");
                        }
                    }
                }
                stderr: StdioCollector {
                    onStreamFinished: {
                        openRgbSection.openRgbRefreshing = false;
                        const trimmed = text.trim();
                        if (trimmed.length > 0) {
                            openRgbSection.openRgbError = trimmed;
                        }
                    }
                }
            }

            // ── Master Switch ──
            ConfigSwitch {
                buttonIcon: "palette"
                text: Translation.tr("Enable OpenRGB color synchronization")
                checked: Config.options.appearance.openrgb.enable
                onCheckedChanged: {
                    Config.options.appearance.openrgb.enable = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Synchronize RGB hardware colors with Material You wallpaper palette")
                }
            }

            // ── Real-Time Status Card (Harmonic Material You Design) ──
            Rectangle {
                id: statusCard
                Layout.fillWidth: true
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer1
                implicitHeight: cardLayout.implicitHeight + Appearance.font.pixelSize.large

                readonly property bool isReady: openRgbSection.binaryInstalled && openRgbSection.pythonModuleInstalled && openRgbSection.serverRunning
                readonly property bool hasDevices: (openRgbSection.openRgbDevices || []).length > 0
                readonly property bool isEnabled: Config.options.appearance && Config.options.appearance.openrgb && Config.options.appearance.openrgb.enable

                readonly property string statusText: {
                    if (!isEnabled)
                        return Translation.tr("Integration disabled");
                    if (openRgbSection.openRgbRefreshing)
                        return Translation.tr("Checking…");
                    if (isReady && hasDevices)
                        return Translation.tr("Ready · %1 device(s)").arg(String(openRgbSection.openRgbDevices.length));
                    if (isReady)
                        return Translation.tr("Ready · No devices");
                    if (!openRgbSection.binaryInstalled)
                        return Translation.tr("OpenRGB not installed");
                    if (!openRgbSection.pythonModuleInstalled)
                        return Translation.tr("Python client missing");
                    if (!openRgbSection.serverRunning)
                        return Translation.tr("Server stopped");
                    return Translation.tr("Setup required");
                }

                readonly property string detailText: {
                    if (!isEnabled)
                        return Translation.tr("Enable the switch above to synchronize RGB lighting with your Material You wallpaper theme.");
                    if (isReady && hasDevices)
                        return Translation.tr("Connected to OpenRGB SDK server. Hardware colors are ready to synchronize.");
                    if (isReady)
                        return Translation.tr("OpenRGB server is running, but no compatible RGB devices were found. Ensure devices are supported and connected.");
                    if (!openRgbSection.binaryInstalled)
                        return Translation.tr("The OpenRGB application is not installed. Follow the manual installation guide below.");
                    if (!openRgbSection.pythonModuleInstalled)
                        return Translation.tr("The python client library (openrgb-python / scipy) is missing. Run the installation command below.");
                    if (!openRgbSection.serverRunning)
                        return Translation.tr("OpenRGB is installed but the SDK server is not running. Start it with the command below or in the OpenRGB app.");
                    return Translation.tr("Follow the installation steps below to configure OpenRGB on your system.");
                }

                ColumnLayout {
                    id: cardLayout
                    anchors.fill: parent
                    anchors.margins: Appearance.font.pixelSize.small
                    spacing: Appearance.font.pixelSize.small

                    // Header Row
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Appearance.font.pixelSize.smallest

                        MaterialShapeWrappedMaterialSymbol {
                            text: "palette"
                            iconSize: Appearance.font.pixelSize.large
                            padding: Appearance.font.pixelSize.smallest
                            shape: (statusCard.isReady && statusCard.hasDevices) ? MaterialShape.Shape.Clover4Leaf : MaterialShape.Shape.Cookie7Sided
                            color: (statusCard.isReady && statusCard.hasDevices) ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSecondaryContainer
                            colSymbol: (statusCard.isReady && statusCard.hasDevices) ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSecondaryContainer
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("OpenRGB Status")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer1
                            elide: Text.ElideRight
                        }

                        Rectangle {
                            implicitWidth: statusPillText.implicitWidth + Appearance.font.pixelSize.normal
                            implicitHeight: statusPillText.implicitHeight + Appearance.font.pixelSize.smallest
                            radius: Appearance.rounding.full
                            color: (statusCard.isReady && statusCard.hasDevices) ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSecondaryContainer

                            StyledText {
                                id: statusPillText
                                anchors.centerIn: parent
                                text: statusCard.statusText
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.DemiBold
                                color: (statusCard.isReady && statusCard.hasDevices) ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSecondaryContainer
                            }
                        }
                    }

                    // Detail text & Recheck button
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Appearance.font.pixelSize.smallest

                        StyledText {
                            Layout.fillWidth: true
                            text: statusCard.detailText
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                            wrapMode: Text.Wrap
                        }

                        RippleButtonWithIcon {
                            implicitHeight: 36
                            centerContent: true
                            materialIcon: openRgbSection.openRgbRefreshing ? "progress_activity" : "refresh"
                            mainText: openRgbSection.openRgbRefreshing ? Translation.tr("Checking…") : Translation.tr("Recheck")
                            enabled: !openRgbSection.openRgbRefreshing
                            colText: Appearance.colors.colOnPrimaryContainer
                            colBackground: Appearance.colors.colPrimaryContainer
                            colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                            colRipple: Appearance.colors.colPrimaryContainerActive
                            onClicked: openRgbSection.refreshDevices()
                        }
                    }

                    // Requirements Pills
                    Flow {
                        Layout.fillWidth: true
                        spacing: 8

                        Rectangle {
                            radius: Appearance.rounding.full
                            color: Appearance.colors.colLayer2
                            implicitWidth: chip1Row.implicitWidth + 16
                            implicitHeight: 28

                            RowLayout {
                                id: chip1Row
                                anchors.centerIn: parent
                                spacing: 6

                                MaterialSymbol {
                                    text: openRgbSection.binaryInstalled ? "check_circle" : "radio_button_unchecked"
                                    iconSize: 14
                                    color: openRgbSection.binaryInstalled ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                                }

                                StyledText {
                                    text: Translation.tr("OpenRGB Daemon")
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: openRgbSection.binaryInstalled ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
                                }
                            }
                        }

                        Rectangle {
                            radius: Appearance.rounding.full
                            color: Appearance.colors.colLayer2
                            implicitWidth: chip2Row.implicitWidth + 16
                            implicitHeight: 28

                            RowLayout {
                                id: chip2Row
                                anchors.centerIn: parent
                                spacing: 6

                                MaterialSymbol {
                                    text: openRgbSection.pythonModuleInstalled ? "check_circle" : "radio_button_unchecked"
                                    iconSize: 14
                                    color: openRgbSection.pythonModuleInstalled ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                                }

                                StyledText {
                                    text: Translation.tr("Python Libraries")
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: openRgbSection.pythonModuleInstalled ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
                                }
                            }
                        }

                        Rectangle {
                            radius: Appearance.rounding.full
                            color: Appearance.colors.colLayer2
                            implicitWidth: chip3Row.implicitWidth + 16
                            implicitHeight: 28

                            RowLayout {
                                id: chip3Row
                                anchors.centerIn: parent
                                spacing: 6

                                MaterialSymbol {
                                    text: openRgbSection.serverRunning ? "check_circle" : "radio_button_unchecked"
                                    iconSize: 14
                                    color: openRgbSection.serverRunning ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                                }

                                StyledText {
                                    text: Translation.tr("SDK Server")
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: openRgbSection.serverRunning ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
                                }
                            }
                        }

                        Rectangle {
                            radius: Appearance.rounding.full
                            color: Appearance.colors.colLayer2
                            implicitWidth: chip4Row.implicitWidth + 16
                            implicitHeight: 28

                            RowLayout {
                                id: chip4Row
                                anchors.centerIn: parent
                                spacing: 6

                                MaterialSymbol {
                                    text: (openRgbSection.openRgbDevices || []).length > 0 ? "check_circle" : "radio_button_unchecked"
                                    iconSize: 14
                                    color: (openRgbSection.openRgbDevices || []).length > 0 ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                                }

                                StyledText {
                                    text: (openRgbSection.openRgbDevices || []).length > 0
                                        ? Translation.tr("%1 Devices").arg(String(openRgbSection.openRgbDevices.length))
                                        : Translation.tr("No Devices")
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: (openRgbSection.openRgbDevices || []).length > 0 ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── Manual Installation Guide ─────────────────────────────────────────────
        ContentSection {
            title: Translation.tr("Manual Installation Guide")
            icon: "menu_book"
            tooltip: Translation.tr("Step-by-step instructions to install and configure OpenRGB on your distribution.")

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("OpenRGB is an optional integration. To use it, install the OpenRGB daemon and python libraries for your Linux distribution, then start the OpenRGB SDK server:")
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }

            ContentSubsection {
                title: Translation.tr("Select Distribution")
                icon: "desktop_windows"
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: subPageRoot.selectedDistro
                    onSelected: function(newValue) {
                        subPageRoot.selectedDistro = newValue;
                    }
                    options: subPageRoot.distroOptions
                }
            }

            // Step 1: OpenRGB Package
            HelperCodeBox {
                Layout.fillWidth: true
                Layout.topMargin: 4
                topLeftRadius: Appearance.rounding.large
                topRightRadius: Appearance.rounding.large
                bottomLeftRadius: Appearance.rounding.large
                bottomRightRadius: Appearance.rounding.large
                icon: "download"
                title: Translation.tr("1. Install OpenRGB & udev rules")
                text: Translation.tr("Installs the OpenRGB application and udev rules for non-root hardware access. Run this in your terminal:")
                codeSnippet: subPageRoot.openrgbPkgCommandFor(subPageRoot.selectedDistro)
                snippetWrapMode: Text.Wrap
            }

            // Step 2: Python Libraries
            HelperCodeBox {
                Layout.fillWidth: true
                Layout.topMargin: 4
                topLeftRadius: Appearance.rounding.large
                topRightRadius: Appearance.rounding.large
                bottomLeftRadius: Appearance.rounding.large
                bottomRightRadius: Appearance.rounding.large
                icon: "terminal"
                title: Translation.tr("2. Install Python Dependencies")
                text: Translation.tr("Installs the Python OpenRGB client and scipy interpolation library used to smoothly transition RGB colors:")
                codeSnippet: subPageRoot.pythonPkgCommandFor(subPageRoot.selectedDistro)
                snippetWrapMode: Text.Wrap
            }

            // Step 3: Server daemon
            HelperCodeBox {
                Layout.fillWidth: true
                Layout.topMargin: 4
                topLeftRadius: Appearance.rounding.large
                topRightRadius: Appearance.rounding.large
                bottomLeftRadius: Appearance.rounding.large
                bottomRightRadius: Appearance.rounding.large
                icon: "play_arrow"
                title: Translation.tr("3. Start OpenRGB SDK Server")
                text: Translation.tr("Start OpenRGB with the background SDK server active (or enable 'Start Server' in the OpenRGB GUI settings):")
                codeSnippet: subPageRoot.serverStartCommandFor(subPageRoot.selectedDistro)
                snippetWrapMode: Text.Wrap
            }

            HelperCodeBox {
                Layout.fillWidth: true
                Layout.topMargin: 4
                topLeftRadius: Appearance.rounding.large
                topRightRadius: Appearance.rounding.large
                bottomLeftRadius: Appearance.rounding.large
                bottomRightRadius: Appearance.rounding.large
                icon: "security"
                title: Translation.tr("Hardware Access Permissions (udev)")
                text: Translation.tr("If OpenRGB does not detect your motherboard, RAM or USB devices, reload udev rules and re-plug USB devices:")
                codeSnippet: "sudo udevadm control --reload-rules && sudo udevadm trigger"
                snippetWrapMode: Text.Wrap
            }
        }

        // ── Detected Devices ─────────────────────────────────────────────────────
        ContentSection {
            title: Translation.tr("Detected Devices")
            icon: "memory"
            tooltip: Translation.tr("Toggle which detected RGB hardware components will synchronize colors.")

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
                    text: modelData.name && modelData.name.length > 0 ? modelData.name : Translation.tr("Device %1").arg(String(modelData.id))
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
                visible: (openRgbSection.openRgbDevices || []).length === 0 && !openRgbSection.openRgbRefreshing
                materialIcon: "info"
                text: Translation.tr("No OpenRGB devices detected. Ensure OpenRGB server is running and devices are detected by OpenRGB.")
            }
        }

        // ── Integration Settings ─────────────────────────────────────────────────
        ContentSection {
            title: Translation.tr("Integration Settings")
            icon: "tune"
            tooltip: Translation.tr("Transition animation speed and startup behavior.")

            ConfigSpinBox {
                icon: "av_timer"
                text: Translation.tr("Fade duration (ms)")
                value: (Config.options.appearance.openrgb.fadeDuration !== undefined ? Config.options.appearance.openrgb.fadeDuration : 0.5) * 1000
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
}
