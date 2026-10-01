import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Widgets
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.utils
import qs.modules.common.functions
import "./widgets"

Item {
    id: root

    property bool isVertical: false
    property var dockContent: null
    property int delegateIndex: -1

    readonly property real buttonSize: Appearance.sizes.dockButtonSize
    readonly property real dotMargin: root.dockContent?.dotMargin ?? Math.max(1, Math.round((Config.options?.dock.height ?? 60) * 0.2) - 2)
    readonly property real dotMarginV: root.dockContent?.dotMarginV ?? root.dotMargin
    readonly property real slotSize: root.dockContent?.buttonSlotSize ?? (buttonSize + dotMargin * 2)
    readonly property real slotHeight: root.dockContent
        ? (root.isVertical ? root.dockContent.buttonSlotSize : root.dockContent.buttonSlotHeight)
        : (buttonSize + dotMarginV * 2)
    readonly property real fixedSlots: isVertical ? 2.5 : 3
    readonly property real fixedLength: fixedSlots * slotSize

    implicitWidth: root.isVertical ? root.slotSize : root.fixedLength
    implicitHeight: root.isVertical ? root.slotSize : root.slotHeight
    // Magnified with the icons, at the muted share the dock keeps for a widget
    // body: the delegate wrapper grows the slot by exactly the room this scale
    // needs, so the neighbours slide instead of being drawn over.
    readonly property real contentMagnification: root.dockContent ? root.dockContent._getSlotMagScale(root) : 1.0
    scale: root.contentMagnification
    transformOrigin: root.dockContent?.magnificationTransformOrigin ?? Item.Bottom

    // ── Drag overlay (reorder support) ─────────────────────────────────────
    MouseArea {
        id: dragOverlay
        anchors.fill: parent
        z: 10
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton | Qt.BackButton | Qt.ForwardButton
        preventStealing: true
        cursorShape: Qt.PointingHandCursor
        hoverEnabled: true
        property real pressCoord: 0
        property bool dragActive: false

        onEntered: {
            root.weatherHovered = true;
            if (root.dockContent)
                root.dockContent.onButtonEntered(root);
        }
        onExited: {
            root.weatherHovered = false;
            if (root.dockContent)
                root.dockContent.onButtonExited(root);
        }

        onPressed: (event) => {
            if (event.button === Qt.LeftButton) {
                pressCoord = root.isVertical ? event.y : event.x
            }
        }
        onPositionChanged: (event) => {
            if (!pressed) return
            var cur = root.isVertical ? event.y : event.x
            var dist = Math.abs(cur - pressCoord)
            if (!dragActive && dist > 5 && root.delegateIndex >= 0) {
                dragActive = true
                if (root.dockContent) {
                    root.dockContent.startItemDrag(root.delegateIndex, dragOverlay, event.x, event.y)
                }
            }
            if (dragActive) {
                if (root.dockContent) root.dockContent.moveItemDrag(dragOverlay, event.x, event.y)
            }
        }
        onReleased: (event) => {
            if (dragActive) {
                dragActive = false
                if (root.dockContent) root.dockContent.endItemDrag()
            }
        }
        onCanceled: {
            if (dragActive) {
                dragActive = false
                if (root.dockContent) root.dockContent.cancelDrag()
            }
        }
    }

    DockTooltip {
        id: weatherTooltip
        parentItem: root
        text: root.weatherDesc + " · " + root.cityName
        showTooltip: dragOverlay.containsMouse
        tooltipOffset: -root.dotMargin
    }

    property bool weatherHovered: false

    readonly property string cityName: Weather.data?.city || "Unknown"
    readonly property string weatherDesc: Weather.data?.wDesc || "Unknown"
    readonly property string temperature: (Weather.data?.temp || "--").replace(/[^-0-9]/g, "") + "°"

    function get3DWeatherIconName(wCode) {
        let iconName = Icons.getWeatherIcon(wCode);
        if(!iconName) return "clouds.png";
        switch(iconName) {
            case "clear_day": return "sun.png";
            case "partly_cloudy_day": return "sun-clouds.png";
            case "cloud": 
            case "foggy": return "clouds.png";
            case "rainy": 
            case "weather_hail": return "sun-clouds-rain.png";
            case "thunderstorm": return "lightning.png";
            case "cloudy_snowing":
            case "snowing_heavy":
            case "snowing": return "clouds-snow.png";
            default: return "clouds.png";
        }
    }

    readonly property string iconFileName: get3DWeatherIconName(Weather.data?.wCode)
    readonly property bool isSunny: iconFileName === "sun.png" || iconFileName === "sun-clouds.png"
    readonly property bool isNight: {
        const hour = DateTime.clock.date.getHours();
        return hour >= 18 || hour < 6;
    }

    function getGradientColor(position) {
        if (root.isSunny) {
            if (root.isNight) {
                return position === 0 ? "#1a2a44" : "#0d1526"; // Dark Night Blue
            }
            return position === 0 ? "#2e8fd3" : "#2764b1"; // Day Blue
        } else {
            if (root.isNight) {
                return position === 0 ? "#37474f" : "#263238"; // Dark Grey
            }
            return position === 0 ? "#a1a1a1" : "#6b6b6b"; // Day Grey
        }
    }
    
    Rectangle {
        id: bgRect
        anchors.fill: parent
        anchors.leftMargin: root.dotMargin
        anchors.rightMargin: root.dotMargin
        anchors.topMargin: root.dotMarginV
        anchors.bottomMargin: root.dotMarginV
        radius: (Config.options?.dock?.widgetRadius ?? -1) >= 0 ? Config.options.dock.widgetRadius : (Appearance.rounding.windowRounding + 12)
        clip: true

        // Ensure children like the weather icon are properly clipped by the radius
        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: bgRect.width
                height: bgRect.height
                radius: bgRect.radius
            }
        }

        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: getGradientColor(0) }
            GradientStop { position: 1.0; color: getGradientColor(1) }
        }

        Loader {
            active: !root.isVertical
            anchors.fill: parent
            sourceComponent: Item {
                anchors.fill: parent

                ColumnLayout {
                    id: infoColumn
                    anchors.left: parent.left
                    anchors.leftMargin: root.dotMargin + 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    // Constrain width to leave room for temperature + icon
                    width: Math.max(1, root.fixedLength - root.buttonSize * 1.5 - root.dotMargin * 3 - 8)
                    clip: true

                    StyledText {
                        Layout.fillWidth: true
                        text: root.weatherDesc
                        font.pixelSize: Math.round(root.buttonSize * 0.28)
                        font.weight: Font.DemiBold
                        color: "white"
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.cityName
                        font.pixelSize: Math.round(root.buttonSize * 0.24)
                        font.weight: Font.Normal
                        color: "white"
                        opacity: 0.8
                        elide: Text.ElideRight
                    }
                }
                
                StyledText {
                    anchors.right: parent.right
                    anchors.rightMargin: iconImg.width * 0.6
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.temperature
                    font.pixelSize: Math.round(root.buttonSize * 0.6)
                    font.weight: Font.Light
                    color: "white"
                }

                // Weather icon hover interaction: sits further right, slides left on hover
                readonly property real _weatherIconWidth: root.buttonSize * 1.3
                readonly property real _weatherIconBaseMargin: -(_weatherIconWidth * 0.25 + 6)
                readonly property real _weatherIconHoverMargin: _weatherIconBaseMargin + 6

                Image {
                    id: iconImg
                    source: "file://" + Directories.assetsPath + "/icons/weather/" + root.iconFileName
                    width: parent._weatherIconWidth
                    height: parent._weatherIconWidth
                    anchors.right: parent.right
                    anchors.rightMargin: root.weatherHovered ? parent._weatherIconHoverMargin : parent._weatherIconBaseMargin
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: height * 0.25
                    sourceSize: Qt.size(width * 2, height * 2)
                    smooth: true
                    antialiasing: true

                    Behavior on anchors.rightMargin {
                        NumberAnimation {
                            duration: 700
                            easing.type: Easing.InOutCubic
                        }
                    }
                }
            }
        }

        Loader {
            active: root.isVertical
            anchors.fill: parent
            sourceComponent: Item {
                anchors.fill: parent
                StyledText {
                    anchors.centerIn: parent
                    text: root.temperature
                    font.pixelSize: Math.round(root.buttonSize * 0.45)
                    font.weight: Font.Bold
                    color: "white"
                }
            }
        }
    }
}
