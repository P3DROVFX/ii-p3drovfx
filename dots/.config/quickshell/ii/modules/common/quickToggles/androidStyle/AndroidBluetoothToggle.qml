pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs.services
import qs.modules.common
import qs.modules.common.models.quickToggles
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.common.widgets.bluetooth
import "QuickToggleResize.js" as Resize

/**
 * Android-style Bluetooth Quick Toggle.
 *
 * Supports compact 1x1 / 2x1 morphs and rich, responsive 2x2, 4x2, 2x4 layouts
 * inspired by the Bluetooth Devices popup module (MaterialCookie shapes, battery
 * progress bar, EarbudsControlService ANC modes and Conversation Awareness).
 */
AndroidQuickToggleButton {
    id: root

    toggleModel: BluetoothToggle {}

    expandedIconShape: "Clover8Leaf"
    centerExpandedIcon: true
    expandedSurfaceColor: BluetoothStatus.connected
        ? (root.toggled ? Appearance.colors.colPrimary : Appearance.colors.colLayer3)
        : (BluetoothStatus.enabled ? Appearance.colors.colLayer3 : Appearance.colors.colSurfaceContainerLow)
    expandedSymbolColor: BluetoothStatus.connected
        ? (root.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer3)
        : (BluetoothStatus.enabled ? Appearance.colors.colOnLayer3 : Appearance.colors.colOnSurfaceVariant)
    expandedStatusTransparency: 0.4

    readonly property var activeDevice: EarbudsControlService.activeDevice ?? BluetoothStatus.firstActiveDevice
    readonly property var device: root.activeDevice
    readonly property string deviceName: activeDevice ? (activeDevice.name || activeDevice.alias || "") : ""
    readonly property string deviceIcon: activeDevice ? (activeDevice.icon || "") : ""
    readonly property string customImage: root.getDeviceImageSource(root.activeDevice)
    readonly property bool isEarbud: customImage === "" && (deviceIcon.toLowerCase().includes("headset")
        || deviceIcon.toLowerCase().includes("headphone") || deviceIcon.toLowerCase().includes("audio")
        || deviceName.toLowerCase().includes("buds"))

    readonly property var devBattery: root.activeDevice ? EarbudsControlService.batteryInfo(root.activeDevice) : null
    readonly property var devNoise: root.activeDevice ? EarbudsControlService.noiseControl(root.activeDevice) : null
    readonly property var devCa: root.activeDevice ? EarbudsControlService.conversationAwareness(root.activeDevice) : null
    readonly property var primaryPercent: root.activeDevice ? EarbudsControlService.primaryBatteryPercent(root.activeDevice) : null
    readonly property bool hasBattery: (devBattery && devBattery.available) || primaryPercent !== null || (activeDevice?.batteryAvailable ?? false)
    readonly property real batteryFraction: primaryPercent !== null ? (primaryPercent / 100.0) : (activeDevice?.battery ?? 0)
    readonly property bool isConnected: BluetoothStatus.connected && root.activeDevice !== null

    /**
     * Whether the cookie's slow turn may run.
     *
     * It is an infinite animation, and a tile of the island dashboard lives on a
     * full-screen, always-mapped surface: running it while the tile is not drawn costs
     * a 60 Hz repaint of the whole window (see the sports tiles' pulse). `visible` is
     * the effective visibility - it drops with a closed dashboard even while its grid
     * is kept warm - and `isUnused` is the tray's static preview. Each cookie adds its
     * own `visible`, because the rich layout keeps every format branch built and only
     * one of them is shown.
     */
    readonly property bool cookieTurns: root.isConnected && root.visible && !root.isUnused

    expandedTitle: isConnected ? deviceName
        : (BluetoothStatus.enabled ? Translation.tr("No devices") : Translation.tr("Bluetooth off"))
    expandedStatus: isConnected && hasBattery
        ? Math.round(batteryFraction * 100) + Translation.tr("% battery") : ""
    expandedIconComponent: isConnected ? deviceArtwork : null

    // ── Helpers ───────────────────────────────────────────────────────────────
    function getDeviceImageSource(dev) {
        if (!dev)
            return "";

        if (Config.options && Config.options.bluetoothDeviceImages) {
            var custom = Config.options.bluetoothDeviceImages.find(function(d) {
                return d.mac === dev.address;
            });
            if (custom && custom.image)
                return "file://" + Directories.shellConfig + "/bluetooth_images/" + custom.image;
        }

        var mac = (dev.address || "").replace(/:/g, "_").toUpperCase();
        var name = (dev.name || dev.alias || "").toLowerCase();
        var basePath = Directories.assetsPath ? ("file://" + Directories.assetsPath + "/images/devices/") : "";

        if (mac === "E8_EE_CC_96_31_3A" || name.includes("q30") || name.includes("soundcore life q30") || name.includes("soundcore"))
            return basePath + "anker_q30_.png";
        if (mac === "68_7D_6B_94_0B_C2" || name.includes("buds 3 pro") || name.includes("buds3 pro") || name.includes("galaxy buds 3 pro"))
            return basePath + "galaxy_buds_3_pro.png";
        if (name.includes("galaxy buds 3") || name.includes("buds 3") || name.includes("buds3"))
            return basePath + "galaxy_buds_3.png";
        if (mac === "64_1B_2F_9B_95_CE" || name.includes("s23"))
            return basePath + "samsung_s23.png";
        if (name.includes("s24"))
            return basePath + "samsung_s24_ultra.png";
        if (name.includes("pixel buds") || name.includes("buds pro") || name.includes("buds fe") || name.includes("buds"))
            return basePath + "pixel_buds.png";
        if (name.includes("xbox") || name.includes("elite"))
            return basePath + "xbox_elite_series_2.png";

        return "";
    }

    Component {
        id: deviceArtwork
        Item {
            anchors.fill: parent

            Image {
                anchors.centerIn: parent
                width: parent.width * 0.88
                height: parent.height * 0.88
                visible: root.customImage !== ""
                source: root.customImage
                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: true
            }

            Row {
                anchors.centerIn: parent
                spacing: root.scaled(2)
                visible: root.isEarbud && root.customImage === ""
                Repeater {
                    model: 2
                    Item {
                        id: bud
                        required property int index
                        width: Math.min(parent.parent.width * 0.45, root.scaled(28))
                        height: Math.min(parent.parent.height * 0.85, root.scaled(44))
                        Item {
                            anchors.fill: parent
                            layer.enabled: true
                            layer.effect: ColorOverlay {
                                color: root.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer3
                            }
                            Image {
                                anchors.fill: parent
                                source: "../../../../assets/images/devices/earbuds_cushion.svg"
                                sourceSize: Qt.size(width, height)
                                mirror: bud.index === 0
                            }
                        }
                        Item {
                            anchors.fill: parent
                            layer.enabled: true
                            layer.effect: ColorOverlay {
                                color: root.toggled ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer3
                            }
                            Image {
                                anchors.fill: parent
                                source: "../../../../assets/images/devices/earbuds_stem.svg"
                                sourceSize: Qt.size(width, height)
                                mirror: bud.index === 0
                            }
                        }
                    }
                }
            }

            MaterialSymbol {
                anchors.centerIn: parent
                visible: root.customImage === "" && !root.isEarbud
                fill: root.toggled ? 1 : 0
                text: Icons.getBluetoothDeviceMaterialSymbol(root.deviceIcon)
                iconSize: Math.min(parent.width * 0.75, root.scaled(32))
                color: root.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer3
            }
        }
    }

    // ── Overrides for 2x2+ and 1x2 sizes ──────────────────────────────────────
    wide2x2OverrideComponent: richBluetoothLayout
    tall1x2OverrideComponent: tall1x2Layout

    Component {
        id: richBluetoothLayout

        Item {
            id: container
            anchors.fill: parent
            anchors.margins: root.scaled(8)

            readonly property bool isWideFormat: (root.effectiveSizeW > root.effectiveSizeH) || (container.width > container.height * 1.2)
            readonly property bool isTallFormat: !isWideFormat && ((root.effectiveSizeH > root.effectiveSizeW) || (container.height > container.width * 1.2))
            readonly property bool isCompact2x2: !isWideFormat && !isTallFormat
            readonly property bool hasNoise: (root.devNoise && root.devNoise.available && root.devNoise.modes && root.devNoise.modes.length > 0)

            // =========================================================================
            // 1. CONNECTED STATE
            // =========================================================================
            Item {
                anchors.fill: parent
                visible: root.isConnected

                // ── 1.A WIDE FORMAT (e.g. 4x2, 4x3, 6x2) ──────────────────────────────
                RowLayout {
                    anchors.fill: parent
                    visible: container.isWideFormat
                    spacing: root.scaled(14)

                    // Left: Large Cookie Shape (fills nearly full height)
                    Item {
                        Layout.preferredWidth: root.scaled(88)
                        Layout.preferredHeight: root.scaled(88)
                        Layout.alignment: Qt.AlignVCenter

                        MaterialCookie {
                            id: wideCookie
                            anchors.centerIn: parent
                            implicitSize: root.scaled(86)
                            color: Appearance.colors.colPrimaryContainer

                            RotationAnimation on rotation {
                                from: 0; to: 360
                                duration: 15000
                                loops: Animation.Infinite
                                running: root.cookieTurns && wideCookie.visible
                            }
                        }

                        Loader {
                            anchors.centerIn: parent
                            width: root.scaled(68)
                            height: root.scaled(68)
                            sourceComponent: deviceArtwork
                        }
                    }

                    // Middle: Device Name, Status & Battery Bar
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: root.scaled(4)

                        StyledText {
                            text: root.deviceName !== "" ? root.deviceName : Translation.tr("Bluetooth Device")
                            font.pixelSize: root.scaled(Appearance.font.pixelSize.larger)
                            font.weight: Font.Bold
                            color: Appearance.colors.colOnLayer2
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: root.scaled(4)

                            MaterialSymbol {
                                text: "bluetooth_connected"
                                iconSize: root.scaled(14)
                                color: Appearance.colors.colPrimary
                            }

                            StyledText {
                                text: Translation.tr("Connected")
                                font.pixelSize: root.scaled(Appearance.font.pixelSize.smaller)
                                color: Appearance.colors.colSubtext
                            }

                            Item { Layout.fillWidth: true }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            visible: root.hasBattery
                            spacing: root.scaled(8)

                            StyledProgressBar {
                                Layout.fillWidth: true
                                Layout.preferredHeight: root.scaled(8)
                                valueBarHeight: root.scaled(8)
                                from: 0; to: 1
                                value: root.batteryFraction
                                highlightColor: root.batteryFraction <= 0.15 ? Appearance.m3colors.m3error : Appearance.colors.colPrimary
                                trackColor: ColorUtils.transparentize(Appearance.colors.colOnLayer2, 0.8)
                            }

                            StyledText {
                                text: Math.round(root.batteryFraction * 100) + "%"
                                font.pixelSize: root.scaled(Appearance.font.pixelSize.normal)
                                font.weight: Font.Bold
                                color: root.batteryFraction <= 0.15 ? Appearance.m3colors.m3error : Appearance.colors.colOnLayer2
                            }
                        }
                    }

                    // Right: Noise Control & Conversation Awareness (if available)
                    ColumnLayout {
                        visible: container.hasNoise || (root.devCa && root.devCa.available)
                        Layout.preferredWidth: root.scaled(165)
                        Layout.alignment: Qt.AlignVCenter
                        spacing: root.scaled(6)

                        EarbudsNoiseControlSelector {
                            visible: container.hasNoise
                            Layout.fillWidth: true
                            compact: true
                            buttonHeight: root.scaled(32)
                            modes: root.devNoise ? root.devNoise.modes : []
                            currentMode: root.devNoise ? root.devNoise.currentMode : "off"
                            onModeRequested: modeKey => EarbudsControlService.setNoiseMode(root.activeDevice, modeKey)
                        }

                        EarbudsConversationAwareness {
                            visible: root.devCa && root.devCa.available
                            Layout.fillWidth: true
                            compact: true
                            enabled: root.devCa ? root.devCa.enabled : false
                            available: root.devCa ? root.devCa.available : false
                            onToggled: en => EarbudsControlService.setConversationAwareness(root.activeDevice, en)
                        }
                    }
                }

                // ── 1.B TALL FORMAT (e.g. 2x3, 2x4, 2x5, 2x6) ──────────────────────────────
                ColumnLayout {
                    anchors.fill: parent
                    visible: container.isTallFormat
                    spacing: root.scaled(6)

                    Item { Layout.fillHeight: true }

                    // Top: Hero Shape
                    Item {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: root.scaled(container.hasNoise ? 72 : (root.effectiveSizeH >= 4 ? 108 : 82))
                        Layout.preferredHeight: root.scaled(container.hasNoise ? 72 : (root.effectiveSizeH >= 4 ? 108 : 82))

                        MaterialCookie {
                            id: tallCookie
                            anchors.centerIn: parent
                            implicitSize: root.scaled(container.hasNoise ? 70 : (root.effectiveSizeH >= 4 ? 104 : 80))
                            color: Appearance.colors.colPrimaryContainer

                            RotationAnimation on rotation {
                                from: 0; to: 360
                                duration: 15000
                                loops: Animation.Infinite
                                running: root.cookieTurns && tallCookie.visible
                            }
                        }

                        Loader {
                            anchors.centerIn: parent
                            width: root.scaled(container.hasNoise ? 54 : (root.effectiveSizeH >= 4 ? 84 : 64))
                            height: root.scaled(container.hasNoise ? 54 : (root.effectiveSizeH >= 4 ? 84 : 64))
                            sourceComponent: deviceArtwork
                        }
                    }

                    // Device Name & Status (Centered)
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignHCenter
                        spacing: root.scaled(2)

                        StyledText {
                            text: root.deviceName !== "" ? root.deviceName : Translation.tr("Bluetooth Device")
                            font.pixelSize: root.scaled(Appearance.font.pixelSize.larger)
                            font.weight: Font.Bold
                            horizontalAlignment: Text.AlignHCenter
                            color: Appearance.colors.colOnLayer2
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: root.scaled(4)

                            MaterialSymbol {
                                text: "bluetooth_connected"
                                iconSize: root.scaled(14)
                                color: Appearance.colors.colPrimary
                            }

                            StyledText {
                                text: (root.effectiveSizeH < 4 && root.hasBattery)
                                    ? (Translation.tr("Connected") + " • " + Math.round(root.batteryFraction * 100) + "%")
                                    : Translation.tr("Connected")
                                font.pixelSize: root.scaled(Appearance.font.pixelSize.small)
                                color: Appearance.colors.colSubtext
                            }
                        }
                    }

                    // Battery Display (Big text + bar in tall formats 2x4+)
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignHCenter
                        visible: root.hasBattery && root.effectiveSizeH >= 4
                        spacing: root.scaled(4)

                        StyledText {
                            visible: !container.hasNoise
                            Layout.alignment: Qt.AlignHCenter
                            text: Math.round(root.batteryFraction * 100) + "%"
                            font.pixelSize: root.scaled(Appearance.font.pixelSize.hugeass)
                            font.weight: Font.Black
                            color: root.batteryFraction <= 0.15 ? Appearance.m3colors.m3error : Appearance.colors.colOnLayer2
                        }

                        StyledProgressBar {
                            Layout.fillWidth: true
                            Layout.preferredHeight: root.scaled(8)
                            valueBarHeight: root.scaled(8)
                            from: 0; to: 1
                            value: root.batteryFraction
                            highlightColor: root.batteryFraction <= 0.15 ? Appearance.m3colors.m3error : Appearance.colors.colPrimary
                            trackColor: ColorUtils.transparentize(Appearance.colors.colOnLayer2, 0.8)
                        }

                        StyledText {
                            visible: container.hasNoise
                            Layout.alignment: Qt.AlignHCenter
                            text: Math.round(root.batteryFraction * 100) + "%"
                            font.pixelSize: root.scaled(Appearance.font.pixelSize.smallie)
                            font.weight: Font.Bold
                            color: root.batteryFraction <= 0.15 ? Appearance.m3colors.m3error : Appearance.colors.colOnLayer2
                        }
                    }

                    // ANC Modes & Conversation Awareness
                    EarbudsNoiseControlSelector {
                        visible: container.hasNoise
                        Layout.fillWidth: true
                        compact: true
                        buttonHeight: root.scaled(30)
                        modes: root.devNoise ? root.devNoise.modes : []
                        currentMode: root.devNoise ? root.devNoise.currentMode : "off"
                        onModeRequested: modeKey => EarbudsControlService.setNoiseMode(root.activeDevice, modeKey)
                    }

                    EarbudsConversationAwareness {
                        visible: root.devCa && root.devCa.available
                        Layout.fillWidth: true
                        compact: true
                        enabled: root.devCa ? root.devCa.enabled : false
                        available: root.devCa ? root.devCa.available : false
                        onToggled: en => EarbudsControlService.setConversationAwareness(root.activeDevice, en)
                    }

                    Item { Layout.fillHeight: true }
                }

                // ── 1.C COMPACT 2x2 FORMAT ────────────────────────────────────────────
                // Case 1: With ANC Modes (e.g. Galaxy Buds 3 Pro, Anker Q30)
                ColumnLayout {
                    anchors.fill: parent
                    visible: container.isCompact2x2 && container.hasNoise
                    spacing: root.scaled(4)

                    Item { Layout.fillHeight: true }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: root.scaled(8)

                        Item {
                            Layout.preferredWidth: root.scaled(52)
                            Layout.preferredHeight: root.scaled(52)
                            Layout.alignment: Qt.AlignVCenter

                            MaterialCookie {
                                id: ancCookie
                                anchors.centerIn: parent
                                implicitSize: root.scaled(50)
                                color: Appearance.colors.colPrimaryContainer

                                RotationAnimation on rotation {
                                    from: 0; to: 360
                                    duration: 15000
                                    loops: Animation.Infinite
                                    running: root.cookieTurns && ancCookie.visible
                                }
                            }

                            Loader {
                                anchors.centerIn: parent
                                width: root.scaled(40)
                                height: root.scaled(40)
                                sourceComponent: deviceArtwork
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            spacing: root.scaled(1)

                            StyledText {
                                text: root.deviceName !== "" ? root.deviceName : Translation.tr("Bluetooth Device")
                                font.pixelSize: root.scaled(Appearance.font.pixelSize.normal)
                                font.weight: Font.Bold
                                color: Appearance.colors.colOnLayer2
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }

                            StyledText {
                                text: Translation.tr("Connected")
                                font.pixelSize: root.scaled(Appearance.font.pixelSize.smallie)
                                color: Appearance.colors.colSubtext
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }
                    }

                    RowLayout {
                        visible: root.hasBattery
                        Layout.fillWidth: true
                        spacing: root.scaled(6)

                        StyledProgressBar {
                            Layout.fillWidth: true
                            Layout.preferredHeight: root.scaled(6)
                            valueBarHeight: root.scaled(6)
                            from: 0; to: 1
                            value: root.batteryFraction
                            highlightColor: root.batteryFraction <= 0.15 ? Appearance.m3colors.m3error : Appearance.colors.colPrimary
                            trackColor: ColorUtils.transparentize(Appearance.colors.colOnLayer2, 0.8)
                        }

                        StyledText {
                            text: Math.round(root.batteryFraction * 100) + "%"
                            font.pixelSize: root.scaled(Appearance.font.pixelSize.smallie)
                            font.weight: Font.Bold
                            color: root.batteryFraction <= 0.15 ? Appearance.m3colors.m3error : Appearance.colors.colOnLayer2
                        }
                    }

                    EarbudsNoiseControlSelector {
                        Layout.fillWidth: true
                        compact: true
                        buttonHeight: root.scaled(30)
                        modes: root.devNoise ? root.devNoise.modes : []
                        currentMode: root.devNoise ? root.devNoise.currentMode : "off"
                        onModeRequested: modeKey => EarbudsControlService.setNoiseMode(root.activeDevice, modeKey)
                    }

                    Item { Layout.fillHeight: true }
                }

                // Case 2: Without ANC (e.g. Phones, simple headsets, mice, controllers)
                ColumnLayout {
                    anchors.fill: parent
                    visible: container.isCompact2x2 && !container.hasNoise
                    spacing: root.scaled(4)

                    Item { Layout.fillHeight: true }

                    // Top: Large Hero Shape filling width/height
                    Item {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: root.scaled(80)
                        Layout.preferredHeight: root.scaled(80)

                        MaterialCookie {
                            id: bareCookie
                            anchors.centerIn: parent
                            implicitSize: root.scaled(78)
                            color: Appearance.colors.colPrimaryContainer

                            RotationAnimation on rotation {
                                from: 0; to: 360
                                duration: 15000
                                loops: Animation.Infinite
                                running: root.cookieTurns && bareCookie.visible
                            }
                        }

                        Loader {
                            anchors.centerIn: parent
                            width: root.scaled(62)
                            height: root.scaled(62)
                            sourceComponent: deviceArtwork
                        }
                    }

                    Item { Layout.preferredHeight: root.scaled(2) }

                    // Middle: Device Name & Connection Status
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignHCenter
                        spacing: root.scaled(1)

                        StyledText {
                            text: root.deviceName !== "" ? root.deviceName : Translation.tr("Bluetooth Device")
                            font.pixelSize: root.scaled(Appearance.font.pixelSize.normal)
                            font.weight: Font.Bold
                            horizontalAlignment: Text.AlignHCenter
                            color: Appearance.colors.colOnLayer2
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: root.scaled(3)

                            MaterialSymbol {
                                text: "bluetooth_connected"
                                iconSize: root.scaled(13)
                                color: Appearance.colors.colPrimary
                            }

                            StyledText {
                                text: Translation.tr("Connected")
                                font.pixelSize: root.scaled(Appearance.font.pixelSize.smallie)
                                color: Appearance.colors.colSubtext
                            }
                        }
                    }

                    Item { Layout.preferredHeight: root.scaled(2) }

                    // Bottom: Full-Width Battery Progress Bar + Percentage
                    RowLayout {
                        Layout.fillWidth: true
                        visible: root.hasBattery
                        spacing: root.scaled(6)

                        StyledProgressBar {
                            Layout.fillWidth: true
                            Layout.preferredHeight: root.scaled(7)
                            valueBarHeight: root.scaled(7)
                            from: 0; to: 1
                            value: root.batteryFraction
                            highlightColor: root.batteryFraction <= 0.15 ? Appearance.m3colors.m3error : Appearance.colors.colPrimary
                            trackColor: ColorUtils.transparentize(Appearance.colors.colOnLayer2, 0.8)
                        }

                        StyledText {
                            text: Math.round(root.batteryFraction * 100) + "%"
                            font.pixelSize: root.scaled(Appearance.font.pixelSize.small)
                            font.weight: Font.Bold
                            color: root.batteryFraction <= 0.15 ? Appearance.m3colors.m3error : Appearance.colors.colOnLayer2
                        }
                    }

                    Item { Layout.fillHeight: true }
                }
            }

            // =========================================================================
            // 2. DISCONNECTED / BLUETOOTH OFF STATE
            // =========================================================================
            // Shape and one line, nothing under it: the tile is barely taller than those
            // two together, so a hint line came out past the tile's own edge.
            ColumnLayout {
                anchors.fill: parent
                visible: !root.isConnected
                spacing: root.scaled(6)
                Layout.alignment: Qt.AlignCenter

                Item { Layout.fillHeight: true }

                MaterialShape {
                    id: emptyShape
                    Layout.alignment: Qt.AlignHCenter
                    shapeString: "Cookie6Sided"
                    /**
                     * The shape yields to what the label and the three gaps need.
                     *
                     * At its designed size the pair is taller than a two-row tile's inner
                     * box, and the spacers above and below had nothing left to centre
                     * with: the label ended up sitting on the tile's bottom edge.
                     */
                    implicitSize: Math.min(root.scaled(container.isTallFormat ? 88 : (container.isWideFormat ? 76 : 64)),
                        Math.max(root.scaled(24), container.height - root.scaled(6) * 3 - emptyLabel.implicitHeight))
                    color: Appearance.colors.colLayer3

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: BluetoothStatus.enabled ? "bluetooth_searching" : "bluetooth_disabled"
                        iconSize: Math.round(emptyShape.implicitSize * 0.5)
                        color: Appearance.colors.colOnLayer3
                    }
                }

                StyledText {
                    id: emptyLabel
                    Layout.alignment: Qt.AlignHCenter
                    Layout.fillWidth: true
                    text: BluetoothStatus.enabled ? Translation.tr("No devices connected") : Translation.tr("Bluetooth off")
                    font.pixelSize: root.scaled(Appearance.font.pixelSize.normal)
                    font.weight: Font.Bold
                    horizontalAlignment: Text.AlignHCenter
                    color: Appearance.colors.colOnLayer2
                    elide: Text.ElideRight
                }

                Item { Layout.fillHeight: true }
            }
        }
    }

    Component {
        id: tall1x2Layout

        Item {
            anchors.fill: parent
            anchors.margins: root.scaled(8)

            ColumnLayout {
                anchors.fill: parent
                spacing: root.scaled(4)

                Item { Layout.fillHeight: true }

                Item {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: root.scaled(52)
                    Layout.preferredHeight: root.scaled(52)

                    MaterialCookie {
                        anchors.centerIn: parent
                        implicitSize: root.scaled(50)
                        color: root.isConnected ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer3
                    }

                    Loader {
                        anchors.centerIn: parent
                        width: root.scaled(38)
                        height: root.scaled(38)
                        sourceComponent: root.isConnected ? deviceArtwork : null
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        visible: !root.isConnected
                        text: BluetoothStatus.enabled ? "bluetooth_searching" : "bluetooth_disabled"
                        iconSize: root.scaled(26)
                        color: Appearance.colors.colOnLayer3
                    }
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.fillWidth: true
                    text: root.isConnected ? (root.deviceName || Translation.tr("Bluetooth")) : (BluetoothStatus.enabled ? Translation.tr("No devices") : Translation.tr("Off"))
                    font.pixelSize: root.scaled(Appearance.font.pixelSize.small)
                    font.weight: Font.Bold
                    horizontalAlignment: Text.AlignHCenter
                    color: Appearance.colors.colOnLayer2
                    elide: Text.ElideRight
                }

                StyledText {
                    visible: root.isConnected && root.hasBattery
                    Layout.alignment: Qt.AlignHCenter
                    text: Math.round(root.batteryFraction * 100) + "%"
                    font.pixelSize: root.scaled(Appearance.font.pixelSize.smaller)
                    font.weight: Font.Medium
                    horizontalAlignment: Text.AlignHCenter
                    color: Appearance.colors.colSubtext
                }

                Item { Layout.fillHeight: true }
            }
        }
    }
}
