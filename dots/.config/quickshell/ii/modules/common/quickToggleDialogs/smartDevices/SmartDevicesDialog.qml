import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

WindowDialog {
    id: root

    preferredDialogWidth: 380
    backgroundWidth: 380
    backgroundHeight: Math.min(860, contentHeight)

    property int currentDeviceIndex: 0
    readonly property var currentDevice: (SmartDevicesService.devices && SmartDevicesService.devices.length > 0)
        ? SmartDevicesService.devices[Math.min(currentDeviceIndex, SmartDevicesService.devices.length - 1)]
        : null

    readonly property string deviceCategory: currentDevice?.category || "dj"
    readonly property bool isLighting: deviceCategory === "dj" || deviceCategory === "dd" || deviceCategory === "light"
    readonly property bool isSocket: deviceCategory === "cz" || deviceCategory === "socket" || deviceCategory === "plug"
    readonly property bool isSwitch: deviceCategory === "kg" || deviceCategory === "switch"

    readonly property bool isWhiteMode: currentDevice?.mode === "white"
    readonly property color activeDeviceColor: currentDevice?.hex_color || "#4400FF"
    readonly property color pureHueColor: SmartDevicesService.hsvToHex(currentDevice?.hue ?? 256, 100, 100)

    readonly property color whitePreviewColor: {
        const k = root.currentDevice?.temperature ?? 4000;
        if (k < 3400) return "#FFB74D";
        if (k < 5000) return "#FFE0B2";
        return "#CFD8DC";
    }

    function badgeIconColor(bgCol) {
        const lum = 0.299 * bgCol.r + 0.587 * bgCol.g + 0.114 * bgCol.b;
        return lum > 0.5 ? "#1A1A1A" : "#FFFFFF";
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Gradient Styled Slider (Inherits StyledSlider, keeping standard geometry,
    // handle, tooltip and interaction while displaying gradients across the track)
    // ──────────────────────────────────────────────────────────────────────────
    component GradientStyledSlider: StyledSlider {
        id: gSlider
        required property Gradient trackGradient
        configuration: StyledSlider.Configuration.L
        stopIndicatorValues: []

        background: Item {
            id: bgContainer
            anchors.verticalCenter: parent?.verticalCenter
            anchors.horizontalCenter: parent?.horizontalCenter
            width: gSlider.width
            implicitHeight: gSlider.trackWidth

            readonly property real handlePos: gSlider.leftPadding + (gSlider.visualPosition * gSlider.effectiveDraggingWidth)
            readonly property real leftW: Math.max(0, handlePos - gSlider.handleMargins - (gSlider.handleWidth / 2))
            readonly property real rightX: handlePos + gSlider.handleMargins + (gSlider.handleWidth / 2)
            readonly property real rightW: Math.max(0, width - rightX)

            // 1. Left Track (Active / Filled): Full Vibrant Gradient
            Item {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: bgContainer.leftW
                height: gSlider.trackWidth
                clip: true
                visible: width > 1

                Rectangle {
                    width: bgContainer.width
                    height: gSlider.trackWidth
                    radius: gSlider.trackRadius
                    gradient: gSlider.trackGradient
                }
            }

            // 2. Right Track (Inactive / Unfilled): Gradient continues, visible under translucent tint!
            Item {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: bgContainer.rightW
                height: gSlider.trackWidth
                clip: true
                visible: width > 1

                Rectangle {
                    x: -(bgContainer.width - bgContainer.rightW)
                    width: bgContainer.width
                    height: gSlider.trackWidth
                    radius: gSlider.trackRadius
                    gradient: gSlider.trackGradient
                }

                // Semi-transparent overlay to indicate unfilled portion while keeping colors visible
                Rectangle {
                    anchors.fill: parent
                    topLeftRadius: gSlider.unsharpenRadius
                    bottomLeftRadius: gSlider.unsharpenRadius
                    topRightRadius: gSlider.trackRadius
                    bottomRightRadius: gSlider.trackRadius
                    color: Appearance.colors.colSurfaceContainerHighest
                    opacity: 0.45
                }
            }
        }
    }

    // ── Dialog Content ────────────────────────────────────────────────────────
    // When no devices exist: Empty State layout
    ColumnLayout {
        id: emptyStateLayout
        visible: !SmartDevicesService.hasDevices
        Layout.fillWidth: true
        spacing: 16

        Item { implicitHeight: 12 }

        MaterialShapeWrappedMaterialSymbol {
            Layout.alignment: Qt.AlignHCenter
            shape: MaterialShape.Shape.SoftBurst
            text: "home_iot_device"
            iconSize: 36
            implicitSize: 84
            color: Appearance.colors.colPrimaryContainer
            colSymbol: Appearance.colors.colOnPrimaryContainer
        }

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: Translation.tr("Smart Devices")
            font.family: Appearance.font.family.title
            font.pixelSize: 24
            font.weight: Font.Bold
            color: Appearance.colors.colOnSurface
        }

        Rectangle {
            Layout.fillWidth: true
            radius: 24
            color: Appearance.colors.colSurfaceContainer
            implicitHeight: emptyCardCol.implicitHeight + 28

            ColumnLayout {
                id: emptyCardCol
                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                    margins: 16
                }
                spacing: 12

                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    font.pixelSize: 13
                    color: Appearance.colors.colOnSurface
                    lineHeight: 1.35
                    text: Translation.tr("Smart Devices currently supports Tuya smart home devices via TinyTuya. Connect and configure devices manually on your local network (e.g. using 'tinytuya wizard'). This shell acts as a native interface for control.")
                }

                RippleButton {
                    Layout.fillWidth: true
                    implicitHeight: 42
                    buttonRadius: 21
                    colBackground: Appearance.colors.colSurfaceContainerHighest
                    colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
                    colRipple: Appearance.colors.colSurfaceContainerHighestActive

                    contentItem: Item {
                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 8
                            MaterialSymbol {
                                text: "open_in_new"
                                iconSize: 18
                                color: Appearance.colors.colPrimary
                            }
                            StyledText {
                                text: Translation.tr("TinyTuya on GitHub")
                                font.pixelSize: 13
                                font.weight: Font.Bold
                                color: Appearance.colors.colPrimary
                            }
                        }
                    }
                    onClicked: {
                        Qt.openUrlExternally("https://github.com/jasonacox/tinytuya");
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    font.pixelSize: 11
                    color: Appearance.colors.colOnSurfaceVariant
                    lineHeight: 1.25
                    text: Translation.tr("Support for other smart device ecosystems is open to PRs on the repository.")
                }
            }
        }

        WindowDialogButtonRow {
            Layout.leftMargin: 0
            Layout.rightMargin: 0
            Layout.bottomMargin: -8

            RippleButton {
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSurfaceContainerHighest
                colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
                colRipple: Appearance.colors.colSurfaceContainerHighestActive
                implicitHeight: 36
                implicitWidth: scanRow.implicitWidth + 32

                contentItem: Item {
                    RowLayout {
                        id: scanRow
                        anchors.centerIn: parent
                        spacing: 6
                        MaterialSymbol {
                            text: "refresh"
                            iconSize: 16
                            color: Appearance.colors.colOnSurface
                        }
                        StyledText {
                            text: SmartDevicesService.isRefreshing ? Translation.tr("Scanning...") : Translation.tr("Scan Devices")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.variableAxes: ({ "wght": 600 })
                            color: Appearance.colors.colOnSurface
                        }
                    }
                }
                onClicked: SmartDevicesService.refresh()
            }

            Item { Layout.fillWidth: true }

            RippleButton {
                id: emptyDoneBtn
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                colRipple: Appearance.colors.colPrimaryActive
                implicitHeight: 36
                implicitWidth: emptyDoneText.implicitWidth + 48

                contentItem: StyledText {
                    id: emptyDoneText
                    text: Translation.tr("Done")
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.variableAxes: ({ "wght": 700 })
                    color: Appearance.colors.colOnPrimary
                }
                onClicked: root.dismiss()
            }
        }
    }

    // When devices exist: Active Controller Layout
    ColumnLayout {
        id: activeDeviceLayout
        visible: SmartDevicesService.hasDevices && currentDevice !== null
        Layout.fillWidth: true
        spacing: 16

        // ── Header: "Home devices" + Big Bold Device Title + Standard StyledSwitch ──
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                StyledText {
                    text: Translation.tr("Home devices")
                    font.family: Appearance.font.family.title
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnSurfaceVariant
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.currentDevice?.name ?? Translation.tr("LED strip")
                    font.family: Appearance.font.family.title
                    font.pixelSize: 32
                    font.weight: Font.Black
                    font.variableAxes: ({ "wght": 900, "wdth": 100, "ROND": 100 })
                    color: Appearance.colors.colOnSurface
                    elide: Text.ElideRight
                }
            }

            StyledSwitch {
                checked: root.currentDevice?.is_on ?? false
                onToggled: {
                    if (root.currentDevice) {
                        SmartDevicesService.setDevicePower(root.currentDevice.id, checked);
                    }
                }
            }
        }

        // ── Hero Card: Shape Badge (Device Toggle) + Output Digits ────────────
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 160
            radius: 28
            color: Appearance.colors.colSurfaceContainer

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 20
                anchors.rightMargin: 20
                anchors.topMargin: 16
                anchors.bottomMargin: 16
                spacing: 20

                // 12-sided Flower Badge -> Clickable button that toggles THIS specific device!
                Item {
                    id: badgeButton
                    width: 96
                    height: 96
                    Layout.alignment: Qt.AlignVCenter

                    readonly property bool isOn: root.currentDevice?.is_on ?? false
                    readonly property color badgeColor: isOn
                        ? (root.isWhiteMode ? root.whitePreviewColor : root.activeDeviceColor)
                        : Appearance.colors.colSurfaceContainerHighest

                    scale: badgeMouse.pressed ? 0.90 : (badgeMouse.containsMouse ? 1.05 : 1.0)
                    Behavior on scale {
                        NumberAnimation { duration: 120 }
                    }

                    MaterialShape {
                        anchors.fill: parent
                        shape: MaterialShape.Shape.Cookie12Sided
                        color: badgeButton.badgeColor

                        Behavior on color {
                            ColorAnimation { duration: 180 }
                        }
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: !badgeButton.isOn ? "power_settings_new" : (root.isSocket ? "outlet" : (root.isSwitch ? "power" : (root.isWhiteMode ? "wb_sunny" : "lightbulb")))
                        iconSize: 42
                        color: badgeButton.isOn ? root.badgeIconColor(badgeButton.badgeColor) : Appearance.colors.colOnSurfaceVariant

                        Behavior on color {
                            ColorAnimation { duration: 180 }
                        }
                    }

                    MouseArea {
                        id: badgeMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (root.currentDevice) {
                                SmartDevicesService.setDevicePower(root.currentDevice.id, !root.currentDevice.is_on);
                            }
                        }
                    }

                    StyledToolTip {
                        text: root.currentDevice?.is_on
                            ? Translation.tr("Turn off %1").arg(root.currentDevice?.name ?? Translation.tr("device"))
                            : Translation.tr("Turn on %1").arg(root.currentDevice?.name ?? Translation.tr("device"))
                    }
                }

                // Text Stack (All lines left-aligned, standard high-contrast surface text)
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 2

                    StyledText {
                        text: root.isLighting ? Translation.tr("Output") : Translation.tr("Status")
                        font.family: Appearance.font.family.main
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnSurfaceVariant
                    }

                    RowLayout {
                        spacing: 2

                        StyledText {
                            text: root.isLighting
                                ? `${root.currentDevice?.brightness ?? 80}`
                                : (root.currentDevice?.is_on ? Translation.tr("ON") : Translation.tr("OFF"))
                            font.family: Appearance.font.family.main
                            font.pixelSize: root.isLighting ? 64 : 44
                            font.variableAxes: ({ "wght": 850, "wdth": 40, "ROND": 100 })
                            color: Appearance.colors.colOnSurface
                        }

                        StyledText {
                            visible: root.isLighting
                            text: "%"
                            font.family: Appearance.font.family.main
                            font.pixelSize: 26
                            font.weight: Font.Bold
                            Layout.alignment: Qt.AlignBottom
                            Layout.bottomMargin: 10
                            color: Appearance.colors.colOnSurface
                        }
                    }

                    StyledText {
                        font.family: Appearance.font.family.main
                        font.pixelSize: 14
                        font.italic: true
                        color: Appearance.colors.colOnSurfaceVariant
                        text: {
                            if (!root.isLighting) {
                                return root.isSocket ? Translation.tr("Smart Socket · 220V") : Translation.tr("Smart Switch · Local Network");
                            }
                            return root.isWhiteMode
                                ? `${Translation.tr("Whites")} · ${(root.currentDevice?.temperature ?? 4000)}K`
                                : `${Translation.tr("Colour")} · ${(root.currentDevice?.hue ?? 256)}° · ${root.currentDevice?.saturation ?? 100}%`;
                        }
                    }
                }
            }
        }

        // ── Segmented Mode Switcher ("Colour" | "Whites") (Lighting Only) ───────
        Rectangle {
            visible: root.isLighting
            Layout.fillWidth: true
            implicitHeight: 48
            radius: Appearance.rounding.full
            color: Appearance.colors.colSurfaceContainerHighest

            RowLayout {
                anchors.fill: parent
                anchors.margins: 4
                spacing: 4

                // Colour Tab
                RippleButton {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    buttonRadius: Appearance.rounding.full
                    colBackground: !root.isWhiteMode ? Appearance.colors.colPrimaryContainer : "transparent"
                    colBackgroundHover: !root.isWhiteMode ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colLayer1Hover
                    colRipple: !root.isWhiteMode ? Appearance.colors.colPrimaryContainerActive : Appearance.colors.colLayer1Active

                    contentItem: StyledText {
                        text: Translation.tr("Colour")
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font.family: Appearance.font.family.main
                        font.pixelSize: 15
                        font.weight: !root.isWhiteMode ? Font.Black : Font.DemiBold
                        color: !root.isWhiteMode ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurfaceVariant
                    }

                    onClicked: {
                        if (root.currentDevice && root.isWhiteMode) {
                            SmartDevicesService.setDeviceColourHsv(
                                root.currentDevice.id,
                                root.currentDevice.hue ?? 256,
                                root.currentDevice.saturation ?? 100,
                                root.currentDevice.brightness ?? 80,
                                root.currentDevice.hex_color || "#4400FF"
                            );
                        }
                    }
                }

                // Whites Tab
                RippleButton {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    buttonRadius: Appearance.rounding.full
                    colBackground: root.isWhiteMode ? Appearance.colors.colPrimaryContainer : "transparent"
                    colBackgroundHover: root.isWhiteMode ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colLayer1Hover
                    colRipple: root.isWhiteMode ? Appearance.colors.colPrimaryContainerActive : Appearance.colors.colLayer1Active

                    contentItem: StyledText {
                        text: Translation.tr("Whites")
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font.family: Appearance.font.family.main
                        font.pixelSize: 15
                        font.weight: root.isWhiteMode ? Font.Black : Font.DemiBold
                        color: root.isWhiteMode ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurfaceVariant
                    }

                    onClicked: {
                        if (root.currentDevice && !root.isWhiteMode) {
                            SmartDevicesService.setDeviceWhite(
                                root.currentDevice.id,
                                root.currentDevice.brightness ?? 80,
                                root.currentDevice.temperature ?? 4000
                            );
                        }
                    }
                }
            }
        }

        // ══════════════════════════════════════════════════════════════════════
        // WHITES MODE CONTROLS (Lighting Only)
        // ══════════════════════════════════════════════════════════════════════
        ColumnLayout {
            visible: root.isLighting && root.isWhiteMode
            Layout.fillWidth: true
            spacing: 14

            // Temperature Slider (Gradient from amber to cool white)
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                RowLayout {
                    Layout.fillWidth: true

                    StyledText {
                        text: Translation.tr("Temperature")
                        font.family: Appearance.font.family.title
                        font.pixelSize: 15
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnSurface
                    }

                    Item { Layout.fillWidth: true }

                    StyledText {
                        text: `${Math.round(tempSlider.value)}K`
                        font.family: Appearance.font.family.main
                        font.pixelSize: 16
                        font.weight: Font.Bold
                        font.italic: true
                        color: Appearance.colors.colOnSurface
                    }
                }

                GradientStyledSlider {
                    id: tempSlider
                    Layout.fillWidth: true
                    from: 2700
                    to: 6500
                    value: root.currentDevice?.temperature ?? 4000
                    trackGradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.00; color: "#FF9800" }
                        GradientStop { position: 0.45; color: "#FFF3E0" }
                        GradientStop { position: 1.00; color: "#90CAF9" }
                    }
                    onMoved: {
                        if (root.currentDevice) {
                            SmartDevicesService.setDeviceWhite(root.currentDevice.id, root.currentDevice.brightness ?? 80, Math.round(value));
                        }
                    }
                }
            }

            // Presets: Warm / Neutral / Cool
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                readonly property int curTemp: root.currentDevice?.temperature ?? 4000

                function isPresetActive(targetK) {
                    return Math.abs(curTemp - targetK) < 550;
                }

                // Warm preset (2700K)
                RippleButton {
                    Layout.fillWidth: true
                    implicitHeight: 40
                    buttonRadius: Appearance.rounding.full
                    colBackground: parent.isPresetActive(2700) ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSurfaceContainerHighest
                    colBackgroundHover: parent.isPresetActive(2700) ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colSurfaceContainerHighestHover
                    colRipple: parent.isPresetActive(2700) ? Appearance.colors.colPrimaryContainerActive : Appearance.colors.colSurfaceContainerHighestActive

                    contentItem: StyledText {
                        text: Translation.tr("Warm")
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font.family: Appearance.font.family.main
                        font.pixelSize: 14
                        font.weight: parent.parent.isPresetActive(2700) ? Font.Black : Font.DemiBold
                        color: parent.parent.isPresetActive(2700) ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurface
                    }

                    onClicked: {
                        if (root.currentDevice) {
                            SmartDevicesService.setDeviceWhite(root.currentDevice.id, root.currentDevice.brightness ?? 80, 2700);
                        }
                    }
                }

                // Neutral preset (4000K)
                RippleButton {
                    Layout.fillWidth: true
                    implicitHeight: 40
                    buttonRadius: Appearance.rounding.full
                    colBackground: parent.isPresetActive(4000) ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSurfaceContainerHighest
                    colBackgroundHover: parent.isPresetActive(4000) ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colSurfaceContainerHighestHover
                    colRipple: parent.isPresetActive(4000) ? Appearance.colors.colPrimaryContainerActive : Appearance.colors.colSurfaceContainerHighestActive

                    contentItem: StyledText {
                        text: Translation.tr("Neutral")
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font.family: Appearance.font.family.main
                        font.pixelSize: 14
                        font.weight: parent.parent.isPresetActive(4000) ? Font.Black : Font.DemiBold
                        color: parent.parent.isPresetActive(4000) ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurface
                    }

                    onClicked: {
                        if (root.currentDevice) {
                            SmartDevicesService.setDeviceWhite(root.currentDevice.id, root.currentDevice.brightness ?? 80, 4000);
                        }
                    }
                }

                // Cool preset (6500K)
                RippleButton {
                    Layout.fillWidth: true
                    implicitHeight: 40
                    buttonRadius: Appearance.rounding.full
                    colBackground: parent.isPresetActive(6500) ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSurfaceContainerHighest
                    colBackgroundHover: parent.isPresetActive(6500) ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colSurfaceContainerHighestHover
                    colRipple: parent.isPresetActive(6500) ? Appearance.colors.colPrimaryContainerActive : Appearance.colors.colSurfaceContainerHighestActive

                    contentItem: StyledText {
                        text: Translation.tr("Cool")
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font.family: Appearance.font.family.main
                        font.pixelSize: 14
                        font.weight: parent.parent.isPresetActive(6500) ? Font.Black : Font.DemiBold
                        color: parent.parent.isPresetActive(6500) ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurface
                    }

                    onClicked: {
                        if (root.currentDevice) {
                            SmartDevicesService.setDeviceWhite(root.currentDevice.id, root.currentDevice.brightness ?? 80, 6500);
                        }
                    }
                }
            }

            // Brightness Slider (StyledSlider with white temperature color)
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                RowLayout {
                    Layout.fillWidth: true

                    StyledText {
                        text: Translation.tr("Brightness")
                        font.family: Appearance.font.family.title
                        font.pixelSize: 15
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnSurface
                    }

                    Item { Layout.fillWidth: true }

                    StyledText {
                        text: `${Math.round(brightWhiteSlider.value)}%`
                        font.family: Appearance.font.family.main
                        font.pixelSize: 16
                        font.weight: Font.Bold
                        font.italic: true
                        color: Appearance.colors.colOnSurface
                    }
                }

                StyledSlider {
                    id: brightWhiteSlider
                    Layout.fillWidth: true
                    configuration: StyledSlider.Configuration.L
                    stopIndicatorValues: []
                    highlightColor: root.whitePreviewColor
                    trackColor: Appearance.colors.colSurfaceContainerHighest
                    from: 1
                    to: 100
                    value: root.currentDevice?.brightness ?? 80
                    onMoved: {
                        if (root.currentDevice) {
                            SmartDevicesService.setDeviceWhite(
                                root.currentDevice.id,
                                Math.round(value),
                                root.currentDevice.temperature ?? 4000
                            );
                        }
                    }
                }
            }
        }

        // ══════════════════════════════════════════════════════════════════════
        // COLOUR MODE CONTROLS (Lighting Only)
        // ══════════════════════════════════════════════════════════════════════
        ColumnLayout {
            visible: root.isLighting && !root.isWhiteMode
            Layout.fillWidth: true
            spacing: 14

            // 1. Hue Slider (Full Rainbow Spectrum across filled and unfilled tracks)
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                RowLayout {
                    Layout.fillWidth: true

                    StyledText {
                        text: Translation.tr("Hue")
                        font.family: Appearance.font.family.title
                        font.pixelSize: 15
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnSurface
                    }

                    Item { Layout.fillWidth: true }

                    StyledText {
                        text: `${Math.round(hueSlider.value)}°`
                        font.family: Appearance.font.family.main
                        font.pixelSize: 16
                        font.weight: Font.Bold
                        font.italic: true
                        color: Appearance.colors.colOnSurface
                    }
                }

                GradientStyledSlider {
                    id: hueSlider
                    Layout.fillWidth: true
                    from: 0
                    to: 360
                    value: root.currentDevice?.hue ?? 256
                    trackGradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.00; color: "#FF3142" }
                        GradientStop { position: 0.17; color: "#FF9431" }
                        GradientStop { position: 0.33; color: "#31F673" }
                        GradientStop { position: 0.50; color: "#31D6F6" }
                        GradientStop { position: 0.67; color: "#5231F6" }
                        GradientStop { position: 0.83; color: "#F631D6" }
                        GradientStop { position: 1.00; color: "#FF3142" }
                    }
                    onMoved: {
                        if (root.currentDevice) {
                            const hue = Math.round(value) % 360;
                            const hex = SmartDevicesService.hsvToHex(hue, root.currentDevice.saturation ?? 100, root.currentDevice.brightness ?? 80);
                            SmartDevicesService.setDeviceColourHsv(
                                root.currentDevice.id,
                                hue,
                                root.currentDevice.saturation ?? 100,
                                root.currentDevice.brightness ?? 80,
                                hex
                            );
                        }
                    }
                }
            }

            // 2. Saturation Slider (From white/desaturated to pure hue color)
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                RowLayout {
                    Layout.fillWidth: true

                    StyledText {
                        text: Translation.tr("Saturation")
                        font.family: Appearance.font.family.title
                        font.pixelSize: 15
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnSurface
                    }

                    Item { Layout.fillWidth: true }

                    StyledText {
                        text: `${Math.round(satSlider.value)}%`
                        font.family: Appearance.font.family.main
                        font.pixelSize: 16
                        font.weight: Font.Bold
                        font.italic: true
                        color: Appearance.colors.colOnSurface
                    }
                }

                GradientStyledSlider {
                    id: satSlider
                    Layout.fillWidth: true
                    from: 0
                    to: 100
                    value: root.currentDevice?.saturation ?? 100
                    trackGradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.00; color: "#FFFFFF" }
                        GradientStop { position: 1.00; color: root.pureHueColor }
                    }
                    onMoved: {
                        if (root.currentDevice) {
                            const sat = Math.round(value);
                            const hex = SmartDevicesService.hsvToHex(root.currentDevice.hue ?? 256, sat, root.currentDevice.brightness ?? 80);
                            SmartDevicesService.setDeviceColourHsv(
                                root.currentDevice.id,
                                root.currentDevice.hue ?? 256,
                                sat,
                                root.currentDevice.brightness ?? 80,
                                hex
                            );
                        }
                    }
                }
            }

            // 3. Preset Color Dots (Red, Orange, Green, Cyan, Blue, Magenta)
            RowLayout {
                Layout.fillWidth: true
                spacing: 0

                readonly property var palette: [
                    { name: "red", hex: "#F63142", hue: 350 },
                    { name: "orange", hex: "#F69431", hue: 34 },
                    { name: "green", hex: "#31F673", hue: 142 },
                    { name: "cyan", hex: "#31D6F6", hue: 185 },
                    { name: "blue", hex: "#5231F6", hue: 236 },
                    { name: "magenta", hex: "#F631D6", hue: 310 }
                ]

                Repeater {
                    model: parent.palette
                    delegate: Item {
                        Layout.fillWidth: true
                        implicitHeight: 44

                        Rectangle {
                            id: dot
                            width: 38
                            height: 38
                            radius: 19
                            anchors.centerIn: parent
                            color: modelData.hex

                            readonly property bool isSelected: Math.abs((root.currentDevice?.hue ?? 256) - modelData.hue) < 18

                            border.width: isSelected ? 3 : 0
                            border.color: Appearance.colors.colOnSurface

                            scale: dotMouse.pressed ? 0.90 : (dotMouse.containsMouse ? 1.08 : 1.0)
                            Behavior on scale {
                                NumberAnimation { duration: 120 }
                            }

                            MouseArea {
                                id: dotMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.currentDevice) {
                                        SmartDevicesService.setDeviceColourHsv(
                                            root.currentDevice.id,
                                            modelData.hue,
                                            100,
                                            root.currentDevice.brightness ?? 80,
                                            modelData.hex
                                        );
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // 4. Brightness Slider (StyledSlider using current LED color!)
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                RowLayout {
                    Layout.fillWidth: true

                    StyledText {
                        text: Translation.tr("Brightness")
                        font.family: Appearance.font.family.title
                        font.pixelSize: 15
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnSurface
                    }

                    Item { Layout.fillWidth: true }

                    StyledText {
                        text: `${Math.round(brightColourSlider.value)}%`
                        font.family: Appearance.font.family.main
                        font.pixelSize: 16
                        font.weight: Font.Bold
                        font.italic: true
                        color: Appearance.colors.colOnSurface
                    }
                }

                StyledSlider {
                    id: brightColourSlider
                    Layout.fillWidth: true
                    configuration: StyledSlider.Configuration.L
                    stopIndicatorValues: []
                    highlightColor: root.activeDeviceColor
                    trackColor: Appearance.colors.colSurfaceContainerHighest
                    from: 1
                    to: 100
                    value: root.currentDevice?.brightness ?? 80
                    onMoved: {
                        if (root.currentDevice) {
                            const bright = Math.round(value);
                            const hex = SmartDevicesService.hsvToHex(
                                root.currentDevice.hue ?? 256,
                                root.currentDevice.saturation ?? 100,
                                bright
                            );
                            SmartDevicesService.setDeviceColourHsv(
                                root.currentDevice.id,
                                root.currentDevice.hue ?? 256,
                                root.currentDevice.saturation ?? 100,
                                bright,
                                hex
                            );
                        }
                    }
                }
            }
        }

        // ══════════════════════════════════════════════════════════════════════
        // SOCKET / SWITCH CONTROLS (Non-Lighting Devices: cz, kg)
        // ══════════════════════════════════════════════════════════════════════
        ColumnLayout {
            visible: !root.isLighting
            Layout.fillWidth: true
            spacing: 12

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: socketCol.implicitHeight + 32
                radius: 24
                color: Appearance.colors.colSurfaceContainer

                ColumnLayout {
                    id: socketCol
                    anchors {
                        left: parent.left
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        margins: 16
                    }
                    spacing: 14

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        MaterialSymbol {
                            text: root.currentDevice?.is_on ? "check_circle" : "power_settings_new"
                            iconSize: 24
                            color: root.currentDevice?.is_on ? Appearance.colors.colPrimary : Appearance.colors.colOutline
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            StyledText {
                                text: root.currentDevice?.is_on ? Translation.tr("Device Active") : Translation.tr("Device Standby")
                                font.family: Appearance.font.family.title
                                font.pixelSize: 15
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnSurface
                            }
                            StyledText {
                                text: root.currentDevice?.ip ? `${Translation.tr("Local IP")}: ${root.currentDevice.ip}` : Translation.tr("Connected via TinyTuya local protocol")
                                font.pixelSize: 12
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                        }
                    }

                    RippleButton {
                        Layout.fillWidth: true
                        implicitHeight: 44
                        buttonRadius: 22
                        colBackground: root.currentDevice?.is_on ? Appearance.colors.colPrimary : Appearance.colors.colSurfaceContainerHighest
                        colBackgroundHover: root.currentDevice?.is_on ? Appearance.colors.colPrimaryHover : Appearance.colors.colSurfaceContainerHighestHover
                        colRipple: root.currentDevice?.is_on ? Appearance.colors.colPrimaryActive : Appearance.colors.colSurfaceContainerHighestActive

                        contentItem: StyledText {
                            text: root.currentDevice?.is_on
                                ? Translation.tr("Turn Off Device")
                                : Translation.tr("Turn On Device")
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            font.family: Appearance.font.family.main
                            font.pixelSize: 14
                            font.weight: Font.Bold
                            color: root.currentDevice?.is_on ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurface
                        }
                        onClicked: {
                            if (root.currentDevice) {
                                SmartDevicesService.setDevicePower(root.currentDevice.id, !root.currentDevice.is_on);
                            }
                        }
                    }
                }
            }
        }

        // ── Bottom Navigation / Done Button Row ───────────────────────────────
        WindowDialogButtonRow {
            Layout.leftMargin: 0
            Layout.rightMargin: 0
            Layout.bottomMargin: -8

            // Pagination (shown only if > 1 device)
            RowLayout {
                visible: SmartDevicesService.deviceCount > 1
                spacing: 6

                Item {
                    width: 36
                    height: 36
                    Rectangle {
                        anchors.fill: parent
                        radius: 18
                        color: Appearance.colors.colSurfaceContainerHighest
                    }
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "chevron_left"
                        iconSize: 20
                        color: root.currentDeviceIndex > 0 ? Appearance.colors.colOnSurface : Appearance.colors.colOutline
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: root.currentDeviceIndex > 0
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            if (root.currentDeviceIndex > 0) {
                                root.currentDeviceIndex--;
                            }
                        }
                    }
                }

                StyledText {
                    text: `${root.currentDeviceIndex + 1} / ${SmartDevicesService.deviceCount}`
                    font.family: Appearance.font.family.main
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnSurfaceVariant
                }

                Item {
                    width: 36
                    height: 36
                    Rectangle {
                        anchors.fill: parent
                        radius: 18
                        color: Appearance.colors.colSurfaceContainerHighest
                    }
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "chevron_right"
                        iconSize: 20
                        color: root.currentDeviceIndex < SmartDevicesService.deviceCount - 1 ? Appearance.colors.colOnSurface : Appearance.colors.colOutline
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: root.currentDeviceIndex < SmartDevicesService.deviceCount - 1
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            if (root.currentDeviceIndex < SmartDevicesService.deviceCount - 1) {
                                root.currentDeviceIndex++;
                            }
                        }
                    }
                }
            }

            Item { Layout.fillWidth: true }

            // Done Button using standard RippleButton matching VolumeDialog/BluetoothDialog
            RippleButton {
                id: doneBtn
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                colRipple: Appearance.colors.colPrimaryActive
                implicitHeight: 36
                implicitWidth: doneText.implicitWidth + 48

                contentItem: StyledText {
                    id: doneText
                    text: Translation.tr("Done")
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.variableAxes: ({ "wght": 700 })
                    color: Appearance.colors.colOnPrimary
                }
                onClicked: root.dismiss()
            }
        }
    }
}
