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

Item {
    id: root

    // Configuration shortcuts
    readonly property var cfg: Config.options.background.widgets.wearos_arc_clock
    readonly property bool cfgBlackBg: cfg ? (cfg.blackBackground ?? false) : false
    readonly property bool cfgReflection: cfg ? (cfg.enableGlassReflection ?? true) : true
    readonly property bool cfgPattern: cfg ? (cfg.enableBackgroundPattern ?? true) : true
    readonly property string cfgLeftComp: cfg ? (cfg.leftComplication ?? "weather") : "weather"
    readonly property string cfgRightComp: cfg ? (cfg.rightComplication ?? "battery") : "battery"
    readonly property string cfgBottomComp: cfg ? (cfg.bottomComplication ?? "calendar") : "calendar"
    readonly property bool cfgShadows: cfg ? (cfg.enableShadows ?? false) : false

    // Color tokens (Strictly dynamic via Appearance & WidgetColorScheme)
    readonly property color cardBgColor: cfgBlackBg ? "#000000" : WidgetColorScheme.cardBgColor
    readonly property color textColor: cfgBlackBg ? "#FFFFFF" : WidgetColorScheme.textColorOnBg
    readonly property color subtextColor: cfgBlackBg ? "#A0A0A0" : WidgetColorScheme.subtextColorOnBg
    readonly property color accentColor: WidgetColorScheme.accentColor
    readonly property color trackColor: cfgBlackBg ? "#242424" : WidgetColorScheme.innerShapeColor

    // DateTime binding
    readonly property var currentTime: DateTime.clock.date
    readonly property int hourVal: currentTime.getHours()
    readonly property int minVal: currentTime.getMinutes()
    readonly property int dateVal: currentTime.getDate()

    // Helper functions for dates & minutes formatting
    function formatMin(m) {
        let val = (m + 60) % 60;
        return val < 10 ? "0" + val : "" + val;
    }

    function getDateOffset(offset) {
        let d = new Date(currentTime.getTime());
        d.setDate(d.getDate() + offset);
        return d.getDate();
    }

    // Complications state models
    readonly property var leftData: getComplicationData(cfgLeftComp)
    readonly property var rightData: getComplicationData(cfgRightComp)
    readonly property var bottomData: getBottomComplicationData(cfgBottomComp)

    function getComplicationData(type) {
        switch (type) {
            case "weather":
                let t = Weather.data?.temp ? Weather.data.temp.replace("°C", "°").replace("°F", "°") : "0°";
                return {
                    value: t,
                    icon: WeatherIcons.getWeatherIcon(Weather.data?.wCode ?? 113, false),
                    isLocalImage: true,
                    pct: 0.75
                };
            case "battery":
                return {
                    value: Battery.percentage !== null ? Math.round(Battery.percentage * 100) : "100",
                    icon: Battery.isCharging ? "battery_charging_full" : "battery_full",
                    isLocalImage: false,
                    pct: Battery.percentage ?? 1.0
                };
            case "phone_battery":
                let active = KdeConnectService.activeDevice && KdeConnectService.activeDevice.reachable;
                return {
                    value: active ? (KdeConnectService.activeDevice.charge ?? 100) : "--",
                    icon: "smartphone",
                    isLocalImage: false,
                    pct: active ? (KdeConnectService.activeDevice.charge ?? 100) / 100.0 : 0.0
                };
            case "bluetooth_battery":
                let dev = BluetoothStatus.connectedDevices.length > 0 ? BluetoothStatus.connectedDevices[0] : null;
                return {
                    value: dev ? (dev.battery ?? 80) : "--",
                    icon: dev ? Icons.getBluetoothDeviceMaterialSymbol(dev.icon || "") : "headphones",
                    isLocalImage: false,
                    pct: dev ? (dev.battery ?? 80) / 100.0 : 0.0
                };
            case "water_reminder":
                let goal = Config.options.background.widgets.water_reminder?.dailyGoal ?? 8;
                let drunk = WaterReminderService.glassesDrunk ?? 0;
                return {
                    value: drunk,
                    icon: "water_full",
                    isLocalImage: false,
                    pct: Math.min(1.0, drunk / goal)
                };
            case "cpu_usage":
                return {
                    value: Math.round(ResourceUsage.cpuUsage * 100) + "%",
                    icon: "developer_board",
                    isLocalImage: false,
                    pct: ResourceUsage.cpuUsage
                };
            case "memory_usage":
                return {
                    value: Math.round(ResourceUsage.memoryUsedPercentage * 100) + "%",
                    icon: "memory",
                    isLocalImage: false,
                    pct: ResourceUsage.memoryUsedPercentage
                };
            default:
                return { value: "", icon: "", isLocalImage: false, pct: 0 };
        }
    }

    function getBottomComplicationData(type) {
        switch (type) {
            case "calendar":
                let today = DateTime.clock.date || new Date();
                const currentDay = today.getDate();
                const currentMonth = today.getMonth();
                const currentYear = today.getFullYear();
                let todayEvts = [];
                if (CalendarService.khalAvailable && CalendarService.events) {
                    for (let i = 0; i < CalendarService.events.length; i++) {
                        let evt = CalendarService.events[i];
                        let taskDate = new Date(evt.startDate);
                        if (taskDate.getDate() === currentDay && taskDate.getMonth() === currentMonth && taskDate.getFullYear() === currentYear) {
                            todayEvts.push(evt);
                        }
                    }
                    todayEvts.sort((a, b) => a.startDate - b.startDate);
                }
                let now = today.getTime();
                let nextEvt = null;
                for (let i = 0; i < todayEvts.length; i++) {
                    let evtEnd = new Date(todayEvts[i].endDate).getTime();
                    if (evtEnd > now) {
                        nextEvt = todayEvts[i];
                        break;
                    }
                }
                if (!nextEvt && todayEvts.length > 0) nextEvt = todayEvts[0];
                if (nextEvt) {
                    let start = new Date(nextEvt.startDate);
                    let end = new Date(nextEvt.endDate);
                    let startStr = start.getHours() + ":" + (start.getMinutes() < 10 ? "0" + start.getMinutes() : start.getMinutes());
                    let endStr = end.getHours() + ":" + (end.getMinutes() < 10 ? "0" + end.getMinutes() : end.getMinutes());
                    return {
                        title: nextEvt.content || nextEvt.summary || Translation.tr("Event"),
                        subtitle: startStr + " - " + endStr,
                        icon: "calendar_today"
                    };
                }
                return { title: Translation.tr("No events today"), subtitle: "", icon: "calendar_today" };

            case "todo":
                let task = TickTickService.tasks.length > 0 ? TickTickService.tasks[0] : null;
                return {
                    title: task ? task.title : Translation.tr("No pending tasks"),
                    subtitle: task ? Translation.tr("TickTick Inbox") : "",
                    icon: "check_box"
                };

            case "media":
                let title = Mpris.metadata?.title;
                let artist = Mpris.metadata?.artist;
                let active = title !== undefined && title !== "";
                return {
                    title: active ? title : Translation.tr("Nothing playing"),
                    subtitle: active ? (artist || "") : "",
                    icon: Mpris.playbackState === "playing" ? "play_arrow" : "pause"
                };

            case "water":
                let drunk = WaterReminderService.glassesDrunk ?? 0;
                let goal = Config.options.background.widgets.water_reminder?.dailyGoal ?? 8;
                return {
                    title: drunk + "/" + goal + " " + Translation.tr("glasses"),
                    subtitle: Translation.tr("Water Intake"),
                    icon: "water_full"
                };
            default:
                return { title: "", subtitle: "", icon: "" };
        }
    }

    // Outer shadow
    StyledDropShadow {
        id: shadowEffect
        target: mainCircle
        visible: root.cfgShadows
    }

    // Main Face Circle
    Rectangle {
        id: mainCircle
        anchors.fill: parent
        radius: width / 2
        color: WidgetColorScheme.tintBackground(root.cardBgColor)
        clip: true

        Behavior on color {
            ColorAnimation { duration: 250 }
        }

        // Canvas for dotted pattern, arc gauges, radial dials, and curved bottom texts
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
                var r_mask = width / 2 - 1.5;

                // Enforce strict circular clip to prevent any drawing from bleeding outside watch face
                ctx.beginPath();
                ctx.arc(cx, cy, r_mask, 0, 2 * Math.PI);
                ctx.clip();

                // 1. Dotted Background Pattern with radial gradient transparency
                if (root.cfgPattern) {
                    let dotSpacing = 11;
                    for (let x = dotSpacing / 2; x < width; x += dotSpacing) {
                        for (let y = dotSpacing / 2; y < height; y += dotSpacing) {
                            let dx = x - cx;
                            let dy = y - cy;
                            let dist = Math.sqrt(dx*dx + dy*dy);
                            if (dist < r_mask) {
                                let opacityFactor = Math.pow(1.0 - (dist / r_mask), 1.4);
                                ctx.fillStyle = ColorUtils.applyAlpha(root.textColor, opacityFactor * 0.45);
                                ctx.beginPath();
                                ctx.arc(x, y, 1.1, 0, 2 * Math.PI);
                                ctx.fill();
                            }
                        }
                    }
                }

                // 2. Compact Complication gauges: Horseshoe arcs open at the BOTTOM (centerAngle = -Math.PI / 2)
                // Left gauge (bottom-left ~7:30)
                if (root.cfgLeftComp !== "none") {
                    let cx_l = cx - width * 0.25;
                    let cy_l = cy + height * 0.20;
                    drawConcentricComplicationArc(ctx, cx_l, cy_l, root.leftData.pct, root.accentColor, root.trackColor);
                }
                // Right gauge (middle-right ~3:30, higher and further right)
                if (root.cfgRightComp !== "none") {
                    let cx_r = cx + width * 0.27;
                    let cy_r = cy - height * 0.02;
                    drawConcentricComplicationArc(ctx, cx_r, cy_r, root.rightData.pct, root.accentColor, root.trackColor);
                }

                // 3. Curved Stacked Bottom Text Complications at 5 o'clock position (~Math.PI * 0.38)
                if (root.cfgBottomComp !== "none" && root.bottomData.title !== "") {
                    let hasSub = root.bottomData.subtitle !== "";
                    let posAngle = Math.PI * 0.38; // Positioned around 5 o'clock
                    if (hasSub) {
                        let line1Text = root.bottomData.subtitle;
                        if (root.cfgBottomComp === "calendar") {
                            line1Text = "[" + root.dateVal + "] " + line1Text;
                        }
                        // Line 1 (inner curve): Subtitle / time range in accent color
                        drawCurvedText(ctx, cx, cy, width * 0.405, posAngle, line1Text, Math.round(width * 0.033), root.accentColor);
                        // Line 2 (outer curve): Title in main text color
                        drawCurvedText(ctx, cx, cy, width * 0.458, posAngle, root.bottomData.title, Math.round(width * 0.040), root.textColor);
                    } else {
                        drawCurvedText(ctx, cx, cy, width * 0.442, posAngle, root.bottomData.title, Math.round(width * 0.040), root.textColor);
                    }
                }

                // 4. Radial Date and Minute Dial (r_date = 0.395, r_min = 0.270, angle_step = 21.0°)
                let angle_c = -106 * Math.PI / 180; // ~ 11:20 position
                let angle_step = 21.0 * Math.PI / 180; // 21 degrees arc step to prevent text overlap
                let r_date = width * 0.395; // Outer date arc radius
                let r_min = width * 0.270;  // Inner minute arc radius

                // Draw Open-Top U-Chute Capsule Selector TILTED RADIALLY along angle_c with generous padding
                ctx.save();
                ctx.translate(cx, cy);
                ctx.rotate(angle_c + Math.PI / 2);
                ctx.beginPath();
                let capW = width * 0.145; // Pill width
                let capR = capW / 2;
                let topY = -r_date - width * 0.030; // Outer top end extending past date digit
                let botY = -r_min + width * 0.035;  // Inner bottom end wrapping around active minute

                ctx.moveTo(-capR, topY);
                ctx.lineTo(-capR, botY - capR);
                ctx.arc(0, botY - capR, capR, Math.PI, 0, true);
                ctx.lineTo(capR, topY);

                ctx.lineWidth = Math.max(2.0, width * 0.010);
                ctx.strokeStyle = root.accentColor;
                ctx.lineCap = "round";
                ctx.stroke();
                ctx.restore();

                // Draw short discrete radial divider ticks between columns (no long rays!)
                ctx.save();
                ctx.strokeStyle = ColorUtils.applyAlpha(root.textColor, 0.32);
                ctx.lineWidth = 1.4;
                for (let i = -2; i <= 2; i++) {
                    let angle = angle_c + i * angle_step;

                    if (i !== 0) {
                        // Short tick between date and minute
                        let r1 = r_min + width * 0.030;
                        let r2 = r_date - width * 0.030;
                        ctx.beginPath();
                        ctx.moveTo(cx + Math.cos(angle) * r1, cy + Math.sin(angle) * r1);
                        ctx.lineTo(cx + Math.cos(angle) * r2, cy + Math.sin(angle) * r2);
                        ctx.stroke();
                    }

                    // Short tick mark above date arc (~6px dash)
                    let r3 = r_date + width * 0.020;
                    let r4 = r_date + width * 0.050;
                    ctx.beginPath();
                    ctx.moveTo(cx + Math.cos(angle) * r3, cy + Math.sin(angle) * r3);
                    ctx.lineTo(cx + Math.cos(angle) * r4, cy + Math.sin(angle) * r4);
                    ctx.stroke();
                }
                ctx.restore();

                // Draw central capsule divider dot inside active column
                ctx.fillStyle = ColorUtils.applyAlpha(root.textColor, 0.45);
                ctx.beginPath();
                let r_dot = (r_date + r_min) / 2;
                ctx.arc(cx + Math.cos(angle_c) * r_dot, cy + Math.sin(angle_c) * r_dot, 1.8, 0, 2 * Math.PI);
                ctx.fill();

                // Render Radial Date Digits (26, 27, 28) - ROTATED ALONG RADIAL RAY
                ctx.save();
                ctx.textAlign = "center";
                ctx.textBaseline = "middle";

                for (let i = -1; i <= 1; i++) {
                    let angle = angle_c + i * angle_step;
                    let tx = cx + Math.cos(angle) * r_date;
                    let ty = cy + Math.sin(angle) * r_date;
                    let val = root.getDateOffset(i);
                    let isCenter = (i === 0);

                    ctx.font = "bold " + Math.round(width * (isCenter ? 0.056 : 0.046)) + "px sans-serif";
                    ctx.fillStyle = isCenter ? root.textColor : ColorUtils.applyAlpha(root.textColor, 0.50);

                    ctx.save();
                    ctx.translate(tx, ty);
                    ctx.rotate(angle + Math.PI / 2);
                    ctx.fillText(val, 0, 0);
                    ctx.restore();
                }
                ctx.restore();

                // Render Radial Minute Digits (55, 56, 57, 58, 59) - PROPORTIONAL NON-OVERLAPPING SIZES
                ctx.save();
                ctx.textAlign = "center";
                ctx.textBaseline = "middle";

                for (let i = -2; i <= 2; i++) {
                    let angle = angle_c + i * angle_step;
                    let tx = cx + Math.cos(angle) * r_min;
                    let ty = cy + Math.sin(angle) * r_min;
                    let val = root.formatMin(root.minVal + i);
                    let isCenter = (i === 0);
                    let isAdj = (i === -1 || i === 1);

                    ctx.font = "bold " + Math.round(width * (isCenter ? 0.088 : (isAdj ? 0.062 : 0.048))) + "px sans-serif";
                    ctx.fillStyle = isCenter ? root.textColor : ColorUtils.applyAlpha(root.textColor, isAdj ? 0.60 : 0.30);

                    ctx.save();
                    ctx.translate(tx, ty);
                    ctx.rotate(angle + Math.PI / 2);
                    ctx.fillText(val, 0, 0);
                    ctx.restore();
                }
                ctx.restore();
            }

            function drawConcentricComplicationArc(ctx, cx_g, cy_g, pct, colorAccent, colorTrack) {
                let r_g = width * 0.088; // Compact gauge radius snug around content
                let arcSpan = Math.PI * 1.35; // ~243 degrees horseshoe
                let centerAngle = -Math.PI / 2; // Horseshoe open at bottom!
                let startAngle = centerAngle - arcSpan / 2;
                let endAngle = centerAngle + arcSpan / 2;
                let amount = Math.min(1.0, Math.max(0.0, pct));
                let lineWidth = width * 0.026;

                ctx.beginPath();
                ctx.arc(cx_g, cy_g, r_g, startAngle, endAngle);
                ctx.lineWidth = lineWidth;
                ctx.strokeStyle = colorTrack;
                ctx.lineCap = "round";
                ctx.stroke();

                if (amount > 0) {
                    ctx.beginPath();
                    ctx.arc(cx_g, cy_g, r_g, startAngle, startAngle + arcSpan * amount);
                    ctx.lineWidth = lineWidth;
                    ctx.strokeStyle = colorAccent;
                    ctx.lineCap = "round";
                    ctx.stroke();
                }
            }

            function drawCurvedText(ctx, cx, cy, radius, centerAngle, text, fontPx, fillCol) {
                ctx.save();
                ctx.font = "bold " + fontPx + "px sans-serif";
                ctx.fillStyle = fillCol;
                ctx.textAlign = "center";
                ctx.textBaseline = "middle";

                var charWidths = [];
                var totalWidth = 0;
                for (var i = 0; i < text.length; i++) {
                    var w = ctx.measureText(text[i]).width;
                    charWidths.push(w);
                    totalWidth += w;
                }

                var totalArcAngle = totalWidth / radius;
                var startArcAngle = centerAngle + (totalArcAngle / 2);

                var currentArc = startArcAngle;
                for (var j = 0; j < text.length; j++) {
                    var charW = charWidths[j];
                    var halfCharAngle = (charW / 2) / radius;
                    var charAngle = currentArc - halfCharAngle;

                    var charX = cx + Math.cos(charAngle) * radius;
                    var charY = cy + Math.sin(charAngle) * radius;

                    var rot = charAngle - Math.PI / 2;

                    ctx.save();
                    ctx.translate(charX, charY);
                    ctx.rotate(rot);
                    ctx.fillText(text[j], 0, 0);
                    ctx.restore();

                    currentArc -= (charW / radius);
                }
                ctx.restore();
            }

            // Refresh canvas on state updates
            Connections {
                target: root
                function onCfgLeftCompChanged() { dialCanvas.requestPaint(); }
                function onCfgRightCompChanged() { dialCanvas.requestPaint(); }
                function onCfgBottomCompChanged() { dialCanvas.requestPaint(); }
                function onLeftDataChanged() { dialCanvas.requestPaint(); }
                function onRightDataChanged() { dialCanvas.requestPaint(); }
                function onBottomDataChanged() { dialCanvas.requestPaint(); }
                function onCfgPatternChanged() { dialCanvas.requestPaint(); }
                function onTextColorChanged() { dialCanvas.requestPaint(); }
                function onAccentColorChanged() { dialCanvas.requestPaint(); }
                function onTrackColorChanged() { dialCanvas.requestPaint(); }
                function onMinValChanged() { dialCanvas.requestPaint(); }
                function onHourValChanged() { dialCanvas.requestPaint(); }
                function onDateValChanged() { dialCanvas.requestPaint(); }
            }
        }

        // Left Complication Content (Snug inside gauge, Value Text on TOP, Icon on BOTTOM)
        Column {
            id: leftComplicationContent
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: -parent.width * 0.25
            anchors.verticalCenterOffset: parent.height * 0.20
            spacing: 1
            z: 2
            visible: root.cfgLeftComp !== "none"

            StyledText {
                text: root.leftData.value
                font.pixelSize: Math.round(root.width * 0.055)
                font.weight: Font.Bold
                color: root.textColor
                anchors.horizontalCenter: parent.horizontalCenter
            }

            Loader {
                id: leftIconLoader
                anchors.horizontalCenter: parent.horizontalCenter
                sourceComponent: root.leftData.isLocalImage ? localImageComp : symbolIconComp
                property string iconSource: root.leftData.icon

                Component {
                    id: localImageComp
                    Image {
                        source: leftIconLoader.iconSource
                        sourceSize: Qt.size(Math.round(root.width * 0.055), Math.round(root.width * 0.055))
                    }
                }

                Component {
                    id: symbolIconComp
                    MaterialSymbol {
                        text: leftIconLoader.iconSource
                        iconSize: Math.round(root.width * 0.055)
                        color: root.textColor
                    }
                }
            }
        }

        // Right Complication Content (Snug inside gauge, higher up & right, Value Text on TOP, Icon on BOTTOM)
        Column {
            id: rightComplicationContent
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: parent.width * 0.27
            anchors.verticalCenterOffset: -parent.height * 0.02
            spacing: 1
            z: 2
            visible: root.cfgRightComp !== "none"

            StyledText {
                text: root.rightData.value
                font.pixelSize: Math.round(root.width * 0.055)
                font.weight: Font.Bold
                color: root.textColor
                anchors.horizontalCenter: parent.horizontalCenter
            }

            Loader {
                id: rightIconLoader
                anchors.horizontalCenter: parent.horizontalCenter
                sourceComponent: symbolIconCompRight
                property string iconSource: root.rightData.icon

                Component {
                    id: symbolIconCompRight
                    MaterialSymbol {
                        text: rightIconLoader.iconSource
                        iconSize: Math.round(root.width * 0.055)
                        color: root.textColor
                    }
                }
            }
        }

        // Large Central Hour Display (Medium-Large, compact bold "12")
        StyledText {
            id: hourText
            text: root.hourVal
            font.pixelSize: Math.round(root.width * 0.22)
            font.weight: Font.DemiBold
            color: root.textColor
            anchors.centerIn: parent
            anchors.verticalCenterOffset: parent.height * 0.07
        }
    }

    // 3D Glass Dome Reflection Overlay
    Item {
        id: glassReflectionOverlay
        anchors.fill: parent
        z: 10
        enabled: false
        visible: root.cfgReflection

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
                    radius: 3
                }
            }
        }

        // Top-Right Crescent Reflection
        Item {
            id: topReflectionContainer
            anchors.fill: parent
            layer.enabled: true
            layer.effect: FastBlur {
                radius: 28
            }

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
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.3; color: ColorUtils.applyAlpha("#FFFFFF", 0.42) }
                    GradientStop { position: 0.7; color: ColorUtils.applyAlpha("#FFFFFF", 0.42) }
                    GradientStop { position: 1.0; color: "transparent" }
                }
                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: topMaskShape
                }
            }
        }

        // Bottom-Left Crescent Reflection
        Item {
            id: bottomReflectionContainer
            anchors.fill: parent
            layer.enabled: true
            layer.effect: FastBlur {
                radius: 28
            }

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
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.3; color: ColorUtils.applyAlpha("#FFFFFF", 0.28) }
                    GradientStop { position: 0.7; color: ColorUtils.applyAlpha("#FFFFFF", 0.28) }
                    GradientStop { position: 1.0; color: "transparent" }
                }
                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: bottomMaskShape
                }
            }
        }
    }
}
