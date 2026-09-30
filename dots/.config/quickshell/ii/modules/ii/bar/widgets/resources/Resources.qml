import qs.modules.ii.bar.popups.resources
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

MouseArea {
    id: root
    property bool borderless: Config.options.bar.borderless
    property bool vertical: false

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

    implicitWidth: rowLayout.implicitWidth
    implicitHeight: Appearance.sizes.baseBarHeight
    hoverEnabled: !BarInteraction.clickToShow

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

        Item {
            id: dockerItem
            property bool shown: Config.options.bar.resources.showDocker && DockerService.dockerRunning
            visible: width > 0
            clip: true
            Layout.leftMargin: shown ? 6 : 0
            implicitWidth: shown ? dockerRow.implicitWidth : 0
            implicitHeight: Appearance.sizes.baseBarHeight

            Behavior on implicitWidth {
                animation: Appearance.animation.barResize.numberAnimation.createObject(this)
            }

            RowLayout {
                id: dockerRow
                spacing: 4
                anchors.centerIn: parent

                CustomIcon {
                    source: "docker.svg"
                    width: 16
                    height: 16
                    colorize: true
                    color: Appearance.colors.colOnLayer1
                }

                StyledText {
                    text: DockerService.runningCount.toString()
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnLayer1
                }
            }
        }
    }

    // Lazy: popup controller is only built on approach (same as ExpressiveSports).
    PopupLoader {
        active: BarInteraction.enablePopups
            && (BarInteraction.clickToShow || root.containsMouse || held)
        sourceComponent: ExpressiveResourcesPopup {
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
}
