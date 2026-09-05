"""Contract tests for the Outline and Orbs panel-button designs.

Both are single new designs added beside the existing default/expressive pair,
so the checks here are mostly about the wiring staying complete and about the
two things that made each design work: a visible hover state, and a toggled
state that survives a monochrome palette.
"""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[2]
OUTLINE = ROOT / "modules/ii/bar/widgets/policies/OutlinePoliciesPanelButton.qml"
ORBS = ROOT / "modules/ii/bar/widgets/dashboard/OrbsDashboardPanelButton.qml"
ORB = ROOT / "modules/ii/bar/widgets/dashboard/OrbIconWrapper.qml"
EVERY = (OUTLINE, ORBS, ORB)
# The two files where drawing with a stroke is sanctioned, because "a ring with
# no background" is the request and a fill would be the other design.
STROKE_ALLOWED = (OUTLINE, ORB)


class BarPanelButtonDesignsContractTest(unittest.TestCase):
    def read(self, relative_path: str) -> str:
        return (ROOT / relative_path).read_text(encoding="utf-8")

    def test_both_designs_are_offered_in_the_style_selector(self):
        registry = self.read("modules/common/BarComponentRegistry.qml")

        policies = registry.split('id: "policies_panel_button"', 1)[1].split("\n        {", 1)[0]
        self.assertIn('styleConfigKey: "policies"', policies)
        for style in ("default", "expressive", "outline"):
            self.assertIn(f'value: "{style}"', policies)

        dashboard = registry.split('id: "dashboard_panel_button"', 1)[1].split("\n        {", 1)[0]
        self.assertIn('styleConfigKey: "dashboard"', dashboard)
        for style in ("default", "expressive", "orbs"):
            self.assertIn(f'value: "{style}"', dashboard)

    def test_the_router_reaches_both_designs(self):
        router = self.read("modules/ii/bar/BarComponent.qml")
        self.assertIn('if (style === "outline")', router)
        self.assertIn('if (style === "orbs")', router)
        self.assertIn("OutlinePoliciesPanelButton {", router)
        self.assertIn("OrbsDashboardPanelButton {", router)
        # Both draw their own surface, so no style but `default` may get a chip
        # painted behind it.
        self.assertIn('Config.options.bar.styles.policies !== "default"', router)
        self.assertIn('Config.options.bar.styles.dashboard !== "default"', router)

    def test_the_dashboard_page_can_switch_style_too(self):
        page = self.read("modules/settings/configs/widgets/DashboardButtonConfig.qml")
        self.assertIn("Config.options.bar.styles.dashboard", page)
        self.assertIn('value: "orbs"', page)
        # Both orb treatments are reachable from the page.
        self.assertIn("Config.options.bar.dashboardButton.orbVariant", page)
        self.assertIn('value: "filled"', page)
        self.assertIn('value: "outline"', page)

    def test_each_design_answers_to_hover_and_to_toggle(self):
        outline = OUTLINE.read_text(encoding="utf-8")
        orbs = ORBS.read_text(encoding="utf-8")

        # Hover
        self.assertIn("mouseArea.containsMouse", outline)
        self.assertIn("mouseArea.containsMouse", orbs)
        # Toggle
        self.assertIn("GlobalStates.sidebarLeftOpen", outline)
        self.assertIn("GlobalStates.sidebarRightOpen", orbs)
        for body, name in ((outline, "outline"), (orbs, "orbs")):
            self.assertIn("root.open", body, name)

    def test_the_toggled_state_does_not_rely_on_hue_alone(self):
        # The palette comes from the wallpaper, and a monochrome one can put two
        # families a couple of hex digits apart. The outline ring closes its
        # gaps; the orbs swap which Material pair they are made of. Neither is a
        # hue shift on its own.
        outline = OUTLINE.read_text(encoding="utf-8")
        self.assertIn("property real solidity", outline)
        self.assertIn("dashPattern:", outline)

        orbs = ORBS.read_text(encoding="utf-8")
        self.assertIn("colSecondaryContainer", orbs)
        self.assertIn("colPrimary", orbs)

    def test_one_driver_per_geometry(self):
        outline = OUTLINE.read_text(encoding="utf-8")
        # The dash and the gap are two numbers derived from one, so hover and
        # open can never disagree about how solid the ring currently is.
        self.assertEqual(outline.count("Behavior on solidity"), 1)
        self.assertEqual(outline.count("Behavior on implicitWidth"), 0)
        self.assertEqual(outline.count("Behavior on implicitHeight"), 0)

        orbs = ORBS.read_text(encoding="utf-8")
        self.assertEqual(orbs.count("Behavior on ringWidth"), 1)
        self.assertEqual(orbs.count("Behavior on implicitWidth"), 0)
        self.assertEqual(orbs.count("Behavior on implicitHeight"), 0)

    def test_neither_design_reflows_the_bar_on_hover(self):
        # A hover that changes the widget's length pushes every neighbour along
        # with it. Both designs keep their bounding box and change what is
        # drawn inside it.
        for path in (OUTLINE, ORBS):
            body = path.read_text(encoding="utf-8")
            implicit = "\n".join(line for line in body.splitlines()
                                 if "implicitWidth:" in line or "implicitHeight:" in line)
            self.assertNotIn("containsMouse", implicit, path.name)
            self.assertNotIn("hovered", implicit, path.name)

    def test_the_outline_ring_is_drawn_inside_its_own_box(self):
        # The design this replaced was a filled plate, and in a float-style bar
        # its corners read as spilling out of the group. Half the stroke sits
        # outside the path, so the radius has to give it room.
        outline = OUTLINE.read_text(encoding="utf-8")
        self.assertIn("(root.side - root.ringWidth) / 2 - 1", outline)

    def test_both_orientations_are_drawn(self):
        for path in EVERY:
            body = path.read_text(encoding="utf-8")
            self.assertIn("property bool vertical", body, path.name)
        for path in (OUTLINE, ORBS):
            body = path.read_text(encoding="utf-8")
            self.assertIn("Appearance.sizes.verticalBarWidth", body, path.name)
            self.assertIn("Appearance.sizes.baseBarHeight", body, path.name)

    def test_strokes_stay_in_the_two_files_that_are_allowed_them(self):
        for path in EVERY:
            body = path.read_text(encoding="utf-8")
            if path in STROKE_ALLOWED:
                continue
            self.assertNotIn("border.width", body, path.name)
            self.assertNotIn("border.color", body, path.name)
            self.assertNotIn("strokeWidth", body, path.name)

    def test_no_pulse_and_no_hardcoded_colour(self):
        for path in EVERY:
            body = path.read_text(encoding="utf-8")
            self.assertNotIn("SequentialAnimation on scale", body, path.name)
            self.assertNotIn("SequentialAnimation on opacity", body, path.name)
            for match in re.finditer(r'(?<!\w)#[0-9a-fA-F]{3,8}\b', body):
                line = body[:match.start()].count("\n") + 1
                self.fail(f"{path.name}:{line} hardcodes a colour")

    def test_the_only_infinite_loop_is_a_real_spinner(self):
        for path in EVERY:
            body = path.read_text(encoding="utf-8")
            lines = body.splitlines()
            for index, line in enumerate(lines):
                if "loops: Animation.Infinite" not in line:
                    continue
                window = "\n".join(lines[max(0, index - 8):index + 1])
                self.assertIn("running:", window, f"{path.name}:{index + 1}")

    def test_material_pairs_are_not_crossed(self):
        orbs = ORBS.read_text(encoding="utf-8")
        # Filled discs pair with their own `on` colour; rings have no surface to
        # pair with, so the ink is the ring's own colour.
        self.assertIn("colOnPrimary", orbs)
        self.assertIn("colOnSecondaryContainer", orbs)
        self.assertIn("if (root.outlined)\n            return root.colOrb;", orbs)

        # The bare ring pairs with the bar group background, like every other
        # surfaceless bar widget.
        outline = OUTLINE.read_text(encoding="utf-8")
        self.assertIn("colOnLayer1", outline)

    def test_the_default_policies_button_still_has_a_size(self):
        # It referenced an `id` that does not exist in that file, so both
        # implicit sizes evaluated to undefined and the widget collapsed to
        # nothing: picking the default style made it vanish from the bar.
        body = self.read("modules/ii/bar/widgets/policies/PoliciesPanelButton.qml")
        self.assertNotIn("root.contentScale", body)
        self.assertIn("Math.round(42 * leftSidebarButton.contentScale)", body)
        # And its two icons are alternatives, not a pair.
        self.assertIn("visible: !Config.options.bar.useMaterialSymbolForTopLeftIcon", body)


if __name__ == "__main__":
    unittest.main()
