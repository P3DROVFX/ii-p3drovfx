import unittest
from pathlib import Path


ROOT = Path(__file__).parents[2]
SCRIPTS = ROOT / "scripts"
SOURCE = SCRIPTS / "tray/sni_watcher_src/src/main.rs"


class TrayWatcherContractTests(unittest.TestCase):
    """The tray watcher only helps if it can take the bus name without ever
    letting it go unowned, and if the shell is willing to step aside for it."""

    def test_helper_is_registered_for_building_and_stamping(self):
        helpers = (SCRIPTS / "rust-helpers.sh").read_text(encoding="utf-8")
        self.assertIn('"sni_watcher:tray"', helpers)
        self.assertTrue((SCRIPTS / "tray/README.md").is_file())
        self.assertTrue((SCRIPTS / "tray/sni_watcher_src/Cargo.toml").is_file())

    def test_name_is_requested_queued_and_never_replaced(self):
        source = SOURCE.read_text(encoding="utf-8")
        # An empty flag set is the whole point: the default asks not to be
        # queued, which fails outright while a shell holds the name, and
        # replacing a running shell would leave its host without a watcher.
        self.assertIn("BitFlags::empty()", source)
        self.assertNotIn("ReplaceExisting", source)
        self.assertNotIn("AllowReplacement", source)

    def test_handover_adopts_items_registered_with_the_previous_watcher(self):
        source = SOURCE.read_text(encoding="utf-8")
        self.assertIn("adopt_existing", source)
        # Recent Chromium, so every current Electron app, moved off the path
        # everyone else uses; a sweep that only knows the old one finds nothing.
        self.assertIn("/org/chromium/StatusNotifierItem/1", source)
        self.assertIn("/StatusNotifierItem", source)

    def test_host_registration_is_always_reported(self):
        source = SOURCE.read_text(encoding="utf-8")
        # A client that asks while the shell is starting must not conclude there
        # is no tray: that is what makes Electron tear its own icon down.
        self.assertIn("fn is_status_notifier_host_registered(&self) -> bool {\n        true\n    }", source)

    def test_only_one_instance_holds_the_queue_slot(self):
        source = SOURCE.read_text(encoding="utf-8")
        self.assertIn("INSTANCE_NAME", source)
        self.assertIn("RequestNameFlags::DoNotQueue", source)


if __name__ == "__main__":
    unittest.main()
