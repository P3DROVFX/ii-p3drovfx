"""Contracts for avoiding duplicate dock delegates across orientations."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
DOCK_CONTENT = (ROOT / "modules/ii/dock/DockContent.qml").read_text(encoding="utf-8")
DOCK_APP_BUTTON = (ROOT / "modules/ii/dock/DockAppButton.qml").read_text(encoding="utf-8")


class DockOrientationLifecycleContractTests(unittest.TestCase):
    def test_only_the_visible_orientation_owns_the_dock_model(self):
        """A hidden Row/Column still creates Repeater delegates in QML."""
        self.assertIn(
            "model: root.isVertical ? null : dockItemModel",
            DOCK_CONTENT,
        )
        self.assertIn(
            "model: root.isVertical ? dockItemModel : null",
            DOCK_CONTENT,
        )

    def test_island_layers_are_not_instantiated_for_other_dock_styles(self):
        """Floating/transparent docks do not need hidden island delegates."""
        self.assertIn(
            "model: root.islandsStyle ? root.islandSegments : null",
            DOCK_CONTENT,
        )

    def test_tooltip_popup_is_lazy_when_not_in_use(self):
        """Disabled tooltips must not create one PopupWindow per app."""
        self.assertIn(
            "active: (Config.options?.dock?.enableAppTooltip ?? false) || GlobalStates.editMode",
            DOCK_APP_BUTTON,
        )
        self.assertIn("parentItem: root", DOCK_APP_BUTTON)


if __name__ == "__main__":
    unittest.main()
