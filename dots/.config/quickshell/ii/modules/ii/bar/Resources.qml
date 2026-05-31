import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

MouseArea {
    id: root
    property bool borderless: Config.options.bar.borderless
    property bool vertical: false

    implicitWidth: mainRow.implicitWidth
    implicitHeight: Appearance.sizes.baseBarHeight
    hoverEnabled: !Config.options.bar.tooltips.clickToShow

    readonly property color capsuleColor: {
        try {
            return rootItem.colBackground;
        } catch(e) {
            return Appearance.colors.colLayer1;
        }
    }

    RowLayout {
        id: mainRow
        spacing: 8
        anchors.centerIn: parent

        // 1. Resources Capsule
        Rectangle {
            id: resourcesCapsule
            implicitWidth: rowLayout.implicitWidth + 12
            implicitHeight: Appearance.sizes.baseBarHeight - 10
            color: Config.options.bar.resources.showDocker ? root.capsuleColor : "transparent"
            radius: Config.options.bar.barGroupStyle === 1 ? Appearance.rounding.windowRounding : Appearance.rounding.full

            RowLayout {
                id: rowLayout
                spacing: 0
                anchors.centerIn: parent

                Resource {
                    iconName: "memory"
                    shown: Config.options.bar.resources.alwaysShowRam
                    percentage: ResourceUsage.memoryUsedPercentage
                    warningThreshold: Config.options.bar.resources.memoryWarningThreshold
                }

                Resource {
                    iconName: "planner_review"
                    shown: Config.options.bar.resources.alwaysShowCpu
                    percentage: ResourceUsage.cpuUsage
                    Layout.leftMargin: shown ? 6 : 0
                    warningThreshold: Config.options.bar.resources.cpuWarningThreshold
                }

                Resource {
                    iconName: "thermostat"
                    shown: Config.options.bar.resources.alwaysShowCpuTemp
                    percentage: ResourceUsage.cpuTemp / 100
                    Layout.leftMargin: shown ? 6 : 0
                }

                Resource {
                    iconName: "hard_drive"
                    shown: Config.options.bar.resources.alwaysShowDisk
                    percentage: ResourceUsage.diskUsedPercentage
                    Layout.leftMargin: shown ? 6 : 0
                }

                Resource {
                    iconName: "swap_horiz"
                    shown: Config.options.bar.resources.alwaysShowSwap
                    percentage: ResourceUsage.swapUsedPercentage
                    Layout.leftMargin: shown ? 6 : 0
                    warningThreshold: Config.options.bar.resources.swapWarningThreshold
                }
            }
        }

        // 2. Standalone Docker Capsule
        Rectangle {
            id: dockerCapsule
            property bool shown: Config.options.bar.resources.showDocker
            visible: shown
            clip: true
            implicitWidth: shown ? (dockerRow.implicitWidth + 16) : 0
            implicitHeight: Appearance.sizes.baseBarHeight - 10
            color: root.capsuleColor
            radius: Config.options.bar.barGroupStyle === 1 ? Appearance.rounding.windowRounding : Appearance.rounding.full

            Behavior on implicitWidth {
                NumberAnimation {
                    duration: Appearance.animation.elementMove.duration
                    easing.type: Appearance.animation.elementMove.type
                }
            }

            RowLayout {
                id: dockerRow
                spacing: 6
                anchors.centerIn: parent

                CustomIcon {
                    source: "docker.svg"
                    width: 18
                    height: 18
                    colorize: true
                    color: Appearance.colors.colOnSurface
                }

                StyledText {
                    text: DockerService.runningCount.toString()
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnSurface
                }
            }
        }
    }

    ExpressiveResourcesPopup {
        hoverTarget: root
        Component.onCompleted: {
            activeChanged.connect(() => {
                if (active) {
                    DockerService.refreshForPopup();
                }
            });
        }
    }
}
