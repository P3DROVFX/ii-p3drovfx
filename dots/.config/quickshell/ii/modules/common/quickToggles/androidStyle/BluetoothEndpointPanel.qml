pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Bluetooth
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.common.widgets.bluetooth

/**
 * The tall / multi-row face of the Bluetooth quick toggle.
 *
 * Designed in Google Material 3 Expressive style, following the same architectural
 * pattern as AudioEndpointPanel:
 * - Surfaces, not lines: clean gaps and fills with M3 color tokens.
 * - Shape is state: Material shape morphs between Circle (off/idle) and Cookie (live/hover).
 * - Key metric in expressive condensed digits: Google Sans Flex digits showing battery percentage.
 * - Fluid responsiveness: adapts layout dynamically to wide, tall, narrow, and compact geometries
 *   based on settled dimensions to prevent animation jitter.
 * - Shape click toggles Bluetooth; tile background click opens the Bluetooth device menu.
 */
Item {
    id: root

    /** The AndroidQuickToggleButton this face is drawn for. */
    required property var tile

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
    readonly property int batteryPercent: Math.round(root.batteryFraction * 100)

    readonly property bool isConnected: BluetoothStatus.connected && root.activeDevice !== null
    readonly property bool isEnabled: BluetoothStatus.enabled
    readonly property bool live: root.isConnected
    readonly property bool hasNoise: (root.devNoise && root.devNoise.available && root.devNoise.modes && root.devNoise.modes.length > 0)

    readonly property string kindLabel: {
        if (root.isConnected)
            return Translation.tr("Bluetooth") + " · " + Translation.tr("Connected");
        if (BluetoothStatus.discovering)
            return Translation.tr("Bluetooth") + " · " + Translation.tr("Searching...");
        if (root.isEnabled)
            return Translation.tr("Bluetooth") + " · " + Translation.tr("No devices");
        return Translation.tr("Bluetooth off");
    }

    readonly property string titleText: {
        if (root.isConnected)
            return root.deviceName || Translation.tr("Bluetooth");
        if (root.isEnabled)
            return Translation.tr("No devices");
        return Translation.tr("Bluetooth");
    }

    // Accent family of the tile
    readonly property bool isLowBattery: root.hasBattery && root.batteryPercent <= 15
    readonly property color colAccent: root.isLowBattery ? Appearance.m3colors.m3error : Appearance.colors.colPrimary
    readonly property color colAccentContainer: root.isLowBattery ? Appearance.colors.colErrorContainer : Appearance.colors.colPrimaryContainer
    readonly property color colOnAccentContainer: root.isLowBattery ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnPrimaryContainer
    readonly property color colMutedFill: ColorUtils.transparentize(Appearance.colors.colOnLayer2, 0.55)

    function s(value) {
        return root.tile.scaled(value);
    }
    function clamp(value, lo, hi) {
        return Math.max(lo, Math.min(hi, value));
    }

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

        return BluetoothDeviceImages.sourceFor(dev);
    }

    // ── Format: decided on the SETTLED size, so it does not flip while the tile animates ──
    readonly property real settledW: Math.max(1, root.tile.allocatedWidth - root.tile.scaled(24))
    readonly property real settledH: Math.max(1, root.tile.baseHeight - root.tile.scaled(24))
    readonly property string format: {
        const w = root.settledW, h = root.settledH;
        if (w < root.s(100))
            return "narrow";
        if (w >= root.s(250) && w >= h * 2)
            return "wide";
        if (h >= w * 1.2)
            return "tall";
        return "compact";
    }

    // ── Geometry of the three parts for the current format and the live size ──
    readonly property var geometry: {
        const W = root.width, H = root.height;
        const s = root.s;
        const g = {};
        switch (root.format) {
        case "wide": {
            const size = root.clamp(Math.round(H * 0.72), s(40), s(84));
            const digitsW = Math.round(Math.min(W * 0.46, H * 1.8));
            const colX = size + s(16);
            const nameH = s(44);
            g.shape = { x: 0, y: (H - size) / 2, size: size };
            g.digits = { x: W - digitsW, y: 0, w: digitsW, h: H, align: Text.AlignRight };
            g.name = { x: colX, y: (H - nameH) / 2, w: Math.max(0, W - colX - digitsW - s(12)), h: nameH, single: false, show: true };
            break;
        }
        case "tall": {
            const size = Math.min(W, s(52));
            const nameH = s(36);
            g.shape = { x: 0, y: 0, size: size };
            g.digits = { x: 0, y: size + s(4), w: W, h: Math.max(0, H - size - s(4) - nameH - s(6)), align: Text.AlignLeft };
            g.name = { x: 0, y: H - nameH, w: W, h: nameH, single: false, show: true };
            break;
        }
        case "narrow": {
            const size = Math.min(W, Math.round(H * 0.42), s(44));
            const gap = s(4);
            g.shape = { x: (W - size) / 2, y: 0, size: size };
            g.digits = { x: 0, y: size + gap, w: W, h: Math.max(0, H - size - gap), align: Text.AlignHCenter };
            g.name = { x: 0, y: 0, w: 0, h: 0, single: true, show: false };
            break;
        }
        default: { // compact: 2x2, 2x3, 3x2 ...
            const nameH = s(18);
            const gap = s(6);
            const topH = Math.max(s(24), H - nameH - gap);
            const size = Math.min(topH, s(46));
            g.shape = { x: 0, y: 0, size: size };
            g.digits = { x: size + s(8), y: 0, w: Math.max(0, W - size - s(8)), h: topH, align: Text.AlignRight };
            g.name = { x: 0, y: topH + gap, w: W, h: nameH, single: true, show: true };
        }
        }
        return g;
    }

    // ═════════════════════════ Artwork Component ═════════════════════════

    Component {
        id: deviceArtwork
        Item {
            anchors.fill: parent

            Image {
                anchors.centerIn: parent
                width: parent.width * 0.84
                height: parent.height * 0.84
                visible: root.customImage !== ""
                source: root.customImage
                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: true
            }

            Row {
                anchors.centerIn: parent
                spacing: root.s(2)
                visible: root.isEarbud && root.customImage === ""
                Repeater {
                    model: 2
                    Item {
                        id: bud
                        required property int index
                        width: Math.min(parent.parent.width * 0.45, root.s(28))
                        height: Math.min(parent.parent.height * 0.85, root.s(44))
                        Item {
                            anchors.fill: parent
                            layer.enabled: true
                            layer.effect: ColorOverlay {
                                color: root.live ? root.colOnAccentContainer : Appearance.colors.colOnLayer3
                            }
                            Image {
                                anchors.fill: parent
                                source: Directories.assetsPath ? ("file://" + Directories.assetsPath + "/images/devices/earbuds_cushion.svg") : ""
                                sourceSize: Qt.size(width, height)
                                mirror: bud.index === 0
                            }
                        }
                        Item {
                            anchors.fill: parent
                            layer.enabled: true
                            layer.effect: ColorOverlay {
                                color: root.live ? root.colAccent : Appearance.colors.colLayer3
                            }
                            Image {
                                anchors.fill: parent
                                source: Directories.assetsPath ? ("file://" + Directories.assetsPath + "/images/devices/earbuds_stem.svg") : ""
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
                fill: root.live ? 1 : 0
                text: root.isConnected ? Icons.getBluetoothDeviceMaterialSymbol(root.deviceIcon) : (root.isEnabled ? "bluetooth_searching" : "bluetooth_disabled")
                iconSize: Math.round(parent.width * 0.52)
                color: root.live ? root.colOnAccentContainer : Appearance.colors.colOnLayer3
            }
        }
    }

    // ═════════════════════════ The tile face ═════════════════════════

    // Shape button: shape is state. Live = Cookie, idle/off = Circle.
    Item {
        id: shapeSlot
        x: root.geometry.shape.x
        y: root.geometry.shape.y
        width: root.geometry.shape.size
        height: width

        MaterialShape {
            id: shapeButton
            anchors.fill: parent
            implicitSize: parent.width
            shapeString: {
                if (!root.isEnabled)
                    return "Circle";
                if (!root.isConnected)
                    return BluetoothStatus.discovering ? (shapeHover.hovered ? "Sunny" : "SoftBurst") : "Circle";
                return shapeHover.hovered ? "Cookie12Sided" : "Cookie9Sided";
            }
            color: root.live ? root.colAccentContainer : Appearance.colors.colLayer3
            scale: shapeArea.pressed ? 0.95 : (shapeHover.hovered ? 1.02 : 1)
            Behavior on scale {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(shapeButton)
            }
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(shapeButton)
            }

            Loader {
                anchors.centerIn: parent
                width: parent.width * 0.76
                height: parent.height * 0.76
                sourceComponent: deviceArtwork
            }
        }
        HoverHandler {
            id: shapeHover
            enabled: !root.tile.editMode
        }
        MouseArea {
            id: shapeArea
            anchors.fill: parent
            enabled: !root.tile.editMode
            cursorShape: Qt.PointingHandCursor
            onClicked: root.tile.mainAction()
        }
    }

    // The key metric / battery digits.
    Item {
        id: digitsBox
        x: root.geometry.digits.x
        y: root.geometry.digits.y
        width: root.geometry.digits.w
        height: root.geometry.digits.h
        clip: false

        property real boldness: root.live ? 1 : 0
        Behavior on boldness {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(digitsBox)
        }
        readonly property bool showPct: root.live && root.hasBattery
        readonly property string text: {
            if (root.live) {
                if (root.hasBattery)
                    return String(root.batteryPercent);
                return "ON";
            }
            if (BluetoothStatus.discovering)
                return "···";
            return "--";
        }
        readonly property var axes: ({
            "wght": 560 + 200 * boldness,
            "wdth": 30 + 10 * boldness,
            "ROND": 100
        })
        // Calibrated on the real font: how wide one digit is per pixel of size.
        TextMetrics {
            id: digitMetrics
            text: "0"
            font.family: Appearance.font.family.main
            font.pixelSize: 100
            font.variableAxes: digitsBox.axes
        }
        readonly property real digitW: Math.max(0.3, digitMetrics.advanceWidth / 100)
        readonly property real pctRatio: 0.34
        readonly property real px: Math.round(Math.max(root.s(12), Math.min(height * 0.92,
            width / (text.length * digitW + (showPct ? pctRatio * 0.62 : 0)))))

        Row {
            id: digitsRow
            spacing: 1
            anchors.verticalCenter: parent.verticalCenter
            x: root.geometry.digits.align === Text.AlignRight ? parent.width - width
                : (root.geometry.digits.align === Text.AlignHCenter ? (parent.width - width) / 2 : 0)

            StyledText {
                id: digitsText
                text: digitsBox.text
                font.family: Appearance.font.family.main
                font.pixelSize: digitsBox.px
                font.variableAxes: digitsBox.axes
                verticalAlignment: Text.AlignVCenter
                color: root.live ? (root.isLowBattery ? Appearance.m3colors.m3error : Appearance.colors.colOnLayer2) : Appearance.colors.colSubtext
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(digitsText)
                }
            }
            Item {
                visible: digitsBox.showPct
                width: pctText.implicitWidth
                height: digitsText.implicitHeight
                StyledText {
                    id: pctText
                    anchors.top: parent.top
                    anchors.topMargin: Math.round(digitsBox.px * 0.18)
                    text: "%"
                    font.family: Appearance.font.family.main
                    font.pixelSize: Math.max(root.s(9), Math.round(digitsBox.px * digitsBox.pctRatio))
                    font.weight: Font.Bold
                    color: root.live ? root.colAccent : Appearance.colors.colSubtext
                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(pctText)
                    }
                }
            }
        }
    }

    // Caption + Device name. Single line in compact with unfold_more chevron.
    Item {
        id: nameBlock
        visible: root.geometry.name.show
        x: root.geometry.name.x
        y: root.geometry.name.y
        width: root.geometry.name.w
        height: root.geometry.name.h

        readonly property bool single: root.geometry.name.single

        StyledText {
            id: captionText
            visible: !nameBlock.single
            width: parent.width
            text: root.kindLabel
            font.pixelSize: root.s(Appearance.font.pixelSize.smallest + 1)
            font.weight: Font.Bold
            color: Appearance.colors.colSubtext
            elide: Text.ElideRight
        }
        StyledText {
            id: deviceText
            y: nameBlock.single ? (parent.height - height) / 2 : captionText.height
            width: nameBlock.single ? Math.max(0, parent.width - chevron.width - root.s(2)) : parent.width
            text: nameBlock.single && !root.live ? root.kindLabel : root.titleText
            font.family: nameBlock.single ? Appearance.font.family.main : Appearance.font.family.title
            font.pixelSize: nameBlock.single ? root.s(Appearance.font.pixelSize.smaller)
                : root.s(root.format === "wide" ? Appearance.font.pixelSize.larger : Appearance.font.pixelSize.small)
            font.variableAxes: nameBlock.single ? Appearance.font.variableAxes.main : Appearance.font.variableAxes.titleRounded
            font.weight: nameBlock.single ? Font.DemiBold : Font.Medium
            color: Appearance.colors.colOnLayer2
            elide: Text.ElideRight
        }
        MaterialSymbol {
            id: chevron
            visible: nameBlock.single
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: "unfold_more"
            iconSize: root.s(16)
            color: root.live ? root.colAccent : Appearance.colors.colSubtext
        }
    }
}
