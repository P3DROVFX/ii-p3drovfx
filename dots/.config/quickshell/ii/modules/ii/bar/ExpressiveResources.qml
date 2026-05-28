import qs.services
import qs.modules.common
import QtQuick
import QtQuick.Layouts

MouseArea {
    id: root
    property bool vertical: false
    property bool alwaysShowAllResources: false
    property bool isMaterial: true // Forced expressive

    implicitWidth: vertical ? Appearance.sizes.verticalBarWidth - 8 : (rowLoader.item?.implicitWidth ?? 0) + 10
    implicitHeight: vertical ? (colLoader.item?.implicitHeight ?? 0) + 12 : Appearance.sizes.baseBarHeight - 8
    hoverEnabled: !Config.options.bar.tooltips.clickToShow

    Behavior on implicitHeight {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(root)
    }

    Rectangle {
        anchors.fill: parent
        color: Appearance.colors.colTertiaryContainer
        radius: Config.options.bar.barGroupStyle === 1 ? Appearance.rounding.windowRounding : Appearance.rounding.full

        Loader {
            id: rowLoader
            active: !root.vertical
            visible: active
            anchors.centerIn: parent
            anchors.leftMargin: 2
            anchors.rightMargin: 4
            sourceComponent: RowLayout {
                spacing: 0
                Resource {
                    iconName: "memory"
                    shown: Config.options.bar.resources.alwaysShowRam
                    percentage: ResourceUsage.memoryUsedPercentage
                    warningThreshold: Config.options.bar.resources.memoryWarningThreshold
                    colorActive: Appearance.colors.colOnTertiaryContainer
                    colorIcon: Appearance.colors.colOnTertiaryContainer
                    colorText: Appearance.colors.colOnTertiaryContainer
                }
                Resource {
                    iconName: "planner_review"
                    shown: Config.options.bar.resources.alwaysShowCpu
                    percentage: ResourceUsage.cpuUsage
                    Layout.leftMargin: shown ? 6 : 0
                    warningThreshold: Config.options.bar.resources.cpuWarningThreshold
                    colorActive: Appearance.colors.colOnTertiaryContainer
                    colorIcon: Appearance.colors.colOnTertiaryContainer
                    colorText: Appearance.colors.colOnTertiaryContainer
                }
                Resource {
                    iconName: "thermostat"
                    shown: Config.options.bar.resources.alwaysShowCpuTemp
                    percentage: ResourceUsage.cpuTemp / 100
                    Layout.leftMargin: shown ? 6 : 0
                    colorActive: Appearance.colors.colOnTertiaryContainer
                    colorIcon: Appearance.colors.colOnTertiaryContainer
                    colorText: Appearance.colors.colOnTertiaryContainer
                }
                Resource {
                    iconName: "hard_drive"
                    shown: Config.options.bar.resources.alwaysShowDisk
                    percentage: ResourceUsage.diskUsedPercentage
                    Layout.leftMargin: shown ? 6 : 0
                    colorActive: Appearance.colors.colOnTertiaryContainer
                    colorIcon: Appearance.colors.colOnTertiaryContainer
                    colorText: Appearance.colors.colOnTertiaryContainer
                }
                Resource {
                    iconName: "swap_horiz"
                    shown: Config.options.bar.resources.alwaysShowSwap
                    percentage: ResourceUsage.swapUsedPercentage
                    Layout.leftMargin: shown ? 6 : 0
                    warningThreshold: Config.options.bar.resources.swapWarningThreshold
                    colorActive: Appearance.colors.colOnTertiaryContainer
                    colorIcon: Appearance.colors.colOnTertiaryContainer
                    colorText: Appearance.colors.colOnTertiaryContainer
                }
            }
        }

        Loader {
            id: colLoader
            active: root.vertical
            visible: active
            anchors.centerIn: parent
            sourceComponent: ColumnLayout {
                spacing: 6
                Layout.margins: 4
                Resource {
                    Layout.alignment: Qt.AlignHCenter
                    iconName: "memory"
                    shown: Config.options.bar.resources.alwaysShowRam
                    percentage: ResourceUsage.memoryUsedPercentage
                    warningThreshold: Config.options.bar.resources.memoryWarningThreshold
                    implicitHeight: 24
                    colorActive: Appearance.colors.colOnTertiaryContainer
                    colorIcon: Appearance.colors.colOnTertiaryContainer
                    colorText: Appearance.colors.colOnTertiaryContainer
                }
                Resource {
                    Layout.alignment: Qt.AlignHCenter
                    iconName: "planner_review"
                    shown: Config.options.bar.resources.alwaysShowCpu
                    percentage: ResourceUsage.cpuUsage
                    warningThreshold: Config.options.bar.resources.cpuWarningThreshold
                    implicitHeight: 24
                    colorActive: Appearance.colors.colOnTertiaryContainer
                    colorIcon: Appearance.colors.colOnTertiaryContainer
                    colorText: Appearance.colors.colOnTertiaryContainer
                }
                Resource {
                    Layout.alignment: Qt.AlignHCenter
                    iconName: "thermostat"
                    shown: Config.options.bar.resources.alwaysShowCpuTemp
                    percentage: ResourceUsage.cpuTemp / 100
                    implicitHeight: 24
                    colorActive: Appearance.colors.colOnTertiaryContainer
                    colorIcon: Appearance.colors.colOnTertiaryContainer
                    colorText: Appearance.colors.colOnTertiaryContainer
                }
                Resource {
                    Layout.alignment: Qt.AlignHCenter
                    iconName: "hard_drive"
                    shown: Config.options.bar.resources.alwaysShowDisk
                    percentage: ResourceUsage.diskUsedPercentage
                    implicitHeight: 24
                    colorActive: Appearance.colors.colOnTertiaryContainer
                    colorIcon: Appearance.colors.colOnTertiaryContainer
                    colorText: Appearance.colors.colOnTertiaryContainer
                }
                Resource {
                    Layout.alignment: Qt.AlignHCenter
                    iconName: "swap_horiz"
                    shown: Config.options.bar.resources.alwaysShowSwap
                    percentage: ResourceUsage.swapUsedPercentage
                    warningThreshold: Config.options.bar.resources.swapWarningThreshold
                    implicitHeight: 24
                    colorActive: Appearance.colors.colOnTertiaryContainer
                    colorIcon: Appearance.colors.colOnTertiaryContainer
                    colorText: Appearance.colors.colOnTertiaryContainer
                }
            }
        }

        Loader {
            active: Config.options.bar.resources.expressivePopup
            source: "ExpressiveResourcesPopup.qml"
            onLoaded: item.hoverTarget = root
        }

        Loader {
            active: !Config.options.bar.resources.expressivePopup
            source: "ResourcesPopup.qml"
            onLoaded: item.hoverTarget = root
        }
    }
}
