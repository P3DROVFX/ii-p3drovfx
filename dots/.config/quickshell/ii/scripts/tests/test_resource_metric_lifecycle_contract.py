"""Static contracts for demand-driven resource sampling."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]


class ResourceMetricLifecycleContractTests(unittest.TestCase):
    def read(self, path: str) -> str:
        return (ROOT / path).read_text(encoding="utf-8")

    def test_optional_resource_processes_are_not_boot_processes(self):
        source = self.read("services/ResourceUsage.qml")
        self.assertIn("running: false", source[source.index("id: locateCpuTempPathProc"):])
        self.assertIn("running: false", source[source.index("id: findCpuMaxFreqProc"):])
        self.assertIn("running: false", source[source.index("id: cpuModelProc"):])
        self.assertIn("running: false", source[source.index("id: gpuModelProc"):])
        self.assertIn("running: root.diskMonitoringEnabled", source)
        self.assertIn("running: root.gpuMonitoringEnabled", source)

    def test_cpu_ram_tick_does_not_parse_ungated_metrics(self):
        source = self.read("services/ResourceUsage.qml")
        self.assertIn("if (root.temperatureMonitoringEnabled && root.cpuTempPath)", source)
        self.assertIn("if (root.swapMonitoringEnabled)", source)
        self.assertIn("if (!historyMonitoringEnabled)", source)

    def test_popup_requests_only_metrics_it_can_show(self):
        source = self.read("modules/ii/bar/popups/resources/ExpressiveResourcesPopup.qml")
        service = self.read("services/ResourceUsage.qml")
        self.assertIn("property int resourcePopupMonitoringRequests: 0", service)
        self.assertIn("function requestResourcePopup(on: bool)", service)
        self.assertIn("requestResourcePopup(activeNow)", source)
        self.assertIn('requestMetric("disk", activeNow)', source)
        self.assertIn('requestMetric("temperature", activeNow)', source)
        self.assertIn('requestMetric("hardwareIdentity", activeNow)', source)
        self.assertIn('const wantsSwap = activeNow && !!Config.options.bar.resources.alwaysShowSwap', source)

    def test_docker_requires_a_live_widget_consumer(self):
        docker = self.read("services/DockerService.qml")
        self.assertIn("property int consumerRequests: 0", docker)
        self.assertIn("consumerRequests > 0", docker)
        self.assertIn("function requestConsumer(on: bool)", docker)
        self.assertIn("if (root._enabled)\n                    eventsProc.running = true;", docker)

        for path in (
            "modules/ii/bar/widgets/resources/ExpressiveResources.qml",
            "modules/ii/bar/widgets/resources/Resources.qml",
            "modules/ii/verticalBar/Resources.qml",
        ):
            self.assertIn("DockerService.requestConsumer", self.read(path))


if __name__ == "__main__":
    unittest.main()
