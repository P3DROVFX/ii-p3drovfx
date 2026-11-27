import qs.modules.ii.bar.popups.resources
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes

// ─────────────────────────────────────────────────────────────────────────────
// ExpressiveResources — redesign total M3 Expressive
//
// Bar widget: cada recurso ativo = MaterialShape colorido (cookie shape)
// com ícone preenchido + arco proporcional leve (Shape direto, sem FBO/OpacityMask)
// + texto percentual opcional (lazy). Orientação única em GridLayout.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root
    property bool vertical: false
    property bool alwaysShowAllResources: false
    property bool isMaterial: true // Forced expressive
    property bool popupActive: false

    // Hold only the optional metric work that this bar instance actually
    // renders. CPU/RAM remain the cheap always-on pair in ResourceUsage.
    property bool _temperatureMetricRequested: false
    property bool _diskMetricRequested: false
    property bool _swapMetricRequested: false
    property bool _dockerConsumerRequested: false

    function syncMetricRequests() {
        const resources = Config.options.bar.resources;
        const wantTemperature = !!resources.alwaysShowCpuTemp;
        const wantDisk = !!resources.alwaysShowDisk;
        const wantSwap = !!resources.alwaysShowSwap;
        const wantDocker = !!resources.showDocker;

        if (_temperatureMetricRequested !== wantTemperature) {
            ResourceUsage.requestMetric("temperature", wantTemperature);
            _temperatureMetricRequested = wantTemperature;
        }
        if (_diskMetricRequested !== wantDisk) {
            ResourceUsage.requestMetric("disk", wantDisk);
            _diskMetricRequested = wantDisk;
        }
        if (_swapMetricRequested !== wantSwap) {
            ResourceUsage.requestMetric("swap", wantSwap);
            _swapMetricRequested = wantSwap;
        }
        if (_dockerConsumerRequested !== wantDocker) {
            DockerService.requestConsumer(wantDocker);
            _dockerConsumerRequested = wantDocker;
        }
    }

    Component.onCompleted: syncMetricRequests()
    Component.onDestruction: {
        if (_temperatureMetricRequested)
            ResourceUsage.requestMetric("temperature", false);
        if (_diskMetricRequested)
            ResourceUsage.requestMetric("disk", false);
        if (_swapMetricRequested)
            ResourceUsage.requestMetric("swap", false);
        if (_dockerConsumerRequested)
            DockerService.requestConsumer(false);
    }

    Connections {
        target: Config.options.bar.resources
        function onAlwaysShowCpuTempChanged() { root.syncMetricRequests(); }
        function onAlwaysShowDiskChanged() { root.syncMetricRequests(); }
        function onAlwaysShowSwapChanged() { root.syncMetricRequests(); }
        function onShowDockerChanged() { root.syncMetricRequests(); }
    }

    implicitWidth: vertical ? Appearance.sizes.verticalBarWidth : mainGrid.implicitWidth
    implicitHeight: vertical ? mainGrid.implicitHeight : Appearance.sizes.baseBarHeight
    width: implicitWidth
    height: implicitHeight

    // ── Helpers ───────────────────────────────────────────────────────────────
    readonly property int _activeShapeSize: root.vertical
        ? (Appearance.sizes.verticalBarWidth - 10)
        : (Appearance.sizes.baseBarHeight - 10)

    function shapeColor(pct, baseColor, warnColor) {
        if (pct >= 0.85) return warnColor ?? Appearance.colors.colError
        return baseColor
    }

    Behavior on implicitHeight {
        NumberAnimation {
            duration: Appearance.animation.barResize.duration
            easing.type: Appearance.animation.barResize.type
            easing.bezierCurve: Appearance.animation.barResize.bezierCurve
        }
    }
    Behavior on implicitWidth {
        NumberAnimation {
            duration: Appearance.animation.barResize.duration
            easing.type: Appearance.animation.barResize.type
            easing.bezierCurve: Appearance.animation.barResize.bezierCurve
        }
    }

    // ── Unified Layout (single orientation active, 6 Loaders instead of 12) ───
    GridLayout {
        id: mainGrid
        columns: root.vertical ? 1 : -1
        rowSpacing: 4
        columnSpacing: 4
        anchors.centerIn: parent

        GridLayout {
            id: resourcesGrid
            columns: root.vertical ? 1 : -1
            rowSpacing: 3
            columnSpacing: 3
            Layout.alignment: Qt.AlignCenter

            // CPU — Cookie12Sided, primary color family
            Loader {
                active: Config.options.bar.resources.alwaysShowCpu
                visible: active
                Layout.alignment: Qt.AlignCenter
                sourceComponent: ResourceShape {
                    iconName: root.vertical ? "memory_alt" : "memory"
                    percentage: ResourceUsage.cpuUsage
                    baseColor: Appearance.colors.colPrimary
                    onBaseColor: Appearance.colors.colOnPrimary
                    shapeStr: "Cookie12Sided"
                    size: root._activeShapeSize
                    warningThreshold: Config.options.bar.resources.cpuWarningThreshold
                }
            }

            // RAM — Clover shape, secondary color
            Loader {
                active: Config.options.bar.resources.alwaysShowRam
                visible: active
                Layout.alignment: Qt.AlignCenter
                sourceComponent: ResourceShape {
                    iconName: root.vertical ? "memory" : "memory_alt"
                    percentage: ResourceUsage.memoryUsedPercentage
                    baseColor: Appearance.colors.colSecondary
                    onBaseColor: Appearance.colors.colOnSecondary
                    shapeStr: "Clover"
                    size: root._activeShapeSize
                    warningThreshold: Config.options.bar.resources.memoryWarningThreshold
                }
            }

            // CPU Temp — sunny shape, tertiary
            Loader {
                active: Config.options.bar.resources.alwaysShowCpuTemp
                visible: active
                Layout.alignment: Qt.AlignCenter
                sourceComponent: ResourceShape {
                    iconName: "thermostat"
                    percentage: ResourceUsage.cpuTemp / 100
                    baseColor: Appearance.colors.colTertiary
                    onBaseColor: Appearance.colors.colOnTertiary
                    shapeStr: "Sunny"
                    size: root._activeShapeSize
                    warningThreshold: 80
                }
            }

            // Disk — Cookie7Sided, secondary container tinted
            Loader {
                active: Config.options.bar.resources.alwaysShowDisk
                visible: active
                Layout.alignment: Qt.AlignCenter
                sourceComponent: ResourceShape {
                    iconName: "hard_drive"
                    percentage: ResourceUsage.diskUsedPercentage
                    baseColor: Appearance.colors.colSecondaryContainer
                    onBaseColor: Appearance.colors.colOnSecondaryContainer
                    shapeStr: "Cookie7Sided"
                    size: root._activeShapeSize
                    warningThreshold: 90
                }
            }

            // Swap — Cookie9Sided, tertiary container
            Loader {
                active: Config.options.bar.resources.alwaysShowSwap
                visible: active
                Layout.alignment: Qt.AlignCenter
                sourceComponent: ResourceShape {
                    iconName: "swap_horiz"
                    percentage: ResourceUsage.swapUsedPercentage
                    baseColor: Appearance.colors.colTertiaryContainer
                    onBaseColor: Appearance.colors.colOnTertiaryContainer
                    shapeStr: "Cookie9Sided"
                    size: root._activeShapeSize
                    warningThreshold: Config.options.bar.resources.swapWarningThreshold
                }
            }
        }

        // ── Docker capsule (single active orientation) ────────────────────────
        Loader {
            active: Config.options.bar.resources.showDocker && DockerService.dockerRunning
            visible: active
            Layout.alignment: Qt.AlignCenter
            sourceComponent: DockerCapsule { vertical: root.vertical; barHeight: root._activeShapeSize }
        }
    }

    // ── Popup declaration (lazy) ──────────────────────────────────────────────
    Loader {
        active: BarInteraction.enablePopups
            && (BarInteraction.clickToShow || hoverArea.containsMouse || root.popupActive)
        sourceComponent: ExpressiveResourcesPopup {
            hoverTarget: hoverArea
            onActiveChanged: root.popupActive = active
            Component.onDestruction: root.popupActive = false
            Component.onCompleted: {
                activeChanged.connect(() => {
                    if (active) {
                        DockerService.refreshForPopup();
                    }
                });
            }
        }
    }

    // ══ ResourceShape inline component ════════════════════════════════════════
    component ResourceShape: Item {
        id: rs
        required property string iconName
        required property double percentage
        required property color baseColor
        required property color onBaseColor
        required property string shapeStr
        required property int size
        property int warningThreshold: 100

        readonly property bool isWarning: percentage * 100 >= warningThreshold
        property color currentColor:   isWarning ? Appearance.colors.colError   : baseColor
        property color currentOnColor: isWarning ? Appearance.colors.colOnError : onBaseColor

        implicitWidth: size
        implicitHeight: size

        Behavior on currentColor {
            ColorAnimation { duration: Appearance.animation.elementMoveFast.duration }
        }
        Behavior on currentOnColor {
            ColorAnimation { duration: Appearance.animation.elementMoveFast.duration }
        }

        MaterialShape {
            id: shape
            anchors.fill: parent
            shapeString: rs.shapeStr
            color: rs.currentColor

            // Direct lightweight pie-wedge Shape (no offscreen FBO / OpacityMask)
            Shape {
                id: usageArc
                anchors.centerIn: parent
                width: Math.max(2, rs.size - 6)
                height: width
                readonly property real radius: width / 2
                readonly property real sweep: Math.max(0, Math.min(1, rs.percentage)) * 360
                visible: sweep > 0.5

                ShapePath {
                    id: arcPath
                    strokeColor: "transparent"
                    strokeWidth: 0
                    fillColor: Qt.rgba(rs.currentOnColor.r, rs.currentOnColor.g, rs.currentOnColor.b, 0.35)
                    startX: usageArc.radius
                    startY: usageArc.radius

                    PathAngleArc {
                        moveToStart: false
                        centerX: usageArc.radius
                        centerY: usageArc.radius
                        radiusX: usageArc.radius
                        radiusY: usageArc.radius
                        startAngle: -90
                        sweepAngle: usageArc.sweep
                    }
                    PathLine {
                        x: usageArc.radius
                        y: usageArc.radius
                    }
                }
            }

            MaterialSymbol {
                anchors.centerIn: parent
                text: rs.iconName
                iconSize: Math.round(rs.size * 0.55)
                fill: 1
                color: rs.currentOnColor
                font.weight: Font.DemiBold
            }
        }

        // Percentage label — lazy, only built when enabled in config
        Loader {
            active: Config.options.bar.resources.showPercentageText
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: -2
            sourceComponent: Rectangle {
                implicitWidth: pctLabel.implicitWidth + 6
                implicitHeight: 12
                radius: Appearance.rounding.full
                border.width: 1
                border.color: Qt.rgba(rs.currentOnColor.r, rs.currentOnColor.g, rs.currentOnColor.b, 0.85)
                color: Qt.rgba(rs.currentColor.r, rs.currentColor.g, rs.currentColor.b, 0.85)

                StyledText {
                    id: pctLabel
                    anchors.centerIn: parent
                    text: {
                        if (rs.iconName === "thermostat") {
                            if (Config.options.bar.weather.useUSCS) {
                                return Math.round((rs.percentage * 100) * 1.8 + 32) + "°F";
                            }
                            return Math.round(rs.percentage * 100) + "°C";
                        }
                        return Math.round(rs.percentage * 100) + "%";
                    }
                    font.pixelSize: 8
                    font.weight: Font.Black
                    color: rs.currentOnColor
                }
            }
        }

        Timer {
            interval: 700
            repeat: true
            running: rs.isWarning
            onTriggered: rs.scale = (rs.scale > 1.04) ? 1.0 : 1.08
            onRunningChanged: {
                if (!running) rs.scale = 1.0
            }
        }
    }

    // ══ DockerCapsule inline component (single active orientation) ════════════
    component DockerCapsule: Rectangle {
        id: dc
        property bool vertical: false
        property int barHeight: 28

        implicitWidth: vertical
            ? (Appearance.sizes.verticalBarWidth - 8)
            : (countText.implicitWidth + iconCircle.width + 20)
        implicitHeight: vertical
            ? (countText.implicitHeight + iconCircle.height + 16)
            : (Appearance.sizes.baseBarHeight - 8)

        radius: Appearance.rounding.full
        color: Appearance.colors.colSurfaceContainerHigh

        Behavior on implicitWidth {
            NumberAnimation {
                duration: Appearance.animation.barResize.duration
                easing.type: Appearance.animation.barResize.type
                easing.bezierCurve: Appearance.animation.barResize.bezierCurve
            }
        }
        Behavior on implicitHeight {
            NumberAnimation {
                duration: Appearance.animation.barResize.duration
                easing.type: Appearance.animation.barResize.type
                easing.bezierCurve: Appearance.animation.barResize.bezierCurve
            }
        }

        Rectangle {
            id: iconCircle
            anchors.left: dc.vertical ? undefined : parent.left
            anchors.leftMargin: dc.vertical ? 0 : 4
            anchors.verticalCenter: dc.vertical ? undefined : parent.verticalCenter
            anchors.top: dc.vertical ? parent.top : undefined
            anchors.topMargin: dc.vertical ? 4 : 0
            anchors.horizontalCenter: dc.vertical ? parent.horizontalCenter : undefined
            width: dc.vertical ? (parent.width - 4) : (parent.height - 8)
            height: width
            radius: width / 2
            color: Appearance.colors.colPrimary

            CustomIcon {
                anchors.centerIn: parent
                source: "docker.svg"
                width: 16
                height: 16
                colorize: true
                color: Appearance.colors.colOnPrimary
            }
        }

        StyledText {
            id: countText
            anchors.right: dc.vertical ? undefined : parent.right
            anchors.rightMargin: dc.vertical ? 0 : 10
            anchors.verticalCenter: dc.vertical ? undefined : parent.verticalCenter
            anchors.bottom: dc.vertical ? parent.bottom : undefined
            anchors.bottomMargin: dc.vertical ? 8 : 0
            anchors.horizontalCenter: dc.vertical ? parent.horizontalCenter : undefined
            text: DockerService.runningCount.toString()
            font.pixelSize: dc.vertical ? Appearance.font.pixelSize.smaller : Appearance.font.pixelSize.small
            font.weight: Font.Black
            color: Appearance.colors.colOnSurface
        }
    }

    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: !BarInteraction.clickToShow
    }
}
