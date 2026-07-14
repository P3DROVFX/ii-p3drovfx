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
import Quickshell.Services.Mpris

AbstractBackgroundWidget {
    id: root

    configEntryName: "wearos_clock"

    visibleWhenLocked: root.lockBehavior === "keep" || root.lockBehavior === "center" || root.lockBehavior === "lockOnly" || (Config.options.lock.centerWidget === "clock")

    // Default size is 240x240 for 1:1 widgets as per AGENTS.md guidelines
    implicitWidth: 240
    implicitHeight: 240

    readonly property bool useAlbumColors: Config.ready ? (Config.options.background.widgets.wearos_clock.useAlbumColors ?? true) : true
    readonly property MprisPlayer player: MprisController.activePlayer
    readonly property string artUrl: player?.trackArtUrl ?? ""
    property bool isLocalArt: artUrl.startsWith("file://")
    property string artDownloadLocation: Directories.coverArt
    property string artFileName: Qt.md5(artUrl)
    property string artFilePath: `${artDownloadLocation}/${artFileName}`
    property bool artDownloaded: false

    readonly property string artSource: {
        if (!artUrl)
            return "";
        if (isLocalArt)
            return artUrl;
        return artDownloaded ? Qt.resolvedUrl(artFilePath) : "";
    }

    onArtFilePathChanged: {
        if (!artUrl || artUrl.length === 0) {
            artDownloaded = false;
            return;
        }
        if (isLocalArt) {
            artDownloaded = true;
            return;
        }
        artDownloader.targetFile = artUrl;
        artDownloader.artFilePath = artFilePath;
        artDownloader.running = true;
    }

    Process {
        id: artDownloader
        property string targetFile: root.artUrl
        property string artFilePath: root.artFilePath
        property string artTempPath: root.artFilePath + ".tmp"
        command: ["bash", "-c", `[ -f ${artFilePath} ] || (curl -4 -sSL '${targetFile}' -o '${artTempPath}' && mv '${artTempPath}' '${artFilePath}')`]
        onExited: {
            artDownloaded = true;
        }
    }

    ColorQuantizer {
        id: colorQuantizer
        source: root.artSource
        depth: 2
        rescaleSize: 1
    }

    readonly property color rawExtractedColor: colorQuantizer?.colors[0] ?? Appearance.colors.colPrimary

    // Elevate saturation and adjust lightness of the extracted color to get a highly vibrant palette
    property color artDominantColor: {
        if (!root.useDynamicColors)
            return Appearance.colors.colPrimary;
        let h = rawExtractedColor.hslHue;
        let s = Math.max(0.85, rawExtractedColor.hslSaturation);
        let l = Math.max(0.58, Math.min(0.65, rawExtractedColor.hslLightness));
        return Qt.hsla(h, s, l, 1.0);
    }

    property QtObject blendedColors: AdaptedMaterialScheme {
        color: root.artDominantColor
    }

    readonly property bool useDynamicColors: root.useAlbumColors && root.artSource !== ""

    // Vibrant button coloring using only colPrimary, colOnPrimary, and colPrimaryContainer
    readonly property color activeAccentColor: root.useDynamicColors ? blendedColors.colPrimary : Appearance.colors.colPrimary
    readonly property color activeAccentContainer: root.useDynamicColors ? blendedColors.colPrimaryContainer : Appearance.colors.colPrimaryContainer
    readonly property color activeOnPrimary: root.useDynamicColors ? blendedColors.colOnPrimary : Appearance.colors.colOnPrimary

    // Text colors are blended with white (neutral tinting) to prevent extremely vibrant/hard-to-read text, matching reference watch displays
    readonly property color activeTextColor: root.useDynamicColors ? ColorUtils.mix("#FFFFFF", root.artDominantColor, 0.90) : Appearance.colors.colOnSurface
    readonly property color activeSubtextColor: root.useDynamicColors ? ColorUtils.mix("#FFFFFF", root.artDominantColor, 0.70) : Appearance.colors.colOnSurfaceVariant

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
    readonly property real minuteRotation: (minute * 6) + (second * 0.1)
    readonly property real hourRotation: ((hour % 12) * 30) + (minute * 0.5)

    // Outer bezel shadow support
    StyledDropShadow {
        id: outerBezelShadow
        target: bezelRing
        visible: Config.options.background.widgets.enableShadows ?? true
    }

    // Outer Bezel Ring (Moldura) using opaque solid colBackgroundSurfaceContainer base
    Rectangle {
        id: bezelRing
        anchors.fill: parent
        radius: width / 2
        color: Appearance.m3colors.m3shadow // Opaque base to prevent transparency leaks

        // Inner Screen Container
        Rectangle {
            id: innerScreen
            anchors.fill: parent
            anchors.margins: parent.width * 0.08 // 8% bezel thickness
            radius: width / 2
            color: Appearance.m3colors.m3shadow

            // Opaque Background Artwork + Gradient Container (with circular masking)
            Item {
                id: artBackgroundContainer
                anchors.fill: parent
                z: 0

                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: artBackgroundContainer.width
                        height: artBackgroundContainer.height
                        radius: artBackgroundContainer.width / 2
                    }
                }

                // Opaque base behind album art
                Rectangle {
                    anchors.fill: parent
                    color: Appearance.m3colors.m3shadow
                }

                // Album Art with a light blur (for background vibe)
                Image {
                    id: albumArtImage
                    anchors.fill: parent
                    source: root.artSource
                    fillMode: Image.PreserveAspectCrop
                    visible: root.artSource !== ""
                    asynchronous: true

                    layer.enabled: true
                    layer.effect: FastBlur {
                        radius: 4 // light blur
                    }
                }

                // Radial Gradient: smooth/wide fade region, starts closer to the center
                RadialGradient {
                    id: radialGrad
                    anchors.fill: parent
                    horizontalRadius: width / 2
                    verticalRadius: height / 2
                    gradient: Gradient {
                        GradientStop {
                            position: 0.0
                            color: "transparent"
                        }
                        GradientStop {
                            position: 0.25
                            color: "transparent"
                        }
                        GradientStop {
                            position: 0.62
                            color: ColorUtils.transparentize(Appearance.m3colors.m3shadow, 0.4)
                        }
                        GradientStop {
                            position: 0.75
                            color: ColorUtils.transparentize(Appearance.m3colors.m3shadow, 0.2)
                        }
                        GradientStop {
                            position: 1.0
                            color: Appearance.m3colors.m3shadow
                        }
                    }
                }
            }

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
                    ctx.save();
                    ctx.font = "bold " + Math.round(width * 0.034) + "px sans-serif";
                    ctx.fillStyle = root.activeSubtextColor;
                    ctx.textAlign = "center";
                    ctx.textBaseline = "middle";

                    var r_outer = width * 0.44;
                    for (var i = 0; i < 30; i++) {
                        var val = i * 2;
                        var valStr = val < 10 ? "0" + val : "" + val;
                        var angle = -Math.PI / 2 + (i * Math.PI / 15);

                        // Draw tick mark
                        ctx.beginPath();
                        ctx.strokeStyle = ColorUtils.applyAlpha(root.activeSubtextColor, 0.4);
                        ctx.lineWidth = 1;
                        ctx.moveTo(cx + Math.cos(angle) * (r_outer - 4), cy + Math.sin(angle) * (r_outer - 4));
                        ctx.lineTo(cx + Math.cos(angle) * r_outer, cy + Math.sin(angle) * r_outer);
                        ctx.stroke();

                        // Draw outer numbers slightly inward
                        var textR = r_outer - 10;
                        ctx.fillText(valStr, cx + Math.cos(angle) * textR, cy + Math.sin(angle) * textR);
                    }
                    ctx.restore();

                    // Draw inner numbers (05, 10, 20... 55)
                    ctx.save();
                    ctx.font = "bold " + Math.round(width * 0.052) + "px sans-serif";
                    ctx.fillStyle = root.activeTextColor;
                    ctx.textAlign = "center";
                    ctx.textBaseline = "middle";

                    var r_inner = width * 0.33;
                    var innerNumbers = [
                        { val: "05", angle: -Math.PI/2 + (Math.PI/6) },
                        { val: "10", angle: -Math.PI/2 + (Math.PI/3) },
                        { val: "20", angle: -Math.PI/2 + (2*Math.PI/3) },
                        { val: "25", angle: -Math.PI/2 + (5*Math.PI/6) },
                        { val: "30", angle: -Math.PI/2 + Math.PI },
                        { val: "35", angle: -Math.PI/2 + (7*Math.PI/6) },
                        { val: "40", angle: -Math.PI/2 + (4*Math.PI/3) },
                        { val: "50", angle: -Math.PI/2 + (5*Math.PI/3) },
                        { val: "55", angle: -Math.PI/2 + (11*Math.PI/6) }
                    ];

                    innerNumbers.forEach(function(item) {
                        ctx.fillText(item.val, cx + Math.cos(item.angle) * r_inner, cy + Math.sin(item.angle) * r_inner);
                    });

                    // Draw inner ticks (every 5 minutes/seconds)
                    ctx.strokeStyle = ColorUtils.applyAlpha(root.activeTextColor, 0.5);
                    ctx.lineWidth = 1.5;
                    for (var j = 0; j < 12; j++) {
                        var innerAngle = -Math.PI / 2 + (j * Math.PI / 6);
                        ctx.beginPath();
                        ctx.moveTo(cx + Math.cos(innerAngle) * (r_inner - 4), cy + Math.sin(innerAngle) * (r_inner - 4));
                        ctx.lineTo(cx + Math.cos(innerAngle) * (r_inner + 4), cy + Math.sin(innerAngle) * (r_inner + 4));
                        ctx.stroke();
                    }
                    ctx.restore();
                }

                // Update canvas on style/color updates
                Connections {
                    target: root
                    function onActiveTextColorChanged() { dialCanvas.requestPaint(); }
                    function onActiveSubtextColorChanged() { dialCanvas.requestPaint(); }
                }
            }

            // Complication 1: Digital Time Pill (9:00 position)
            Rectangle {
                id: digitalTimeComplication
                width: parent.width * 0.28
                height: parent.width * 0.12
                radius: height / 2
                color: ColorUtils.transparentize(Appearance.m3colors.m3shadow, 0.4)
                border.color: ColorUtils.applyAlpha(root.activeTextColor, 0.15)
                border.width: 1
                anchors.left: parent.left
                anchors.leftMargin: parent.width * 0.10
                anchors.verticalCenter: parent.verticalCenter
                z: 2

                StyledText {
                    text: {
                        var hStr = root.hour < 10 ? "0" + root.hour : "" + root.hour;
                        var mStr = root.minute < 10 ? "0" + root.minute : "" + root.minute;
                        return hStr + ":" + mStr;
                    }
                    color: root.activeTextColor
                    font.pixelSize: parent.height * 0.55
                    font.weight: Font.Bold
                    anchors.centerIn: parent
                }
            }

            // Complication 2: Battery Circle (3:00 position)
            Rectangle {
                id: batteryComplication
                width: parent.width * 0.12
                height: width
                radius: width / 2
                color: ColorUtils.transparentize(Appearance.m3colors.m3shadow, 0.4)
                border.color: ColorUtils.applyAlpha(root.activeTextColor, 0.15)
                border.width: 1
                anchors.right: parent.right
                anchors.rightMargin: parent.width * 0.10
                anchors.verticalCenter: parent.verticalCenter
                z: 2

                StyledText {
                    text: Math.round(Battery.percentage * 100)
                    color: root.activeTextColor
                    font.pixelSize: parent.height * 0.46
                    font.weight: Font.Bold
                    anchors.centerIn: parent
                }
            }

            // Complication 3: Steps sub-dial (12:00 position)
            Item {
                id: stepsComplication
                width: parent.width * 0.24
                height: width
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: parent.width * 0.16
                z: 2

                // Circular Progress Background
                MaterialShape {
                    anchors.fill: parent
                    shapeString: "Circle"
                    color: "transparent"
                    borderColor: ColorUtils.applyAlpha(root.activeTextColor, 0.15)
                    borderWidth: 0.08
                }

                // Dotted progress active overlay
                MaterialShape {
                    anchors.fill: parent
                    shapeString: "Circle"
                    color: "transparent"
                    borderColor: root.activeAccentColor
                    borderWidth: 0.08
                }

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 0

                    StyledText {
                        text: "7,789" // Mock steps count since no desktop sensor exists
                        color: root.activeTextColor
                        font.pixelSize: stepsComplication.height * 0.22
                        font.weight: Font.Bold
                        Layout.alignment: Qt.AlignHCenter
                    }

                    MaterialSymbol {
                        text: "directions_run"
                        iconSize: stepsComplication.height * 0.26
                        color: root.activeAccentColor
                        Layout.alignment: Qt.AlignHCenter
                    }
                }
            }

            // Complication 4: Seconds Sub-dial (7:30 position)
            Rectangle {
                id: secondsComplication
                width: parent.width * 0.24
                height: width
                radius: width / 2
                color: "transparent"
                border.color: ColorUtils.applyAlpha(root.activeTextColor, 0.1)
                border.width: 1
                x: parent.width * 0.24
                y: parent.height * 0.58
                z: 2

                // Complication marks
                Repeater {
                    model: 8
                    Item {
                        anchors.fill: parent
                        rotation: index * 45
                        Rectangle {
                            width: 1
                            height: 3
                            color: ColorUtils.applyAlpha(root.activeTextColor, 0.3)
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.top
                        }
                    }
                }

                StyledText {
                    text: "10"
                    color: root.activeTextColor
                    font.pixelSize: parent.height * 0.28
                    font.weight: Font.Bold
                    anchors.right: parent.right
                    anchors.rightMargin: parent.width * 0.15
                    anchors.verticalCenter: parent.verticalCenter
                }

                // Sub-dial center dot
                Rectangle {
                    width: 4
                    height: 4
                    radius: 2
                    color: root.activeTextColor
                    anchors.centerIn: parent
                }

                // Rotating indicator
                Item {
                    anchors.fill: parent
                    rotation: root.second * 6
                    Rectangle {
                        width: 2
                        height: parent.height * 0.4
                        radius: 1
                        color: root.activeAccentColor
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.verticalCenter
                    }
                }
            }

            // Complication 5: Activity badge (4:30 position)
            Rectangle {
                id: activityBadge
                width: parent.width * 0.18
                height: width
                radius: width / 2
                color: ColorUtils.transparentize(Appearance.m3colors.m3shadow, 0.4)
                border.color: ColorUtils.applyAlpha(root.activeTextColor, 0.15)
                border.width: 1
                x: parent.width * 0.58
                y: parent.height * 0.50
                z: 2

                MaterialSymbol {
                    text: "directions_run"
                    iconSize: parent.width * 0.55
                    color: root.activeTextColor
                    anchors.centerIn: parent
                }
            }

            // Complication 6: Date indicators (6:00 position)
            ColumnLayout {
                id: dateIndicatorGroup
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: parent.width * 0.14
                spacing: 2
                z: 2

                StyledText {
                    text: root.dayName
                    color: root.activeSubtextColor
                    font.pixelSize: innerScreen.width * 0.04
                    font.weight: Font.Bold
                    Layout.alignment: Qt.AlignHCenter
                }

                Rectangle {
                    width: innerScreen.width * 0.12
                    height: innerScreen.width * 0.08
                    radius: height / 2
                    color: ColorUtils.transparentize(Appearance.m3colors.m3shadow, 0.4)
                    border.color: ColorUtils.applyAlpha(root.activeTextColor, 0.15)
                    border.width: 1
                    Layout.alignment: Qt.AlignHCenter

                    StyledText {
                        text: root.date
                        color: root.activeTextColor
                        font.pixelSize: parent.height * 0.65
                        font.weight: Font.Bold
                        anchors.centerIn: parent
                    }
                }
            }

            // Top decorative accent icon (12:00 top)
            MaterialSymbol {
                text: "shield"
                iconSize: parent.width * 0.06
                color: root.activeAccentColor
                anchors.top: parent.top
                anchors.topMargin: parent.width * 0.04
                anchors.horizontalCenter: parent.horizontalCenter
                z: 2
            }

            // Bottom decorative accent icon (6:00 bottom)
            MaterialSymbol {
                text: "home"
                iconSize: parent.width * 0.06
                color: root.activeTextColor
                anchors.bottom: parent.bottom
                anchors.bottomMargin: parent.width * 0.04
                anchors.horizontalCenter: parent.horizontalCenter
                z: 2
            }

            // Analog Hands (Center overlay)
            Item {
                id: handsContainer
                anchors.fill: parent
                z: 4

                // Hour Hand capsule
                Item {
                    anchors.fill: parent
                    rotation: root.hourRotation

                    Rectangle {
                        width: parent.width * 0.042
                        height: parent.height * 0.22
                        radius: width / 2
                        color: "transparent"
                        border.color: root.activeTextColor
                        border.width: 2
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.verticalCenter
                    }
                }

                // Minute Hand capsule
                Item {
                    anchors.fill: parent
                    rotation: root.minuteRotation

                    Rectangle {
                        width: parent.width * 0.042
                        height: parent.height * 0.33
                        radius: width / 2
                        color: "transparent"
                        border.color: root.activeTextColor
                        border.width: 2
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.verticalCenter
                    }
                }

                // Center pivot ring
                Rectangle {
                    width: parent.width * 0.05
                    height: width
                    radius: width / 2
                    color: Appearance.m3colors.m3shadow
                    border.color: root.activeSubtextColor
                    border.width: 3
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
