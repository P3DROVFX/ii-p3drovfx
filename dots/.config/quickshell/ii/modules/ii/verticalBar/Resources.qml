import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import qs.modules.ii.bar as Bar
import qs.modules.ii.bar.popups.resources

MouseArea {
    id: root

    property bool alwaysShowAllResources: false

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

    implicitWidth: Appearance.sizes.verticalBarWidth
    implicitHeight: colLayout.implicitHeight
    hoverEnabled: !BarInteraction.clickToShow

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

        Item {
            id: dockerItemCol
            property bool shown: Config.options.bar.resources.showDocker && DockerService.dockerRunning
            visible: height > 0
            clip: true
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: Appearance.sizes.verticalBarWidth - 8
            implicitHeight: shown ? dockerCol.implicitHeight : 0

            Behavior on implicitHeight {
                animation: Appearance.animation.barResize.numberAnimation.createObject(this)
            }

            ColumnLayout {
                id: dockerCol
                spacing: 2
                anchors.centerIn: parent

                CustomIcon {
                    Layout.alignment: Qt.AlignHCenter
                    source: "docker.svg"
                    width: 18
                    height: 18
                    colorize: true
                    color: Appearance.colors.colOnLayer1
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
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
