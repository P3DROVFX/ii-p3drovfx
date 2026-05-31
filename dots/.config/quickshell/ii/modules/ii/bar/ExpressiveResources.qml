import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

// ─────────────────────────────────────────────────────────────────────────────
// ExpressiveResources — redesign total M3 Expressive
//
// Bar widget: cada recurso ativo = MaterialShape colorido (cookie shape)
// com ícone preenchido + texto percentual flutuante. As cores de shape
// indicam nível de uso via opacidade/saturação — primário para CPU/RAM,
// secundário para disco, terciário para swap/temp.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root
    property bool vertical: false
    property bool alwaysShowAllResources: false
    property bool isMaterial: true // Forced expressive

    implicitWidth:  vertical ? mainCol.implicitWidth  : mainRow.implicitWidth
    implicitHeight: vertical ? mainCol.implicitHeight : mainRow.implicitHeight
    width: implicitWidth
    height: implicitHeight

    // ── Helpers ───────────────────────────────────────────────────────────────
    readonly property int _shapeSize: Appearance.sizes.baseBarHeight - 10
    readonly property int _shapeVSize: Appearance.sizes.verticalBarWidth - 10

    // Color for a resource shape based on usage level
    function shapeColor(pct, baseColor, warnColor) {
        if (pct >= 0.85) return warnColor ?? Appearance.colors.colError
        return baseColor
    }

    Behavior on implicitHeight {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(root)
    }
    Behavior on implicitWidth {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(root)
    }

    // ── Horizontal Layout ─────────────────────────────────────────────────────
    RowLayout {
        id: mainRow
        visible: !root.vertical
        spacing: 4
        anchors.centerIn: parent

        // ── Resource shapes row ───────────────────────────────────────────────
        RowLayout {
            id: resourcesRow
            spacing: 3

            // CPU — Cookie12Sided, primary color family
            Loader {
                id: cpuShapeH
                active: Config.options.bar.resources.alwaysShowCpu
                visible: active
                sourceComponent: ResourceShape {
                    iconName: "memory_alt"
                    percentage: ResourceUsage.cpuUsage
                    baseColor: Appearance.colors.colPrimary
                    onBaseColor: Appearance.colors.colOnPrimary
                    shapeStr: "Cookie12Sided"
                    size: root._shapeSize
                    warningThreshold: Config.options.bar.resources.cpuWarningThreshold
                }
            }

            // RAM — Clover shape, secondary color
            Loader {
                id: ramShapeH
                active: Config.options.bar.resources.alwaysShowRam
                visible: active
                sourceComponent: ResourceShape {
                    iconName: "memory"
                    percentage: ResourceUsage.memoryUsedPercentage
                    baseColor: Appearance.colors.colSecondary
                    onBaseColor: Appearance.colors.colOnSecondary
                    shapeStr: "Clover"
                    size: root._shapeSize
                    warningThreshold: Config.options.bar.resources.memoryWarningThreshold
                }
            }

            // CPU Temp — sunny shape, tertiary
            Loader {
                id: tempShapeH
                active: Config.options.bar.resources.alwaysShowCpuTemp
                visible: active
                sourceComponent: ResourceShape {
                    iconName: "thermostat"
                    percentage: ResourceUsage.cpuTemp / 100
                    baseColor: Appearance.colors.colTertiary
                    onBaseColor: Appearance.colors.colOnTertiary
                    shapeStr: "Sunny"
                    size: root._shapeSize
                    warningThreshold: 80
                }
            }

            // Disk — Cookie7Sided, secondary container tinted
            Loader {
                id: diskShapeH
                active: Config.options.bar.resources.alwaysShowDisk
                visible: active
                sourceComponent: ResourceShape {
                    iconName: "hard_drive"
                    percentage: ResourceUsage.diskUsedPercentage
                    baseColor: Appearance.colors.colSecondaryContainer
                    onBaseColor: Appearance.colors.colOnSecondaryContainer
                    shapeStr: "Cookie7Sided"
                    size: root._shapeSize
                    warningThreshold: 90
                }
            }

            // Swap — Cookie9Sided, tertiary container
            Loader {
                id: swapShapeH
                active: Config.options.bar.resources.alwaysShowSwap
                visible: active
                sourceComponent: ResourceShape {
                    iconName: "swap_horiz"
                    percentage: ResourceUsage.swapUsedPercentage
                    baseColor: Appearance.colors.colTertiaryContainer
                    onBaseColor: Appearance.colors.colOnTertiaryContainer
                    shapeStr: "Cookie9Sided"
                    size: root._shapeSize
                    warningThreshold: Config.options.bar.resources.swapWarningThreshold
                }
            }
        }

        // ── Docker capsule (horizontal) ───────────────────────────────────────
        Loader {
            id: dockerHLoader
            active: Config.options.bar.resources.showDocker
            visible: active
            sourceComponent: DockerCapsule { vertical: false; barHeight: root._shapeSize }
        }
    }

    // ── Vertical Layout ───────────────────────────────────────────────────────
    ColumnLayout {
        id: mainCol
        visible: root.vertical
        spacing: 4
        anchors.centerIn: parent

        ColumnLayout {
            spacing: 3
            Layout.alignment: Qt.AlignHCenter

            Loader {
                active: Config.options.bar.resources.alwaysShowCpu
                visible: active
                Layout.alignment: Qt.AlignHCenter
                sourceComponent: ResourceShape {
                    iconName: "memory_alt"
                    percentage: ResourceUsage.cpuUsage
                    baseColor: Appearance.colors.colPrimary
                    onBaseColor: Appearance.colors.colOnPrimary
                    shapeStr: "Cookie12Sided"
                    size: root._shapeVSize
                    warningThreshold: Config.options.bar.resources.cpuWarningThreshold
                }
            }

            Loader {
                active: Config.options.bar.resources.alwaysShowRam
                visible: active
                Layout.alignment: Qt.AlignHCenter
                sourceComponent: ResourceShape {
                    iconName: "memory"
                    percentage: ResourceUsage.memoryUsedPercentage
                    baseColor: Appearance.colors.colSecondary
                    onBaseColor: Appearance.colors.colOnSecondary
                    shapeStr: "Clover"
                    size: root._shapeVSize
                    warningThreshold: Config.options.bar.resources.memoryWarningThreshold
                }
            }

            Loader {
                active: Config.options.bar.resources.alwaysShowCpuTemp
                visible: active
                Layout.alignment: Qt.AlignHCenter
                sourceComponent: ResourceShape {
                    iconName: "thermostat"
                    percentage: ResourceUsage.cpuTemp / 100
                    baseColor: Appearance.colors.colTertiary
                    onBaseColor: Appearance.colors.colOnTertiary
                    shapeStr: "Sunny"
                    size: root._shapeVSize
                    warningThreshold: 80
                }
            }

            Loader {
                active: Config.options.bar.resources.alwaysShowDisk
                visible: active
                Layout.alignment: Qt.AlignHCenter
                sourceComponent: ResourceShape {
                    iconName: "hard_drive"
                    percentage: ResourceUsage.diskUsedPercentage
                    baseColor: Appearance.colors.colSecondaryContainer
                    onBaseColor: Appearance.colors.colOnSecondaryContainer
                    shapeStr: "Cookie7Sided"
                    size: root._shapeVSize
                    warningThreshold: 90
                }
            }

            Loader {
                active: Config.options.bar.resources.alwaysShowSwap
                visible: active
                Layout.alignment: Qt.AlignHCenter
                sourceComponent: ResourceShape {
                    iconName: "swap_horiz"
                    percentage: ResourceUsage.swapUsedPercentage
                    baseColor: Appearance.colors.colTertiaryContainer
                    onBaseColor: Appearance.colors.colOnTertiaryContainer
                    shapeStr: "Cookie9Sided"
                    size: root._shapeVSize
                    warningThreshold: Config.options.bar.resources.swapWarningThreshold
                }
            }
        }

        // ── Docker capsule (vertical) ─────────────────────────────────────────
        Loader {
            active: Config.options.bar.resources.showDocker
            visible: active
            Layout.alignment: Qt.AlignHCenter
            sourceComponent: DockerCapsule { vertical: true; barHeight: root._shapeVSize }
        }
    }

    // ── Popup declaration ────────────────────────────────────────────────────
    ExpressiveResourcesPopup {
        hoverTarget: hoverArea
        Component.onCompleted: {
            activeChanged.connect(() => {
                if (active) {
                    DockerService.refreshForPopup();
                }
            });
        }
    }

    // ══ ResourceShape inline component ════════════════════════════════════════
    // A MaterialShape cookie with icon + optional percentage arc overlay
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
        // Writable intermediates so animations can target them
        property color currentColor:   isWarning ? Appearance.colors.colError   : baseColor
        property color currentOnColor: isWarning ? Appearance.colors.colOnError : onBaseColor

        implicitWidth: size
        implicitHeight: size

        // Smooth color transition on warning toggle
        Behavior on currentColor {
            ColorAnimation {
                duration: Appearance.animation.elementMoveFast.duration
            }
        }
        Behavior on currentOnColor {
            ColorAnimation {
                duration: Appearance.animation.elementMoveFast.duration
            }
        }

        MaterialShape {
            id: shape
            anchors.fill: parent
            shapeString: rs.shapeStr
            color: rs.currentColor

            // Arc ring overlay — shows proportional fill of usage
            ClippedFilledCircularProgress {
                anchors.centerIn: parent
                implicitSize: rs.size - 6
                lineWidth: 0
                value: rs.percentage
                colPrimary: Qt.rgba(rs.currentOnColor.r, rs.currentOnColor.g, rs.currentOnColor.b, 0.35)
                colSecondary: "transparent"
                enableAnimation: false
                accountForLightBleeding: false
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

        // Percentage label — small pill below the shape
        Rectangle {
            visible: Config.options.bar.resources.showPercentageText
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: -6
            implicitWidth: pctLabel.implicitWidth + 6
            implicitHeight: 12
            radius: Appearance.rounding.full
            color: Qt.rgba(rs.currentColor.r, rs.currentColor.g, rs.currentColor.b, 0.85)

            StyledText {
                id: pctLabel
                anchors.centerIn: parent
                text: Math.round(rs.percentage * 100) + "%"
                font.pixelSize: 8
                font.weight: Font.Black
                color: rs.currentOnColor
            }
        }

        // Warning pulse: scale up/down while isWarning
        PropertyAnimation {
            id: warnPulse
            target: rs
            property: "scale"
            from: 1.0
            to: 1.08
            duration: 700
            easing.type: Easing.InOutSine
            running: false
        }
        // Toggle pulse loop manually — avoid SequentialAnimation on readonly deps
        Timer {
            interval: 700
            repeat: true
            running: rs.isWarning
            onTriggered: {
                rs.scale = (rs.scale > 1.04) ? 1.0 : 1.08
            }
            onRunningChanged: {
                if (!running) rs.scale = 1.0
            }
        }
    }

    // ══ DockerCapsule inline component ════════════════════════════════════════
    component DockerCapsule: Item {
        id: dc
        property bool vertical: false
        property int barHeight: 28

        implicitWidth:  vertical ? (Appearance.sizes.verticalBarWidth - 8) : (countTextH.implicitWidth + iconCircleH.width + 20)
        implicitHeight: vertical ? (countTextV.implicitHeight + iconCircleV.height + 16) : (Appearance.sizes.baseBarHeight - 8)

        Behavior on implicitWidth {
            NumberAnimation {
                duration: Appearance.animation.elementMove.duration
                easing.type: Appearance.animation.elementMove.type
            }
        }
        Behavior on implicitHeight {
            NumberAnimation {
                duration: Appearance.animation.elementMove.duration
                easing.type: Appearance.animation.elementMove.type
            }
        }

        // Horizontal capsule
        Rectangle {
            visible: !dc.vertical
            anchors.fill: parent
            radius: Appearance.rounding.full
            color: Appearance.colors.colSurfaceContainerHigh

            Rectangle {
                id: iconCircleH
                anchors.left: parent.left
                anchors.leftMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                width: parent.height - 8
                height: width
                radius: width / 2
                color: Appearance.colors.colPrimary

                CustomIcon {
                    anchors.centerIn: parent
                    source: "docker.svg"
                    width: 16
                    height: 16
                    colorize: false
                }
            }

            StyledText {
                id: countTextH
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: DockerService.runningCount.toString()
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.Black
                color: Appearance.colors.colOnSurface
            }
        }

        // Vertical capsule
        Rectangle {
            visible: dc.vertical
            anchors.fill: parent
            radius: Appearance.rounding.full
            color: Appearance.colors.colSurfaceContainerHigh

            Rectangle {
                id: iconCircleV
                anchors.top: parent.top
                anchors.topMargin: 4
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - 4
                height: width
                radius: width / 2
                color: Appearance.colors.colPrimary

                CustomIcon {
                    anchors.centerIn: parent
                    source: "docker.svg"
                    width: 16
                    height: 16
                    colorize: false
                }
            }

            StyledText {
                id: countTextV
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 8
                anchors.horizontalCenter: parent.horizontalCenter
                text: DockerService.runningCount.toString()
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.Black
                color: Appearance.colors.colOnSurface
            }
        }
    }

    // Internal MouseArea for hover popups and custom click behaviors
    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: !Config.options.bar.tooltips.clickToShow
        acceptedButtons: Qt.LeftButton | Qt.RightButton
    }
}
