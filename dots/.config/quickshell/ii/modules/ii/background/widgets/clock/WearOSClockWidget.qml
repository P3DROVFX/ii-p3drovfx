import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import QtQuick.Shapes as Shapes
import qs
import qs.services
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

AbstractBackgroundWidget {
    id: root

    configEntryName: "wearos_clock"

    visibleWhenLocked: root.lockBehavior === "keep" || root.lockBehavior === "center" || root.lockBehavior === "lockOnly" || (Config.options.lock.centerWidget === "clock")

    // Default size is 240x240 for 1:1 widgets as per AGENTS.md guidelines
    readonly property real contentScale: (Config.options.background.widgets.wearos_clock.widgetSize ?? 100) / 100.0
    implicitWidth: 240 * contentScale
    implicitHeight: 240 * contentScale

    // ── Config-driven visibility toggles (all default to current state = visible) ──
    readonly property bool cfgShowBezel: Config.ready ? (Config.options.background.widgets.wearos_clock.showBezelRing ?? true) : true
    readonly property bool cfgShowOuterNums: Config.ready ? (Config.options.background.widgets.wearos_clock.showOuterNumbers ?? true) : true
    readonly property bool cfgShowInnerNums: Config.ready ? (Config.options.background.widgets.wearos_clock.showInnerNumbers ?? true) : true
    readonly property bool cfgShowDistroLogo: Config.ready ? (Config.options.background.widgets.wearos_clock.showDistroLogo ?? true) : true
    readonly property bool cfgShowSunset: Config.ready ? (Config.options.background.widgets.wearos_clock.showSunsetComplication ?? true) : true
    readonly property bool cfgShowDigitalTime: Config.ready ? (Config.options.background.widgets.wearos_clock.showDigitalTimePill ?? true) : true
    readonly property bool cfgShowBattery: Config.ready ? (Config.options.background.widgets.wearos_clock.showBatteryPill ?? true) : true
    readonly property bool cfgShowHourDial: Config.ready ? (Config.options.background.widgets.wearos_clock.showHourSubDial ?? true) : true
    readonly property bool cfgShowBedtime: Config.ready ? (Config.options.background.widgets.wearos_clock.showBedtimeIcon ?? true) : true
    readonly property bool cfgShowKdeConnect: Config.ready ? (Config.options.background.widgets.wearos_clock.showKdeConnect ?? true) : true
    readonly property bool cfgShowDate: Config.ready ? (Config.options.background.widgets.wearos_clock.showDateComplication ?? true) : true
    readonly property bool cfgShowMinuteHand: Config.ready ? (Config.options.background.widgets.wearos_clock.showMinuteHand ?? true) : true

    // Smartwatch dials are always dark, so text and ticks must always be light/white for readability
    readonly property color activeTextColor: "#FFFFFF"
    readonly property color activeSubtextColor: "#A0A0A0"
    readonly property color activeAccentColor: Appearance.colors.colPrimary
    readonly property real r_inner: (implicitWidth * 0.96) * 0.37

    // Clock state properties
    property var currentTime: new Date()

    Timer {
        id: clockTimer
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            currentTime = new Date();
        }
    }

    // Time calculations
    readonly property int hour: currentTime.getHours()
    readonly property int minute: currentTime.getMinutes()
    readonly property int second: currentTime.getSeconds()
    readonly property int date: currentTime.getDate()
    readonly property string dayName: {
        const days = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"];
        return days[currentTime.getDay()];
    }

    // Hand rotations
    readonly property real hourRotation: ((hour % 12) * 30) + (minute * 0.5)
    readonly property real minuteRotation: (minute * 6) + (second * 0.1)

    // Outer bezel shadow support
    StyledDropShadow {
        id: outerBezelShadow
        target: bezelRing
        visible: (Config.options.background.widgets.wearos_clock.enableShadows ?? true) && (root.cfgShowBezel)
    }

    // Outer Bezel Ring (Moldura) using opaque solid colBackgroundSurfaceContainer base
    Rectangle {
        id: bezelRing
        anchors.fill: parent
        radius: width / 2
        color: WidgetColorScheme.tintBackground(Appearance.m3colors.m3shadow)
        clip: true
        opacity: root.cfgShowBezel ? 1.0 : 0.0

        Behavior on opacity {
            NumberAnimation {
                duration: 300
            }
        }

        // Inner Screen Container - margins reduced to 2% to move contents closer to the border
        Rectangle {
            id: innerScreen
            anchors.fill: parent
            anchors.margins: parent.width * 0.02
            radius: width / 2
            color: WidgetColorScheme.tintBackground(Appearance.m3colors.m3shadow)
            clip: true

            // Dial Canvas for rendering clock ticks and numbers
            Canvas {
                id: dialCanvas
                anchors.fill: parent
                z: 1
                contextType: "2d"

                onPaint: {
                    var ctx = getContext("2d");
                    ctx.reset();

                    var cx = width / 2;
                    var cy = height / 2;

                    // Draw outer ticks & numbers (00 to 58)
                    if (root.cfgShowOuterNums) {
                        ctx.save();
                        ctx.font = "bold " + Math.round(width * 0.034) + "px sans-serif";
                        ctx.fillStyle = root.activeSubtextColor;
                        ctx.textAlign = "center";
                        ctx.textBaseline = "middle";

                        var r_outer = width * 0.49;
                        var textR = r_outer - 10;
                        for (var i = 0; i < 30; i++) {
                            var val = i * 2;
                            var valStr = val < 10 ? "0" + val : "" + val;
                            var angle = -Math.PI / 2 + (i * Math.PI / 15);

                            // Draw outer numbers
                            ctx.fillText(valStr, cx + Math.cos(angle) * textR, cy + Math.sin(angle) * textR);

                            // Draw dot between this number and the next
                            var angle_mid = angle + (Math.PI / 30);
                            ctx.beginPath();
                            ctx.arc(cx + Math.cos(angle_mid) * textR, cy + Math.sin(angle_mid) * textR, 1.5, 0, 2 * Math.PI);
                            ctx.fillStyle = ColorUtils.applyAlpha(root.activeSubtextColor, 0.4);
                            ctx.fill();
                        }
                        ctx.restore();
                    }

                    // Draw inner numbers (05, 10, 20... 55)
                    if (root.cfgShowInnerNums) {
                        ctx.save();
                        ctx.font = "bold " + Math.round(width * 0.052) + "px sans-serif";
                        ctx.fillStyle = root.activeTextColor;
                        ctx.textAlign = "center";
                        ctx.textBaseline = "middle";

                        var r_inner = width * 0.39;
                        var innerNumbers = [
                            {
                                val: "05",
                                angle: -Math.PI / 2 + (Math.PI / 6)
                            },
                            {
                                val: "10",
                                angle: -Math.PI / 2 + (Math.PI / 3)
                            },
                            {
                                val: "20",
                                angle: -Math.PI / 2 + (2 * Math.PI / 3)
                            },
                            {
                                val: "25",
                                angle: -Math.PI / 2 + (5 * Math.PI / 6)
                            },
                            {
                                val: "30",
                                angle: -Math.PI / 2 + Math.PI
                            },
                            {
                                val: "35",
                                angle: -Math.PI / 2 + (7 * Math.PI / 6)
                            },
                            {
                                val: "40",
                                angle: -Math.PI / 2 + (4 * Math.PI / 3)
                            },
                            {
                                val: "45",
                                angle: -Math.PI / 2 + (3 * Math.PI / 2)
                            },
                            {
                                val: "50",
                                angle: -Math.PI / 2 + (5 * Math.PI / 3)
                            },
                            {
                                val: "55",
                                angle: -Math.PI / 2 + (11 * Math.PI / 6)
                            }
                        ];

                        innerNumbers.forEach(function (item) {
                            var tx = cx + Math.cos(item.angle) * r_inner;
                            var ty = cy + Math.sin(item.angle) * r_inner;

                            var rot = item.angle + Math.PI / 2;
                            // Normalize rot to [-PI, PI]
                            while (rot > Math.PI)
                                rot -= 2 * Math.PI;
                            while (rot < -Math.PI)
                                rot += 2 * Math.PI;

                            // Flip 180 degrees if text is upside down (facing down)
                            if (rot > Math.PI / 2 || rot < -Math.PI / 2) {
                                rot += Math.PI;
                            }

                            ctx.save();
                            ctx.translate(tx, ty);
                            ctx.rotate(rot);
                            ctx.fillText(item.val, 0, 0);
                            ctx.restore();
                        });

                        // Draw inner ticks (4 lines between every 5 minutes/seconds)
                        ctx.save();
                        for (var j = 0; j < 12; j++) {
                            var baseAngle = -Math.PI / 2 + (j * Math.PI / 6);
                            for (var k = 1; k <= 4; k++) {
                                var tickAngle = baseAngle + (k * Math.PI / 30);
                                var isMiddle = (k === 2 || k === 3);
                                var tickHeight = isMiddle ? 7 : 4;
                                var tickWidth = isMiddle ? 2.2 : 1.4;

                                ctx.lineWidth = tickWidth;
                                ctx.strokeStyle = ColorUtils.applyAlpha(root.activeTextColor, isMiddle ? 0.28 : 0.16);

                                var r_start = r_inner - (tickHeight / 2);
                                var r_end = r_inner + (tickHeight / 2);

                                ctx.beginPath();
                                ctx.moveTo(cx + Math.cos(tickAngle) * r_start, cy + Math.sin(tickAngle) * r_start);
                                ctx.lineTo(cx + Math.cos(tickAngle) * r_end, cy + Math.sin(tickAngle) * r_end);
                                ctx.stroke();
                            }
                        }
                        ctx.restore();
                    }
                }

                // Update canvas on style/color updates
                Connections {
                    target: root
                    function onActiveTextColorChanged() {
                        dialCanvas.requestPaint();
                    }
                    function onActiveSubtextColorChanged() {
                        dialCanvas.requestPaint();
                    }
                }
            }

            // Small distro logo at 12:00 (minute 0 of inner ring)
            CustomIcon {
                id: distroLogo
                visible: root.cfgShowDistroLogo
                width: 14
                height: 14
                source: SystemInfo.distroIcon
                colorize: true
                color: root.activeTextColor
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height / 2 - root.r_inner - (height / 2)
                z: 2
            }

            // Complication 6: Sunset Gauge Widget (top center, below distro logo, above center pivot, offset right)
            Rectangle {
                id: sunsetComplication
                visible: root.cfgShowSunset
                width: parent.width * 0.18
                height: width
                radius: width / 2
                color: "transparent"
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.horizontalCenterOffset: 6
                y: parent.height * 0.17
                z: 2

                readonly property real sunsetHour: {
                    var sunsetStr = Weather.data.sunset || "18:00";
                    var parts = sunsetStr.split(":");
                    if (parts.length >= 2) {
                        var h = parseInt(parts[0]);
                        var m = parseInt(parts[1]);
                        return h + m / 60;
                    }
                    return 18.0;
                }

                // 24 Hour Gauge: alternating lines and dots, leaving gap at bottom
                Repeater {
                    model: 24
                    Item {
                        anchors.fill: parent
                        rotation: (index - 18) * 15 // Sunset (18:00) is exactly at 0 degree (top center)
                        visible: (index < 4 || index > 8) // Hide 4, 5, 6, 7, 8 to leave a gap at the bottom for the sun icon

                        readonly property bool isHighlighted: (index >= 9 && index <= sunsetComplication.sunsetHour)

                        Rectangle {
                            width: parent.isHighlighted ? 1.6 : (index % 2 === 0 ? 1.0 : 1.2)
                            height: parent.isHighlighted ? 4.0 : (index % 2 === 0 ? 3.0 : 1.2)
                            radius: (index % 2 === 0) ? 0 : width / 2
                            color: parent.isHighlighted ? Appearance.colors.colPrimary : ColorUtils.applyAlpha(root.activeTextColor, 0.20)
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.top
                        }
                    }
                }

                // Time text inside
                StyledText {
                    text: Weather.data.sunset || "18:00"
                    color: root.activeTextColor
                    font.pixelSize: parent.height * 0.22
                    font.weight: Font.Bold
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: -2
                }

                // Sun icon at the bottom gap
                Item {
                    width: 9
                    height: 9
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: parent.width * 0.02
                    anchors.horizontalCenter: parent.horizontalCenter

                    MaterialSymbol {
                        text: "sunny"
                        fill: 1
                        iconSize: 12
                        color: root.activeTextColor
                        anchors.centerIn: parent
                    }
                }
            }

            // Complication 1: Digital Time Pill (aligned with 55 of internal ring, slightly below 50)
            Rectangle {
                id: digitalTimeComplication
                visible: root.cfgShowDigitalTime
                width: parent.width * 0.20
                height: parent.width * 0.10
                radius: height / 2
                color: "transparent"
                border.color: Appearance.colors.colPrimaryContainer
                border.width: 1
                x: parent.width * 0.20
                y: parent.height * 0.36
                z: 2

                // Inner filled pill with spacing (gap)
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 3.5
                    radius: height / 2
                    color: Appearance.colors.colPrimaryContainer

                    StyledText {
                        text: {
                            var hStr = root.hour < 10 ? "0" + root.hour : "" + root.hour;
                            var mStr = root.minute < 10 ? "0" + root.minute : "" + root.minute;
                            return hStr + ":" + mStr;
                        }
                        color: Appearance.colors.colOnPrimaryContainer
                        font.pixelSize: parent.height * 0.65
                        font.weight: Font.Bold
                        anchors.centerIn: parent
                    }
                }
            }

            // Backing gradient to fade out the ring/ticks behind/around the battery pill
            RadialGradient {
                id: batteryFadeGlow
                visible: root.cfgShowBattery
                anchors.centerIn: batteryComplication
                width: batteryComplication.width * 1.25
                height: batteryComplication.height * 1.85
                z: 1.5
                gradient: Gradient {
                    GradientStop {
                        position: 0.0
                        color: Appearance.m3colors.m3shadow
                    }
                    GradientStop {
                        position: 0.5
                        color: Appearance.m3colors.m3shadow
                    }
                    GradientStop {
                        position: 1.0
                        color: "transparent"
                    }
                }
            }

            // Complication 2: Battery Pill (3:00 position)
            Rectangle {
                id: batteryComplication
                visible: root.cfgShowBattery
                width: parent.width * 0.14
                height: parent.width * 0.08
                radius: height / 2
                color: Appearance.m3colors.m3shadow
                border.color: root.activeAccentColor
                border.width: 1
                anchors.right: parent.right
                anchors.rightMargin: parent.width * 0.01
                anchors.verticalCenter: parent.verticalCenter
                z: 2

                StyledText {
                    text: Math.round(Battery.percentage * 100)
                    color: root.activeAccentColor
                    font.pixelSize: parent.height * 0.50
                    font.weight: Font.Bold
                    anchors.centerIn: parent
                }
            }

            // Complication 3: Hour Sub-dial (7:30 position) - no border circle
            Rectangle {
                id: hourDialComplication
                visible: root.cfgShowHourDial
                width: parent.width * 0.22
                height: width
                radius: width / 2
                color: "transparent"
                x: parent.width * 0.24
                y: parent.height * 0.52
                z: 2

                // Complication marks: 12 main hour ticks (lines)
                Repeater {
                    model: 12
                    Item {
                        anchors.fill: parent
                        rotation: index * 30
                        Rectangle {
                            width: 2.0
                            height: 5.5
                            radius: 0
                            color: ColorUtils.applyAlpha(root.activeTextColor, 0.55)
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.top
                        }
                    }
                }

                // Complication minor marks: 12 dots (halfway between each hour)
                Repeater {
                    model: 12
                    Item {
                        anchors.fill: parent
                        rotation: index * 30 + 15
                        Rectangle {
                            width: 2
                            height: 2
                            radius: 0.75
                            color: ColorUtils.applyAlpha(root.activeTextColor, 0.35)
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.top
                        }
                    }
                }

                StyledText {
                    text: root.hour % 12 === 0 ? 12 : root.hour % 12
                    color: root.activeTextColor
                    font.pixelSize: parent.height * 0.28
                    font.weight: Font.Bold
                    anchors.right: parent.right
                    anchors.rightMargin: parent.width * 0.15
                    anchors.verticalCenter: parent.verticalCenter
                }

                // Sub-dial center dot pivot
                Rectangle {
                    width: 4
                    height: 4
                    radius: 2
                    color: root.activeTextColor
                    anchors.centerIn: parent
                }

                // Rotating indicator: Hour rotation
                Item {
                    anchors.fill: parent
                    rotation: root.hourRotation
                    Rectangle {
                        width: parent.width * 0.08
                        height: parent.height * 0.35
                        radius: width / 2
                        color: Appearance.m3colors.m3shadow
                        border.color: root.activeTextColor
                        border.width: 1.5
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.verticalCenter
                        anchors.bottomMargin: parent.width * 0.045
                    }
                }
            }

            // Backing gradient to fade out the ring/ticks behind/around the bedtime icon
            RadialGradient {
                id: bedtimeFadeGlow
                visible: root.cfgShowBedtime
                anchors.centerIn: bedtimeIconContainer
                width: bedtimeIconContainer.width * 1.8
                height: bedtimeIconContainer.height * 1.8
                z: 1.5
                gradient: Gradient {
                    GradientStop {
                        position: 0.0
                        color: Appearance.m3colors.m3shadow
                    }
                    GradientStop {
                        position: 0.5
                        color: Appearance.m3colors.m3shadow
                    }
                    GradientStop {
                        position: 1.0
                        color: "transparent"
                    }
                }
            }

            // Complication 4: Bedtime icon (6:00 position) - direct icon aligned with external ring
            Item {
                id: bedtimeIconContainer
                visible: root.cfgShowBedtime
                width: 11
                height: 11
                anchors.bottom: parent.bottom
                anchors.bottomMargin: parent.width * 0.006
                anchors.horizontalCenter: parent.horizontalCenter
                z: 2

                MaterialSymbol {
                    id: bedtimeIcon
                    text: "bedtime"
                    fill: 1
                    iconSize: 11
                    color: root.activeTextColor
                    anchors.centerIn: parent
                }
            }

            // Complication 7: KDE Connect Connection Status Widget (above date complication, resized and positioned left)
            Rectangle {
                id: kdeConnectComplication
                visible: root.cfgShowKdeConnect
                width: 38
                height: 38
                radius: width / 2
                color: KdeConnectService.activeReachable ? Appearance.colors.colSecondaryContainer : ColorUtils.applyAlpha(Appearance.colors.colSecondaryContainer, 0.4)
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.horizontalCenterOffset: 38
                y: parent.height * 0.38
                z: 2

                MaterialSymbol {
                    text: KdeConnectService.activeReachable ? "mobile" : "mobile_off"
                    fill: 1
                    iconSize: 22
                    color: KdeConnectService.activeReachable ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSecondaryOnContainer
                    anchors.centerIn: parent
                }
            }

            // Complication 5: Date Small Widget (6:00 position, below center pivot, above inner ring)
            Column {
                id: smallDateComplication
                visible: root.cfgShowDate
                spacing: 2
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.horizontalCenterOffset: 30
                y: parent.height * 0.58
                z: 2

                // Day of the week (Top Row)
                Rectangle {
                    width: 32
                    height: 14
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colPrimaryContainer
                    anchors.horizontalCenter: parent.horizontalCenter

                    StyledText {
                        text: {
                            const days = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"];
                            return days[root.currentTime.getDay()];
                        }
                        color: Appearance.colors.colOnPrimaryContainer
                        font.pixelSize: 8
                        font.weight: Font.DemiBold
                        anchors.centerIn: parent
                    }
                }

                // Day of the month (Bottom Row)
                Rectangle {
                    width: 32
                    height: 18
                    radius: 4
                    color: Appearance.colors.colPrimary
                    anchors.horizontalCenter: parent.horizontalCenter

                    StyledText {
                        text: root.date
                        color: Appearance.colors.colOnPrimary
                        font.pixelSize: 13
                        font.weight: Font.Bold
                        anchors.centerIn: parent
                    }
                }
            }

            // Analog Hands (Center overlay - Hour hand only)
            Item {
                id: handsContainer
                anchors.fill: parent
                z: 4

                // Minute Hand capsule (Hour hand removed)
                Item {
                    visible: root.cfgShowMinuteHand
                    anchors.fill: parent
                    rotation: root.minuteRotation

                    Rectangle {
                        width: parent.width * 0.047
                        height: parent.height * 0.30
                        radius: width / 2
                        color: ColorUtils.applyAlpha(Appearance.m3colors.m3shadow, 0.25)
                        border.color: root.activeAccentColor
                        border.width: 3
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.verticalCenter
                        anchors.bottomMargin: parent.width * 0.04
                    }
                }

                // Center pivot ring
                Rectangle {
                    width: parent.width * 0.05
                    height: width
                    radius: width / 2
                    color: Appearance.m3colors.m3shadow
                    border.color: root.activeSubtextColor
                    border.width: 2.5
                    anchors.centerIn: parent
                }
            }
        }
    }

    // 3D Glass Dome Reflection Overlay
    Item {
        id: glassReflectionOverlay
        anchors.fill: parent
        z: 10
        enabled: false // Transparent to mouse events
        visible: Config.options.background.widgets.wearos_clock.enableGlassReflection ?? true

        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Item {
                width: glassReflectionOverlay.width
                height: glassReflectionOverlay.height

                Rectangle {
                    id: outerMaskBase
                    anchors.fill: parent
                    radius: width / 2
                    visible: false
                }

                FastBlur {
                    anchors.fill: parent
                    source: outerMaskBase
                    radius: 3 // soft feather on the bezel mask boundary
                }
            }
        }

        // Top-Right Crescent Reflection (14:00 / 70 degrees)
        Item {
            id: topReflectionContainer
            anchors.fill: parent
            layer.enabled: true
            layer.effect: FastBlur {
                radius: 28 // increased blur/dispersion for a softer, broader premium glass glow
            }

            // Crescent Mask Shape
            Shapes.Shape {
                id: topMaskShape
                anchors.fill: parent
                visible: false

                Shapes.ShapePath {
                    strokeColor: "transparent"
                    fillColor: "white"
                    startX: parent.width * 0.40
                    startY: parent.height * 0.04
                    PathArc {
                        x: topMaskShape.width * 0.96
                        y: topMaskShape.height * 0.60
                        radiusX: topMaskShape.width * 0.48
                        radiusY: topMaskShape.height * 0.48
                        useLargeArc: false
                    }
                    PathArc {
                        x: topMaskShape.width * 0.40
                        y: topMaskShape.height * 0.04
                        radiusX: topMaskShape.width * 0.35
                        radiusY: topMaskShape.height * 0.35
                        useLargeArc: false
                        direction: PathArc.Counterclockwise
                    }
                }
            }

            LinearGradient {
                anchors.fill: parent
                start: Qt.point(width * 0.40, height * 0.04)
                end: Qt.point(width * 0.96, height * 0.60)
                cached: true
                gradient: Gradient {
                    GradientStop {
                        position: 0.0
                        color: "transparent"
                    }
                    GradientStop {
                        position: 0.3
                        color: ColorUtils.applyAlpha("#FFFFFF", 0.42)
                    }
                    GradientStop {
                        position: 0.7
                        color: ColorUtils.applyAlpha("#FFFFFF", 0.42)
                    }
                    GradientStop {
                        position: 1.0
                        color: "transparent"
                    }
                }
                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: topMaskShape
                }
            }
        }

        // Bottom-Left Crescent Reflection (250 degrees / 8:00)
        Item {
            id: bottomReflectionContainer
            anchors.fill: parent
            layer.enabled: true
            layer.effect: FastBlur {
                radius: 28 // increased blur/dispersion for a softer, broader premium glass glow
            }

            // Crescent Mask Shape
            Shapes.Shape {
                id: bottomMaskShape
                anchors.fill: parent
                visible: false

                Shapes.ShapePath {
                    strokeColor: "transparent"
                    fillColor: "white"
                    startX: parent.width * 0.60
                    startY: parent.height * 0.96
                    PathArc {
                        x: bottomMaskShape.width * 0.04
                        y: bottomMaskShape.height * 0.40
                        radiusX: bottomMaskShape.width * 0.48
                        radiusY: bottomMaskShape.height * 0.48
                        useLargeArc: false
                    }
                    PathArc {
                        x: bottomMaskShape.width * 0.60
                        y: bottomMaskShape.height * 0.96
                        radiusX: bottomMaskShape.width * 0.35
                        radiusY: bottomMaskShape.height * 0.35
                        useLargeArc: false
                        direction: PathArc.Counterclockwise
                    }
                }
            }

            LinearGradient {
                anchors.fill: parent
                start: Qt.point(width * 0.60, height * 0.96)
                end: Qt.point(width * 0.04, height * 0.40)
                cached: true
                gradient: Gradient {
                    GradientStop {
                        position: 0.0
                        color: "transparent"
                    }
                    GradientStop {
                        position: 0.3
                        color: ColorUtils.applyAlpha("#FFFFFF", 0.28)
                    }
                    GradientStop {
                        position: 0.7
                        color: ColorUtils.applyAlpha("#FFFFFF", 0.28)
                    }
                    GradientStop {
                        position: 1.0
                        color: "transparent"
                    }
                }
                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: bottomMaskShape
                }
            }
        }
    }
}
