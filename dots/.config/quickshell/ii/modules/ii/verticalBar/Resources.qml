import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar as Bar
import qs.services

MouseArea {
    id: root

    property bool alwaysShowAllResources: false
    readonly property color capsuleColor: {
        try {
            return rootItem.colBackground;
        } catch (e) {
            return Appearance.colors.colLayer1;
        }
    }

    implicitWidth: Appearance.sizes.verticalBarWidth
    implicitHeight: mainCol.implicitHeight
    hoverEnabled: !Config.options.bar.tooltips.clickToShow

    ColumnLayout {
        id: mainCol

        spacing: 6
        anchors.centerIn: parent

        // 1. Resources Capsule
        Rectangle {
            id: resourcesCapsule

            implicitWidth: Appearance.sizes.verticalBarWidth - 8
            implicitHeight: colLayout.implicitHeight + 10
            color: Config.options.bar.resources.showDocker ? root.capsuleColor : "transparent"
            radius: Config.options.bar.barGroupStyle === 1 ? Appearance.rounding.windowRounding : Appearance.rounding.full

            ColumnLayout {
                id: colLayout

                spacing: 6
                anchors.centerIn: parent

                Resource {
                    Layout.alignment: Qt.AlignHCenter
                    iconName: "memory"
                    shown: Config.options.bar.resources.alwaysShowRam
                    percentage: ResourceUsage.memoryUsedPercentage
                    warningThreshold: Config.options.bar.resources.memoryWarningThreshold
                }

                Resource {
                    Layout.alignment: Qt.AlignHCenter
                    iconName: "planner_review"
                    shown: Config.options.bar.resources.alwaysShowCpu
                    percentage: ResourceUsage.cpuUsage
                    warningThreshold: Config.options.bar.resources.cpuWarningThreshold
                }

                Resource {
                    Layout.alignment: Qt.AlignHCenter
                    iconName: "thermostat"
                    shown: Config.options.bar.resources.alwaysShowCpuTemp
                    percentage: ResourceUsage.cpuTemp / 100
                }

                Resource {
                    Layout.alignment: Qt.AlignHCenter
                    iconName: "hard_drive"
                    shown: Config.options.bar.resources.alwaysShowDisk
                    percentage: ResourceUsage.diskUsedPercentage
                }

                Resource {
                    Layout.alignment: Qt.AlignHCenter
                    iconName: "swap_horiz"
                    shown: Config.options.bar.resources.alwaysShowSwap
                    percentage: ResourceUsage.swapUsedPercentage
                    warningThreshold: Config.options.bar.resources.swapWarningThreshold
                }

            }

        }

        // 2. Standalone Docker Vertical Capsule
        Rectangle {
            id: dockerCapsuleCol

            property bool shown: Config.options.bar.resources.showDocker && DockerService.dockerRunning

            visible: shown
            clip: true
            implicitWidth: Appearance.sizes.verticalBarWidth - 8
            implicitHeight: shown ? 40 : 0
            color: root.capsuleColor
            radius: Config.options.bar.barGroupStyle === 1 ? Appearance.rounding.windowRounding : Appearance.rounding.full

            ColumnLayout {
                spacing: 2
                anchors.centerIn: parent

                CustomIcon {
                    Layout.alignment: Qt.AlignHCenter
                    source: "docker.svg"
                    width: 18
                    height: 18
                    colorize: true
                    color: Appearance.colors.colOnSurface
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: DockerService.runningCount.toString()
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnSurface
                }

            }

            Behavior on implicitHeight {
                NumberAnimation {
                    duration: Appearance.animation.elementMove.duration
                    easing.type: Appearance.animation.elementMove.type
                }

            }

        }

    }

    Bar.ExpressiveResourcesPopup {
        hoverTarget: root
        Component.onCompleted: {
            activeChanged.connect(() => {
                if (active)
                    DockerService.refreshForPopup();

            });
        }
    }

}
