from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
TIMER_DIR = ROOT / "modules/ii/bar/widgets/timer"


class BarTimerWidgetContractTest(unittest.TestCase):
    def read(self, relative_path: str) -> str:
        return (ROOT / relative_path).read_text(encoding="utf-8")

    def test_countdown_uses_the_shared_service_state_and_display_clock(self):
        state = self.read("modules/ii/bar/widgets/timer/TimerBarState.qml")
        service = self.read("services/TimerService.qml")
        # The dashboard's timer widgets moved to modules/common/dashboardWidgets in
        # e24b18ccb so the tablet family could use them without importing ii. The
        # contract is unchanged; only the address is.
        sidebar = self.read("modules/common/dashboardWidgets/timer/CountdownTimer.qml")

        self.assertIn("TimerService.countdowns", state)
        self.assertIn("TimerService.countdownSecondsLeft", state)
        self.assertIn("property int countdownTick: 0", service)
        self.assertIn("root.countdownTick++", service)
        self.assertIn("readonly property int displayTick: TimerService.countdownTick", sidebar)
        self.assertNotIn("property int displayTick: 0", sidebar)

    def test_bar_prioritizes_the_next_unfinished_countdown(self):
        state = self.read("modules/ii/bar/widgets/timer/TimerBarState.qml")

        logic = self.read("modules/ii/bar/widgets/timer/TimerBarLogic.js")
        self.assertIn("TimerBarLogic.prioritizedCountdowns", state)
        self.assertIn(".filter(countdown => !(countdown && countdown.notified))", logic)
        self.assertIn("active.sort((a, b) =>", logic)
        self.assertIn("if (aPaused !== bPaused)", logic)
        self.assertIn("return aLeft - bLeft", logic)
        self.assertIn("primaryCountdown: root.activeCountdowns[0]", state)

    def test_countdown_visibility_is_configurable(self):
        config = self.read("modules/common/Config.qml")
        page = self.read("modules/settings/configs/widgets/IndicatorsConfig.qml")

        self.assertIn("property bool showCountdowns: true", config)
        self.assertIn("Config.options.bar.timers.showCountdowns", page)
        self.assertIn('buttonIcon: "hourglass_top"', page)

    def test_default_and_expressive_styles_are_registered(self):
        config = self.read("modules/common/Config.qml")
        component_registry = self.read("modules/common/BarComponentRegistry.qml")
        style_registry = self.read("modules/ii/bar/registry/BarWidgetRegistry.qml")
        router = self.read("modules/ii/bar/BarComponent.qml")

        self.assertIn('property string timer: "expressive"', config)
        timer_entry = component_registry.split('id: "timer"', 1)[1].split('id: "weather"', 1)[0]
        self.assertIn('styleConfigKey: "timer"', timer_entry)
        self.assertIn("styleOptions: defaultStyleOptions", timer_entry)
        self.assertIn('case "timer":', style_registry)
        self.assertIn("ExpressiveTimerWidget", router)
        self.assertIn("vertical: rootItem.vertical", router)

    def test_every_bar_style_displays_and_controls_countdowns(self):
        files = (
            TIMER_DIR / "TimerWidget.qml",
            TIMER_DIR / "ExpressiveTimerWidget.qml",
            ROOT / "modules/ii/verticalBar/VerticalTimerWidget.qml",
        )

        for path in files:
            body = path.read_text(encoding="utf-8")
            self.assertIn("timerState.showCountdowns", body, path.name)
            self.assertIn("timerState.countdownText", body, path.name)
            self.assertIn("timerState.toggleCountdown()", body, path.name)
            self.assertIn('"hourglass_top"', body, path.name)

    def test_vertical_values_rotate_inward_and_swap_their_measured_axes(self):
        files = (
            TIMER_DIR / "ExpressiveTimerWidget.qml",
            ROOT / "modules/ii/verticalBar/VerticalTimerWidget.qml",
        )

        for path in files:
            body = path.read_text(encoding="utf-8")
            self.assertIn("Config.options.bar.bottom ? 90 : -90", body, path.name)
            self.assertIn("rotation:", body, path.name)
            self.assertIn("timeText.implicitHeight", body, path.name)
            self.assertIn("timeText.implicitWidth", body, path.name)

        vertical = files[1].read_text(encoding="utf-8")
        self.assertIn("Behavior on implicitHeight", vertical)
        self.assertIn("Appearance.animation.barResize.numberAnimation", vertical)

    def test_timer_actions_use_the_shared_ripple_button(self):
        files = (
            TIMER_DIR / "TimerWidget.qml",
            TIMER_DIR / "ExpressiveTimerWidget.qml",
            ROOT / "modules/ii/verticalBar/VerticalTimerWidget.qml",
        )

        for path in files:
            body = path.read_text(encoding="utf-8")
            self.assertIn("RippleButton", body, path.name)
            self.assertNotIn("MouseArea", body, path.name)
            self.assertNotIn("property string icon:", body, path.name)
            self.assertIn("property string iconName:", body, path.name)

    def test_expressive_surface_follows_bar_and_material_contracts(self):
        body = (TIMER_DIR / "ExpressiveTimerWidget.qml").read_text(encoding="utf-8")

        self.assertIn("Appearance.sizes.baseBarHeight - 8", body)
        self.assertIn("Appearance.sizes.verticalBarWidth - 8", body)
        self.assertIn("BarWidgetPalette", body)
        self.assertIn("MaterialShapeWrappedMaterialSymbol", body)
        self.assertIn("id: theme", body)
        self.assertNotIn("id: palette", body)
        self.assertIn("theme.colContainer", body)
        self.assertIn("qs.modules.common.functions", body)
        self.assertIn("ColorUtils.categoryOnColor(theme.colContainer)", body)
        self.assertNotIn("color: theme.colOnContainer", body)
        self.assertIn("theme.colAccent", body)
        self.assertIn("theme.colOnAccent", body)
        self.assertNotIn("border.width", body)
        self.assertNotIn("border.color", body)
        self.assertNotIn("loops: Animation.Infinite", body)
        self.assertNotIn("scale:", body)


if __name__ == "__main__":
    unittest.main()
