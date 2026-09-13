#!/usr/bin/env python3
"""Lock preview contract.

Edit Mode's Lockscreen tab renders the real LockSurface against a stub
context. The stub must never reach PAM or the session, and the preview must
be mounted non-interactive so no island can act.
"""

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PREVIEW = ROOT / "modules/common/panels/lock/LockPreviewContext.qml"
SURFACE = ROOT / "modules/ii/lock/LockSurface.qml"
HOST = ROOT / "modules/ii/background/BackgroundWidgetsWindow.qml"


class LockPreviewContract(unittest.TestCase):
    def test_preview_context_never_reaches_pam_or_session(self):
        src = PREVIEW.read_text()
        for forbidden in ("PamContext", "Quickshell.Services.Pam", "Process {", "loginctl", "systemctl", "LockContext {"):
            self.assertNotIn(forbidden, src, f"LockPreviewContext.qml contains {forbidden!r}")

    def test_preview_context_stubs_the_unlock_entry_points(self):
        src = PREVIEW.read_text()
        for fn in ("tryUnlock", "tryFingerUnlock"):
            self.assertRegex(src, rf"function {fn}\(", f"missing {fn}")

    def test_host_mounts_the_surface_non_interactive(self):
        src = HOST.read_text()
        block = src[src.index("sourceComponent: LockSurface {"):]
        block = block[:block.index("}") + 1]
        self.assertIn("interactive: false", block)
        self.assertIn("context: LockPreviewContext {}", block)

    def test_surface_guards_its_actions_on_interactive(self):
        src = SURFACE.read_text()
        self.assertIn("property bool interactive: true", src)
        guards = len(re.findall(r"if \(!root\.interactive\)", src))
        self.assertGreaterEqual(guards, 8, f"only {guards} interactive guards")
        self.assertIn("readOnly: !root.interactive", src)
        self.assertIn("editingIslands: !root.interactive && GlobalStates.editLockPreview", src)


if __name__ == "__main__":
    unittest.main()
