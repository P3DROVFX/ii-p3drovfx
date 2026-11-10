pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.background.widgets

/*
 * Home (1x2): the smart lights (SmartDevicesService, the same devices as the
 * Smart Devices quick toggle) as a column of tiles. A lit tile fills from the
 * left to its brightness in the light's own colour - its hue, or the warmth
 * of its white - and its bulb's circle opens into a sun. A click switches a
 * light, the wheel dims it, and the − / + keys step it by a tenth. The header
 * switches everything at once. Clicks arrive through cardTapped and the wheel
 * never takes the press, so the widget still moves from anywhere.
 */
ExpressiveCardWidget {
    id: root

    configEntryName: "home_devices"
    designWidth: 240
    designHeight: 492

    readonly property real padding: 14
    readonly property var devices: SmartDevicesService.devices ?? []

    // What a light looks like right now: its hue at full value, or its white.
    function lightColor(device) {
        if (device?.mode === "white") {
            const t = Math.max(0, Math.min(1, ((device.temperature ?? 4000) - 2700) / (6500 - 2700)));
            return Qt.rgba(1 - 0.15 * t, 0.72 + 0.19 * t, 0.45 + 0.55 * t, 1);
        }
        return SmartDevicesService.hsvToHex(device?.hue ?? 0, device?.saturation ?? 100, 100);
    }
    function setBrightness(device, value) {
        const v = Math.max(1, Math.min(100, Math.round(value)));
        if (device.mode === "white")
            SmartDevicesService.setDeviceWhite(device.id, v, device.temperature ?? 4000);
        else
            SmartDevicesService.setDeviceColourHsv(device.id, device.hue ?? 0, device.saturation ?? 100, v, "");
    }

    onCardTapped: at => {
        const p = tiles.mapFromItem(root.contentItem, at.x, at.y);
        const tile = tiles.childAt(p.x, p.y);
        if (tile && tile.modelData !== undefined && tile.online)
            SmartDevicesService.toggleDevice(tile.modelData.id);
    }

    // ── Header ──
    Item {
        id: header
        x: root.padding
        y: root.padding
        width: root.designWidth - root.padding * 2
        height: 46

        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: -2

            StyledText {
                text: Translation.tr("Home")
                color: WidgetColorScheme.textColorOnBg
                font.family: Appearance.font.family.title
                font.pixelSize: Appearance.font.pixelSize.huge
                font.variableAxes: Appearance.font.variableAxes.titleRounded
            }
            StyledText {
                text: SmartDevicesService.hasDevices
                    ? Translation.tr("%1 of %2 on").arg(SmartDevicesService.onCount).arg(SmartDevicesService.deviceCount)
                    : Translation.tr("No devices")
                color: WidgetColorScheme.subtextColorOnBg
                font.family: Appearance.font.family.main
                font.pixelSize: 12
                font.variableAxes: ({ "wght": 500, "wdth": 100, "slnt": -10, "ROND": 100 })
            }
        }

        WidgetButton {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: SmartDevicesService.hasDevices
            width: 44
            height: 44
            symbol: "power_settings_new"
            symbolSize: 22
            colFill: SmartDevicesService.anyDeviceOn ? WidgetColorScheme.accentColor : WidgetColorScheme.pillBgColor
            colContent: SmartDevicesService.anyDeviceOn ? WidgetColorScheme.onAccentColor : WidgetColorScheme.textColorOnBg
            restRadius: SmartDevicesService.anyDeviceOn ? Appearance.rounding.normal : root.pill(height)
            onClicked: if (root.actionsEnabled) SmartDevicesService.toggleAll()
        }
    }

    // ── Lights ──
    Flickable {
        id: list
        x: root.padding
        anchors.top: header.bottom
        anchors.topMargin: 12
        width: root.designWidth - root.padding * 2
        height: root.designHeight - list.y - root.padding
        clip: true
        contentWidth: width
        contentHeight: tiles.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
            id: tiles
            width: list.width
            spacing: 8

            Repeater {
                model: root.devices

                delegate: Rectangle {
                    id: tile
                    required property var modelData
                    readonly property bool on: tile.modelData.is_on === true
                    readonly property bool online: tile.modelData.online !== false
                    readonly property color light: root.lightColor(tile.modelData)
                    readonly property real level: Math.max(0, Math.min(1, (tile.modelData.brightness ?? 0) / 100))
                    // A tall tile is a column of light filling from its foot.
                    readonly property bool column: tile.height > tile.width * 1.1
                    width: tiles.width
                    // The lights share the column; a long list scrolls.
                    height: Math.max(88, (list.height - tiles.spacing * (root.devices.length - 1)) / Math.max(1, root.devices.length))
                    radius: Appearance.rounding.large
                    color: WidgetColorScheme.pillBgColor
                    opacity: tile.online ? 1 : 0.5
                    clip: true

                    WheelHandler {
                        enabled: root.actionsEnabled && tile.on
                        onWheel: event => root.setBrightness(tile.modelData, (tile.modelData.brightness ?? 0) + (event.angleDelta.y > 0 ? 5 : -5))
                    }

                    // The brightness, in the light's colour.
                    Rectangle {
                        y: tile.column ? tile.height - height : 0
                        width: tile.column ? tile.width : (tile.on ? Math.max(tile.radius * 2, tile.width * tile.level) : 0)
                        height: tile.column ? (tile.on ? Math.max(tile.radius * 2, tile.height * tile.level) : 0) : tile.height
                        radius: tile.radius
                        color: tile.light
                        Behavior on width {
                            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                        }
                        Behavior on height {
                            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                        }
                    }

                    Item {
                        id: bulb
                        x: 14
                        y: 14
                        width: 40
                        height: 40

                        MaterialShape {
                            anchors.fill: parent
                            shapeString: tile.on ? "Sunny" : "Circle"
                            color: tile.on ? root.contentOn(tile.light) : WidgetColorScheme.cardBgColor
                        }
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: tile.on ? "lightbulb" : "light_off"
                            iconSize: 20
                            fill: tile.on ? 1 : 0
                            color: tile.on ? tile.light : WidgetColorScheme.subtextColorOnBg
                        }
                    }

                    StyledText {
                        id: nameText
                        anchors.left: bulb.right
                        anchors.leftMargin: 10
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: bulb.verticalCenter
                        elide: Text.ElideRight
                        text: String(tile.modelData.name ?? "")
                        color: tile.on && (tile.column ? tile.level > 0.85 : tile.level > 0.45) ? root.contentOn(tile.light) : WidgetColorScheme.textColorOnBg
                        font.family: Appearance.font.family.main
                        font.pixelSize: 14
                        font.variableAxes: ({ "wght": 700, "wdth": 90, "ROND": 100 })
                    }

                    StyledText {
                        x: 14
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 8
                        text: !tile.online ? Translation.tr("Offline") : tile.on ? Math.round(tile.level * 100) + "%" : Translation.tr("Off")
                        color: tile.on && tile.level > 0.25 ? root.contentOn(tile.light) : WidgetColorScheme.subtextColorOnBg
                        font.family: Appearance.font.family.main
                        font.pixelSize: tile.on ? (tile.column ? 64 : 30) : 16
                        font.variableAxes: tile.on ? ({ "wght": 780, "wdth": 60, "ROND": 100 })
                                                   : ({ "wght": 450, "wdth": 100, "slnt": -10, "ROND": 100 })
                    }

                    Row {
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 10
                        spacing: 4
                        visible: tile.on

                        Repeater {
                            model: [{ symbol: "remove", step: -10 }, { symbol: "add", step: 10 }]
                            delegate: WidgetButton {
                                required property var modelData
                                width: 32
                                height: 32
                                symbol: modelData.symbol
                                symbolSize: 16
                                colFill: WidgetColorScheme.cardBgColor
                                colContent: WidgetColorScheme.textColorOnBg
                                onClicked: if (root.actionsEnabled) root.setBrightness(tile.modelData, (tile.modelData.brightness ?? 0) + modelData.step)
                            }
                        }
                    }
                }
            }
        }
    }

    Column {
        visible: !SmartDevicesService.hasDevices
        anchors.centerIn: parent
        width: root.designWidth - root.padding * 2
        spacing: 8

        MaterialSymbol {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "home_iot_device"
            iconSize: 44
            color: WidgetColorScheme.subtextColorOnBg
        }
        StyledText {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: Translation.tr("Set up your lights in the Smart Devices quick toggle")
            color: WidgetColorScheme.subtextColorOnBg
            font.family: Appearance.font.family.main
            font.pixelSize: Appearance.font.pixelSize.small
        }
    }
}
