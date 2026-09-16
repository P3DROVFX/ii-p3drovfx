import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]


def source(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


class TypeToSearchEditModeContractTests(unittest.TestCase):
    def test_edit_mode_is_a_keyboard_owning_surface(self):
        content = source("services/TypeToSearch.qml")

        self.assertIn("|| GlobalStates.editMode", content)
        self.assertIn("&& !root.shellSurfaceFocused", content)

    def test_edit_mode_gate_is_part_of_the_arming_surface_predicate(self):
        content = source("services/TypeToSearch.qml")
        shell_surface = content.split("readonly property bool shellSurfaceFocused:", 1)[1].split(
            "readonly property bool armed:", 1
        )[0]

        self.assertIn("GlobalStates.editMode", shell_surface)


if __name__ == "__main__":
    unittest.main()
